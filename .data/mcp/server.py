#!/usr/bin/env python3
"""
MCP server for the Odoo dev environment (stdlib only).

Exposes the utils commands as tools for AI agents (Cursor, Claude, ...).
Runs INSIDE the utils container, two transports:

    --serve [PORT]   Streamable HTTP on 0.0.0.0:PORT (default 8300), kept
                     running in the background by the 'mcp' utils command and
                     started with the container. Client: http://<project>.mcp.docker.localhost/mcp
    (no option)      stdio, for clients that spawn the process themselves:
                     docker exec -i -u utils <project>_utils python3 .../server.py

    --config         print the client configuration (Cursor / Claude Desktop)
    --tools          list the tools
    --test [URL]     handshake + one tool call (against URL, or a stdio child)

Every tool runs the same scripts a human uses in the utils terminal, with
-y (no prompt) and NO_COLOR=1 (plain text), so behaviour stays identical.
"""
import json
import os
import subprocess
import sys
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = "/home/utils/odoo_custom_docker"
CMDS = f"{ROOT}/.data/scripts/commands"
INTERNAL = f"{ROOT}/.data/scripts/internal"   # status, conf, logs, check_versions: not utils commands
PROTOCOL_VERSIONS = ("2025-06-18", "2025-03-26", "2024-11-05")


def env_version():
    try:
        with open(f"{ROOT}/.data/VERSION") as fh:
            return fh.read().strip()
    except OSError:
        return "0"


SERVER_INFO = {"name": "odoo-dev-utils", "version": env_version()}


def read_env():
    env = {}
    for name in (".env", ".env.secrets"):
        try:
            with open(f"{ROOT}/{name}") as fh:
                for line in fh:
                    line = line.strip()
                    if not line or line.startswith("#") or "=" not in line:
                        continue
                    k, v = line.split("=", 1)
                    env[k.strip()] = v.strip().strip("'\"")
        except OSError:
            pass
    return env


def selected_db(a):
    """Database argument of a tool call, else SELECTED_DB read from .env now (db_select / conf_set change it)."""
    return a.get("database") or read_env().get("SELECTED_DB", "")


# Project name: resolved by docker compose (folder name unless set in .env), set in the container environment.
PROJECT = os.environ["COMPOSE_PROJECT_NAME"]
MCP_PORT = 8300   # inside the container; the shared proxy serves it on MCP_URL
MCP_URL = f"http://{PROJECT}.mcp.docker.localhost/mcp"
ODOO_CONTAINER = f"{PROJECT}_odoo"


