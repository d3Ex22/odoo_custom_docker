#!/bin/bash

# Compute the Odoo addons_path from mounted volumes and write it to odoo.conf.
#
# When SCAN_SUBFOLDERS=true (set in .env), scans /mnt/extra-addons recursively
# for __manifest__.py files and includes each unique parent directory as a path.
# Otherwise, /mnt/extra-addons itself is used as a single path.
#
# /mnt/enterprise-addons is prepended when non-empty (takes priority over extras).
# The computed path is both written to odoo.conf and printed to stdout.

ENV_FILE="/home/odoo/.env"
ODOO_CONF="/etc/odoo/odoo.conf"

if [ ! -f "$ENV_FILE" ]; then
    exit 0
fi

source "$ENV_FILE"

PATHS=""

if [ -d "/mnt/enterprise-addons" ] && [ "$(find /mnt/enterprise-addons -mindepth 1 -not -name '.*' 2>/dev/null | head -n 1)" ]; then
    PATHS="/mnt/enterprise-addons"
fi

if [ -d "/mnt/extra-addons" ]; then
    if [ "${SCAN_SUBFOLDERS}" = "true" ]; then
        FOUND_PATHS=""
        while IFS= read -r manifest; do
            MODULE_DIR=$(dirname "$manifest")
            PARENT_DIR=$(dirname "$MODULE_DIR")
            if [ -n "$PARENT_DIR" ] && [ "$PARENT_DIR" != "/mnt/extra-addons" ]; then
                if [[ ",${FOUND_PATHS}," != *",${PARENT_DIR},"* ]]; then
                    FOUND_PATHS="${FOUND_PATHS}${FOUND_PATHS:+,}${PARENT_DIR}"
                fi
            elif [ "$PARENT_DIR" = "/mnt/extra-addons" ]; then
                if [[ ",${FOUND_PATHS}," != *",/mnt/extra-addons,"* ]]; then
                    FOUND_PATHS="${FOUND_PATHS}${FOUND_PATHS:+,}/mnt/extra-addons"
                fi
            fi
        done < <(find /mnt/extra-addons \( -name "__manifest__.py" -o -name "__openerp__.py" \) 2>/dev/null)

        if [ -n "$FOUND_PATHS" ]; then
            PATHS="${PATHS}${PATHS:+,}${FOUND_PATHS}"
        fi
    else
        if find /mnt/extra-addons -maxdepth 2 \( -name "__manifest__.py" -o -name "__openerp__.py" \) -print -quit 2>/dev/null | grep -q .; then
            PATHS="${PATHS}${PATHS:+,}/mnt/extra-addons"
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
