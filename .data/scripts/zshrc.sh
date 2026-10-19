#!/bin/zsh
# ============================================================================
# zshrc.sh — shell of the utils container: Oh My Zsh, completion, palette,
# the command functions (one per script in .data/scripts/commands/), help,
# commands handed over by the hub. Owned by the environment (env-update).
# Personal additions go to .config/utils/.zshrc (sourced after this file).
# ============================================================================
export LC_ALL=C.UTF-8 LANG=C.UTF-8

# -----------------------------------------------------------------------
# Oh My Zsh
# -----------------------------------------------------------------------
ZSH_THEME=""
plugins=(history zsh-autosuggestions zsh-syntax-highlighting you-should-use)
zstyle ':omz:update' mode disabled
source $ZSH/oh-my-zsh.sh

# -----------------------------------------------------------------------
# Completion
# -----------------------------------------------------------------------
[ -f /home/utils/odoo_custom_docker/.data/scripts/completion.sh ] && \
    source /home/utils/odoo_custom_docker/.data/scripts/completion.sh

# -----------------------------------------------------------------------
# Environment & palette
# su - utils creates a fresh login shell: the entrypoint variables are not
# inherited, load .env and the palette here.
# -----------------------------------------------------------------------
# Project name resolved by compose (folder name), written by the entrypoint
_PROJECT_FROM_CONTAINER="${COMPOSE_PROJECT_NAME:-$(cat /var/shared/.project_name 2>/dev/null)}"
[ -f /home/utils/odoo_custom_docker/.env ] && source /home/utils/odoo_custom_docker/.env
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME:-$_PROJECT_FROM_CONTAINER}"; unset _PROJECT_FROM_CONTAINER

source /home/utils/odoo_custom_docker/.data/scripts/lib/theme.sh
# Terminal settings (clock time zone, same as the tmux status bar)
source /home/utils/odoo_custom_docker/.config/terminal.conf 2>/dev/null
export TZ="${TERMINAL_TZ:-UTC}"

# -----------------------------------------------------------------------
# Syntax highlighting (zsh-syntax-highlighting), colors from lib/theme.sh
# -----------------------------------------------------------------------
ZSH_HIGHLIGHT_STYLES[command]="fg=${THEME_GREEN},bold"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=${THEME_GREEN}"
ZSH_HIGHLIGHT_STYLES[alias]="fg=${THEME_GREEN}"
ZSH_HIGHLIGHT_STYLES[function]="fg=${THEME_GREEN}"
ZSH_HIGHLIGHT_STYLES[unknown-command]="fg=${THEME_RED},bold"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${THEME_PURPLE},italic"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=${THEME_YELLOW}"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=${THEME_YELLOW}"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=${THEME_YELLOW}"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=${THEME_ORANGE},bold"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${THEME_MUTED}"
ZSH_HIGHLIGHT_STYLES[process-substitution]="fg=${THEME_PURPLE}"
ZSH_HIGHLIGHT_STYLES[comment]="fg=${THEME_MUTED},italic"
ZSH_HIGHLIGHT_STYLES[path]="fg=${THEME_CYAN}"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=${THEME_BLUE}"
ZSH_HIGHLIGHT_STYLES[assign]="fg=${THEME_CYAN}"

# -----------------------------------------------------------------------
# Commands — one function per script in .data/scripts/commands/
# (functions, not aliases: completion-aware and usable from scripts)
# -----------------------------------------------------------------------
_CMDS=/home/utils/odoo_custom_docker/.data/scripts/commands

# Odoo process
start()          { "$_CMDS/start.sh" "$@"; }
stop()           { "$_CMDS/stop.sh" "$@"; }
reboot()         { "$_CMDS/reboot.sh" "$@"; }
_update_fn()     { "$_CMDS/update.sh" "$@"; }
alias update='noglob _update_fn'
alias u='noglob _update_fn'
alias s='start'
alias r='reboot'
shell()          { "$_CMDS/shell.sh" "$@"; }
_test_fn()       { "$_CMDS/test.sh" "$@"; }
watch()          { "$_CMDS/watch.sh" "$@"; }
alias test='noglob _test_fn'   # alias (not function): the builtin stays available to scripts
debug()          { "$_CMDS/debug.sh" "$@"; }

# Database
database()       { "$_CMDS/database.sh" "$@"; }
db()             { "$_CMDS/database.sh" "$@"; }
psql()           { "$_CMDS/psql.sh" "$@"; }

# Project
rebuild()        { "$_CMDS/rebuild.sh" "$@"; }
pull()           { "$_CMDS/pull.sh" "$@"; }
env-update()     { "$_CMDS/env-update.sh" "$@"; }

# Code tools
_translation_fn() { "$_CMDS/translation.sh" "$@"; }
alias translation='noglob _translation_fn'
pre-commit()     { "$_CMDS/pre-commit.sh" "$@"; }
alias pc='pre-commit'
requirements()   { "$_CMDS/requirements.sh" "$@"; }
pip()            { "$_CMDS/pip.sh" "$@"; }
upgrade-code()   { "$_CMDS/upgrade-code.sh" "$@"; }
migrate()        { "$_CMDS/migrate.sh" "$@"; }
grok()           { "$_CMDS/grok.sh" "$@"; }

# -----------------------------------------------------------------------
# Prompt (starship, colours substituted by the entrypoint), live clock,
# cursor shape (terminal.conf), welcome screen
# -----------------------------------------------------------------------
eval "$(starship init zsh)"
TRAPALRM() { if zle && [[ $WIDGET != *complete* && $WIDGET != *menu* ]]; then zle reset-prompt; fi; }
TMOUT=1
case "${TMUX_CURSOR_STYLE:-block}" in underline) _cur=4 ;; bar) _cur=6 ;; *) _cur=2 ;; esac
[ "${TMUX_CURSOR_BLINK:-false}" = "true" ] && _cur=$((_cur - 1))
printf '\033[%s q' "$_cur"; unset _cur
command clear
[ -f /home/utils/.welcome ] && cat /home/utils/.welcome

# help                 → welcome screen
# help <command> [sub] → that command's --help (help db restore)
help() {
    # eval so that aliases (u, test, pc, ...) expand like on the command line
    if [ -n "$1" ]; then eval "${(q)@} --help"; else cat /home/utils/.welcome; fi
}
alias clear="command clear && cat /home/utils/.welcome"

# -----------------------------------------------------------------------
# Commands handed over by the hub (rebuild after a .env change...). At an idle
# prompt the hub types them in this terminal directly (tmux send-keys); while
# a command runs here they wait in /var/shared/.hub_command and start when it
# returns (precmd), so their prompts (confirmations) are answered here.
# -----------------------------------------------------------------------
_hub_pending() {
    local f=/var/shared/.hub_command cmd
    [ -s "$f" ] || return 0
    cmd=$(<"$f"); rm -f "$f"
    [ -n "$cmd" ] || return 0
    print -s -- "$cmd"; print -P "%F{cyan}› hub:%f $cmd"; eval "$cmd"
}
autoload -Uz add-zsh-hook && add-zsh-hook precmd _hub_pending
