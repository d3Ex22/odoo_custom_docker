#!/bin/bash
# ============================================================================
# rebuild - Rebuild Docker containers based on version changes
# ============================================================================
# Usage: rebuild [-h|--help] [-nc|--no-cache] [-a|--all]
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

show_help() {
    echo ""
    echo "rebuild - Rebuild Docker containers"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       rebuild [OPTIONS]"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -nc, --no-cache    Rebuild without Docker cache"
    echo "       -a, --all          Force rebuild db and odoo containers"
    echo "       -h, --help         Show this help"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Detects version changes in .env and rebuilds only the"
    echo "       necessary containers. Automatically applies --no-cache"
    echo "       when Odoo build version changes."
    echo ""
    printf "   ${C}CONFIGURATION${RST} (from .env)\n"
    echo "       ODOO_VERSION       Odoo version (e.g. 19.0)"
    echo "       ODOO_BUILD         Build date or 'latest'"
    echo "       PYTHON_VERSION     Python version (e.g. 3.12)"
    echo "       POSTGRES_VERSION   PostgreSQL version (e.g. 17)"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       rebuild              Auto-detect what needs rebuild"
    echo "       rebuild -nc          Force fresh build without cache"
    echo "       rebuild -a           Force rebuild odoo and db"
    echo "       rebuild -a -nc       Force rebuild all without cache"
    echo ""
}

NO_CACHE=""
FORCE_ALL=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -nc|--no-cache) NO_CACHE="--no-cache"; shift ;;
        -a|--all) FORCE_ALL=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        *) shift ;;
    esac
done

HOST_PROJECT_DIR=$(cat /home/odoo/docker_dev/data/.host_project_dir 2>/dev/null | tr -d '\n')
if [ -z "$HOST_PROJECT_DIR" ]; then
    echo "❌ .host_project_dir not found"
    echo "   Run 'docker compose up' from host first"
    exit 1
fi

DC="docker compose -f /home/odoo/docker_dev/docker-compose.yml -p $PROJECT"
COMPAT_FILE="/home/odoo/docker_dev/data/versions.conf"

WANTED_ODOO="${ODOO_VERSION:-19.0}"
WANTED_PY="${PYTHON_VERSION:-3.12}"
WANTED_PG="${POSTGRES_VERSION:-17}"

ODOO_PKG=$(docker exec "$ODOO_CONTAINER" dpkg -s odoo 2>/dev/null | grep -oP '(?<=Version: )\S+')
INSTALLED_ODOO=$(echo "$ODOO_PKG" | grep -oP '^\d+\.\d+')
INSTALLED_BUILD=$(echo "$ODOO_PKG" | grep -oP '\d{8}$')
INSTALLED_PY=$(docker exec "$ODOO_CONTAINER" python3 --version 2>/dev/null | grep -oP '\d+\.\d+')
INSTALLED_PG=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)

WANTED_BUILD="${ODOO_BUILD:-latest}"
NIGHTLY_BUILDS=$(curl -s --connect-timeout 5 "http://nightly.odoo.com/${WANTED_ODOO}/nightly/deb/" 2>/dev/null | grep -oP "odoo_${WANTED_ODOO}\.\d+_all\.deb" | grep -oP '\d{8}' | sort -u)
LATEST_BUILD=$(echo "$NIGHTLY_BUILDS" | sort -r | head -1)

if [ "$WANTED_BUILD" = "latest" ]; then
    WANTED_BUILD="$LATEST_BUILD"
elif [ -n "$NIGHTLY_BUILDS" ] && ! echo "$NIGHTLY_BUILDS" | grep -q "^${WANTED_BUILD}$"; then
    echo "❌ Build ${WANTED_BUILD} not found on nightly"
    echo ""
    echo "   Last 5 builds for Odoo ${WANTED_ODOO}:"
    echo "$NIGHTLY_BUILDS" | tail -5 | while read b; do echo "   - $b"; done
    echo "   - latest (${LATEST_BUILD})"
    echo ""
    echo "   Full list: http://nightly.odoo.com/${WANTED_ODOO}/nightly/deb/"
    exit 1
fi

