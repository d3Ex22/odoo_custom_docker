#!/usr/bin/env python3
"""Hub of the shared proxy: one page, one tab per project.

Served on the bare hosts (odoo.docker.localhost, logs., utils., mcp., mail.)
by the odoo_proxy stack, stdlib only. Running projects come from the Traefik
API (routers <project>-odoo|logs|utils|mcp|mail), their live state from the
status endpoint of their utils container (http://<project>_utils:8300/status,
written every 2s by status.py), the projects seen once on this machine from
the registry kept in the odoo_env_meta volume (/var/odoo-env/projects/<name>
= host folder). Actions run docker compose in a throwaway docker:cli container
(start, stop, restart, first-start wizard) or a utils command in the project's
utils container (restart odoo, env-update, rebuild typed in its terminal).
Each action is journaled per project (odoo_env_meta volume, shown in the menu).

The Config panel edits the project's .env from a form generated from the file,
which therefore follows one layout:
    # ====  /  # TITLE  /  # ====          section
    # ----  /  # TITLE  /  # desc…  /  # ----   sub-section (desc optional)
    # help lines right above KEY=value     one setting (contiguous keys share them)
    # comment block followed by a blank line    free note
The last help line may be a marker '#@ optional auto type=bool apply=r|compose|rebuild
wipe=db': badges, toggle, and the severity of a change (blue restart / orange
rebuild / red database wipe) that also drives the 'env changed' flag of a tab.

The page gets its state pushed over /api/events (server-sent events: a thread
polls Traefik + the status endpoints every second and emits on change) and acts
through POST /api/* carrying the token embedded in the page (X-Hub-Token).
"""
import collections
import json
import mimetypes
import os
import queue
import re
import secrets
import subprocess
import threading
import time
import urllib.request
from urllib.parse import unquote
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

TRAEFIK_API = os.environ.get("TRAEFIK_API", "http://traefik:8080/api/http/routers")
HUB_HOST = os.environ.get("HUB_HOST", "odoo.docker.localhost")
REGISTRY = os.environ.get("REGISTRY", "/var/odoo-env/projects")
COMPOSE_IMAGE = os.environ.get("COMPOSE_IMAGE", "docker:cli")
STATIC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "static")
JOURNAL_DIR = os.environ.get("JOURNAL_DIR", os.path.join(os.path.dirname(REGISTRY), "journal"))
COLORS_DIR = os.path.join(os.path.dirname(REGISTRY), "colors")       # <name>: primary colour, written by the utils entrypoint
PROGRESS_DIR = os.path.join(os.path.dirname(REGISTRY), "progress")   # <name>: step of a running 'rebuild' (rebuild.sh)
UTILS_ROOT = "/home/utils/odoo_custom_docker"   # project folder inside its utils container
VIEWS = ("odoo", "logs", "utils", "mail", "mcp")
STARTS = {}            # project → {"state": "starting"|"restarting"|"stopping"|"started"|"stopped"|"error", "log": str, "detail": str}
STARTS_LOCK = threading.Lock()
JOURNAL_LOCK = threading.Lock()
POOL = ThreadPoolExecutor(max_workers=8)
TOKEN = secrets.token_urlsafe(24)   # per process; the page carries it, every POST must send it back
mimetypes.add_type("font/woff2", ".woff2")


def registry():
    """{name: host folder} of the projects started once on this machine."""
    out = {}
    try:
        for name in os.listdir(REGISTRY):
            with open(os.path.join(REGISTRY, name)) as f:
                path = f.read().strip()
            if path and path != "/unknown":
                out[name] = path
    except OSError:
        pass
    return out


def running():
    """{name: {view: host}} from the Traefik routers."""
    try:
        with urllib.request.urlopen(TRAEFIK_API, timeout=2) as r:
            routers = json.load(r)
    except Exception:
        return {}
    found = {}
    for rt in routers:
        name = rt.get("name", "")
        if not name.endswith("@docker") or rt.get("status") != "enabled":
            continue
        base = name[: -len("@docker")]
        for view in VIEWS:
            if base.endswith("-" + view):
                host = re.search(r"Host\(`([^`]+)`\)", rt.get("rule", ""))
                if host:
                    found.setdefault(base[: -len(view) - 1], {})[view] = host.group(1)
                break
    return found


