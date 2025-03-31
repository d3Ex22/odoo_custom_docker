#!/bin/bash

# -----------------------------------------------------------------------------
# Script to connect to a PostgreSQL database inside a Docker container (db)
# Usage:
#   psql [-d DBNAME] [additional psql arguments]
# Options:
#   -d DBNAME : Database name (optional, fallback to SELECTED_DB in .env)
#   Any other arguments will be passed directly to the psql command.
# -----------------------------------------------------------------------------

ENV_FILE="/home/odoo/.env"
DBNAME=""
ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d)
            DBNAME="$2"
            shift 2
            ;;
        *)
            ARGS+=("$1")
            shift
            ;;
    esac
done

# If no DBNAME was passed, get it from .env
if [ -z "$DBNAME" ]; then
    if [ -f "$ENV_FILE" ]; then
        DBNAME=$(grep '^SELECTED_DB=' "$ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
    fi
fi

# If still not defined, show error
if [ -z "$DBNAME" ]; then
    echo "❌ No database name provided and no SELECTED_DB found in $ENV_FILE"
    exit 1
fi

# Connect via docker exec
docker exec -it db psql -d "$DBNAME" -U odoo "${ARGS[@]}"
