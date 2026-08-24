#!/bin/bash
# ============================================================================
# translation - Fresh-export translation files for Odoo module(s)
# ============================================================================
# Usage: translation [-h|--help] [-d DATABASE] [-l LANGUAGE] [MODULE[,MODULE2,...]]
#        translation --all
#        translation          # interactive module picker
# Aliases: i18n-export, i18n
#
# Replaces i18n/fr.po (or other language file) in each selected module with a
# freshly extracted export from the database / source.
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "translation - Fresh-export translation files (replaces module i18n/*.po)"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       translation [MODULE[,MODULE2,...]]"
    echo "       translation aec_*"
    echo "       translation --all"
    echo "       translation -l fr_FR sale,purchase"
    echo "       translation --pot my_module"
    echo "       translation          # interactive picker"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       MODULE    Module name(s), comma-separated"
    echo "                 Supports regex patterns: sale_*, aec_*, 3ds_*"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -d, --database DB   Database (default: SELECTED_DB)"
    echo "       -l, --language LANG Language code (default: fr_FR → fr.po)"
    echo "       --all               Export every module under /mnt/extra-addons"
    echo "       (no MODULE)         Interactive list (extra-addons only, not odoo/enterprise)"
    echo "       -a, --all-langs     Export every active language from the DB"
    echo "       --pot               Also export i18n/<module>.pot template"
    echo "       --no-restart        Ignored (kept for compatibility; Odoo is never stopped)"
    echo "       -h, --help          Show this help"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Extracts translations with Odoo and overwrites each module's"
    echo "       i18n/<lang>.po in place (default: fr.po). On Odoo 19+ uses"
    echo "       \`odoo i18n export -l <lang>\`; older versions use --i18n-export"
    echo "       with --stop-after-init. The running Odoo server is left alone."
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       translation aec_sale_order"
    echo "       translation aec_*"
    echo "       translation --all"
    echo "       translation --pot aec_base,aec_partner"
    echo "       translation"
    echo ""
    printf "   ${CPRIMARY}CONFIGURATION${RST} (from .env)\n"
    echo "       SELECTED_DB    Default database"
    echo ""
}

lang_to_po_filename() {
    local lang="$1"
    if [[ "$lang" == *_* ]]; then
        echo "${lang%%_*}.po"
    else
        echo "${lang}.po"
    fi
}

# Odoo 19 CLI accepts short codes (fr) or locales (fr_FR). Prefer short for -l.
lang_to_cli_code() {
    local lang="$1"
    if [ "$lang" = "pot" ]; then
        echo "pot"
        return
    fi
    if [[ "$lang" == *_* ]]; then
        echo "${lang%%_*}"
    else
        echo "$lang"
    fi
}

