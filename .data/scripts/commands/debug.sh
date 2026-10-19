#!/bin/bash
set -uo pipefail
# ============================================================================
# debug - Run Odoo under debugpy and attach Cursor / VS Code to it
# ============================================================================
# Usage: debug [on|off|status]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "debug" "Python debugger: Odoo under debugpy, launch.json for the IDE"
    h_sec "USAGE"
    h_use "debug on       restart Odoo under debugpy, write .vscode/launch.json"
    h_use "debug off      back to a plain start"
    h_use "debug          state and attach port"
    h_sec "DESCRIPTION"
    h_text "debugpy listens on port 5678 inside the odoo container, published on"
    h_text "the host (free port chosen by Docker, or DEBUGPY_PORT from .env). The"
    h_text "'Attach: Odoo (<project>)' configuration written in .vscode/launch.json"
    h_text "of the project connects to it with the path mappings of your addons,"
    h_text "ODOO_PATH and ENTERPRISE_PATH. Breakpoints work in your modules right"
    h_text "away; in Odoo's own code when ODOO_PATH is on the build commit (pull)."
    h_text "If your IDE workspace is a parent folder, copy that configuration into"
    h_text "the workspace launch.json. DEBUGPY=true is kept across restarts (u, r)."
    h_sec "EXAMPLES"
    h_ex "debug on" ""
    h_text "Fixed port: DEBUGPY_PORT in .env (hub config), then docker compose up -d odoo"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
ACTION="${1:-status}"
case "$ACTION" in -h|--help) show_help; exit 0 ;; on|off|status) ;; *) die "Unknown option: $1" "See: debug --help" ;; esac
[ $# -gt 1 ] && die "Usage: debug [on|off|status]"

require_odoo_container
require_host_project_dir
LAUNCH="${_PROJECT_ROOT}/.vscode/launch.json"

write_launch_json() {   # write_launch_json PORT
    mkdir -p "${_PROJECT_ROOT}/.vscode"
    HOST_DIR="$HOST_PROJECT_DIR" PORT="$1" PROJECT="$PROJECT" ADDONS="${ADDONS_PATH:-./addons}" \
    ODOO_SRC="${ODOO_PATH:-}" ENTERPRISE="${ENTERPRISE_PATH:-}" LAUNCH="$LAUNCH" python3 - <<'PY'
import json, os
host, port, project = os.environ["HOST_DIR"], int(os.environ["PORT"]), os.environ["PROJECT"]
def absp(rel): return os.path.normpath(os.path.join(host, rel))
maps = [{"localRoot": absp(os.environ["ADDONS"]), "remoteRoot": "/mnt/extra-addons"}]
if os.environ["ODOO_SRC"]: maps.append({"localRoot": absp(os.environ["ODOO_SRC"]), "remoteRoot": "/opt/odoo"})
if os.environ["ENTERPRISE"] and ".enterprise_placeholder" not in os.environ["ENTERPRISE"]:
    maps.append({"localRoot": absp(os.environ["ENTERPRISE"]), "remoteRoot": "/mnt/enterprise-addons"})
conf = {"name": f"Attach: Odoo ({project})", "type": "debugpy", "request": "attach",
        "connect": {"host": "localhost", "port": port}, "pathMappings": maps, "justMyCode": False}
path = os.environ["LAUNCH"]
try:
    with open(path) as f: data = json.load(f)
except (OSError, ValueError):
    data = {"version": "0.2.0", "configurations": []}
data["configurations"] = [c for c in data.get("configurations", []) if c.get("name") != conf["name"]] + [conf]
with open(path, "w") as f: json.dump(data, f, indent=2); f.write("\n")
PY
}

case "$ACTION" in
    status)
        PORT=$(debugpy_host_port)
        if [ "${DEBUGPY:-false}" = "true" ]; then ui_kv "debugpy" "${CSUCCESS}on${RST}"; else ui_kv "debugpy" "${CMUTED}off${RST} (debug on)"; fi
        if [ -n "$PORT" ]; then ui_kv "Attach" "localhost:${PORT}"
        else ui_kv "Attach" "${CWARN}port not published${RST} ${CMUTED}— recreate odoo: docker compose up -d odoo${RST}"; fi
        [ -f "$LAUNCH" ] && ui_kv "launch.json" "${LAUNCH#${_PROJECT_ROOT}/}"
        exit 0 ;;
    on)
        PORT=$(debugpy_host_port)
        [ -z "$PORT" ] && die "debugpy port not published on the host" "The odoo container predates this feature: docker compose up -d odoo (from the host), then debug on"
        set_env_value DEBUGPY true; export DEBUGPY=true
        write_launch_json "$PORT" || die "Could not write ${LAUNCH}"
        ui_step "Restarting Odoo under debugpy..."
        launch_odoo "" || exit 1
        ui_ok "debugpy listening — attach with 'Attach: Odoo (${PROJECT})' on localhost:${PORT}"
        ui_note "Configuration written in ${LAUNCH#${_PROJECT_ROOT}/} (copy it to your workspace launch.json if the IDE is opened on a parent folder)"
        ui_note "Breakpoints in your addons work right away; Odoo core needs ODOO_PATH on the build commit (pull)" ;;
    off)
        set_env_value DEBUGPY false; export DEBUGPY=false
        ui_step "Restarting Odoo without debugpy..."
        launch_odoo "" || exit 1
        ui_ok "debugpy off" ;;
esac
