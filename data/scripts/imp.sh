#!/bin/bash

# -----------------------------------------------------------------------------
# Script to import a PostgreSQL database dump from /home/odoo/db_zip into a new database.
# Usage:
#   import DBNAME [-na] [-s]
# Options:
#   DBNAME : Name of the database to create and import into (required)
#   -na    : No anonymization (optional, skip anonymization)
#   -s     : Switch Odoo to this database and restart Odoo (optional)
# -----------------------------------------------------------------------------

ZIP_DIR="/home/odoo/db_zip"
TMP_DIR="/home/odoo/db_zip/tmp"
ODOO_ENV_FILE="/home/odoo/.env"
FILESTORE_BASE="/home/odoo/data/odoo/filestore"

NEW_DB_NAME="$1"
NO_ANON=false
SWITCH=false

if [ -z "$NEW_DB_NAME" ]; then
  echo "❌ No database name provided."
  echo "Usage: import DBNAME [-na] [-s]"
  exit 1
fi
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    -na)
      NO_ANON=true
      shift
      ;;
    -s)
      SWITCH=true
      shift
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: import DBNAME [-na] [-s]"
      exit 1
      ;;
  esac
done

ZIP_LIST=($(find "$ZIP_DIR" -maxdepth 1 -type f -name "*.zip" ! -name "*out_*.zip"))
ZIP_COUNT=${#ZIP_LIST[@]}

if [ "$ZIP_COUNT" -eq 0 ]; then
  echo "❌ No zip file available for import in $ZIP_DIR."
  exit 1
fi

SELECTED_ZIP=""
if [ "$ZIP_COUNT" -eq 1 ]; then
  SELECTED_ZIP="${ZIP_LIST[0]}"
else
  echo "Multiple zip files found:"
  for i in "${!ZIP_LIST[@]}"; do
    echo "$((i+1)). $(basename "${ZIP_LIST[$i]}")"
  done
  read -p "Select a zip file to import [1-$ZIP_COUNT]: " SELECTION
  if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$ZIP_COUNT" ]; then
    SELECTED_ZIP="${ZIP_LIST[$((SELECTION-1))]}"
  else
    echo "❌ Invalid selection."
    exit 1
  fi
fi

echo "📦 Selected zip file: $SELECTED_ZIP"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

echo "📦 Extracting $SELECTED_ZIP..."
unzip -o "$SELECTED_ZIP" -d "$TMP_DIR"

SQL_FILE="${TMP_DIR}/dump.sql"
if [ ! -f "$SQL_FILE" ]; then
  echo "❌ No dump.sql file found inside $SELECTED_ZIP."
  exit 1
fi

echo "🚧 Creating database: $NEW_DB_NAME..."
docker exec db psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS \"$NEW_DB_NAME\";"
docker exec db psql -U odoo -d postgres -c "CREATE DATABASE \"$NEW_DB_NAME\" OWNER odoo;"

echo "📥 Importing dump into $NEW_DB_NAME..."
docker exec -i db psql -U odoo -d "$NEW_DB_NAME" < "$SQL_FILE"

if [[ "$NO_ANON" = false && "$SELECTED_ZIP" != *"anon_"* ]]; then
  echo "🧹 Anonymizing data in $NEW_DB_NAME..."

  docker exec db psql -U odoo -d "$NEW_DB_NAME" -c "
    UPDATE res_partner SET email = false WHERE email IS NOT NULL;
    UPDATE res_users SET login = 'admin' WHERE id = 2;
    UPDATE res_users SET password = 'admin' WHERE id = 2;
    UPDATE ir_cron SET active = false WHERE active IS NOT NULL;
    UPDATE ir_mail_server SET active = false WHERE active IS NOT NULL;
    UPDATE fetchmail_server SET active = false WHERE active IS NOT NULL;
  "

  echo "✅ Anonymization done."
else
  echo "ℹ️ Skipping anonymization (already anonymized or -na provided)."
fi

# ✅ Gestion du filestore
FILESTORE_SRC="${TMP_DIR}/filestore"
FILESTORE_DST="${FILESTORE_BASE}/${NEW_DB_NAME}"

if [ -d "$FILESTORE_SRC" ]; then
  echo "📂 Filestore found. Copying content to $FILESTORE_DST..."
  mkdir -p "$FILESTORE_DST"
  cp -r "$FILESTORE_SRC/"* "$FILESTORE_DST/"
  echo "✅ Filestore copied."
else
  echo "ℹ️ No filestore found in the archive. Skipping."
fi

# ✅ Switch to the new DB in .env if requested
if $SWITCH; then
  echo "🔄 Switching Odoo to use database: $NEW_DB_NAME"

  TMP_FILE="${ODOO_ENV_FILE}.tmp"
  > "$TMP_FILE"

  # Recopie toutes les lignes sauf SELECTED_DB
  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" != SELECTED_DB=* ]]; then
      echo "$line" >> "$TMP_FILE"
    fi
  done < "$ODOO_ENV_FILE"

  # Ajoute la nouvelle ligne SELECTED_DB
  echo "SELECTED_DB=$NEW_DB_NAME" >> "$TMP_FILE"

  # Réécrit le fichier .env proprement
  cat "$TMP_FILE" > "$ODOO_ENV_FILE"
  rm "$TMP_FILE"

  echo "✅ $ODOO_ENV_FILE updated to SELECTED_DB=$NEW_DB_NAME"

  echo "🚀 Restarting Odoo..."
  docker compose restart odoo

  if [ $? -eq 0 ]; then
    echo "✅ Odoo restarted successfully with database '$NEW_DB_NAME'."
  else
    echo "❌ Failed to restart Odoo."
    exit 1
  fi
else
  echo "ℹ️ Database '$NEW_DB_NAME' imported but not set as active (use -s to switch)."
fi

rm -rf "$TMP_DIR"

echo "✅ Import completed successfully for database '$NEW_DB_NAME'."
