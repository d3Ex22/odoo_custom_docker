#!/bin/bash

# -----------------------------------------------------------------------------
# Script to export a PostgreSQL database into a zip file.
# Usage:
#   export [-d DBNAME]
# Options:
#   -d DBNAME : Database name to export (optional, fallback to SELECTED_DB in .env)
# -----------------------------------------------------------------------------

# Chemins et fichiers
ZIP_DIR="/home/odoo/db_zip"
TMP_DIR="/home/odoo/db_zip/tmp"
ODOO_ENV_FILE="/home/odoo/.env"
DBNAME=""
DATE_TAG=$(date +%Y%m%d_%H%M%S)

# ✅ Parse des arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -d)
      DBNAME="$2"
      shift 2
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: export [-d DBNAME]"
      exit 1
      ;;
  esac
done

# ✅ Charger DBNAME depuis .env si non fourni
if [ -z "$DBNAME" ]; then
  if [ -f "$ODOO_ENV_FILE" ]; then
    DBNAME=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
  fi
fi

# ✅ Vérifier que DBNAME est bien défini
if [ -z "$DBNAME" ]; then
  echo "❌ No database name provided and no SELECTED_DB found in $ODOO_ENV_FILE."
  exit 1
fi

echo "📦 Preparing to export database: $DBNAME"

# ✅ Vérifier que la DB existe
DB_EXISTS=$(docker exec db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DBNAME';")
if [ "$DB_EXISTS" != "1" ]; then
  echo "❌ Database '$DBNAME' does not exist."
  exit 1
fi

# ✅ Préparer les dossiers temporaires
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

# ✅ Chemins des fichiers temporaires et finaux
EXPORT_SQL="${TMP_DIR}/dump.sql"
EXPORT_ZIP="${ZIP_DIR}/out_${DBNAME}_${DATE_TAG}.zip"

# ✅ Exporter la base
echo "📤 Exporting database '$DBNAME' to SQL file..."
docker exec db pg_dump -U odoo "$DBNAME" > "$EXPORT_SQL"

# ✅ Vérification
if [ $? -ne 0 ]; then
  echo "❌ Failed to export database '$DBNAME'."
  rm -rf "$TMP_DIR"
  exit 1
fi

# ✅ Compresser en zip
echo "📦 Compressing SQL dump to $EXPORT_ZIP..."
zip -j "$EXPORT_ZIP" "$EXPORT_SQL"

# ✅ Nettoyage des fichiers temporaires
rm -rf "$TMP_DIR"

echo "✅ Database '$DBNAME' exported successfully to $EXPORT_ZIP"
