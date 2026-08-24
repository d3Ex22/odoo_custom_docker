#!/bin/bash

# ============================================================================
# Detect the host-side absolute path of the project directory.
# ============================================================================
detect_host_project_dir() {
    local mount_point="/home/utils/odoo_custom_docker"
    local host_path=""

    local container_id=$(hostname 2>/dev/null)

    if [ -n "$container_id" ] && command -v docker &> /dev/null; then
        host_path=$(docker inspect "$container_id" 2>/dev/null | grep -B2 "\"Destination\": \"${mount_point}\"" | grep "\"Source\"" | sed 's/.*"Source": "\(.*\)".*/\1/' | tr -d ',' | xargs)
    fi

    if [ -z "$host_path" ] || [ "$host_path" = "." ]; then
        host_path="$HOST_PROJECT_DIR"
    fi

    if [ -z "$host_path" ] || [ "$host_path" = "." ]; then
        host_path="/unknown"
    fi

    echo "$host_path"
}

HOST_PROJECT_DIR=$(detect_host_project_dir)
echo "$HOST_PROJECT_DIR" > /home/utils/odoo_custom_docker/.data/host_project_path.map

# ============================================================================
# Set UTF-8 locale for correct Unicode character width calculation.
# ============================================================================
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# ============================================================================
# Load runtime environment and resolve color variables.
# ============================================================================
source /home/utils/odoo_custom_docker/.env 2>/dev/null

CONTAINER_THEME_CONF="/home/utils/odoo_custom_docker/.config/utils/theme.conf"
THEMES_DIR="/home/utils/odoo_custom_docker/.data/themes"

source "$CONTAINER_THEME_CONF" 2>/dev/null
set -a
if [ "${USE_DEFAULT_THEME}" = "true" ] && [ -n "${DEFAULT_THEME}" ] && [ -f "${THEMES_DIR}/${DEFAULT_THEME}.conf" ]; then
    source "${THEMES_DIR}/${DEFAULT_THEME}.conf"
else
    source "${THEMES_DIR}/default.conf" 2>/dev/null
fi
source "$CONTAINER_THEME_CONF" 2>/dev/null
set +a
source /home/utils/odoo_custom_docker/.data/scripts/hex_to_ansi.sh

# ============================================================================
# Generate Starship prompt config.
# ============================================================================
ACTIVE_THEME="${THEMES_DIR}/${DEFAULT_THEME:-default}.conf"
[ "${USE_DEFAULT_THEME}" != "true" ] && ACTIVE_THEME="${THEMES_DIR}/default.conf"
THEME_VARS=$(cat "$ACTIVE_THEME" "$CONTAINER_THEME_CONF" 2>/dev/null | grep -oE '^[A-Z_][A-Z_0-9]*' | sed 's/.*/${&}/' | paste -sd ' ')
USER_STARSHIP="/home/utils/odoo_custom_docker/.config/utils/starship.toml"
DEFAULT_STARSHIP="${THEMES_DIR}/starship.toml"
if grep -qvE '^\s*#|^\s*$' "$USER_STARSHIP" 2>/dev/null; then
    STARSHIP_SOURCE="$USER_STARSHIP"
else
    STARSHIP_SOURCE="$DEFAULT_STARSHIP"
fi
envsubst "$THEME_VARS" < "$STARSHIP_SOURCE" > /home/utils/starship.toml
chown utils:utils /home/utils/starship.toml
mkdir -p /home/utils/.cache/starship
chown -R utils:utils /home/utils/.cache
ZSHRC="/home/utils/.zshrc"
MARKER="# --- MANAGED BY ENTRYPOINT ---"
if ! grep -qF "$MARKER" "$ZSHRC" 2>/dev/null; then
    echo "$MARKER" >> "$ZSHRC"
    echo 'eval "$(starship init zsh)"' >> "$ZSHRC"
    cat >> "$ZSHRC" << 'ZSH_REALTIME'
TRAPALRM() {
    if zle && [[ $WIDGET != *complete* && $WIDGET != *menu* ]]; then
        zle reset-prompt
    fi
}
TMOUT=1
ZSH_REALTIME
fi

# ============================================================================
# Ensure all command scripts are executable + shared dir exists.
# ============================================================================
find /home/utils/odoo_custom_docker/.data/scripts/commands -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
mkdir -p /var/shared && chmod 777 /var/shared 2>/dev/null

