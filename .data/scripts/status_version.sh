#!/bin/bash
# Return version display with highlight on changed/incompatible versions

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
NIGHTLY_CACHE="/tmp/.odoo_nightly_cache"
WANTED_ODOO="${ODOO_VERSION}"
WANTED_PY="${PYTHON_VERSION}"
WANTED_PG="${POSTGRES_VERSION}"
WANTED_BUILD="${ODOO_BUILD}"

VERSIONS_CACHE="/var/shared/.odoo_versions_cache"
VERSIONS_TTL=10

INSTALLED_ODOO="" INSTALLED_BUILD="" INSTALLED_PY="" INSTALLED_PG=""
if [ -f "$VERSIONS_CACHE" ]; then
    CACHE_AGE=$(($(date +%s) - $(stat -c %Y "$VERSIONS_CACHE" 2>/dev/null || echo 0)))
    if [ $CACHE_AGE -lt $VERSIONS_TTL ]; then
        IFS='|' read -r INSTALLED_ODOO INSTALLED_BUILD INSTALLED_PY INSTALLED_PG < "$VERSIONS_CACHE"
    fi
fi

if [ -z "$INSTALLED_ODOO" ] || [ -z "$INSTALLED_PG" ]; then
    BUILD_INFO=$(docker exec "$ODOO_CONTAINER" cat /opt/odoo/.build_version 2>/dev/null)
    if [ -n "$BUILD_INFO" ]; then
        IFS='|' read -r INSTALLED_ODOO INSTALLED_BUILD <<< "$BUILD_INFO"
    else
        ODOO_PKG=$(docker exec "$ODOO_CONTAINER" dpkg -s odoo 2>/dev/null | grep -oP '(?<=Version: )\S+')
        INSTALLED_ODOO=$(echo "$ODOO_PKG" | grep -oP '^\d+\.\d+')
        INSTALLED_BUILD=$(echo "$ODOO_PKG" | grep -oP '\d{8}$')
    fi
    INSTALLED_PY=$(docker exec "$ODOO_CONTAINER" python3 --version 2>/dev/null | grep -oP '\d+\.\d+')
    INSTALLED_PG=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)
    echo "${INSTALLED_ODOO}|${INSTALLED_BUILD}|${INSTALLED_PY}|${INSTALLED_PG}" > "$VERSIONS_CACHE"
fi

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

ODOO_STYLE="#[fg=${TMUX_ODOO_COLOR},bold]"
BUILD_STYLE="#[fg=${TMUX_ODOO_COLOR},bold]"
PY_STYLE="#[fg=${TMUX_PY_COLOR},bold]"
PG_STYLE="#[fg=${TMUX_PG_COLOR},bold]"
STATUS=""
BLINK=$(($(date +%s) % 2))
NEED_REBUILD=false
BUILD_UPDATE=false

if ! check_compat "$WANTED_ODOO" "$WANTED_PY" "$WANTED_PG" "$COMPAT_FILE"; then
    ODOO_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    BUILD_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    PY_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    PG_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    STATUS="#[default]#[fg=${TMUX_ALERT_BG},bg=${TMUX_STATUS_BG},bold] REBUILD BLOCKED"
else
    if [ -n "$INSTALLED_ODOO" ] && [ "$WANTED_ODOO" != "$INSTALLED_ODOO" ]; then
        NEED_REBUILD=true
        [ $BLINK -eq 0 ] && ODOO_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
        [ $BLINK -eq 0 ] && BUILD_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    fi
    if [ -n "$INSTALLED_BUILD" ] && [ -n "$RESOLVED_BUILD" ] && [ "$RESOLVED_BUILD" != "$INSTALLED_BUILD" ]; then
        BUILD_UPDATE=true
        [ $BLINK -eq 0 ] && BUILD_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    fi
    if [ -n "$INSTALLED_PY" ] && [ "$WANTED_PY" != "$INSTALLED_PY" ]; then
        NEED_REBUILD=true
        [ $BLINK -eq 0 ] && PY_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    fi
    if [ -n "$INSTALLED_PG" ] && [ "$WANTED_PG" != "$INSTALLED_PG" ]; then
        NEED_REBUILD=true
        [ $BLINK -eq 0 ] && PG_STYLE="#[fg=${TMUX_ALERT_FG},bg=${TMUX_ALERT_BG},bold]"
    fi

    if $NEED_REBUILD && [ $BLINK -eq 0 ]; then
        STATUS="#[default]#[fg=${TMUX_ALERT_BG},bg=${TMUX_STATUS_BG},bold] REBUILD"
    elif $BUILD_UPDATE && [ $BLINK -eq 0 ]; then
        STATUS="#[default]#[fg=${TMUX_ALERT_BG},bg=${TMUX_STATUS_BG},bold] REBUILD TO UPDATE"
    fi
fi

DISPLAY_BUILD="${RESOLVED_BUILD:-latest}"
DISPLAY_PY="${WANTED_PY}"
DISPLAY_PG="${WANTED_PG}"

OUTPUT="#[default]${ODOO_STYLE} Odoo ${WANTED_ODOO}.#[default]${BUILD_STYLE}${DISPLAY_BUILD}#[default] ${PY_STYLE} Py ${DISPLAY_PY} #[default]${PG_STYLE} PG ${DISPLAY_PG} #[default]${STATUS}"
echo "$OUTPUT" > /var/shared/.tmux_status_left 2>/dev/null
echo "$OUTPUT"
