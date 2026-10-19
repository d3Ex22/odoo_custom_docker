#!/bin/bash
# ============================================================================
# lib/project.sh — images, modules, .env edition, version compatibility
# odoo_image / sync_image_revs / expand_modules / set_env_value / check_compat.
# Sourced by common.sh (every command) — not meant to be sourced alone.
# ============================================================================

# ----------------------------------------------------------------------------
# 6. Modules, versions, .env, databases
# ----------------------------------------------------------------------------
# Nightly source build dates (YYYYMMDD, oldest first) of an Odoo version; the latest one.
nightly_builds() {
    curl -s --connect-timeout 5 "https://nightly.odoo.com/${1}/nightly/src/" 2>/dev/null \
        | grep -oP "odoo_${1}\.\K\d{8}(?=\.tar\.gz)" | sort -u
}
nightly_latest_build() { nightly_builds "$1" | tail -1; }

# Installed "version|build" as written by the odoo image (/opt/odoo/.build_version).
installed_odoo_build() {
    docker exec "$ODOO_CONTAINER" cat /opt/odoo/.build_version 2>/dev/null
}

# --- Images: tagged by stack + Dockerfile revision, shared by every project
#     (see docker-compose.yml). Must match its 'image:' lines.
IMAGE_NS="odoo-env"
odoo_image()  { echo "${IMAGE_NS}/odoo:${ODOO_VERSION}-py${PYTHON_VERSION}-${ODOO_BUILD}-${ODOO_IMAGE_REV:-dev}"; }
db_image()    { echo "${IMAGE_NS}/db:${POSTGRES_VERSION}"; }
utils_image() { echo "${IMAGE_NS}/utils:${UTILS_IMAGE_REV:-dev}"; }
image_rev()   { bash "${_PROJECT_ROOT}/.data/scripts/image_rev.sh" "$1" "$_PROJECT_ROOT"; }   # image_rev odoo|utils
# Keep ODOO_IMAGE_REV / UTILS_IMAGE_REV in .env equal to the current files
# (compose reads the tags from there). Returns 1 when something changed.
sync_image_revs() {
    local changed=1 svc var rev
    for svc in odoo utils; do
        var="$(echo "$svc" | tr a-z A-Z)_IMAGE_REV"
        rev=$(image_rev "$svc")
        [ -z "$rev" ] && continue
        [ "${!var:-}" = "$rev" ] && continue
        set_env_value "$var" "$rev"
        printf -v "$var" '%s' "$rev"; export "$var"
        changed=0
    done
    return $changed
}
image_id()    { docker image inspect "$1" --format '{{.Id}}' 2>/dev/null; }   # empty = missing
container_image_id() { docker inspect "$1" --format '{{.Image}}' 2>/dev/null; }

# Last-use ledger: one file per image (mtime = last 'compose up' / rebuild of
# a project using it), in the odoo_env_meta volume shared by every project.
LEDGER_DIR="/var/odoo-env/last_used"
ledger_key()   { echo "$1" | tr '/:' '__'; }
ledger_touch() { mkdir -p "$LEDGER_DIR" 2>/dev/null && touch "${LEDGER_DIR}/$(ledger_key "$1")" 2>/dev/null; }
ledger_touch_current() { local i; for i in "$(odoo_image)" "$(db_image)" "$(utils_image)"; do ledger_touch "$i"; done; }

# Rebuild the module cache inside the odoo container (hash-validated on addon
# dir mtimes, so modules added since 'compose up' become known).
refresh_modules_cache() {
    docker exec "$ODOO_CONTAINER" /usr/local/bin/check_modules.sh "$1" >/dev/null 2>&1
}

