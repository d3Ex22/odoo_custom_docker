#!/bin/zsh
# ============================================================================
# zsh completion for the utils commands (sourced by .config/utils/.zshrc)
# ============================================================================

_UTILS_ROOT=/home/utils/odoo_custom_docker

_get_databases() {
    local cache="/tmp/.zsh_db_cache" ttl=5
    if [ -f "$cache" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0)))
        [ $age -lt $ttl ] && { cat "$cache"; return; }
    fi
    local result
    result=$(docker exec "${COMPOSE_PROJECT_NAME}_db" psql -U odoo -d postgres -tAc \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname;" 2>/dev/null)
    [ -n "$result" ] && echo "$result" > "$cache"
    echo "$result"
}

_get_modules() {
    local cache="$_UTILS_ROOT/.data/volumes/odoo-container/cache/.modules_list"
    [ -f "$cache" ] && tail -1 "$cache" | tr '|' '\n'
}

_get_backup_files() {
    find "$_UTILS_ROOT/db_files" -maxdepth 1 -type f \( -iname "*.sql" -o -iname "*.dump" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" \) 2>/dev/null \
        | xargs -n1 basename 2>/dev/null | sort -r
}

_get_valid_versions() {
    local compat="$_UTILS_ROOT/.data/compat.map" odoo="${ODOO_VERSION}"
    [ ! -f "$compat" ] && return
    case "$1" in
        odoo)     grep -v '^#' "$compat" | grep -v '^$' | cut -d: -f1 | tr -d ' ' ;;
        python)   grep -E "^${odoo}[[:space:]]*:" "$compat" | cut -d: -f3 | tr -d ' ' | tr ',' '\n' ;;
        postgres) grep -E "^${odoo}[[:space:]]*:" "$compat" | cut -d: -f5 | tr -d ' ' | tr ',' '\n' ;;
    esac
}

_global_opts=('-y:Answer yes to confirmations' '--yes:Answer yes to confirmations' '-p:Run in a side pane' '--pane:Run in a side pane' '--no-color:Plain output' '-h:Help' '--help:Help')

_describe_dbs()     { local -a dbs; dbs=(${(f)"$(_get_databases)"}); _describe 'database' dbs; }
_describe_modules() { local -a mods; mods=(${(f)"$(_get_modules)"}); _describe 'module' mods; }
_describe_opts()    { local -a o; o=("$@" "${_global_opts[@]}"); _describe 'option' o; }

_update() {
    if [[ "${words[CURRENT-1]}" == -d || "${words[CURRENT-1]}" == --database ]]; then
        local -a d; d=(${(f)"$(_get_databases)"} 'all:Every Odoo database'); _describe 'database' d
    elif [[ "${words[CURRENT]}" == -* ]]; then
        _describe_opts '-k:Save as ODOO_UPDATE' '--keep:Save as ODOO_UPDATE' '-w:Wait until ready' '--wait:Wait until ready' \
            '-d:Database(s) to update' '--database:Database(s) to update'
    else
        _describe_modules
    fi
}

_test_cmd() {
    if [[ "${words[CURRENT-1]}" == --on ]]; then _describe_dbs
    elif [[ "${words[CURRENT]}" == -* ]]; then
        _describe_opts '-t:Odoo --test-tags' '--tags:Odoo --test-tags' '--on:Test on a copy of this database' \
            '--keep:Keep the test database' '--no-demo:Fresh database without demo data' '-v:Full Odoo log' '--verbose:Full Odoo log' \
            '--coverage:Coverage report of the tested modules'
    else _describe_modules; fi
}

_watch_cmd() { local -a o; o=('on:Start the watcher' 'off:Stop the watcher'); _describe_opts "${o[@]}"; }

_start_cmd() { _describe_opts '-w:Wait until ready' '--wait:Wait until ready'; }

