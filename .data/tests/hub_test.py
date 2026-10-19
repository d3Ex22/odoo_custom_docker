#!/usr/bin/env python3
"""
hub_test.py - Unit tests of the hub (.data/proxy/hub.py) and of the status
daemon (.data/scripts/status.py), without Docker: run from the host or utils.

    python3 .data/tests/hub_test.py [-v]

The hub is started on a free port against a fake Traefik API and a fake
status endpoint (both served by this script); the daemon's pure functions
(.env parsing with markers, env_changed severities) run on temp files.
"""
import http.server
import importlib.util
import json
import os
import shutil
import socket
import sys
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


ENV = """# =============================================================================
# TEST
# =============================================================================

# -----------------------------------------------------------------------
# RUNTIME
# -----------------------------------------------------------------------

# Database to use on startup
#@ optional apply=r
SELECTED_DB=main

# Mail catcher profile
#@ apply=compose
COMPOSE_PROFILES=mail

# Debug toggle
#@ type=bool apply=r
DEBUGPY=false

# Odoo series and Python
#@ apply=rebuild
ODOO_VERSION=19.0
PYTHON_VERSION=3.12

# PostgreSQL major
#   Changing it wipes the databases.
#@ apply=rebuild wipe=db
POSTGRES_VERSION=17

# Free text
ODOO_ARGS='--dev xml'
"""


class StatusTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="hubtest.")
        os.environ.update(ENV_ROOT=ROOT, ENV_SHARED=cls.tmp)
        cls.st = load("status", os.path.join(ROOT, ".data/scripts/status.py"))
        cls.env_path = os.path.join(cls.tmp, ".env")
        with open(cls.env_path, "w") as fh:
            fh.write(ENV)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def test_parse_env_values_and_markers(self):
        values, markers = self.st.parse_env(self.env_path)
        self.assertEqual(values["ODOO_ARGS"], "--dev xml")   # quotes stripped
        self.assertEqual(values["POSTGRES_VERSION"], "17")
        self.assertEqual(markers["SELECTED_DB"], {"optional": True, "apply": "r"})
        self.assertEqual(markers["POSTGRES_VERSION"], {"apply": "rebuild", "wipe": "db"})
        self.assertEqual(markers["PYTHON_VERSION"]["apply"], "rebuild")   # contiguous keys share the marker line
        self.assertEqual(markers["ODOO_ARGS"], {})

    def test_env_changed_levels(self):
        values, markers = self.st.parse_env(self.env_path)
        applied = dict(values, COMPOSE_PROFILES="", SELECTED_DB="other", POSTGRES_VERSION="16", ODOO_ARGS="")
        changed = self.st.Status.env_changed(values, markers, applied)
        self.assertEqual(set(changed), {"COMPOSE_PROFILES", "POSTGRES_VERSION"})   # 'r' keys and unmarked keys never count
        self.assertEqual(changed["COMPOSE_PROFILES"], {"apply": "compose", "wipe": False, "from": "", "to": "mail"})
        self.assertEqual(changed["POSTGRES_VERSION"]["apply"], "rebuild")
        self.assertTrue(changed["POSTGRES_VERSION"]["wipe"])

    def test_compat_and_versions(self):
        root = os.path.join(self.tmp, "root")
        os.makedirs(os.path.join(root, ".data"))
        with open(os.path.join(root, ".data", "compat.map"), "w") as fh:
            fh.write("# odoo : def_py : compat_py : def_pg : compat_pg\n19.0 : 3.12 : 3.13,3.12,3.11,3.10 : 17 : 17,16,15,14,13\n")
        orig, self.st.ROOT = self.st.ROOT, root
        try:
            self.assertTrue(self.st.compat_ok("19.0", "3.12", "17"))
            self.assertFalse(self.st.compat_ok("19.0", "3.12", "12"))
            self.assertFalse(self.st.compat_ok("18.0", "3.12", "17"))   # unknown series
        finally:
            self.st.ROOT = orig
        self.assertGreater(self.st.version_key("4.10"), self.st.version_key("4.9"))
        self.assertGreater(self.st.version_key("4.0.0"), self.st.version_key("3.9"))

    def test_git_branch(self):
        repo = os.path.join(self.tmp, "ent")
        os.makedirs(os.path.join(repo, ".git"))
        os.makedirs(os.path.join(repo, "web_enterprise"))
        open(os.path.join(repo, "web_enterprise", "__manifest__.py"), "w").close()
        with open(os.path.join(repo, ".git", "HEAD"), "w") as fh:
            fh.write("ref: refs/heads/saas-19.2\n")
        self.assertEqual(self.st.git_branch(repo), "saas~19.2")
        self.assertEqual(self.st.enterprise_series(os.path.relpath(repo, self.st.ROOT)), "saas~19.2")
        self.assertEqual(self.st.enterprise_series(os.path.relpath(self.tmp, self.st.ROOT)), "")   # no module inside
        with open(os.path.join(repo, ".git", "HEAD"), "w") as fh:
            fh.write("0123abcd\n")   # detached
        self.assertEqual(self.st.git_branch(repo), "")


