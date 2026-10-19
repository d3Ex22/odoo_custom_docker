#!/bin/bash
set -uo pipefail
# ============================================================================
# migrate - Upgrade a database to a newer Odoo version (upgrade.odoo.com)
# ============================================================================
# Usage: migrate [-h|--help] <database> <version>
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

VALID_VERSIONS=$(compat_odoo_versions | xargs)

show_help() {
    h_name "migrate" "Upgrade a database with Odoo's upgrade service"
    h_sec "USAGE"
    h_use "migrate <database> <version>"
    h_sec "ARGUMENTS"
    h_opt "database" "Source database (left untouched)"
    h_opt "version" "Target Odoo version: ${VALID_VERSIONS}"
    h_sec "REQUIREMENTS"
    h_text "ENTERPRISE_KEY in .env.secrets (or .env) — an Enterprise subscription code."
    h_sec "DESCRIPTION"
    h_text "Runs the official upgrade script in 'test' mode: the database is"
    h_text "dumped, upgraded by upgrade.odoo.com and restored as a new database"
    h_text "named by the service (<database>_<version>...). Takes several minutes:"
    h_text "runs in a side pane so you can keep working meanwhile."
    h_sec "EXAMPLES"
    h_ex "migrate main 19.0" ""
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in -h|--help) show_help; exit 0 ;; esac
[ $# -ne 2 ] && die "Usage: migrate <database> <version>" "See: migrate --help"

SRC_DB="$1"
TARGET_VERSION="$2"
echo "$VALID_VERSIONS" | tr ' ' '\n' | grep -qx "$TARGET_VERSION" \
    || die "Unsupported version: $TARGET_VERSION" "Supported: $VALID_VERSIONS"

require_db_container
db_exists "$SRC_DB" || die "Database '$SRC_DB' does not exist" "db list to see the databases"

CURRENT_VERSION=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$SRC_DB" -tAc \
    "SELECT latest_version FROM ir_module_module WHERE name = 'base' LIMIT 1;" 2>/dev/null)
[ -z "$CURRENT_VERSION" ] && die "Cannot read the Odoo version of '$SRC_DB'" "Is it an Odoo database?"
CURRENT_MAJOR="${CURRENT_VERSION%%.*}"
TARGET_MAJOR="${TARGET_VERSION%%.*}"
[ "$CURRENT_MAJOR" -ge "$TARGET_MAJOR" ] && die "Database is already on ${CURRENT_VERSION} (>= ${TARGET_VERSION})"

[ -z "${ENTERPRISE_KEY:-}" ] && die "ENTERPRISE_KEY is not set" "Add ENTERPRISE_KEY=<code> to .env.secrets (git-ignored)"
open_pane

ui_title "Migrate" "$SRC_DB  ${CURRENT_VERSION} → ${TARGET_VERSION}"

ui_kv "Database" "$SRC_DB"
ui_kv "From → to" "${CURRENT_VERSION} → ${TARGET_VERSION}"
ui_kv "Contract" "${ENTERPRISE_KEY:0:8}..."
echo
confirm "Start the upgrade? (several minutes)" || { ui_note "Cancelled"; exit 0; }
echo

# The upgrade script dumps with the local pg_dump: its major must match the server.
PG_SERVER=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)
PG_CLIENT=$(pg_dump --version 2>/dev/null | grep -oP '\d+' | head -1)
if [ -n "$PG_SERVER" ] && [ "$PG_CLIENT" != "$PG_SERVER" ]; then
    ui_step "Installing PostgreSQL client ${PG_SERVER} (server) in place of ${PG_CLIENT}..."
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get remove -y -qq "postgresql-client-${PG_CLIENT}" >/dev/null 2>&1
    if sudo apt-get install -y -qq "postgresql-client-${PG_SERVER}" >/dev/null 2>&1; then
        hash -r
        export PATH="/usr/lib/postgresql/${PG_SERVER}/bin:$PATH"
        ui_ok "PostgreSQL client ${PG_SERVER} installed"
    else
        ui_warn "Could not install PostgreSQL client ${PG_SERVER}; using ${PG_CLIENT}"
    fi
fi

UPGRADE_PY=$(mktemp /tmp/upgrade.XXXXXX.py); trap 'rm -f "$UPGRADE_PY"' EXIT
curl -fsS -o "$UPGRADE_PY" https://upgrade.odoo.com/upgrade || die "Cannot download the upgrade script" "https://upgrade.odoo.com"
cd /tmp && PGHOST="$DB_CONTAINER" PGUSER="$DB_USER" PGPASSWORD="$DB_PASSWORD" \
    python3 "$UPGRADE_PY" test -d "$SRC_DB" -t "$TARGET_VERSION" --contract "$ENTERPRISE_KEY"
RC=$?
echo
if [ $RC -eq 0 ]; then
    ui_done "Upgrade finished — the upgraded copy is listed by: db list"
else
    die "Upgrade script exited with code $RC"
fi
