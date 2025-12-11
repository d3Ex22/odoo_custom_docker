#!/bin/bash

REQUIREMENTS_FILE="/mnt/extra-addons/requirements.txt"
HASH_FILE="/var/lib/odoo/cache/.requirements_hash"

if [ ! -f "$REQUIREMENTS_FILE" ]; then
    echo "No requirements.txt found, skipping pip install"
    exit 0
fi

NEW_HASH=$(md5sum "$REQUIREMENTS_FILE" | cut -d' ' -f1)

if [ -f "$HASH_FILE" ]; then
    STORED_HASH=$(cat "$HASH_FILE")
    if [ "$NEW_HASH" = "$STORED_HASH" ]; then
        MISSING=0
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            PKG=$(echo "$line" | sed 's/[<>=].*//')
            [ -z "$PKG" ] && continue
            if ! pip show "$PKG" >/dev/null 2>&1; then
                MISSING=1
                break
            fi
        done < "$REQUIREMENTS_FILE"
        if [ "$MISSING" -eq 0 ]; then
            echo "Requirements unchanged, skipping pip install"
            exit 0
        fi
    fi
fi

echo "Installing requirements from $REQUIREMENTS_FILE..."
pip install -r "$REQUIREMENTS_FILE"

if [ $? -eq 0 ]; then
    echo "$NEW_HASH" > "$HASH_FILE"
    echo "Requirements installed successfully"
else
    echo "Warning: Some requirements may have failed to install"
fi
