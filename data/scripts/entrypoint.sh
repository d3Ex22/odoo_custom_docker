#!/bin/bash

ENV_FILE="/home/odoo/.env"

# ✅ Lecture des variables depuis .env
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
else
    echo "❌ ERROR: File $ENV_FILE not found!"
    exit 1
fi

# ✅ Vérification que SELECTED_DB est bien défini
if [ -z "$SELECTED_DB" ]; then
    echo "❌ ERROR: SELECTED_DB is not set in $ENV_FILE"
    exit 1
fi

# ✅ Si ODOO_ARGS non défini, le mettre à vide
ODOO_ARGS="${ODOO_ARGS:-}"

echo "✅ Selected DB: $SELECTED_DB"
echo "✅ Extra Odoo Args: $ODOO_ARGS"

# ✅ Démarrage du service SSH
echo "🚀 Starting SSH service..."
service ssh start

# Installation des dépendances supplémentaires du projet
apt-get update
apt-get install xmlsec1 build-essential python3-dev poppler-utils libpoppler-dev libpoppler-cpp-dev -y

# ✅ Installation des requirements si présents
if [ -f "/mnt/extra-addons/requirements.txt" ]; then
    echo "📦 Installing Python requirements..."
    pip install -r /mnt/extra-addons/requirements.txt
else
    echo "⚠️ No requirements.txt found in /mnt/extra-addons"
fi

# ✅ Lancement d'Odoo avec la DB et les arguments supplémentaires
echo "🚀 Launching Odoo with: -d $SELECTED_DB $ODOO_ARGS"
exec odoo -d "$SELECTED_DB" $ODOO_ARGS
