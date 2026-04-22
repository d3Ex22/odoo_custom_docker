#!/bin/bash
# ============================================================================
# Common utilities for all command scripts.
# Source this at the start of each command script.
# ============================================================================

# --- Environment ---
_PROJECT_ROOT="/home/utils/odoo_custom_docker"
source "${_PROJECT_ROOT}/.env" 2>/dev/null

# --- Container names ---
PROJECT="${COMPOSE_PROJECT_NAME}"
ODOO_CONTAINER="${PROJECT}_odoo"
UTILS_CONTAINER="${PROJECT}_utils"
DB_CONTAINER="${PROJECT}_db"
DB_USER="odoo"
DB_PASSWORD="odoo"
MODULES_CACHE="${_PROJECT_ROOT}/.data/volumes/odoo-container/cache/.modules_list"
COMPAT_FILE="${_PROJECT_ROOT}/.data/compat.map"
ENV_FILE="${_PROJECT_ROOT}/.env"
ODOO_TMUX_SESSION="logs"

# --- Theme loading ---
# Pattern: user overrides → default theme → user overrides (user wins)
_THEMES_DIR="${_PROJECT_ROOT}/.data/themes"
_UTILS_THEME_CONF="${_PROJECT_ROOT}/.config/utils/theme.conf"
source "$_UTILS_THEME_CONF" 2>/dev/null
if [ "${USE_DEFAULT_THEME}" = "true" ] && [ -n "${DEFAULT_THEME}" ] && [ -f "${_THEMES_DIR}/${DEFAULT_THEME}.conf" ]; then
    source "${_THEMES_DIR}/${DEFAULT_THEME}.conf"
else
    source "${_THEMES_DIR}/default.conf" 2>/dev/null
fi
source "$_UTILS_THEME_CONF" 2>/dev/null

source "${_PROJECT_ROOT}/.data/scripts/hex_to_ansi.sh"

build_odoo_cmd() {
    local modules="${1:-}"
    local cmd="odoo -c /etc/odoo/odoo.conf"
    [ -n "$SELECTED_DB" ] && cmd="$cmd -d $SELECTED_DB"
    [ -n "$ODOO_ARGS" ]   && cmd="$cmd $ODOO_ARGS"
    [ -n "$modules" ]     && cmd="$cmd -u $modules"
    echo "$cmd"
}

odoo_pane_pty() {
    docker exec "$ODOO_CONTAINER" tmux list-panes -t "$ODOO_TMUX_SESSION:0" \
        -F '#{pane_tty}' -f '#{==:#{pane_index},1}' 2>/dev/null
}

stop_odoo() {
    local pane="${ODOO_TMUX_SESSION}:0.1"
    local pid h tty
    pid=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null)
    [ -z "$pid" ] && return 1
    h=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_height}' 2>/dev/null)
    tty=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_tty}' 2>/dev/null)
    [ -n "$tty" ] && docker exec "$ODOO_CONTAINER" bash -c "printf '%0.s\n' \$(seq 1 ${h:-50}) > $tty"
    docker exec "$ODOO_CONTAINER" kill -9 "$pid" 2>/dev/null
}

run_odoo_script() {
    docker exec "$ODOO_CONTAINER" chmod +x /tmp/.odoo_runner.sh
    docker exec "$ODOO_CONTAINER" tmux respawn-pane -t "${ODOO_TMUX_SESSION}:0.1" "bash /tmp/.odoo_runner.sh"
}

