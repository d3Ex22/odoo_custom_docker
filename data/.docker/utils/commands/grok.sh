#!/bin/bash
# ============================================================================
# grok - Create secure tunnel with ngrok
# ============================================================================
# Usage: grok [-h|--help]
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
    echo "grok - Create secure tunnel with ngrok"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       grok"
    echo ""
    printf "   ${C}REQUIREMENTS${RST}\n"
    echo "       NGROK_KEY in .env"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Creates a secure tunnel using ngrok to expose Odoo"
    echo "       to the internet. Opens in a side pane (1/3 width)."
    echo "       Press Ctrl+C in the pane to close ngrok."
    echo ""
    printf "   ${C}GET YOUR TOKEN${RST}\n"
    echo "       https://dashboard.ngrok.com/get-started/your-authtoken"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ -z "$NGROK_KEY" ]; then
    echo "❌ NGROK_KEY not found in .env"
    echo "   Add NGROK_KEY=your_token to .env"
    echo "   Get token: https://dashboard.ngrok.com/get-started/your-authtoken"
    exit 1
fi

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
ODOO_CONTAINER="${PROJECT}_odoo"
TTYD_UTILS="${PROJECT}_ttyd_utils"
PORT=8069

ODOO_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ODOO_CONTAINER" 2>/dev/null)

if [ -z "$ODOO_IP" ]; then
    echo "❌ Odoo container not running"
    exit 1
fi

# Check if ngrok pane already exists
PANE_COUNT=$(docker exec "$TTYD_UTILS" tmux list-panes -t utils 2>/dev/null | wc -l)
if [ "$PANE_COUNT" -gt 2 ]; then
    echo "⚠️  Ngrok pane already open"
    echo "   Close it with Ctrl+C first"
    exit 1
fi

echo "Starting ngrok tunnel..."
echo "   Target: ${ODOO_IP}:${PORT}"
echo ""

# Build ngrok command
NGROK_CMD="ngrok config add-authtoken '$NGROK_KEY' 2>/dev/null; ngrok http '${ODOO_IP}:${PORT}'"

# Create vertical split pane in ttyd_utils tmux session (33% width, on the right)
docker exec "$TTYD_UTILS" tmux split-window -t utils:0.1 -h -p 33 "$NGROK_CMD"

echo "✓ Ngrok opened in side pane"
echo "  Close with Ctrl+C in the ngrok pane"
