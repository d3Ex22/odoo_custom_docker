#!/bin/bash

# -----------------------------------------------------------------------------
# Script to switch the Odoo database (update SELECTED_DB in .env and restart Odoo)
# Usage:
#   switch DBNAME [-y]
# Options:
#   DBNAME : The new database name to set as SELECTED_DB (required)
#   -y     : Force switch without confirmation (create if doesn't exist, switch if exists)
# -----------------------------------------------------------------------------

ODOO_ENV_FILE="/home/odoo/.env"
NEW_DB_NAME=""
CONFIRM=true

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y)
      CONFIRM=false
      shift
      ;;
    *)
      if [ -z "$NEW_DB_NAME" ]; then
        NEW_DB_NAME="$1"
        shift
      else
        echo "❌ Unknown option: $1"
        echo "Usage: switch DBNAME [-y]"
        exit 1
      fi
      ;;
  esac
done

# ✅ Vérification que le nom de la DB est bien fourni
if [ -z "$NEW_DB_NAME" ]; then
  echo "❌ No database name provided."
  echo "Usage: switch DBNAME [-y]"
  exit 1
fi

# 🔄 Lecture de l'ancien SELECTED_DB pour information
CURRENT_DB=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
echo "📦 Current SELECTED_DB in .env: $CURRENT_DB"

# 🔎 Vérification que la DB existe bien dans PostgreSQL
echo "🔎 Checking if database '$NEW_DB_NAME' exists..."
DB_EXISTS=$(docker exec db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$NEW_DB_NAME';")

if [ "$DB_EXISTS" != "1" ]; then
  echo "⚠️ Database '$NEW_DB_NAME' does not exist."
  if $CONFIRM; then
    read -p "❓ Do you want to switch and let Odoo create this new database? (yes/[no]): " answer
    if [[ "$answer" != "yes" ]]; then
      echo "❌ Aborted."
      exit 1
    fi
  else
    echo "✅ Proceeding to switch and let Odoo create this new database (forced mode)."
  fi
else
  echo "✅ Database '$NEW_DB_NAME' exists."
  if $CONFIRM; then
    read -p "❓ Do you want to switch to this existing database? (yes/[no]): " answer
    if [[ "$answer" != "yes" ]]; then
      echo "❌ Aborted."
      exit 1
    fi
  else
    echo "✅ Proceeding to switch to existing database (forced mode)."
  fi
fi

# ✅ Confirmation de la bascule
echo "ℹ️ Switching from '$CURRENT_DB' to '$NEW_DB_NAME'."

# 🔧 Remplacement propre via cat (sans sed, sans toucher aux autres lignes)
TMP_FILE="${ODOO_ENV_FILE}.tmp"
> "$TMP_FILE"  # Vide le fichier temporaire

while IFS= read -r line || [ -n "$line" ]; do
  if [[ "$line" != SELECTED_DB=* ]]; then
    echo "$line" >> "$TMP_FILE"
  fi
done < "$ODOO_ENV_FILE"

# Ajout de la nouvelle ligne SELECTED_DB
echo "SELECTED_DB=$NEW_DB_NAME" >> "$TMP_FILE"

# Remplacement final
cat "$TMP_FILE" > "$ODOO_ENV_FILE"
rm "$TMP_FILE"

echo "✅ $ODOO_ENV_FILE updated to SELECTED_DB=$NEW_DB_NAME"

# ✅ Restart Odoo pour prendre en compte la nouvelle DB
echo "🚀 Restarting Odoo with new database '$NEW_DB_NAME'..."
docker compose restart odoo

if [ $? -eq 0 ]; then
  echo "✅ Odoo restarted successfully with database '$NEW_DB_NAME'."
else
  echo "❌ Failed to restart Odoo."
  exit 1
fi

echo "🎉 Database switch to '$NEW_DB_NAME' completed successfully."