expand_modules() {
    local input="$1"
    [ -z "$input" ] && return
    local known=""
    [ -f "$MODULES_CACHE" ] && known=$(tail -1 "$MODULES_CACHE")
    local result="" seen=""
    IFS=',' read -ra tokens <<< "$input"
    for token in "${tokens[@]}"; do
        token=$(echo "$token" | xargs)
        [ -z "$token" ] && continue
        if [[ "$token" == *[\*\?.\[\+\^\$]* ]]; then
            local regex="$token"
            regex=$(echo "$regex" | sed -E 's/([^.\\])\*/\1.*/g; s/^\*/.*/; s/([^\\])\?/\1./g; s/^\?/./')
            if [ -n "$known" ]; then
                local matches
                matches=$(echo "$known" | tr '|' '\n' | grep -E "^${regex}$")
                if [ -z "$matches" ]; then
                    printf "${CWARN}⚠ No modules matching '%s'${RST}\n" "$token" >&2
                    continue
                fi
                while IFS= read -r m; do
                    [ -z "$m" ] && continue
                    echo "$seen" | grep -qxF "$m" && continue
                    seen="${seen}${seen:+$'\n'}${m}"
                    result="${result}${result:+,}${m}"
                done <<< "$matches"
            fi
        else
            echo "$seen" | grep -qxF "$token" && continue
            seen="${seen}${seen:+$'\n'}${token}"
            result="${result}${result:+,}${token}"
        fi
    done
    echo "$result"
}

run_precommit() {
    local container="$1" files="$2"
    [ -z "$files" ] && return
    if ! docker exec "$container" which pre-commit >/dev/null 2>&1; then
        printf "  ${CWARN}Installing pre-commit (first time only)...${RST}\n\n"
        docker exec "$container" pip install pre-commit --quiet 2>/dev/null
    fi
    docker exec "$container" bash -c '
        cd /mnt/extra-addons
        PRECOMMIT_CACHE="/home/odoo/.cache/pre-commit"
        PRECOMMIT_GIT="$PRECOMMIT_CACHE/git_repo"
        git config --global --add safe.directory /mnt/extra-addons
        git config --global --add safe.directory "$PRECOMMIT_GIT"
        [ -f .pre-commit-config.yaml ] && mv .pre-commit-config.yaml .pre-commit-config.yaml.backup
        cp /opt/.pre-commit-config.yaml .pre-commit-config.yaml
        [ -d .git ] && mv .git .git_backup_precommit
        if [ -d "$PRECOMMIT_GIT/.git" ]; then
            cp -a "$PRECOMMIT_GIT/.git" .git
        else
            git init --quiet
            git config user.email "pre-commit@local"
            git config user.name "Pre-commit"
            mkdir -p "$PRECOMMIT_GIT"
            cp -a .git "$PRECOMMIT_GIT/.git"
        fi
        git add -A
        pre-commit run --files '"$files"' || true
        cp -a .git "$PRECOMMIT_GIT/.git"
        rm -rf .git
        [ -d .git_backup_precommit ] && mv .git_backup_precommit .git
        rm -f .pre-commit-config.yaml
        [ -f .pre-commit-config.yaml.backup ] && mv .pre-commit-config.yaml.backup .pre-commit-config.yaml
    ' 2>&1 | sed 's/^/  /'
}

set_env_value() {
    local key="$1" value="$2"
    [ "$value" = "-" ] && value=""
    local escaped_value
    escaped_value=$(printf '%s\n' "$value" | sed 's/[&/\]/\\&/g')
    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        local tmp="/tmp/.env.tmp.$$"
        sed "s/^${key}=.*/${key}=${escaped_value}/" "$ENV_FILE" > "$tmp"
        cat "$tmp" > "$ENV_FILE"
        rm -f "$tmp"
    else
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

db_exists() {
    local dbname="$1"
    [ -z "$dbname" ] && return 1
    local result
    result=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname = '$dbname';" 2>/dev/null)
    [ "$result" = "1" ]
}

check_compat() {
    local odoo="$1" py="$2" pg="$3"
    local compat="${4:-$COMPAT_FILE}"
    [ ! -f "$compat" ] && return 0
    while IFS=: read -r o_ver def_py py_vers def_pg pg_vers; do
        o_ver=$(echo "$o_ver" | tr -d ' ')
        [[ "$o_ver" =~ ^#.*$ || -z "$o_ver" ]] && continue
        if [ "$odoo" = "$o_ver" ]; then
            local py_ok=false pg_ok=false
            py_vers=$(echo "$py_vers" | tr -d ' ')
            pg_vers=$(echo "$pg_vers" | tr -d ' ')
            IFS=',' read -ra PY_ARR <<< "$py_vers"
            for v in "${PY_ARR[@]}"; do [ "$py" = "$v" ] && py_ok=true; done
            IFS=',' read -ra PG_ARR <<< "$pg_vers"
            for v in "${PG_ARR[@]}"; do [ "$pg" = "$v" ] && pg_ok=true; done
            $py_ok && $pg_ok && return 0
            return 1
        fi
    done < "$compat"
    return 1
}
