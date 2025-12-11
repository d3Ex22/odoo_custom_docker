#!/bin/bash
# ============================================================================
# fix-reports - Fix report.url in database
# ============================================================================
# Usage: fix-reports [-f] [-h|--help]
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
    echo "fix-reports - Fix report.url in database"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       fix-reports [-f|--force]"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -f, --force  ${C}Force update if key exists              ${RST}"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Sets or updates 'report.url' in ir_config_parameter"
    echo "       to 'http://0.0.0.0:8069' for PDF report generation."
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       fix-reports           ${C}Insert if not exists          ${RST}"
    echo "       fix-reports --force   ${C}Force update existing value   ${RST}"
    echo ""
}

FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "❌ Unknown option: $1"
            echo "   Use --help for usage"
            exit 1
            ;;
    esac
done

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
DB_CONTAINER="${PROJECT}_db"
PG_USER="${POSTGRES_USER:-odoo}"
DB_PARAM_KEY="report.url"
DB_PARAM_VALUE="http://0.0.0.0:8069"

DBNAME="${SELECTED_DB:-}"

if [ -z "$DBNAME" ]; then
    echo "❌ No database selected"
    echo "   Use: db select <name>"
    exit 1
fi

echo "Database: $DBNAME"
echo "Checking '$DB_PARAM_KEY'..."

EXISTING_VALUE=$(docker exec "$DB_CONTAINER" psql -U "$PG_USER" -d "$DBNAME" -tAc "
    SELECT value FROM ir_config_parameter WHERE key = '$DB_PARAM_KEY';
" | xargs)

if [ -n "$EXISTING_VALUE" ]; then
    echo "   Current: '$EXISTING_VALUE'"
    echo "   Target:  '$DB_PARAM_VALUE'"

    if $FORCE; then
        docker exec "$DB_CONTAINER" psql -U "$PG_USER" -d "$DBNAME" -c "
            DELETE FROM ir_config_parameter WHERE key = '$DB_PARAM_KEY';
            INSERT INTO ir_config_parameter (key, value, create_date, write_date)
            VALUES ('$DB_PARAM_KEY', '$DB_PARAM_VALUE', NOW(), NOW());
        " >/dev/null 2>&1
        echo "✓ Key updated to '$DB_PARAM_VALUE'"
    else
        echo "   Use -f to force update"
    fi
else
    docker exec "$DB_CONTAINER" psql -U "$PG_USER" -d "$DBNAME" -c "
        INSERT INTO ir_config_parameter (key, value, create_date, write_date)
        VALUES ('$DB_PARAM_KEY', '$DB_PARAM_VALUE', NOW(), NOW());
    " >/dev/null 2>&1
    echo "✓ Key inserted with value '$DB_PARAM_VALUE'"
fi

