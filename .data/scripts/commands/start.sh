#!/bin/bash
# ============================================================================
# start - Start the Odoo process (if stopped)
# ============================================================================
# Usage: start [-h|--help] [-w|--wait]
# Alias: s
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "start (s)" "Start the Odoo process"
    h_sec "USAGE"
    h_use "s [-w]"
    h_sec "OPTIONS"
    h_opt "-w, --wait" "Wait until Odoo is ready and report errors"
    h_sec "DESCRIPTION"
    h_text "Starts Odoo in its tmux pane with SELECTED_DB, ODOO_ARGS and"
    h_text "ODOO_UPDATE (-u) from .env. Does nothing if Odoo already runs."
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
WAIT=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -w|--wait) WAIT=true; shift ;;
        *) die "Unknown option: $1" "See: s --help" ;;
    esac
done

require_odoo_container
if odoo_process_running; then
    ui_ok "Odoo is already running"
    ui_note "r to restart, u <module> to update"
    exit 0
fi

MODULES=""
if [ -n "${ODOO_UPDATE:-}" ]; then
    refresh_modules_cache "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)"
    MODULES=$(expand_modules "$ODOO_UPDATE")
    [ -n "$MODULES" ] && ui_note "ODOO_UPDATE=${MODULES}"
fi

ui_step "Starting Odoo..."
launch_odoo "$MODULES" || die "Failed to start Odoo"
ui_ok "Odoo started"

$WAIT && exec bash "${_PROJECT_ROOT}/.data/scripts/internal/logs.sh" --wait
exit 0