odoo_major_version() {
    # Prefer .env ODOO_VERSION (e.g. 19.0), fallback to `odoo --version`.
    local ver="${ODOO_VERSION:-}"
    if [ -z "$ver" ]; then
        ver=$(docker exec "$ODOO_CONTAINER" odoo --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    fi
    echo "${ver%%.*}"
}

supports_i18n_cli() {
    local major
    major=$(odoo_major_version)
    [ -n "$major" ] && [ "$major" -ge 19 ] 2>/dev/null
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

# Legacy Odoo ≤18: --i18n-export=/path --modules=M -l LANG
export_module_lang_legacy() {
    local module="$1"
    local lang="$2"
    local output_kind="$3"
    local module_path output_file output_path lang_arg

    module_path=$(find_module_path "$module" "$ADDON_PATHS")
    if [ -z "$module_path" ]; then
        printf "${CERROR}❌ Module '%s' not found in addons paths${RST}\n" "$module" >&2
        return 1
    fi

    if [ "$output_kind" = "pot" ]; then
        output_file="${module}.pot"
        lang_arg="en_US"
    else
        output_file=$(lang_to_po_filename "$lang")
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

    if ! docker exec "$ODOO_CONTAINER" test -s "$output_path"; then
        printf "${CERROR}  ❌ Output file missing or empty: %s${RST}\n" "$output_path" >&2
        return 1
    fi
    return 0
}

# Odoo 19+: odoo i18n export -d DB MODULE... -l LANG [pot]
# Writes directly under each module's i18n/ (overwrites fr.po / .pot).
export_modules_cli() {
    local langs_csv="$1"   # e.g. "fr" or "fr,pot" or "fr_FR,en_US"
    shift
    local -a modules=("$@")
    local -a lang_args=()
    local lang cli_lang

    IFS=',' read -ra _langs <<< "$langs_csv"
    for lang in "${_langs[@]}"; do
        lang=$(echo "$lang" | xargs)
        [ -z "$lang" ] && continue
        cli_lang=$(lang_to_cli_code "$lang")
        lang_args+=("$cli_lang")
    done

    if [ "${#modules[@]}" -eq 0 ] || [ "${#lang_args[@]}" -eq 0 ]; then
        echo "❌ Internal error: no modules or languages for i18n export" >&2
        return 1
    fi

    # Ensure i18n dirs exist. Do NOT delete existing po before a successful
    # export — Odoo overwrites in place; pre-delete left empty modules on failure.
    local module module_path targets=""
    for module in "${modules[@]}"; do
        module_path=$(find_module_path "$module" "$ADDON_PATHS")
        if [ -z "$module_path" ]; then
            printf "${CERROR}❌ Module '%s' not found in addons paths${RST}\n" "$module" >&2
            return 1
        fi
        docker exec "$ODOO_CONTAINER" mkdir -p "${module_path}/i18n" 2>/dev/null
        targets=""
        for lang in "${_langs[@]}"; do
            lang=$(echo "$lang" | xargs)
            [ -z "$lang" ] && continue
            if [ "$lang" = "pot" ]; then
                targets="${targets:+$targets,}${module}.pot"
            else
                targets="${targets:+$targets,}$(lang_to_po_filename "$lang")"
            fi
        done
        printf "  ${CWARN}▶${RST} %s → i18n/%s\n" "$module" "$targets"
    done

    local log rc
    # IMPORTANT:
    # - always pass -l explicitly (Odoo 19 defaults to 'pot' when -l is omitted)
    # - global-looking opts (-c/-d/-l) belong to the `i18n export` subcommand
    # - MODULE args must come before -l (nargs='+' would eat modules)
    # - runs alongside the server; no need to stop Odoo
    log=$(docker exec "$ODOO_CONTAINER" odoo \
        i18n export \
        -c /etc/odoo/odoo.conf \
        -d "$DBNAME" \
        "${modules[@]}" \
        -l "${lang_args[@]}" \
        2>&1)
    rc=$?

    if [ "$rc" -ne 0 ]; then
        printf "${CERROR}❌ odoo i18n export failed${RST}\n" >&2
        echo "$log" | sed 's/^/    /' >&2
        return 1
    fi

    # Verify outputs (warn on empty — some metadata-only modules export empty po).
    local missing=0
    for module in "${modules[@]}"; do
        module_path=$(find_module_path "$module" "$ADDON_PATHS")
        for lang in "${_langs[@]}"; do
            lang=$(echo "$lang" | xargs)
            [ -z "$lang" ] && continue
            if [ "$lang" = "pot" ]; then
                output_path="${module_path}/i18n/${module}.pot"
            else
                output_path="${module_path}/i18n/$(lang_to_po_filename "$lang")"
            fi
            if ! docker exec "$ODOO_CONTAINER" test -f "$output_path"; then
                printf "${CERROR}  ❌ Missing: %s${RST}\n" "$output_path" >&2
                missing=$((missing + 1))
            fi
        done
    done
    [ "$missing" -gt 0 ] && return 1
    return 0
}

# Modules under /mnt/extra-addons only (excludes Odoo core + enterprise).
list_extra_addon_modules() {
    docker exec "$ODOO_CONTAINER" bash -c '
        if [ ! -d /mnt/extra-addons ]; then
            exit 0
        fi
        find /mnt/extra-addons \( -path "*/.*" -o -path "*/__pycache__/*" \) -prune -o \
            -name "__manifest__.py" -type f -print 2>/dev/null \
            | sed "s|/__manifest__.py||" \
            | while IFS= read -r dir; do
                basename "$dir"
              done \
            | sort -u
    ' 2>/dev/null
}

extra_addon_modules_csv() {
    list_extra_addon_modules | paste -sd, -
}

prompt_select_modules() {
    # Interactive picker when no MODULE / --all was given.
    local modules_csv
    modules_csv=$(extra_addon_modules_csv)
    if [ -z "$modules_csv" ]; then
        echo "❌ No modules found under /mnt/extra-addons"
        echo "   (Odoo core and enterprise are excluded)"
        exit 1
    fi

    local -a modules=()
    IFS=',' read -ra modules <<< "$modules_csv"

    echo ""
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CPRIMARY}  Select modules to export${RST}  (extra-addons only)\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"
    printf "    ${CSUCCESS}%2s.${RST} %s\n" "0" "all"

    local i=1
    declare -A MODULE_MAP
    local m
    for m in "${modules[@]}"; do
        m=$(echo "$m" | xargs)
        [ -z "$m" ] && continue
        printf "    ${CSUCCESS}%2d.${RST} %s\n" "$i" "$m"
        MODULE_MAP[$i]="$m"
        i=$((i + 1))
    done

    echo ""
    printf "  Select (0=all / 1,2,3 / names / patterns) [all]: "
    local choice
    read -r choice

    choice=$(echo "${choice:-all}" | xargs)
    if [ -z "$choice" ] || [ "$choice" = "all" ] || [ "$choice" = "0" ] || [ "$choice" = "*" ]; then
        EXPORT_ALL=true
        return 0
    fi

    # Pure numeric list? map indices → module names
    if [[ "$choice" =~ ^[0-9,\ ]+$ ]]; then
        local selected="" num
        IFS=',' read -ra nums <<< "$choice"
        for num in "${nums[@]}"; do
            num=$(echo "$num" | xargs)
            [ -z "$num" ] && continue
            if [ "$num" = "0" ]; then
                EXPORT_ALL=true
                return 0
            fi
            if [ -n "${MODULE_MAP[$num]:-}" ]; then
                selected="${selected:+$selected,}${MODULE_MAP[$num]}"
            else
                printf "${CWARN}⚠ Unknown selection: %s${RST}\n" "$num" >&2
            fi
        done
        if [ -z "$selected" ]; then
            echo "❌ No valid module selected"
            exit 1
        fi
        MODULES="$selected"
        return 0
    fi

    # Otherwise treat as module names / patterns (comma or space separated)
    MODULES=$(echo "$choice" | tr ' ' ',')
}

# ---------------------------------------------------------------------------
# Args
# ---------------------------------------------------------------------------
DBNAME=""
LANGUAGE="fr_FR"
ALL_LANGS=false
EXPORT_ALL=false
EXPORT_POT=false
NO_RESTART=false
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
        --all)
            EXPORT_ALL=true
            shift
            ;;
        -a|--all-langs)
            ALL_LANGS=true
            shift
            ;;
        --pot)
            EXPORT_POT=true
            shift
            ;;
        --no-restart)
            NO_RESTART=true
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

