#!/bin/bash

# -----------------------------------------------------------------------------
# Script to connect to a PostgreSQL database inside a Docker container (db)
# Usage:
#   psql [-d DBNAME] [additional psql arguments]
# Options:
#   -d DBNAME : Database name (optional, default: "main")
#   Any other arguments will be passed directly to the psql command.
# -----------------------------------------------------------------------------

# Default database name
DBNAME="main"

# Array to store additional arguments passed to the script
ARGS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -d)
            # If -d is provided, use the next argument as database name
            DBNAME="$2"
            shift 2  # Shift twice to skip both -d and DBNAME
            ;;
        *)
            # Collect any other arguments to pass them to psql
            ARGS+=("$1")
            shift  # Move to next argument
            ;;
    esac
done

# Execute psql inside the 'db' container, connecting to the specified database
# -d "$DBNAME" specifies the database to connect to
# -U odoo specifies the user (adjust if needed)
# "${ARGS[@]}" passes any additional arguments given to this script to psql
docker exec -it db psql -d "$DBNAME" -U odoo "${ARGS[@]}"
