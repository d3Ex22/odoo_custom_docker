#!/bin/bash
# ============================================================================
# set - Configure Odoo environment settings
# ============================================================================
# Usage: set [-h|--help] <VAR> [value]
# ============================================================================

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C=$(printf '\033[38;2;%s;%s;%sm' "$R" "$G" "$B")
RST=$(printf '\033[0m')

ENV_FILE="/home/odoo/docker_dev/.env"
COMPAT_FILE="/home/odoo/docker_dev/data/versions.conf"

get_valid_odoo_versions() {
    [ ! -f "$COMPAT_FILE" ] && echo "19.0 18.0 17.0 16.0 15.0" && return
    grep -v '^#' "$COMPAT_FILE" | grep -v '^$' | cut -d: -f1 | tr '\n' ' '
}

get_valid_python_versions() {
    local odoo="${1:-${ODOO_VERSION:-19.0}}"
    [ ! -f "$COMPAT_FILE" ] && echo "3.12 3.11 3.10" && return
    grep "^${odoo}:" "$COMPAT_FILE" | cut -d: -f2 | tr ',' ' '
}

get_valid_postgres_versions() {
    local odoo="${1:-${ODOO_VERSION:-19.0}}"
    [ ! -f "$COMPAT_FILE" ] && echo "17 16 15" && return
    grep "^${odoo}:" "$COMPAT_FILE" | cut -d: -f3 | tr ',' ' ' | tr -d ' \n' | tr ',' ' '
}

validate_python() {
    local py="$1"
    local odoo="${ODOO_VERSION:-19.0}"
    local valid=$(get_valid_python_versions "$odoo")
    for v in $valid; do
        [ "$py" = "$v" ] && return 0
    done
    return 1
}

validate_postgres() {
    local pg="$1"
    local odoo="${ODOO_VERSION:-19.0}"
    local valid=$(get_valid_postgres_versions "$odoo")
    for v in $valid; do
        [ "$pg" = "$v" ] && return 0
    done
    return 1
}

validate_odoo_version() {
    local odoo="$1"
    local valid=$(get_valid_odoo_versions)
    for v in $valid; do
        [ "$odoo" = "$v" ] && return 0
    done
    return 1
}

show_help() {
    echo ""
    echo "set - Configure Odoo environment settings"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       set <VAR> [value]"
    echo "       set"
    echo ""
    printf "   ${C}VARIABLES${RST}\n"
    echo "       SELECTED_DB <name>       ${C}Active database               ${RST}"
    echo "       ODOO_UPDATE <modules>    ${C}Modules to -u on start        ${RST}"
    echo "       ODOO_ARGS <args>         ${C}Extra Odoo arguments          ${RST}"
    echo "       ODOO_VERSION <ver>       ${C}Odoo version (rebuild)        ${RST}"
    echo "       ODOO_BUILD <build>       ${C}Build date (rebuild)          ${RST}"
    echo "       PYTHON_VERSION <ver>     ${C}Python version (rebuild)      ${RST}"
    echo "       POSTGRES_VERSION <ver>   ${C}PostgreSQL version (rebuild)  ${RST}"
    echo ""
    printf "   ${C}SPECIAL VALUES${RST}\n"
    echo "       set <VAR> -              ${C}Clear/reset the value         ${RST}"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       set SELECTED_DB production"
    echo "       set ODOO_UPDATE sale,purchase"
    echo "       set ODOO_ARGS \"--dev xml --limit-time-real 0\""
    echo "       set ODOO_UPDATE -"
    echo ""
}

help_selected_db() {
    echo ""
    echo "set SELECTED_DB - Set active database"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       set SELECTED_DB <name>"
    echo "       set SELECTED_DB -"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Sets SELECTED_DB in .env"
    echo "       Use '-' to clear the value"
    echo "       Restart Odoo with 'r' to apply"
    echo ""
}

help_odoo_update() {
    echo ""
    echo "set ODOO_UPDATE - Set modules to update on start"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       set ODOO_UPDATE <module1,module2,...>"
    echo "       set ODOO_UPDATE -"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Sets ODOO_UPDATE in .env"
    echo "       Modules will be updated (-u) on each Odoo start"
    echo "       Use '-' to clear the value"
    echo ""
}

help_odoo_args() {
    echo ""
    echo "set ODOO_ARGS - Set extra Odoo arguments"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       set ODOO_ARGS \"<arguments>\""
    echo "       set ODOO_ARGS -"
    echo ""
    printf "   ${C}COMMON ARGUMENTS${RST}\n"
    echo "       --dev xml           ${C}Auto-reload XML views            ${RST}"
    echo "       --limit-time-real 0 ${C}Disable timeout                  ${RST}"
    echo "       --log-level=debug   ${C}Debug logging                    ${RST}"
    echo ""
    printf "   ${C}EXAMPLE${RST}\n"
    echo "       set ODOO_ARGS \"--dev xml --limit-time-real 0\""
    echo ""
}

