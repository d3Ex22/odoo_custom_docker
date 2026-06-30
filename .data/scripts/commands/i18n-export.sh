#!/bin/bash
# ============================================================================
# i18n-export - Export translation files for Odoo module(s)
# ============================================================================
# Usage: i18n-export [-h|--help] [-d DATABASE] [-l LANGUAGE] MODULE[,MODULE2,...]
# Alias: i18n
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "i18n-export - Export translation files for Odoo module(s)"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       i18n-export MODULE[,MODULE2,...]"
    echo "       i18n-export -l fr_FR sale"
    echo "       i18n-export -a my_module"
    echo "       i18n-export --pot my_module"
    echo "       i18n MODULE"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       MODULE    Module name(s) to export, comma-separated"
    echo "                 Supports regex patterns: sale_*, 3ds_*"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -d, --database DB   Database (default: SELECTED_DB)"
    echo "       -l, --language LANG Odoo language code (default: fr_FR → fr.po)"
    echo "       -a, --all-langs     Export every active language from the database"
    echo "       --pot               Export template to i18n/<module>.pot"
    echo "       -h, --help          Show this help"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Runs Odoo --i18n-export and writes PO/POT files under each"
    echo "       module's i18n/ directory. Odoo must be stopped during export."
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       i18n-export 3ds_helpdesk_ticket_credits"
    echo "       i18n-export -l en_US sale,purchase"
    echo "       i18n-export -a 3ds_*"
    echo "       i18n-export --pot my_module"
    echo ""
    printf "   ${CPRIMARY}CONFIGURATION${RST} (from .env)\n"
    echo "       SELECTED_DB    Default database"
    echo ""
}

lang_to_filename() {
    local lang="$1"
    if [ "$lang" = "pot" ]; then
        echo "pot"
        return
    fi
    if [[ "$lang" == *_* ]]; then
        echo "${lang%%_*}.po"
    else
        echo "${lang}.po"
    fi
}

find_module_path() {
    local module="$1"
    local paths="$2"
    docker exec "$ODOO_CONTAINER" bash -c "
        IFS=',' read -ra ADDON_PATHS <<< '$paths'
        for addon_path in \"\${ADDON_PATHS[@]}\"; do
            [ -z \"\$addon_path\" ] && continue
            found=\$(find \"\$addon_path\" -path '*/${module}/__manifest__.py' -print -quit 2>/dev/null)
            if [ -n \"\$found\" ]; then
                dirname \"\$found\"
                exit 0
            fi
        done
        exit 1
    " 2>/dev/null
}

export_module_lang() {
    local module="$1"
    local lang="$2"
    local output_kind="$3"
    local module_path
    local output_file
    local output_path
    local lang_arg

    module_path=$(find_module_path "$module" "$ADDON_PATHS")
    if [ -z "$module_path" ]; then
        printf "${CERROR}❌ Module '%s' not found in addons paths${RST}\n" "$module" >&2
        return 1
    fi

    if [ "$output_kind" = "pot" ]; then
        output_file="${module}.pot"
        lang_arg="en_US"
    else
        output_file=$(lang_to_filename "$lang")
        lang_arg="$lang"
    fi

    output_path="${module_path}/i18n/${output_file}"
    docker exec "$ODOO_CONTAINER" mkdir -p "${module_path}/i18n" 2>/dev/null

    printf "  ${CWARN}▶${RST} %s → i18n/%s (%s)\n" "$module" "$output_file" "$lang_arg"

    local log rc
    log=$(docker exec "$ODOO_CONTAINER" odoo -c /etc/odoo/odoo.conf \
        -d "$DBNAME" \
        --stop-after-init \
        --no-http \
        --i18n-export="$output_path" \
        --modules="$module" \
        -l "$lang_arg" \
        --addons-path="$ADDON_PATHS" \
        --log-level=warn 2>&1)
    rc=$?

    if [ "$rc" -ne 0 ]; then
        printf "${CERROR}  ❌ Export failed for %s${RST}\n" "$module" >&2
        echo "$log" | sed 's/^/    /' >&2
        return 1
    fi

    if ! docker exec "$ODOO_CONTAINER" test -f "$output_path"; then
        printf "${CERROR}  ❌ Output file not created: %s${RST}\n" "$output_path" >&2
        return 1
    fi

    return 0
}

DBNAME=""
LANGUAGE="fr_FR"
ALL_LANGS=false
EXPORT_POT=false
MODULES=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            show_help
            exit 0
            ;;
        -d|--database)
            DBNAME="$2"
            shift 2
            ;;
        -l|--language)
            LANGUAGE="$2"
            shift 2
            ;;
        -a|--all-langs)
            ALL_LANGS=true
            shift
            ;;
        --pot)
            EXPORT_POT=true
            shift
            ;;
        -*)
            printf "${CERROR}❌ Unknown option: %s${RST}\n" "$1"
            show_help
            exit 1
            ;;
        *)
            if [ -z "$MODULES" ]; then
                MODULES="$1"
            else
                MODULES="${MODULES},$1"
            fi
            shift
            ;;
    esac
