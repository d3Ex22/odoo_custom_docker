#!/bin/bash
# ============================================================================
# set - Configure Odoo environment settings
# ============================================================================
# Usage: set [-h|--help] <VAR> [value]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

get_valid_odoo_versions() {
    [ ! -f "$COMPAT_FILE" ] && echo "19.0 18.0 17.0 16.0 15.0" && return
    grep -v '^#' "$COMPAT_FILE" | grep -v '^$' | cut -d: -f1 | tr -d ' ' | tr '\n' ' '
}

get_valid_python_versions() {
    local odoo="${1:-${ODOO_VERSION}}"
    [ ! -f "$COMPAT_FILE" ] && echo "3.12 3.11 3.10" && return
    grep -E "^${odoo}[[:space:]]*:" "$COMPAT_FILE" | cut -d: -f3 | tr -d ' ' | tr ',' ' '
}

get_valid_postgres_versions() {
    local odoo="${1:-${ODOO_VERSION}}"
    [ ! -f "$COMPAT_FILE" ] && echo "17 16 15" && return
    grep -E "^${odoo}[[:space:]]*:" "$COMPAT_FILE" | cut -d: -f5 | tr -d ' ' | tr ',' ' '
}

validate_python() {
    local py="$1"
    local odoo="${ODOO_VERSION}"
    local valid=$(get_valid_python_versions "$odoo")
    for v in $valid; do
        [ "$py" = "$v" ] && return 0
    done
    return 1
}

validate_postgres() {
    local pg="$1"
    local odoo="${ODOO_VERSION}"
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
    echo "conf - Configure Odoo environment settings"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       conf <VAR> [value]"
    echo "       set"
    echo ""
    printf "   ${CPRIMARY}VARIABLES${RST}\n"
    echo "       SELECTED_DB <name>       ${CPRIMARY}Active database               ${RST}"
    echo "       ODOO_UPDATE <modules>    ${CPRIMARY}Modules to -u on start        ${RST}"
    echo "       ODOO_ARGS <args>         ${CPRIMARY}Extra Odoo arguments          ${RST}"
    echo "       ODOO_VERSION <ver>       ${CPRIMARY}Odoo version (rebuild)        ${RST}"
    echo "       ODOO_BUILD <build>       ${CPRIMARY}Build date (rebuild)          ${RST}"
    echo "       PYTHON_VERSION <ver>     ${CPRIMARY}Python version (rebuild)      ${RST}"
    echo "       POSTGRES_VERSION <ver>   ${CPRIMARY}PostgreSQL version (rebuild)  ${RST}"
    echo ""
    printf "   ${CPRIMARY}SPECIAL VALUES${RST}\n"
    echo "       conf <VAR> -              ${CPRIMARY}Clear/reset the value         ${RST}"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       conf SELECTED_DB production"
    echo "       conf ODOO_UPDATE sale,purchase"
    echo "       conf ODOO_ARGS \"--dev xml --limit-time-real 0\""
    echo "       conf ODOO_UPDATE -"
    echo ""
}

help_selected_db() {
    echo ""
    echo "conf SELECTED_DB - Set active database"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       conf SELECTED_DB <name>"
    echo "       conf SELECTED_DB -"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Sets SELECTED_DB in .env"
    echo "       Use '-' to clear the value"
    echo "       Restart Odoo with 'r' to apply"
    echo ""
}

help_odoo_update() {
    echo ""
    echo "conf ODOO_UPDATE - Set modules to update on start"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       conf ODOO_UPDATE <module1,module2,...>"
    echo "       conf ODOO_UPDATE -"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Sets ODOO_UPDATE in .env"
    echo "       Modules will be updated (-u) on each Odoo start"
    echo "       Use '-' to clear the value"
    echo ""
}

