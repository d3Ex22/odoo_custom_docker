#!/bin/bash

# ============================================
# 1. FIX PERMISSIONS
# ============================================
if [ "$(id -u)" = "0" ]; then
    chown -R odoo:odoo /var/lib/odoo /var/log/odoo 2>/dev/null || true
    chmod -R 755 /var/lib/odoo /var/log/odoo 2>/dev/null || true
fi

# ============================================
# 2. LOAD ENVIRONMENT
# ============================================
ENV_FILE="/home/odoo/.env"
if [ -f "$ENV_FILE" ]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

# ============================================
# 3. GENERATE ADDONS PATH
# ============================================
ADDON_PATHS=""
if [ -x /usr/local/bin/generate_addons_path.sh ]; then
    ADDON_PATHS=$(/usr/local/bin/generate_addons_path.sh)
fi

# ============================================
# 4. CHECK & INSTALL REQUIREMENTS
# ============================================
[ -x /usr/local/bin/check_requirements.sh ] && /usr/local/bin/check_requirements.sh

# ============================================
# 5. WAIT FOR POSTGRES
# ============================================
echo "Waiting for PostgreSQL..."
until pg_isready -h "${DB_HOST:-db}" -p "${DB_PORT:-5432}" -U "${DB_USER:-odoo}" -q 2>/dev/null; do
    sleep 2
done
echo "PostgreSQL ready"

# ============================================
# 6. CHECK MODULE NAMES
# ============================================
[ -n "$ODOO_UPDATE" ] && [ -x /usr/local/bin/check_modules.sh ] && /usr/local/bin/check_modules.sh "$ODOO_UPDATE"

# ============================================
# 7. BUILD ODOO COMMAND
# ============================================
ODOO_CMD="odoo -c /etc/odoo/odoo.conf"
[ -n "$SELECTED_DB" ] && ODOO_CMD="$ODOO_CMD -d $SELECTED_DB"
[ -n "$ODOO_ARGS" ] && ODOO_CMD="$ODOO_CMD $ODOO_ARGS"
[ -n "$ODOO_UPDATE" ] && ODOO_CMD="$ODOO_CMD -u $ODOO_UPDATE"

# ============================================
# 8. START ODOO IN TMUX
# ============================================
echo "Starting Odoo in tmux session..."

# Build colored PS1 for shell prompt (using LOGS_COLOR)
LOGS_COLOR="${LOGS_COLOR:-#8be9fd}"
LR=$((16#${LOGS_COLOR:1:2}))
LG=$((16#${LOGS_COLOR:3:2}))
LB=$((16#${LOGS_COLOR:5:2}))
COLORED_PS1="\\[\\033[38;2;${LR};${LG};${LB}m\\]\\u@\\h:\\w\\$\\[\\033[0m\\] "

tmux new-session -d -s odoo bash
tmux send-keys -t odoo:0 "export PS1='$COLORED_PS1'" Enter
tmux send-keys -t odoo:0 "clear" Enter

# Display startup messages
sleep 0.2
PTY=$(tmux list-panes -t odoo -F '#{pane_tty}' 2>/dev/null)
printf "Detected addon paths: \033[38;2;${LR};${LG};${LB}m%s\033[0m\n" "$ADDON_PATHS" > "$PTY"
printf "Odoo started: \033[38;2;${LR};${LG};${LB}m%s\033[0m\n\n" "$ODOO_CMD" > "$PTY"

tmux send-keys -t odoo:0 "$ODOO_CMD" Enter
tmux set-option -t odoo remain-on-exit on
tmux set-option -g mouse on
tmux set-option -g history-limit 50000
tmux set-option -g status off

# ============================================
# 9. KEEP CONTAINER ALIVE (handle SIGTERM gracefully)
# ============================================
trap 'kill $(jobs -p) 2>/dev/null; exit 0' SIGTERM SIGINT SIGHUP
while true; do sleep 1 & wait $!; done
