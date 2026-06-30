# ============================================================================
# Utils container ZSH configuration — edit freely, no rebuild required.
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
# Theme & environment
# su - utils creates a fresh login shell, env vars from root entrypoint are
# not inherited. Load the theme directly here.
# -----------------------------------------------------------------------
[ -f /home/utils/odoo_custom_docker/.env ] && source /home/utils/odoo_custom_docker/.env

_THEME_CONF="/home/utils/odoo_custom_docker/.config/utils/theme.conf"
_THEMES_DIR="/home/utils/odoo_custom_docker/.data/themes"
source "$_THEME_CONF" 2>/dev/null
if [ "${USE_DEFAULT_THEME}" = "true" ] && [ -n "${DEFAULT_THEME}" ] && [ -f "${_THEMES_DIR}/${DEFAULT_THEME}.conf" ]; then
    source "${_THEMES_DIR}/${DEFAULT_THEME}.conf"
else
    source "${_THEMES_DIR}/default.conf" 2>/dev/null
fi
source "$_THEME_CONF" 2>/dev/null
unset _THEME_CONF _THEMES_DIR

# -----------------------------------------------------------------------
# Syntax highlighting styles (colors from utils/theme.conf)
# -----------------------------------------------------------------------
ZSH_HIGHLIGHT_STYLES[command]="fg=${ZSH_HL_COMMAND},bold"
ZSH_HIGHLIGHT_STYLES[unknown-command]="fg=${ZSH_HL_UNKNOWN_COMMAND},bold"
ZSH_HIGHLIGHT_STYLES[builtin]="fg=${ZSH_HL_BUILTIN}"
ZSH_HIGHLIGHT_STYLES[alias]="fg=${ZSH_HL_ALIAS}"
ZSH_HIGHLIGHT_STYLES[function]="fg=${ZSH_HL_FUNCTION}"
ZSH_HIGHLIGHT_STYLES[precommand]="fg=${ZSH_HL_PRECOMMAND},italic"
ZSH_HIGHLIGHT_STYLES[single-quoted-argument]="fg=${ZSH_HL_STRING}"
ZSH_HIGHLIGHT_STYLES[double-quoted-argument]="fg=${ZSH_HL_STRING}"
ZSH_HIGHLIGHT_STYLES[dollar-quoted-argument]="fg=${ZSH_HL_STRING}"
ZSH_HIGHLIGHT_STYLES[redirection]="fg=${ZSH_HL_REDIRECTION},bold"
ZSH_HIGHLIGHT_STYLES[commandseparator]="fg=${ZSH_HL_SEPARATOR}"
ZSH_HIGHLIGHT_STYLES[process-substitution]="fg=${ZSH_HL_PROCESS}"
ZSH_HIGHLIGHT_STYLES[comment]="fg=${ZSH_HL_COMMENT},italic"
ZSH_HIGHLIGHT_STYLES[path]="fg=${ZSH_HL_PATH}"
ZSH_HIGHLIGHT_STYLES[globbing]="fg=${ZSH_HL_GLOBBING}"
ZSH_HIGHLIGHT_STYLES[assign]="fg=${ZSH_HL_ASSIGN}"

# -----------------------------------------------------------------------
# Commands — functions (completion-aware)
# -----------------------------------------------------------------------
_update_fn() { /home/utils/odoo_custom_docker/.data/scripts/commands/update.sh "$@"; }
alias update='noglob _update_fn'
alias u='noglob _update_fn'
conf()     { /home/utils/odoo_custom_docker/.data/scripts/commands/set.sh "$@"; }
database() { /home/utils/odoo_custom_docker/.data/scripts/commands/database.sh "$@"; }
db()       { /home/utils/odoo_custom_docker/.data/scripts/commands/database.sh "$@"; }
shell()    { /home/utils/odoo_custom_docker/.data/scripts/commands/shell.sh "$@"; }
psql()     { /home/utils/odoo_custom_docker/.data/scripts/commands/psql.sh "$@"; }
migrate()  { /home/utils/odoo_custom_docker/.data/scripts/commands/migrate.sh "$@"; }
rebuild()  { /home/utils/odoo_custom_docker/.data/scripts/commands/rebuild.sh "$@"; }
_i18n_export_fn() { /home/utils/odoo_custom_docker/.data/scripts/commands/i18n-export.sh "$@"; }
alias i18n-export='noglob _i18n_export_fn'
alias i18n='noglob _i18n_export_fn'

# -----------------------------------------------------------------------
# Commands — aliases (no completion needed)
# -----------------------------------------------------------------------
alias clear="command clear && source /home/utils/.welcome"
alias reboot="/home/utils/odoo_custom_docker/.data/scripts/commands/reboot.sh"
alias r="reboot"
alias start="/home/utils/odoo_custom_docker/.data/scripts/commands/start.sh"
alias s="start"
alias stop="/home/utils/odoo_custom_docker/.data/scripts/commands/stop.sh"
alias status="/home/utils/odoo_custom_docker/.data/scripts/commands/status.sh"
alias check_versions="/home/utils/odoo_custom_docker/.data/scripts/commands/check_versions.sh"
alias grok="/home/utils/odoo_custom_docker/.data/scripts/commands/grok.sh"
alias help="source /home/utils/.welcome"
alias pip="/home/utils/odoo_custom_docker/.data/scripts/commands/pip.sh"
alias pre-commit="/home/utils/odoo_custom_docker/.data/scripts/commands/pre-commit.sh"
alias pc="pre-commit"
alias requirements="/home/utils/odoo_custom_docker/.data/scripts/commands/requirements.sh"
alias upgrade-code="/home/utils/odoo_custom_docker/.data/scripts/commands/upgrade-code.sh"