# utils shell is non-root; allow docker CLI from db/u/rebuild/etc.
if [ -S /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock 2>/dev/null || true
fi


# ============================================================================
# Generate the welcome screen.
# ============================================================================
cat > /home/utils/.welcome << EOF
echo "Available commands (--help for details):"
echo ""
echo "    Odoo:"
printf "     ${CPRIMARY}(r)  ${RST}reboot                        ${CPRIMARY}Restart Odoo                  ${RST}\n"
printf "     ${CPRIMARY}     ${RST}shell [db]                    ${CPRIMARY}Odoo shell (new pane)         ${RST}\n"
printf "     ${CPRIMARY}(s)  ${RST}start                         ${CPRIMARY}Start Odoo process            ${RST}\n"
printf "     ${CPRIMARY}     ${RST}stop                          ${CPRIMARY}Stop Odoo process             ${RST}\n"
printf "     ${CPRIMARY}(u)  ${RST}update [module]               ${CPRIMARY}Update module(s) and restart  ${RST}\n"
echo ""
echo "    Database:"
printf "     ${CPRIMARY}(db) ${RST}database [command]            ${CPRIMARY}Database management           ${RST}\n"
printf "     ${CPRIMARY}     ${RST}psql [--database db]          ${CPRIMARY}PostgreSQL shell              ${RST}\n"
echo ""
echo "    Migration:"
printf "     ${CPRIMARY}     ${RST}migrate <db> <version>        ${CPRIMARY}Migrate database via Odoo     ${RST}\n"
printf "     ${CPRIMARY}     ${RST}upgrade-code --from VER       ${CPRIMARY}Migrate code (19.0+ only)     ${RST}\n"
echo ""
echo "    Docker:"
printf "     ${CPRIMARY}     ${RST}rebuild [--no-cache] [--all]  ${CPRIMARY}Rebuild containers            ${RST}\n"
printf "     ${CPRIMARY}     ${RST}conf <VAR> [value]            ${CPRIMARY}Configure .env settings       ${RST}\n"
printf "     ${CPRIMARY}     ${RST}status                        ${CPRIMARY}Container status              ${RST}\n"
echo ""
echo "    Tools:"
printf "     ${CPRIMARY}     ${RST}check_versions                ${CPRIMARY}Installed versions            ${RST}\n"
printf "     ${CPRIMARY}     ${RST}translation [module|--all]    ${CPRIMARY}Fresh-export / replace fr.po    ${RST}\n"
printf "     ${CPRIMARY}     ${RST}grok                          ${CPRIMARY}Ngrok tunnel                  ${RST}\n"
printf "     ${CPRIMARY}     ${RST}help                          ${CPRIMARY}Show this help                ${RST}\n"
printf "     ${CPRIMARY}     ${RST}pip <command>                 ${CPRIMARY}Pip in Odoo container         ${RST}\n"
printf "     ${CPRIMARY}(pc) ${RST}pre-commit                    ${CPRIMARY}Run pre-commit hooks          ${RST}\n"
printf "     ${CPRIMARY}     ${RST}requirements                  ${CPRIMARY}Install addons requirements   ${RST}\n"
echo ""
EOF
chown utils:utils /home/utils/.welcome

source /home/utils/odoo_custom_docker/.config/utils/web-terminal.conf 2>/dev/null

DECSCUSR="2"
case "${TMUX_CURSOR_STYLE}" in
    block) DECSCUSR="2" ;;
    underline) DECSCUSR="4" ;;
    bar) DECSCUSR="6" ;;
esac
[ "${TMUX_CURSOR_BLINK}" = "true" ] && DECSCUSR=$((DECSCUSR - 1))
MARKER2="# --- CURSOR/WELCOME ---"
if ! grep -qF "$MARKER2" "$ZSHRC" 2>/dev/null; then
    {
        echo "$MARKER2"
        echo "printf '\\033[${DECSCUSR} q'"
        echo 'command clear'
        echo '[ -f /home/utils/.welcome ] && source /home/utils/.welcome'
    } >> "$ZSHRC"
else
    sed -i '/^clear$/c\command clear' "$ZSHRC" 2>/dev/null || true
fi

# ============================================================================
# tmux session: logo pane + interactive zsh
# ============================================================================
LOGO_HEIGHT=6

cat > /tmp/.utils_logo.sh << LOGO_EOF
#!/bin/bash
printf '${BPRIMARY}    ____        __                      __  __  __    _   __         ${RST}\n'
printf '${BPRIMARY}   / __ \  ____/ / ____    ____        / / / / / /_  (_) / / _____   ${RST}\n'
printf '${BPRIMARY}  / / / / / __  / / __ \  / __ \      / / / / / __/ / / / / / ___/   ${RST}\n'
printf '${BPRIMARY} / /_/ / / /_/ / / /_/ / / /_/ /     / /_/ / / /_  / / / / (__  )    ${RST}\n'
printf '${BPRIMARY} \____/  \____/  \____/  \____/      \____/  \__/ /_/ /_/ /____/     ${RST}\n'
exec sleep infinity
LOGO_EOF
chmod +x /tmp/.utils_logo.sh

_HL="${TMUX_SCROLLBACK:-50000}"
printf "set -g history-limit %s\\n" "$_HL" > /tmp/.utils_tmux.conf
tmux -f /tmp/.utils_tmux.conf new-session -d -s utils /tmp/.utils_logo.sh
tmux split-window -t utils:0 -v -p 90 "exec su - utils"

tmux select-pane -t utils:0.1
tmux resize-pane -t utils:0.0 -y $LOGO_HEIGHT

for _wi in $(tmux list-windows -t utils -F "#{window_index}" 2>/dev/null); do
    tmux set-option -t "utils:${_wi}" -w history-limit "$_HL"
done

# --- Shared tmux config (keybindings, styles, status bar) ---
source /home/utils/odoo_custom_docker/.data/scripts/tmux_setup.sh "utils" "$LOGO_HEIGHT" "#(/home/utils/odoo_custom_docker/.data/scripts/status_version.sh 2>/dev/null)"

# ============================================================================
# Web terminal: theme & launch
# ============================================================================
export WEBTERM_CMD="tmux attach-session -t utils"
export WEBTERM_TITLE="Odoo Utils"
source /home/utils/odoo_custom_docker/.data/scripts/webterm_env.sh

sleep 0.5
exec node /opt/web-terminal/server.js
