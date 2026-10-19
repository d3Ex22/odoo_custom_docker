#!/bin/bash
# ============================================================================
# pip - Run pip inside the Odoo virtualenv
# ============================================================================
# Usage: pip <pip arguments> | pip [-h|--help]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "pip" "Run pip inside the Odoo virtualenv (/opt/venv)"
    h_sec "USAGE"
    h_use "pip <command> [options]        every argument is passed to pip"
    h_sec "COMMON COMMANDS"
    h_opt "install <pkg>" "Install a package"
    h_opt "uninstall <pkg>" "Remove a package"
    h_opt "list | freeze" "Installed packages"
    h_opt "show <pkg>" "Package details"
    h_sec "NOTES"
    h_text "Packages installed here are lost on 'rebuild'. To keep them, add"
    h_text "them to a requirements.txt in your addons (installed at start)."
    h_sec "EXAMPLES"
    h_ex "pip install requests" ""
    h_ex "pip list" ""
    h_text "Without argument: this help (pip -h is forwarded to pip)."
    h_end
}

[ $# -eq 0 ] && { show_help; exit 0; }

require_odoo_container
TTY=""; [ -t 0 ] && TTY="-t"
exec docker exec -i $TTY "$ODOO_CONTAINER" pip "$@"