[ -z "$DBNAME" ] && DBNAME="${SELECTED_DB}"
if [ -z "$DBNAME" ]; then
    echo "❌ No database specified and no SELECTED_DB in .env"
    echo "   Usage: translation -d <database> [MODULE]"
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

if [ -z "$MODULES" ] && [ "$EXPORT_ALL" != true ]; then
    if [ -t 0 ]; then
        prompt_select_modules
    else
        echo "❌ No module specified (non-interactive shell)"
        echo "   Usage: translation MODULE[,MODULE2,...]   or   translation --all"
        exit 1
    fi
fi

if [ "$EXPORT_ALL" = true ]; then
    MODULES=$(extra_addon_modules_csv)
    if [ -z "$MODULES" ]; then
        echo "❌ No modules found under /mnt/extra-addons"
        echo "   (Odoo core and enterprise are excluded)"
        exit 1
    fi
fi

if [ "$EXPORT_ALL" != true ]; then
    MODULES=$(expand_modules "$MODULES")
    # Keep only modules that live under /mnt/extra-addons
    local_extra=$(list_extra_addon_modules)
    filtered=""
    IFS=',' read -ra _mods <<< "$MODULES"
    for m in "${_mods[@]}"; do
        m=$(echo "$m" | xargs)
        [ -z "$m" ] && continue
        if echo "$local_extra" | grep -qxF "$m"; then
            filtered="${filtered:+$filtered,}$m"
        else
            printf "${CWARN}⚠ Skipping '%s' (not under /mnt/extra-addons)${RST}\n" "$m" >&2
        fi
    done
    MODULES="$filtered"