def status(name):
    try:
        with urllib.request.urlopen(f"http://{name}_utils:8300/status", timeout=0.8) as r:
            return json.load(r)
    except Exception:
        return None


def projects():
    """Running projects (with hosts and live status) + known stopped ones (+ the last journal entry)."""
    live = running()
    known = registry()
    names = sorted(set(live) | set(known))
    statuses = dict(zip(names, POOL.map(lambda n: status(n) if n in live else None, names)))
    out = []
    for n in names:
        hosts = live.get(n, {})
        with STARTS_LOCK:
            start = STARTS.get(n)
            if start and (start["state"] in ("starting", "started") if n in live else start["state"] == "stopped"):
                STARTS.pop(n, None); start = None
        last = journal_load(n)
        if start and "t0" in start:   # seconds elapsed, so the page can show a timer (building images takes minutes)
            start = dict(start, elapsed=int(time.time() - start["t0"]))
        out.append({"name": n, "running": n in live, "dir": known.get(n), "status": statuses.get(n),
                    "start": start, "last": last[-1] if last else None, "color": color(n), "progress": progress(n),
                    **{v: hosts.get(v) for v in VIEWS}})
    return out


def in_project(name, path, cmd, stdin=None, timeout=120, live=None):
    """Run a shell command in the project folder: in its utils container when it runs (fast), else in a throwaway container."""
    if name and name in (running() if live is None else live):
        args = ["docker", "exec", "-i", "-e", f"HUB_PROJECT_DIR={UTILS_ROOT}", f"{name}_utils", "sh", "-c", cmd]
    else:
        args = ["docker", "run", "--rm", "-i", "-e", "HUB_PROJECT_DIR=/p", "-v", f"{path}:/p", COMPOSE_IMAGE, "sh", "-c", cmd]
    proc = subprocess.run(args, input=stdin, capture_output=True, text=True, timeout=timeout)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout).strip()[-500:] or f"command failed: {cmd}")
    return proc.stdout


def env_read(path, name=None, live=None):
    return in_project(name, path, 'cat "$HUB_PROJECT_DIR/.env"', live=live)


def env_write(path, text, name=None):
    # 'cat >' keeps the inode: the ./.env file bind-mounted in the odoo container stays valid
    in_project(name, path, 'cat > "$HUB_PROJECT_DIR/.env"', stdin=text)


SETUP_KEYS = ("ODOO_VERSION", "ENTERPRISE_PATH", "ODOO_PATH", "ADDONS_PATH", "SELECTED_DB", "SSH_PATH")


def env_values(text, keys):
    """{KEY: value} of `keys` found in `text`, unquoted (reverse of env_apply)."""
    out = {}
    for m in re.finditer(r"^([A-Z_][A-Z0-9_]*)=(.*)$", text, re.M):
        if m.group(1) in keys:
            v = m.group(2)
            if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
                v = v[1:-1].replace("'\\''", "'") if v[0] == "'" else v[1:-1]
            out[m.group(1)] = v
    return out


