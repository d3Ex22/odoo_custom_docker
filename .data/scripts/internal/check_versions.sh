#!/bin/bash
# ============================================================================
# check_versions - Installed vs wanted (.env) vs latest nightly versions
# Internal: check_versions MCP tool / docker exec. Not a utils command.
# ============================================================================
# Usage: check_versions
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh


parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    "") ;;
    *) die "Unknown option: $1" ;;
esac

IFS='|' read -r ODOO_V ODOO_B <<< "$(installed_odoo_build)"
PY_V=$(docker exec "$ODOO_CONTAINER" python3 --version 2>/dev/null | grep -oP '\d+\.\d+')
PG_V=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)
LATEST=$(nightly_latest_build "${ODOO_VERSION}")

ui_title "Versions" "installed → wanted (.env)"
NEED_REBUILD=false
REPO_MISMATCH=false

row() {   # row LABEL INSTALLED WANTED
    local label="$1" inst="$2" want="$3"
    if [ -z "$inst" ]; then
        printf "  ${CMUTED}%-12s${RST} %-18s ${CMUTED}(not running)${RST}\n" "$label" "-"
    elif [ "$inst" = "$want" ]; then
        printf "  ${CMUTED}%-12s${RST} %-18s ${CSUCCESS}✓${RST}\n" "$label" "$inst"
    else
        printf "  ${CMUTED}%-12s${RST} %-18s ${CWARN}→ %s${RST}\n" "$label" "$inst" "$want"
        NEED_REBUILD=true
    fi
}

WANTED_BUILD="${ODOO_BUILD}"
[ "$WANTED_BUILD" = "latest" ] && WANTED_BUILD="${ODOO_B:-${LATEST:-latest}}"   # latest = whatever the image holds
row "Odoo" "${ODOO_V:+$ODOO_V.$ODOO_B}" "${ODOO_VERSION}.${WANTED_BUILD}"
row "Python" "$PY_V" "$PYTHON_VERSION"
row "PostgreSQL" "$PG_V" "$POSTGRES_VERSION"
if container_running "$ODOO_CONTAINER"; then
    # Mounted source folders must be on the same series (Odoo refuses to start otherwise)
    while IFS='=' read -r kind ver; do
        [ -z "$kind" ] && continue
        case "$kind" in enterprise) label="Enterprise" ;; odoo) label="Odoo src" ;; esac
        case "$ver" in
            none)    printf "  ${CMUTED}%-12s %-18s not mounted${RST}\n" "$label" "-" ;;
            unknown) printf "  ${CMUTED}%-12s${RST} %-18s ${CMUTED}series unknown (not a git repo)${RST}\n" "$label" "?" ;;
            *)       if [ "$ver" = "$ODOO_VERSION" ]; then printf "  ${CMUTED}%-12s${RST} %-18s ${CSUCCESS}✓${RST}\n" "$label" "$ver"
                     else printf "  ${CMUTED}%-12s${RST} %-18s ${CERROR}✗ must be %s${RST}\n" "$label" "$ver" "$ODOO_VERSION"; REPO_MISMATCH=true; fi ;;
        esac
    done <<< "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/check_paths_version.sh --print 2>/dev/null)"
fi
echo
if [ -n "$LATEST" ]; then
    if [ "$ODOO_B" = "$LATEST" ]; then
        ui_kv "Nightly" "${LATEST} ${CSUCCESS}(up to date)${RST}"
    elif [ "$ODOO_BUILD" = "latest" ] && [ -n "$ODOO_B" ]; then
        ui_kv "Nightly" "${LATEST} ${CMUTED}newer than ${ODOO_B} — rebuild -n to refresh${RST}"
    else
        ui_kv "Nightly" "${LATEST} ${CMUTED}latest build for Odoo ${ODOO_VERSION}${RST}"
    fi
else
    ui_kv "Nightly" "${CMUTED}unreachable${RST}"
fi
ui_kv "Images" "$(odoo_image) $([ -n "$(image_id "$(odoo_image)")" ] && printf "${CSUCCESS}✓${RST}" || printf "${CWARN}missing${RST}")"
ui_kv "" "$(db_image) $([ -n "$(image_id "$(db_image)")" ] && printf "${CSUCCESS}✓${RST}" || printf "${CWARN}missing${RST}")"
ui_kv "" "$(utils_image) $([ -n "$(image_id "$(utils_image)")" ] && printf "${CSUCCESS}✓${RST}" || printf "${CWARN}missing${RST}")"
echo
if $NEED_REBUILD; then
    ui_warn "Containers differ from .env — run: rebuild"
else
    ui_ok "Containers match .env"
fi
$REPO_MISMATCH && ui_warn "Mounted repos are on another series (Odoo will not start) — run: pull"
echo
