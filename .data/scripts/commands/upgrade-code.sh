#!/bin/bash
# ============================================================================
# upgrade-code - Migrate module code using OCA + Odoo official + custom scripts
# ============================================================================
# Usage: upgrade-code --from VERSION [--to VERSION] [--module A,B] [--dry-run] [-f] [-a]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

ADDONS_ROOT="/mnt/extra-addons"
CUSTOM_DIR="/opt/migration_scripts"   # .data/migration_scripts, mounted read-only
# Where Odoo ships its upgrade_code scripts (the mounted source first, then the image)
ODOO_UPGRADE_DIRS=(/mnt/odoo-src/odoo/upgrade_code /opt/odoo/odoo/upgrade_code "/opt/venv/lib/python*/site-packages/odoo/upgrade_code")

show_help() {
    h_name "upgrade-code" "Migrate module source code to a newer Odoo version"
    h_sec "USAGE"
    h_use "upgrade-code --from VERSION [options]"
    h_sec "OPTIONS"
    h_opt "--from VERSION" "Source Odoo version (required, e.g. 16.0)"
    h_opt "--to VERSION" "Target version (default: ODOO_VERSION)"
    h_opt "--module A,B" "Only these modules (comma-separated)"
    h_opt "--dry-run" "Show what would change, modify nothing"
    h_opt "-f, --force" "Run every tool, no questions"
    h_opt "-a, --all-files" "All addon paths and modules, no picker"
    h_sec "TOOLS"
    h_opt "OCA odoo-module-migrator" "Imports, manifest keys, version bump"
    h_opt "odoo upgrade_code" "Official scripts shipped with Odoo (19.0+)"
    h_opt ".data/migration_scripts" "Your own upgrade_code scripts"
    h_sec "DESCRIPTION"
    h_text "Requires the odoo container to run Odoo 19.0+. Manifests are bumped"
    h_text "to <to>.0.0 and pre-commit can be run at the end. Some changes stay"
    h_text "manual (attrs/states, kanban templates...) — a reminder is printed."
    h_sec "EXAMPLES"
    h_ex "upgrade-code --from 16.0" ""
    h_ex "upgrade-code --from 17.0 --module my_module --dry-run" ""
    h_ex "upgrade-code --from 16.0 -f -a" "Everything"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
FROM_VERSION=""
TO_VERSION="${ODOO_VERSION:-19.0}"
MODULES=""
DRY_RUN=false
FORCE=false
ALL_FILES=false
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        --from) FROM_VERSION="${2:-}"; [ -z "$FROM_VERSION" ] && die "--from needs a version"; shift 2 ;;
        --to) TO_VERSION="${2:-}"; [ -z "$TO_VERSION" ] && die "--to needs a version"; shift 2 ;;
        --module) MODULES="${2:-}"; [ -z "$MODULES" ] && die "--module needs a name"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        -a|--all-files) ALL_FILES=true; shift ;;
        *) die "Unknown option: $1" "See: upgrade-code --help" ;;
    esac
done
[ -z "$FROM_VERSION" ] && die "--from VERSION is required" "Example: upgrade-code --from 16.0"
[[ "$FROM_VERSION" =~ ^[0-9]+\.[0-9]+$ ]] || die "Invalid --from version: $FROM_VERSION" "Expected e.g. 16.0"
[[ "${ODOO_VERSION:-}" =~ ^(19|[2-9][0-9])\. ]] || die "upgrade-code needs Odoo 19.0+ in the odoo container (ODOO_VERSION=${ODOO_VERSION:-?})"
$FORCE && ASSUME_YES=true
DRY_FLAG=""; $DRY_RUN && DRY_FLAG="--dry-run"

require_odoo_container
docker exec "$ODOO_CONTAINER" test -d "$ADDONS_ROOT" 2>/dev/null || die "No addons mounted in the Odoo container"
open_pane

