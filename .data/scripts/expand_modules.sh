#!/bin/bash
# ============================================================================
# expand_modules.sh — Resolve glob/regex patterns to concrete module names.
#
# Reads the module cache (pipe-separated list of known module names) and
# expands any token containing special characters (*, ?, ., [, +, ^, $)
# against it using ERE regex. Glob-like shortcuts are converted first:
#   sale_*  → sale_.*     (bare * becomes .*)
#   sale_?  → sale_.      (bare ? becomes .)
#
# Usage:  expand_modules.sh "sale_*,base,purchase"
# Output: sale_crm,sale_management,...,base,purchase   (stdout, comma-sep)
#
# Env:  MODULES_CACHE  path to the cache file (default: /var/odoo/cache/.modules_list)
# ============================================================================

INPUT="$1"
[ -z "$INPUT" ] && exit 0

CACHE="${MODULES_CACHE:-/var/odoo/cache/.modules_list}"
KNOWN=""
[ -f "$CACHE" ] && KNOWN=$(tail -1 "$CACHE")

RESULT="" SEEN=""
IFS=',' read -ra TOKENS <<< "$INPUT"
for token in "${TOKENS[@]}"; do
    token=$(echo "$token" | xargs)
    [ -z "$token" ] && continue
    if [[ "$token" == *[\*\?.\[\+\^\$]* ]]; then
        regex=$(echo "$token" | sed -E 's/([^.\\])\*/\1.*/g; s/^\*/.*/; s/([^\\])\?/\1./g; s/^\?/./')
        if [ -n "$KNOWN" ]; then
            matches=$(echo "$KNOWN" | tr '|' '\n' | grep -E "^${regex}$")
            if [ -z "$matches" ]; then
                echo "⚠ No modules matching '${token}'" >&2
                continue
            fi
            while IFS= read -r m; do
                [ -z "$m" ] && continue
                echo "$SEEN" | grep -qxF "$m" && continue
                SEEN="${SEEN}${SEEN:+$'\n'}${m}"
                RESULT="${RESULT}${RESULT:+,}${m}"
            done <<< "$matches"
        fi
    else
        echo "$SEEN" | grep -qxF "$token" && continue
        SEEN="${SEEN}${SEEN:+$'\n'}${token}"
        RESULT="${RESULT}${RESULT:+,}${token}"
    fi
done
echo "$RESULT"
