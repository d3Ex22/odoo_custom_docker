#!/bin/bash
set -uo pipefail

DB="${SELECTED_DB:-}"
[ -z "$DB" ] && exit 0
[[ "$DB" =~ ^[a-zA-Z0-9_]+$ ]] || exit 0

export PGPASSWORD="${DB_PASSWORD:-odoo}"

EXISTS=$(psql -h db -p 5432 -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DB'" 2>/dev/null | tr -d '[:space:]')
[ "$EXISTS" = "1" ] || exit 0

HAS_ICP=$(psql -h db -p 5432 -U odoo -d "$DB" -tAc \
    "SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='ir_config_parameter' LIMIT 1" 2>/dev/null | tr -d '[:space:]')
[ "$HAS_ICP" = "1" ] || exit 0

echo "Applying dev DB defaults (report.url, expiration / cron)..."
psql -h db -p 5432 -U odoo -d "$DB" -q >/dev/null 2>&1 <<'EOSQL' || true
DELETE FROM ir_config_parameter WHERE key = 'report.url';
INSERT INTO ir_config_parameter (key, value, create_date, write_date)
VALUES ('report.url', 'http://0.0.0.0:8069', NOW(), NOW());
UPDATE ir_config_parameter SET value = '2055-05-26 14:31:26' WHERE key = 'database.expiration_date';
UPDATE ir_cron SET active = false WHERE cron_name = 'Publisher: Update Notification';
EOSQL

exit 0
