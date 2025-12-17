#!/bin/bash
# ============================================================================
# migrate - Migrate database to a new Odoo version
# ============================================================================
# Usage: migrate [-h|--help] <database> <version>
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh
DB_PASSWORD="${POSTGRES_PASSWORD:-odoo}"
COMPAT_FILE="/home/odoo/docker_dev/data/versions.conf"

get_valid_versions() {
    [ ! -f "$COMPAT_FILE" ] && echo "19.0 18.0 17.0 16.0" && return
    grep -v '^#' "$COMPAT_FILE" | grep -v '^$' | cut -d: -f1 | sort -rV | tr '\n' ' '
}

VALID_VERSIONS=($(get_valid_versions))

show_help() {
    echo ""
    echo "migrate - Migrate database to a new Odoo version"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       migrate <database> <version>"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       database    Source database name"
    echo "       version     Target Odoo version (${VALID_VERSIONS[*]})"
    echo ""
    printf "   ${C}REQUIREMENTS${RST}\n"
    echo "       ENTERPRISE_KEY in .env (required)"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Uses Odoo's official upgrade service to migrate the database."
    echo "       The original database is preserved, migration creates a copy."
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       migrate production 19.0"
    echo "       migrate mydb_18 19.0"
    echo ""
}

validate_version() {
    for v in "${VALID_VERSIONS[@]}"; do
        [ "$1" = "$v" ] && return 0
    done
    echo "❌ Invalid version: $1"
    echo "   Supported: ${VALID_VERSIONS[*]}"
    exit 1
}

get_db_version() {
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$1" -tAc \
        "SELECT latest_version FROM ir_module_module WHERE name = 'base' LIMIT 1;" 2>/dev/null
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ $# -lt 2 ]; then
    echo "❌ Usage: migrate <database> <version>"
    echo "   Use 'migrate --help' for details"
    exit 1
fi

SRC_DB="$1"
TARGET_VERSION="$2"

validate_version "$TARGET_VERSION"

DB_EXISTS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = '$SRC_DB';")
if [ "$DB_EXISTS" != "1" ]; then
    echo "❌ Database '$SRC_DB' does not exist"
    exit 1
fi

echo "Detecting database Odoo version..."
CURRENT_VERSION=$(get_db_version "$SRC_DB")
if [ -z "$CURRENT_VERSION" ]; then
    echo "❌ Unable to determine current version"
    exit 1
fi
echo "   Current: $CURRENT_VERSION"

CURRENT_MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
TARGET_MAJOR=$(echo "$TARGET_VERSION" | cut -d. -f1)
if [ "$CURRENT_MAJOR" -ge "$TARGET_MAJOR" ]; then
    echo "❌ Current version ($CURRENT_VERSION) >= target ($TARGET_VERSION)"
    exit 1
fi

if [ -z "$ENTERPRISE_KEY" ]; then
    echo "❌ ENTERPRISE_KEY not found in .env"
    echo "   Add ENTERPRISE_KEY=your_code to .env"
    exit 1
fi

# Check and install matching PostgreSQL client version
PG_SERVER_VERSION=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)
PG_CLIENT_VERSION=$(pg_dump --version 2>/dev/null | grep -oP '\d+' | head -1)

echo "Container's PostgreSQL versions:"
echo "   Database: $PG_SERVER_VERSION"
echo "   Utils: $PG_CLIENT_VERSION"

if [ -n "$PG_SERVER_VERSION" ] && [ "$PG_CLIENT_VERSION" != "$PG_SERVER_VERSION" ]; then
    echo "Switching PostgreSQL client $PG_CLIENT_VERSION → $PG_SERVER_VERSION..."
    sudo apt-get update -qq 2>/dev/null
    sudo apt-get remove -y -qq postgresql-client-$PG_CLIENT_VERSION >/dev/null 2>&1
    sudo apt-get install -y -qq postgresql-client-$PG_SERVER_VERSION >/dev/null 2>&1
    if [ $? -eq 0 ]; then
        hash -r  # Refresh bash PATH cache
        export PATH="/usr/lib/postgresql/$PG_SERVER_VERSION/bin:$PATH"
        echo "✓ PostgreSQL client $PG_SERVER_VERSION installed"
    else
        echo "⚠️  Could not install PostgreSQL client $PG_SERVER_VERSION, using default"
    fi
fi

echo ""
echo "Migration:"
echo "   Database: $SRC_DB"
echo "   From: $CURRENT_VERSION → $TARGET_VERSION"
echo "   Enterprise key: ${ENTERPRISE_KEY:0:8}..."
echo ""
echo "Starting upgrade..."
echo ""

cd /tmp && PGHOST=db PGUSER=$DB_USER PGPASSWORD=$DB_PASSWORD python3 <(curl -s https://upgrade.odoo.com/upgrade) test -d "$SRC_DB" -t "$TARGET_VERSION" --contract "$ENTERPRISE_KEY"
