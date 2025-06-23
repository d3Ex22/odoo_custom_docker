#!/bin/bash

# -----------------------------------------------------------------------------
# Script to duplicate a PostgreSQL database inside a Docker container (db)
# Usage:
#   copy NEW_DB_NAME [-d SOURCE_DB_NAME] [-s]
# Options:
#   NEW_DB_NAME  : The name of the new database to create (required)
#   -d SOURCE_DB : The source database to copy from (optional, fallback to SELECTED_DB in /home/odoo/.env)
#   -s           : Switch SELECTED_DB in .env to NEW_DB_NAME and restart Odoo
# -----------------------------------------------------------------------------

# Default values
SOURCE_DB=""
NEW_DB_NAME="$1"
SWITCH=false
ODOO_ENV_FILE="/home/odoo/.env"

# ✅ Check if NEW_DB_NAME is provided
if [ -z "$NEW_DB_NAME" ]; then
  echo "❌ No target database name provided."
  echo "Usage: copy NEW_DB_NAME [-d SOURCE_DB_NAME] [-s]"
  exit 1
fi

shift  # Process next arguments (e.g., -d or -s option)

# ✅ Parse additional arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      SOURCE_DB="$2"
      shift 2
      ;;
    -s)
      SWITCH=true
      shift
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: copy NEW_DB_NAME [-d SOURCE_DB_NAME] [-s]"
      exit 1
      ;;
  esac
done

# ✅ Load SOURCE_DB from .env if not provided
if [ -z "$SOURCE_DB" ]; then
  if [ -f "$ODOO_ENV_FILE" ]; then
    SOURCE_DB=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
  fi
fi

# ✅ Check if SOURCE_DB is set
if [ -z "$SOURCE_DB" ]; then
  echo "❌ No source database name provided and no SELECTED_DB found in $ODOO_ENV_FILE."
  exit 1
fi

# ✅ Check if SOURCE_DB exists
SOURCE_DB_EXISTS=$(docker exec db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$SOURCE_DB';")

if [ "$SOURCE_DB_EXISTS" != "1" ]; then
  echo "❌ Source database '$SOURCE_DB' does not exist."
  exit 1
fi

# ✅ Check if NEW_DB_NAME already exists
NEW_DB_EXISTS=$(docker exec db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$NEW_DB_NAME';")

if [ "$NEW_DB_EXISTS" == "1" ]; then
  echo "❌ Target database '$NEW_DB_NAME' already exists."
  exit 1
fi

echo "✅ Source database: $SOURCE_DB"
echo "✅ Target database to create: $NEW_DB_NAME"

# 🚀 Duplicate the database
echo "🚀 Duplicating database '$SOURCE_DB' into '$NEW_DB_NAME'..."
docker exec db psql -U odoo -d postgres -c "CREATE DATABASE \"$NEW_DB_NAME\" WITH TEMPLATE \"$SOURCE_DB\" OWNER odoo;"

if [ $? -eq 0 ]; then
  echo "✅ Database '$NEW_DB_NAME' successfully created from '$SOURCE_DB'."
else
  echo "❌ Failed to duplicate the database."
  exit 1
fi

# 🔄 Switch SELECTED_DB in .env if -s option is provided
if $SWITCH; then
  echo "🔄 Switching SELECTED_DB to '$NEW_DB_NAME' in $ODOO_ENV_FILE..."

  TMP_FILE="${ODOO_ENV_FILE}.tmp"
  > "$TMP_FILE"  # Vide le fichier temporaire

  # Recopie tout sauf SELECTED_DB
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" != SELECTED_DB=* ]]; then
      echo "$line" >> "$TMP_FILE"
    fi
  done < "$ODOO_ENV_FILE"

  # Ajout de la nouvelle ligne SELECTED_DB
  echo "SELECTED_DB=$NEW_DB_NAME" >> "$TMP_FILE"

  # Remplacement final du fichier .env
  cat "$TMP_FILE" > "$ODOO_ENV_FILE"
  rm "$TMP_FILE"

  echo "✅ $ODOO_ENV_FILE updated to SELECTED_DB=$NEW_DB_NAME"

  # ✅ Restart Odoo
  echo "🚀 Restarting Odoo with new database '$NEW_DB_NAME'..."
  docker compose restart odoo

  if [ $? -eq 0 ]; then
    echo "✅ Odoo restarted successfully with database '$NEW_DB_NAME'."
  else
    echo "❌ Failed to restart Odoo."
    exit 1
  fi
else
  echo "ℹ️ No switch requested. You can use 'switch $NEW_DB_NAME' to activate it."
fi
