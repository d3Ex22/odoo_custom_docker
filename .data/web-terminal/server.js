const http = require("http");
const fs = require("fs");
const path = require("path");
const { WebSocketServer } = require("ws");
const pty = require("node-pty");

const PORT = parseInt(process.env.WEBTERM_PORT || "7681");
const CMD_PARTS = (process.env.WEBTERM_CMD || "bash").split(" ");
const CMD = CMD_PARTS[0];
const CMD_ARGS = CMD_PARTS.slice(1);

const CONFIG = JSON.stringify({
    title: process.env.WEBTERM_TITLE || "Terminal",
    fontFamily: process.env.WEBTERM_FONT_FAMILY || '"JetBrainsMono Nerd Font", Consolas, Menlo, Ubuntu, monospace',
    fontSize: parseInt(process.env.WEBTERM_FONT_SIZE || "14"),
    fontWeight: parseInt(process.env.WEBTERM_FONT_WEIGHT || "400"),
    fontWeightBold: parseInt(process.env.WEBTERM_FONT_WEIGHT_BOLD || "700"),
    scrollback: parseInt(process.env.WEBTERM_SCROLLBACK || "50000", 10),
    theme: JSON.parse(process.env.WEBTERM_THEME || "{}"),
    msgConnecting: process.env.WEBTERM_MSG_CONNECTING || "Connecting...",
    msgReconnecting: process.env.WEBTERM_MSG_RECONNECTING || "Reconnecting...",
    msgCopied: process.env.WEBTERM_MSG_COPIED || "Copied",
    msgCopyFailed: process.env.WEBTERM_MSG_COPY_FAILED || "Copy blocked — release mouse or press Cmd+C",
    overlayColor: process.env.WEBTERM_OVERLAY_COLOR || "#aaaaaa",
    overlayBg: process.env.WEBTERM_OVERLAY_BG || "rgba(0, 0, 0, 0.7)",
});

const MIME = {
    ".html": "text/html",
    ".js": "application/javascript",
    ".css": "text/css",
};

const PUBLIC = path.join(__dirname, "public");

function serveStatic(req, res) {
    if (req.url === "/config") {
        res.writeHead(200, { "Content-Type": "application/json" });
        res.end(CONFIG);
        return;
    }

    if (req.url === "/health") {
        res.writeHead(200, { "Content-Type": "text/plain" });
        res.end("ok");
        return;
    }

    if (req.url === "/favicon.ico") {
        res.writeHead(204);
        res.end();
        return;
    }

    let filePath = req.url === "/" ? "/index.html" : req.url;
    filePath = path.resolve(PUBLIC, filePath.replace(/^\/+/, ""));

    if (!filePath.startsWith(PUBLIC + path.sep) && filePath !== PUBLIC) {
        res.writeHead(403);
        res.end();
        return;
    }

    const ext = path.extname(filePath);
    const headers = { "Content-Type": MIME[ext] || "application/octet-stream" };
    if (ext === ".js" || ext === ".html") {
        headers["Cache-Control"] = "no-cache";
    }
    fs.readFile(filePath, (err, data) => {
        if (err) {
            res.writeHead(404);
            res.end("Not found");
            return;
        }
        res.writeHead(200, headers);
        res.end(data);
    });
}

const server = http.createServer(serveStatic);
const wss = new WebSocketServer({ server, path: "/ws" });

wss.on("connection", (ws) => {
    const proc = pty.spawn(CMD, CMD_ARGS, {
        name: "xterm-256color",
        cols: 80,
        rows: 24,
        cwd: process.env.HOME || "/",
        env: Object.assign({}, process.env, { TERM: "xterm-256color" }),
    });

    proc.onData((data) => {
        try { ws.send(data); } catch (_) {}
    });

    proc.onExit(() => {
        try { ws.close(); } catch (_) {}
    });

    const DA_RE = /\x1b\[\?[\d;]*c/g;

    ws.on("message", (raw) => {
        let msg;
        try { msg = JSON.parse(raw); } catch (_) {
            proc.write(raw.toString().replace(DA_RE, ""));
            return;
        }
        if (msg.type === "input" && typeof msg.data === "string") {
            proc.write(msg.data.replace(DA_RE, ""));
        } else if (msg.type === "resize" && msg.cols > 0 && msg.rows > 0) {
            proc.resize(msg.cols, msg.rows);
        }
    });

    ws.on("close", () => {
        try { proc.kill(); } catch (_) {}
    });
});

server.listen(PORT, "0.0.0.0");