# ----------------------------------------------------------------------------
# Command execution
# ----------------------------------------------------------------------------
def run(args, stdin=None, timeout=900, merge=True):
    """Run a command; stderr is merged into stdout (merge=True) so that error
    messages keep their place in the output, as a human would see them."""
    env = dict(os.environ, NO_COLOR="1", ASSUME_YES="true", TERM="dumb")
    stderr = subprocess.STDOUT if merge else subprocess.PIPE
    try:
        proc = subprocess.run(args, input=stdin, stdout=subprocess.PIPE, stderr=stderr, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s"
    return proc.returncode, proc.stdout, proc.stderr or ""


def script(name, *args, timeout=900):
    # confirmations are answered by ASSUME_YES (run); psql forwards every argument to the binary anyway
    path = f"{INTERNAL}/{name}.sh" if os.path.exists(f"{INTERNAL}/{name}.sh") else f"{CMDS}/{name}.sh"
    rc, out, err = run(["bash", path, *args], timeout=timeout)
    text = out + ("\n" + err if err.strip() else "")
    text = "\n".join(line.rstrip() for line in text.splitlines()).strip("\n")
    return rc, text or f"(exit {rc})"


def text_result(text, is_error=False):
    return {"content": [{"type": "text", "text": text}], "isError": is_error}


def flag(value, name):
    return [name] if value else []


# ----------------------------------------------------------------------------
# Tools
# ----------------------------------------------------------------------------
def t_odoo_status(a):
    rc1, s = script("status")
    rc2, c = script("conf")
    return text_result(s + "\n\n" + c, rc1 != 0)


def t_odoo_start(a):
    rc, t = script("start", *flag(a.get("wait", True), "-w"))
    return text_result(t, rc not in (0, 2))


def t_odoo_stop(a):
    rc, t = script("stop")
    return text_result(t, rc != 0)


def t_odoo_restart(a):
    rc, t = script("reboot", *flag(a.get("wait", True), "-w"))
    return text_result(t, rc not in (0, 2))


def t_odoo_update(a):
    mods = a.get("modules", "").strip()
    if not mods:
        return text_result("modules is required (comma-separated list, patterns allowed)", True)
    db = selected_db(a)
    if not db:
        return text_result("no database: pass 'database' (name, comma list or 'all') or set SELECTED_DB", True)
    rc, t = script("update", *flag(a.get("keep"), "-k"), *flag(a.get("wait", True), "-w"), "-d", db, mods)
    return text_result(t, rc not in (0, 2))


def t_odoo_logs(a):
    args = ["-n", str(int(a.get("lines", 100)))]
    if a.get("grep"):
        args += ["-g", a["grep"]]
    if a.get("errors_only"):
        args += ["-e"]
    if a.get("level"):
        args += ["-l", str(a["level"])]
    rc, t = script("logs", *args)
    return text_result(t, rc != 0)


def t_odoo_wait_ready(a):
    rc, t = script("logs", "-w", str(int(a.get("timeout", 120))))
    return text_result(t, rc == 1)


def t_odoo_shell(a, commit=False):
    code = a.get("code", "")
    if not code.strip():
        return text_result("code is required", True)
    db = selected_db(a)
    if not db:
        return text_result("no database: pass 'database' or set SELECTED_DB", True)
    if commit:  # only reached when the code itself raised nothing
        code = code.rstrip() + "\nenv.cr.commit()\nprint('(committed)')\n"
    run(["docker", "exec", ODOO_CONTAINER, "/usr/local/bin/generate_addons_path.sh"], timeout=30)  # refresh addons_path
    rc, out, err = run(["docker", "exec", "-i", ODOO_CONTAINER, "odoo", "shell",
                        "-c", "/etc/odoo/odoo.conf", "-d", db, "--no-http", "--log-level=warn", "--shell-interface=python"],
                       stdin=code, timeout=int(a.get("timeout", 300)), merge=False)
    err_lines = [l for l in err.splitlines() if l.strip() and " INFO " not in l]
    text = out.strip()
    if err_lines:
        text += ("\n--- stderr ---\n" if text else "") + "\n".join(err_lines[-80:])
    return text_result(text or "(no output)", rc != 0)


def t_odoo_shell_commit(a):
    return t_odoo_shell(a, commit=True)


def t_odoo_test(a):
    mods = a.get("modules", "").strip()
    if not mods:
        return text_result("modules is required (comma-separated list)", True)
    args = []
    if a.get("tags"):
        args += ["-t", a["tags"]]
    if a.get("on_database"):
        args += ["--on", a["on_database"]]
    args += flag(a.get("keep"), "--keep") + flag(a.get("no_demo"), "--no-demo") + flag(a.get("verbose"), "-v") + flag(a.get("coverage"), "--coverage")
    rc, t = script("test", *args, mods, timeout=int(a.get("timeout", 1800)))
    return text_result(t, rc != 0)


def t_db_list(a):
    rc, t = script("database", "list")
    return text_result(t, rc != 0)


def t_db_select(a):
    rc, t = script("database", "select", a["name"])
    return text_result(t, rc != 0)


def t_db_backup(a):
    args = ["backup"] + flag(a.get("filestore"), "-fs") + (["--keep", str(int(a["keep"]))] if a.get("keep") else []) \
        + ([a["name"]] if a.get("name") else [])
    rc, t = script("database", *args, timeout=3600)
    return text_result(t, rc != 0)


def t_db_restore(a):
    if bool(a.get("file")) == bool(a.get("last")):
        return text_result("exactly one of 'file' or 'last' is required", True)
    src = ["-F", a["file"]] if a.get("file") else ["--last"]
    args = ["restore", "-f", *src] + flag(a.get("switch"), "-s") + flag(not a.get("sanitize", True), "-na") + [a["name"]]
    rc, t = script("database", *args, timeout=7200)
    return text_result(t, rc != 0)


def t_db_drop(a):
    rc, t = script("database", "drop", a["name"])
    return text_result(t, rc != 0)


def t_db_clone(a):
    rc, t = script("database", "clone", *flag(a.get("force"), "-f"), a["source"], a["destination"], timeout=3600)
    return text_result(t, rc != 0)


def t_db_query(a):
    db = selected_db(a)
    if not db:
        return text_result("no database: pass 'database' or set SELECTED_DB", True)
    rc, t = script("psql", "-d", db, "-X", "--csv", "-c", a["sql"], timeout=300)
    return text_result(t, rc != 0)


def t_conf_set(a):
    rc, t = script("conf", a["variable"], a.get("value") or "-")
    return text_result(t, rc != 0)


def t_repos_pull(a):
    args = ([a["repo"]] if a.get("repo") else []) + flag(a.get("force"), "-f")
    if a.get("build"):
        args += ["--build", a["build"]]
    rc, t = script("pull", *args, timeout=1800)
    return text_result(t, rc != 0)


def t_check_versions(a):
    rc, t = script("check_versions")
    return text_result(t, rc != 0)


def t_translation_export(a):
    args = (["--all"] if a.get("all") else [a["modules"]]) + flag(a.get("pot"), "--pot")
    if a.get("language"):
        args = ["-l", a["language"]] + args
    rc, t = script("translation", *args, timeout=1800)
    return text_result(t, rc != 0)


def t_pre_commit(a):
    args = ["-a"] + ([a["folder"]] if a.get("folder") else [])
    rc, t = script("pre-commit", *args, timeout=1800)
    return text_result(t, rc != 0)


def t_requirements_install(a):
    rc, t = script("requirements", timeout=1800)
    return text_result(t, rc != 0)


MODEL_INFO_CODE = r"""
import json
name = %(model)r
Model = env.get(name)
if Model is None:
    print("unknown model: " + name); raise SystemExit
fields = {}
for fname, f in sorted(Model._fields.items()):
    if %(all)r is False and fname in ("create_uid", "create_date", "write_uid", "write_date", "__last_update", "display_name", "id"):
        continue
    d = {"type": f.type, "string": f.string}
    if getattr(f, "comodel_name", None): d["comodel"] = f.comodel_name
    if f.required: d["required"] = True
    if not f.store: d["store"] = False
    if f.compute: d["compute"] = f.compute if isinstance(f.compute, str) else "function"
    if f.related: d["related"] = ".".join(f.related) if isinstance(f.related, (list, tuple)) else f.related
    if f.type == "selection" and isinstance(f.selection, list): d["selection"] = [k for k, _v in f.selection]
    if getattr(f, "inverse_name", None): d["inverse_name"] = f.inverse_name
    if f._module: d["module"] = f._module
    fields[fname] = d
info = {
    "model": Model._name, "description": Model._description, "table": Model._table,
    "transient": Model._transient, "abstract": Model._abstract, "rec_name": Model._rec_name,
    "order": Model._order, "inherit": Model._inherit if isinstance(Model._inherit, list) else [Model._inherit] if Model._inherit else [],
    "inherits": dict(Model._inherits), "modules": sorted({f._module for f in Model._fields.values() if f._module} | ({Model._module} if Model._module else set())),
    "field_count": len(Model._fields), "fields": fields,
}
try:
    info["views"] = env["ir.ui.view"].search_read([("model", "=", Model._name)], ["name", "type", "xml_id", "inherit_id", "priority"], order="type,priority,id")
    for v in info["views"]:
        v["inherit_id"] = v["inherit_id"] and v["inherit_id"][1]
    info["records"] = None
    if not Model._abstract and Model._auto:
        env.cr.execute("SELECT count(*) FROM " + Model._table)
        info["records"] = env.cr.fetchone()[0]
except Exception as exc:
    info["views_error"] = str(exc)
print(json.dumps(info, indent=1, default=str))
"""

XMLID_CODE = r"""
import json
ref = %(ref)r
try:
    rec = env.ref(ref)
except Exception as exc:
    print("not found: " + ref + " (" + str(exc) + ")"); raise SystemExit
out = {"xmlid": ref, "model": rec._name, "id": rec.id, "display_name": rec.display_name}
if rec._name == "ir.ui.view":
    out.update(type=rec.type, model_target=rec.model, inherit_id=rec.inherit_id.xml_id or rec.inherit_id.id, arch=rec.arch)
elif rec._name == "ir.actions.act_window":
    out.update(res_model=rec.res_model, view_mode=rec.view_mode, domain=rec.domain, context=rec.context)
elif rec._name == "ir.ui.menu":
    out.update(parent=rec.parent_id.complete_name if rec.parent_id else None, action=str(rec.action) if rec.action else None)
elif rec._name == "ir.model.access":
    out.update(model=rec.model_id.model, group=rec.group_id.full_name if rec.group_id else None, perms=[rec.perm_read, rec.perm_write, rec.perm_create, rec.perm_unlink])
elif rec._name == "res.groups":
    out.update(full_name=rec.full_name, users=len(rec.users))
else:
    out["fields"] = {k: v for k, v in rec.read()[0].items() if k not in ("create_uid", "write_uid", "create_date", "write_date")}
print(json.dumps(out, indent=1, default=str))
"""


def t_odoo_model_info(a):
    model = (a.get("model") or "").strip()
    if not model:
        return text_result("model is required (e.g. sale.order)", True)
    return t_odoo_shell({"code": MODEL_INFO_CODE % {"model": model, "all": bool(a.get("all_fields"))},
                         "database": a.get("database"), "timeout": 120})


def t_odoo_xmlid(a):
    ref = (a.get("ref") or "").strip()
    if not ref or "." not in ref:
        return text_result("ref is required: module.record_id", True)
    return t_odoo_shell({"code": XMLID_CODE % {"ref": ref}, "database": a.get("database"), "timeout": 120})


def t_odoo_logs_since(a):
    since = (a.get("since") or "").strip()
    marker = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
    args = ["--since", since] if since else ["-n", "50"]
    if a.get("grep"):
        args += ["-g", a["grep"]]
    rc, t = script("logs", *args)
    return text_result(f"{t}\n\n-- marker: {marker}  (pass it as 'since' next time to read only what follows)", rc != 0)


def t_odoo_module_list(a):
    cache = f"{ROOT}/.data/volumes/odoo-container/cache/.modules_list"
    try:
        with open(cache) as fh:
            known = fh.read().strip().splitlines()[-1].split("|")
    except (OSError, IndexError):
        return text_result("module cache not available yet (start Odoo once)", True)
    pat = (a.get("pattern") or "").lower()
    mods = sorted(m for m in known if pat in m.lower())
    return text_result("\n".join(mods) if mods else "(no match)")


TOOLS = [
    ("odoo_status", t_odoo_status,
     "Stack overview: containers, Odoo process state, selected database, versions, URLs and the .env runtime settings. Call this first.",
     {}),
    ("odoo_start", t_odoo_start,
     "Start the Odoo process if stopped (wait=true blocks until ready and reports log errors).",
     {"wait": {"type": "boolean", "default": True}}),
    ("odoo_stop", t_odoo_stop, "Stop the Odoo process (container stays up).", {}),
    ("odoo_restart", t_odoo_restart,
     "Restart Odoo without updating modules (~2s). wait=true blocks until ready and reports log errors.",
     {"wait": {"type": "boolean", "default": True}}),
    ("odoo_update", t_odoo_update,
     "Restart Odoo with -u <modules> to load Python/XML changes. Comma-separated, patterns allowed (my_*), 'all' for everything. "
     "Returns the ready/error report of the start (exit code 2 = started with errors, details included).",
     {"modules": {"type": "string"}, "keep": {"type": "boolean", "default": False, "description": "Save as ODOO_UPDATE default"},
      "wait": {"type": "boolean", "default": True},
      "database": {"type": "string", "description": "default: SELECTED_DB; name, comma list or 'all'. Odoo then serves only these until the next restart"}},
     ["modules"]),
    ("odoo_logs", t_odoo_logs,
     "Read the Odoo logs pane. lines (default 100), grep (case-insensitive filter), errors_only (ERROR/CRITICAL/Traceback blocks of the current run), "
     "level (DEBUG|INFO|WARNING|ERROR|CRITICAL: every record of the current run at that level and above, with its traceback lines; ignores lines).",
     {"lines": {"type": "integer", "default": 100}, "grep": {"type": "string"}, "errors_only": {"type": "boolean", "default": False},
      "level": {"type": "string", "enum": ["DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"]}}),
    ("odoo_wait_ready", t_odoo_wait_ready,
     "Block until the current Odoo start finished; returns ready/timeout and the error blocks if any.",
     {"timeout": {"type": "integer", "default": 120}}),
    ("odoo_shell", t_odoo_shell,
     "Run Python code in 'odoo shell' (env, self=admin user available; print() to output). "
     "The transaction is ROLLED BACK at the end unless the code calls env.cr.commit(). Use for ORM inspection, data fixes, tests.",
     {"code": {"type": "string"}, "database": {"type": "string", "description": "default: SELECTED_DB"},
      "timeout": {"type": "integer", "default": 300}}, ["code"]),
    ("odoo_shell_commit", t_odoo_shell_commit,
     "Same as odoo_shell but COMMITS the transaction at the end (env.cr.commit() is appended; nothing is committed if the code raises). "
     "Use only for intended data changes, after the user agreed.",
     {"code": {"type": "string"}, "database": {"type": "string", "description": "default: SELECTED_DB"},
      "timeout": {"type": "integer", "default": 300}}, ["code"]),
    ("odoo_test", t_odoo_test,
     "Run the Odoo tests of modules on a throwaway database (fresh DB with demo data and -i, or on_database=<db> to clone it and -u). "
     "The running Odoo is not affected. Returns the test lines, errors and the summary; isError when a test failed. "
     "tags = Odoo --test-tags (':TestClass.test_method', '/module', 'at_install,post_install').",
     {"modules": {"type": "string"}, "tags": {"type": "string"}, "on_database": {"type": "string"},
      "keep": {"type": "boolean", "default": False, "description": "Keep the test database for inspection"},
      "no_demo": {"type": "boolean", "default": False}, "verbose": {"type": "boolean", "default": False},
      "coverage": {"type": "boolean", "default": False, "description": "Line coverage report of the tested modules (coverage.py)"},
      "timeout": {"type": "integer", "default": 1800}}, ["modules"]),
    ("odoo_model_info", t_odoo_model_info,
     "Describe a model as loaded in the database: inheritance (_inherit/_inherits), modules, fields (type, comodel, required, "
     "compute/related, selection) and its views (name, type, xml_id, inherit). JSON output.",
     {"model": {"type": "string", "description": "technical name, e.g. sale.order"},
      "all_fields": {"type": "boolean", "default": False, "description": "include id/display_name/create_* /write_*"},
      "database": {"type": "string", "description": "default: SELECTED_DB"}}, ["model"]),
    ("odoo_xmlid", t_odoo_xmlid,
     "Resolve an xml id (module.name) to its record: model, id, and the useful content (view arch and inherit, action target, menu path, access rule...). JSON output.",
     {"ref": {"type": "string"}, "database": {"type": "string", "description": "default: SELECTED_DB"}}, ["ref"]),
    ("odoo_logs_since", t_odoo_logs_since,
     "Incremental log reading for agents that loop: returns the log lines after 'since' (UTC 'YYYY-MM-DD HH:MM:SS', the marker returned by the previous call) "
     "and a new marker. Without 'since': the last 50 lines and a marker.",
     {"since": {"type": "string"}, "grep": {"type": "string"}}),
    ("odoo_module_list", t_odoo_module_list,
     "List known module names (addons + odoo + enterprise), optionally filtered by a substring.",
     {"pattern": {"type": "string"}}),
    ("db_list", t_db_list, "List databases with size and Odoo version; the selected one is marked.", {}),
    ("db_select", t_db_select, "Set SELECTED_DB and reboot Odoo on it (created on start if missing).",
     {"name": {"type": "string"}}, ["name"]),
    ("db_backup", t_db_backup, "Backup a database to ./db_files/<name>_<date>.zip (filestore optional).",
     {"name": {"type": "string", "description": "default: SELECTED_DB"}, "filestore": {"type": "boolean", "default": False},
      "keep": {"type": "integer", "description": "rotation: keep only the N most recent backups of this database"}}),
    ("db_restore", t_db_restore,
     "Restore a backup into <name> (replaced if it exists) from a file under ./db_files or the latest backup of <name> (last=true). "
     "sanitize=true neutralizes crons/mail and anonymizes emails.",
     {"name": {"type": "string"}, "file": {"type": "string", "description": "file name under ./db_files"},
      "last": {"type": "boolean", "default": False, "description": "most recent <name>_*.zip under ./db_files"},
      "switch": {"type": "boolean", "default": False}, "sanitize": {"type": "boolean", "default": True}}, ["name"]),
    ("db_drop", t_db_drop, "Drop a database and its filestore. Destructive: confirm with the user first.",
     {"name": {"type": "string"}}, ["name"]),
    ("db_clone", t_db_clone, "Copy a database (and filestore) to a new name.",
     {"source": {"type": "string"}, "destination": {"type": "string"}, "force": {"type": "boolean", "default": False}},
     ["source", "destination"]),
    ("db_query", t_db_query, "Run a SQL query with psql (CSV output). Read-only queries preferred; writes bypass the ORM.",
     {"sql": {"type": "string"}, "database": {"type": "string", "description": "default: SELECTED_DB"}}, ["sql"]),
    ("conf_set", t_conf_set,
     "Write a .env runtime setting: SELECTED_DB, ODOO_UPDATE, ODOO_ARGS, ODOO_VERSION, ODOO_BUILD, PYTHON_VERSION, POSTGRES_VERSION. Empty value clears it.",
     {"variable": {"type": "string"}, "value": {"type": "string"}}, ["variable"]),
    ("check_versions", t_check_versions,
     "Installed vs wanted (.env) vs latest nightly versions, plus the series of the mounted Odoo/Enterprise repos; says if a rebuild or a pull is needed.", {}),
    ("repos_pull", t_repos_pull,
     "Checkout the mounted ENTERPRISE_PATH / ODOO_PATH git repos on the ODOO_VERSION branch at the ODOO_BUILD commit (or build='latest'). "
     "Odoo refuses to start when a repo is on another series.",
     {"repo": {"type": "string", "enum": ["odoo", "enterprise"]}, "build": {"type": "string"},
      "force": {"type": "boolean", "default": False, "description": "Discard local changes"}}),
    ("translation_export", t_translation_export,
     "Re-export i18n/<lang>.po of modules (default fr_FR). modules: comma list / patterns, or all=true.",
     {"modules": {"type": "string"}, "all": {"type": "boolean", "default": False}, "language": {"type": "string"},
      "pot": {"type": "boolean", "default": False}}),
    ("pre_commit", t_pre_commit, "Run the pre-commit hooks on every module (optionally of one addons sub-folder). Modifies files in place; isError when a hook reported issues (re-run to confirm the fixes).",
     {"folder": {"type": "string"}}),
    ("requirements_install", t_requirements_install, "Install the addons requirements.txt in the Odoo venv.", {}),
]


def tool_descriptors():
    out = []
    for name, _fn, desc, props, *req in TOOLS:
        schema = {"type": "object", "properties": props}
        if req and req[0]:
            schema["required"] = req[0]
        out.append({"name": name, "description": desc, "inputSchema": schema})
    return out


TOOL_FN = {t[0]: t[1] for t in TOOLS}

PROMPTS = [
    {"name": "migrate_module", "description": "Step-by-step migration of a custom module to the Odoo version of this environment, using the tools.",
     "arguments": [{"name": "module", "description": "technical name", "required": True},
                   {"name": "from_version", "description": "source series, e.g. 17.0", "required": True}],
     "text": (
         "Migrate the custom module '{module}' from Odoo {from_version} to the version served by this environment (check odoo_status).\n"
         "1. odoo_module_list('{module}') then read its manifest, models, views, security, JS.\n"
         "2. For every model it inherits run odoo_model_info to confirm the fields and the inherited views it extends (odoo_xmlid on each inherit xml id) still exist in the target version; adapt renamed/removed ones.\n"
         "3. Apply the version-specific changes (attrs/states → invisible/readonly expressions, tree → list, OWL/ES module JS, _sql_constraints, name_get → _compute_display_name, etc.) for every intermediate version.\n"
         "4. Bump the manifest major version to the target, keep the author, remove the migrations/ folders that no longer apply.\n"
         "5. odoo_update('{module}') and read the report; on errors odoo_logs(errors_only=true), fix, repeat until it starts clean.\n"
         "6. odoo_test('{module}') if the module has tests; otherwise odoo_shell to exercise the main flows.\n"
         "Report what changed and what remains to verify by hand (reports, JS screens).")},
    {"name": "debug_error", "description": "Diagnose the last Odoo errors from the logs and propose a fix.",
     "arguments": [],
     "text": ("Call odoo_logs(errors_only=true). For each traceback identify the module and file at fault, explain the cause in two sentences, "
              "inspect the model with odoo_model_info / the record with odoo_xmlid or db_query when useful, then propose the minimal fix. "
              "After editing, odoo_update(<module>) and confirm the error is gone.")},
]


# ----------------------------------------------------------------------------
# JSON-RPC / MCP
# ----------------------------------------------------------------------------
def respond(msg):
    sys.stdout.write(json.dumps(msg) + "\n")
    sys.stdout.flush()


def handle(req):
    method = req.get("method")
    rid = req.get("id")
    params = req.get("params") or {}
    if method == "initialize":
        version = params.get("protocolVersion")
        if version not in PROTOCOL_VERSIONS:
            version = PROTOCOL_VERSIONS[-1]
        return {"jsonrpc": "2.0", "id": rid, "result": {
            "protocolVersion": version,
            "capabilities": {"tools": {}, "prompts": {}},
            "serverInfo": SERVER_INFO,
            "instructions": (
                f"Odoo dev environment '{PROJECT}'. Start with odoo_status. After editing module code call "
                "odoo_update(modules) and read its report; use odoo_logs(errors_only=true) for tracebacks, "
                "odoo_shell for ORM inspection (odoo_shell_commit to persist), odoo_model_info / odoo_xmlid to inspect models, fields and views, "
                "odoo_logs_since to read logs incrementally, odoo_test to run module tests, db_query for SQL. "
                "Destructive tools (db_drop, db_restore, odoo_shell_commit) must be confirmed with the user."),
        }}
    if method == "ping":
        return {"jsonrpc": "2.0", "id": rid, "result": {}}
    if method == "tools/list":
        return {"jsonrpc": "2.0", "id": rid, "result": {"tools": tool_descriptors()}}
    if method == "prompts/list":
        return {"jsonrpc": "2.0", "id": rid, "result": {"prompts": [
            {"name": p["name"], "description": p["description"], "arguments": p["arguments"]} for p in PROMPTS]}}
    if method == "prompts/get":
        prompt = next((p for p in PROMPTS if p["name"] == params.get("name")), None)
        if not prompt:
            return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32602, "message": f"Unknown prompt: {params.get('name')}"}}
        args = params.get("arguments") or {}
        text = prompt["text"].format(**{a["name"]: args.get(a["name"], "") for a in prompt["arguments"]})
        return {"jsonrpc": "2.0", "id": rid, "result": {"description": prompt["description"],
                "messages": [{"role": "user", "content": {"type": "text", "text": text}}]}}
    if method == "tools/call":
        name = params.get("name")
        fn = TOOL_FN.get(name)
        if not fn:
            return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32602, "message": f"Unknown tool: {name}"}}
        try:
            result = fn(params.get("arguments") or {})
        except KeyError as exc:
            result = text_result(f"missing argument: {exc}", True)
        except Exception as exc:  # noqa: BLE001 - report any failure to the client
            result = text_result(f"{type(exc).__name__}: {exc}", True)
        return {"jsonrpc": "2.0", "id": rid, "result": result}
    if method and method.startswith("notifications/"):
        return None
    if rid is None:
        return None
    return {"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": f"Method not found: {method}"}}


