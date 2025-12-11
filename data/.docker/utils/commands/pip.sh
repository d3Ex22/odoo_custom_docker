#!/bin/bash
# ============================================================================
# pip - Run pip in Odoo container
# ============================================================================
# Usage: pip [pip arguments] [-h|--help]
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
    echo "pip - Run pip in Odoo container"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       pip <command> [options]"
    echo ""
    printf "   ${C}COMMON COMMANDS${RST}\n"
    echo "       install <pkg>      ${C}Install a package                ${RST}"
    echo "       uninstall <pkg>    ${C}Uninstall a package              ${RST}"
    echo "       list               ${C}List installed packages          ${RST}"
    echo "       freeze             ${C}Output installed packages        ${RST}"
    echo "       show <pkg>         ${C}Show package details             ${RST}"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       pip install requests"
    echo "       pip list"
    echo "       pip freeze > requirements.txt"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
    show_help
    exit 0
fi

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
ODOO_CONTAINER="${PROJECT}_odoo"

docker exec -it "$ODOO_CONTAINER" pip "$@"

