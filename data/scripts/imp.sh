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

# ✅ Liste des fichiers valides (sql direct ou archives)
ZIP_LIST=($(find "$ZIP_DIR" -maxdepth 1 -type f \( -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" -o -iname "*.sql" \) ! -name "*out_*"))
ZIP_COUNT=${#ZIP_LIST[@]}

if [ "$ZIP_COUNT" -eq 0 ]; then
  echo "❌ No valid file available for import in $ZIP_DIR."
  exit 1
fi

# ✅ Sélection du fichier
SELECTED_FILE=""
if [ "$ZIP_COUNT" -eq 1 ]; then
  SELECTED_FILE="${ZIP_LIST[0]}"
else
  echo "Multiple valid files found:"
  for i in "${!ZIP_LIST[@]}"; do
    echo "$((i+1)). $(basename "${ZIP_LIST[$i]}")"
  done
  read -p "Select a file to import [1-$ZIP_COUNT]: " SELECTION
  if [[ "$SELECTION" =~ ^[0-9]+$ ]] && [ "$SELECTION" -ge 1 ] && [ "$SELECTION" -le "$ZIP_COUNT" ]; then
    SELECTED_FILE="${ZIP_LIST[$((SELECTION-1))]}"
  else
    echo "❌ Invalid selection."
    exit 1
  fi
fi

echo "📦 Selected file: $SELECTED_FILE"

# ✅ Cas fichier SQL direct
if [[ "$SELECTED_FILE" =~ \.sql$ ]]; then
  SQL_FILE="$SELECTED_FILE"
  FILESTORE_FOUND=false
else
  # ✅ Cas archive compressée
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
  
  EXT="${SELECTED_FILE##*.}"
  echo "📂 Extracting $SELECTED_FILE..."
  case "$EXT" in
    "zip") unzip -o "$SELECTED_FILE" -d "$TMP_DIR" ;;
    "7z")  7z x "$SELECTED_FILE" -o"$TMP_DIR" ;;
    "gz"|"tgz") tar -xzf "$SELECTED_FILE" -C "$TMP_DIR" ;;
    *) echo "❌ Unsupported archive format: $EXT"; exit 1 ;;
  esac

  # ✅ Recherche du fichier SQL
  SQL_FILE=$(find "$TMP_DIR" -type f -iname "*.sql" | head -n 1)
  if [ -z "$SQL_FILE" ]; then
    echo "❌ No SQL file found inside the archive."
    exit 1
  fi
  echo "🗄️ Found SQL file: $(basename "$SQL_FILE")"

  # ✅ Vérifie si filestore présent
  FILESTORE_FOUND=$(find "$TMP_DIR" -type d -name "filestore" | head -n 1)
fi

# ✅ Création et import de la DB
echo "🚧 Creating database: $NEW_DB_NAME..."
docker exec db psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS \"$NEW_DB_NAME\";"
docker exec db psql -U odoo -d postgres -c "CREATE DATABASE \"$NEW_DB_NAME\" OWNER odoo;"

echo "📥 Importing dump into $NEW_DB_NAME..."
docker exec -i db psql -U odoo -d "$NEW_DB_NAME" < "$SQL_FILE"

# ✅ Anonymisation si nécessaire
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
  echo "📂 Filestore found. Copying content to /filestore/$NEW_DB_NAME..."
  mkdir -p "$FILESTORE_BASE/$NEW_DB_NAME"
  cp -r "$FILESTORE_FOUND/"* "$FILESTORE_BASE/$NEW_DB_NAME/"
  echo "✅ Filestore copied."
else
  echo "ℹ️ No filestore found. Skipping."
fi

# ✅ Mise à jour du .env si besoin
if $SWITCH; then
  echo "🔄 Switching Odoo to use database: $NEW_DB_NAME"

  TMP_FILE="${ODOO_ENV_FILE}.tmp"
  > "$TMP_FILE"

  while IFS= read -r line || [ -n "$line" ]; do
    if [[ "$line" != SELECTED_DB=* ]]; then
      echo "$line" >> "$TMP_FILE"
    fi
  done < "$ODOO_ENV_FILE"

  echo "SELECTED_DB=$NEW_DB_NAME" >> "$TMP_FILE"

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

# ✅ Nettoyage si archive
if [[ ! "$SELECTED_FILE" =~ \.sql$ ]]; then
  rm -rf "$TMP_DIR"
fi

echo "✅ Import completed successfully for database '$NEW_DB_NAME'."
