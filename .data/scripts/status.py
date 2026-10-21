#!/usr/bin/env python3
"""
Status daemon of a project (runs in the utils container, stdlib only).

Every INTERVAL seconds it writes to /var/shared:
    .tmux_status_left    versions + rebuild alerts (tmux status-left of both sessions)
    .tmux_status_right   service pills MCP / ODOO / ENT / DB / database (status-right)
    status.json          the same, machine-readable: hub tabs and the MCP /status endpoint

One process, no 'docker' CLI: containers are read through the Engine API on the
socket (one list call per tick, 'top' for the Odoo process), PostgreSQL with
pg_isready, the MCP server over HTTP. The slow values are cached: installed
build (per container id), nightly build (10 min), enterprise series (git HEAD of
the mirrored folder, 15 s), template release (hourly, in a thread), env_changed
(recomputed only when .env or its applied snapshot changed).

    status.py --loop     daemon (utils entrypoint)
    status.py            one tick, prints status.json

.env keys carry a marker line in their help ('#@ apply=compose wipe=db', see
.env): 'apply' says how a change is applied (r = next Odoo start, compose =
docker compose up -d, rebuild) and 'wipe=db' that it wipes the databases.
env_changed lists the keys whose value differs from the snapshot taken when the
newest container was created (.env.applied), for apply = compose | rebuild.
"""
import http.client
import io
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tarfile
import tempfile
import threading
import time
import urllib.request

ROOT = os.environ.get("ENV_ROOT", "/home/utils/odoo_custom_docker")   # overridden by the tests
SHARED = os.environ.get("ENV_SHARED", "/var/shared")
ENV_FILE = f"{ROOT}/.env"
APPLIED = f"{SHARED}/.env.applied"
INTERVAL = 2
LOG = f"{SHARED}/.status.log"


# ----------------------------------------------------------------------------
# Docker Engine API over the unix socket
# ----------------------------------------------------------------------------
class _Conn(http.client.HTTPConnection):
    def __init__(self):
        super().__init__("docker")

    def connect(self):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(5)
        self.sock.connect("/var/run/docker.sock")


def docker(method, path, body=None):
    conn = _Conn()
    try:
        conn.request(method, path, body=json.dumps(body) if body is not None else None,
                     headers={"Content-Type": "application/json"} if body is not None else {})
        resp = conn.getresponse()
        return resp.status, resp.read()
    except (OSError, http.client.HTTPException):
        return 0, b""
    finally:
        conn.close()


def docker_json(method, path, body=None):
    status, data = docker(method, path, body)
    try:
        return json.loads(data) if 200 <= status < 300 and data else None
    except ValueError:
        return None


def containers(project):
    """{name: {id, image, created, running}} of the project's containers (one API call; the Engine name filter
    is a substring match, so <project>_test_odoo would come back too: keep the exact names)."""
    names = {f"{project}_{service}" for service in ("odoo", "utils", "db", "mail")}
    out = {}
    for c in docker_json("GET", f"/containers/json?all=1&filters={urllib.request.quote(json.dumps({'name': [project + '_']}))}") or []:
        for n in c.get("Names", []):
            if n[1:] in names:
                out[n[1:]] = {"id": c["Id"], "image": c.get("Image", ""), "created": c.get("Created", 0),
                              "running": c.get("State") == "running"}
    return out


def process_names(cid):
    top = docker_json("GET", f"/containers/{cid}/top?ps_args=-o%20pid,comm")
    return [r[1] for r in (top or {}).get("Processes", []) if len(r) > 1]


def container_file(cid, path):
    """Content of a file inside a container (archive API, no exec)."""
    status, data = docker("GET", f"/containers/{cid}/archive?path={urllib.request.quote(path)}")
    if status != 200:
        return ""
    try:
        with tarfile.open(fileobj=io.BytesIO(data)) as tar:
            member = tar.getmembers()[0]
            return (tar.extractfile(member).read() if member.isfile() else b"").decode(errors="replace").strip()
    except (tarfile.TarError, IndexError):
        return ""


