#!/bin/bash
# ============================================================================
# status - Display container status
# ============================================================================
# Usage: status [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "status - Display container status"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       status"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Shows the status of all Docker containers in the stack."
    echo "       Displays IP address and health status for each container."
    echo "       If a container has errors, shows the last 5 log lines."
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

echo ""
echo -e "\033[1mContainer Status${RST}"
echo "──────────────────────────────────────────────────────────"
printf "%-20s %-18s %s\n" "NAME" "IP" "STATUS"
echo "──────────────────────────────────────────────────────────"

CONTAINERS=("${PROJECT}_traefik" "${PROJECT}_db" "${PROJECT}_odoo" "${PROJECT}_utils")
ERRORS=""

for CONTAINER in "${CONTAINERS[@]}"; do
    SHORT_NAME=$(echo "$CONTAINER" | sed "s/${PROJECT}_//")

    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        printf "%-20s %-18s ${CMUTED}not created${RST}\n" "$SHORT_NAME" "-"
        continue
    fi

    STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)

    if [ "$STATUS" = "running" ]; then
        if [ "$HEALTH" = "unhealthy" ]; then
            STATUS_COLOR="${CERROR}"
            STATUS_TEXT="unhealthy"
            ERRORS="$ERRORS$CONTAINER\n"
        elif [ "$HEALTH" = "healthy" ]; then
            STATUS_COLOR="${CSUCCESS}"
            STATUS_TEXT="healthy"
        else
            STATUS_COLOR="${CSUCCESS}"
            STATUS_TEXT="running"
        fi
    elif [ "$STATUS" = "restarting" ]; then
        STATUS_COLOR="${CWARN}"
        STATUS_TEXT="restarting"
        ERRORS="$ERRORS$CONTAINER\n"
    else
        STATUS_COLOR="${CERROR}"
        STATUS_TEXT="$STATUS"
        ERRORS="$ERRORS$CONTAINER\n"
    fi

    [ -z "$IP" ] && IP="-"

    printf "%-20s %-18s ${STATUS_COLOR}${STATUS_TEXT}${RST}\n" "$SHORT_NAME" "$IP"
done

echo "──────────────────────────────────────────────────────────"

if [ -n "$ERRORS" ]; then
    echo ""
    echo -e "${CERROR}\033[1mError Logs${RST}"
    echo "──────────────────────────────────────────────────────────"
    echo -e "$ERRORS" | while read -r CONTAINER; do
        [ -z "$CONTAINER" ] && continue
        SHORT_NAME=$(echo "$CONTAINER" | sed "s/${PROJECT}_//")
        echo -e "${CWARN}► $SHORT_NAME${RST}"
        docker logs "$CONTAINER" --tail 5 2>&1 | sed 's/^/  /'
        echo ""
    done
fi

echo ""
