#!/bin/bash
# ============================================================================
# psql - PostgreSQL shell
# ============================================================================
# Usage: psql [-d <db>] [psql args] [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "psql - PostgreSQL shell"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       psql [-d|--database <name>] [psql options]"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -d, --database <db>  ${CPRIMARY}Database name (default: SELECTED_DB) ${RST}"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Opens a psql shell in the PostgreSQL container."
    echo "       If no database specified, uses current SELECTED_DB."
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       psql                     ${CPRIMARY}Connect to selected DB     ${RST}"
    echo "       psql --database mydb     ${CPRIMARY}Connect to 'mydb'          ${RST}"
    echo "       psql -c 'SELECT 1'       ${CPRIMARY}Run single command         ${RST}"
    echo ""
}

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
    DBNAME="${SELECTED_DB}"
fi

if [ -z "$DBNAME" ]; then
    echo "❌ No database specified and no SELECTED_DB found"
    echo "   Use: psql -d <database>"
    exit 1
fi

docker exec -it "$DB_CONTAINER" psql -d "$DBNAME" -U "$DB_USER" "${ARGS[@]}"
