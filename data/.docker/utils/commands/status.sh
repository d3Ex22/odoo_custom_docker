#!/bin/bash
# ============================================================================
# status - Display container status
# ============================================================================
# Usage: status [-h|--help]
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

show_help() {
    echo ""
    echo "status - Display container status"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       status"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Shows the status of all Docker containers in the stack."
    echo "       Displays IP address and health status for each container."
    echo "       If a container has errors, shows the last 5 log lines."
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

GRAY="\033[90m"
BOLD="\033[1m"

echo ""
echo -e "${BOLD}Container Status${RST}"
echo "──────────────────────────────────────────────────────────"
printf "%-20s %-18s %s\n" "NAME" "IP" "STATUS"
echo "──────────────────────────────────────────────────────────"

CONTAINERS=("${PROJECT}_traefik" "${PROJECT}_db" "${PROJECT}_odoo" "${PROJECT}_utils" "${PROJECT}_ttyd_utils" "${PROJECT}_ttyd_logs")
ERRORS=""

for CONTAINER in "${CONTAINERS[@]}"; do
    SHORT_NAME=$(echo "$CONTAINER" | sed "s/${PROJECT}_//")
    
    if ! docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
        printf "%-20s %-18s ${GRAY}not created${RST}\n" "$SHORT_NAME" "-"
        continue
    fi
    
    STATUS=$(docker inspect -f '{{.State.Status}}' "$CONTAINER" 2>/dev/null)
    HEALTH=$(docker inspect -f '{{.State.Health.Status}}' "$CONTAINER" 2>/dev/null)
    IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CONTAINER" 2>/dev/null)
    
    if [ "$STATUS" = "running" ]; then
        if [ "$HEALTH" = "unhealthy" ]; then
            STATUS_COLOR="${RED}"
            STATUS_TEXT="unhealthy"
            ERRORS="$ERRORS$CONTAINER\n"
        elif [ "$HEALTH" = "healthy" ]; then
            STATUS_COLOR="${GREEN}"
            STATUS_TEXT="healthy"
        else
            STATUS_COLOR="${GREEN}"
            STATUS_TEXT="running"
        fi
    elif [ "$STATUS" = "restarting" ]; then
        STATUS_COLOR="${YELLOW}"
        STATUS_TEXT="restarting"
        ERRORS="$ERRORS$CONTAINER\n"
    else
        STATUS_COLOR="${RED}"
        STATUS_TEXT="$STATUS"
        ERRORS="$ERRORS$CONTAINER\n"
    fi
    
    [ -z "$IP" ] && IP="-"
    
    printf "%-20s %-18s ${STATUS_COLOR}${STATUS_TEXT}${RST}\n" "$SHORT_NAME" "$IP"
done

echo "──────────────────────────────────────────────────────────"

if [ -n "$ERRORS" ]; then
    echo ""
    echo -e "${RED}${BOLD}Error Logs${RST}"
    echo "──────────────────────────────────────────────────────────"
    echo -e "$ERRORS" | while read -r CONTAINER; do
        [ -z "$CONTAINER" ] && continue
        SHORT_NAME=$(echo "$CONTAINER" | sed "s/${PROJECT}_//")
        echo -e "${YELLOW}► $SHORT_NAME${RST}"
        docker logs "$CONTAINER" --tail 5 2>&1 | sed 's/^/  /'
        echo ""
    done
fi

echo ""
