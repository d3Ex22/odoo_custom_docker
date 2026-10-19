#!/bin/bash

# ============================================================================
# Detect the host-side absolute path of the project directory.
# ============================================================================
detect_host_project_dir() {
    local mount_point="/home/utils/odoo_custom_docker"
    local host_path=""

    local container_id=$(hostname 2>/dev/null)

    if [ -n "$container_id" ] && command -v docker &> /dev/null; then
        host_path=$(docker inspect "$container_id" \
            --format "{{range .Mounts}}{{if eq .Destination \"${mount_point}\"}}{{.Source}}{{end}}{{end}}" 2>/dev/null)
    fi

    if [ -z "$host_path" ] || [ "$host_path" = "." ]; then
        host_path="/unknown"
    fi

    # Docker Desktop records bind sources made from a container (hub start /
    # restart, dc_host) under /host_mnt: keep the real host path.
    echo "${host_path#/host_mnt}"
}

HOST_PROJECT_DIR=$(detect_host_project_dir)
echo "$HOST_PROJECT_DIR" > /home/utils/odoo_custom_docker/.data/host_project_path.map

# ============================================================================
# A project is a plain copy of the template repository: drop the copied .git
# and the files that only serve the template repository (README*, CHANGELOG.md,
# docs/, its .gitignore — addons/ is never touched)
# unless this folder IS the clone (named after the remote repository).
# ============================================================================
PROJECT_ROOT="/home/utils/odoo_custom_docker"
REPO_NAME=""
if [ -e "$PROJECT_ROOT/.git" ]; then
    GIT_DIR_PATH="$PROJECT_ROOT/.git"
    [ -f "$GIT_DIR_PATH" ] && GIT_DIR_PATH=$(sed -n 's/^gitdir: //p' "$GIT_DIR_PATH")   # worktree
    REPO_NAME=$(git config --file "$GIT_DIR_PATH/config" --get remote.origin.url 2>/dev/null | sed -E 's#/+$##; s#.*[/:]##; s/\.git$//')
fi
if [ "$(basename "$HOST_PROJECT_DIR")" != "$REPO_NAME" ]; then
    REMOVED=""
    [ -n "$REPO_NAME" ] && rm -rf "$PROJECT_ROOT/.git" && REMOVED=" .git (from ${REPO_NAME})"   # a .git without remote is the user's
    for f in README.md README.fr.md CHANGELOG.md docs .gitignore; do
        [ -e "$PROJECT_ROOT/$f" ] && rm -rf "$PROJECT_ROOT/$f" && REMOVED="$REMOVED $f"
    done
    [ -n "$REMOVED" ] && echo "Removed${REMOVED}: this folder is a project, not the template clone"
fi

# ============================================================================
# Set UTF-8 locale for correct Unicode character width calculation.
# ============================================================================
export LC_ALL=C.UTF-8
export LANG=C.UTF-8

# ============================================================================
# Runtime environment: the command libraries (.env, palette, set_env_value,
# image tags...). COMPOSE_PROJECT_NAME comes resolved from docker compose
# (folder name unless set in .env); lib/env.sh keeps it over an empty .env value.
# ============================================================================
source /home/utils/odoo_custom_docker/.data/scripts/common.sh
source /home/utils/odoo_custom_docker/.data/scripts/lib/theme.sh   # colours back (dropped by env.sh: no tty here)
export COMPOSE_PROJECT_NAME
# 'su - utils' starts a clean login shell: keep the name where scripts find it.
mkdir -p /var/shared && chmod 777 /var/shared && echo "$COMPOSE_PROJECT_NAME" > /var/shared/.project_name
as_utils() { su utils -s /bin/bash -c "$*"; }

# Image tags carry the Dockerfile revision (ODOO_IMAGE_REV / UTILS_IMAGE_REV):
# keep .env in sync so that 'rebuild' and 'docker compose up' use the right tag.
sync_image_revs && echo "Image revision updated in .env (Dockerfile changed: rebuild builds the new image)"