# ----------------------------------------------------------------------------
# Files: .env (values + markers), palette, compat map
# ----------------------------------------------------------------------------
def mtime(path):
    try:
        return os.stat(path).st_mtime
    except OSError:
        return 0


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        return v[1:-1].replace("'\\''", "'")
    return v


def parse_env(path):
    """(values, markers): markers[key] = {'apply': 'compose', 'wipe': 'db', 'auto': True...} from the '#@' line of its help."""
    values, markers, pending = {}, {}, {}
    try:
        with open(path) as fh:
            lines = fh.read().splitlines()
    except OSError:
        return values, markers
    for line in lines:
        if line.startswith("#@"):
            for tok in line[2:].split():
                k, _, v = tok.partition("=")
                pending[k] = v or True
        elif line.startswith("#"):
            continue
        elif re.match(r"[A-Z_][A-Z0-9_]*=", line):
            k, _, v = line.partition("=")
            values[k] = unquote(v)
            markers[k] = dict(pending)   # contiguous keys share the marker line
        else:
            pending = {}
    return values, markers


class Cached:
    """Value recomputed when its ttl expired or its key changed."""

    def __init__(self, fn, ttl=0):
        self.fn, self.ttl, self.at, self.key, self.value = fn, ttl, 0, None, None

    def get(self, key=None, *args):
        now = time.time()
        if self.value is None or key != self.key or (self.ttl and now - self.at >= self.ttl):
            self.value, self.key, self.at = self.fn(*args), key, now
        return self.value


THEME_FILE = f"{ROOT}/.data/scripts/lib/theme.sh"
THEME_VARS = ("TMUX_ODOO_COLOR", "TMUX_PY_COLOR", "TMUX_PG_COLOR", "TMUX_ALERT_FG", "TMUX_ALERT_BG",
              "TMUX_STATUS_BG", "TMUX_STATUS_FG", "COLOR_SUCCESS", "COLOR_WARN", "COLOR_ERROR")


def load_theme():
    """TMUX_* / COLOR_* values of lib/theme.sh (resolved by bash, like the scripts)."""
    script = f'source {THEME_FILE}; for v in {" ".join(THEME_VARS)}; do printf "%s=%s\\n" "$v" "${{!v}}"; done'
    try:
        out = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        out = ""
    theme = {v: "default" for v in THEME_VARS}
    theme.update(dict(l.split("=", 1) for l in out.splitlines() if "=" in l and l.split("=", 1)[1]))
    return theme


def compat_ok(odoo, py, pg):
    try:
        with open(f"{ROOT}/.data/compat.map") as fh:
            rows = fh.read().splitlines()
    except OSError:
        return True
    for line in rows:
        parts = [p.strip() for p in line.split(":")]
        if len(parts) == 5 and not parts[0].startswith("#") and parts[0] == odoo:
            return py in parts[2].split(",") and pg in parts[4].split(",")
    return False


def nightly_latest(version):
    try:
        with urllib.request.urlopen(f"https://nightly.odoo.com/{version}/nightly/src/", timeout=5) as r:
            builds = re.findall(rf"odoo_{re.escape(version)}\.(\d{{8}})\.tar\.gz", r.read().decode(errors="replace"))
        return max(builds) if builds else ""
    except (OSError, ValueError):
        return ""


def git_branch(path):
    """19.0 / saas~19.2 from .git/HEAD, '' when not a repo or detached."""
    gitdir = os.path.join(path, ".git")
    try:
        if os.path.isfile(gitdir):
            with open(gitdir) as fh:
                gitdir = os.path.normpath(os.path.join(path, fh.read().split("gitdir:", 1)[1].strip()))
        with open(os.path.join(gitdir, "HEAD")) as fh:
            head = fh.read().strip()
    except (OSError, IndexError):
        return ""
    ref = head.partition("ref: refs/heads/")[2]
    return ref.replace("saas-", "saas~") if re.fullmatch(r"(saas-)?\d+\.\d+", ref) else ""