def setup_info(name, known):
    """Current critical values + suggestions from the sibling projects (same parent folder, same Odoo version)."""
    live = running()
    mine = env_values(env_read(known[name], name, live), SETUP_KEYS)
    parent = os.path.dirname(known[name])
    suggest = {}
    for other, d in sorted(known.items()):
        if other == name or os.path.dirname(d) != parent:
            continue
        st = status(other) if other in live else None
        if st:
            vals = {"ENTERPRISE_PATH": st.get("enterprise_path"), "ODOO_PATH": st.get("odoo_path"),
                    "version": st.get("odoo_version"), "verified": st.get("enterprise") == "ok"}
        else:
            try:
                ev = env_values(env_read(d, other, live), ("ODOO_VERSION", "ENTERPRISE_PATH", "ODOO_PATH"))
            except Exception:  # noqa: BLE001
                continue
            vals = {"ENTERPRISE_PATH": ev.get("ENTERPRISE_PATH"), "ODOO_PATH": ev.get("ODOO_PATH"),
                    "version": ev.get("ODOO_VERSION"), "verified": False}
        if vals["version"] != mine.get("ODOO_VERSION"):
            continue
        for k in ("ENTERPRISE_PATH", "ODOO_PATH"):
            if vals.get(k) and (k not in suggest or (vals["verified"] and not suggest[k]["verified"])):
                suggest[k] = {"value": vals[k], "from": other, "verified": vals["verified"]}
    return {"env": mine, "suggest": suggest, "dir": known[name]}


def setup_apply(name, path, values):
    env_write(path, env_apply(env_read(path, name), values), name)
    in_project(name, path, 'mkdir -p "$HUB_PROJECT_DIR/.data/volumes/shared" && touch "$HUB_PROJECT_DIR/.data/volumes/shared/.setup_done"')


def env_apply(text, values):
    """Replace the KEY=value lines of `text` for the keys of `values` (same quoting rule as set_env_value)."""
    out = []
    for line in text.split("\n"):
        m = re.match(r"^([A-Z_][A-Z0-9_]*)=(.*)$", line)
        if m and m.group(1) in values:
            v = values[m.group(1)]
            if v and not re.fullmatch(r"[A-Za-z0-9_.,:/=@+~-]+", v):
                v = "'" + v.replace("'", "'\\''") + "'"
            line = f"{m.group(1)}={v}"
        out.append(line)
    return "\n".join(out)


def busy(name):
    return (STARTS.get(name) or {}).get("state") in ("starting", "restarting", "stopping")


def compose_run(name, path, state, *commands, done="started"):
    """Run docker compose commands in the project folder; STARTS[name] follows (state → done | error).
    No-op when a run is already in progress for the project."""
    t0 = time.time()
    with STARTS_LOCK:
        if busy(name):
            return
        STARTS[name] = {"state": state, "log": "", "t0": t0}
    # compose expands '~' of .env paths (SSH_PATH=~/.ssh) with HOME: give it the host user's home, not /root
    home = re.match(r"^(/(?:Users|home)/[^/]+)/", path)
    base = ["docker", "run", "--rm", "-v", "/var/run/docker.sock:/var/run/docker.sock",
            *(["-e", f"HOME={home.group(1)}"] if home else []),
            "-v", f"{path}:{path}", "-w", path, COMPOSE_IMAGE, "docker", "compose"]
    label = "docker compose " + " · ".join(" ".join(a) for a in commands)
    try:
        for args in commands:
            lines = []
            with subprocess.Popen(base + list(args), stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True) as proc:
                for line in proc.stdout:   # the tab shows where a long run is (image build steps, containers)
                    lines.append(line)
                    detail = progress_detail(line)
                    if detail and name in STARTS:
                        STARTS[name]["detail"] = detail
            if proc.returncode != 0:
                log = "".join(lines).strip()[-1500:]
                STARTS[name] = {"state": "error", "log": log}
                journal(name, label, False, log[-300:])
                return
        STARTS[name] = {"state": done, "log": ""}
        journal(name, label, True, f"{time.time() - t0:.0f}s")
    except Exception as exc:  # noqa: BLE001
        STARTS[name] = {"state": "error", "log": str(exc)}
        journal(name, label, False, str(exc))


def progress_detail(line):
    """Short label from a docker compose output line: '#12 [odoo builder 4/9] RUN …' → 'building odoo 4/9',
    'Container demo_db  Starting' → 'demo_db starting', 'odoo Pulling' → 'pulling odoo'. None for the rest."""
    m = re.match(r"^#\d+ \[(\S+)(?: \S+)* (\d+)/(\d+)\]", line)
    if m:
        return f"building {m.group(1)} {m.group(2)}/{m.group(3)}"
    m = re.match(r"^\s*Container (\S+)\s+(\w+)", line)
    if m:
        return f"{m.group(1)} {m.group(2).lower()}"
    m = re.match(r"^\s*(\S+) Pulling", line)
    if m:
        return f"pulling {m.group(1)}"
    return None


