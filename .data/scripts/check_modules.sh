#!/bin/bash
# ============================================================================
# Build the module name cache read by utils (completion, 'u' validation) and
# odoo_header.sh: /var/odoo/cache/.modules_list = <paths hash>\n<a|b|c...>.
# Rebuilt when an addon directory (Odoo, enterprise, yours) changed.
# Usage: check_modules.sh <addon_paths>   (comma-separated)
# ============================================================================

ADDON_PATHS="$1"
CACHE_FILE="/var/odoo/cache/.modules_list"

SCAN_PATHS="/opt/odoo/addons /opt/odoo/odoo/addons $(echo "$ADDON_PATHS" | tr ',' ' ')"
PATHS_HASH=$(printf '%s' "$SCAN_PATHS" $(stat -c '%Y' $SCAN_PATHS 2>/dev/null) | md5sum | cut -d' ' -f1)
[ -f "$CACHE_FILE" ] && [ "$(head -1 "$CACHE_FILE")" = "$PATHS_HASH" ] && exit 0

KNOWN=$(find $SCAN_PATHS -maxdepth 2 -name "__manifest__.py" 2>/dev/null \
    | awk -F/ '{print $(NF-1)}' | sort -u | paste -sd '|')
mkdir -p "$(dirname "$CACHE_FILE")"
printf '%s\n%s\n' "$PATHS_HASH" "$KNOWN" > "$CACHE_FILE"
