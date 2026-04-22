#!/bin/bash

# ============================================================================
# Fix ownership/permissions on writable volumes.
# ============================================================================
if [ "$(id -u)" = "0" ]; then
    chown -R odoo:odoo /var/lib/odoo /var/log/odoo 2>/dev/null || true
    chmod -R 755 /var/lib/odoo /var/log/odoo 2>/dev/null || true
fi

# ============================================================================
# Set UTF-8 locale for correct Unicode character width calculation.
# ============================================================================
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# ============================================================================
# Load runtime environment and theme colors.
# ============================================================================
ENV_FILE="/home/odoo/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi
CONTAINER_THEME_CONF="/etc/config/odoo/theme.conf"
THEMES_DIR="/etc/themes"

source "$CONTAINER_THEME_CONF" 2>/dev/null
set -a
if [ "${USE_DEFAULT_THEME}" = "true" ] && [ -n "${DEFAULT_THEME}" ] && [ -f "${THEMES_DIR}/${DEFAULT_THEME}.conf" ]; then
    source "${THEMES_DIR}/${DEFAULT_THEME}.conf"
else
    source "${THEMES_DIR}/default.conf" 2>/dev/null
fi
source "$CONTAINER_THEME_CONF" 2>/dev/null
set +a

# ============================================================================
# Compute addon paths from mounted volumes and write them to odoo.conf.
# ============================================================================
ADDON_PATHS=""
if [ -x /usr/local/bin/generate_addons_path.sh ]; then
    ADDON_PATHS=$(/usr/local/bin/generate_addons_path.sh)
fi

# ============================================================================
# Install Python requirements found in addon paths.
# ============================================================================
[ -x /usr/local/bin/check_requirements.sh ] && /usr/local/bin/check_requirements.sh "/mnt/extra-addons"

# ============================================================================
# IoT Box mode: install deps & ensure iot_drivers in server_wide_modules.
# ============================================================================
[ -x /usr/local/bin/check_iot.sh ] && /usr/local/bin/check_iot.sh

# ============================================================================
# Wait for PostgreSQL to be ready before starting Odoo.
# ============================================================================
echo "Waiting for PostgreSQL..."
until pg_isready -h "db" -p "5432" -U "odoo" -q 2>/dev/null; do
    sleep 2
done
echo "PostgreSQL ready"

# ============================================================================
# Dev DB defaults (report.url, enterprise dev tweaks) — only if DB exists and has Odoo tables.
# ============================================================================
[ -x /usr/local/bin/dev_db_bootstrap.sh ] && /usr/local/bin/dev_db_bootstrap.sh

# ============================================================================
# Build module cache (for utils / headers). No -u on cold start — use update (u) or reboot flow.
# ============================================================================
/usr/local/bin/check_modules.sh "" "$ADDON_PATHS"
ODOO_CMD="odoo -c /etc/odoo/odoo.conf"
[ -n "$SELECTED_DB" ] && ODOO_CMD="$ODOO_CMD -d $SELECTED_DB"
[ -n "$ODOO_ARGS" ]   && ODOO_CMD="$ODOO_CMD $ODOO_ARGS"

# ============================================================================
# tmux session: logo pane + Odoo process
# ============================================================================
echo "Starting Odoo in tmux session..."

set -a
source /etc/config/odoo/web-terminal.conf 2>/dev/null
set +a

source /usr/local/bin/hex_to_ansi.sh 2>/dev/null || true

LOGO_HEIGHT=7
IOT_PANE_WIDTH=49

cat > /tmp/.logs_logo.sh << LOGO_EOF
#!/bin/bash
printf '${BPRIMARY}    ____        __                      __                           ${RST}\n'
printf '${BPRIMARY}   / __ \  ____/ / ____    ____        / /    ____    _____   _____  ${RST}\n'
printf '${BPRIMARY}  / / / / / __  / / __ \  / __ \      / /    / __ \  / __  / / ___/  ${RST}\n'
printf '${BPRIMARY} / /_/ / / /_/ / / /_/ / / /_/ /     / /___ / /_/ / / /_/ / (__  )   ${RST}\n'
printf '${BPRIMARY} \____/  \____/  \____/  \____/     /_____/ \____/  \__, / /____/    ${RST}\n'
printf '${BPRIMARY}                                                   /____/            ${RST}\n'
exec sleep infinity
LOGO_EOF
chmod +x /tmp/.logs_logo.sh

_HL="${TMUX_SCROLLBACK:-50000}"
printf "set -g history-limit %s\\n" "$_HL" > /tmp/.odoo_tmux.conf
tmux -f /tmp/.odoo_tmux.conf new-session -d -s logs /tmp/.logs_logo.sh

cat > /tmp/.odoo_runner.sh << RUNNER_EOF
#!/bin/bash
/usr/local/bin/odoo_header.sh "$ODOO_CMD" "$ADDON_PATHS"
exec $ODOO_CMD
RUNNER_EOF
chmod +x /tmp/.odoo_runner.sh

tmux set-option -t logs remain-on-exit on
tmux split-window -t logs:0 -v -p 90 "bash /tmp/.odoo_runner.sh"
tmux select-pane -t logs:0.1
tmux resize-pane -t logs:0.0 -y $LOGO_HEIGHT
tmux select-pane -t logs:0.0 -d

# --- IoT Box async setup (separate pane, right side; -l = new pane width in cols from the start) ---
TMUX_IOT_COLS=""
if [ "${ODOO_IOT_BOX}" = "true" ] && [ -x /usr/local/bin/check_iot_setup.sh ]; then
    tmux split-window -t logs:0.1 -h -l "$IOT_PANE_WIDTH" "IOT_PANE_WIDTH=$IOT_PANE_WIDTH bash /usr/local/bin/check_iot_setup.sh"
    tmux select-pane -t logs:0.1
    TMUX_IOT_COLS="$IOT_PANE_WIDTH"
fi

# --- Reapply history-limit on every window (belt-and-suspenders) ---
for _wi in $(tmux list-windows -t logs -F "#{window_index}" 2>/dev/null); do
    tmux set-option -t "logs:${_wi}" -w history-limit "$_HL"
done

# --- Shared tmux config (keybindings, styles, status bar) ---
source /usr/local/bin/tmux_setup.sh "logs" "$LOGO_HEIGHT" "#(cat /var/shared/.tmux_status_left 2>/dev/null)" "$TMUX_IOT_COLS"

# ============================================================================
# Web terminal: theme & launch (background)
# ============================================================================
source /etc/config/odoo/web-terminal.conf 2>/dev/null
export WEBTERM_CMD="tmux attach-session -t logs"
export WEBTERM_TITLE="Odoo Logs"
source /usr/local/bin/webterm_env.sh

node /opt/web-terminal/server.js &

# ============================================================================
# Keep the container alive and forward signals to child processes.
# ============================================================================
trap 'tmux kill-server 2>/dev/null; kill $(jobs -p) 2>/dev/null; exit 0' SIGTERM SIGINT SIGHUP
while true; do sleep 1 & wait $!; done
