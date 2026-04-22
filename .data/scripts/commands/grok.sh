#!/bin/bash
# ============================================================================
# grok - Create secure tunnel with ngrok
# ============================================================================
# Usage: grok [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "grok - Create secure tunnel with ngrok"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       grok"
    echo ""
    printf "   ${CPRIMARY}REQUIREMENTS${RST}\n"
    echo "       NGROK_KEY in .env"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Creates a secure tunnel using ngrok to expose Odoo"
    echo "       to the internet. Opens in a side pane (1/3 width)."
    echo "       Press Ctrl+C in the pane to close ngrok."
    echo ""
    printf "   ${CPRIMARY}GET YOUR TOKEN${RST}\n"
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

PORT=8069

ODOO_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ODOO_CONTAINER" 2>/dev/null)

if [ -z "$ODOO_IP" ]; then
    echo "❌ Odoo container not running"
    exit 1
fi

PANE_COUNT=$(sudo tmux -S /tmp/tmux-0/default list-panes -t utils 2>/dev/null | wc -l)
if [ "$PANE_COUNT" -gt 2 ]; then
    echo "⚠️  Ngrok pane already open"
    echo "   Close it with Ctrl+C first"
    exit 1
fi

echo "Starting ngrok tunnel..."
echo "   Target: ${ODOO_IP}:${PORT}"
echo ""

NGROK_CMD="ngrok config add-authtoken '$NGROK_KEY' 2>/dev/null; ngrok http '${ODOO_IP}:${PORT}'"

sudo tmux -S /tmp/tmux-0/default split-window -t utils:0.1 -h -p 33 "$NGROK_CMD"

echo "✓ Ngrok opened in side pane"
echo "  Close with Ctrl+C in the ngrok pane"
