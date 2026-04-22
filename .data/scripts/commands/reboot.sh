#!/bin/bash
# ============================================================================
# reboot - Restart Odoo service
# ============================================================================
# Usage: reboot [-h|--help]
# Alias: r
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "reboot - Restart Odoo service"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       reboot"
    echo "       r"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Stops the current Odoo process and restarts it with the"
    echo "       same configuration. Uses tmux to manage the process."
    echo ""
    printf "   ${CPRIMARY}CONFIGURATION${RST} (from .env)\n"
    echo "       SELECTED_DB     Database to use"
    echo "       ODOO_ARGS       Additional Odoo arguments"
    echo ""
    printf "   ${CPRIMARY}NOTE${RST}\n"
    echo "       ODOO_UPDATE is intentionally ignored by reboot."
    echo "       Use 'update' (u) to restart with -u <modules>."
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo "Restarting Odoo..."

ADDON_PATHS=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)
ODOO_CMD=$(build_odoo_cmd)

stop_odoo || exit 1
sleep 0.3

docker exec -i "$ODOO_CONTAINER" tee /tmp/.odoo_runner.sh > /dev/null << RUNNER_EOF
#!/bin/bash
/usr/local/bin/odoo_header.sh "$ODOO_CMD" "$ADDON_PATHS"
exec $ODOO_CMD
RUNNER_EOF
run_odoo_script

echo "✓ Odoo restarted"
