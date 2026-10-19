#!/bin/bash
# ============================================================================
# Outgoing mail catcher (Mailpit container 'mail', compose profile 'mail').
# Runs inside the odoo container.
#
#   mail_catcher.sh conf       odoo.conf smtp_server/smtp_port → mail:1025 when
#                              the profile is on, removed otherwise
#   mail_catcher.sh db DB      point every ir_mail_server of DB to mail:1025
#   mail_catcher.sh enabled    exit 0 when the profile is on
# ============================================================================
ODOO_CONF="/etc/odoo/odoo.conf"
PROFILES="${COMPOSE_PROFILES:-}"
[ -z "$PROFILES" ] && [ -f /home/odoo/.env ] && PROFILES=$(grep -E '^COMPOSE_PROFILES=' /home/odoo/.env | cut -d= -f2- | tr -d "\"' ")
enabled() { [[ ",${PROFILES}," == *,mail,* ]]; }

set_key() {   # set_key KEY VALUE  (empty value removes the key); written in place (bind-mounted file)
    local key="$1" value="$2" tmp="/tmp/odoo.conf.mail"
    if [ -z "$value" ]; then grep -vE "^${key}\s*=" "$ODOO_CONF" > "$tmp"
    elif grep -qE "^${key}\s*=" "$ODOO_CONF"; then sed -E "s|^${key}\s*=.*|${key} = ${value}|" "$ODOO_CONF" > "$tmp"
    else { cat "$ODOO_CONF"; [ -n "$(tail -c1 "$ODOO_CONF")" ] && echo; echo "${key} = ${value}"; } > "$tmp"; fi   # file may lack a final newline
    cat "$tmp" > "$ODOO_CONF"; rm -f "$tmp"
}

case "${1:-}" in
    enabled) enabled ;;
    conf)
        [ -f "$ODOO_CONF" ] || exit 0
        if enabled; then set_key smtp_server mail; set_key smtp_port 1025; set_key smtp_ssl False
        else set_key smtp_server ""; set_key smtp_port ""; set_key smtp_ssl ""; fi ;;
    db)
        enabled || exit 0
        DB="$2"
        export PGPASSWORD="${PASSWORD:-odoo}"
        psql -h "${HOST:-db}" -p "${PORT:-5432}" -U "${USER:-odoo}" -d "$DB" -q >/dev/null 2>&1 <<'EOSQL'
UPDATE ir_mail_server
   SET smtp_host = 'mail', smtp_port = 1025, smtp_encryption = 'none', smtp_user = NULL, smtp_pass = NULL
 WHERE smtp_host IS DISTINCT FROM 'mail' OR smtp_port IS DISTINCT FROM 1025 OR smtp_encryption IS DISTINCT FROM 'none';
EOSQL
        ;;
    *) echo "usage: mail_catcher.sh conf | db DB | enabled" >&2; exit 1 ;;
esac