def enterprise_series(rel_path):
    """Series of the mirrored enterprise folder: '' when the folder holds no module, 'unknown' when it is not a git checkout."""
    if not rel_path:
        return ""
    path = os.path.normpath(os.path.join(ROOT, rel_path))
    try:
        if not any(os.path.isfile(os.path.join(path, d, "__manifest__.py")) for d in os.listdir(path)):
            return ""
    except OSError:
        return ""
    return git_branch(path) or "unknown"


# ----------------------------------------------------------------------------
# Template release (hourly, background thread; cache compatible with env-update.sh)
# ----------------------------------------------------------------------------
UPDATE_CACHE = f"{SHARED}/.env_update"
UPDATE_TTL = 3600


def check_release(local_ver, repo, ref):
    with open(UPDATE_CACHE, "w") as fh:   # no retry every tick when offline
        fh.write(f"{local_ver}||\n")
    refs = [f"refs/heads/{ref}", f"refs/tags/{ref}"] if ref else ["HEAD"]
    try:
        out = subprocess.run(["git", "ls-remote", repo, *refs], capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.SubprocessError):
        return
    remote = out.split()[0] if out.split() else ""
    try:
        with open(f"{ROOT}/.data/.template_rev") as fh:
            known = fh.read().strip()
    except OSError:
        known = ""
    if not remote or remote == known:
        return
    tmp = tempfile.mkdtemp(prefix="env-check.")
    try:
        clone = ["git", "clone", "-q", "--depth", "1", "--no-checkout", *(["-b", ref] if ref else []), repo, tmp]
        if subprocess.run(clone, capture_output=True, timeout=60).returncode == 0:
            ver = subprocess.run(["git", "-C", tmp, "show", "HEAD:.data/VERSION"], capture_output=True, text=True, timeout=10).stdout.strip().splitlines()
            with open(UPDATE_CACHE, "w") as fh:
                fh.write(f"{local_ver}|{ver[0] if ver else ''}|{remote[:7]}\n")
    except (OSError, subprocess.SubprocessError):
        pass
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def version_key(v):
    return [int(x) if x.isdigit() else x for x in re.split(r"[.\-]", v)]


def local_version():
    try:
        with open(f"{ROOT}/.data/VERSION") as fh:
            return fh.read().strip()
    except OSError:
        return ""


def env_update_info(env, local_ver):
    local_ver = local_ver or "0"
    repo = env.get("ENV_TEMPLATE_REPO", "")
    if repo and time.time() - mtime(UPDATE_CACHE) >= UPDATE_TTL and not any(t.name == "release" for t in threading.enumerate()):
        threading.Thread(target=check_release, args=(local_ver, repo, env.get("ENV_TEMPLATE_REF", "")), name="release", daemon=True).start()
    try:
        with open(UPDATE_CACHE) as fh:
            _, avail, rev = fh.read().strip().split("|")[:3]
    except (OSError, ValueError):
        avail, rev = "", ""
    if avail and avail != local_ver and version_key(avail) > version_key(local_ver):
        return {"current": local_ver, "available": avail, "rev": rev, "ref": env.get("ENV_TEMPLATE_REF", "")}
    return {}


