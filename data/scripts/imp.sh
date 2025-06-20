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

# ✅ Vérification que le nom de la DB est fourni
if [ -z "$NEW_DB_NAME" ]; then
  echo "❌ No database name provided."
  echo "Usage: import DBNAME [-na] [-s]"
  exit 1
fi
shift

# ✅ Gestion des options
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

# ✅ Recherche des fichiers valides
IMPORT_LIST=($(find "$ZIP_DIR" -maxdepth 1 -type f \( -iname "*.sql" -o -iname "*.dump" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" \) ! -name "*out_*"))
if [ ${#IMPORT_LIST[@]} -eq 0 ]; then
  echo "❌ No valid file found in $ZIP_DIR."
  exit 1
fi

# ✅ Sélection
SELECTED_FILE=""
if [ ${#IMPORT_LIST[@]} -eq 1 ]; then
  SELECTED_FILE="${IMPORT_LIST[0]}"
else
  echo "Multiple files found:"
  for i in "${!IMPORT_LIST[@]}"; do
    echo "$((i + 1)). $(basename "${IMPORT_LIST[$i]}")"
  done
  read -p "Select a file to import [1-${#IMPORT_LIST[@]}]: " CHOICE
  if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#IMPORT_LIST[@]} ]; then
    SELECTED_FILE="${IMPORT_LIST[$((CHOICE - 1))]}"
  else
    echo "❌ Invalid selection."
    exit 1
  fi
fi

echo "📦 Selected file: $(basename "$SELECTED_FILE")"

# ✅ Déterminer si c’est un fichier brut ou une archive
IS_ARCHIVE=false
EXT_LOWER=$(echo "$SELECTED_FILE" | tr '[:upper:]' '[:lower:]')

if [[ "$EXT_LOWER" =~ \.(zip|7z|tar\.gz|tgz)$ ]]; then
  IS_ARCHIVE=true
fi

# ✅ Extraction si archive
if $IS_ARCHIVE; then
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  echo "📂 Extracting archive..."
  case "$EXT_LOWER" in
    *.zip) unzip -o "$SELECTED_FILE" -d "$TMP_DIR" ;;
    *.7z)  7z x "$SELECTED_FILE" -o"$TMP_DIR" ;;
    *.tar.gz|*.tgz) tar -xzf "$SELECTED_FILE" -C "$TMP_DIR" ;;
    *) echo "❌ Unsupported archive format."; exit 1 ;;
  esac

  SQL_FILE=$(find "$TMP_DIR" -type f \( -iname "*.sql" -o -iname "*.dump" \) | head -n 1)
  if [ -z "$SQL_FILE" ]; then
    echo "❌ No .sql or .dump file found inside archive."
    exit 1
  fi

  FILESTORE_FOUND=$(find "$TMP_DIR" -type d -name "filestore" | head -n 1)
else
  SQL_FILE="$SELECTED_FILE"
  FILESTORE_FOUND=""
fi

# ✅ Création de la base
echo "🚧 Creating database: $NEW_DB_NAME..."
docker exec db psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS \"$NEW_DB_NAME\";"
docker exec db psql -U odoo -d postgres -c "CREATE DATABASE \"$NEW_DB_NAME\" OWNER odoo;"

# ✅ Import selon extension
echo "📥 Importing dump into $NEW_DB_NAME..."
EXT_SQL=$(echo "$SQL_FILE" | tr '[:upper:]' '[:lower:]')

if [[ "$EXT_SQL" =~ \.dump$ ]]; then
  docker exec -i db pg_restore -U odoo -d "$NEW_DB_NAME" --no-owner < "$SQL_FILE"
elif [[ "$EXT_SQL" =~ \.sql$ ]]; then
  docker exec -i db psql -U odoo -d "$NEW_DB_NAME" < "$SQL_FILE"
else
  echo "❌ Unknown file format for import: $SQL_FILE"
  exit 1
fi

# ✅ Anonymisation
if [[ "$NO_ANON" = false && "$SELECTED_FILE" != *"anon_"* ]]; then
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
if [ -n "$FILESTORE_FOUND" ]; then
  echo "📂 Copying filestore to $FILESTORE_BASE/$NEW_DB_NAME..."
  mkdir -p "$FILESTORE_BASE/$NEW_DB_NAME"
  cp -r "$FILESTORE_FOUND/"* "$FILESTORE_BASE/$NEW_DB_NAME/"
  echo "✅ Filestore copied."
else
  echo "ℹ️ No filestore found."
fi

# ✅ Mise à jour .env
if $SWITCH; then
  echo "🔄 Switching Odoo to use database: $NEW_DB_NAME"
  TMP_FILE="${ODOO_ENV_FILE}.tmp"
  > "$TMP_FILE"

  while IFS= read -r line || [ -n "$line" ]; do
    [[ "$line" != SELECTED_DB=* ]] && echo "$line" >> "$TMP_FILE"
  done < "$ODOO_ENV_FILE"

  echo "SELECTED_DB=$NEW_DB_NAME" >> "$TMP_FILE"
  cat "$TMP_FILE" > "$ODOO_ENV_FILE"
  rm "$TMP_FILE"

  echo "✅ Updated .env with SELECTED_DB=$NEW_DB_NAME"
  echo "🚀 Restarting Odoo..."
  docker compose restart odoo

  if [ $? -eq 0 ]; then
    echo "✅ Odoo restarted with new DB."
  else
    echo "❌ Failed to restart Odoo."
    exit 1
  fi
else
  echo "ℹ️ DB imported but not activated (use -s to switch)."
fi

# ✅ Cleanup
$IS_ARCHIVE && rm -rf "$TMP_DIR"

echo "✅ Import completed for database '$NEW_DB_NAME'."
