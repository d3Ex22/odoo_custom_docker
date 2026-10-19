#!/usr/bin/env python3
"""Web terminal server: serves the xterm.js client of public/ and bridges a
WebSocket (/ws) to a pty running WEBTERM_CMD (tmux attach in both containers).

Standard library only (no Node.js, no native module in the images): HTTP via
http.server, the WebSocket framing of RFC 6455 written out below, pty.fork().
Configuration through environment variables: WEBTERM_* (.config/terminal.conf,
exported by the entrypoints) and the TERM_* colors of lib/theme.sh.
"""
import base64
import codecs
import fcntl
import hashlib
import json
import os
import pty
import re
import shlex
import signal
import struct
import sys
import termios
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("WEBTERM_PORT", "7681"))
CMD = shlex.split(os.environ.get("WEBTERM_CMD", "bash"))
PUBLIC = os.path.join(os.path.dirname(os.path.realpath(__file__)), "public")
MIME = {".html": "text/html", ".js": "application/javascript", ".css": "text/css"}
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
# xterm.js theme key → TERM_* variable of lib/theme.sh
THEME_KEYS = {
    "background": "BG", "foreground": "FG", "cursor": "CURSOR", "cursorAccent": "BG",
    "selectionBackground": "SELECTION", "black": "BLACK", "red": "RED", "green": "GREEN",
    "yellow": "YELLOW", "blue": "BLUE", "magenta": "MAGENTA", "cyan": "CYAN", "white": "WHITE",
    "brightBlack": "BRIGHT_BLACK", "brightRed": "BRIGHT_RED", "brightGreen": "BRIGHT_GREEN",
    "brightYellow": "BRIGHT_YELLOW", "brightBlue": "BRIGHT_BLUE", "brightMagenta": "BRIGHT_MAGENTA",
    "brightCyan": "BRIGHT_CYAN", "brightWhite": "BRIGHT_WHITE",
}


def config():
    g = os.environ.get
    theme = {k: g(f"TERM_{v}") for k, v in THEME_KEYS.items() if g(f"TERM_{v}")}
    return json.dumps({
        "title": g("WEBTERM_TITLE", "Terminal"),
        "fontFamily": g("WEBTERM_FONT_FAMILY", '"JetBrainsMono Nerd Font", Consolas, Menlo, Ubuntu, monospace'),
        "fontSize": int(g("WEBTERM_FONT_SIZE", "14")),
        "fontWeight": int(g("WEBTERM_FONT_WEIGHT", "400")),
        "fontWeightBold": int(g("WEBTERM_FONT_WEIGHT_BOLD", "700")),
        "scrollback": int(g("WEBTERM_SCROLLBACK", "50000")),
        "theme": theme,
        "msgConnecting": "Connecting...",
        "msgReconnecting": "Reconnecting...",
        "msgCopied": "Copied",
        "msgCopyFailed": "Copy blocked — release mouse or press Cmd+C",
        "overlayColor": theme.get("brightBlack", "#aaaaaa"),
        "overlayBg": theme.get("background", "#000000") + "b3",
    }).encode()


# xterm.js answers the queries tmux sends on attach (DA1/DA2, XTVERSION, DECRQM,
# DSR, window and color reports). tmux 3.2 only understands the DA1 reply and
# forwards the others to the active pane as typed text ("0;276;0c" sitting in
# the prompt): drop every reply before the pty.
REPLY_RE = re.compile("|".join([
    r"\x1b\[\?[\d;]*c",                       # DA1  \e[?1;2c
    r"\x1b\[>[\d;]*c",                        # DA2  \e[>0;276;0c
    r"\x1b\[\?[\d;]*\$?[nyu]",                # DECRQM \e[?2026;2$y, DSR \e[?0n, kitty \e[?0u
    r"\x1b\[\d*n",                            # DSR  \e[0n
    r"\x1b\[[\d;]+R",                         # CPR  \e[24;80R
    r"\x1b\[[\d;]+t",                         # window report \e[8;24;80t
    r"\x1bP[>!|][^\x1b]*\x1b\\",              # XTVERSION / DA3  \eP>|xterm.js(5.5.0)\e\\
    r"\x1b\]1[0-9];[^\x07\x1b]*(?:\x07|\x1b\\)",  # color reports \e]11;rgb:...\e\\
]))


