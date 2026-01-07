#!/bin/bash
# ============================================================================
# pre-commit - Run pre-commit hooks on addon files
# ============================================================================

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C="\033[38;2;${R};${G};${B}m"
RST="\033[0m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
GREEN="\033[0;32m"

show_help() {
    echo ""
    echo "pre-commit - Run pre-commit hooks on addon files"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       pre-commit [FOLDER] [OPTIONS]"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       FOLDER            Specify folder name (e.g., custom-addons, oca-addons)"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -a, --all          Run on all modules (skip module selection)"
    echo "       -h, --help         Show this help"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
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

CONTAINER="${COMPOSE_PROJECT_NAME:-odoo}_odoo"

if ! docker exec "$CONTAINER" test -d /mnt/extra-addons 2>/dev/null; then
    printf "${RED}❌ Odoo container not running${RST}\n"
    exit 1
fi

echo ""
printf "${C}═══════════════════════════════════════════════════════════════${RST}\n"
printf "${C}  PRE-COMMIT${RST}\n"
printf "${C}═══════════════════════════════════════════════════════════════${RST}\n"
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
        printf "${GREEN}  ✓ Using folder: $(basename "$MATCHED_PATH")${RST}\n\n"
    else
        printf "${YELLOW}  ⚠ Folder '$TARGET_FOLDER' not found, falling back to interactive selection${RST}\n\n"
        TARGET_FOLDER=""
    fi
fi

if [ "$PATH_COUNT" -gt 1 ] && [ -z "$TARGET_FOLDER" ]; then
    printf "${C}───────────────────────────────────────────────────────────────${RST}\n"
    printf "${C}  Select addon paths ($PATH_COUNT detected)${RST}\n"
    printf "${C}───────────────────────────────────────────────────────────────${RST}\n\n"
    
    i=1
    declare -A PATH_MAP
    while IFS= read -r path; do
        [ -z "$path" ] && continue
        path_name=$(basename "$path")
        printf "    ${GREEN}%2d.${RST} %s\n" "$i" "$path_name"
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
        printf "${C}───────────────────────────────────────────────────────────────${RST}\n"
        printf "${C}  Select modules ($MODULE_COUNT available)${RST}\n"
        printf "${C}───────────────────────────────────────────────────────────────${RST}\n\n"
        
        i=1
        declare -A MODULE_MAP
        while IFS= read -r mod_path; do
            [ -z "$mod_path" ] && continue
            mod_name=$(basename "$mod_path")
            printf "    ${GREEN}%2d.${RST} %s\n" "$i" "$mod_name"
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
        printf "${GREEN}  ✓ Using all $MODULE_COUNT modules${RST}\n\n"
    fi
fi
# ============================================================================
# RUN PRE-COMMIT
# ============================================================================
printf "${C}───────────────────────────────────────────────────────────────${RST}\n"
printf "${GREEN}  ▶ Running pre-commit${RST}\n"
printf "${C}───────────────────────────────────────────────────────────────${RST}\n\n"

# Check if pre-commit is installed (cache is persisted in volume)
if ! docker exec "$CONTAINER" which pre-commit >/dev/null 2>&1; then
    printf "  ${YELLOW}Installing pre-commit (first time only)...${RST}\n\n"
    docker exec "$CONTAINER" pip install pre-commit --quiet 2>/dev/null
fi

# Collect all files to process
FILES_TO_PROCESS=""
for path in $SELECTED_PATHS; do
    path_name=$(basename "$path")
    printf "  ${YELLOW}▶${RST} $path_name\n"
    FILES=$(docker exec "$CONTAINER" find "$path" -type f \( -name "*.py" -o -name "*.xml" -o -name "*.js" -o -name "*.css" \) 2>/dev/null | tr '\n' ' ')
    FILES_TO_PROCESS="$FILES_TO_PROCESS $FILES"
done

echo ""

# Run pre-commit with persistent git repo and config
if [ -n "$FILES_TO_PROCESS" ]; then
    docker exec "$CONTAINER" bash -c '
        cd /mnt/extra-addons
        PRECOMMIT_CACHE="/home/odoo/.cache/pre-commit"
        PRECOMMIT_GIT="$PRECOMMIT_CACHE/git_repo"
        
        # Fix git ownership issues
        git config --global --add safe.directory /mnt/extra-addons
        git config --global --add safe.directory "$PRECOMMIT_GIT"
        
        # Backup existing .pre-commit-config.yaml if present
        if [ -f .pre-commit-config.yaml ]; then
            mv .pre-commit-config.yaml .pre-commit-config.yaml.backup
        fi
        
        # Copy pre-commit config
        cp /opt/.pre-commit-config.yaml .pre-commit-config.yaml
        
        # Backup existing .git if present
        if [ -d .git ]; then
            mv .git .git_backup_precommit
        fi
        
        # Use persistent git repo or create new one
        if [ -d "$PRECOMMIT_GIT/.git" ]; then
            # Restore persistent git repo
            cp -a "$PRECOMMIT_GIT/.git" .git
        else
            # Create new git repo and save it
            git init --quiet
            git config user.email "pre-commit@local"
            git config user.name "Pre-commit"
            mkdir -p "$PRECOMMIT_GIT"
            cp -a .git "$PRECOMMIT_GIT/.git"
        fi
        
        # Update git index with current files
        git add -A
        
        # Run pre-commit
        pre-commit run --files '"$FILES_TO_PROCESS"' || true
        
        # Save updated git repo to cache
        cp -a .git "$PRECOMMIT_GIT/.git"
        
        # Cleanup: remove temp git, restore original
        rm -rf .git
        if [ -d .git_backup_precommit ]; then
            mv .git_backup_precommit .git
        fi
        
        # Cleanup: remove config, restore original
        rm -f .pre-commit-config.yaml
        if [ -f .pre-commit-config.yaml.backup ]; then
            mv .pre-commit-config.yaml.backup .pre-commit-config.yaml
        fi
    ' 2>&1 | sed 's/^/  /'
fi

echo ""
printf "${GREEN}  ✓ Pre-commit completed${RST}\n\n"

