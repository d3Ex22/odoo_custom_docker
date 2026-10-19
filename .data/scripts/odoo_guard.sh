#!/bin/bash
# ============================================================================
# Pre-start guard, run in the Odoo logs pane just before 'exec odoo'.
# Refuses to start when the mounted Enterprise / Odoo source folders do not
# match ODOO_VERSION (see check_paths_version.sh). Exit 1 = do not start.
# ============================================================================

source /opt/env/scripts/lib/theme.sh

ENV_FILE="/home/odoo/.env"
[ -z "${ODOO_VERSION:-}" ] && [ -f "$ENV_FILE" ] && ODOO_VERSION=$(grep -E '^ODOO_VERSION=' "$ENV_FILE" | cut -d= -f2 | tr -d "\"' ")
export ODOO_VERSION

# First start of this project on this machine: the configuration has not been
# confirmed yet (hub first-start dialog). Odoo must not
# create the database before ENTERPRISE_PATH & co are settled.
if [ ! -f /var/shared/.setup_done ]; then
    printf '\n%s▸ First start — Odoo is waiting for the configuration to be confirmed%s\n' "$CWARN" "$RST"
    printf '%s  Hub: http://odoo.docker.localhost → this project → setup (enterprise / odoo paths, database)%s\n' "$CMUTED" "$RST"
    echo
    exit 1
fi

ERRORS=$(/usr/local/bin/check_paths_version.sh) && exit 0

printf '\n%s✗ Odoo not started — source folders do not match ODOO_VERSION=%s%s\n' "$CERROR" "$ODOO_VERSION" "$RST"
echo "$ERRORS" | while IFS= read -r line; do printf '  %s%s%s\n' "$CWARN" "$line" "$RST"; done
printf '%s  Fix from the utils terminal:%s\n' "$CMUTED" "$RST"
printf '%s    pull                              checkout the %s branch of the mounted repos%s\n' "$CMUTED" "$ODOO_VERSION" "$RST"
printf '%s    ODOO_VERSION (hub config) + rebuild  or change the server version%s\n' "$CMUTED" "$RST"
printf '%s    s                                 start Odoo again%s\n\n' "$CMUTED" "$RST"
exit 1
