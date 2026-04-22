#!/bin/bash
# ============================================================================
# pip - Run pip in Odoo container
# ============================================================================
# Usage: pip [pip arguments] [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "pip - Run pip in Odoo container"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       pip <command> [options]"
    echo ""
    printf "   ${CPRIMARY}COMMON COMMANDS${RST}\n"
    echo "       install <pkg>      ${CPRIMARY}Install a package                ${RST}"
    echo "       uninstall <pkg>    ${CPRIMARY}Uninstall a package              ${RST}"
    echo "       list               ${CPRIMARY}List installed packages          ${RST}"
    echo "       freeze             ${CPRIMARY}Output installed packages        ${RST}"
    echo "       show <pkg>         ${CPRIMARY}Show package details             ${RST}"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       pip install requests"
    echo "       pip list"
    echo "       pip freeze > requirements.txt"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ] || [ -z "$1" ]; then
    show_help
    exit 0
fi

docker exec -it "$ODOO_CONTAINER" pip "$@"