class WebSocket:
    """Minimal server side of RFC 6455 over an already upgraded socket."""

    def __init__(self, sock):
        self.sock = sock
        self.lock = threading.Lock()

    def _recv(self, n):
        buf = b""
        while len(buf) < n:
            chunk = self.sock.recv(n - len(buf))
            if not chunk:
                raise ConnectionError
            buf += chunk
        return buf

    def recv(self):
        """Return (opcode, payload) of the next message; fragments are joined."""
        opcode, payload = None, b""
        while True:
            b1, b2 = self._recv(2)
            fin, op, masked, length = b1 & 0x80, b1 & 0x0F, b2 & 0x80, b2 & 0x7F
            if length == 126:
                length = struct.unpack("!H", self._recv(2))[0]
            elif length == 127:
                length = struct.unpack("!Q", self._recv(8))[0]
            mask = self._recv(4) if masked else None
            data = self._recv(length)
            if mask:
                data = bytes(c ^ mask[i % 4] for i, c in enumerate(data))
            if op >= 8:                      # control frame: never fragmented
                return op, data
            if op:
                opcode = op
            payload += data
            if fin:
                return opcode, payload

    def send(self, data, opcode=1):
        if isinstance(data, str):
            data = data.encode()
        head = bytes([0x80 | opcode])
        n = len(data)
        if n < 126:
            head += bytes([n])
        elif n < 65536:
            head += bytes([126]) + struct.pack("!H", n)
        else:
            head += bytes([127]) + struct.pack("!Q", n)
        with self.lock:
            self.sock.sendall(head + data)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):      # quiet: the terminal's own output is enough
        pass

    def _reply(self, code, body=b"", ctype="text/plain", extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path == "/ws" and self.headers.get("Upgrade", "").lower() == "websocket":
            return self.websocket()
        if path == "/config":
            return self._reply(200, config(), "application/json")
        if path == "/health":
            return self._reply(200, b"ok")
        if path == "/favicon.ico":
            return self._reply(204)
        rel = "index.html" if path == "/" else path.lstrip("/")
        full = os.path.realpath(os.path.join(PUBLIC, rel))
        if not full.startswith(PUBLIC + os.sep):
            return self._reply(403)
        try:
            with open(full, "rb") as fh:
                body = fh.read()
        except OSError:
            return self._reply(404, b"Not found")
        ext = os.path.splitext(full)[1]
        extra = {"Cache-Control": "no-cache"} if ext in (".js", ".html") else None
        self._reply(200, body, MIME.get(ext, "application/octet-stream"), extra)

    # ---- /ws: one pty per connection ------------------------------------
    def websocket(self):
        key = self.headers.get("Sec-WebSocket-Key", "")
        accept = base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()
        self.send_response(101, "Switching Protocols")
        self.send_header("Upgrade", "websocket")
        self.send_header("Connection", "Upgrade")
        self.send_header("Sec-WebSocket-Accept", accept)
        self.end_headers()
        self.close_connection = True
        ws = WebSocket(self.connection)

        pid, fd = pty.fork()
        if pid == 0:                      # child: the terminal program
            os.environ["TERM"] = "xterm-256color"
            os.chdir(os.environ.get("HOME", "/"))
            try:
                os.execvp(CMD[0], CMD)
            finally:
                os._exit(1)
        resize(fd, 24, 80)
        self.connection.settimeout(None)

        def pump():                       # pty → browser, as text (utf-8 safe across chunks)
            decoder = codecs.getincrementaldecoder("utf-8")(errors="replace")
            try:
                while True:
                    data = os.read(fd, 65536)
                    if not data:
                        break
                    ws.send(decoder.decode(data))
            except OSError:
                pass
            try:
                ws.send(b"", 8)
            except OSError:
                pass
            try:
                self.connection.shutdown(2)
            except OSError:
                pass

        threading.Thread(target=pump, daemon=True).start()
        try:
            while True:
                op, payload = ws.recv()
                if op == 8:
                    break
                if op == 9:
                    ws.send(payload, 10)
                    continue
                if op not in (1, 2):
                    continue
                text = payload.decode("utf-8", "replace")
                try:
                    msg = json.loads(text)
                except ValueError:
                    os.write(fd, REPLY_RE.sub("", text).encode())
                    continue
                if msg.get("type") == "input" and isinstance(msg.get("data"), str):
                    os.write(fd, REPLY_RE.sub("", msg["data"]).encode())
                elif msg.get("type") == "resize":
                    cols, rows = msg.get("cols"), msg.get("rows")
                    if isinstance(cols, int) and isinstance(rows, int) and cols > 0 and rows > 0:
                        resize(fd, rows, cols)
        except (ConnectionError, OSError):
            pass
        finally:
            try:
                os.kill(pid, signal.SIGHUP)
            except OSError:   # already exited
                pass
            try:
                os.close(fd)
            except OSError:
                pass
            try:
                os.waitpid(pid, 0)
            except ChildProcessError:
                pass


def resize(fd, rows, cols):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except OSError:
        pass


if __name__ == "__main__":
    signal.signal(signal.SIGCHLD, signal.SIG_DFL)
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    server.daemon_threads = True
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        sys.exit(0)
