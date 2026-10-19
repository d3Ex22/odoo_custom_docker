#!/bin/bash
# ============================================================================
# translation - Fresh-export translation files for Odoo module(s)
# ============================================================================
# Usage: translation [-h|--help] [-d DATABASE] [-l LANGUAGE] [MODULE[,MODULE2,...]]
#        translation --all
#        translation          # interactive module picker
#
# Replaces i18n/fr.po (or other language file) in each selected module with a
# freshly extracted export from the database / source.
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

show_help() {
    h_name "translation" "Re-export the i18n/*.po files of your modules"
    h_sec "USAGE"
    h_use "translation [options] MODULE[,MODULE2,...]"
    h_use "translation --all"
    h_use "translation                        interactive picker"
    h_sec "ARGUMENTS"
    h_opt "MODULE" "Comma-separated names; patterns allowed: my_*, sale_[a-m]*"
    h_text "Only modules under your addons (ADDONS_PATH) are exported, never odoo/enterprise."
    h_sec "OPTIONS"
    h_opt "-d, --database DB" "Database (default: SELECTED_DB, asked when empty)"
    h_opt "-l, --language LANG" "Language code (default: fr_FR → i18n/fr.po)"
    h_opt "-L, --all-langs" "Every active language of the database"
    h_opt "--pot" "Also export the i18n/<module>.pot template"
    h_opt "-a, --all" "Every module of your addons"
    h_sec "DESCRIPTION"
    h_text "Overwrites i18n/<lang>.po in place with a fresh export. Odoo 19+ uses"
    h_text "'odoo i18n export'; older versions use --i18n-export. The running"
    h_text "Odoo is not stopped. Modules must be installed (state 'installed')."
    h_sec "EXAMPLES"
    h_ex "translation my_module" ""
    h_ex "translation my_*" ""
    h_ex "translation --pot -l en_US my_module" ""
    h_ex "translation --all" "Everything"
    h_global
    h_end
}

# fr_FR → fr: the .po file name, and the code the Odoo 19 CLI prefers for -l.
lang_short() { echo "${1%%_*}"; }
lang_to_po_filename() { echo "$(lang_short "$1").po"; }

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
        ui_err "Module '$module' not found in addons paths"
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

    ui_step "$module → i18n/$output_file ($lang_arg)"

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
        ui_err "Export failed for $module"
        echo "$log" | sed 's/^/    /' >&2
        return 1
    fi

    if ! docker exec "$ODOO_CONTAINER" test -s "$output_path"; then
        ui_err "Output file missing or empty: $output_path"
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
        lang_args+=("$(lang_short "$lang")")
    done

    if [ "${#modules[@]}" -eq 0 ] || [ "${#lang_args[@]}" -eq 0 ]; then
        ui_err "Internal error: no modules or languages for i18n export"
        return 1
    fi

    # i18n/ must exist; existing .po files are overwritten in place by Odoo.
    local module module_path targets=""
    for module in "${modules[@]}"; do
        module_path=$(find_module_path "$module" "$ADDON_PATHS")
        if [ -z "$module_path" ]; then
            ui_err "Module '$module' not found in addons paths"
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
        ui_step "$module → i18n/$targets"
    done

    local log rc
    # -l is always given (Odoo 19 defaults to 'pot' without it) and comes after
    # the modules (nargs='+' would swallow them). Runs alongside the server.
    log=$(docker exec "$ODOO_CONTAINER" odoo \
        i18n export \
        -c /etc/odoo/odoo.conf \
        -d "$DBNAME" \
        "${modules[@]}" \
        -l "${lang_args[@]}" \
        2>&1)
    rc=$?

    if [ "$rc" -ne 0 ]; then
        ui_err "odoo i18n export failed"
        echo "$log" | sed 's/^/    /' >&2
        return 1
    fi

    # Every expected file must exist (an empty .po is fine: metadata-only modules).
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
                ui_err "Missing: $output_path"
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
        die "No module found in your addons (/mnt/extra-addons)"
    fi

    local -a modules=()
    IFS=',' read -ra modules <<< "$modules_csv"

    ui_section "Select modules to export (your addons only)"
    printf "  ${CPRIMARY}%2s.${RST} %s\n" "0" "all"

    local i=1 m
    local -A MODULE_MAP
    for m in "${modules[@]}"; do
        m=$(echo "$m" | xargs)
        [ -z "$m" ] && continue
        printf "  ${CPRIMARY}%2d.${RST} %s\n" "$i" "$m"
        MODULE_MAP[$i]="$m"
        i=$((i + 1))
    done

    echo ""
    printf "${CWARN}?${RST} Select ${CMUTED}(0=all / 1,2,3 / names / patterns) [all]${RST} "
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
                ui_warn "Unknown selection: $num" >&2
            fi
        done
        if [ -z "$selected" ]; then
            die "No valid module selected"
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
MODULES=""

