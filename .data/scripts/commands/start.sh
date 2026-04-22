#!/bin/bash
# ============================================================================
# start - Start Odoo process
# ============================================================================
# Usage: start [-h|--help]
# Alias: s
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "start - Start Odoo process"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       start"
    echo "       s"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Starts Odoo in its tmux pane with full configuration:"
    echo "       SELECTED_DB, ODOO_ARGS, and ODOO_UPDATE from .env"
    echo ""
    printf "   ${CPRIMARY}CONFIGURATION${RST} (from .env)\n"
    echo "       SELECTED_DB    Database to use"
    echo "       ODOO_ARGS      Additional Odoo arguments"
    echo "       ODOO_UPDATE    Module(s) to update on start"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if docker exec "$ODOO_CONTAINER" pgrep -x odoo >/dev/null 2>&1; then
    echo "Odoo is already running"
    exit 0
fi

ADDON_PATHS=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)

[ -n "$ODOO_UPDATE" ] && ODOO_UPDATE=$(expand_modules "$ODOO_UPDATE")
ODOO_CMD=$(build_odoo_cmd "$ODOO_UPDATE")

echo "Starting Odoo..."

docker exec -i "$ODOO_CONTAINER" tee /tmp/.odoo_runner.sh > /dev/null << RUNNER_EOF
#!/bin/bash
/usr/local/bin/odoo_header.sh "$ODOO_CMD" "$ADDON_PATHS"
exec $ODOO_CMD
RUNNER_EOF
run_odoo_script

echo "✓ Odoo started"
