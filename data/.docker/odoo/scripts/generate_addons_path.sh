#!/bin/bash

ENV_FILE="/home/odoo/.env"
ODOO_CONF="/etc/odoo/odoo.conf"

if [ ! -f "$ENV_FILE" ]; then
    exit 0
fi

source "$ENV_FILE"

PATHS=""

if [ -d "/mnt/enterprise-addons" ] && [ "$(ls -A /mnt/enterprise-addons 2>/dev/null)" ]; then
    PATHS="/mnt/enterprise-addons"
fi

if [ -d "/mnt/extra-addons" ]; then
    if [ "${SCAN_SUBFOLDERS:-false}" = "true" ]; then
        FOUND_PATHS=""
        while IFS= read -r manifest; do
            MODULE_DIR=$(dirname "$manifest")
            PARENT_DIR=$(dirname "$MODULE_DIR")
            if [ -n "$PARENT_DIR" ] && [ "$PARENT_DIR" != "/mnt/extra-addons" ]; then
                if [[ ! "$FOUND_PATHS" =~ "$PARENT_DIR" ]]; then
                    FOUND_PATHS="${FOUND_PATHS}${FOUND_PATHS:+,}${PARENT_DIR}"
                fi
            elif [ "$PARENT_DIR" = "/mnt/extra-addons" ]; then
                if [[ ! "$FOUND_PATHS" =~ "/mnt/extra-addons" ]]; then
                    FOUND_PATHS="${FOUND_PATHS}${FOUND_PATHS:+,}/mnt/extra-addons"
                fi
            fi
        done < <(find /mnt/extra-addons -name "__manifest__.py" -o -name "__openerp__.py" 2>/dev/null)
        
        if [ -n "$FOUND_PATHS" ]; then
            PATHS="${PATHS}${PATHS:+,}${FOUND_PATHS}"
        fi
    else
        if [ "$(ls -A /mnt/extra-addons 2>/dev/null)" ]; then
            PATHS="${PATHS}${PATHS:+,}/mnt/extra-addons"
        fi
    fi
fi

if [ -z "$PATHS" ]; then
    PATHS="/mnt/extra-addons"
fi

if [ -f "$ODOO_CONF" ]; then
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
