#!/bin/bash
# ============================================================================
# requirements - Run Odoo requirements installer
# ============================================================================
# Usage: requirements [-h|--help]
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

show_help() {
    echo ""
    echo "requirements - Run Odoo requirements installer"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       requirements"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Executes /usr/local/bin/check_requirements.sh in the Odoo container"
    echo "       using the pyenv environment (installs /mnt/extra-addons/requirements.txt)."
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
ODOO_CONTAINER="${PROJECT}_odoo"

if ! docker ps --format '{{.Names}}' | grep -q "^${ODOO_CONTAINER}$"; then
    echo "❌ Odoo container is not running"
    exit 1
fi

docker exec -it "$ODOO_CONTAINER" /usr/local/bin/check_requirements.sh