_database() {
    local -a subcommands
    subcommands=(
        'list:List databases and backups'
        'select:Set the active database'
        'drop:Drop a database'
        'clone:Copy a database'
        'backup:Backup to ./db_files'
        'restore:Restore from ./db_files'
        'sanitize:Neutralize / anonymize'
    )
    if (( CURRENT == 2 )); then _describe 'subcommand' subcommands; return; fi
    local cur="${words[CURRENT]}" prev="${words[CURRENT-1]}"
    case "${words[2]}" in
        select) [[ "$cur" == -* ]] && _describe_opts || _describe_dbs ;;
        drop)   [[ "$cur" == -* ]] && _describe_opts '-f:Drop the selected DB and restart Odoo' '--force:Drop the selected DB and restart Odoo' || _describe_dbs ;;
        clone)
            if [[ "$cur" == -* ]]; then _describe_opts '-f:Replace destination' '--force:Replace destination'
            elif (( CURRENT == 3 )); then _describe_dbs; fi ;;
        backup) [[ "$cur" == -* ]] && _describe_opts '-fs:Include filestore' '--filestore:Include filestore' '--keep:Keep only the N latest backups' || _describe_dbs ;;
        restore)
            if [[ "$prev" == (-F|--file) ]]; then
                local -a files; files=(${(f)"$(_get_backup_files)"}); _describe 'backup file' files
            elif [[ "$cur" == -* ]]; then
                _describe_opts '-s:Select the restored DB' '--switch:Select the restored DB' '-f:Replace existing DB' '--force:Replace existing DB' \
                    '-na:Skip neutralize + anonymize' '--no-sanitize:Skip neutralize + anonymize' '-F:Backup file' '--file:Backup file' \
                    '-l:Latest backup of this database' '--last:Latest backup of this database'
            else
                _describe_dbs
            fi ;;
        sanitize)
            if [[ "$prev" == (-F|--file) ]]; then
                local -a files; files=(${(f)"$(_get_backup_files)"}); _describe 'backup file' files
            elif [[ "$cur" == -* ]]; then
                _describe_opts '-a:Neutralize + anonymize' '--all:Neutralize + anonymize' '-F:Backup file' '--file:Backup file'
            else
                _describe_dbs
            fi ;;
    esac
}

_shell_cmd() { _describe_dbs; }

_psql_cmd() {
    if [[ "${words[CURRENT-1]}" == (-d|--database) ]]; then _describe_dbs
    else local -a o; o=('-d:Database' '--database:Database' '-c:Run a command' '-f:Run a file' '-tA:Tuples only, unaligned'); _describe 'option' o; fi
}

_migrate_cmd() {
    if (( CURRENT == 2 )); then _describe_dbs
    elif (( CURRENT == 3 )); then local -a v; v=(${(f)"$(_get_valid_versions odoo)"}); _describe 'version' v; fi
}

_pull_cmd() {
    local -a o; o=('odoo:Odoo source repo' 'enterprise:Enterprise repo' '--build:Target build (latest or YYYYMMDD)' '-f:Discard local changes' '--force:Discard local changes')
    _describe_opts "${o[@]}"
}
_rebuild_cmd() { _describe_opts '-a:Rebuild odoo and db images' '--all:Rebuild odoo and db images' '-n:Latest nightly' '--nightly:Latest nightly' '-nc:No build cache' '--no-cache:No build cache'; }

_translation_cmd() {
    if [[ "${words[CURRENT-1]}" == (-d|--database) ]]; then _describe_dbs
    elif [[ "${words[CURRENT]}" == -* ]]; then
        _describe_opts '-d:Database' '--database:Database' '-l:Language code' '--language:Language code' \
            '--all:Every module of your addons' '-a:Every module of your addons' '-L:Every active language' '--all-langs:Every active language' '--pot:Also export the .pot'
    else _describe_modules; fi
}

_precommit_cmd() { _describe_opts '-a:All modules' '--all:All modules'; }
_upgrade_code_cmd() {
    local -a o
    o=('--from:Source version' '--to:Target version' '--module:Module name(s)' '--dry-run:Preview only' '-f:Run every tool' '--force:Run every tool' '-a:All paths and modules' '--all-files:All paths and modules')
    _describe_opts "${o[@]}"
}
_logs_cmd() {
    if [[ "${words[CURRENT-1]}" == (-g|--grep) ]]; then return
    elif [[ "${words[CURRENT]}" == -* ]]; then _describe_opts '-g:Keep the matching lines' '--grep:Keep the matching lines'
    else _describe_opts 'warning:Warnings and errors (default)' 'error:Errors only' 'critical:Critical only' 'info:Everything but debug' 'debug:Everything'; fi
}
_debug_cmd() { _describe_opts 'on:Odoo under debugpy + launch.json' 'off:Plain start' 'status:State and attach port'; }
_env_update_cmd() { _describe_opts '-n:Preview only' '--dry-run:Preview only' '--ref:Template branch / tag' '--from:Local template copy'; }
_help_cmd() {
    local -a c
    c=(start s stop reboot r update u shell test watch debug logs database db psql rebuild pull env-update translation pre-commit pc requirements pip upgrade-code migrate grok)
    _describe 'command' c
}

# aliases 'u' / 'update' / 'translation' expand to noglob _xxx_fn: complete both names
compdef _update update u _update_fn
compdef _start_cmd start s reboot r
compdef _test_cmd test _test_fn
compdef _watch_cmd watch
compdef _logs_cmd logs
compdef _database database db
compdef _shell_cmd shell
compdef _psql_cmd psql
compdef _migrate_cmd migrate
compdef _rebuild_cmd rebuild
compdef _pull_cmd pull
compdef _translation_cmd translation _translation_fn
compdef _precommit_cmd pre-commit pc
compdef _upgrade_code_cmd upgrade-code
compdef _debug_cmd debug
compdef _env_update_cmd env-update
compdef _help_cmd help
