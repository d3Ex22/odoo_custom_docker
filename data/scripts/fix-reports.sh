#!/bin/bash

# -----------------------------------------------------------------------------
# Script to check, insert, or update 'report.url' in ir_config_parameter.
# Usage:
#   fix-reports [-f]
# Options:
#   -f : Force replacement if key exists.
# -----------------------------------------------------------------------------

# Variables
ODOO_ENV_FILE="/home/odoo/.env"
DB_PARAM_KEY="report.url"
DB_PARAM_VALUE="http://0.0.0.0:8069"
FORCE=false

# ✅ Parse options
while [[ $# -gt 0 ]]; do
  case "$1" in
    -f)
      FORCE=true
      shift
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: fix-reports [-f]"
      exit 1
      ;;
  esac
done

# ✅ Load SELECTED_DB from .env
if [ -f "$ODOO_ENV_FILE" ]; then
  SELECTED_DB=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
else
  echo "❌ File $ODOO_ENV_FILE not found."
  exit 1
fi

# ✅ Check that SELECTED_DB is set
if [ -z "$SELECTED_DB" ]; then
  echo "❌ No SELECTED_DB found in $ODOO_ENV_FILE."
  exit 1
fi

echo "📂 Targeting database: $SELECTED_DB"
echo "🔍 Checking for key '$DB_PARAM_KEY' in table 'ir_config_parameter'..."

# ✅ Check if the key exists and retrieve its current value
EXISTING_VALUE=$(docker exec db psql -U odoo -d "$SELECTED_DB" -tAc "
  SELECT value FROM ir_config_parameter WHERE key = '$DB_PARAM_KEY';
" | xargs)

if [ -n "$EXISTING_VALUE" ]; then
  echo "✅ Key '$DB_PARAM_KEY' already exists in table 'ir_config_parameter'."
  echo "   Current value: '$EXISTING_VALUE'"
  echo "   Desired value: '$DB_PARAM_VALUE'"

  if $FORCE; then
    echo "⚙️  Force option enabled. Replacing existing value..."
    docker exec db psql -U odoo -d "$SELECTED_DB" -c "
      DELETE FROM ir_config_parameter WHERE key = '$DB_PARAM_KEY';
    "
    docker exec db psql -U odoo -d "$SELECTED_DB" -c "
      INSERT INTO ir_config_parameter (key, value, create_date, write_date)
      VALUES ('$DB_PARAM_KEY', '$DB_PARAM_VALUE', NOW(), NOW());
    "
    if [ $? -eq 0 ]; then
      echo "✅ Key '$DB_PARAM_KEY' successfully updated to '$DB_PARAM_VALUE'."
    else
      echo "❌ Failed to update key '$DB_PARAM_KEY'."
      exit 1
    fi
  else
    echo "ℹ️ To force update this value, re-run the script with '-f'."
  fi
else
  echo "➕ Key '$DB_PARAM_KEY' does not exist. Inserting it with value '$DB_PARAM_VALUE'..."
  docker exec db psql -U odoo -d "$SELECTED_DB" -c "
    INSERT INTO ir_config_parameter (key, value, create_date, write_date)
    VALUES ('$DB_PARAM_KEY', '$DB_PARAM_VALUE', NOW(), NOW());
  "
  if [ $? -eq 0 ]; then
    echo "✅ Key '$DB_PARAM_KEY' successfully inserted with value '$DB_PARAM_VALUE'."
  else
    echo "❌ Failed to insert key '$DB_PARAM_KEY'."
    exit 1
  fi
fi
