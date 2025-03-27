#!/bin/bash

# -----------------------------------------------------------------------------
# Script to drop a PostgreSQL database inside a Docker container (db)
# Usage:
#   drop DBNAME [-y]
# Options:
#   DBNAME : Database name to drop (required)
#   -y     : Skip confirmation
# -----------------------------------------------------------------------------

# Default values
CONFIRM=true
DBNAME="$1"
ODOO_ENV_FILE="/home/odoo/.env"

# ✅ Vérification que DBNAME est bien fourni
if [ -z "$DBNAME" ]; then
  echo "❌ No database name provided."
  echo "Usage: drop DBNAME [-y]"
  exit 1
fi

shift  # On enlève DBNAME des arguments, pour traiter le reste (ex: -y)

# ✅ Parse des arguments supplémentaires
while [[ $# -gt 0 ]]; do
  case "$1" in
    -y)
      CONFIRM=false
      shift
      ;;
    *)
      echo "❌ Unknown option: $1"
      echo "Usage: drop DBNAME [-y]"
      exit 1
      ;;
  esac
done

# ✅ Lecture de la DB active (SELECTED_DB) depuis .env
if [ -f "$ODOO_ENV_FILE" ]; then
  ACTIVE_DB=$(grep '^SELECTED_DB=' "$ODOO_ENV_FILE" | cut -d '=' -f2 | tr -d '[:space:]')
else
  echo "❌ Configuration file $ODOO_ENV_FILE not found."
  exit 1
fi

# ✅ Sécurité : interdiction de supprimer la DB active
if [ "$DBNAME" == "$ACTIVE_DB" ]; then
  echo "❌ Refusing to drop the active database '$DBNAME'. Please switch to another database before dropping."
  exit 1
fi

# ✅ Confirmation si nécessaire
if $CONFIRM; then
  read -p "⚠️ Are you sure you want to drop the database '$DBNAME'? (yes/[no]): " answer
  if [[ "$answer" != "yes" ]]; then
    echo "❌ Aborted."
    exit 1
  fi
fi

# ✅ Vérification que la DB existe
DB_EXISTS=$(docker exec db psql -U odoo -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$DBNAME';")

if [ "$DB_EXISTS" != "1" ]; then
  echo "❌ Database '$DBNAME' does not exist."
  exit 1
fi

# ✅ Suppression de la DB
echo "🗑️ Dropping database '$DBNAME'..."
docker exec db psql -U odoo -d postgres -c "DROP DATABASE \"$DBNAME\";"

if [ $? -eq 0 ]; then
  echo "✅ Database '$DBNAME' successfully dropped."
else
  echo "❌ Failed to drop the database '$DBNAME'."
  exit 1
fi
