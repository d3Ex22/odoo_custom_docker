#!/bin/bash
# ============================================================================
# upgrade-code - Migrate module code using OCA + Odoo official + custom scripts
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

_odoo_upgrade_code_dirs=(
    /mnt/odoo-src/odoo/upgrade_code
    /opt/odoo/odoo/upgrade_code
    /opt/venv/lib/python*/site-packages/odoo/upgrade_code
    /opt/pyenv/versions/*/lib/python*/site-packages/odoo/upgrade_code
)

list_odoo_upgrade_scripts() {
    local container="$1"
    local dirs_shell
    dirs_shell=$(printf ' "%s"' "${_odoo_upgrade_code_dirs[@]}")
    docker exec "$container" bash -c "
        shopt -s nullglob
        dirs=(${dirs_shell})
        declare -A seen=()
        for dir in \"\${dirs[@]}\"; do
            [ -d \"\$dir\" ] || continue
            for f in \"\$dir\"/*.py; do
                base=\$(basename \"\$f\" .py)
                [[ \"\$base\" == __* ]] && continue
                seen[\$base]=1
            done
        done
        printf '%s\n' \"\${!seen[@]}\" | sort
    " 2>/dev/null
}

resolve_odoo_upgrade_code_dir() {
    local container="$1"
    local dirs_shell
    dirs_shell=$(printf ' "%s"' "${_odoo_upgrade_code_dirs[@]}")
    docker exec "$container" bash -c "
        shopt -s nullglob
        dirs=(${dirs_shell})
        for dir in \"\${dirs[@]}\"; do
            [ -d \"\$dir\" ] && echo \"\$dir\" && exit 0
        done
        python3 -c \"import odoo; from pathlib import Path; p=Path(odoo.__path__[0])/'upgrade_code'; print(p if p.is_dir() else '')\" 2>/dev/null
    " 2>/dev/null | head -1
}

show_help() {
    echo ""
    echo "upgrade-code - Migrate module code"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       upgrade-code --from VERSION [OPTIONS]"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       --from VERSION    Source Odoo version (required)"
    echo "       --to VERSION      Target version (default: 19.0)"
    echo "       --module NAME     Migrate specific module(s)"
    echo "       --dry-run         Preview changes without applying"
    echo "       -f, --force       Run all tools without confirmation"
    echo "       -a, --all-files   Migrate all paths/modules without selection"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       upgrade-code --from 16.0"
    echo "       upgrade-code --from 16.0 --force"
    echo "       upgrade-code --from 18.0 --module my_module"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

ODOO_VER="${ODOO_VERSION}"
if [[ ! "$ODOO_VER" =~ ^19\. ]]; then
    printf "${CERROR}❌ upgrade-code requires Odoo 19.0+${RST}\n"
    exit 1
fi

FROM_VERSION=""
TO_VERSION="19.0"
MODULE=""
DRY_RUN=false
FORCE=false
ALL_FILES=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --from) FROM_VERSION="$2"; shift 2 ;;
        --to) TO_VERSION="$2"; shift 2 ;;
        --module) MODULE="$2"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        -a|--all-files) ALL_FILES=true; shift ;;
        *) printf "${CERROR}❌ Unknown option: $1${RST}\n"; show_help; exit 1 ;;
    esac
done

if [ -z "$FROM_VERSION" ]; then
    show_help
    exit 0
fi

CONTAINER="$ODOO_CONTAINER"

if ! docker exec "$CONTAINER" test -d /mnt/extra-addons 2>/dev/null; then
    printf "${CERROR}❌ Odoo container not running${RST}\n"
    exit 1
fi

DRY_FLAG=""
[ "$DRY_RUN" = true ] && DRY_FLAG="--dry-run"

# ============================================================================
# PATH & MODULE DETECTION
# ============================================================================
# Use generate_addons_path.sh logic to detect addon paths
DETECTED_PATHS=$(docker exec "$CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null | tr ',' '\n' | grep -v "^$")
SELECTED_PATHS="/mnt/extra-addons"

# Check if we have multiple paths (subfolders structure)
PATH_COUNT=$(echo "$DETECTED_PATHS" | grep -c "/" || echo "0")

if [ "$PATH_COUNT" -gt 1 ] && [ "$ALL_FILES" = false ]; then
    echo ""
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CPRIMARY}  Select addon paths ($PATH_COUNT detected)${RST}\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

    i=1
    declare -A PATH_MAP
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        path_name=$(basename "$path")
        printf "    ${CSUCCESS}%2d.${RST} %s\n" "$i" "$path_name"
        PATH_MAP[$i]="$path"
        ((i++))
    done <<< "$DETECTED_PATHS"

    echo ""
    printf "  Select paths (1,2,3 / all) [all]: "
    read -r PATH_CHOICE

    if [ -n "$PATH_CHOICE" ] && [ "$PATH_CHOICE" != "all" ]; then
        SELECTED_PATHS=""
        IFS=',' read -ra NUMS <<< "$PATH_CHOICE"
        for num in "${NUMS[@]}"; do
            num=$(echo "$num" | tr -d ' ')
            [ -n "${PATH_MAP[$num]}" ] && SELECTED_PATHS="$SELECTED_PATHS ${PATH_MAP[$num]}"
        done
        SELECTED_PATHS=$(echo "$SELECTED_PATHS" | xargs)
    else
        SELECTED_PATHS=$(echo "$DETECTED_PATHS" | tr '\n' ' ' | xargs)
    fi
elif [ "$PATH_COUNT" -eq 1 ]; then
    SELECTED_PATHS="$DETECTED_PATHS"
fi

# ============================================================================
# MODULE SELECTION (if no --module provided)
# ============================================================================
if [ -z "$MODULE" ] && [ "$ALL_FILES" = false ]; then
    # Find all modules in selected paths
    ALL_MODULES=$(docker exec "$CONTAINER" find $SELECTED_PATHS -maxdepth 2 -name "__manifest__.py" -type f 2>/dev/null | xargs -I{} dirname {} | sort -u)
    MODULE_COUNT=$(echo "$ALL_MODULES" | grep -c "/" || echo "0")

    if [ "$MODULE_COUNT" -gt 0 ]; then
        echo ""
        printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
        printf "${CPRIMARY}  Select modules to migrate ($MODULE_COUNT available)${RST}\n"
        printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

        i=1
        declare -A MODULE_MAP
        declare -A MODULE_NAME_MAP
        while IFS= read -r mod_path; do
            [ -z "$mod_path" ] && continue
            mod_name=$(basename "$mod_path")
            # Show relative path from /mnt/extra-addons
            rel_path=${mod_path#/mnt/extra-addons/}
            printf "    ${CSUCCESS}%2d.${RST} %s\n" "$i" "$rel_path"
            MODULE_MAP[$i]="$mod_path"
            MODULE_NAME_MAP[$i]="$mod_name"
            ((i++))
        done <<< "$ALL_MODULES"

        echo ""
        printf "  Select modules (1,2,3 / all) [all]: "
        read -r MOD_CHOICE

        if [ -n "$MOD_CHOICE" ] && [ "$MOD_CHOICE" != "all" ]; then
            SELECTED_PATHS=""
            MODULE=""
            IFS=',' read -ra NUMS <<< "$MOD_CHOICE"
            for num in "${NUMS[@]}"; do
                num=$(echo "$num" | tr -d ' ')
                [ -n "${MODULE_MAP[$num]}" ] && SELECTED_PATHS="$SELECTED_PATHS ${MODULE_MAP[$num]}"
                [ -n "${MODULE_NAME_MAP[$num]}" ] && MODULE="$MODULE,${MODULE_NAME_MAP[$num]}"
            done
            SELECTED_PATHS=$(echo "$SELECTED_PATHS" | xargs)
            MODULE=$(echo "$MODULE" | sed 's/^,//')
        fi
    fi
fi

echo ""
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
[ "$DRY_RUN" = true ] && printf "${CPRIMARY}  UPGRADE CODE - DRY RUN${RST}\n" || printf "${CPRIMARY}  UPGRADE CODE${RST}\n"
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
echo ""
printf "  From: ${CWARN}$FROM_VERSION${RST} → To: ${CSUCCESS}$TO_VERSION${RST}\n"
[ -n "$MODULE" ] && printf "  Module(s): ${CWARN}$MODULE${RST}\n"
[ "$SELECTED_PATHS" != "/mnt/extra-addons" ] && printf "  Paths: ${CWARN}$SELECTED_PATHS${RST}\n"
echo ""

# ============================================================================
# TOOL SELECTION
# ============================================================================
USE_OCA=false
USE_ODOO=false
USE_CUSTOM=false
ODOO_SCRIPTS=()
CUSTOM_SCRIPTS=()

if [ "$FORCE" = true ]; then
    USE_OCA=true
    USE_ODOO=true
    USE_CUSTOM=true
    # Load all custom scripts
    CUSTOM_AVAILABLE=$(docker exec "$CONTAINER" find /opt/migration_scripts -maxdepth 1 -name "*.py" -type f 2>/dev/null | sort)
    while IFS= read -r script; do
        [ -n "$script" ] && CUSTOM_SCRIPTS+=("$script")
    done <<< "$CUSTOM_AVAILABLE"
else
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CPRIMARY}  Select tools to run${RST}\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

    # OCA
    printf "  ${CPRIMARY}1. OCA odoo-module-migrator${RST}\n"
    printf "     Imports, __openerp__→__manifest__, version bump\n"
    printf "     Use OCA? [Y/n]: "
    read -r OCA_CHOICE
    [[ -z "$OCA_CHOICE" || "$OCA_CHOICE" =~ ^[Yy] ]] && USE_OCA=true
    echo ""

    # Odoo official - list scripts
    printf "  ${CPRIMARY}2. Odoo official upgrade_code${RST}\n"
    ODOO_AVAILABLE=$(list_odoo_upgrade_scripts "$CONTAINER")

    if [ -n "$ODOO_AVAILABLE" ]; then
        printf "     Available scripts:\n"
        i=1
        declare -A ODOO_SCRIPT_MAP
        while IFS= read -r script; do
            [ -z "$script" ] && continue
            printf "       ${CSUCCESS}%2d.${RST} %s\n" "$i" "$script"
            ODOO_SCRIPT_MAP[$i]="$script"
            ((i++))
        done <<< "$ODOO_AVAILABLE"

        printf "     Select (1,2,3 / all / none) [all]: "
        read -r ODOO_CHOICE

        if [ -z "$ODOO_CHOICE" ] || [ "$ODOO_CHOICE" = "all" ]; then
            USE_ODOO=true
        elif [ "$ODOO_CHOICE" != "none" ]; then
            USE_ODOO=true
            IFS=',' read -ra NUMS <<< "$ODOO_CHOICE"
            for num in "${NUMS[@]}"; do
                num=$(echo "$num" | tr -d ' ')
                [ -n "${ODOO_SCRIPT_MAP[$num]}" ] && ODOO_SCRIPTS+=("${ODOO_SCRIPT_MAP[$num]}")
            done
        fi
    else
        printf "     ${CWARN}No scripts available${RST}\n"
    fi
    echo ""

    # Custom scripts
    printf "  ${CACCENT}3. Custom migration scripts${RST}\n"
    CUSTOM_AVAILABLE=$(docker exec "$CONTAINER" find /opt/migration_scripts -maxdepth 1 -name "*.py" -type f 2>/dev/null | sort)

    if [ -n "$CUSTOM_AVAILABLE" ]; then
        printf "     Available scripts:\n"
        i=1
        declare -A CUSTOM_SCRIPT_MAP
        while IFS= read -r script; do
            [ -z "$script" ] && continue
            script_name=$(basename "$script")
            desc=$(docker exec "$CONTAINER" grep -m1 '"""' "$script" 2>/dev/null | sed 's/.*"""\(.*\)""".*/\1/')
            [ -z "$desc" ] && desc="No description"
            printf "       ${CSUCCESS}%2d.${RST} %s\n" "$i" "$script_name"
            printf "           ${CWARN}%s${RST}\n" "$desc"
            CUSTOM_SCRIPT_MAP[$i]="$script"
            ((i++))
        done <<< "$CUSTOM_AVAILABLE"

        printf "     Select (1,2,3 / all / none) [all]: "
        read -r CUSTOM_CHOICE

        if [ -z "$CUSTOM_CHOICE" ] || [ "$CUSTOM_CHOICE" = "all" ]; then
            USE_CUSTOM=true
            while IFS= read -r script; do
                [ -n "$script" ] && CUSTOM_SCRIPTS+=("$script")
            done <<< "$CUSTOM_AVAILABLE"
        elif [ "$CUSTOM_CHOICE" != "none" ]; then
            USE_CUSTOM=true
            IFS=',' read -ra NUMS <<< "$CUSTOM_CHOICE"
            for num in "${NUMS[@]}"; do
                num=$(echo "$num" | tr -d ' ')
                [ -n "${CUSTOM_SCRIPT_MAP[$num]}" ] && CUSTOM_SCRIPTS+=("${CUSTOM_SCRIPT_MAP[$num]}")
            done
        fi
    else
        printf "     ${CWARN}No custom scripts found${RST}\n"
    fi
    echo ""
fi

OCA_DONE=false
ODOO_DONE=false
CUSTOM_DONE=false
VERSION_DONE=false

# ============================================================================
# 1. OCA odoo-module-migrator
# ============================================================================
if [ "$USE_OCA" = true ]; then
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CPRIMARY}  ▶ OCA odoo-module-migrator${RST}\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

    docker exec "$CONTAINER" pip install --upgrade odoo-module-migrator --quiet 2>/dev/null

    OCA_HELP=$(docker exec "$CONTAINER" odoo-module-migrate --help 2>&1)
    OCA_MAX=$(echo "$OCA_HELP" | grep -oP '\d+\.\d+' | sort -V | tail -1)
    [ -z "$OCA_MAX" ] && OCA_MAX="18.0"

    OCA_TARGET="$TO_VERSION"
    [[ "$TO_VERSION" > "$OCA_MAX" ]] && OCA_TARGET="$OCA_MAX"

    printf "  Target: $OCA_TARGET\n\n"

    # OCA needs to run per directory (doesn't support multiple paths)
    for OCA_PATH in $SELECTED_PATHS; do
        printf "  ${CPRIMARY}▶${RST} $(basename "$OCA_PATH")\n"

        OCA_CMD="odoo-module-migrate --directory $OCA_PATH"
        OCA_CMD="$OCA_CMD --init-version-name $FROM_VERSION"
        OCA_CMD="$OCA_CMD --target-version-name $OCA_TARGET"
        OCA_CMD="$OCA_CMD --no-commit"
        [ -n "$MODULE" ] && OCA_CMD="$OCA_CMD --modules $MODULE"

        if [ "$DRY_RUN" = true ]; then
            printf "    ${CWARN}[DRY-RUN]${RST} Would run: $OCA_CMD\n"
        else
            docker exec "$CONTAINER" bash -c "$OCA_CMD" 2>&1 | sed 's/^/    /'
        fi
        echo ""
    done
    printf "  ${CSUCCESS}✓${RST} OCA completed\n"
    [ "$DRY_RUN" = false ] && OCA_DONE=true
    echo ""