help_odoo_args() {
    echo ""
    echo "conf ODOO_ARGS - Set extra Odoo arguments"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       conf ODOO_ARGS \"<arguments>\""
    echo "       conf ODOO_ARGS -"
    echo ""
    printf "   ${CPRIMARY}COMMON ARGUMENTS${RST}\n"
    echo "       --dev xml           ${CPRIMARY}Auto-reload XML views            ${RST}"
    echo "       --limit-time-real 0 ${CPRIMARY}Disable timeout                  ${RST}"
    echo "       --log-level=debug   ${CPRIMARY}Debug logging                    ${RST}"
    echo ""
    printf "   ${CPRIMARY}EXAMPLE${RST}\n"
    echo "       conf ODOO_ARGS \"--dev xml --limit-time-real 0\""
    echo ""
}

set_value() { set_env_value "$@"; }

show_current() {
    local py_valid=$(get_valid_python_versions)
    local pg_valid=$(get_valid_postgres_versions)

    echo "Current settings:"
    echo ""
    printf "   ${CPRIMARY}SELECTED_DB${RST}       %s\n" "${SELECTED_DB}"
    printf "   ${CPRIMARY}ODOO_UPDATE${RST}       %s\n" "${ODOO_UPDATE}"
    printf "   ${CPRIMARY}ODOO_ARGS${RST}         %s\n" "${ODOO_ARGS}"
    echo ""
    printf "   ${CPRIMARY}ODOO_VERSION${RST}      %s\n" "${ODOO_VERSION}"
    printf "   ${CPRIMARY}ODOO_BUILD${RST}        %s\n" "${ODOO_BUILD}"
    printf "   ${CPRIMARY}PYTHON_VERSION${RST}    %s  ${CPRIMARY}(valid: %s)${RST}\n" "${PYTHON_VERSION}" "$py_valid"
    printf "   ${CPRIMARY}POSTGRES_VERSION${RST}  %s  ${CPRIMARY}(valid: %s)${RST}\n" "${POSTGRES_VERSION}" "$pg_valid"
    echo ""
    echo "Use 'conf <VAR> --help' for details"
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
            echo "Current: SELECTED_DB=${SELECTED_DB}"
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
            echo "Current: ODOO_UPDATE=${ODOO_UPDATE}"
            exit 0
        fi
        if [ "$2" != "-" ]; then
            ${_PROJECT_ROOT}/.data/scripts/check_modules.sh "$2" "" "$MODULES_CACHE"
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
            echo "Current: ODOO_ARGS=${ODOO_ARGS}"
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
            echo "Current: ODOO_VERSION=${ODOO_VERSION}"
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
            echo "Current: ODOO_BUILD=${ODOO_BUILD}"
            exit 0
        fi
        set_value "ODOO_BUILD" "$2"
        echo "✓ ODOO_BUILD=${2}"
        echo "  Run 'rebuild' to apply"
        ;;
    PYTHON_VERSION)
        if [ -z "$2" ]; then
            echo "Current: PYTHON_VERSION=${PYTHON_VERSION}"
            echo "Valid for Odoo ${ODOO_VERSION}: $(get_valid_python_versions)"
            exit 0
        fi
        if ! validate_python "$2"; then
            echo "❌ Invalid PYTHON_VERSION: $2"
            echo "   Valid for Odoo ${ODOO_VERSION}: $(get_valid_python_versions)"
            exit 1
        fi
        set_value "PYTHON_VERSION" "$2"
        echo "✓ PYTHON_VERSION=${2}"
        echo "  Run 'rebuild' to apply"
        ;;
    POSTGRES_VERSION)
        if [ -z "$2" ]; then
            echo "Current: POSTGRES_VERSION=${POSTGRES_VERSION}"
            echo "Valid for Odoo ${ODOO_VERSION}: $(get_valid_postgres_versions)"
            exit 0
        fi
        if ! validate_postgres "$2"; then
            echo "❌ Invalid POSTGRES_VERSION: $2"
            echo "   Valid for Odoo ${ODOO_VERSION}: $(get_valid_postgres_versions)"
            exit 1
        fi
        set_value "POSTGRES_VERSION" "$2"
        echo "✓ POSTGRES_VERSION=${2}"
        echo "  Run 'rebuild' to apply"
        ;;
    *)
        echo "❌ Unknown variable: $1"
        echo "   Use 'conf --help' for available variables"
        exit 1
        ;;
esac
