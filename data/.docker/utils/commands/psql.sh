#!/bin/bash
# ============================================================================
# psql - PostgreSQL shell
# ============================================================================
# Usage: psql [-d <db>] [psql args] [-h|--help]
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
    echo "psql - PostgreSQL shell"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       psql [-d|--database <name>] [psql options]"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -d, --database <db>  ${C}Database name (default: SELECTED_DB) ${RST}"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Opens a psql shell in the PostgreSQL container."
    echo "       If no database specified, uses current SELECTED_DB."
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       psql                     ${C}Connect to selected DB     ${RST}"
    echo "       psql --database mydb     ${C}Connect to 'mydb'          ${RST}"
    echo "       psql -c 'SELECT 1'       ${C}Run single command         ${RST}"
    echo ""
}

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
DB_CONTAINER="${PROJECT}_db"
PG_USER="${POSTGRES_USER:-odoo}"
DBNAME=""
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--database)
            DBNAME="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

if [ -z "$DBNAME" ]; then
    DBNAME="${SELECTED_DB:-}"
fi

if [ -z "$DBNAME" ]; then
    echo "❌ No database specified and no SELECTED_DB found"
    echo "   Use: psql -d <database>"
    exit 1
fi

docker exec -it "$DB_CONTAINER" psql -d "$DBNAME" -U "$PG_USER" "${ARGS[@]}"

