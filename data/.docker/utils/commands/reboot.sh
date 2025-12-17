#!/bin/bash
# ============================================================================
# reboot - Restart Odoo service
# ============================================================================
# Usage: reboot [-h|--help]
# Alias: r
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

show_help() {
    echo ""
    echo "reboot - Restart Odoo service"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       reboot"
    echo "       r"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Stops the current Odoo process and restarts it with the"
    echo "       same configuration. Uses tmux to manage the process."
    echo ""
    printf "   ${C}CONFIGURATION${RST} (from .env)\n"
    echo "       SELECTED_DB     Database to use"
    echo "       ODOO_ARGS       Additional Odoo arguments"
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

echo "Restarting Odoo..."

ADDON_PATHS=$(docker exec "$CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)

ODOO_CMD="odoo -c /etc/odoo/odoo.conf"
[ -n "$SELECTED_DB" ] && ODOO_CMD="$ODOO_CMD -d $SELECTED_DB"
[ -n "$ODOO_ARGS" ] && ODOO_CMD="$ODOO_CMD $ODOO_ARGS"

docker exec "$CONTAINER" tmux send-keys -t odoo:0 C-c 2>/dev/null

# Wait for odoo to stop (max 2.5s)
for i in {1..5}; do
    if ! docker exec "$CONTAINER" pgrep -x odoo >/dev/null 2>&1; then
        break
    fi
    sleep 0.5
done

# Check if odoo actually stopped
if docker exec "$CONTAINER" pgrep -x odoo >/dev/null 2>&1; then
    echo "❌ Failed to stop Odoo (timeout)"
    exit 1
fi
sleep 0.3

PTY=$(docker exec "$CONTAINER" tmux list-panes -t odoo -F '#{pane_tty}' 2>/dev/null)
# Clear prompt line, print messages
docker exec "$CONTAINER" bash -c "printf '\\033[1A\\033[2K\\nDetected addon paths: \\033[38;2;${LR};${LG};${LB}m%s\\033[0m\\n' '$ADDON_PATHS' > $PTY"
docker exec "$CONTAINER" bash -c "printf 'Odoo rebooted: \\033[38;2;${LR};${LG};${LB}m%s\\033[0m\\n\\n' '$ODOO_CMD' > $PTY"
docker exec "$CONTAINER" tmux send-keys -t odoo:0 "$ODOO_CMD" Enter

echo "✓ Odoo restarted"