# ----------------------------------------------------------------------------
# One tick
# ----------------------------------------------------------------------------
class Status:
    def __init__(self):
        self.env = Cached(lambda: parse_env(ENV_FILE))
        self.theme = Cached(load_theme)
        self.nightly = Cached(nightly_latest, ttl=600)
        self.build = Cached(lambda cid: container_file(cid, "/opt/odoo/.build_version"))
        self.enterprise = Cached(enterprise_series, ttl=15)
        self.changed = Cached(self.env_changed)

    @staticmethod
    def env_changed(env, markers, applied_values):
        out = {}
        for k in set(env) | set(applied_values):
            apply = markers.get(k, {}).get("apply")
            if apply not in ("compose", "rebuild") or env.get(k, "") == applied_values.get(k, ""):
                continue
            out[k] = {"apply": apply, "wipe": markers[k].get("wipe") == "db",
                      "from": applied_values.get(k, ""), "to": env.get(k, "")}
        return dict(sorted(out.items()))

    def tick(self):
        env, markers = self.env.get(mtime(ENV_FILE))
        theme = self.theme.get(mtime(THEME_FILE))
        project = os.environ.get("COMPOSE_PROJECT_NAME") or env.get("COMPOSE_PROJECT_NAME", "")
        cs = containers(project)
        odoo, utils, db = cs.get(f"{project}_odoo", {}), cs.get(f"{project}_utils", {}), cs.get(f"{project}_db", {})
        wanted = {"odoo": env.get("ODOO_VERSION", ""), "py": env.get("PYTHON_VERSION", ""), "pg": env.get("POSTGRES_VERSION", ""),
                  "build": env.get("ODOO_BUILD", "latest")}

        # installed stack: build file of the odoo container, python from its image tag, postgres from the db image tag
        inst_odoo, _, inst_build = (self.build.get(odoo["id"], odoo["id"]) if odoo else "").partition("|")
        m = re.search(r"-py(\d+\.\d+)-", odoo.get("image", ""))
        inst_py = m.group(1) if m else ""
        m = re.search(r":(\d+)$", db.get("image", ""))
        inst_pg = m.group(1) if m else ""
        latest = self.nightly.get(wanted["odoo"], wanted["odoo"]) if wanted["build"] == "latest" or not inst_build else ""

        # rebuild needed? versions, pinned build, or containers created on another tag than .env wants
        blink = int(time.time() // INTERVAL) % 2 == 0
        alert = f"#[fg={theme['TMUX_ALERT_FG']},bg={theme['TMUX_ALERT_BG']},bold]"
        styles = {k: f"#[fg={theme[c]},bold]" for k, c in (("odoo", "TMUX_ODOO_COLOR"), ("build", "TMUX_ODOO_COLOR"), ("py", "TMUX_PY_COLOR"), ("pg", "TMUX_PG_COLOR"))}
        need_rebuild, build_update, status = False, False, ""
        if not compat_ok(wanted["odoo"], wanted["py"], wanted["pg"]):
            styles = dict.fromkeys(styles, alert)
            status = f"#[default]#[fg={theme['TMUX_ALERT_BG']},bg={theme['TMUX_STATUS_BG']},bold] REBUILD BLOCKED"
        else:
            bad = set()
            if inst_odoo and wanted["odoo"] != inst_odoo:
                bad |= {"odoo", "build"}
            if wanted["build"] != "latest" and inst_build and wanted["build"] != inst_build:
                bad.add("build")
            elif wanted["build"] == "latest" and inst_build and latest and latest != inst_build:
                build_update = True   # newer nightly: only hinted (rebuild -n)
            if inst_py and wanted["py"] != inst_py:
                bad.add("py")
            if inst_pg and wanted["pg"] != inst_pg:
                bad.add("pg")
            odoo_tag = f"odoo-env/odoo:{wanted['odoo']}-py{wanted['py']}-{wanted['build']}-{env.get('ODOO_IMAGE_REV') or 'dev'}"
            utils_tag = f"odoo-env/utils:{env.get('UTILS_IMAGE_REV') or 'dev'}"
            need_rebuild = bool(bad) or (bool(odoo) and odoo["image"] != odoo_tag) or (bool(utils) and utils["image"] != utils_tag)
            if blink:
                for k in bad:
                    styles[k] = alert
                if need_rebuild:
                    status = f"#[default]#[fg={theme['TMUX_ALERT_BG']},bg={theme['TMUX_STATUS_BG']},bold] REBUILD"
        display_build = (inst_build or (latest if wanted["build"] == "latest" else wanted["build"]) or "latest") + ("⇡" if build_update else "")
        left = (f"#[default]{styles['odoo']} Odoo {wanted['odoo']}.#[default]{styles['build']}{display_build}#[default] "
                f"{styles['py']} Py {wanted['py']} #[default]{styles['pg']} PG {wanted['pg']} #[default]{status}")

        # services
        on = f"#[fg={theme['TMUX_STATUS_BG']},bg={theme['COLOR_SUCCESS']},bold]"
        warn = f"#[fg={theme['TMUX_STATUS_BG']},bg={theme['COLOR_WARN']},bold]"
        off = f"#[fg={theme['TMUX_STATUS_BG']},bg={theme['COLOR_ERROR']},bold]"
        ent_ver = self.enterprise.get(env.get("ENTERPRISE_PATH", ""), env.get("ENTERPRISE_PATH", ""))
        ent_state = "ok" if ent_ver == wanted["odoo"] else "missing" if not ent_ver else "mismatch"
        proc_up = bool(odoo.get("running")) and "odoo" in process_names(odoo["id"])
        db_up = bool(db.get("running")) and subprocess.run(["pg_isready", "-h", f"{project}_db", "-U", "odoo", "-q", "-t", "1"],
                                                            capture_output=True).returncode == 0
        try:
            with urllib.request.urlopen("http://localhost:8300/health", timeout=0.5) as r:
                mcp_up = r.status == 200
        except OSError:
            mcp_up = False
        try:
            with open(f"{SHARED}/.last_start") as fh:
                last_start, last_errors, start_at = (fh.read().strip().split("|") + ["0"])[:3]
        except (OSError, ValueError):
            last_start, last_errors, start_at = "", "0", "0"
        # red: process gone or the start blocked Odoo (failed / dead / timeout); orange: up, with errors in the log
        proc_style = off if not proc_up or last_start in ("failed", "dead") else warn if last_start in ("errors", "timeout") else on
        ent_style = {"ok": on, "missing": off}.get(ent_state, warn)
        active_db = env.get("SELECTED_DB") or "multi-db"

        def pill(style, label):
            return f"{style} {label} #[default] "

        right = (pill(on if mcp_up else off, "MCP") + pill(proc_style, "ODOO") + pill(ent_style, "ENT") + pill(on if db_up else off, "DB")
                 + pill(f"#[fg={theme['TMUX_STATUS_BG']},bg={theme['TMUX_STATUS_FG']},bold]", active_db))

        # .env vs the snapshot taken when the newest container was created
        newest = max([c["created"] for c in cs.values()] or [0])
        if newest > mtime(APPLIED):
            try:
                shutil.copyfile(ENV_FILE, APPLIED)
            except OSError:
                pass
        env_changed = self.changed.get((mtime(ENV_FILE), mtime(APPLIED)), env, markers, parse_env(APPLIED)[0])
        env_version = local_version()

        data = {"project": project, "odoo": proc_up, "db": db_up, "mcp": mcp_up, "mail": bool(cs.get(f"{project}_mail", {}).get("running")),
                "enterprise": ent_state, "enterprise_version": ent_ver, "start": last_start, "start_errors": int(last_errors or 0), "start_at": int(start_at or 0),
                "database": env.get("SELECTED_DB", ""), "odoo_version": inst_odoo or wanted["odoo"], "build": inst_build,
                "rebuild": need_rebuild, "env_changed": env_changed, "env_update": env_update_info(env, env_version),
                "env_version": env_version, "setup": not os.path.exists(f"{SHARED}/.setup_done"),
                "enterprise_path": env.get("ENTERPRISE_PATH", ""), "odoo_path": env.get("ODOO_PATH", ""), "time": int(time.time())}
        write(f"{SHARED}/.tmux_status_left", left + "\n")
        write(f"{SHARED}/.tmux_status_right", right + "\n")
        write(f"{SHARED}/status.json", json.dumps(data) + "\n")
        return data


def write(path, text):
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        fh.write(text)
    os.replace(tmp, path)


def main(argv):
    st = Status()
    if "--loop" not in argv:
        print(json.dumps(st.tick()))
        return
    try:
        os.remove(f"{SHARED}/.last_start")
    except OSError:
        pass
    last_error = ""
    while True:
        t = time.time()
        try:
            st.tick()
        except Exception as exc:  # noqa: BLE001 — the daemon must survive anything
            message = f"{type(exc).__name__}: {exc}"
            if message != last_error:   # a persistent failure is logged once, not every tick
                last_error = message
                try:
                    with open(LOG, "a") as fh:
                        fh.write(f"{time.strftime('%H:%M:%S')} {message}\n")
                except OSError:
                    pass
        time.sleep(max(0.2, INTERVAL - (time.time() - t)))


if __name__ == "__main__":
    main(sys.argv[1:])
