#!/bin/bash
# ============================================================================
# conf - Read / write the runtime settings of .env
# Internal: odoo_status / conf_set MCP tools, docker exec. Humans edit .env
# from the hub (config panel). Not a utils command.
# ============================================================================
# Usage: conf [<VAR> [value|-]]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

# VAR|what applies the change|description
VARS=(
    "SELECTED_DB|reboot|Active database (db select does this + reboots)"
    "ODOO_UPDATE|next u / start|Modules updated by a bare 'u' (u -k <modules> does this)"
    "ODOO_ARGS|reboot|Extra Odoo CLI arguments"
    "AUTO_UPDATE|watch on/off|Auto 'u <module>' when a __manifest__.py is saved (watch on/off does this)"
    "ODOO_VERSION|rebuild|Odoo version (19.0, 18.0, ...)"
    "ODOO_BUILD|rebuild|Nightly build date YYYYMMDD or 'latest'"
    "PYTHON_VERSION|rebuild|Python version of the Odoo image"
    "POSTGRES_VERSION|rebuild|PostgreSQL version (existing databases are wiped)"
    "ENTERPRISE_PATH|docker compose up -d|Enterprise addons folder, relative to this project (empty = community)"
    "ODOO_PATH|docker compose up -d|Odoo source checkout mounted read-only (pull, upgrade-code)"
    "ADDONS_PATH|docker compose up -d|Your addons folder, mounted at /mnt/extra-addons"
    "IMAGE_RETENTION_DAYS|daily|Days before an unused shared image is removed (0 = keep them all)"
    "COMPOSE_PROFILES|docker compose up -d|'mail' enables the outgoing mail catcher, empty disables it"
    "ODOO_WS_PORT|docker compose up -d|Port of /websocket: 8069 threaded (default), 8072 with workers"
    "DEBUGPY|reboot|Start Odoo under debugpy (debug on/off does this + writes launch.json)"
    "DEBUGPY_PORT|docker compose up -d|Fixed host port for debugpy (empty = chosen by Docker)"
    "ENV_TEMPLATE_REPO|env-update|Template repository refreshed by env-update"
    "ENV_TEMPLATE_REF|env-update|Template branch / tag (empty = default branch)"
)

var_field() {   # var_field VAR 2|3
    local line
    for line in "${VARS[@]}"; do
        [ "${line%%|*}" = "$1" ] && echo "$line" | cut -d'|' -f"$2" && return 0
    done
    return 1
}

valid_py_versions() { grep -E "^${ODOO_VERSION}[[:space:]]*:" "$COMPAT_FILE" 2>/dev/null | cut -d: -f3 | tr -d ' ' | tr ',' ' '; }
valid_pg_versions() { grep -E "^${ODOO_VERSION}[[:space:]]*:" "$COMPAT_FILE" 2>/dev/null | cut -d: -f5 | tr -d ' ' | tr ',' ' '; }
in_list() { local v; for v in $2; do [ "$1" = "$v" ] && return 0; done; return 1; }


show_current() {
    ui_title "Settings" ".env"
    local line var val
    for line in "${VARS[@]}"; do
        var="${line%%|*}"
        val="${!var:-}"
        if [ -z "$val" ]; then
            printf "  ${CPRIMARY}%-20s${RST} ${CMUTED}(empty)${RST}\n" "$var"
        else
            printf "  ${CPRIMARY}%-20s${RST} %s\n" "$var" "$val"
        fi
    done
    echo
    ui_note "Python for Odoo ${ODOO_VERSION}: $(valid_py_versions | xargs)"
    ui_note "PostgreSQL for Odoo ${ODOO_VERSION}: $(valid_pg_versions | xargs)"
    echo
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    "") show_current; exit 0 ;;
esac

