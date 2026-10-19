#!/bin/bash
# ============================================================================
# mcp - MCP server for AI agents (.data/mcp/server.py), always on
# Internal: started by the utils entrypoint, restarted by env-update when the
# server changed. Served by the shared proxy on http://<project>.mcp.docker.localhost/mcp
# Log: .data/volumes/shared/mcp.log
# ============================================================================
# Usage: mcp start|stop|restart
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

SERVER="${_PROJECT_ROOT}/.data/mcp/server.py"
LOG="/var/shared/mcp.log"
HEALTH="http://localhost:${MCP_PORT}/health"

mcp_running() { curl -sf -m 1 "$HEALTH" >/dev/null 2>&1; }

mcp_start() {
    mcp_running && return 0
    nohup python3 "$SERVER" --serve "$MCP_PORT" >> "$LOG" 2>&1 &
    disown 2>/dev/null
    local i
    for i in $(seq 1 15); do mcp_running && return 0; sleep 0.2; done
    ui_err "MCP server did not start"; tail -5 "$LOG" 2>/dev/null | sed 's/^/  /' >&2; return 1
}

mcp_stop() {
    local pids i; pids=$(pgrep -f "server.py --serve" 2>/dev/null)
    [ -n "$pids" ] && kill $pids 2>/dev/null
    for i in 1 2 3 4 5; do mcp_running || return 0; sleep 0.2; done
    mcp_running && { ui_err "MCP server still answering"; return 1; }
    return 0
}

case "${1:-}" in
    start) mcp_start ;;
    stop) mcp_stop ;;
    restart) mcp_stop && mcp_start && ui_ok "MCP server restarted" ;;
    *) die "Usage: mcp start|stop|restart" ;;
esac
