#!/bin/bash
# ============================================================================
# status - Display container status
# ============================================================================
# Usage: status [-h|--help]
# ============================================================================

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C="\033[38;2;${R};${G};${B}m"
RST="\033[0m"

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

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
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
