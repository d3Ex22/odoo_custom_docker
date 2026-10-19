#!/bin/bash
# ============================================================================
# stop - Stop the Odoo process (container stays up)
# ============================================================================
# Usage: stop [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "stop" "Stop the Odoo process"
    h_sec "USAGE"
    h_use "stop"
    h_sec "DESCRIPTION"
    h_text "Kills the Odoo process (SIGKILL — dev environment, instant). The"
    h_text "container and the logs pane stay up; use 's' to start Odoo again."
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    "") ;;
    *) die "Unknown option: $1" "See: stop --help" ;;
esac

require_odoo_container
if ! odoo_process_running; then
    ui_ok "Odoo is already stopped"
    exit 0
fi
stop_odoo || die "Failed to stop Odoo"
ui_ok "Odoo stopped"
ui_note "s to start it again"
