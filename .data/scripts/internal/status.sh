#!/bin/bash
# ============================================================================
# status - Stack overview: containers, Odoo process, database, URLs
# ============================================================================
# Usage: status
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh


parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    "") ;;
    *) die "Unknown option: $1" ;;
esac

ui_title "Status" "$PROJECT"

printf "  ${CMUTED}%-10s %-16s %s${RST}\n" "CONTAINER" "IP" "STATE"
ERRORS=()
for SHORT in db odoo utils mail; do
    CONTAINER="${PROJECT}_${SHORT}"
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        [ "$SHORT" = "mail" ] && continue   # optional (COMPOSE_PROFILES=mail)
        printf "  %-10s %-16s ${CMUTED}not created${RST}\n" "$SHORT" "-"
        continue
    fi
    STATE=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    case "$STATE:$HEALTH" in
        running:unhealthy) COLOR="$CERROR"; TEXT="unhealthy"; ERRORS+=("$CONTAINER") ;;
        running:healthy)   COLOR="$CSUCCESS"; TEXT="healthy" ;;
        running:*)         COLOR="$CSUCCESS"; TEXT="running" ;;
        restarting:*)      COLOR="$CWARN"; TEXT="restarting"; ERRORS+=("$CONTAINER") ;;
        *)                 COLOR="$CERROR"; TEXT="$STATE"; ERRORS+=("$CONTAINER") ;;
    esac
    printf "  %-10s %-16s ${COLOR}%s${RST}\n" "$SHORT" "${IP:--}" "$TEXT"
done

echo
if container_running "$ODOO_CONTAINER"; then
    if odoo_process_running; then
        ui_kv "Odoo process" "${CSUCCESS}running${RST}"
    else
        ui_kv "Odoo process" "${CWARN}stopped${RST} ${CMUTED}(s to start)${RST}"
    fi
    IFS='|' read -r ODOO_V ODOO_B <<< "$(installed_odoo_build)"
    PY_V=$(docker exec "$ODOO_CONTAINER" python3 --version 2>/dev/null | grep -oP '\d+\.\d+')
    ui_kv "Odoo" "${ODOO_V:-?}.${ODOO_B:-?}  ${CMUTED}Python ${PY_V:-?} · $(docker inspect "$ODOO_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null)${RST}"
fi
if container_running "$DB_CONTAINER"; then
    PG_V=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)
    ui_kv "PostgreSQL" "${PG_V:-?}"
fi
ui_kv "Database" "${SELECTED_DB:-${CMUTED}none (multi-db)${RST}}"
[ -n "${ODOO_UPDATE:-}" ] && ui_kv "ODOO_UPDATE" "$ODOO_UPDATE"
[ -n "${ODOO_ARGS:-}" ] && ui_kv "ODOO_ARGS" "$ODOO_ARGS"
if curl -sf -m 1 "http://localhost:${MCP_PORT}/health" >/dev/null 2>&1; then
    ui_kv "MCP server" "${CSUCCESS}running${RST}  ${CMUTED}http://${MCP_HOST}/mcp${RST}"
else
    ui_kv "MCP server" "${CWARN}down${RST} ${CMUTED}(.data/volumes/shared/mcp.log)${RST}"
fi
PANES=$(utils_tmux list-panes -t utils:0 -F '#{@role}' 2>/dev/null | grep -v '^$' | paste -sd' ' -)
[ -n "$PANES" ] && ui_kv "Side panes" "$PANES"
[ "${AUTO_UPDATE:-false}" = "true" ] && ui_kv "AUTO_UPDATE" "true ${CMUTED}(watch)${RST}"
[ "${DEBUGPY:-false}" = "true" ] && ui_kv "debugpy" "on  ${CMUTED}attach on localhost:$(debugpy_host_port) (debug)${RST}"

echo
if proxy_running; then
    ui_kv "Proxy" "${CSUCCESS}running${RST}  ${CMUTED}${HUB_URL}${RST}"
else
    ui_kv "Proxy" "${CERROR}stopped${RST} ${CMUTED}(docker compose up -d of any project starts it) — URLs below unreachable${RST}"
fi
ui_kv "Odoo" "http://${ODOO_HOST}"
ui_kv "Logs" "http://${LOGS_HOST}"
ui_kv "Utils" "http://${UTILS_HOST}"
ui_kv "MCP" "http://${MCP_HOST}/mcp"
if [[ "${COMPOSE_PROFILES:-}" == *mail* ]]; then ui_kv "Mail" "http://${MAIL_HOST}"
else ui_kv "Mail" "${CMUTED}catcher off (COMPOSE_PROFILES=mail)${RST}"; fi
ui_kv "Traefik" "http://traefik.docker.localhost"
echo

if [ ${#ERRORS[@]} -gt 0 ]; then
    ui_section "Last logs of containers in error"
    for CONTAINER in "${ERRORS[@]}"; do
        ui_warn "${CONTAINER#${PROJECT}_}"
        docker logs "$CONTAINER" --tail 5 2>&1 | sed 's/^/    /'
        echo
    done
fi
