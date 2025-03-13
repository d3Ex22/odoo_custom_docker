#!/bin/bash

# -----------------------------------------------------------------------------
# Script to check if 'report.url' exists in ir_config_parameter and insert it if not.
# Usage:
#   ./set_report_url.sh
# -----------------------------------------------------------------------------

# Variables
ODOO_ENV_FILE="/home/odoo/.env"
DB_PARAM_KEY="report.url"
DB_PARAM_VALUE="http://0.0.0.0:8069"

# ✅ Charger SELECTED_DB depuis .env
if [ -f "$ODOO_ENV_FILE" ]; then
  SELECTED_DB=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
else
  echo "❌ File $ODOO_ENV_FILE not found."
  exit 1
fi

# ✅ Vérifier que SELECTED_DB est bien défini
if [ -z "$SELECTED_DB" ]; then
  echo "❌ No SELECTED_DB found in $ODOO_ENV_FILE."
  exit 1
fi

echo "📂 Targeting database: $SELECTED_DB"

# ✅ Vérifier si la clé existe déjà
EXISTS=$(docker exec db psql -U odoo -d "$SELECTED_DB" -tAc "SELECT 1 FROM ir_config_parameter WHERE key = '$DB_PARAM_KEY';")

if [ "$EXISTS" == "1" ]; then
  echo "✅ The key '$DB_PARAM_KEY' already exists in the database."
else
  echo "➕ Inserting '$DB_PARAM_KEY' with value '$DB_PARAM_VALUE'..."
  docker exec db psql -U odoo -d "$SELECTED_DB" -c "
    INSERT INTO ir_config_parameter (create_uid, write_uid, key, value, create_date, write_date)
    VALUES (1, 1, '$DB_PARAM_KEY', '$DB_PARAM_VALUE', NOW(), NOW());
  "
  if [ $? -eq 0 ]; then
    echo "✅ Key '$DB_PARAM_KEY' successfully inserted."
  else
    echo "❌ Failed to insert key '$DB_PARAM_KEY'."
    exit 1
  fi
fi