def serve():
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            respond({"jsonrpc": "2.0", "id": None, "error": {"code": -32700, "message": "Parse error"}})
            continue
        reply = handle(req)
        if reply is not None:
            respond(reply)


# ----------------------------------------------------------------------------
# Streamable HTTP transport (stateless): POST /mcp with one JSON-RPC message
# (or a batch) → JSON reply; notifications → 202. GET /health for monitoring.
# ----------------------------------------------------------------------------
class McpHandler(BaseHTTPRequestHandler):
    server_version = f"odoo-mcp/{SERVER_INFO['version']}"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # one line per request on stderr, except the polls of the hub / status loop
        if self.path.rstrip("/") not in ("/health", "/status"):
            sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        if body:
            self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        if self.path.rstrip("/") == "/health":
            self._send(200, json.dumps({"status": "ok", "project": PROJECT, "tools": len(TOOLS)}).encode())
        elif self.path.rstrip("/") == "/status":   # written every 2s by the status loop (hub tabs)
            try:
                with open("/var/shared/status.json", "rb") as fh:
                    self._send(200, fh.read())
            except OSError:
                self._send(503, json.dumps({"error": "status not available yet"}).encode())
        elif self.path.rstrip("/") == "/mcp":
            self._send(405)  # no server-initiated stream
        else:
            self._send(404)

    def do_DELETE(self):
        self._send(200 if self.path.rstrip("/") == "/mcp" else 404)

    def do_POST(self):
        if self.path.rstrip("/") != "/mcp":
            return self._send(404)
        length = int(self.headers.get("Content-Length") or 0)
        try:
            payload = json.loads(self.rfile.read(length) or b"null")
        except json.JSONDecodeError:
            return self._send(400, json.dumps({"jsonrpc": "2.0", "id": None,
                                               "error": {"code": -32700, "message": "Parse error"}}).encode())
        msgs = payload if isinstance(payload, list) else [payload]
        replies = [r for r in (handle(m) for m in msgs if isinstance(m, dict)) if r is not None]
        if not replies:
            return self._send(202)
        body = replies if isinstance(payload, list) else replies[0]
        self._send(200, json.dumps(body).encode())


