#!/bin/bash
# Fast module name validation for Odoo container

MODULES="$1"
[ -z "$MODULES" ] && exit 0

CACHE_FILE="/var/lib/odoo/cache/.modules_cache"
CACHE_AGE=300

build_cache() {
    local modules=""
    for dir in /mnt/extra-addons/*/; do
        [ -f "${dir}__manifest__.py" ] && modules="$modules|$(basename "$dir")"
    done
    for dir in /mnt/extra-addons/*/*/; do
        [ -f "${dir}__manifest__.py" ] && modules="$modules|$(basename "$dir")"
    done
    for dir in /mnt/enterprise-addons/*/; do
        [ -f "${dir}__manifest__.py" ] && modules="$modules|$(basename "$dir")"
    done
    echo "${modules:1}" > "$CACHE_FILE"
    echo "${modules:1}"
}

KNOWN=""
if [ -f "$CACHE_FILE" ]; then
    AGE=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
    if [ $AGE -lt $CACHE_AGE ]; then
        KNOWN=$(cat "$CACHE_FILE")
    else
        KNOWN=$(build_cache)
    fi
else
    KNOWN=$(build_cache)
fi

[ -z "$KNOWN" ] && exit 0

WARNINGS=""
IFS=',' read -ra MOD_ARRAY <<< "$MODULES"
for mod in "${MOD_ARRAY[@]}"; do
    mod=$(echo "$mod" | xargs)
    [ "$mod" = "all" ] && continue
    [ "$mod" = "base" ] && continue
    if ! echo "$KNOWN" | grep -qE "(^|\\|)${mod}(\\||$)"; then
        WARNINGS="$WARNINGS $mod"
    fi
done

if [ -n "$WARNINGS" ]; then
    echo -e "\033[33m⚠️  Unknown module(s):$WARNINGS\033[0m"
fi

