#!/bin/bash
# ============================================================================
# stop - Stop Odoo process
# ============================================================================
# Usage: stop [-h|--help]
# ============================================================================

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C=$(printf '\033[38;2;%s;%s;%sm' "$R" "$G" "$B")
RST=$(printf '\033[0m')

show_help() {
    echo ""
    echo "stop - Stop Odoo process"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       stop"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Sends Ctrl+C to the Odoo process in its tmux pane."
    echo "       The pane stays open, use 'start' to restart Odoo."
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

if ! docker exec "$CONTAINER" pgrep -x odoo >/dev/null 2>&1; then
    echo "Odoo is already stopped"
    exit 0
fi

echo "Stopping Odoo..."
docker exec "$CONTAINER" tmux send-keys -t odoo:0 C-c 2>/dev/null

# Wait for odoo to actually stop (max 2.5s)
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

# Wait for prompt to appear then write message
sleep 0.3
PTY=$(docker exec "$CONTAINER" tmux list-panes -t odoo -F '#{pane_tty}' 2>/dev/null)
# Clear current line, print message, then trigger new prompt
docker exec "$CONTAINER" bash -c "printf '\\r\\033[KOdoo stopped\\n\\n' > $PTY"
docker exec "$CONTAINER" tmux send-keys -t odoo:0 "" Enter
echo "✓ Odoo stopped"