def serve_http(port):
    httpd = ThreadingHTTPServer(("0.0.0.0", port), McpHandler)
    httpd.daemon_threads = True
    sys.stderr.write(f"odoo-mcp: {PROJECT} listening on http://0.0.0.0:{port}/mcp ({len(TOOLS)} tools)\n")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass


# ----------------------------------------------------------------------------
# CLI helpers: --config / --tools / --test
# ----------------------------------------------------------------------------
def client_config():
    return {"mcpServers": {f"odoo-{PROJECT}": {"url": MCP_URL}}}


def self_test(url=None):
    if url:
        def call(msg):
            req = urllib.request.Request(url, data=json.dumps(msg).encode(),
                                         headers={"Content-Type": "application/json", "Accept": "application/json"})
            with urllib.request.urlopen(req, timeout=120) as resp:
                return json.loads(resp.read())
        print(f"transport    : http {url}")
    else:
        proc = subprocess.Popen([sys.executable, __file__], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)

        def call(msg):
            proc.stdin.write(json.dumps(msg) + "\n")
            proc.stdin.flush()
            return json.loads(proc.stdout.readline())
        print("transport    : stdio (child process)")

    init = call({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                 "params": {"protocolVersion": PROTOCOL_VERSIONS[0], "capabilities": {}, "clientInfo": {"name": "self-test", "version": "0"}}})
    print(f"initialize   : protocol {init['result']['protocolVersion']}, server {init['result']['serverInfo']['name']}")
    tools = call({"jsonrpc": "2.0", "id": 2, "method": "tools/list"})["result"]["tools"]
    print(f"tools/list   : {len(tools)} tools")
    status = call({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "odoo_status", "arguments": {}}})["result"]
    first = status["content"][0]["text"].splitlines()
    print(f"odoo_status  : {'error' if status.get('isError') else 'ok'} ({len(first)} lines)")
    if not url:
        proc.stdin.close()
        proc.wait(timeout=10)
    print("\nMCP server OK. Client configuration: python3 server.py --config")


def arg_value(argv, flag, default=None):
    if flag in argv:
        i = argv.index(flag)
        if i + 1 < len(argv) and not argv[i + 1].startswith("-"):
            return argv[i + 1]
    return default


def main(argv):
    if "--serve" in argv:
        serve_http(int(arg_value(argv, "--serve", MCP_PORT)))
    elif "--config" in argv:
        print(json.dumps(client_config(), indent=2))
        print(f"\n# Cursor: ~/.cursor/mcp.json (or .cursor/mcp.json in the workspace)\n"
              f"# Claude Desktop: claude_desktop_config.json\n"
              f"# The server runs in '{PROJECT}_utils' (utils: mcp). Details: AGENTS.md", file=sys.stderr)
    elif "--tools" in argv:
        for t in tool_descriptors():
            req = t["inputSchema"].get("required", [])
            args = ", ".join(f"{k}{'*' if k in req else ''}" for k in t["inputSchema"]["properties"])
            print(f"{t['name']}({args})\n    {t['description']}")
    elif "--test" in argv:
        self_test(arg_value(argv, "--test"))
    elif "-h" in argv or "--help" in argv:
        print(__doc__.strip())
    else:
        serve()


if __name__ == "__main__":
    main(sys.argv[1:])