set_value() {
    local key="$1"
    local value="$2"
    
    if [ "$value" = "-" ]; then
        value=""
    fi
    
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        local tmp_file="/tmp/.env.tmp.$$"
        if [ -z "$value" ]; then
            sed "s|^${key}=.*|${key}=|" "$ENV_FILE" > "$tmp_file"
        else
            sed "s|^${key}=.*|${key}=${value}|" "$ENV_FILE" > "$tmp_file"
        fi
        cat "$tmp_file" > "$ENV_FILE"
        rm -f "$tmp_file"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

show_current() {
    local py_valid=$(get_valid_python_versions)
    local pg_valid=$(get_valid_postgres_versions)
    
    echo "Current settings:"
    echo ""
    printf "   ${C}SELECTED_DB${RST}       %s\n" "${SELECTED_DB:-<not set>}"
    printf "   ${C}ODOO_UPDATE${RST}       %s\n" "${ODOO_UPDATE:-<not set>}"
    printf "   ${C}ODOO_ARGS${RST}         %s\n" "${ODOO_ARGS:-<not set>}"
    echo ""
    printf "   ${C}ODOO_VERSION${RST}      %s\n" "${ODOO_VERSION:-19.0}"
    printf "   ${C}ODOO_BUILD${RST}        %s\n" "${ODOO_BUILD:-latest}"
    printf "   ${C}PYTHON_VERSION${RST}    %s  ${C}(valid: %s)${RST}\n" "${PYTHON_VERSION:-3.12}" "$py_valid"
    printf "   ${C}POSTGRES_VERSION${RST}  %s  ${C}(valid: %s)${RST}\n" "${POSTGRES_VERSION:-17}" "$pg_valid"
    echo ""
    echo "Use 'set <VAR> --help' for details"
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ -z "$1" ]; then
    show_current
    exit 0
fi

VAR=$(echo "$1" | tr '[:lower:]' '[:upper:]')

case "$VAR" in
    SELECTED_DB)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_selected_db
            exit 0
        fi
        if [ -z "$2" ]; then
            echo "Current: SELECTED_DB=${SELECTED_DB:-<not set>}"
            exit 0
        fi
        set_value "SELECTED_DB" "$2"
        echo "✓ SELECTED_DB=${2}"
        echo "  Restart Odoo with 'r' to apply"
        ;;
    ODOO_UPDATE)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_odoo_update
            exit 0
        fi
        if [ -z "$2" ]; then
            echo "Current: ODOO_UPDATE=${ODOO_UPDATE:-<not set>}"
            exit 0
        fi
        if [ "$2" != "-" ]; then
            /home/odoo/docker_dev/data/.docker/utils/commands/utils/check_modules.sh "$2"
        fi
        set_value "ODOO_UPDATE" "$2"
        if [ "$2" = "-" ]; then
            echo "✓ ODOO_UPDATE cleared"
        else
            echo "✓ ODOO_UPDATE=${2}"
        fi
        ;;
    ODOO_ARGS)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_odoo_args
            exit 0
        fi
        if [ -z "$2" ]; then
            echo "Current: ODOO_ARGS=${ODOO_ARGS:-<not set>}"
            exit 0
        fi
        set_value "ODOO_ARGS" "$2"
        if [ "$2" = "-" ]; then
            echo "✓ ODOO_ARGS cleared"
        else
            echo "✓ ODOO_ARGS=${2}"
        fi
        ;;
    ODOO_VERSION)
        if [ -z "$2" ]; then
            echo "Current: ODOO_VERSION=${ODOO_VERSION:-19.0}"
            echo "Valid: $(get_valid_odoo_versions)"
            exit 0
        fi
        if ! validate_odoo_version "$2"; then
            echo "❌ Invalid ODOO_VERSION: $2"
            echo "   Valid: $(get_valid_odoo_versions)"
            exit 1
        fi
        set_value "ODOO_VERSION" "$2"
        echo "✓ ODOO_VERSION=${2}"
        echo "  Run 'rebuild' to apply"
        echo ""
        echo "  Note: Check PYTHON_VERSION and POSTGRES_VERSION compatibility"
        ;;
    ODOO_BUILD)
        if [ -z "$2" ]; then
            echo "Current: ODOO_BUILD=${ODOO_BUILD:-latest}"
            exit 0
        fi
        set_value "ODOO_BUILD" "$2"
        echo "✓ ODOO_BUILD=${2}"
        echo "  Run 'rebuild' to apply"
        ;;
    PYTHON_VERSION)
        if [ -z "$2" ]; then
            echo "Current: PYTHON_VERSION=${PYTHON_VERSION:-3.12}"
            echo "Valid for Odoo ${ODOO_VERSION:-19.0}: $(get_valid_python_versions)"
            exit 0
        fi
        if ! validate_python "$2"; then
            echo "❌ Invalid PYTHON_VERSION: $2"
            echo "   Valid for Odoo ${ODOO_VERSION:-19.0}: $(get_valid_python_versions)"
            exit 1
        fi
        set_value "PYTHON_VERSION" "$2"
        echo "✓ PYTHON_VERSION=${2}"
        echo "  Run 'rebuild' to apply"
        ;;
    POSTGRES_VERSION)
        if [ -z "$2" ]; then
            echo "Current: POSTGRES_VERSION=${POSTGRES_VERSION:-17}"
            echo "Valid for Odoo ${ODOO_VERSION:-19.0}: $(get_valid_postgres_versions)"
            exit 0
        fi
        if ! validate_postgres "$2"; then
            echo "❌ Invalid POSTGRES_VERSION: $2"
            echo "   Valid for Odoo ${ODOO_VERSION:-19.0}: $(get_valid_postgres_versions)"
            exit 1
        fi
        set_value "POSTGRES_VERSION" "$2"
        echo "✓ POSTGRES_VERSION=${2}"
        echo "  Run 'rebuild' to apply"
        ;;
    *)
        echo "❌ Unknown variable: $1"
        echo "   Use 'set --help' for available variables"
        exit 1
        ;;
esac
