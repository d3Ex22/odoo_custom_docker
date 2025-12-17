#!/bin/bash
# ============================================================================
# Common utilities for all commands
# Source this at the start of each command script
# ============================================================================

# Load environment
source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

# Project settings
PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
ODOO_CONTAINER="${PROJECT}_odoo"
UTILS_CONTAINER="${PROJECT}_utils"
DB_CONTAINER="${PROJECT}_db"
DB_USER="${POSTGRES_USER:-odoo}"

# Colors
COLOR="${UTILS_COLOR:-#2ecc71}"
_R=$((16#${COLOR:1:2}))
_G=$((16#${COLOR:3:2}))
_B=$((16#${COLOR:5:2}))
C=$(printf '\033[38;2;%s;%s;%sm' "$_R" "$_G" "$_B")
RST=$(printf '\033[0m')
RED=$(printf '\033[0;31m')
YELLOW=$(printf '\033[0;33m')
GREEN=$(printf '\033[0;32m')
BLUE=$(printf '\033[0;34m')