def progress(name):
    """Step of a 'rebuild' typed in the utils terminal (/var/odoo-env/progress/<name>: '<epoch>\\n<label>',
    written by rebuild.sh while it builds; survives the utils container being recreated)."""
    path = os.path.join(PROGRESS_DIR, name)
    try:
        if time.time() - os.path.getmtime(path) > 300:   # left behind by an interrupted run
            return None
        with open(path) as f:
            t0, label = f.read().split("\n", 1)
        return {"label": label.strip(), "elapsed": int(time.time() - float(t0))}
    except (OSError, ValueError):
        return None


def color(name):
    """Primary colour of the project (/var/odoo-env/colors/<name>, written by its utils entrypoint); None → the page hashes the name."""
    try:
        with open(os.path.join(COLORS_DIR, name)) as f:
            c = f.read().strip()
        return c if re.fullmatch(r"#[0-9a-fA-F]{6}", c) else None
    except OSError:
        return None


# ---- journal: last actions per project, kept in the shared volume ----
JOURNAL = {}   # name → deque of {t, action, ok, detail}


def journal_path(name):
    return os.path.join(JOURNAL_DIR, name + ".json")


def journal_load(name):
    if name not in JOURNAL:
        try:
            with open(journal_path(name)) as fh:
                JOURNAL[name] = collections.deque(json.load(fh), maxlen=30)
        except (OSError, ValueError):
            JOURNAL[name] = collections.deque(maxlen=30)
    return JOURNAL[name]


def journal(name, action, ok=True, detail=""):
    with JOURNAL_LOCK:
        entries = journal_load(name)
        entries.append({"t": int(time.time()), "action": action, "ok": bool(ok), "detail": str(detail)[:300]})
        try:
            os.makedirs(JOURNAL_DIR, exist_ok=True)
            with open(journal_path(name), "w") as fh:
                json.dump(list(entries), fh)
        except OSError:
            pass
    events.poke()   # the menus show the last entry


def utils_command(name, command, *args, timeout=600):
    """Run a utils command (-y, plain text) in the project's utils container; returns (ok, log)."""
    cmd = ["docker", "exec", "-u", "utils", "-e", "NO_COLOR=1", f"{name}_utils", "bash",
           f"{UTILS_ROOT}/.data/scripts/commands/{command}.sh", "-y", *args]
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        ok, log = proc.returncode == 0, (proc.stdout + proc.stderr).strip()[-4000:]
    except Exception as exc:  # noqa: BLE001
        ok, log = False, str(exc)
    journal(name, " ".join((command, *args)), ok, log[-300:])
    return ok, log


def utils_type(name, command):
    """Hand a command to the utils terminal of the project, where its confirmations are answered: typed right
    away (tmux send-keys) when the shell is idle at its prompt, else queued in /var/shared/.hub_command and
    started by the zsh precmd hook (.data/scripts/zshrc.sh) when the running command returns."""
    script = ('printf "%s\\n" "$1" > /var/shared/.hub_command && '
              'p=$(tmux display-message -t utils:0.1 -p "#{pane_pid}" 2>/dev/null) && z=$(pgrep -P "$p" 2>/dev/null | head -1); '
              'if [ -n "$z" ] && [ -z "$(pgrep -P "$z" 2>/dev/null)" ]; then rm -f /var/shared/.hub_command; '
              'tmux send-keys -t utils:0.1 C-u "$1" Enter; echo typed; else echo queued; fi')
    proc = subprocess.run(["docker", "exec", f"{name}_utils", "sh", "-c", script, "sh", command],
                          capture_output=True, text=True, timeout=10, check=True)
    journal(name, f"{command} ({proc.stdout.strip() or 'queued'} in utils)")


