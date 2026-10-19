#!/bin/bash
# ============================================================================
# odoo_runner.sh [-d DB|-] [-u MODULES] — the Odoo process of the logs pane.
# Builds the command from .env (DEBUGPY, SELECTED_DB, ODOO_ARGS), prints the
# start header, checks the mounted sources (odoo_guard.sh), then execs Odoo.
# Started by the odoo entrypoint, respawned in the pane by start / reboot /
# update (utils, lib/odoo.sh launch_odoo). -d overrides SELECTED_DB ('-' =
# multi-db), -u adds the modules to update.
# ============================================================================
set -a; source /home/odoo/.env 2>/dev/null; set +a
DB="${SELECTED_DB:-}"; MODULES=""
while [ $# -gt 0 ]; do
    case "$1" in
        -d) DB="${2:-}"; [ "$DB" = "-" ] && DB=""; shift 2 ;;
        -u) MODULES="${2:-}"; shift 2 ;;
        *) shift ;;
    esac
done

ADDON_PATHS=$(/usr/local/bin/generate_addons_path.sh 2>/dev/null)
CMD="odoo -c /etc/odoo/odoo.conf"
# DEBUGPY=true: same server under debugpy (port 5678 in the container, see 'debug')
[ "${DEBUGPY:-false}" = "true" ] && CMD="python -m debugpy --listen 0.0.0.0:5678 $(command -v odoo) -c /etc/odoo/odoo.conf"
[ -n "$DB" ]               && CMD="$CMD -d $DB"
[ -n "${ODOO_ARGS:-}" ]    && CMD="$CMD $ODOO_ARGS"
[ -n "$MODULES" ]          && CMD="$CMD -u $MODULES"
echo "$CMD" > /tmp/.odoo_cmd   # read by logs.sh -w (database served or not)

/usr/local/bin/odoo_header.sh "$CMD" "$ADDON_PATHS"
/usr/local/bin/odoo_guard.sh || exit 1
exec $CMD
