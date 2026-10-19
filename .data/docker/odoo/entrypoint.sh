#!/bin/bash

# ============================================================================
# Environment scripts: mounted from .data/scripts (rw, so that they can be made
# executable), linked where every script and the utils commands expect them.
# ============================================================================
if [ -d /opt/env/scripts ]; then
    chmod +x /opt/env/scripts/*.sh 2>/dev/null || true
    for _f in /opt/env/scripts/*.sh; do ln -sf "$_f" "/usr/local/bin/$(basename "$_f")"; done
fi

# ============================================================================
# Fix ownership/permissions on writable volumes.
# ============================================================================
if [ "$(id -u)" = "0" ]; then
    chown -R odoo:odoo /var/lib/odoo 2>/dev/null || true
    chmod -R 755 /var/lib/odoo 2>/dev/null || true
fi

# ============================================================================
# Set UTF-8 locale for correct Unicode character width calculation.
# ============================================================================
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# ============================================================================
# Runtime environment (.env), palette (lib/theme.sh) and terminal settings.
# ============================================================================
_PROJECT_FROM_CONTAINER="${COMPOSE_PROJECT_NAME:-}"   # resolved by compose: an empty .env value must not clobber it
set -a
source /home/odoo/.env 2>/dev/null
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$_PROJECT_FROM_CONTAINER}"
source /opt/env/scripts/lib/theme.sh
source /etc/config/terminal.conf 2>/dev/null
set +a

# ============================================================================
# Compute addon paths from mounted volumes and write them to odoo.conf.
# ============================================================================
ADDON_PATHS=""
if [ -x /usr/local/bin/generate_addons_path.sh ]; then
    ADDON_PATHS=$(/usr/local/bin/generate_addons_path.sh)
fi

# ============================================================================
# Outgoing mail: with the 'mail' profile (Mailpit container) odoo.conf falls
# back to it when a database has no active mail server.
# ============================================================================
[ -x /usr/local/bin/mail_catcher.sh ] && /usr/local/bin/mail_catcher.sh conf

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
printf 'Waiting for PostgreSQL...\n'
until pg_isready -h "db" -p "5432" -U "odoo" -q 2>/dev/null; do
    sleep 2
done
printf 'PostgreSQL ready\n'

# ============================================================================
# Dev DB defaults (report.url, enterprise dev tweaks) — only if DB exists and has Odoo tables.
# ============================================================================
[ -x /usr/local/bin/dev_db_bootstrap.sh ] && /usr/local/bin/dev_db_bootstrap.sh

# ============================================================================
# Module name cache (utils completion, headers). No -u on a cold start: 'u'.
# ============================================================================
[ -x /usr/local/bin/check_modules.sh ] && /usr/local/bin/check_modules.sh "$ADDON_PATHS"

# ============================================================================
# tmux session: logo pane + Odoo process (odoo_runner.sh: command from .env,
# header, start guard — the same script start / reboot / update respawn)
# ============================================================================
printf 'Starting Odoo in tmux session...\n'

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

tmux set-option -t logs remain-on-exit on
tmux split-window -t logs:0 -v -p 90 "bash /usr/local/bin/odoo_runner.sh"
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

# --- Shared tmux config (keybindings, styles, status bar) ---
source /usr/local/bin/tmux_setup.sh "logs" "$LOGO_HEIGHT" "#(cat /var/shared/.tmux_status_left 2>/dev/null)" "$TMUX_IOT_COLS"

# ============================================================================
# Web terminal (background, restarted if it dies). Colors: TERM_* exported
# above from lib/theme.sh, font/scrollback: WEBTERM_* from terminal.conf.
# ============================================================================
export WEBTERM_CMD="tmux attach-session -t logs"
export WEBTERM_TITLE="Odoo Logs"
(while true; do python3 /opt/web-terminal/server.py || true; sleep 1; done) &

# ============================================================================
# Keep the container alive and forward signals to child processes.
# ============================================================================
trap 'tmux kill-server 2>/dev/null; kill $(jobs -p) 2>/dev/null; exit 0' SIGTERM SIGINT SIGHUP
while true; do sleep 1 & wait $!; done
