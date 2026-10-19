#!/bin/bash
# Dev defaults applied at start: SELECTED_DB, or every database in multi-db mode
# (no SELECTED_DB: any database can be opened from the selector).
set -uo pipefail

export PGPASSWORD="${PASSWORD:-odoo}" PGHOST="${HOST:-db}" PGPORT="${PORT:-5432}" PGUSER="${USER:-odoo}"
pg() { psql -d "$1" -tAc "$2" 2>/dev/null | tr -d '[:space:]'; }   # pg DB SQL

if [ -n "${SELECTED_DB:-}" ]; then
    DBS="$SELECTED_DB"
else
    DBS=$(psql -d postgres -tAc \
        "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname" 2>/dev/null)
fi

for DB in $DBS; do
    [[ "$DB" =~ ^[a-zA-Z0-9_]+$ ]] || continue
    [ "$(pg postgres "SELECT 1 FROM pg_database WHERE datname = '$DB'")" = "1" ] || continue
    [ "$(pg "$DB" "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ir_config_parameter' LIMIT 1")" = "1" ] || continue
    echo "Applying dev DB defaults to $DB (report.url, expiration / cron)..."
    psql -d "$DB" -q >/dev/null 2>&1 <<'EOSQL' || true
DELETE FROM ir_config_parameter WHERE key = 'report.url';
INSERT INTO ir_config_parameter (key, value, create_date, write_date)
VALUES ('report.url', 'http://0.0.0.0:8069', NOW(), NOW());
UPDATE ir_config_parameter SET value = '2055-05-26 14:31:26' WHERE key = 'database.expiration_date';
UPDATE ir_cron SET active = false WHERE cron_name = 'Publisher: Update Notification';
EOSQL
    # Mail catcher: every outgoing server (active or not, the neutralization
    # dummy included) points to the Mailpit container
    [ -x /usr/local/bin/mail_catcher.sh ] && /usr/local/bin/mail_catcher.sh db "$DB"
done

exit 0