done

if [ -z "$MODULES" ]; then
    echo "❌ No module specified"
    echo "   Usage: i18n-export MODULE[,MODULE2,...]"
    exit 1
fi

[ -z "$DBNAME" ] && DBNAME="${SELECTED_DB}"
if [ -z "$DBNAME" ]; then
    echo "❌ No database specified and no SELECTED_DB in .env"
    echo "   Usage: i18n-export -d <database> MODULE"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${ODOO_CONTAINER}$"; then
    echo "❌ Odoo container is not running"
    exit 1
fi

if ! db_exists "$DBNAME"; then
    echo "❌ Database '$DBNAME' does not exist"
    exit 1
fi

MODULES=$(expand_modules "$MODULES")
[ -z "$MODULES" ] && { echo "❌ No matching modules found"; exit 1; }

ADDON_PATHS=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)
[ -z "$ADDON_PATHS" ] && { echo "❌ Could not resolve addons paths"; exit 1; }

if [ "$ALL_LANGS" = true ] && [ "$EXPORT_POT" = true ]; then
    echo "❌ --all-langs and --pot cannot be used together"
    exit 1
fi

if docker exec "$ODOO_CONTAINER" tmux has-session -t "$ODOO_TMUX_SESSION" 2>/dev/null; then
    dead=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "${ODOO_TMUX_SESSION}:0.1" -p '#{pane_dead}' 2>/dev/null)
    if [ "$dead" != "1" ]; then
        printf "${CWARN}⚠ Stopping Odoo before translation export...${RST}\n"
        stop_odoo || exit 1
        sleep 0.3
        RESTART_AFTER=true
    fi
fi

echo ""
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
printf "${CPRIMARY}  I18N EXPORT${RST}  (${DBNAME})\n"
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
echo ""

FAILED=0
IFS=',' read -ra MODULE_LIST <<< "$MODULES"
for module in "${MODULE_LIST[@]}"; do
    module=$(echo "$module" | xargs)
    [ -z "$module" ] && continue

    if [ "$EXPORT_POT" = true ]; then
        export_module_lang "$module" "" "pot" || FAILED=$((FAILED + 1))
        continue
    fi

    if [ "$ALL_LANGS" = true ]; then
        LANGS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" -tAc \
            "SELECT code FROM res_lang WHERE active ORDER BY code;" 2>/dev/null | sed '/^$/d')
        if [ -z "$LANGS" ]; then
            printf "${CERROR}❌ No active languages found in database${RST}\n"
            FAILED=$((FAILED + 1))
            continue
        fi
        while IFS= read -r lang; do
            [ -z "$lang" ] && continue
            export_module_lang "$module" "$lang" "po" || FAILED=$((FAILED + 1))
        done <<< "$LANGS"
    else
        export_module_lang "$module" "$LANGUAGE" "po" || FAILED=$((FAILED + 1))
    fi
done

echo ""
if [ "$FAILED" -gt 0 ]; then
    printf "${CERROR}❌ %d export(s) failed${RST}\n" "$FAILED"
    [ "${RESTART_AFTER:-false}" = true ] && printf "${CWARN}⚠ Odoo was stopped; run 'start' or 'u' to restart${RST}\n"
    exit 1
fi

printf "${CSUCCESS}✓ Translation export completed${RST}\n"
[ "${RESTART_AFTER:-false}" = true ] && printf "${CWARN}⚠ Odoo was stopped; run 'start' or 'u' to restart${RST}\n"
echo ""
