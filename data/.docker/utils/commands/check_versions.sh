#!/bin/bash
# ============================================================================
# check_versions - Display installed versions
# ============================================================================
# Usage: check_versions [-h|--help]
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
    echo "check_versions - Display installed versions"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       check_versions"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Shows the currently installed versions of Odoo, Python,"
    echo "       and PostgreSQL in the running containers."
    echo "       Also shows the latest available Odoo build from nightly."
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
ODOO_CONTAINER="${PROJECT}_odoo"
DB_CONTAINER="${PROJECT}_db"

echo "Installed versions:"
echo ""

ODOO_PKG=$(docker exec "$ODOO_CONTAINER" dpkg -s odoo 2>/dev/null | grep -oP '(?<=Version: )\S+')
ODOO_V=$(echo "$ODOO_PKG" | grep -oP '^\d+\.\d+')
ODOO_BUILD=$(echo "$ODOO_PKG" | grep -oP '\d{8}$')

LATEST_BUILD=$(curl -s --connect-timeout 3 "http://nightly.odoo.com/${ODOO_V:-19.0}/nightly/deb/" 2>/dev/null | \
    grep -oP "odoo_${ODOO_V:-19.0}\.\d+_all\.deb" | grep -oP '\d{8}' | sort -r | head -1)

printf "   Odoo: %s" "${ODOO_V:-not running}"
[ -n "$ODOO_BUILD" ] && printf " (build: %s)" "$ODOO_BUILD"
if [ -n "$LATEST_BUILD" ] && [ "$ODOO_BUILD" != "$LATEST_BUILD" ]; then
    printf " → %s available" "$LATEST_BUILD"
elif [ -n "$LATEST_BUILD" ]; then
    printf " ✓"
fi
echo ""

PY_V=$(docker exec "$ODOO_CONTAINER" python3 --version 2>/dev/null | grep -oP '\d+\.\d+')
echo "   Python: ${PY_V:-not running}"

PG_V=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)
echo "   PostgreSQL: ${PG_V:-not running}"

echo ""
