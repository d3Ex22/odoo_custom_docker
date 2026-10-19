#!/bin/bash
# ============================================================================
# Prints a header in the Odoo logs pane before (re)starting Odoo.
# Called from inside the odoo container.
# Usage: odoo_header.sh <odoo_command> [addon_paths]
# ============================================================================

ODOO_CMD="$1"
ADDON_PATHS="$2"

source /opt/env/scripts/lib/theme.sh

SEP="${CMUTED}────────────────────────────────────────────────────────${RST}"

printf '\n%s\n' "$SEP"

if [ -n "$ADDON_PATHS" ]; then
    printf '%sAddon paths:%s\n' "$CMUTED" "$RST"
    IFS=',' read -ra PA <<< "$ADDON_PATHS"
    for p in "${PA[@]}"; do
        printf '  - %s%s%s\n' "$CPRIMARY" "$p" "$RST"
    done
else
    printf '%sAddon paths:%s\n' "$CMUTED" "$RST"
    printf '  - %snone%s\n' "$CWARN" "$RST"
fi

REQ_LIST=()
if [ -d "/mnt/extra-addons" ]; then
    while IFS= read -r r; do
        grep -qvE '^\s*(#|$)' "$r" 2>/dev/null && REQ_LIST+=("$r")
    done < <(find "/mnt/extra-addons" -name "requirements.txt" -type f | awk -F'/' '{print NF, $0}' | sort -rn | cut -d' ' -f2-)
fi
if [ ${#REQ_LIST[@]} -gt 0 ]; then
    printf '\n%sRequirements:%s\n' "$CMUTED" "$RST"
    for r in "${REQ_LIST[@]}"; do
        printf '  - %s%s%s\n' "$CPRIMARY" "$r" "$RST"
    done
fi

ARGS=""
set -f
for token in $ODOO_CMD; do
    case "$token" in
        odoo|-c|/etc/odoo/odoo.conf) continue ;;
        -d|-u) SKIP_NEXT="$token"; continue ;;
    esac
    [ -n "$SKIP_NEXT" ] && SKIP_NEXT="" && continue
    ARGS="${ARGS}${ARGS:+,}${token}"
done
set +f
if [ -n "$ARGS" ]; then
    printf '\n%sExtra arguments:%s\n' "$CMUTED" "$RST"
    IFS=',' read -ra AA <<< "$ARGS"
    for a in "${AA[@]}"; do
        printf '  - %s%s%s\n' "$CPRIMARY" "$a" "$RST"
    done
fi

DB=$(echo "$ODOO_CMD" | grep -oP '(?<=-d )\S+')
[ -n "$DB" ] && printf '\n%sDatabase: %s%s%s\n' "$CMUTED" "$CPRIMARY" "$DB" "$RST"

SWM=$(grep -E "^server_wide_modules" /etc/odoo/odoo.conf 2>/dev/null | head -1)
if echo "$SWM" | grep -q "iot_drivers"; then
    printf '\n%sIoT Box: %sRUNNING%s\n' "$CMUTED" "$CSUCCESS" "$RST"
fi

MODS=$(echo "$ODOO_CMD" | grep -oP '(?<=-u )\S+')
if [ -n "$MODS" ]; then
    CACHE="/var/odoo/cache/.modules_list"
    KNOWN=""
    [ -f "$CACHE" ] && KNOWN=$(tail -1 "$CACHE")
    printf '\n%sUpdate modules:%s\n' "$CMUTED" "$RST"
    IFS=',' read -ra ML <<< "$MODS"
    for mod in "${ML[@]}"; do
        mod=$(echo "$mod" | xargs)
        if [ "$mod" != "all" ] && [ "$mod" != "base" ] && [ -n "$KNOWN" ] && ! echo "$KNOWN" | grep -qE "(^|\|)${mod}(\||$)"; then
            printf '  - %s%s ⚠%s\n' "$CWARN" "$mod" "$RST"
        else
            printf '  - %s%s%s\n' "$CSUCCESS" "$mod" "$RST"
        fi
    done
fi

printf '%s\n\n' "$SEP"
