#!/bin/bash
# ============================================================================
# pre-commit - Run pre-commit hooks on addon files
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    echo ""
    echo "pre-commit - Run pre-commit hooks on addon files"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       pre-commit [FOLDER] [OPTIONS]"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       FOLDER            Specify folder name (e.g., custom-addons, oca-addons)"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -a, --all          Run on all modules (skip module selection)"
    echo "       -h, --help         Show this help"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       pre-commit                      # Interactive path and module selection"
    echo "       pre-commit custom-addons        # Pre-select custom-addons, then select modules"
    echo "       pre-commit custom-addons -a     # All modules in custom-addons folder"
    echo "       pre-commit -a                   # All modules in all paths"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

ALL_MODULES=false
TARGET_FOLDER=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all) ALL_MODULES=true; shift ;;
        -h|--help) show_help; exit 0 ;;
        -*) shift ;;
        *) TARGET_FOLDER="$1"; shift ;;
    esac
done

CONTAINER="$ODOO_CONTAINER"

if ! docker exec "$CONTAINER" test -d /mnt/extra-addons 2>/dev/null; then
    printf "${CERROR}❌ Odoo container not running${RST}\n"
    exit 1
fi

echo ""
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
printf "${CPRIMARY}  PRE-COMMIT${RST}\n"
printf "${CPRIMARY}═══════════════════════════════════════════════════════════════${RST}\n"
echo ""

# ============================================================================
# PATH SELECTION (use generate_addons_path.sh)
# ============================================================================
DETECTED_PATHS=$(docker exec "$CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null | tr ',' '\n' | grep -v "^$")
SELECTED_PATHS="/mnt/extra-addons"

PATH_COUNT=$(echo "$DETECTED_PATHS" | grep -c "/" || echo "0")

# If TARGET_FOLDER is specified, try to match it
if [ -n "$TARGET_FOLDER" ]; then
    MATCHED_PATH=$(echo "$DETECTED_PATHS" | grep "/$TARGET_FOLDER$" | head -1)
    if [ -n "$MATCHED_PATH" ]; then
        SELECTED_PATHS="$MATCHED_PATH"
        printf "${CSUCCESS}  ✓ Using folder: $(basename "$MATCHED_PATH")${RST}\n\n"
    else
        printf "${CWARN}  ⚠ Folder '$TARGET_FOLDER' not found, falling back to interactive selection${RST}\n\n"
        TARGET_FOLDER=""
    fi
fi

if [ "$PATH_COUNT" -gt 1 ] && [ -z "$TARGET_FOLDER" ]; then
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
    echo ""
elif [ "$PATH_COUNT" -eq 1 ] && [ -z "$TARGET_FOLDER" ]; then
    SELECTED_PATHS="$DETECTED_PATHS"
fi

# ============================================================================
# MODULE SELECTION
# ============================================================================
if [ "$ALL_MODULES" = false ]; then
    # Find all modules in selected paths
    FOUND_MODULES=$(docker exec "$CONTAINER" find $SELECTED_PATHS -maxdepth 2 -name "__manifest__.py" -type f 2>/dev/null | xargs -I{} dirname {} | sort -u)
    MODULE_COUNT=$(echo "$FOUND_MODULES" | grep -c "/" || echo "0")

    if [ "$MODULE_COUNT" -gt 0 ]; then
        printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
        printf "${CPRIMARY}  Select modules ($MODULE_COUNT available)${RST}\n"
        printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

        i=1
        declare -A MODULE_MAP
        while IFS= read -r mod_path; do
            [ -z "$mod_path" ] && continue
            mod_name=$(basename "$mod_path")
            printf "    ${CSUCCESS}%2d.${RST} %s\n" "$i" "$mod_name"
            MODULE_MAP[$i]="$mod_path"
            ((i++))
        done <<< "$FOUND_MODULES"

        echo ""
        printf "  Select modules (1,2,3 / all) [all]: "
        read -r MOD_CHOICE

        if [ -n "$MOD_CHOICE" ] && [ "$MOD_CHOICE" != "all" ]; then
            SELECTED_PATHS=""
            IFS=',' read -ra NUMS <<< "$MOD_CHOICE"
            for num in "${NUMS[@]}"; do
                num=$(echo "$num" | tr -d ' ')
                [ -n "${MODULE_MAP[$num]}" ] && SELECTED_PATHS="$SELECTED_PATHS ${MODULE_MAP[$num]}"
            done
            SELECTED_PATHS=$(echo "$SELECTED_PATHS" | xargs)
        else
            SELECTED_PATHS=$(echo "$FOUND_MODULES" | tr '\n' ' ')
        fi
        echo ""
    fi
else
    # -a flag: use all modules in selected paths
    FOUND_MODULES=$(docker exec "$CONTAINER" find $SELECTED_PATHS -maxdepth 2 -name "__manifest__.py" -type f 2>/dev/null | xargs -I{} dirname {} | sort -u)
    if [ -n "$FOUND_MODULES" ]; then
        SELECTED_PATHS=$(echo "$FOUND_MODULES" | tr '\n' ' ')
        MODULE_COUNT=$(echo "$FOUND_MODULES" | grep -c "/" || echo "0")
        printf "${CSUCCESS}  ✓ Using all $MODULE_COUNT modules${RST}\n\n"
    fi
fi
# ============================================================================
# RUN PRE-COMMIT
# ============================================================================
printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n"
printf "${CSUCCESS}  ▶ Running pre-commit${RST}\n"
printf "${CPRIMARY}───────────────────────────────────────────────────────────────${RST}\n\n"

FILES_TO_PROCESS=""
for path in $SELECTED_PATHS; do
    printf "  ${CWARN}▶${RST} $(basename "$path")\n"
    FILES=$(docker exec "$CONTAINER" find "$path" -type f \( -name "*.py" -o -name "*.xml" -o -name "*.js" -o -name "*.css" \) 2>/dev/null | tr '\n' ' ')
    FILES_TO_PROCESS="$FILES_TO_PROCESS $FILES"
done
echo ""

run_precommit "$CONTAINER" "$FILES_TO_PROCESS"

echo ""
printf "${CSUCCESS}  ✓ Pre-commit completed${RST}\n\n"