# ============================================================================
# The primary colour is the project's (hub tab, prompt, titles): hashed from
# its name unless PROJECT_COLOR is set; when another project of this machine
# already shows it, the next free palette colour is written to .env.
# ============================================================================
mkdir -p /var/odoo-env/projects /var/odoo-env/colors
if [ -z "${PROJECT_COLOR:-}" ]; then
    _used=" "
    for _p in /var/odoo-env/projects/*; do
        [ -f "$_p" ] && [ "$(basename "$_p")" != "$COMPOSE_PROJECT_NAME" ] && _used="$_used$(cat "/var/odoo-env/colors/$(basename "$_p")" 2>/dev/null) "
    done
    if [[ "$_used" == *" $THEME_PRIMARY "* ]]; then
        for _c in yellow cyan red purple green orange fg blue; do
            eval "_hex=\$THEME_$(echo "$_c" | tr a-z A-Z)"
            [[ "$_used" == *" $_hex "* ]] && continue
            export PROJECT_COLOR="$_c"; set_env_value PROJECT_COLOR "$_c"
            printf 'PROJECT_COLOR=%s (the colour of the name is already used by another project)\n' "$_c"
            break
        done
    fi
    unset _used _p _c _hex
fi
# Palette and terminal settings exported for tmux, starship and the web terminal
set -a
source /home/utils/odoo_custom_docker/.data/scripts/lib/theme.sh
source /home/utils/odoo_custom_docker/.config/terminal.conf 2>/dev/null
set +a
echo "$THEME_PRIMARY" > "/var/odoo-env/colors/${COMPOSE_PROJECT_NAME}"

# ============================================================================
# SSH_PATH: empty = the ~/.ssh of the user owning the project folder, when it
# holds a key. Written to .env for the next 'docker compose up -d' (the hub
# flags it: .env.applied keeps the values this container was created with).
# ============================================================================
if [ -z "${SSH_PATH:-}" ] && [ "$HOST_PROJECT_DIR" != "/unknown" ]; then
    _home=$(printf '%s' "$HOST_PROJECT_DIR" | sed -nE 's#^(/(Users|home)/[^/]+)/.*#\1#p')
    _img=$(docker inspect "$(hostname)" --format '{{.Config.Image}}' 2>/dev/null)
    if [ -n "$_home" ] && [ -n "$_img" ] \
       && docker run --rm -v "${_home}:/h:ro" --entrypoint sh "$_img" -c 'ls /h/.ssh/id_* >/dev/null 2>&1' 2>/dev/null; then
        cp "$ENV_FILE" /var/shared/.env.applied && chown utils:utils /var/shared/.env.applied
        set_env_value SSH_PATH "${_home}/.ssh"
        printf 'SSH_PATH=%s/.ssh detected: docker compose up -d mounts the keys (pull over ssh)\n' "$_home"
    fi
    unset _home _img
fi

# ============================================================================
# Host ssh keys (SSH_PATH, mounted read-only): copy the keys and known_hosts
# for the utils user so that 'pull' can fetch private repos — only those: the
# host ssh config (other servers, comments) stays out of the container. The
# mount keeps the host ownership, which ssh would refuse — hence the copy.
# ============================================================================
if [ -d /home/utils/.ssh_host ] && ls /home/utils/.ssh_host/id_* >/dev/null 2>&1; then
    mkdir -p /home/utils/.ssh
    cp -L /home/utils/.ssh_host/id_* /home/utils/.ssh/ 2>/dev/null || true
    cp -L /home/utils/.ssh_host/known_hosts /home/utils/.ssh/ 2>/dev/null || true
    chown -R utils:utils /home/utils/.ssh
    chmod 700 /home/utils/.ssh
    chmod 600 /home/utils/.ssh/* 2>/dev/null || true
    chmod 644 /home/utils/.ssh/*.pub /home/utils/.ssh/known_hosts 2>/dev/null || true
fi

# ============================================================================
# Starship prompt: .config/utils/starship.toml with the ${THEME_*} colors.
# ============================================================================
envsubst "$(compgen -v THEME_ | sed 's/.*/${&}/' | paste -sd ' ')" \
    < /home/utils/odoo_custom_docker/.config/utils/starship.toml > /home/utils/starship.toml
chown utils:utils /home/utils/starship.toml
mkdir -p /home/utils/.cache/starship
chown -R utils:utils /home/utils/.cache

# Command scripts executable (git modes are not kept by every checkout).
find /home/utils/odoo_custom_docker/.data/scripts/commands /home/utils/odoo_custom_docker/.data/scripts/internal -maxdepth 1 -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null

