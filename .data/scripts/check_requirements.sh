#!/bin/bash

# Install Python dependencies from requirements.txt files found in the addons base dir.
#
# Receives the addons base directory as $1 (defaults to /mnt/extra-addons).
# Searches recursively for all requirements.txt files, installing from deepest
# to shallowest to respect potential overrides.
# Skips installation if the combined hash of all found files matches the cached hash
# AND all listed packages are already installed.
# Uses uv pip for fast parallel installation.

HASH_FILE="/var/odoo/cache/.requirements_hash"
BASE_DIR="${1:-/mnt/extra-addons}"

REQ_FILES=()
if [ -d "$BASE_DIR" ]; then
    while IFS= read -r REQ; do
        grep -qvE '^\s*(#|$)' "$REQ" 2>/dev/null && REQ_FILES+=("$REQ")
    done < <(find "$BASE_DIR" -name "requirements.txt" -type f | awk -F'/' '{print NF, $0}' | sort -rn | cut -d' ' -f2-)
fi

if [ ${#REQ_FILES[@]} -eq 0 ]; then
    echo "No requirements.txt found in $BASE_DIR, skipping"
    exit 0
fi

NEW_HASH=$(cat "${REQ_FILES[@]}" | md5sum | cut -d' ' -f1)

if [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE")" = "$NEW_HASH" ]; then
    MISSING=0
    for REQ in "${REQ_FILES[@]}"; do
        while IFS= read -r line; do
            [[ -z "$line" || "$line" == "#"* ]] && continue
            PKG=$(echo "$line" | sed 's/[<>=!].*//' | tr -d ' ')
            [ -z "$PKG" ] && continue
            if ! uv pip show "$PKG" >/dev/null 2>&1; then
                MISSING=1
                break 2
            fi
        done < "$REQ"
    done
    if [ "$MISSING" -eq 0 ]; then
        echo "Requirements unchanged, skipping pip install"
        exit 0
    fi
fi

SUCCESS=1
for REQ in "${REQ_FILES[@]}"; do
    echo "Installing requirements from $REQ..."
    uv pip install -r "$REQ" || SUCCESS=0
done

if [ "$SUCCESS" -eq 1 ]; then
    echo "$NEW_HASH" > "$HASH_FILE"
    echo "Requirements installed successfully"
else
    echo "Warning: Some requirements may have failed to install"
fi
