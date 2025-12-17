#!/bin/bash
# ============================================================================
# shell - Open Odoo shell in a new pane
# ============================================================================
# Usage: shell [-h|--help] [database]
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

TTYD_UTILS="${PROJECT}_ttyd_utils"

show_help() {
    echo ""
    echo "shell - Open Odoo shell in a new pane"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       shell [database]"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       database    ${C}Database name (default: SELECTED_DB)    ${RST}"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Opens the Odoo shell in a new vertical tmux pane"
    echo "       (50% width) in ttyd_utils terminal."
    echo "       Exit and close the pane with 'exit()' in the shell terminal."
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       shell                  ${C}Shell with SELECTED_DB          ${RST}"
    echo "       shell mydb             ${C}Shell with specific DB          ${RST}"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

DBNAME="$1"
[ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"

if [ -z "$DBNAME" ]; then
    echo "❌ No database specified and no SELECTED_DB in .env"
    echo "   Usage: shell <database>"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${ODOO_CONTAINER}$"; then
    echo "❌ Odoo container is not running"
    exit 1
fi

PANE_COUNT=$(docker exec "$TTYD_UTILS" tmux list-panes -t utils 2>/dev/null | wc -l)
if [ "$PANE_COUNT" -gt 2 ]; then
    echo "⚠️  Shell pane already open"
    echo "   Close it with 'exit' or Ctrl+D first"
    exit 1
fi

SHELL_CMD="docker exec -it $ODOO_CONTAINER odoo shell -c /etc/odoo/odoo.conf -d $DBNAME"

echo "Opening Odoo shell for '$DBNAME'..."
docker exec "$TTYD_UTILS" tmux split-window -t utils:0.1 -h -p 50 "$SHELL_CMD"
echo "✓ Shell opened in side pane"
echo "  Exit with 'exit' or Ctrl+D"