fi

# ============================================================================
# 2. Odoo official upgrade_code
# ============================================================================
if [ "$USE_ODOO" = true ]; then
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CPRIMARY}  ▶ Odoo official upgrade_code${RST}\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

    ODOO_FROM="$FROM_VERSION"
    [[ "$FROM_VERSION" < "17.5" ]] && ODOO_FROM="17.5"

    ADDONS_PATH_ARG=$(echo "$SELECTED_PATHS" | tr ' ' ',')

    if [ ${#ODOO_SCRIPTS[@]} -gt 0 ]; then
        # Run selected scripts only
        for script in "${ODOO_SCRIPTS[@]}"; do
            printf "  ${CPRIMARY}▶${RST} $script\n"
            ODOO_CMD="odoo upgrade_code --script '$script' --addons-path $ADDONS_PATH_ARG"
            [ -n "$MODULE" ] && ODOO_CMD="$ODOO_CMD --glob '$(echo "$MODULE" | cut -d',' -f1)/**/*'"

            OUTPUT=$(docker exec "$CONTAINER" bash -c "$ODOO_CMD $DRY_FLAG" 2>&1)
            FILTERED=$(echo "$OUTPUT" | grep "^/mnt" || true)

            if [ -n "$FILTERED" ]; then
                echo "$FILTERED" | sed "s|^/mnt/extra-addons/||" | sed "s|^|    |"
                [ "$DRY_RUN" = false ] && ODOO_DONE=true
            else
                printf "    ${CSUCCESS}✓${RST} No changes\n"
            fi
        done
    else
        # Run all (no --script)
        ODOO_CMD="odoo upgrade_code"
        ODOO_CMD="$ODOO_CMD --from $ODOO_FROM --to $TO_VERSION"
        ODOO_CMD="$ODOO_CMD --addons-path $ADDONS_PATH_ARG"
        [ -n "$MODULE" ] && ODOO_CMD="$ODOO_CMD --glob '$(echo "$MODULE" | cut -d',' -f1)/**/*'"

        OUTPUT=$(docker exec "$CONTAINER" bash -c "$ODOO_CMD $DRY_FLAG" 2>&1)
        FILTERED=$(echo "$OUTPUT" | grep "^/mnt" || true)

        if [ -n "$FILTERED" ]; then
            echo "$FILTERED" | sed "s|^/mnt/extra-addons/||" | sed "s|^|  |"
            FILE_COUNT=$(echo "$FILTERED" | wc -l)
            printf "\n  ${CSUCCESS}✓${RST} $FILE_COUNT file(s)\n"
            [ "$DRY_RUN" = false ] && ODOO_DONE=true
        else
            printf "  ${CSUCCESS}✓${RST} No changes needed\n"
        fi
    fi
    echo ""
fi

# ============================================================================
# 3. Custom migration scripts
# ============================================================================
if [ "$USE_CUSTOM" = true ] && [ ${#CUSTOM_SCRIPTS[@]} -gt 0 ]; then
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CACCENT}  ▶ Custom migration scripts${RST}\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

    ODOO_UPGRADE_DIR=$(resolve_odoo_upgrade_code_dir "$CONTAINER")
    ADDONS_PATH_ARG=$(echo "$SELECTED_PATHS" | tr ' ' ',')

    for script in "${CUSTOM_SCRIPTS[@]}"; do
        script_name=$(basename "$script")
        printf "  ${CPRIMARY}▶${RST} $script_name\n\n"

        docker exec "$CONTAINER" cp "$script" "$ODOO_UPGRADE_DIR/$script_name" 2>/dev/null

        SCRIPT_CMD="odoo upgrade_code --script '$script_name' --addons-path $ADDONS_PATH_ARG"
        [ -n "$MODULE" ] && SCRIPT_CMD="$SCRIPT_CMD --glob '$(echo "$MODULE" | cut -d',' -f1)/**/*'"

        OUTPUT=$(docker exec "$CONTAINER" bash -c "$SCRIPT_CMD $DRY_FLAG" 2>&1)

        docker exec "$CONTAINER" rm -f "$ODOO_UPGRADE_DIR/$script_name" 2>/dev/null

        # Filter only paths within selected addons (not odoo standard)
        FILTERED=$(echo "$OUTPUT" | grep "^/mnt" || true)
        if [ -n "$FILTERED" ]; then
            echo "$FILTERED" | sed "s|^/mnt/extra-addons/||" | sed "s|^|  |"
            FILE_COUNT=$(echo "$FILTERED" | wc -l)
            printf "\n  ${CSUCCESS}✓${RST} $FILE_COUNT file(s)\n"
            [ "$DRY_RUN" = false ] && CUSTOM_DONE=true
        else
            printf "  ${CSUCCESS}✓${RST} No changes needed\n"
        fi
        echo ""
    done
    echo ""
fi

# ============================================================================
# 4. Bump manifest versions
# ============================================================================
if [ "$DRY_RUN" = false ]; then
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${CSUCCESS}  ▶ Bumping manifest versions → ${TO_VERSION}.0.0${RST}\n"
    printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

    if [ -n "$MODULE" ]; then
        MANIFESTS=$(docker exec "$CONTAINER" find $SELECTED_PATHS -path "*/$MODULE/__manifest__.py" -type f 2>/dev/null)
    else
        MANIFESTS=$(docker exec "$CONTAINER" find $SELECTED_PATHS -name "__manifest__.py" -type f 2>/dev/null)
    fi

    BUMP_COUNT=0
    while IFS= read -r manifest; do
        [ -z "$manifest" ] && continue
        module_name=$(dirname "$manifest" | xargs basename)
        docker exec "$CONTAINER" sed -i "s/['\"]version['\"]\s*:\s*['\"][^'\"]*['\"]/\"version\": \"${TO_VERSION}.0.0\"/" "$manifest" 2>/dev/null
        printf "  ${CSUCCESS}✓${RST} $module_name\n"
        ((BUMP_COUNT++))
    done <<< "$MANIFESTS"

    [ $BUMP_COUNT -gt 0 ] && VERSION_DONE=true
    printf "\n  Updated $BUMP_COUNT manifest(s)\n"
    echo ""
fi

# ============================================================================
# SUMMARY
# ============================================================================
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
printf "${CPRIMARY}  SUMMARY${RST}\n"
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n\n"

if [ "$DRY_RUN" = true ]; then
    printf "  ${CWARN}DRY-RUN MODE${RST} - No changes applied\n"
else
    [ "$OCA_DONE" = true ] && printf "  ${CSUCCESS}✓${RST} OCA\n"
    [ "$ODOO_DONE" = true ] && printf "  ${CSUCCESS}✓${RST} Odoo\n"
    [ "$CUSTOM_DONE" = true ] && printf "  ${CSUCCESS}✓${RST} Custom\n"
    [ "$VERSION_DONE" = true ] && printf "  ${CSUCCESS}✓${RST} Version → ${TO_VERSION}.0.0\n"
fi

echo ""
printf "${CWARN}  ⚠ Manual migrations needed:${RST}\n"
echo "    - attrs= → invisible=, readonly=, required="
echo "    - states= → invisible expression"
echo "    - Kanban views (kanban-box → card)"
echo ""

# ============================================================================
# 5. Pre-commit (optional)
# ============================================================================
if [ "$DRY_RUN" = false ]; then
    RUN_PRECOMMIT=false

    if [ "$FORCE" = true ]; then
        RUN_PRECOMMIT=true
    else
        printf "  Run pre-commit on migrated files? [Y/n]: "
        read -r PRECOMMIT_CHOICE
        [[ -z "$PRECOMMIT_CHOICE" || "$PRECOMMIT_CHOICE" =~ ^[Yy] ]] && RUN_PRECOMMIT=true
    fi

    if [ "$RUN_PRECOMMIT" = true ]; then
        printf "\n${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
        printf "${CSUCCESS}  ▶ Running pre-commit${RST}\n"
        printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

        FILES_TO_PROCESS=$(docker exec "$CONTAINER" find $SELECTED_PATHS -type f \( -name "*.py" -o -name "*.xml" \) 2>/dev/null | tr '\n' ' ')
        run_precommit "$CONTAINER" "$FILES_TO_PROCESS"

        printf "\n  ${CSUCCESS}✓${RST} Pre-commit completed\n\n"
    fi
fi