class Fake(http.server.BaseHTTPRequestHandler):
    """Traefik routers API (/api/http/routers) and a project status endpoint (/status)."""
    routers = []
    status = {}

    def log_message(self, *a):
        pass

    def do_GET(self):
        body = json.dumps(self.routers if self.path.startswith("/api/http/routers") else self.status).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


class HubTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.mkdtemp(prefix="hubtest.")
        cls.registry = os.path.join(cls.tmp, "projects")
        os.makedirs(cls.registry)
        with open(os.path.join(cls.registry, "demo"), "w") as fh:
            fh.write("/tmp/demo\n")
        with open(os.path.join(cls.registry, "idle"), "w") as fh:   # known, not running
            fh.write("/tmp/idle\n")
        fake_port = free_port()
        cls.fake = http.server.ThreadingHTTPServer(("127.0.0.1", fake_port), Fake)
        threading.Thread(target=cls.fake.serve_forever, daemon=True).start()
        Fake.routers = [{"name": "demo-odoo@docker", "status": "enabled", "rule": "Host(`demo.odoo.docker.localhost`)"},
                        {"name": "demo-utils@docker", "status": "enabled", "rule": "Host(`demo.utils.docker.localhost`)"},
                        {"name": "other@file", "status": "enabled", "rule": "Host(`x`)"}]
        Fake.status = {"project": "demo", "odoo": True, "env_changed": {"COMPOSE_PROFILES": {"apply": "compose", "wipe": False, "from": "", "to": "mail"}}}
        os.environ.update(TRAEFIK_API=f"http://127.0.0.1:{fake_port}/api/http/routers", REGISTRY=cls.registry,
                          JOURNAL_DIR=os.path.join(cls.tmp, "journal"))
        cls.hub = load("hub", os.path.join(ROOT, ".data/proxy/hub.py"))
        cls.hub.status = lambda name: Fake.status if name == "demo" else None   # the real one resolves <name>_utils
        cls.port = free_port()
        cls.server = http.server.ThreadingHTTPServer(("127.0.0.1", cls.port), cls.hub.Handler)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        threading.Thread(target=cls.hub.events.loop, daemon=True).start()
        cls.base = f"http://127.0.0.1:{cls.port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.fake.shutdown()
        shutil.rmtree(cls.tmp, ignore_errors=True)

    def get(self, path, headers=None):
        req = urllib.request.Request(self.base + path, headers=dict({"Host": "odoo.docker.localhost"}, **(headers or {})))
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, dict(r.headers), r.read()

    def post(self, path, data=None, token=None):
        req = urllib.request.Request(self.base + path, method="POST", data=json.dumps(data or {}).encode(),
                                     headers={"X-Hub-Token": token if token is not None else self.hub.TOKEN, "Host": "odoo.docker.localhost"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_page_and_static(self):
        code, _, body = self.get("/")
        self.assertEqual(code, 200)
        self.assertIn(f'name="hub-token" content="{self.hub.TOKEN}"'.encode(), body)
        self.assertIn(b'/static/hub.js', body)
        code, headers, _ = self.get("/static/hub.css")
        self.assertEqual(code, 200)
        self.assertTrue(headers["Content-Type"].startswith("text/css"))
        req = urllib.request.Request(self.base + "/static/hub.css", headers={"If-None-Match": headers["ETag"], "Host": "odoo.docker.localhost"})
        try:
            urllib.request.urlopen(req, timeout=5)
            self.fail("expected 304")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 304)
        try:
            self.get("/static/nothing.css")
            self.fail("expected 404")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 404)

    def test_projects_merge_running_and_known(self):
        code, _, body = self.get("/api/projects")
        self.assertEqual(code, 200)
        projects = {p["name"]: p for p in json.loads(body)}
        self.assertEqual(set(projects), {"demo", "idle"})
        self.assertTrue(projects["demo"]["running"])
        self.assertEqual(projects["demo"]["odoo"], "demo.odoo.docker.localhost")
        self.assertEqual(projects["demo"]["dir"], "/tmp/demo")
        self.assertEqual(projects["demo"]["status"]["env_changed"]["COMPOSE_PROFILES"]["apply"], "compose")
        self.assertFalse(projects["idle"]["running"])
        self.assertEqual(projects["idle"]["dir"], "/tmp/idle")
        self.assertIsNone(projects["idle"]["odoo"])
        self.assertIsNone(projects["idle"]["status"])

    def test_view_hosts_redirect_to_the_hub(self):
        req = urllib.request.Request(self.base + "/", headers={"Host": "logs.docker.localhost"})
        try:
            urllib.request.build_opener(NoRedirect).open(req, timeout=5)
            self.fail("expected 302")
        except urllib.error.HTTPError as e:
            self.assertEqual(e.code, 302)
            self.assertTrue(e.headers["Location"].endswith("/#_/logs"))

    def test_post_needs_the_token(self):
        self.assertEqual(self.post("/api/forget?project=demo", token="nope")[0], 403)
        self.assertEqual(self.post("/api/forget?project=unknown")[0], 404)
        self.assertEqual(self.post("/api/scan", {"path": "relative"})[0], 400)
        self.assertEqual(self.post("/api/env?project=demo", {"lower": "x"})[0], 400)

    def test_events_stream(self):
        req = urllib.request.Request(self.base + "/api/events", headers={"Host": "odoo.docker.localhost"})
        with urllib.request.urlopen(req, timeout=5) as r:
            self.assertTrue(r.headers["Content-Type"].startswith("text/event-stream"))
            first = r.readline().decode()
            self.assertTrue(first.startswith("data: "))
            self.assertEqual(json.loads(first[6:])[0]["name"], "demo")
            # a change pushes a new frame (the loop notices within a second)
            Fake.status = dict(Fake.status, odoo=False)
            try:
                self.hub.events.poke()
                deadline = time.time() + 5
                while time.time() < deadline:
                    line = r.readline().decode()
                    if line.startswith("data: ") and not json.loads(line[6:])[0]["status"]["odoo"]:
                        break
                else:
                    self.fail("no update pushed")
            finally:
                Fake.status = dict(Fake.status, odoo=True)

    def test_env_apply_quoting(self):
        text = "A=1\nB='x y'\nC=\n"
        out = self.hub.env_apply(text, {"B": "--dev xml", "C": "plain", "A": "it's"})
        self.assertEqual(out, "A='it'\\''s'\nB='--dev xml'\nC=plain\n")
        self.assertEqual(self.hub.env_values(out, ("A", "B")), {"A": "it's", "B": "--dev xml"})

    def test_compose_name(self):
        self.assertEqual(self.hub.compose_name("/x/19/_AEC", "COMPOSE_PROJECT_NAME=\n"), "aec")
        self.assertEqual(self.hub.compose_name("/x/My Proj", ""), "myproj")
        self.assertEqual(self.hub.compose_name("/x/whatever", "COMPOSE_PROJECT_NAME='custom-1'\n"), "custom-1")

    def test_journal(self):
        self.hub.journal("demo", "test action", True, "detail")
        code, _, body = self.get("/api/journal?project=demo")
        self.assertEqual(code, 200)
        entries = json.loads(body)
        self.assertEqual(entries[-1]["action"], "test action")
        self.assertTrue(os.path.exists(os.path.join(self.tmp, "journal", "demo.json")))
        code, _, body = self.get("/api/projects")   # computed on request: the menu shows the entry right away
        self.assertEqual(json.loads(body)[0]["last"]["action"], "test action")


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *a, **k):
        return None


if __name__ == "__main__":
    unittest.main(argv=[sys.argv[0]] + [a for a in sys.argv[1:] if a in ("-v", "-q")])
