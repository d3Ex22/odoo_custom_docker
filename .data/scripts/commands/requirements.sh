#!/bin/bash
# ============================================================================
# requirements - Install the addons' requirements.txt in the Odoo venv
# ============================================================================
# Usage: requirements [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

show_help() {
    h_name "requirements" "Install addons requirements in the Odoo venv"
    h_sec "USAGE"
    h_use "requirements"
    h_sec "DESCRIPTION"
    h_text "Finds every requirements.txt under /mnt/extra-addons (deepest first)"
    h_text "and installs them with 'uv pip' in the Odoo virtualenv. Skipped when"
    h_text "nothing changed since the last run (hash cache). The same step runs"
    h_text "automatically when the odoo container starts."
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    "") ;;
    *) die "Unknown option: $1" "See: requirements --help" ;;
esac

require_odoo_container
open_pane
ui_step "Checking addons requirements..."
out=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/check_requirements.sh 2>&1)
echo "$out" | sed 's/^/  /'
if echo "$out" | grep -q "installed successfully"; then
    ui_ok "Requirements installed"
    ui_note "r to restart Odoo with the new packages"
elif echo "$out" | grep -qi "warning"; then
    ui_warn "Some requirements failed to install"
    exit 1
else
    ui_ok "Requirements up to date"
fi