# utils shell is non-root; allow docker CLI from db/u/rebuild/etc.
if [ -S /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock 2>/dev/null || true
fi


# ============================================================================
# Generate the welcome screen.
# ============================================================================
# Pre-rendered text, displayed with 'cat' by the 'help' command and on 'clear'.
_w() { printf "   ${CSUCCESS}%-4s${RST} %-36s${CMUTED}%s${RST}\n" "$1" "$2" "$3"; }
_h() { printf "\n ${CPRIMARY}%s${RST}\n" "$1"; }
{
    echo
    _mail=""; [[ "${COMPOSE_PROFILES:-}" == *mail* ]] && _mail=" · mail: http://${COMPOSE_PROJECT_NAME}.mail.docker.localhost"
    printf " ${CPRIMARY}%s${RST}  ${CMUTED}http://%s.odoo.docker.localhost%s · hub: http://odoo.docker.localhost${RST}\n" "$COMPOSE_PROJECT_NAME" "$COMPOSE_PROJECT_NAME" "$_mail"
    printf " ${CMUTED}help <command> for details · flags: -y (no questions)  -p (side pane)${RST}\n"
    _h "Odoo";      _w "s"  "start [-w]"                  "Start Odoo"
                    _w ""   "stop"                        "Stop Odoo"
                    _w "r"  "reboot [-w]"                 "Restart Odoo"
                    _w "u"  "update [-k] [-w] <modules>"  "Restart with -u (-k remembers the list)"
                    _w ""   "shell [db]"                  "Odoo shell (IPython)"
                    _w ""   "test [-t TAGS] <modules>"    "Module tests on a throwaway database"
                    _w ""   "debug [on|off]"              "debugpy + .vscode/launch.json"
                    _w ""   "watch [on|off]"              "u <module> on each saved __manifest__.py"
    _h "Database";  _w "db" "database <cmd>"              "list · select · drop · clone · backup · restore · sanitize"
                    _w ""   "psql [-d db] [args]"         "PostgreSQL shell / query"
    _h "Project";   _w ""   "rebuild [-a] [-n] [-nc]"     "Build the images of .env (missing · all · nightly)"
                    _w ""   "pull [odoo|enterprise]"      "Mounted repos on the ODOO_VERSION branch"
                    _w ""   "env-update [-n]"             "Refresh .data/, compose, docs from the template"
    _h "Code";      _w ""   "translation [modules|--all]" "Re-export i18n/*.po"
                    _w "pc" "pre-commit [folder] [-a]"    "pre-commit hooks on your addons"
                    _w ""   "requirements"                "Install addons requirements.txt"
                    _w ""   "pip <args>"                  "pip in the Odoo venv"
                    _w ""   "upgrade-code --from VER"     "Migrate module code (Odoo 19+)"
                    _w ""   "migrate <db> <version>"      "Upgrade a database via upgrade.odoo.com"
    _h "Other";     _w ""   "grok"                        "ngrok tunnel to Odoo"
                    _w ""   "help [command]"              "This screen / a command's help"
    printf "\n ${CMUTED}Settings (.env), logs, status: hub → this project. Agents: MCP on http://%s.mcp.docker.localhost/mcp${RST}\n" "$COMPOSE_PROJECT_NAME"
    echo
} > /home/utils/.welcome
chown utils:utils /home/utils/.welcome

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

# --- Shared tmux config (keybindings, styles, status bar) ---
source /home/utils/odoo_custom_docker/.data/scripts/tmux_setup.sh "utils" "$LOGO_HEIGHT" "#(cat /var/shared/.tmux_status_left 2>/dev/null)"

# --- Status daemon: one Python process refreshes the status bar files and
#     status.json every 2s for both tmux sessions (Engine API, no docker CLI) ---
as_utils "python3 /home/utils/odoo_custom_docker/.data/scripts/status.py --loop" >/dev/null 2>&1 &

# --- Shared proxy (Traefik + hub, .data/proxy): start it when missing so that
#     *.docker.localhost reaches this project. Background: the first start
#     pulls the images (retried a few times). ---
(for _i in $(seq 1 10); do
    as_utils "bash -c 'source /home/utils/odoo_custom_docker/.data/scripts/common.sh && ensure_proxy'" >/dev/null 2>&1 && break
    sleep 3
done) &

# --- MCP server for AI agents (always on) ---
as_utils "bash /home/utils/odoo_custom_docker/.data/scripts/internal/mcp.sh start" >/dev/null 2>&1 || true

# --- Auto-update watcher pane (AUTO_UPDATE=true, see 'watch') ---
(sleep 2; as_utils "bash /home/utils/odoo_custom_docker/.data/scripts/commands/watch.sh --resume" >/dev/null 2>&1) &

# --- Shared images: record this project's use, drop the ones unused for
#     IMAGE_RETENTION_DAYS — at start, then once a day (log in the odoo_env_meta volume) ---
mkdir -p /var/odoo-env/projects && chown -R utils:utils /var/odoo-env 2>/dev/null
# Registry read by the hub: known projects can be started from the page
[ "$HOST_PROJECT_DIR" != "/unknown" ] && echo "$HOST_PROJECT_DIR" > "/var/odoo-env/projects/${COMPOSE_PROJECT_NAME}"
rm -f "/var/odoo-env/progress/${COMPOSE_PROJECT_NAME}"   # step of a 'rebuild' shown by the hub: over once this container is up
(sleep 20; while true; do as_utils "bash /home/utils/odoo_custom_docker/.data/scripts/internal/prune.sh" >> /var/odoo-env/prune.log 2>&1; sleep 86400; done) &

# ============================================================================
# Web terminal (foreground). Colors: TERM_* exported above from lib/theme.sh,
# font/scrollback: WEBTERM_* from terminal.conf.
# ============================================================================
export WEBTERM_CMD="tmux attach-session -t utils"
export WEBTERM_TITLE="Odoo Utils"
exec python3 /home/utils/odoo_custom_docker/.data/web-terminal/server.py
