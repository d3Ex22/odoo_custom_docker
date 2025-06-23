#!/bin/bash

# -----------------------------------------------------------------------------
# Script to anonymize all PostgreSQL Odoo database dumps found in /home/odoo/db_zip.
# Will ignore any zip files starting with 'anon_' or 'out_'.
# Usage:
#   anon
# -----------------------------------------------------------------------------

# Chemins et fichiers
ZIP_DIR="/home/odoo/db_zip"
TMP_DIR="/home/odoo/db_zip/tmp"
TMP_DB="anon_tmp_db"  # Nom temporaire unique pour travailler

# ✅ Boucle sur chaque zip qui ne commence PAS par 'anon_' ou 'out_'
for DB_ZIP in $(find "$ZIP_DIR" -maxdepth 1 -type f -name "*.zip" ! -name "anon_*.zip" ! -name "out_*.zip"); do
  echo "📂 Found zip file to process: $DB_ZIP"

  # ✅ Nettoyer et préparer le dossier temporaire
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"

  # ✅ Extraire le zip
  echo "📦 Extracting $DB_ZIP..."
  unzip -o "$DB_ZIP" -d "$TMP_DIR"

  # ✅ Vérifier le fichier SQL dump
  SQL_FILE="${TMP_DIR}/dump.sql"

  if [ ! -f "$SQL_FILE" ]; then
    echo "❌ No dump.sql file found inside $DB_ZIP. Skipping."
    continue  # Passer au zip suivant
  fi

  echo "🗄️ Found SQL dump: $SQL_FILE"

  # ✅ Créer la base temporaire
  echo "🚧 Creating temporary database: $TMP_DB..."
  docker exec db psql -U odoo -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_DB\";"
  docker exec db psql -U odoo -d postgres -c "CREATE DATABASE \"$TMP_DB\" OWNER odoo;"

  # ✅ Importer le dump
  echo "📥 Importing dump into $TMP_DB..."
  docker exec -i db psql -U odoo -d "$TMP_DB" < "$SQL_FILE"

  # ✅ Anonymisation avec TES commandes SQL
  echo "🧹 Starting Anonymization in $TMP_DB..."

  docker exec db psql -U odoo -d "$TMP_DB" -c "
    UPDATE res_partner SET email = false WHERE email IS NOT NULL;
    UPDATE res_users SET login = 'admin' WHERE id = 2;
    UPDATE res_users SET password = 'admin' WHERE id = 2;
    UPDATE ir_cron SET active = false WHERE active IS NOT NULL;
    UPDATE ir_mail_server SET active = false WHERE active IS NOT NULL;
    UPDATE fetchmail_server SET active = false WHERE active IS NOT NULL;
  "

  echo "✅ Anonymization done for $DB_ZIP."

  # ✅ Remplacer dump.sql par le dump anonymisé
  echo "📤 Exporting anonymized database into dump.sql..."
  docker exec db pg_dump -U odoo "$TMP_DB" > "$SQL_FILE"

  # ✅ Générer le nom du zip anonymisé en préfixant "anon_"
  ORIGINAL_BASENAME=$(basename "$DB_ZIP")  # Récupère nom du zip sans chemin
  ANON_ZIP="${ZIP_DIR}/anon_${ORIGINAL_BASENAME}"

  # ✅ Compresser l'intégralité du contenu du TMP_DIR en zip final
  echo "📦 Zipping entire content (including dump.sql) to $ANON_ZIP..."
  (cd "$TMP_DIR" && zip -r "$ANON_ZIP" .)

  # ✅ Supprimer la base temporaire
  echo "🗑️ Dropping temporary database $TMP_DB..."
  docker exec db psql -U odoo -d postgres -c "DROP DATABASE \"$TMP_DB\";"

  # ✅ Nettoyer les fichiers temporaires
  rm -rf "$TMP_DIR"

  # ✅ Supprimer le zip source
  echo "🗑️ Deleting source zip: $DB_ZIP"
  rm -f "$DB_ZIP"

  echo "✅ Done processing $DB_ZIP. Anonymized dump created: $ANON_ZIP"
  echo "------------------------------------------------------------"
done

echo "🎉 All eligible zips have been processed and anonymized."
