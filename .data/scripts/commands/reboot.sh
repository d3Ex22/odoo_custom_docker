#!/bin/bash
# ============================================================================
# reboot - Restart the Odoo process (~2s, no module update)
# ============================================================================
# Usage: reboot [-h|--help] [-w|--wait]
# Alias: r
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "reboot (r)" "Restart the Odoo process"
    h_sec "USAGE"
    h_use "r [-w]"
    h_sec "OPTIONS"
    h_opt "-w, --wait" "Wait until Odoo is ready and report errors"
    h_sec "DESCRIPTION"
    h_text "Kills the Odoo process in its tmux pane and starts it again with"
    h_text "SELECTED_DB and ODOO_ARGS. ODOO_UPDATE is ignored on purpose:"
    h_text "use 'u' to restart with -u <modules>."
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
        *) die "Unknown option: $1" "See: r --help" ;;
    esac
done

require_odoo_container
ui_step "Restarting Odoo..."
launch_odoo || die "Failed to restart Odoo"
ui_ok "Odoo restarted"

$WAIT && exec bash "${_PROJECT_ROOT}/.data/scripts/internal/logs.sh" --wait
exit 0