check_compat() {
    local odoo="$1" py="$2" pg="$3"
    [ ! -f "$COMPAT_FILE" ] && return 0
    while IFS=: read -r o_ver py_vers pg_vers; do
        [[ "$o_ver" =~ ^#.*$ || -z "$o_ver" ]] && continue
        if [ "$odoo" = "$o_ver" ]; then
            local py_ok=false pg_ok=false
            IFS=',' read -ra PY_ARR <<< "$py_vers"
            for v in "${PY_ARR[@]}"; do [ "$py" = "$v" ] && py_ok=true; done
            IFS=',' read -ra PG_ARR <<< "$pg_vers"
            for v in "${PG_ARR[@]}"; do [ "$pg" = "$v" ] && pg_ok=true; done
            $py_ok && $pg_ok && return 0
            return 1
        fi
    done < "$COMPAT_FILE"
    return 1
}

if ! check_compat "$WANTED_ODOO" "$WANTED_PY" "$WANTED_PG"; then
    echo "❌ Incompatible versions"
    echo ""
    grep "^$WANTED_ODOO:" "$COMPAT_FILE" | while IFS=: read -r _ py pg; do
        echo "   Odoo $WANTED_ODOO requires:"
        echo "   - Python: $py"
        echo "   - PostgreSQL: $pg"
    done
    exit 1
fi

REBUILD_ODOO=false
REBUILD_DB=false

if $FORCE_ALL; then
    REBUILD_ODOO=true
    REBUILD_DB=true
else
    if [ -z "$INSTALLED_ODOO" ] || [ "$WANTED_ODOO" != "$INSTALLED_ODOO" ] || [ "$WANTED_PY" != "$INSTALLED_PY" ]; then
        REBUILD_ODOO=true
    fi
    if [ -n "$WANTED_BUILD" ] && [ -n "$INSTALLED_BUILD" ] && [ "$WANTED_BUILD" != "$INSTALLED_BUILD" ]; then
        REBUILD_ODOO=true
        NO_CACHE="--no-cache"
    fi
    if [ -z "$INSTALLED_PG" ] || [ "$WANTED_PG" != "$INSTALLED_PG" ]; then
        REBUILD_DB=true
    fi
fi

DC_BUILD="$DC build $NO_CACHE"
DC_UP="$DC --project-directory $HOST_PROJECT_DIR up -d --no-build --force-recreate"
DC_DOWN="$DC --project-directory $HOST_PROJECT_DIR down"

RESTART_ODOO=false
if $REBUILD_DB && [ -n "$INSTALLED_PG" ] && [ "$WANTED_PG" != "$INSTALLED_PG" ]; then
    echo "⚠️  PostgreSQL version change detected"
    echo ""
    echo "   Current: PostgreSQL ${INSTALLED_PG}"
    echo "   Wanted:  PostgreSQL ${WANTED_PG}"
    echo ""
    echo "   All existing databases will be deleted."
    echo ""
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Cancelled"
        exit 0
    fi
    echo "Stopping containers..."
    $DC_DOWN db odoo 2>/dev/null
    echo "Wiping PostgreSQL data..."
    docker run --rm --user root -v ${HOST_PROJECT_DIR}/data/volumes/db/pgdata:/data postgres:${INSTALLED_PG} sh -c "rm -rf /data/*"
    echo "Wiping Odoo data..."
    docker run --rm --user root -v ${HOST_PROJECT_DIR}/data/volumes/odoo:/data postgres:${INSTALLED_PG} sh -c "rm -rf /data/filestore/* /data/sessions/* /data/cache/*"
    RESTART_ODOO=true
    echo ""
fi

if ! $REBUILD_ODOO && ! $REBUILD_DB; then
    echo "✓ All containers are up to date"
    echo "   Odoo: ${INSTALLED_ODOO}.${INSTALLED_BUILD}"
    echo "   Python: ${INSTALLED_PY}"
    echo "   PostgreSQL: ${INSTALLED_PG}"
    echo ""
    echo "   Use 'rebuild -a' to force rebuild"
    exit 0
fi

echo "Rebuilding..."
echo "   Project: ${PROJECT}"
$REBUILD_ODOO && echo "   Odoo: ${INSTALLED_ODOO:-?}.${INSTALLED_BUILD:-?} → ${WANTED_ODOO}.${WANTED_BUILD:-latest}"
$REBUILD_ODOO && echo "   Python: ${INSTALLED_PY:-?} → ${WANTED_PY}"
$REBUILD_DB && echo "   PostgreSQL: ${INSTALLED_PG:-?} → ${WANTED_PG}"
[ -n "$NO_CACHE" ] && echo "   Cache: disabled"
echo ""

cd /home/odoo/docker_dev

CONTAINERS_TO_UP=""

if $REBUILD_ODOO; then
    echo "Building odoo..."
    $DC_BUILD odoo \
        --build-arg ODOO_VERSION=${WANTED_ODOO} \
        --build-arg ODOO_BUILD=${ODOO_BUILD:-latest} \
        --build-arg PYTHON_VERSION=${WANTED_PY}
    CONTAINERS_TO_UP="$CONTAINERS_TO_UP odoo ttyd_logs"
fi

if $REBUILD_DB; then
    echo "Building db..."
    $DC_BUILD db --build-arg POSTGRES_VERSION=${WANTED_PG}
    CONTAINERS_TO_UP="$CONTAINERS_TO_UP db"
fi

if $RESTART_ODOO && ! $REBUILD_ODOO; then
    CONTAINERS_TO_UP="$CONTAINERS_TO_UP odoo ttyd_logs"
fi

if [ -n "$CONTAINERS_TO_UP" ]; then
    echo "Restarting containers..."
    $DC_UP $CONTAINERS_TO_UP
fi

echo ""
echo "✓ Rebuild complete"
