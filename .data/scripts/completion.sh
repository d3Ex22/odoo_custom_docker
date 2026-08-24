#!/bin/zsh
# Auto-completion for Odoo utils commands — zsh native

_get_databases() {
    local project="${COMPOSE_PROJECT_NAME}"
    local cache="/tmp/.zsh_db_cache"
    local ttl=5
    if [ -f "$cache" ]; then
        local age=$(($(date +%s) - $(stat -c %Y "$cache" 2>/dev/null || echo 0)))
        if [ $age -lt $ttl ]; then
            cat "$cache"
            return
        fi
    fi
    local result
    result=$(docker exec "${project}_db" psql -U "odoo" -d postgres -tAc \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres' ORDER BY datname;" 2>/dev/null)
    [ -n "$result" ] && echo "$result" > "$cache"
    echo "$result"
}

_get_modules() {
    local cache="/home/utils/odoo_custom_docker/.data/volumes/odoo-container/cache/.modules_list"
    [ -f "$cache" ] && tail -1 "$cache" | tr '|' '\n'
}

_get_valid_versions() {
    local type="$1"
    local compat_file="/home/utils/odoo_custom_docker/.data/compat.map"
    local odoo="${ODOO_VERSION}"
    [ ! -f "$compat_file" ] && return
    case "$type" in
        odoo)     grep -v '^#' "$compat_file" | grep -v '^$' | cut -d: -f1 | tr -d ' ' ;;
        python)   grep -E "^${odoo}[[:space:]]*:" "$compat_file" | cut -d: -f3 | tr -d ' ' | tr ',' '\n' ;;
        postgres) grep -E "^${odoo}[[:space:]]*:" "$compat_file" | cut -d: -f5 | tr -d ' ' | tr ',' '\n' ;;
    esac
}

_update() {
    local -a modules
    modules=(${(f)"$(_get_modules)"})
    _describe 'module' modules
}

_database() {
    local -a subcommands
    subcommands=(
        'sanitize:Neutralize / anonymize (DB or file)'
        'backup:Backup database'
        'drop:Drop database'
        'clone:Clone database'
        'list:List databases'
        'restore:Restore database'
        'select:Select active database'
    )

    if (( CURRENT == 2 )); then
        _describe 'subcommand' subcommands
        return
    fi

    local -a dbs
    dbs=(${(f)"$(_get_databases)"})

    case "${words[2]}" in
        backup|drop|clone|select)
            _describe 'database' dbs
            ;;
        sanitize)
            if [[ "${words[CURRENT]}" == -* ]]; then
                local -a sopts
                sopts=(
                    '-a:Neutralize + anonymize'
                    '--all:Neutralize + anonymize'
                    '-f:Backup file under db_files'
                    '--file:Backup file under db_files'
                )
                _describe 'option' sopts
            elif [[ "${words[CURRENT-1]}" == (-f|--file) ]]; then
                _path_files -W "/home/utils/odoo_custom_docker/db_files"
            else
                _describe 'database' dbs
            fi
            ;;
        restore)
            if [[ "${words[CURRENT]}" == -* ]]; then
                local -a opts
                opts=('-s:Switch to restored DB' '--switch:Switch to restored DB' '-na:Skip anonymization' '--no-anon:Skip anonymization' '-f:Overwrite existing DB' '--force:Overwrite existing DB')
                _describe 'option' opts
            else
                _describe 'database' dbs
            fi
            ;;
    esac
}

_shell_cmd() {
    local -a dbs
    dbs=(${(f)"$(_get_databases)"})
    _describe 'database' dbs
}

_psql_cmd() {
    if [[ "${words[CURRENT-1]}" == (-d|--database) ]]; then
        local -a dbs
        dbs=(${(f)"$(_get_databases)"})
        _describe 'database' dbs
    else
        local -a opts
        opts=('-d:Database name' '--database:Database name')
        _describe 'option' opts
    fi
}

_migrate_cmd() {
    if (( CURRENT == 2 )); then
        local -a dbs
        dbs=(${(f)"$(_get_databases)"})
        _describe 'database' dbs
    elif (( CURRENT == 3 )); then
        local -a versions
        versions=('19.0' '18.0' '17.0' '16.0' '15.0')
        _describe 'version' versions
    fi
}

_rebuild_cmd() {
    local -a opts
    opts=('-nc:Skip cache' '--no-cache:Skip cache' '-a:Rebuild all containers' '--all:Rebuild all containers' '-h:Show help' '--help:Show help')
    _describe 'option' opts
}

_set_cmd() {
    local -a vars
    vars=(
        'SELECTED_DB:Active database'
        'ODOO_UPDATE:Modules to update on start'
        'ODOO_ARGS:Extra Odoo CLI arguments'
        'ODOO_VERSION:Odoo version (requires rebuild)'
        'ODOO_BUILD:Build date or latest (requires rebuild)'
        'PYTHON_VERSION:Python version (requires rebuild)'
        'POSTGRES_VERSION:PostgreSQL version (requires rebuild)'
    )

    if (( CURRENT == 2 )); then
        _describe 'variable' vars
        return
    fi

    case "${words[2]}" in
        SELECTED_DB)
            local -a dbs
            dbs=(${(f)"$(_get_databases)"} '-')
            _describe 'database' dbs
            ;;
        ODOO_UPDATE)
            local -a modules
            modules=(${(f)"$(_get_modules)"} '-')
            _describe 'module' modules
            ;;
        ODOO_VERSION)
            local -a versions
            versions=(${(f)"$(_get_valid_versions odoo)"})
            _describe 'version' versions
            ;;
        ODOO_BUILD)
            local -a builds
            builds=('latest')
            _describe 'build' builds
            ;;
        PYTHON_VERSION)
            local -a versions
            versions=(${(f)"$(_get_valid_versions python)"})
            _describe 'version' versions
            ;;
        POSTGRES_VERSION)
            local -a versions
            versions=(${(f)"$(_get_valid_versions postgres)"})
            _describe 'version' versions
            ;;
        ODOO_ARGS)
            local -a args
            args=('-:Clear value' '--dev xml:Hot-reload XML views' '--limit-time-real 0:Disable timeout' '--log-level=debug:Debug logging')
            _describe 'argument' args
            ;;
    esac
}

_translation_cmd() {
    if [[ "${words[CURRENT-1]}" == (-d|--database) ]]; then
        local -a dbs
        dbs=(${(f)"$(_get_databases)"})
        _describe 'database' dbs
    elif [[ "${words[CURRENT]}" == -* ]]; then
        local -a opts
        opts=(
            '-d:Database name'
            '--database:Database name'
            '-l:Language code'
            '--language:Language code'
            '--all:Export every module under extra-addons'
            '-a:Export all active languages'
            '--all-langs:Export all active languages'
            '--pot:Also export template POT file'
            '--no-restart:Do not restart Odoo after export'
            '-h:Show help'
            '--help:Show help'
        )
        _describe 'option' opts
    else
        _update
    fi
}

compdef _update update u
compdef _translation_cmd translation i18n-export i18n
compdef _database database db
compdef _shell_cmd shell
compdef _psql_cmd psql
compdef _migrate_cmd migrate
compdef _rebuild_cmd rebuild
compdef _set_cmd conf