fi
[ -z "$MODULES" ] && { echo "❌ No matching modules found under /mnt/extra-addons"; exit 1; }

ADDON_PATHS=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)
[ -z "$ADDON_PATHS" ] && { echo "❌ Could not resolve addons paths"; exit 1; }

echo ""
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
printf "${CPRIMARY}  TRANSLATION EXPORT${RST}  (${DBNAME}) — overwrite i18n/*.po\n"
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
echo ""

FAILED=0
IFS=',' read -ra MODULE_LIST <<< "$MODULES"
# Trim empties into clean array
MODULES_CLEAN=()
for module in "${MODULE_LIST[@]}"; do
    module=$(echo "$module" | xargs)
    [ -z "$module" ] && continue
    MODULES_CLEAN+=("$module")
done

# Odoo i18n export skips modules that are not in state 'installed'
# (e.g. to upgrade / to install). Fail early with a clear message.
NOT_INSTALLED=""
for module in "${MODULES_CLEAN[@]}"; do
    st=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" -tAc \
        "SELECT state FROM ir_module_module WHERE name='${module}' LIMIT 1;" 2>/dev/null | xargs)
    if [ -z "$st" ]; then
        NOT_INSTALLED="${NOT_INSTALLED}  - ${module} (not in database)\n"
    elif [ "$st" != "installed" ]; then
        NOT_INSTALLED="${NOT_INSTALLED}  - ${module} (state: ${st})\n"
    fi
done
if [ -n "$NOT_INSTALLED" ]; then
    printf "${CERROR}❌ Refusing to export: module(s) not fully installed:${RST}\n"
    printf "%b" "$NOT_INSTALLED"
    echo "   Run: u <module>   then retry translation"
    exit 1
fi

if supports_i18n_cli; then
    LANGS_CSV=""
    if [ "$ALL_LANGS" = true ]; then
        LANGS_CSV=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" -tAc \
            "SELECT code FROM res_lang WHERE active ORDER BY code;" 2>/dev/null | sed '/^$/d' | paste -sd, -)
        if [ -z "$LANGS_CSV" ]; then
            printf "${CERROR}❌ No active languages found in database${RST}\n"
            FAILED=1
        fi
    else
        LANGS_CSV="$LANGUAGE"
    fi
    if [ "$EXPORT_POT" = true ]; then
        LANGS_CSV="${LANGS_CSV:+$LANGS_CSV,}pot"
    fi

    if [ "$FAILED" -eq 0 ]; then
        export_modules_cli "$LANGS_CSV" "${MODULES_CLEAN[@]}" || FAILED=1
    fi
else
    # Legacy path: one module × one language at a time
    for module in "${MODULES_CLEAN[@]}"; do
        if [ "$EXPORT_POT" = true ]; then
            export_module_lang_legacy "$module" "" "pot" || FAILED=$((FAILED + 1))
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
                export_module_lang_legacy "$module" "$lang" "po" || FAILED=$((FAILED + 1))
            done <<< "$LANGS"
        else
            export_module_lang_legacy "$module" "$LANGUAGE" "po" || FAILED=$((FAILED + 1))
        fi
    done
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
    printf "${CERROR}❌ Translation export failed${RST}\n"
    exit 1
fi

printf "${CSUCCESS}✓ Translation export completed (%d module(s)) — po files replaced${RST}\n" "${#MODULES_CLEAN[@]}"
echo ""