VAR=$(echo "$1" | tr '[:lower:]' '[:upper:]')
APPLY=$(var_field "$VAR" 2) || die "Unknown variable: $1" "Editable: $(printf '%s\n' "${VARS[@]}" | cut -d'|' -f1 | paste -sd' ' -)"
[ $# -gt 2 ] && die "Too many arguments" "Quote values with spaces"

if [ $# -eq 1 ]; then
    val="${!VAR:-}"
    if [ -z "$val" ]; then printf "%s=\n" "$VAR"; else printf "%s=%s\n" "$VAR" "$val"; fi
    exit 0
fi

VALUE="$2"
if [ "$VALUE" != "-" ]; then
    case "$VAR" in
        ODOO_VERSION)
            in_list "$VALUE" "$(compat_odoo_versions | xargs)" \
                || die "Unsupported ODOO_VERSION: $VALUE" "Known: $(compat_odoo_versions | xargs)" ;;
        ODOO_BUILD)
            [[ "$VALUE" = "latest" || "$VALUE" =~ ^[0-9]{8}$ ]] \
                || die "ODOO_BUILD must be 'latest' or a date YYYYMMDD" "Builds: https://nightly.odoo.com/${ODOO_VERSION}/nightly/src/" ;;
        PYTHON_VERSION)
            in_list "$VALUE" "$(valid_py_versions)" \
                || die "Python $VALUE is not supported by Odoo ${ODOO_VERSION}" "Valid: $(valid_py_versions | xargs)" ;;
        POSTGRES_VERSION)
            in_list "$VALUE" "$(valid_pg_versions)" \
                || die "PostgreSQL $VALUE is not supported by Odoo ${ODOO_VERSION}" "Valid: $(valid_pg_versions | xargs)" ;;
        AUTO_UPDATE)
            [[ "$VALUE" =~ ^(true|false)$ ]] || die "AUTO_UPDATE must be true or false" "Prefer: watch on / watch off" ;;
        DEBUGPY)
            [[ "$VALUE" =~ ^(true|false)$ ]] || die "DEBUGPY must be true or false" "Prefer: debug on / debug off" ;;
        COMPOSE_PROFILES)
            [[ "$VALUE" =~ ^(mail)$ ]] || die "COMPOSE_PROFILES: only 'mail' is known (or - to disable)" ;;
        ODOO_WS_PORT|DEBUGPY_PORT)
            [[ "$VALUE" =~ ^[0-9]+$ ]] || die "$VAR must be a port number" ;;
        IMAGE_RETENTION_DAYS)
            [[ "$VALUE" =~ ^[0-9]+$ ]] || die "IMAGE_RETENTION_DAYS must be a number of days (0 disables the auto prune)" ;;
        ENTERPRISE_PATH|ODOO_PATH|ADDONS_PATH)
            [ -e "${_PROJECT_ROOT}/${VALUE#./}" ] || ui_warn "${VALUE} does not exist (relative to the project folder)" ;;
        SELECTED_DB)
            valid_db_name "$VALUE" || die "Invalid database name: $VALUE"
            db_exists "$VALUE" || ui_warn "Database '$VALUE' does not exist yet — Odoo will create it on start" ;;
        ODOO_UPDATE)
            if container_running "$ODOO_CONTAINER"; then
                refresh_modules_cache "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)"
                UNKNOWN=$(unknown_modules "$(expand_modules "$VALUE")")   # patterns are expanded by 'u' at run time
                [ -n "$UNKNOWN" ] && ui_warn "Unknown module(s): $(echo "$UNKNOWN" | paste -sd, -)"
            fi ;;
    esac
fi

set_env_value "$VAR" "$VALUE"
if [ "$VALUE" = "-" ]; then ui_ok "$VAR cleared"; else ui_ok "$VAR=$VALUE"; fi
case "$APPLY" in
    reboot)  ui_note "r to apply" ;;
    rebuild) ui_note "rebuild to apply" ;;
    "next u / start") ui_note "used by the next bare u (or s / r)" ;;
    "watch on/off") ui_note "watch on / watch off to apply" ;;
    "docker compose up -d") ui_note "docker compose up -d (from the host) to apply" ;;
esac