parse_global_flags "$@"
set -- "${ARGS[@]}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -d|--database) DBNAME="${2:-}"; [ -z "$DBNAME" ] && die "-d needs a database name"; shift 2 ;;
        -l|--language) LANGUAGE="${2:-}"; [ -z "$LANGUAGE" ] && die "-l needs a language code"; shift 2 ;;
        -a|--all) EXPORT_ALL=true; shift ;;
        -L|--all-langs) ALL_LANGS=true; shift ;;
        --pot) EXPORT_POT=true; shift ;;
        -*) die "Unknown option: $1" "See: translation --help" ;;
        *) MODULES="${MODULES:+$MODULES,}$1"; shift ;;
    esac
done

require_odoo_container
require_db_container
open_pane
[ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"
[ -z "$DBNAME" ] && { pick_db "Which database?" || exit 1; DBNAME="$PICKED"; echo; }
db_exists "$DBNAME" || die "Database '$DBNAME' does not exist" "db list to see the databases"

if [ -z "$MODULES" ] && [ "$EXPORT_ALL" != true ]; then
    [ -t 0 ] || die "No module given and no terminal for the picker" "Usage: translation MODULE[,MODULE2,...]  or  translation --all"
    prompt_select_modules
fi

if [ "$EXPORT_ALL" = true ]; then
    MODULES=$(extra_addon_modules_csv)
    [ -z "$MODULES" ] && die "No module found in your addons (/mnt/extra-addons)"
fi

if [ "$EXPORT_ALL" != true ]; then
    refresh_modules_cache "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)"
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
            ui_warn "Skipping '$m' (not in your addons)" >&2
        fi
    done
    MODULES="$filtered"
fi
[ -z "$MODULES" ] && die "No matching module in your addons (/mnt/extra-addons)"

ADDON_PATHS=$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)
[ -z "$ADDON_PATHS" ] && die "Could not resolve addons paths"

ui_title "Translation export" "$DBNAME — overwrite i18n/*.po"

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
    ui_err "Refusing to export: module(s) not fully installed"
    printf "%b" "$NOT_INSTALLED"
    ui_note "u <module> then retry"
    exit 1
fi

# The language must be active in the database, otherwise Odoo exports nothing.
if [ "$ALL_LANGS" != true ]; then
    lang_active=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" -tAc \
        "SELECT 1 FROM res_lang WHERE active AND code='${LANGUAGE}' LIMIT 1;" 2>/dev/null | xargs)
    if [ "$lang_active" != "1" ]; then
        ui_warn "Language '$LANGUAGE' is not active in '$DBNAME'"
        confirm "Load it now? (odoo --load-language, Odoo is not stopped)" || die "Export cancelled" "Activate the language in Odoo (Settings › Languages) or pass -l <code>"
        ui_step "Loading language $LANGUAGE..."
        docker exec "$ODOO_CONTAINER" odoo -c /etc/odoo/odoo.conf -d "$DBNAME" --no-http --stop-after-init \
            --load-language="$LANGUAGE" --log-level=error >/dev/null 2>&1 \
            || die "Could not load language '$LANGUAGE'"
        ui_ok "Language $LANGUAGE loaded"
    fi
fi

if supports_i18n_cli; then
    LANGS_CSV=""
    if [ "$ALL_LANGS" = true ]; then
        LANGS_CSV=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" -tAc \
            "SELECT code FROM res_lang WHERE active ORDER BY code;" 2>/dev/null | sed '/^$/d' | paste -sd, -)
        if [ -z "$LANGS_CSV" ]; then
            ui_err "No active language found in the database"
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
                ui_err "No active language found in the database"
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
[ "$FAILED" -gt 0 ] && die "Translation export failed"
ui_done "Translation export completed — ${#MODULES_CLEAN[@]} module(s), po files replaced"