expand_modules() {
    local input="$1"
    [ -z "$input" ] && return
    local known=""
    [ -f "$MODULES_CACHE" ] && known=$(tail -1 "$MODULES_CACHE")
    local result="" seen="" tokens token m
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
                    ui_warn "No modules matching '$token'" >&2
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

# Unknown module names from a comma list (uses the module cache).
unknown_modules() {
    local known=""
    [ -f "$MODULES_CACHE" ] && known=$(tail -1 "$MODULES_CACHE")
    [ -z "$known" ] && return 0
    local m mods
    IFS=',' read -ra mods <<< "$1"
    for m in "${mods[@]}"; do
        m=$(echo "$m" | xargs)
        [ -z "$m" ] || [ "$m" = "all" ] || [ "$m" = "base" ] && continue
        echo "$known" | grep -qE "(^|\|)${m}(\||$)" || echo "$m"
    done
}

run_precommit() {
    local container="$1" files="$2"
    [ -z "$files" ] && return
    if ! docker exec "$container" which pre-commit >/dev/null 2>&1; then
        ui_step "Installing pre-commit (first time only)..."
        docker exec "$container" pip install pre-commit --quiet 2>/dev/null
    fi
    # addons/.pre-commit-config.yaml is permanent (refreshed from
    # .config/ when it changes) so IDE/host pre-commit see the same hooks.
    # pre-commit and its hooks need a git repo: when addons/ is not one, a
    # persistent repo in the cache is linked for the run through a one-line
    # '.git' pointer file (removed afterwards; nothing is copied or moved).
    docker exec "$container" bash -c '
        cd /mnt/extra-addons
        cmp -s /opt/.pre-commit-config.yaml .pre-commit-config.yaml || cp /opt/.pre-commit-config.yaml .pre-commit-config.yaml
        git config --global --add safe.directory "*" 2>/dev/null
        if [ -e .git ]; then
            grep -qx ".pre-commit-config.yaml" .git/info/exclude 2>/dev/null || echo ".pre-commit-config.yaml" >> .git/info/exclude 2>/dev/null
        else
            repo=/home/odoo/.cache/pre-commit/git_repo
            if [ ! -d "$repo/.git" ]; then
                mkdir -p "$repo" && git -C "$repo" init -q \
                    && git -C "$repo" config user.email "pre-commit@local" && git -C "$repo" config user.name "Pre-commit" \
                    && git -C "$repo" config core.worktree /mnt/extra-addons \
                    && git -C "$repo" config core.fileMode false
            fi
            echo "gitdir: $repo/.git" > .git
            trap "rm -f /mnt/extra-addons/.git" EXIT
            git add -A 2>/dev/null
        fi
        # bind mounts report every file as executable: hooks must trust the git index modes
        GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fileMode GIT_CONFIG_VALUE_0=false pre-commit run --files '"$files"'
    ' 2>&1 | sed 's/^/  /'
    return "${PIPESTATUS[0]}"   # 1 when a hook failed or modified files
}

set_env_value() {
    local key="$1" value="$2"
    [ "$value" = "-" ] && value=""
    # .env is both sourced by bash and parsed by docker compose: single-quote
    # anything that is not a plain word (spaces, $, quotes, #...).
    if [[ -n "$value" && ! "$value" =~ ^[A-Za-z0-9_.,:/=@+-]+$ ]]; then
        value="'${value//\'/\'\\\'\'}'"
    fi
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

# Odoo major (19 for 19.0): .env ODOO_VERSION, fallback to the binary.
odoo_major_version() {
    local ver="${ODOO_VERSION:-}"
    [ -z "$ver" ] && ver=$(docker exec "$ODOO_CONTAINER" odoo --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+' | head -1)
    echo "${ver%%.*}"
}

check_compat() {
    local odoo="$1" py="$2" pg="$3"
    local compat="${4:-$COMPAT_FILE}"
    [ ! -f "$compat" ] && return 0
    local o_ver def_py py_vers def_pg pg_vers py_ok pg_ok vers v
    while IFS=: read -r o_ver def_py py_vers def_pg pg_vers; do
        o_ver=$(echo "$o_ver" | tr -d ' ')
        [[ "$o_ver" =~ ^#.*$ || -z "$o_ver" ]] && continue
        if [ "$odoo" = "$o_ver" ]; then
            py_ok=false; pg_ok=false
            IFS=',' read -ra vers <<< "${py_vers// /}"
            for v in "${vers[@]}"; do [ "$py" = "$v" ] && py_ok=true; done
            IFS=',' read -ra vers <<< "${pg_vers// /}"
            for v in "${vers[@]}"; do [ "$pg" = "$v" ] && pg_ok=true; done
            $py_ok && $pg_ok && return 0
            return 1
        fi
    done < "$compat"
    return 1
}

compat_odoo_versions() {   # all Odoo versions known in compat.map, newest first
    [ -f "$COMPAT_FILE" ] || return 0
    grep -v '^#' "$COMPAT_FILE" | grep -v '^$' | cut -d: -f1 | tr -d ' ' | sort -rV
}
