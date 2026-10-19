#!/bin/bash
# ============================================================================
# lib/theme.sh — the one palette of the environment ("Night City").
# Hub (static/hub.css :root keeps the same values), terminals (xterm.js), tmux,
# prompt (starship.toml placeholders) and the scripts' output all use it.
# Sourced by lib/env.sh (every command), both entrypoints, the status daemon,
# the odoo-side scripts and the utils .zshrc (plain assignments: bash and zsh).
# ============================================================================

# --- Palette -----------------------------------------------------------------
THEME_BG="#07070b"        # terminal and tmux background
THEME_SURFACE="#0e0e15"   # panels, ANSI black
THEME_LINE="#1c1c28"      # borders
THEME_FG="#e9e9f2"
THEME_MUTED="#6c6c86"
THEME_RED="#ff2a5f"       # errors, alerts, brand
THEME_ORANGE="#ff9f1c"    # warnings
THEME_YELLOW="#fcee0a"    # hub brand, python
THEME_GREEN="#39ff14"     # success
THEME_CYAN="#00f0ff"      # accent: paths, links, values
THEME_BLUE="#3d7bff"      # info / debug
THEME_PURPLE="#b967ff"    # Odoo

# --- Primary: the colour of the project, the same as its tab in the hub -------
# Picked from the project name with the hash of static/hub.js colors() (keep
# both in sync); PROJECT_COLOR in .env (a palette name or #rrggbb) overrides it.
theme_project_color() {   # theme_project_color NAME → #rrggbb
    local name="$1" h=0 i c
    for ((i = 0; i < ${#name}; i++)); do
        printf -v c '%d' "'${name:$i:1}"
        h=$(( (h * 31 + c) & 0xFFFFFFFF ))
    done
    case $((h % 7)) in
        0) echo "$THEME_YELLOW" ;; 1) echo "$THEME_CYAN" ;; 2) echo "$THEME_RED" ;; 3) echo "$THEME_PURPLE" ;;
        4) echo "$THEME_GREEN" ;; 5) echo "$THEME_ORANGE" ;; *) echo "$THEME_FG" ;;
    esac
}
case "${PROJECT_COLOR:-}" in
    yellow|cyan|red|purple|green|orange|fg|blue)
        eval "THEME_PRIMARY=\"\$THEME_$(printf '%s' "$PROJECT_COLOR" | tr a-z A-Z)\"" ;;
    "#"*) THEME_PRIMARY="$PROJECT_COLOR" ;;
    *) THEME_PRIMARY=$(theme_project_color "${COMPOSE_PROJECT_NAME:-$(cat /var/shared/.project_name 2>/dev/null)}") ;;
esac
# Prompt segments around the primary one (starship.toml): never the same colour
THEME_PROMPT_USER="$THEME_RED";    [ "$THEME_PRIMARY" = "$THEME_RED" ]    && THEME_PROMPT_USER="$THEME_ORANGE"
THEME_PROMPT_GIT="$THEME_CYAN";    [ "$THEME_PRIMARY" = "$THEME_CYAN" ]   && THEME_PROMPT_GIT="$THEME_GREEN"
THEME_PROMPT_TIME="$THEME_PURPLE"; [ "$THEME_PRIMARY" = "$THEME_PURPLE" ] && THEME_PROMPT_TIME="$THEME_BLUE"

# --- Roles used by the scripts' output (C* normal / B* bold, see below) -------
COLOR_PRIMARY="$THEME_PRIMARY"
COLOR_ACCENT="$THEME_CYAN"
COLOR_MUTED="$THEME_MUTED"
COLOR_SUCCESS="$THEME_GREEN"
COLOR_WARN="$THEME_ORANGE"
COLOR_ERROR="$THEME_RED"
COLOR_FG="$THEME_FG"

# --- tmux (tmux_setup.sh, status.py) -----------------------------------------
TMUX_BG="$THEME_BG"
TMUX_FG="$THEME_FG"
TMUX_BORDER="$THEME_LINE"      # discreet line between the panes
TMUX_STATUS_BG="$THEME_BG"
TMUX_STATUS_FG="$THEME_MUTED"
TMUX_ODOO_COLOR="$THEME_PURPLE"
TMUX_PY_COLOR="$THEME_YELLOW"
TMUX_PG_COLOR="$THEME_BLUE"
TMUX_ALERT_FG="$THEME_BG"
TMUX_ALERT_BG="$THEME_RED"

# --- xterm.js (web-terminal/server.py reads TERM_*) --------------------------
TERM_BG="$THEME_BG"
TERM_FG="$THEME_FG"
TERM_CURSOR="$THEME_PRIMARY"
TERM_SELECTION="$THEME_LINE"
TERM_BLACK="$THEME_SURFACE"
TERM_RED="$THEME_RED"
TERM_GREEN="$THEME_GREEN"
TERM_YELLOW="$THEME_YELLOW"
TERM_BLUE="$THEME_BLUE"
TERM_MAGENTA="$THEME_PURPLE"
TERM_CYAN="$THEME_CYAN"
TERM_WHITE="$THEME_FG"
TERM_BRIGHT_BLACK="$THEME_MUTED"
TERM_BRIGHT_RED="$THEME_RED"
TERM_BRIGHT_GREEN="$THEME_GREEN"
TERM_BRIGHT_YELLOW="$THEME_ORANGE"
TERM_BRIGHT_BLUE="$THEME_BLUE"
TERM_BRIGHT_MAGENTA="$THEME_PURPLE"
TERM_BRIGHT_CYAN="$THEME_CYAN"
TERM_BRIGHT_WHITE="#ffffff"

# --- ANSI sequences for bash scripts: CPRIMARY, BPRIMARY, CMUTED, ... + RST --
# (zsh only needs the hex values above)
if [ -n "${BASH_VERSION:-}" ]; then
    RST=$'\033[0m'
    _theme_ansi() {   # _theme_ansi "1;"|"" "#rrggbb"
        local h="${2#\#}"
        printf '\033[%s38;2;%d;%d;%dm' "$1" "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"
    }
    for _role in PRIMARY ACCENT MUTED SUCCESS WARN ERROR FG; do
        _hex="COLOR_${_role}"
        printf -v "C${_role}" '%s' "$(_theme_ansi "" "${!_hex}")"
        printf -v "B${_role}" '%s' "$(_theme_ansi "1;" "${!_hex}")"
    done
    unset _role _hex
fi
