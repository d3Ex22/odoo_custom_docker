#!/bin/bash
# ============================================================================
# stop - Stop Odoo process
# ============================================================================
# Usage: stop [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "stop - Stop Odoo process"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       stop"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Sends Ctrl+C to the Odoo process in its tmux pane."
    echo "       The pane stays open, use 'start' to restart Odoo."
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if ! docker exec "$ODOO_CONTAINER" pgrep -x odoo >/dev/null 2>&1; then
    echo "Odoo is already stopped"
    exit 0
fi

echo "Stopping Odoo..."
stop_odoo || exit 1
echo "✓ Odoo stopped"
