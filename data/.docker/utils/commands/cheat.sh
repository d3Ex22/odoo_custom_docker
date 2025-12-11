#!/bin/bash
# ============================================================================
# cheat - Bypass Odoo Enterprise expiration
# ============================================================================
# Usage: cheat [-h|--help]
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
    echo "cheat - Bypass Odoo Enterprise expiration"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       cheat"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Extends database expiration date to 2055 and disables"
    echo "       the Publisher Update Notification cron on current DB."
    echo ""
    printf "   ${C}ACTIONS${RST}\n"
    echo "       - Sets database.expiration_date to 2055-05-26"
    echo "       - Disables 'Publisher: Update Notification' cron"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
DB_CONTAINER="${PROJECT}_db"
PG_USER="${POSTGRES_USER:-odoo}"

DBNAME="${SELECTED_DB:-}"

if [ -z "$DBNAME" ]; then
    echo "❌ No database selected"
    echo "   Use: db select <name>"
    exit 1
fi

echo "Applying cheat to: $DBNAME"

docker exec "$DB_CONTAINER" psql -U "$PG_USER" -d "$DBNAME" -c "
WITH update_ir_config AS (
    UPDATE public.ir_config_parameter
    SET value = '2055-05-26 14:31:26'
    WHERE key = 'database.expiration_date'
),
update_ir_cron AS (
    UPDATE public.ir_cron
    SET active = false
    WHERE cron_name = 'Publisher: Update Notification'
)
SELECT 1;
" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "✓ Cheat applied to '$DBNAME'"
else
    echo "❌ Failed to apply cheat"
    exit 1
fi

