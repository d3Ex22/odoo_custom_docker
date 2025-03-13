#!/bin/bash

# -----------------------------------------------------------------------------
# Script to bypass Odoo expiration date and disable publisher cron
# Usage:
#   cheat
# -----------------------------------------------------------------------------

ODOO_ENV_FILE="/home/odoo/.env"

# ✅ Lire la base active (SELECTED_DB) depuis .env
if [ -f "$ODOO_ENV_FILE" ]; then
  DBNAME=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
else
  echo "❌ Configuration file $ODOO_ENV_FILE not found."
  exit 1
fi

# ✅ Vérifier que la DBNAME est bien trouvée
if [ -z "$DBNAME" ]; then
  echo "❌ No SELECTED_DB found in $ODOO_ENV_FILE."
  exit 1
fi

echo "🚀 Running cheat on database: $DBNAME"

# ✅ Exécuter la commande SQL dans le conteneur db
docker exec db psql -U odoo -d "$DBNAME" -c "
WITH update_ir_config AS (
    UPDATE public.ir_config_parameter
    SET value = '2055-05-26 14:31:26'
    WHERE key = 'database.expiration_date'
),
update_ir_cron AS (
    UPDATE public.ir_cron
    SET active = false
    WHERE cron_name = 'Publisher: Update Notification'
)
SELECT 1;
"

# ✅ Vérification du résultat
if [ $? -eq 0 ]; then
  echo "✅ Cheat applied successfully to '$DBNAME'."
else
  echo "❌ Failed to apply cheat on '$DBNAME'."
  exit 1
fi
