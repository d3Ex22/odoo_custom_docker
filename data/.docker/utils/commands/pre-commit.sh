#!/bin/bash
# ============================================================================
# pre-commit - Run pre-commit hooks on addon files
# ============================================================================

source /home/odoo/docker_dev/data/.docker/utils/lib/common.sh

show_help() {
    echo ""
    echo "pre-commit - Run pre-commit hooks on addon files"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       pre-commit [OPTIONS]"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -a, --all-files   Run on all paths/modules without selection"
    echo "       -f, --force       Run on all files without any prompts"
    echo "       -h, --help        Show this help"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       pre-commit              # Interactive selection"
    echo "       pre-commit -a           # All files, no path/module selection"
    echo "       pre-commit -a -f        # All files, no prompts at all"
    echo ""
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

ALL_FILES=false
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -a|--all-files) ALL_FILES=true; shift ;;
        -f|--force) FORCE=true; shift ;;
        *) shift ;;
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

if [ "$PATH_COUNT" -gt 1 ] && [ "$ALL_FILES" = false ]; then
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
elif [ "$PATH_COUNT" -eq 1 ]; then
    SELECTED_PATHS="$DETECTED_PATHS"
fi

# ============================================================================
# MODULE SELECTION
# ============================================================================
if [ "$ALL_FILES" = false ]; then
    # Find all modules in selected paths
    ALL_MODULES=$(docker exec "$CONTAINER" find $SELECTED_PATHS -maxdepth 2 -name "__manifest__.py" -type f 2>/dev/null | xargs -I{} dirname {} | sort -u)
    MODULE_COUNT=$(echo "$ALL_MODULES" | grep -c "/" || echo "0")
    
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
        done <<< "$ALL_MODULES"
        
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
            SELECTED_PATHS=$(echo "$ALL_MODULES" | tr '\n' ' ')
        fi
        echo ""
    fi
fi
# ============================================================================
# RUN PRE-COMMIT
# ============================================================================
printf "${C}───────────────────────────────────────────────────────────────${RST}\n"
printf "${GREEN}  ▶ Running pre-commit${RST}\n"
printf "${C}───────────────────────────────────────────────────────────────${RST}\n\n"

# Check if pre-commit is installed
if ! docker exec "$CONTAINER" which pre-commit >/dev/null 2>&1; then
    printf "  Installing pre-commit...\n\n"
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

# Run pre-commit with temporary git repo and config
if [ -n "$FILES_TO_PROCESS" ]; then
    docker exec "$CONTAINER" bash -c '
        cd /mnt/extra-addons
        
        # Fix git ownership issues
        git config --global --add safe.directory /mnt/extra-addons
        
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
        
        # Create temporary git repo
        git init --quiet
        git config user.email "pre-commit@local"
        git config user.name "Pre-commit"
        git add -A
        
        # Run pre-commit
        pre-commit run --files '"$FILES_TO_PROCESS"' || true
        
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

