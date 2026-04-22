#!/bin/bash
# ============================================================================
# shell - Open Odoo shell in a new pane
# ============================================================================
# Usage: shell [-h|--help] [database]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "shell - Open Odoo shell in a new pane"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       shell [database]"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       database    ${CPRIMARY}Database name (default: SELECTED_DB)    ${RST}"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Opens the Odoo shell in a new vertical tmux pane"
    echo "       (50% width) in the utils terminal."
    echo "       Exit and close the pane with 'exit()' in the shell terminal."
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       shell                  ${CPRIMARY}Shell with SELECTED_DB          ${RST}"
    echo "       shell mydb             ${CPRIMARY}Shell with specific DB          ${RST}"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

DBNAME="$1"
[ -z "$DBNAME" ] && DBNAME="${SELECTED_DB}"

if [ -z "$DBNAME" ]; then
    echo "❌ No database specified and no SELECTED_DB in .env"
    echo "   Usage: shell <database>"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${ODOO_CONTAINER}$"; then
    echo "❌ Odoo container is not running"
    exit 1
fi

PANE_COUNT=$(sudo tmux -S /tmp/tmux-0/default list-panes -t utils 2>/dev/null | wc -l)
if [ "$PANE_COUNT" -gt 2 ]; then
    echo "⚠️  Shell pane already open"
    echo "   Close it with 'exit' or Ctrl+D first"
    exit 1
fi

SHELL_CMD="docker exec -it $ODOO_CONTAINER odoo shell -c /etc/odoo/odoo.conf -d $DBNAME"

echo "Opening Odoo shell for '$DBNAME'..."
sudo tmux -S /tmp/tmux-0/default split-window -t utils:0.1 -h -p 50 "$SHELL_CMD"
echo "✓ Shell opened in side pane"
echo "  Exit with 'exit' or Ctrl+D"
