#!/bin/bash
# ============================================================================
# grok - Expose Odoo on the internet with an ngrok tunnel (side pane)
# ============================================================================
# Usage: grok [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "grok" "Expose Odoo on the internet with ngrok"
    h_sec "USAGE"
    h_use "grok"
    h_sec "REQUIREMENTS"
    h_text "NGROK_KEY in .env.secrets (or .env)"
    h_text "Token: https://dashboard.ngrok.com/get-started/your-authtoken"
    h_sec "DESCRIPTION"
    h_text "Starts 'ngrok http <odoo>:8069' in a side pane (1/3 width)."
    h_text "ngrok itself is downloaded on first use (kept in the shared volume)."
    h_text "The public URL is shown in that pane. Ctrl+C in the pane closes it."
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    "") ;;
    *) die "Unknown option: $1" "See: grok --help" ;;
esac

[ -z "${NGROK_KEY:-}" ] && die "NGROK_KEY is not set" \
    "Add NGROK_KEY=<token> to .env.secrets (git-ignored)" \
    "Token: https://dashboard.ngrok.com/get-started/your-authtoken"

require_odoo_container
ODOO_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$ODOO_CONTAINER" 2>/dev/null)
[ -z "$ODOO_IP" ] && die "Cannot resolve the Odoo container IP"

# ngrok is not part of the image: fetched once into the shared volume
NGROK=/var/shared/bin/ngrok
if [ ! -x "$NGROK" ]; then
    ui_step "Downloading ngrok (first use)..."
    ARCH=$(dpkg --print-architecture 2>/dev/null || echo amd64)
    mkdir -p "$(dirname "$NGROK")" \
        && curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-${ARCH}.tgz" | tar -xz -C "$(dirname "$NGROK")" \
        || die "Cannot download ngrok" "https://ngrok.com/download"
fi
pane_exists ngrok && die "An ngrok pane is already open" "Ctrl+C in it stops the tunnel"
# The token goes to ngrok's own config file, never into the pane script or ps.
"$NGROK" config add-authtoken "$NGROK_KEY" >/dev/null 2>&1 || die "ngrok refused the token" "Check NGROK_KEY in .env"
ui_step "Starting ngrok tunnel to ${ODOO_IP}:8069..."
if in_utils_terminal; then
    run_in_pane "ngrok" "33%" close "$NGROK" http "${ODOO_IP}:8069" || exit 1
    ui_ok "ngrok opened in a side pane"
    ui_note "Ctrl+C in the pane stops the tunnel"
    exit 0
fi
exec "$NGROK" http "${ODOO_IP}:8069"
