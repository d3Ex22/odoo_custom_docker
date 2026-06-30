#!/bin/bash

# Compute the Odoo addons_path from mounted volumes and write it to odoo.conf.
#
# When SCAN_SUBFOLDERS=true (set in .env), scans /mnt/extra-addons recursively
# for __manifest__.py files and includes each unique parent directory as a path.
# Otherwise, /mnt/extra-addons itself is used as a single path.
#
# IGNORED_PATH (comma-separated, optional) skips paths during subfolder scan:
#   - "disabled"                         → any directory named disabled
#   - "repo/disabled"                    → only that path under /mnt/extra-addons
#   - "/mnt/extra-addons/repo/disabled"  → absolute path
#
# /mnt/enterprise-addons is prepended when non-empty (takes priority over extras).
# The computed path is both written to odoo.conf and printed to stdout.

ENV_FILE="/home/odoo/.env"
ODOO_CONF="/etc/odoo/odoo.conf"
EXTRA_ADDONS_ROOT="/mnt/extra-addons"

if [ ! -f "$ENV_FILE" ]; then
    exit 0
fi

source "$ENV_FILE"

is_ignored_path() {
    local target="$1"
    [ -z "${IGNORED_PATH:-}" ] && return 1

    local rel=""
    if [[ "$target" == "$EXTRA_ADDONS_ROOT"/* ]]; then
        rel="${target#"$EXTRA_ADDONS_ROOT"/}"
    elif [ "$target" = "$EXTRA_ADDONS_ROOT" ]; then
        rel=""
    else
        return 1
    fi

    IFS=',' read -ra _ignore_patterns <<< "$IGNORED_PATH"
    for _raw in "${_ignore_patterns[@]}"; do
        local pattern="${_raw#"${_raw%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        [ -z "$pattern" ] && continue

        if [[ "$pattern" == /* ]]; then
            [[ "$target" == "$pattern" || "$target" == "$pattern/"* ]] && return 0
        elif [[ "$pattern" == */* ]]; then
            [[ "$rel" == "$pattern" || "$rel" == "$pattern/"* ]] && return 0
        else
            local rest="$rel"
            while true; do
                local component="${rest%%/*}"
                [ "$component" = "$pattern" ] && return 0
                [[ "$rest" == *"/"* ]] || break
                rest="${rest#*/}"
            done
        fi
    done
    return 1
}

find_addon_manifests() {
    local base="$EXTRA_ADDONS_ROOT"

    if [ -z "${IGNORED_PATH:-}" ]; then
        find "$base" \( -name "__manifest__.py" -o -name "__openerp__.py" \) 2>/dev/null
        return
    fi

    local -a prune_cond=()
    IFS=',' read -ra _ignore_patterns <<< "$IGNORED_PATH"
    for _raw in "${_ignore_patterns[@]}"; do
        local pattern="${_raw#"${_raw%%[![:space:]]*}"}"
        pattern="${pattern%"${pattern##*[![:space:]]}"}"
        [ -z "$pattern" ] && continue

        if [ ${#prune_cond[@]} -gt 0 ]; then
            prune_cond+=(-o)
        fi

        if [[ "$pattern" == /* ]]; then
            prune_cond+=(-path "$pattern")
        elif [[ "$pattern" == */* ]]; then
            prune_cond+=(-path "$base/$pattern")
        else
            prune_cond+=(\( -type d -name "$pattern" \))
        fi
    done

    if [ ${#prune_cond[@]} -eq 0 ]; then
        find "$base" \( -name "__manifest__.py" -o -name "__openerp__.py" \) 2>/dev/null
        return
    fi

    find "$base" \( "${prune_cond[@]}" \) -prune -o \
        \( -name "__manifest__.py" -o -name "__openerp__.py" \) -print 2>/dev/null
}

PATHS=""

if [ -d "/mnt/enterprise-addons" ] && [ "$(find /mnt/enterprise-addons -mindepth 1 -not -name '.*' 2>/dev/null | head -n 1)" ]; then
    PATHS="/mnt/enterprise-addons"
fi

if [ -d "$EXTRA_ADDONS_ROOT" ]; then
    if [ "${SCAN_SUBFOLDERS}" = "true" ]; then
        FOUND_PATHS=""
        while IFS= read -r manifest; do
            MODULE_DIR=$(dirname "$manifest")
            is_ignored_path "$MODULE_DIR" && continue

            PARENT_DIR=$(dirname "$MODULE_DIR")
            is_ignored_path "$PARENT_DIR" && continue

            if [ -n "$PARENT_DIR" ] && [ "$PARENT_DIR" != "$EXTRA_ADDONS_ROOT" ]; then
                if [[ ",${FOUND_PATHS}," != *",${PARENT_DIR},"* ]]; then
                    FOUND_PATHS="${FOUND_PATHS}${FOUND_PATHS:+,}${PARENT_DIR}"
                fi
            elif [ "$PARENT_DIR" = "$EXTRA_ADDONS_ROOT" ]; then
                if [[ ",${FOUND_PATHS}," != *",${EXTRA_ADDONS_ROOT},"* ]]; then
                    FOUND_PATHS="${FOUND_PATHS}${FOUND_PATHS:+,}${EXTRA_ADDONS_ROOT}"
                fi
            fi
        done < <(find_addon_manifests)

        if [ -n "$FOUND_PATHS" ]; then
            PATHS="${PATHS}${PATHS:+,}${FOUND_PATHS}"
        fi
    else
        if find "$EXTRA_ADDONS_ROOT" -maxdepth 2 \( -name "__manifest__.py" -o -name "__openerp__.py" \) -print -quit 2>/dev/null | grep -q .; then
            PATHS="${PATHS}${PATHS:+,}${EXTRA_ADDONS_ROOT}"
        fi
    fi
fi

if [ -n "$PATHS" ] && [ -f "$ODOO_CONF" ]; then
    TMP_CONF="/tmp/odoo.conf.tmp"
    if grep -q "^addons_path" "$ODOO_CONF"; then
        sed "s|^addons_path.*|addons_path = ${PATHS}|" "$ODOO_CONF" > "$TMP_CONF"
        cat "$TMP_CONF" > "$ODOO_CONF"
        rm -f "$TMP_CONF"
    else
        echo "addons_path = ${PATHS}" >> "$ODOO_CONF"
    fi
fi

echo "$PATHS"
