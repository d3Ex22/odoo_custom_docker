#!/bin/bash
# ============================================================================
# shell - Odoo Python shell in a side pane
# ============================================================================
# Usage: shell [-h|--help] [database]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "shell" "Open an Odoo Python shell in a side pane"
    h_sec "USAGE"
    h_use "shell [database]"
    h_sec "ARGUMENTS"
    h_opt "database" "Database (default: SELECTED_DB, asked when empty)"
    h_sec "DESCRIPTION"
    h_text "Opens 'odoo shell' (IPython: completion, history, ?help) in a new pane"
    h_text "on the right (50%). 'env', 'self' and the usual Odoo globals are"
    h_text "available. Exit with exit() / Ctrl+D."
    h_text "Non-interactive use (scripts, AI): docker exec -i <odoo> odoo shell -d DB < code.py"
    h_sec "EXAMPLES"
    h_ex "shell" "Shell on SELECTED_DB"
    h_ex "shell mydb" "Shell on a specific DB"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in -h|--help) show_help; exit 0 ;; esac
[ $# -gt 1 ] && die "Usage: shell [database]"

require_odoo_container
require_db_container
DBNAME="${1:-${SELECTED_DB:-}}"
[ -z "$DBNAME" ] && { pick_db "Which database?" || exit 1; DBNAME="$PICKED"; }
db_exists "$DBNAME" || die "Database '$DBNAME' does not exist" "db list to see the databases"

ui_step "Opening Odoo shell on '$DBNAME'..."
# Refresh addons_path in odoo.conf so modules added since the last start are known.
docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh >/dev/null 2>&1
# From the utils terminal: side pane closed when the shell exits. Elsewhere
# (docker exec -it): inline.
if in_utils_terminal; then
    run_in_pane "odoo-shell" "50%" close \
        docker exec -it "$ODOO_CONTAINER" odoo shell -c /etc/odoo/odoo.conf -d "$DBNAME" --no-http || exit 1
    ui_ok "Shell opened in a side pane"
    ui_note "exit() or Ctrl+D closes it"
    exit 0
fi
TTY=""; [ -t 0 ] && TTY="-t"
exec docker exec -i $TTY "$ODOO_CONTAINER" odoo shell -c /etc/odoo/odoo.conf -d "$DBNAME" --no-http
