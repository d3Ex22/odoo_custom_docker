#!/bin/bash
# ============================================================================
# start - Start Odoo process
# ============================================================================
# Usage: start [-h|--help]
# Alias: s
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

show_help() {
    echo ""
    echo "start - Start Odoo process"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       start"
    echo "       s"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Starts Odoo in its tmux pane with full configuration:"
    echo "       SELECTED_DB, ODOO_ARGS, and ODOO_UPDATE from .env"
    echo ""
    printf "   ${C}CONFIGURATION${RST} (from .env)\n"
    echo "       SELECTED_DB    Database to use"
    echo "       ODOO_ARGS      Additional Odoo arguments"
    echo "       ODOO_UPDATE    Module(s) to update on start"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

CONTAINER="$ODOO_CONTAINER"
LOGS_COLOR="${LOGS_COLOR:-#8be9fd}"
LR=$((16#${LOGS_COLOR:1:2}))
LG=$((16#${LOGS_COLOR:3:2}))
LB=$((16#${LOGS_COLOR:5:2}))

if docker exec "$CONTAINER" pgrep -x odoo >/dev/null 2>&1; then
    echo "Odoo is already running"
    exit 0
fi

ADDON_PATHS=$(docker exec "$CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)

ODOO_CMD="odoo -c /etc/odoo/odoo.conf"
[ -n "$SELECTED_DB" ] && ODOO_CMD="$ODOO_CMD -d $SELECTED_DB"
[ -n "$ODOO_ARGS" ] && ODOO_CMD="$ODOO_CMD $ODOO_ARGS"
[ -n "$ODOO_UPDATE" ] && ODOO_CMD="$ODOO_CMD -u $ODOO_UPDATE"

[ -n "$ODOO_UPDATE" ] && /home/odoo/docker_dev/data/.docker/utils/commands/utils/check_modules.sh "$ODOO_UPDATE"

echo "Starting Odoo..."
PTY=$(docker exec "$CONTAINER" tmux list-panes -t odoo -F '#{pane_tty}' 2>/dev/null)
# Clear prompt line, print messages
docker exec "$CONTAINER" bash -c "printf '\\033[1A\\033[2K\\nDetected addon paths: \\033[38;2;${LR};${LG};${LB}m%s\\033[0m\\n' '$ADDON_PATHS' > $PTY"
docker exec "$CONTAINER" bash -c "printf 'Odoo started: \\033[38;2;${LR};${LG};${LB}m%s\\033[0m\\n\\n' '$ODOO_CMD' > $PTY"
docker exec "$CONTAINER" tmux send-keys -t odoo:0 "$ODOO_CMD" Enter
echo "✓ Odoo started"
