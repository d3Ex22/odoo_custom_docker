#!/bin/bash

# Validate module names from ODOO_UPDATE against all known modules.
#
# Arguments:
#   $1  Module names (comma-separated, required)
#   $2  Addon paths  (comma-separated; empty string when called from utils)
#   $3  Cache file   (default: /var/odoo/cache/.modules_list)
#   $4  --list-unknown  Print only unknown names, one per line, no color
#
# When $3 is provided (external call from utils), the cache is read as-is.
# When $3 is empty (internal call from odoo entrypoint), the cache is
# validated by hash and rebuilt if any addon directory mtime changed.
#
# Prints a yellow warning for any unrecognized module names. Does not block startup.

MODULES="$1"
ADDON_PATHS="$2"
CACHE_FILE="${3:-/var/odoo/cache/.modules_list}"
LIST_UNKNOWN=false
[ "$4" = "--list-unknown" ] && LIST_UNKNOWN=true

KNOWN=""
if [ -n "$3" ]; then
    [ -f "$CACHE_FILE" ] && KNOWN=$(tail -1 "$CACHE_FILE")
else
    SCAN_PATHS="/opt/odoo/addons /opt/odoo/odoo/addons $(echo "$ADDON_PATHS" | tr ',' ' ')"
    PATHS_HASH=$(printf '%s' "$SCAN_PATHS" $(stat -c '%Y' $SCAN_PATHS 2>/dev/null) | md5sum | cut -d' ' -f1)

    if [ -f "$CACHE_FILE" ] && [ "$(head -1 "$CACHE_FILE")" = "$PATHS_HASH" ]; then
        KNOWN=$(tail -1 "$CACHE_FILE")
    fi

    if [ -z "$KNOWN" ]; then
        KNOWN=$(find $SCAN_PATHS -maxdepth 2 -name "__manifest__.py" 2>/dev/null \
            | awk -F/ '{print $(NF-1)}' \
            | sort -u \
            | paste -sd '|')
        printf '%s\n%s\n' "$PATHS_HASH" "$KNOWN" > "$CACHE_FILE"
    fi
fi

[ -z "$MODULES" ] && exit 0
[ -z "$KNOWN" ] && exit 0

WARNINGS=""
IFS=',' read -ra MOD_ARRAY <<< "$MODULES"
for mod in "${MOD_ARRAY[@]}"; do
    mod=$(echo "$mod" | xargs)
    [ "$mod" = "all" ] && continue
    [ "$mod" = "base" ] && continue
    if ! echo "$KNOWN" | grep -qE "(^|\|)${mod}(\||$)"; then
        WARNINGS="$WARNINGS $mod"
    fi
done

if [ -n "$WARNINGS" ]; then
    if $LIST_UNKNOWN; then
        for mod in $WARNINGS; do printf "%s\n" "$mod"; done
    else
        printf "\033[33m⚠️  Unknown module(s):\n"
        for mod in $WARNINGS; do printf "  - %s\n" "$mod"; done
        printf "\033[0m"
    fi
fi
