#!/bin/bash
# ============================================================================
# update - Update Odoo modules and restart
# ============================================================================
# Usage: update [-h|--help] [-k|--keep] [-w|--wait] [-d DB] [MODULE[,MODULE2,...]]
# Alias: u
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "update (u)" "Restart Odoo with -u <modules>"
    h_sec "USAGE"
    h_use "u [-k] [-w] [-d DB] MODULE[,MODULE2,...]"
    h_use "u                                  reuse ODOO_UPDATE from .env"
    h_sec "OPTIONS"
    h_opt "-k, --keep" "Save the list as ODOO_UPDATE (next bare 'u' reuses it)"
    h_opt "-w, --wait" "Wait until Odoo is ready and report errors"
    h_opt "-d, --database DB" "Database(s) to update: name, comma list, or 'all' (every Odoo DB)"
    h_sec "ARGUMENTS"
    h_opt "MODULE" "Comma-separated names; patterns allowed: sale_*, my_[a-m]*"
    h_opt "all" "Every installed module"
    h_sec "DATABASE"
    h_text "-u needs a database: SELECTED_DB by default. Without it (multi-db"
    h_text "mode) and without -d, the Odoo databases are listed to pick one, or"
    h_text "all. Odoo then serves only the updated database(s) until the next"
    h_text "start / reboot, which goes back to SELECTED_DB (or multi-db)."
    h_sec "EXAMPLES"
    h_ex "u sale" ""
    h_ex "u sale,purchase,stock" ""
    h_ex "u my_*" "Every module matching the pattern"
    h_ex "u -k my_module" "then just 'u' for the next updates"
    h_ex "u -w my_module" "Update, wait, show errors if any"
    h_ex "u -d all my_module" "Update it in every Odoo database"
    h_sec "CONFIGURATION (.env)"
    h_opt "ODOO_UPDATE" "Default module list (u -k <modules>, or .env)"
    h_opt "SELECTED_DB" "Database to use (empty = multi-db mode, see DATABASE)"
    h_opt "ODOO_ARGS" "Extra Odoo arguments"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"

KEEP=false
WAIT=false
MODULES=""
DB=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -k|--keep) KEEP=true; shift ;;
        -w|--wait) WAIT=true; shift ;;
        -d|--database) [ -n "${2:-}" ] || die "-d needs a database name" "See: u --help"; DB="$2"; shift 2 ;;
        -*) die "Unknown option: $1" "See: u --help" ;;
        *) MODULES="${MODULES:+$MODULES,}$1"; shift ;;
    esac
done

if [ -z "$MODULES" ]; then
    $KEEP && die "-k needs a module list" "Usage: u -k MODULE[,MODULE2,...]"
    MODULES="${ODOO_UPDATE:-}"
    [ -z "$MODULES" ] && die "No module given and ODOO_UPDATE is empty" \
        "Usage: u MODULE[,MODULE2,...]" "Set a default with: u -k <modules>"
    ui_note "Using ODOO_UPDATE=${MODULES}"
fi

require_odoo_container

# -u only applies to the databases given with -d: resolve one now.
if [ "$DB" = "all" ]; then
    require_db_container
    DB=$(odoo_db_list_names | paste -sd, -)
    [ -z "$DB" ] && die "No Odoo database found" "db list to see the databases"
elif [ -z "$DB" ] && [ -z "${SELECTED_DB:-}" ]; then
    require_db_container
    pick_db "Update which database?" all || exit 1
    DB="$PICKED"
fi
if [ -n "$DB" ] && [ "$DB" != "${SELECTED_DB:-}" ]; then
    require_db_container
    for d in ${DB//,/ }; do db_exists "$d" || die "Database '$d' does not exist" "db list to see the databases"; done
    ui_note "Odoo will serve only ${DB//,/, } until the next start / reboot"
fi

if $KEEP; then
    set_env_value "ODOO_UPDATE" "$MODULES"
    ui_ok "ODOO_UPDATE=${MODULES}"
fi

refresh_modules_cache "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)"

EXPANDED=$(expand_modules "$MODULES")
[ -z "$EXPANDED" ] && die "No matching module" "Patterns are matched against the module cache (addons + odoo + enterprise)"
UNKNOWN=$(unknown_modules "$EXPANDED")
[ -n "$UNKNOWN" ] && ui_warn "Unknown module(s): $(echo "$UNKNOWN" | paste -sd, -)"

ui_step "Restarting Odoo with -u ${EXPANDED}${DB:+ on ${DB//,/, }}..."
SELECTED_DB="${DB:-${SELECTED_DB:-}}" launch_odoo "$EXPANDED" || die "Failed to restart Odoo"
ui_ok "Odoo restarted"

$WAIT && exec bash "${_PROJECT_ROOT}/.data/scripts/internal/logs.sh" --wait
exit 0