# ---- project discovery: register the template copies found under a host folder ----
def compose_name(folder, env_text):
    """Project name as docker compose derives it (COMPOSE_PROJECT_NAME or the normalized folder name)."""
    m = re.search(r"^COMPOSE_PROJECT_NAME=(.*)$", env_text, re.M)
    name = (m.group(1).strip().strip("'\"") if m else "") or os.path.basename(folder.rstrip("/")).lower()
    name = re.sub(r"[^a-z0-9_-]", "", name)
    return re.sub(r"^[^a-z0-9]+", "", name)


def scan(root):
    """Template copies under `root` (depth ≤ 3: docker-compose.yml + .env + .data/scripts/status.py) → {name: host folder}."""
    find = ("cd /scan && find . -mindepth 1 -maxdepth 3 -name docker-compose.yml ! -path '*/.data/*' ! -path '*/node_modules/*' "
            "| while read -r f; do d=$(dirname \"$f\"); [ -f \"$d/.env\" ] && [ -f \"$d/.data/scripts/status.py\" ] && "
            "{ printf '%s\\n' \"$d\"; sed -n 's/^COMPOSE_PROJECT_NAME=//p' \"$d/.env\"; echo '---'; }; done")
    proc = subprocess.run(["docker", "run", "--rm", "-v", f"{root}:/scan:ro", COMPOSE_IMAGE, "sh", "-c", find],
                          capture_output=True, text=True, timeout=120)
    if proc.returncode != 0:
        raise RuntimeError((proc.stderr or proc.stdout).strip()[-500:] or "scan failed")
    found = {}
    for block in proc.stdout.split("---\n"):
        lines = block.strip().split("\n")
        if not lines or not lines[0].startswith("./"):
            continue
        folder = os.path.normpath(os.path.join(root, lines[0][2:]))
        found[compose_name(folder, "COMPOSE_PROJECT_NAME=" + (lines[1] if len(lines) > 1 else ""))] = folder
    return found


def register(found):
    os.makedirs(REGISTRY, exist_ok=True)
    added = []
    for name, folder in found.items():
        if not re.fullmatch(r"[a-z0-9][a-z0-9_-]*", name):
            continue
        p = os.path.join(REGISTRY, name)
        if not os.path.exists(p):
            with open(p, "w") as fh:
                fh.write(folder + "\n")
            added.append(name)
    return added


# ---- server-sent events: the page gets the project list pushed when it changes ----
class Events:
    def __init__(self):
        self.subs, self.lock, self.last, self.wake = set(), threading.Lock(), "", threading.Event()

    def poke(self):   # an action happened: refresh now rather than at the next tick
        self.wake.set()

    def subscribe(self):
        q = queue.Queue(maxsize=50)
        with self.lock:
            self.subs.add(q)
        return q

    def unsubscribe(self, q):
        with self.lock:
            self.subs.discard(q)

    def snapshot(self):
        return self.last

    def loop(self):
        while True:
            try:
                data = json.dumps(projects())
                if data != self.last:
                    self.last = data
                    with self.lock:
                        for q in list(self.subs):
                            try:
                                q.put_nowait(data)
                            except queue.Full:
                                pass
            except Exception:  # noqa: BLE001
                pass
            self.wake.wait(1.0 if self.subs else 5.0)
            self.wake.clear()


