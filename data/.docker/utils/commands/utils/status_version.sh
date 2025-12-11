#!/bin/bash
# Return version display with highlight on changed/incompatible versions

source /home/odoo/docker_dev/.env 2>/dev/null

COMPAT_FILE="/home/odoo/docker_dev/data/versions.conf"
NIGHTLY_CACHE="/tmp/.odoo_nightly_cache"
WANTED_ODOO="${ODOO_VERSION:-19.0}"
WANTED_PY="${PYTHON_VERSION:-3.12}"
WANTED_PG="${POSTGRES_VERSION:-17}"
WANTED_BUILD="${ODOO_BUILD:-latest}"
PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
ODOO_CONTAINER="${PROJECT}_odoo"
DB_CONTAINER="${PROJECT}_db"

ODOO_PKG=$(docker exec "$ODOO_CONTAINER" dpkg -s odoo 2>/dev/null | grep -oP '(?<=Version: )\S+')
INSTALLED_ODOO=$(echo "$ODOO_PKG" | grep -oP '^\d+\.\d+')
INSTALLED_BUILD=$(echo "$ODOO_PKG" | grep -oP '\d{8}$')
INSTALLED_PY=$(docker exec "$ODOO_CONTAINER" python3 --version 2>/dev/null | grep -oP '\d+\.\d+')
INSTALLED_PG=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)

LATEST_BUILD=""
if [ -f "$NIGHTLY_CACHE" ]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$NIGHTLY_CACHE" 2>/dev/null || echo 0)))
    if [ $CACHE_AGE -lt 60 ]; then
        LATEST_BUILD=$(cat "$NIGHTLY_CACHE" 2>/dev/null)
    fi
fi
if [ -z "$LATEST_BUILD" ]; then
    LATEST_BUILD=$(curl -s --connect-timeout 2 "http://nightly.odoo.com/${INSTALLED_ODOO:-$WANTED_ODOO}/nightly/deb/" 2>/dev/null | grep -oP "odoo_${INSTALLED_ODOO:-$WANTED_ODOO}\.\d+_all\.deb" | grep -oP '\d{8}' | sort -r | head -1)
    [ -n "$LATEST_BUILD" ] && echo "$LATEST_BUILD" > "$NIGHTLY_CACHE"
fi

RESOLVED_BUILD="$WANTED_BUILD"
[ "$WANTED_BUILD" = "latest" ] && RESOLVED_BUILD="$LATEST_BUILD"

check_compat() {
    local odoo="$1" py="$2" pg="$3"
    [ ! -f "$COMPAT_FILE" ] && return 0
    while IFS=':' read -r o_ver py_vers pg_vers; do
        o_ver=$(echo "$o_ver" | tr -d ' ')
        [[ "$o_ver" =~ ^#.*$ || -z "$o_ver" ]] && continue
        if [ "$odoo" = "$o_ver" ]; then
            local py_ok=false pg_ok=false
            py_vers=$(echo "$py_vers" | tr -d ' ')
            pg_vers=$(echo "$pg_vers" | tr -d ' ')
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

ODOO_STYLE="#[fg=#875A7B,bold]"
BUILD_STYLE="#[fg=#875A7B,bold]"
PY_STYLE="#[fg=#FFD43B,bold]"
PG_STYLE="#[fg=#336791,bold]"
STATUS=""
BLINK=$(($(date +%s) % 2))
NEED_REBUILD=false
BUILD_UPDATE=false

if ! check_compat "$WANTED_ODOO" "$WANTED_PY" "$WANTED_PG"; then
    ODOO_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    BUILD_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    PY_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    PG_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    STATUS="#[default]#[fg=#ff0000,bg=#000000,bold] REBUILD BLOCKED"
else
    if [ -n "$INSTALLED_ODOO" ] && [ "$WANTED_ODOO" != "$INSTALLED_ODOO" ]; then
        NEED_REBUILD=true
        [ $BLINK -eq 0 ] && ODOO_STYLE="#[fg=#000000,bg=#ff0000,bold]"
        [ $BLINK -eq 0 ] && BUILD_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    fi
    if [ -n "$INSTALLED_BUILD" ] && [ -n "$RESOLVED_BUILD" ] && [ "$RESOLVED_BUILD" != "$INSTALLED_BUILD" ]; then
        BUILD_UPDATE=true
        [ $BLINK -eq 0 ] && BUILD_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    fi
    if [ -n "$INSTALLED_PY" ] && [ "$WANTED_PY" != "$INSTALLED_PY" ]; then
        NEED_REBUILD=true
        [ $BLINK -eq 0 ] && PY_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    fi
    if [ -n "$INSTALLED_PG" ] && [ "$WANTED_PG" != "$INSTALLED_PG" ]; then
        NEED_REBUILD=true
        [ $BLINK -eq 0 ] && PG_STYLE="#[fg=#000000,bg=#ff0000,bold]"
    fi
    
    if $NEED_REBUILD && [ $BLINK -eq 0 ]; then
        STATUS="#[default]#[fg=#ff0000,bg=#000000,bold] REBUILD"
    elif $BUILD_UPDATE && [ $BLINK -eq 0 ]; then
        STATUS="#[default]#[fg=#ff0000,bg=#000000,bold] REBUILD TO UPDATE"
    fi
fi

DISPLAY_BUILD="${RESOLVED_BUILD:-latest}"
DISPLAY_PY="${WANTED_PY}"
DISPLAY_PG="${WANTED_PG}"

echo "#[default]${ODOO_STYLE} Odoo ${WANTED_ODOO}.#[default]${BUILD_STYLE}${DISPLAY_BUILD}#[default] ${PY_STYLE} Py ${DISPLAY_PY} #[default]${PG_STYLE} PG ${DISPLAY_PG} #[default]${STATUS}"
