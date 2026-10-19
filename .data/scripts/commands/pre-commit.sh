#!/bin/bash
# ============================================================================
# pre-commit - Run pre-commit hooks on addon files
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

show_help() {
    h_name "pre-commit (pc)" "Run the pre-commit hooks on your addons"
    h_sec "USAGE"
    h_use "pc [FOLDER] [-a]"
    h_sec "ARGUMENTS"
    h_opt "FOLDER" "Addons sub-folder to lint (e.g. custom-addons); interactive otherwise"
    h_sec "OPTIONS"
    h_opt "-a, --all" "Every module of the selected folder(s), no module picker"
    h_sec "DESCRIPTION"
    h_text "Hooks come from .config/.pre-commit-config.yaml (kept in sync as"
    h_text "addons/.pre-commit-config.yaml) and run inside the Odoo"
    h_text "container on *.py *.xml *.js *.css files. Files are modified in"
    h_text "place (black, isort, prettier...), so commit or stash first."
    h_sec "EXAMPLES"
    h_ex "pc" "Pick folder(s) then module(s)"
    h_ex "pc custom-addons" "Pick modules of custom-addons"
    h_ex "pc -a" "Everything"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
ALL_MODULES=false
TARGET_FOLDER=""
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -a|--all) ALL_MODULES=true; shift ;;
        -*) die "Unknown option: $1" "See: pre-commit --help" ;;
        *) [ -n "$TARGET_FOLDER" ] && die "Only one folder can be given"; TARGET_FOLDER="$1"; shift ;;
    esac
done

require_odoo_container
docker exec "$ODOO_CONTAINER" test -d /mnt/extra-addons 2>/dev/null || die "No addons mounted in the Odoo container"
open_pane

ui_title "Pre-commit" "hooks: .config/.pre-commit-config.yaml"

# --- Addon paths (as generate_addons_path.sh sees them) ---
mapfile -t DETECTED_PATHS < <(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null | tr ',' '\n' | grep -v '^$')
SELECTED_PATHS=("/mnt/extra-addons")
if [ -n "$TARGET_FOLDER" ]; then
    MATCHED=""
    for p in "${DETECTED_PATHS[@]}"; do [[ "$p" == */"$TARGET_FOLDER" ]] && { MATCHED="$p"; break; }; done
    if [ -n "$MATCHED" ]; then
        SELECTED_PATHS=("$MATCHED"); ui_ok "Folder: $TARGET_FOLDER"
    else
        ui_warn "Folder '$TARGET_FOLDER' not found — interactive selection"; TARGET_FOLDER=""
    fi
fi
if [ -z "$TARGET_FOLDER" ] && [ ${#DETECTED_PATHS[@]} -gt 1 ]; then
    ui_section "Select addon paths (${#DETECTED_PATHS[@]} detected)"
    pick_many "Select paths" "${DETECTED_PATHS[@]}" || exit 1
    SELECTED_PATHS=("${PICKED_ITEMS[@]}")
    echo
elif [ -z "$TARGET_FOLDER" ] && [ ${#DETECTED_PATHS[@]} -eq 1 ]; then
    SELECTED_PATHS=("${DETECTED_PATHS[@]}")
fi

# --- Modules of the selected paths ---
mapfile -t MODULES < <(docker exec "$ODOO_CONTAINER" find "${SELECTED_PATHS[@]}" -maxdepth 2 -name "__manifest__.py" -type f 2>/dev/null | xargs -r -n1 dirname | sort -u)
if [ ${#MODULES[@]} -gt 0 ]; then
    if $ALL_MODULES; then
        ui_ok "All ${#MODULES[@]} modules"
    else
        ui_section "Select modules (${#MODULES[@]} available)"
        pick_many "Select modules" "${MODULES[@]#/mnt/extra-addons/}" || exit 1
        MODULES=("${PICKED_ITEMS[@]/#//mnt/extra-addons/}")
        echo
    fi
    SELECTED_PATHS=("${MODULES[@]}")
fi

# ============================================================================
# RUN PRE-COMMIT
# ============================================================================
ui_section "Running pre-commit"

[ ${#SELECTED_PATHS[@]} -eq 0 ] && die "Nothing selected"
for path in "${SELECTED_PATHS[@]}"; do ui_item "${path#/mnt/extra-addons/}"; done
FILES_TO_PROCESS=$(docker exec "$ODOO_CONTAINER" find "${SELECTED_PATHS[@]}" -type f \( -name "*.py" -o -name "*.xml" -o -name "*.js" -o -name "*.css" \) 2>/dev/null | tr '\n' ' ')
echo

if run_precommit "$ODOO_CONTAINER" "$FILES_TO_PROCESS"; then
    echo; ui_done "Pre-commit passed"
else
    echo; ui_warn "Pre-commit reported issues $(fmt_duration "$SECONDS")"
    ui_note "Fixable ones were fixed in place: review the diff, then run pc again"
    exit 1
fi
