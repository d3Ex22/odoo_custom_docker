#!/bin/bash
# ============================================================================
# update - Update Odoo modules and restart
# ============================================================================
# Usage: update [-h|--help] [MODULE[,MODULE2,...]]
# Alias: u
# ============================================================================

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C="\033[38;2;${R};${G};${B}m"
RST="\033[0m"

show_help() {
    echo ""
    echo "update - Update Odoo modules and restart"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       update MODULE[,MODULE2,...]"
    echo "       update"
    echo "       u MODULE"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       MODULE    Module name(s) to update, comma-separated"
    echo "                 If omitted, uses ODOO_UPDATE from .env"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       update sale"
    echo "       update sale,purchase,stock"
    echo "       u base"
    echo ""
    printf "   ${C}CONFIGURATION${RST} (from .env)\n"
    echo "       ODOO_UPDATE    Default module(s) to update"
    echo "       SELECTED_DB    Database to use"
    echo "       ODOO_ARGS      Additional Odoo arguments"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

CONTAINER="${COMPOSE_PROJECT_NAME:-odoo}_odoo"
LOGS_COLOR="${LOGS_COLOR:-#8be9fd}"
LR=$((16#${LOGS_COLOR:1:2}))
LG=$((16#${LOGS_COLOR:3:2}))
LB=$((16#${LOGS_COLOR:5:2}))

if [ -n "$1" ]; then
    MODULES="$1"
elif [ -n "$ODOO_UPDATE" ]; then
    MODULES="$ODOO_UPDATE"
else
    echo "❌ No module specified"
    echo "   Usage: update MODULE[,MODULE2,...]"
    echo "   Or set ODOO_UPDATE in .env"
    exit 1
fi

/home/odoo/docker_dev/data/.docker/utils/commands/utils/check_modules.sh "$MODULES"

echo "Updating module(s): $MODULES"

ADDON_PATHS=$(docker exec "$CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)

ODOO_CMD="odoo -c /etc/odoo/odoo.conf"
[ -n "$SELECTED_DB" ] && ODOO_CMD="$ODOO_CMD -d $SELECTED_DB"
[ -n "$ODOO_ARGS" ] && ODOO_CMD="$ODOO_CMD $ODOO_ARGS"
ODOO_CMD="$ODOO_CMD -u $MODULES"

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
docker exec "$CONTAINER" bash -c "printf 'Odoo updated: \\033[38;2;${LR};${LG};${LB}m%s\\033[0m\\n\\n' '$ODOO_CMD' > $PTY"
docker exec "$CONTAINER" tmux send-keys -t odoo:0 "$ODOO_CMD" Enter

echo "✓ Odoo restarted with update: $MODULES"