in_odoo() { docker exec "$ODOO_CONTAINER" "$@"; }
# Scripts of Odoo's upgrade_code folders (names without .py), one per line
odoo_scripts() {
    in_odoo bash -c 'shopt -s nullglob; for d in '"${ODOO_UPGRADE_DIRS[*]}"'; do for f in "$d"/[!_]*.py; do basename "$f" .py; done; done | sort -u' 2>/dev/null
}
# First writable upgrade_code folder: custom scripts are copied there to run
odoo_upgrade_dir() {
    in_odoo bash -c 'shopt -s nullglob; for d in '"${ODOO_UPGRADE_DIRS[*]}"'; do [ -d "$d" ] && [ -w "$d" ] && { echo "$d"; exit 0; }; done; exit 1' 2>/dev/null
}
# Run 'odoo upgrade_code ARGS' once per selected module (or once for everything),
# print the changed addon files; returns 0 when something changed
run_upgrade_code() {
    local out changed=1 glob
    local -a globs=()
    [ -n "$MODULES" ] && for m in ${MODULES//,/ }; do globs+=("--glob" "${m}/**/*"); done
    [ ${#globs[@]} -eq 0 ] && globs=("--glob" "**/*")
    for ((i = 0; i < ${#globs[@]}; i += 2)); do
        out=$(in_odoo odoo upgrade_code "$@" --addons-path "$(IFS=,; echo "${SELECTED_PATHS[*]}")" "${globs[i]}" "${globs[i+1]}" $DRY_FLAG 2>&1) || { echo "$out" | tail -5 | sed 's/^/    /' >&2; return 2; }
        glob=$(echo "$out" | grep "^${ADDONS_ROOT}" || true)
        [ -n "$glob" ] && { echo "$glob" | sed "s|^${ADDONS_ROOT}/|    |"; changed=0; }
    done
    return $changed
}

# ============================================================================
# Addon paths and modules
# ============================================================================
mapfile -t DETECTED_PATHS < <(in_odoo /usr/local/bin/generate_addons_path.sh 2>/dev/null | tr ',' '\n' | grep -v '^$')
SELECTED_PATHS=("$ADDONS_ROOT")
if [ ${#DETECTED_PATHS[@]} -eq 1 ] || $ALL_FILES; then
    [ ${#DETECTED_PATHS[@]} -gt 0 ] && SELECTED_PATHS=("${DETECTED_PATHS[@]}")
elif [ ${#DETECTED_PATHS[@]} -gt 1 ]; then
    ui_section "Select addon paths (${#DETECTED_PATHS[@]} detected)"
    pick_many "Select paths" "${DETECTED_PATHS[@]}" || exit 1
    SELECTED_PATHS=("${PICKED_ITEMS[@]}")
    echo
fi
if [ -z "$MODULES" ] && ! $ALL_FILES; then
    mapfile -t FOUND < <(in_odoo find "${SELECTED_PATHS[@]}" -maxdepth 2 -name "__manifest__.py" -type f 2>/dev/null | xargs -r -n1 dirname | sort -u)
    if [ ${#FOUND[@]} -gt 0 ]; then
        ui_section "Select modules to migrate (${#FOUND[@]} available)"
        pick_many "Select modules" "${FOUND[@]#${ADDONS_ROOT}/}" || exit 1
        [ ${#PICKED_ITEMS[@]} -lt ${#FOUND[@]} ] && MODULES=$(printf '%s\n' "${PICKED_ITEMS[@]##*/}" | paste -sd, -)
        echo
    fi
fi

if $DRY_RUN; then ui_title "Upgrade code" "DRY RUN — nothing is modified"; else ui_title "Upgrade code"; fi
ui_kv "From → to" "${FROM_VERSION} → ${TO_VERSION}"
[ -n "$MODULES" ] && ui_kv "Module(s)" "${MODULES//,/, }"
[ "${SELECTED_PATHS[*]}" != "$ADDONS_ROOT" ] && ui_kv "Paths" "${SELECTED_PATHS[*]#${ADDONS_ROOT}/}"
echo

# ============================================================================
# Tools
# ============================================================================
USE_OCA=false; USE_ODOO=false
ODOO_SCRIPTS=()     # empty with USE_ODOO=true = every script (--from/--to)
CUSTOM_SCRIPTS=()
mapfile -t CUSTOM_AVAILABLE < <(in_odoo find "$CUSTOM_DIR" -maxdepth 1 -name "*.py" -type f 2>/dev/null | sort)
if $FORCE; then
    USE_OCA=true; USE_ODOO=true
    CUSTOM_SCRIPTS=("${CUSTOM_AVAILABLE[@]}")
else
    [ -t 0 ] || die "The tool selection needs a terminal" "Use: -f (run every tool)"
    ui_section "Select tools to run"
    printf "  ${CPRIMARY}1. OCA odoo-module-migrator${RST}  ${CMUTED}imports, manifest keys, version bump${RST}\n"
    confirm "Use OCA?" && USE_OCA=true
    echo

    printf "  ${CPRIMARY}2. Odoo official upgrade_code${RST}\n"
    mapfile -t ODOO_AVAILABLE < <(odoo_scripts)
    if [ ${#ODOO_AVAILABLE[@]} -gt 0 ]; then
        if confirm "Run the official scripts?"; then
            USE_ODOO=true
            pick_many "Select scripts" "${ODOO_AVAILABLE[@]}" || exit 1
            [ ${#PICKED_ITEMS[@]} -lt ${#ODOO_AVAILABLE[@]} ] && ODOO_SCRIPTS=("${PICKED_ITEMS[@]}")
        fi
    else
        ui_note "no script available"
    fi
    echo

    printf "  ${CPRIMARY}3. Custom migration scripts${RST}  ${CMUTED}.data/migration_scripts${RST}\n"
    if [ ${#CUSTOM_AVAILABLE[@]} -gt 0 ]; then
        if confirm "Run your custom scripts?"; then
            pick_many "Select scripts" "${CUSTOM_AVAILABLE[@]##*/}" || exit 1
            CUSTOM_SCRIPTS=("${PICKED_ITEMS[@]/#/${CUSTOM_DIR}/}")
        fi
    else
        ui_note "no custom script in .data/migration_scripts"
    fi
    echo
fi

OCA_DONE=false; ODOO_DONE=false; CUSTOM_DONE=false; VERSION_DONE=false

# ============================================================================
# 1. OCA odoo-module-migrator
# ============================================================================
if $USE_OCA; then
    ui_section "OCA odoo-module-migrator"
    in_odoo pip install --upgrade odoo-module-migrator --quiet 2>/dev/null
    OCA_MAX=$(in_odoo odoo-module-migrate --help 2>&1 | grep -oP '\d+\.\d+' | sort -V | tail -1)
    OCA_TARGET="$TO_VERSION"
    [ -n "$OCA_MAX" ] && [[ "$TO_VERSION" > "$OCA_MAX" ]] && OCA_TARGET="$OCA_MAX"
    ui_kv "Target" "$OCA_TARGET"; echo
    for OCA_PATH in "${SELECTED_PATHS[@]}"; do   # one directory per run
        ui_step "${OCA_PATH#${ADDONS_ROOT}/}"
        OCA_CMD=(odoo-module-migrate --directory "$OCA_PATH" --init-version-name "$FROM_VERSION" --target-version-name "$OCA_TARGET" --no-commit)
        [ -n "$MODULES" ] && OCA_CMD+=(--modules "$MODULES")
        if $DRY_RUN; then ui_note "[dry-run] ${OCA_CMD[*]}"
        else in_odoo "${OCA_CMD[@]}" 2>&1 | sed 's/^/    /'; fi
        echo
    done
    ui_ok "OCA completed"
    $DRY_RUN || OCA_DONE=true
    echo
fi

# ============================================================================
# 2. Odoo official upgrade_code
# ============================================================================
if $USE_ODOO; then
    ui_section "Odoo official upgrade_code"
    if [ ${#ODOO_SCRIPTS[@]} -gt 0 ]; then
        for script in "${ODOO_SCRIPTS[@]}"; do
            ui_step "$script"
            if run_upgrade_code --script "$script"; then $DRY_RUN || ODOO_DONE=true; else ui_note "no change"; fi
        done
    else
        ODOO_FROM="$FROM_VERSION"
        [[ "$FROM_VERSION" < "17.5" ]] && ODOO_FROM="17.5"   # oldest version the scripts know
        if run_upgrade_code --from "$ODOO_FROM" --to "$TO_VERSION"; then $DRY_RUN || ODOO_DONE=true; else ui_note "no change needed"; fi
    fi
    echo
fi

# ============================================================================
# 3. Custom migration scripts
# ============================================================================
if [ ${#CUSTOM_SCRIPTS[@]} -gt 0 ]; then
    ui_section "Custom migration scripts"
    UPGRADE_DIR=$(odoo_upgrade_dir) || die "No writable upgrade_code folder in the odoo container" "Custom scripts run from Odoo's own folder (/opt/odoo/odoo/upgrade_code)"
    for script in "${CUSTOM_SCRIPTS[@]}"; do
        name=$(basename "$script")
        ui_step "$name"
        in_odoo cp "$script" "$UPGRADE_DIR/$name" || die "Cannot copy $name to $UPGRADE_DIR"
        if run_upgrade_code --script "${name%.py}"; then $DRY_RUN || CUSTOM_DONE=true; else ui_note "no change needed"; fi
        in_odoo rm -f "$UPGRADE_DIR/$name"
        echo
    done
fi

# ============================================================================
# 4. Manifest versions
# ============================================================================
if ! $DRY_RUN; then
    ui_section "Bumping manifest versions → ${TO_VERSION}.0.0"
    FIND_ARGS=(-name "__manifest__.py" -type f)
    if [ -n "$MODULES" ]; then
        FIND_ARGS=("(" -false); for m in ${MODULES//,/ }; do FIND_ARGS+=(-o -path "*/$m/__manifest__.py"); done; FIND_ARGS+=(")" -type f)
    fi
    BUMP_COUNT=0
    while IFS= read -r manifest; do
        [ -z "$manifest" ] && continue
        in_odoo sed -i "s/['\"]version['\"]\s*:\s*['\"][^'\"]*['\"]/\"version\": \"${TO_VERSION}.0.0\"/" "$manifest" 2>/dev/null
        ui_ok "$(basename "$(dirname "$manifest")")"
        ((BUMP_COUNT++))
    done < <(in_odoo find "${SELECTED_PATHS[@]}" "${FIND_ARGS[@]}" 2>/dev/null)
    [ $BUMP_COUNT -gt 0 ] && VERSION_DONE=true
    echo; ui_note "$BUMP_COUNT manifest(s) updated"; echo
fi

# ============================================================================
# Summary
# ============================================================================
ui_section "Summary"
if $DRY_RUN; then
    ui_warn "Dry run — no change applied"
else
    $OCA_DONE && ui_ok "OCA"
    $ODOO_DONE && ui_ok "Odoo upgrade_code"
    $CUSTOM_DONE && ui_ok "Custom scripts"
    $VERSION_DONE && ui_ok "Manifest versions → ${TO_VERSION}.0.0"
fi
echo
ui_warn "Still manual:"
ui_note "attrs= → invisible= / readonly= / required=   (17.0+)"
ui_note "states= → invisible expression               (17.0+)"
ui_note "kanban-box → card templates                   (18.0+)"
echo

# ============================================================================
# 5. Pre-commit (optional)
# ============================================================================
if ! $DRY_RUN && { $FORCE || { [ -t 0 ] && confirm "Run pre-commit on the migrated files?"; }; }; then
    ui_section "Running pre-commit"
    FILES_TO_PROCESS=$(in_odoo find "${SELECTED_PATHS[@]}" -type f \( -name "*.py" -o -name "*.xml" \) 2>/dev/null | tr '\n' ' ')
    if run_precommit "$ODOO_CONTAINER" "$FILES_TO_PROCESS"; then echo; ui_done "Pre-commit passed"
    else echo; ui_warn "Pre-commit reported issues — fixable ones were fixed in place"; fi
fi