events = Events()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):   # quiet
        pass

    def send(self, code, body, ctype="text/html; charset=utf-8", extra=None):
        data = body.encode() if isinstance(body, str) else body
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        if "Cache-Control" not in (extra or {}):
            self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(data)

    def json_reply(self, code, obj):
        return self.send(code, json.dumps(obj), "application/json")

    def query(self):
        q = self.path.partition("?")[2]
        return dict(p.split("=", 1) for p in q.split("&") if "=" in p)

    def body(self):
        raw = self.rfile.read(int(self.headers.get("Content-Length", 0) or 0)) or b"{}"
        data = json.loads(raw)
        if not isinstance(data, dict):
            raise ValueError("bad payload")
        return data

    def project(self):
        name = unquote(self.query().get("project", ""))
        known = registry()
        if not re.fullmatch(r"[a-z0-9_-]+", name) or name not in known:
            return None, known
        return name, known

    @staticmethod
    def background(fn, *args, **kwargs):
        threading.Thread(target=fn, args=args, kwargs=kwargs, daemon=True).start()

    def do_POST(self):
        path = self.path.split("?")[0]
        if self.headers.get("X-Hub-Token") != TOKEN:
            return self.json_reply(403, {"error": "bad token: reload the page"})
        if path == "/api/scan":
            try:
                root = str(self.body().get("path", "")).strip()
                if not root.startswith("/") or ".." in root.split("/"):
                    raise ValueError("absolute host folder expected")
                found = scan(root)
                added = register(found)
                for n in added:
                    journal(n, f"registered by scan of {root}")
                events.poke()
                return self.json_reply(200, {"ok": True, "found": found, "added": added})
            except ValueError as exc:
                return self.json_reply(400, {"error": str(exc)})
            except Exception as exc:  # noqa: BLE001
                return self.json_reply(500, {"error": str(exc)})
        name, known = self.project()
        if not name:
            return self.json_reply(404, {"error": "unknown project"})
        path_host = known[name]
        if path == "/api/start":
            if name in running():
                return self.json_reply(200, {"ok": True, "already": True})
            self.background(compose_run, name, path_host, "starting", ["up", "-d"])
            return self.json_reply(202, {"ok": True})
        if path == "/api/stop":   # docker compose down: containers removed, databases and files kept, the project stays in the hub
            if name not in running():
                return self.json_reply(200, {"ok": True, "already": True})
            self.background(compose_run, name, path_host, "stopping", ["down"], done="stopped")
            return self.json_reply(202, {"ok": True})
        if path == "/api/restart":   # recreate the stack so that every .env change applies
            self.background(compose_run, name, path_host, "restarting", ["down"], ["up", "-d"])
            return self.json_reply(202, {"ok": True})
        if path == "/api/odoo_restart":   # reboot -w: the Odoo process only (~2s), outcome in the journal
            if name not in running():
                return self.json_reply(409, {"error": "project stopped"})
            self.background(utils_command, name, "reboot", "-w")
            return self.json_reply(202, {"ok": True})
        if path == "/api/env":
            try:
                values = self.body()
                if not all(re.fullmatch(r"[A-Z_][A-Z0-9_]*", k) and isinstance(v, str) and "\n" not in v for k, v in values.items()):
                    raise ValueError("bad payload")
                text = env_apply(env_read(path_host, name), values)
                env_write(path_host, text, name)
                journal(name, ".env saved", True, ", ".join(sorted(values)))
                events.poke()
                return self.json_reply(200, {"ok": True, "text": text})
            except ValueError as exc:
                return self.json_reply(400, {"error": str(exc)})
            except Exception as exc:  # noqa: BLE001
                return self.json_reply(500, {"error": str(exc)})
        if path == "/api/setup":
            try:
                values = self.body()
                if not all(k in SETUP_KEYS and k != "ODOO_VERSION" and isinstance(v, str) and "\n" not in v for k, v in values.items()):
                    raise ValueError("bad payload")
                setup_apply(name, path_host, values)
                journal(name, "first start confirmed", True, ", ".join(f"{k}={v}" for k, v in values.items() if v))
            except ValueError as exc:
                return self.json_reply(400, {"error": str(exc)})
            except Exception as exc:  # noqa: BLE001
                return self.json_reply(500, {"error": str(exc)})
            # recreate: the paths are volumes, and Odoo starts now that the marker exists
            self.background(compose_run, name, path_host, "restarting", ["down"], ["up", "-d"])
            return self.json_reply(202, {"ok": True})
        if path == "/api/rebuild":   # typed in the utils terminal: takes minutes and may ask to confirm a database wipe
            if name not in running():
                return self.json_reply(409, {"error": "project stopped"})
            try:
                utils_type(name, "rebuild")
            except Exception as exc:  # noqa: BLE001
                return self.json_reply(500, {"error": str(exc)})
            return self.json_reply(200, {"ok": True})
        if path == "/api/env_update":
            if name not in running():
                return self.json_reply(409, {"error": "project stopped"})
            ok, log = utils_command(name, "env-update")
            events.poke()
            return self.json_reply(200 if ok else 500, {"ok": ok, "log": log})
        if path == "/api/forget":
            for d in (REGISTRY, COLORS_DIR, PROGRESS_DIR):
                try:
                    os.remove(os.path.join(d, name))
                except OSError:
                    pass
            with STARTS_LOCK:
                STARTS.pop(name, None)
            events.poke()
            return self.json_reply(200, {"ok": True})
        return self.send(404, "", "text/plain")

    def do_GET(self):
        host, _, port = self.headers.get("Host", "").partition(":")
        hub = f"http://{HUB_HOST}{':' + port if port else ''}"
        path = self.path.split("?")[0]
        if path == "/api/projects":   # computed now: the page calls it right after an action
            return self.send(200, json.dumps(projects()), "application/json")
        if path == "/api/events":
            return self.stream()
        if path in ("/api/env", "/api/setup", "/api/journal"):
            name, known = self.project()
            if not name:
                return self.json_reply(404, {"error": "project folder unknown (never started on this machine)"})
            try:
                if path == "/api/setup":
                    return self.json_reply(200, setup_info(name, known))
                if path == "/api/journal":
                    return self.json_reply(200, list(journal_load(name)))
                return self.json_reply(200, {"text": env_read(known[name], name), "dir": known[name]})
            except Exception as exc:  # noqa: BLE001
                return self.json_reply(500, {"error": str(exc)})
        if path == "/health":
            return self.send(200, "ok", "text/plain")
        if path.startswith("/static/"):
            return self.static(path[len("/static/"):])
        # logs./utils./mail./mcp.docker.localhost → the hub on that view ("_" = last / only project)
        view = host.split(".")[0]
        if host != HUB_HOST and view in VIEWS:
            return self.send(302, "", extra={"Location": f"{hub}/#_/{'odoo' if view == 'mcp' else view}"})
        if path != "/":
            return self.send(302, "", extra={"Location": f"{hub}/"})
        with open(os.path.join(STATIC, "index.html")) as fh:
            page = fh.read().replace("<head>", f'<head><meta name="hub-token" content="{TOKEN}">', 1)
        return self.send(200, page)

    def static(self, name):
        """static/ files with an ETag on their mtime: cached by the browser, revalidated on each load."""
        file = os.path.join(STATIC, os.path.basename(name))
        try:
            st = os.stat(file)
        except OSError:
            return self.send(404, "", "text/plain")
        etag = f'"{int(st.st_mtime)}-{st.st_size}"'
        if self.headers.get("If-None-Match") == etag:
            self.send_response(304); self.send_header("ETag", etag); self.send_header("Content-Length", "0"); self.end_headers()
            return None
        with open(file, "rb") as fh:
            data = fh.read()
        ctype = mimetypes.guess_type(file)[0] or "application/octet-stream"
        if ctype.startswith("text/") or ctype.endswith("javascript"):
            ctype += "; charset=utf-8"
        return self.send(200, data, ctype, {"ETag": etag, "Cache-Control": "no-cache"})

    def stream(self):
        """text/event-stream: the project list on connect, then each time it changes; a comment every 15s keeps it alive."""
        q = events.subscribe()
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(f"data: {events.snapshot() or json.dumps(projects())}\n\n".encode())
            self.wfile.flush()
            while True:
                try:
                    data = q.get(timeout=15)
                    self.wfile.write(f"data: {data}\n\n".encode())
                except queue.Empty:
                    self.wfile.write(b": keepalive\n\n")
                self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
        finally:
            events.unsubscribe(q)


if __name__ == "__main__":
    threading.Thread(target=events.loop, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
