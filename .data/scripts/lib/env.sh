#!/bin/bash
# ============================================================================
# lib/env.sh — environment, container names, colors
# Project name, .env values, hosts, paths, palette (lib/theme.sh), docker shim.
# Sourced by common.sh (every command) — not meant to be sourced alone.
# ============================================================================

# ----------------------------------------------------------------------------
# 1. Environment
# ----------------------------------------------------------------------------
_PROJECT_ROOT="/home/utils/odoo_custom_docker"
# The project name is resolved by docker compose (folder name unless set in
# .env) and passed to the container; the entrypoint also writes it to
# /var/shared/.project_name for the 'su - utils' login shell, which starts
# without the container environment. An empty .env value must not clobber it.
_PROJECT_FROM_CONTAINER="${COMPOSE_PROJECT_NAME:-$(cat /var/shared/.project_name 2>/dev/null)}"
source "${_PROJECT_ROOT}/.env" 2>/dev/null
# Optional, git-ignored: ENTERPRISE_KEY / NGROK_KEY can live here instead of .env
source "${_PROJECT_ROOT}/.env.secrets" 2>/dev/null
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$_PROJECT_FROM_CONTAINER}"

PROJECT="${COMPOSE_PROJECT_NAME}"
ODOO_CONTAINER="${PROJECT}_odoo"
UTILS_CONTAINER="${PROJECT}_utils"
DB_CONTAINER="${PROJECT}_db"
# URLs served by the shared proxy (.data/proxy): fixed patterns, no .env var.
HUB_URL="http://odoo.docker.localhost"
ODOO_HOST="${PROJECT}.odoo.docker.localhost"
LOGS_HOST="${PROJECT}.logs.docker.localhost"
UTILS_HOST="${PROJECT}.utils.docker.localhost"
MCP_HOST="${PROJECT}.mcp.docker.localhost"
MAIL_HOST="${PROJECT}.mail.docker.localhost"
MCP_PORT=8300   # inside the utils container; the shared proxy serves it on MCP_HOST
PROXY_PROJECT="odoo_proxy"
PROXY_NETWORK="odoo_proxy"
DB_USER="odoo"
DB_PASSWORD="odoo"
MODULES_CACHE="${_PROJECT_ROOT}/.data/volumes/odoo-container/cache/.modules_list"
COMPAT_FILE="${_PROJECT_ROOT}/.data/compat.map"
ENV_FILE="${_PROJECT_ROOT}/.env"
ODOO_TMUX_SESSION="logs"
UTILS_TMUX_SOCKET="/tmp/tmux-0/default"
UI_WIDTH=64
# Narrow side panes (-p): rules shrink to the pane width
if [ -t 1 ]; then _cols=$(tput cols 2>/dev/null); [ -n "$_cols" ] && [ "$_cols" -lt "$UI_WIDTH" ] && UI_WIDTH=$((_cols - 2)); unset _cols; fi

# Command name as typed by the user (used in help, pane titles, errors).
CMD_NAME="${CMD_NAME:-$(basename "${0%.sh}")}"

# --- Colors (lib/theme.sh: CPRIMARY, BPRIMARY, CMUTED, ... RST) ---
source "${_PROJECT_ROOT}/.data/scripts/lib/theme.sh"

# Colors are dropped when stdout is not a terminal or NO_COLOR is set, so the
# output stays clean when piped, captured by a script or read by an AI agent.
disable_colors() {
    local v
    for v in RST {C,B}{PRIMARY,ACCENT,MUTED,SUCCESS,WARN,ERROR,FG}; do
        printf -v "$v" ''
    done
}
{ [ -n "${NO_COLOR:-}" ] || [ ! -t 1 ]; } && disable_colors

# Non-root utils shell: when docker.sock is not writable (root:root socket)
# every docker call goes through sudo. A file test, not 'docker info' (~20ms).
if [ "$(id -u)" -ne 0 ] && [ ! -w /var/run/docker.sock ]; then
    docker() { sudo docker "$@"; }
fi
