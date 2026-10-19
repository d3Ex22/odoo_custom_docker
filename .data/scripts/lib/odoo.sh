#!/bin/bash
# ============================================================================
# lib/odoo.sh — containers, the Odoo process, compose from utils, the proxy
# stop_odoo / launch_odoo / dc_host / proxy_up / check_paths_version.
# Sourced by common.sh (every command) — not meant to be sourced alone.
# ============================================================================

# ----------------------------------------------------------------------------
# 5. Containers & Odoo process
# ----------------------------------------------------------------------------
container_running() { docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$1"; }
require_odoo_container() {
    container_running "$ODOO_CONTAINER" || die "Odoo container is not running" "Start it with: docker compose up -d odoo"
}
require_db_container() {
    container_running "$DB_CONTAINER" || die "Database container is not running" "Start it with: docker compose up -d db"
}
odoo_process_running() { docker exec "$ODOO_CONTAINER" pgrep -x odoo >/dev/null 2>&1; }
# Host port published for debugpy (5678 in the container), empty when not running
debugpy_host_port() { docker port "$ODOO_CONTAINER" 5678/tcp 2>/dev/null | head -1 | sed 's/.*://'; }

stop_odoo() {
    local pane="${ODOO_TMUX_SESSION}:0.1"
    local dead pid h tty
    # No tmux session yet → nothing to stop (treat as success).
    docker exec "$ODOO_CONTAINER" tmux has-session -t "$ODOO_TMUX_SESSION" 2>/dev/null || return 0
    # Pane already dead (Odoo previously stopped, remain-on-exit keeps it) →
    # its pid/tty are stale; do not touch them (avoids writing to a defunct tty).
    dead=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_dead}' 2>/dev/null)
    [ "$dead" = "1" ] && return 0
    pid=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_pid}' 2>/dev/null)
    [ -z "$pid" ] && return 0
    h=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_height}' 2>/dev/null)
    tty=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$pane" -p '#{pane_tty}' 2>/dev/null)
    # Clear the visible pane; ignore errors if the tty is already gone.
    [ -n "$tty" ] && docker exec "$ODOO_CONTAINER" bash -c "printf '%0.s\n' \$(seq 1 ${h:-50}) > $tty" 2>/dev/null
    # SIGKILL on purpose: dev environment, fastest possible restart.
    docker exec "$ODOO_CONTAINER" kill -9 "$pid" 2>/dev/null
    return 0
}

# docker compose from inside utils: runs in a throwaway container that sees the
# project at its HOST path, so compose records host paths in the container
# labels and 'docker compose' keeps working from the host afterwards.
require_host_project_dir() {
    HOST_PROJECT_DIR=$(tr -d '\n' < "${_PROJECT_ROOT}/.data/host_project_path.map" 2>/dev/null)
    [ -z "$HOST_PROJECT_DIR" ] || [ "$HOST_PROJECT_DIR" = "/unknown" ] \
        && die "Host project path unknown" "Run 'docker compose up -d' from the host once"
    UTILS_IMAGE=$(docker inspect "$UTILS_CONTAINER" --format '{{.Config.Image}}' 2>/dev/null)
    [ -z "$UTILS_IMAGE" ] && die "Cannot resolve the utils image"
    return 0
}
# dc_host PROJECT HOST_DIR compose-args...
dc_host() {
    local project="$1" dir="$2"; shift 2
    local tty=""
    [ -t 1 ] && tty="-t"
    docker run --rm $tty \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "${dir}:${dir}" -w "${dir}" \
        --entrypoint docker "$UTILS_IMAGE" compose -p "$project" "$@"
}

# Shared proxy (.data/proxy): started when missing; odoo and utils sit on its
# network through the project compose file, so Traefik reaches them directly.
proxy_running() { container_running "${PROXY_PROJECT}_traefik" && container_running "${PROXY_PROJECT}_hub"; }
proxy_up() {
    require_host_project_dir
    dc_host "$PROXY_PROJECT" "${HOST_PROJECT_DIR}/.data/proxy" up -d --remove-orphans "$@"
}
ensure_proxy() { proxy_running || proxy_up >/dev/null 2>&1; }
# Mounted ENTERPRISE_PATH / ODOO_PATH must match ODOO_VERSION (a wrong series
# loaded with -u corrupts the database). Same check as the odoo runner, done
# here first for an immediate, readable error.
check_paths_version() {
    local out
    out=$(docker exec -e ODOO_VERSION="$ODOO_VERSION" "$ODOO_CONTAINER" /usr/local/bin/check_paths_version.sh 2>/dev/null) && return 0
    ui_err "Odoo not started: mounted source folders do not match ODOO_VERSION=${ODOO_VERSION}"
    echo "$out" | sed 's/^/  /' >&2
    ui_note "pull        → checkout the ${ODOO_VERSION} branch of ENTERPRISE_PATH / ODOO_PATH"
    ui_note "or change ODOO_VERSION (hub config / .env) + rebuild"
    return 1
}

# (re)start Odoo with an optional -u list (start / reboot / update): respawns
# odoo_runner.sh in the logs pane with the caller's SELECTED_DB ('-' = multi-db).
launch_odoo() {
    local modules="${1:-}" before after i
    check_paths_version || return 1
    [ -n "$modules" ] && refresh_modules_cache "$(docker exec "$ODOO_CONTAINER" /usr/local/bin/generate_addons_path.sh 2>/dev/null)"
    stop_odoo || return 1
    # Dev defaults (report.url, mail catcher...) on the database(s) about to be served
    docker exec -e SELECTED_DB="${SELECTED_DB:-}" "$ODOO_CONTAINER" /usr/local/bin/dev_db_bootstrap.sh >/dev/null 2>&1
    sleep 0.3
    before=$(odoo_header_count)
    # -k forces a respawn whether the pane is alive or dead. After 'stop' the
    # pane is dead (remain-on-exit); without -k respawn-pane fails to revive it.
    docker exec "$ODOO_CONTAINER" tmux respawn-pane -k -t "${ODOO_TMUX_SESSION}:0.1" \
        "bash /usr/local/bin/odoo_runner.sh -d '${SELECTED_DB:--}'${modules:+ -u $modules}" || return 1
    echo "starting|0|$(date +%s)" > /var/shared/.last_start 2>/dev/null
    # Wait for the new start header so that 'logs -w' / 'logs -e' never read
    # the previous run (the header is printed within milliseconds).
    for i in $(seq 1 30); do
        after=$(odoo_header_count)
        [ "$after" -gt "$before" ] && break
        sleep 0.1
    done
}
odoo_header_count() {
    docker exec "$ODOO_CONTAINER" tmux capture-pane -t "${ODOO_TMUX_SESSION}:0.1" -p -S - 2>/dev/null \
        | grep -c 'Addon paths:' || true
}
