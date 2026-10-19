#!/bin/bash
# ============================================================================
# psql - PostgreSQL shell / one-shot queries on a database
# ============================================================================
# Usage: psql [-d <db>] [psql arguments] | psql [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "psql" "PostgreSQL shell on a database"
    h_sec "USAGE"
    h_use "psql [-d <database>] [psql options]"
    h_sec "OPTIONS"
    h_opt "-d, --database <db>" "Database (default: SELECTED_DB, asked when empty)"
    h_text "Every other argument is passed to psql (-c, -f, -tA, ...)."
    h_sec "EXAMPLES"
    h_ex "psql" "Interactive shell on SELECTED_DB (side pane)"
    h_ex "psql -d mydb" "Interactive shell on mydb"
    h_ex "psql -tAc 'SELECT count(*) FROM res_users'" "One-shot query, plain output"
    h_ex "psql -f script.sql" "Run a file (path inside the utils container)"
    h_end
}

DBNAME=""
PSQL_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -d|--database) DBNAME="${2:-}"; [ -z "$DBNAME" ] && die "-d needs a database name"; shift 2 ;;
        *) PSQL_ARGS+=("$1"); shift ;;
    esac
done

require_db_container
[ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"
[ -z "$DBNAME" ] && { pick_db "Which database?" || exit 1; DBNAME="$PICKED"; }
db_exists "$DBNAME" || die "Database '$DBNAME' does not exist" "db list to see the databases"

# Interactive shell (no psql argument) from the utils terminal: side pane,
# closed when psql exits (\q). One-shot queries stay inline.
if [ ${#PSQL_ARGS[@]} -eq 0 ] && in_utils_terminal; then
    run_in_pane "psql" "50%" close docker exec -it "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" || exit 1
    ui_ok "psql on '$DBNAME' opened in a side pane"
    ui_note "\\q closes it"
    exit 0
fi
TTY=""; [ -t 0 ] && TTY="-t"
exec docker exec -i $TTY "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" "${PSQL_ARGS[@]}"
