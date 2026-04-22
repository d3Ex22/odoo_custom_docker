#!/bin/bash
# ============================================================================
# update - Update Odoo modules and restart
# ============================================================================
# Usage: update [-h|--help] [MODULE[,MODULE2,...]]
# Alias: u
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "update - Update Odoo modules and restart"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       update MODULE[,MODULE2,...]"
    echo "       update"
    echo "       u MODULE"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       MODULE    Module name(s) to update, comma-separated"
    echo "                 Supports regex patterns: sale_*, sale_.*, sale_[a-m]*"
    echo "                 If omitted, uses ODOO_UPDATE from .env"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       update sale"
    echo "       update sale,purchase,stock"
    echo "       update sale_*"
    echo "       u base"
    echo ""
    printf "   ${CPRIMARY}CONFIGURATION${RST} (from .env)\n"
    echo "       ODOO_UPDATE    Default module(s) to update"
    echo "       SELECTED_DB    Database to use"
    echo "       ODOO_ARGS      Additional Odoo arguments"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ -n "$1" ]; then
    MODULES="$1"
elif [ -n "$ODOO_UPDATE" ]; then
    MODULES="$ODOO_UPDATE"
else
    echo "❌ No module specified"
    echo "   Usage: update MODULE[,MODULE2,...]"
    echo "   Or set ODOO_UPDATE via: conf ODOO_UPDATE <modules>"
    exit 1
fi

MODULES=$(expand_modules "$MODULES")
[ -z "$MODULES" ] && { echo "❌ No matching modules found"; exit 1; }

ADDON_PATHS=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)
ODOO_CMD=$(build_odoo_cmd "$MODULES")

stop_odoo || exit 1
sleep 0.3

docker exec -i "$ODOO_CONTAINER" tee /tmp/.odoo_runner.sh > /dev/null << RUNNER_EOF
#!/bin/bash
/usr/local/bin/odoo_header.sh "$ODOO_CMD" "$ADDON_PATHS"
exec $ODOO_CMD
RUNNER_EOF
run_odoo_script

printf "✓ Odoo restarted.\n"
