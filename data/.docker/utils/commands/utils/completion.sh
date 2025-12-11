#!/bin/bash
# Auto-completion for Odoo utils commands

_get_databases() {
    local project="${COMPOSE_PROJECT_NAME:-odoo}"
    local db_user="${POSTGRES_USER:-odoo}"
    docker exec "${project}_db" psql -U "$db_user" -d postgres -tAc \
        "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres' ORDER BY datname;" 2>/dev/null
}

_get_modules() {
    local modules=""
    local addons_base="/home/odoo/docker_dev/addons"
    local odoo_src="/home/odoo/odoo_src"
    
    if [ -d "$addons_base" ]; then
        for dir in "$addons_base"/*/; do
            [ -f "${dir}__manifest__.py" ] && modules="$modules $(basename "$dir")"
        done
        for dir in "$addons_base"/*/*/; do
            [ -f "${dir}__manifest__.py" ] && modules="$modules $(basename "$dir")"
        done
    fi
    
    if [ -d "$odoo_src/addons" ]; then
        for dir in "$odoo_src/addons/"*/; do
            [ -f "${dir}__manifest__.py" ] && modules="$modules $(basename "$dir")"
        done
    fi
    if [ -d "$odoo_src/odoo/addons" ]; then
        for dir in "$odoo_src/odoo/addons/"*/; do
            [ -f "${dir}__manifest__.py" ] && modules="$modules $(basename "$dir")"
        done
    fi
    
    echo "$modules" | tr ' ' '\n' | sort -u | tr '\n' ' '
}

_update_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(_get_modules)" -- "$cur"))
}

_db_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    local cmd="${COMP_WORDS[1]}"
    
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "anon anon_file backup drop duplicate list restore select" -- "$cur"))
        return
    fi
    
    case "$cmd" in
        anon|backup|drop|duplicate|select)
            COMPREPLY=($(compgen -W "$(_get_databases)" -- "$cur"))
            ;;
        restore)
            if [[ "$cur" != -* ]]; then
                COMPREPLY=($(compgen -W "$(_get_databases)" -- "$cur"))
            else
                COMPREPLY=($(compgen -W "-s --switch -na --no-anon" -- "$cur"))
            fi
            ;;
    esac
}

_shell_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "$(_get_databases)" -- "$cur"))
}

_psql_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    if [ "$prev" = "-d" ] || [ "$prev" = "--database" ]; then
        COMPREPLY=($(compgen -W "$(_get_databases)" -- "$cur"))
    else
        COMPREPLY=($(compgen -W "-d --database" -- "$cur"))
    fi
}

_migrate_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cword="$COMP_CWORD"
    
    if [ "$cword" -eq 1 ]; then
        COMPREPLY=($(compgen -W "$(_get_databases)" -- "$cur"))
    elif [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "19.0 18.0 17.0 16.0 15.0" -- "$cur"))
    fi
}

_rebuild_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    COMPREPLY=($(compgen -W "-nc --no-cache -a --all -h --help" -- "$cur"))
}

_get_valid_versions() {
    local type="$1"
    local compat_file="/home/odoo/docker_dev/data/versions.conf"
    local odoo="${ODOO_VERSION:-19.0}"
    [ ! -f "$compat_file" ] && return
    case "$type" in
        odoo) grep -v '^#' "$compat_file" | grep -v '^$' | cut -d: -f1 | tr '\n' ' ' ;;
        python) grep "^${odoo}:" "$compat_file" | cut -d: -f2 | tr ',' ' ' ;;
        postgres) grep "^${odoo}:" "$compat_file" | cut -d: -f3 | tr ',' ' ' ;;
    esac
}

_set_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"
    local prev_upper=$(echo "$prev" | tr '[:lower:]' '[:upper:]')
    
    if [ "$COMP_CWORD" -eq 1 ]; then
        COMPREPLY=($(compgen -W "SELECTED_DB ODOO_UPDATE ODOO_ARGS ODOO_VERSION ODOO_BUILD PYTHON_VERSION POSTGRES_VERSION" -- "$cur"))
        return
    fi
    
    case "$prev_upper" in
        SELECTED_DB)
            COMPREPLY=($(compgen -W "$(_get_databases) -" -- "$cur"))
            ;;
        ODOO_UPDATE)
            COMPREPLY=($(compgen -W "$(_get_modules) -" -- "$cur"))
            ;;
        ODOO_VERSION)
            COMPREPLY=($(compgen -W "$(_get_valid_versions odoo)" -- "$cur"))
            ;;
        ODOO_BUILD)
            COMPREPLY=($(compgen -W "latest" -- "$cur"))
            ;;
        PYTHON_VERSION)
            COMPREPLY=($(compgen -W "$(_get_valid_versions python)" -- "$cur"))
            ;;
        POSTGRES_VERSION)
            COMPREPLY=($(compgen -W "$(_get_valid_versions postgres)" -- "$cur"))
            ;;
    esac
}

complete -F _update_completion update u
complete -F _db_completion database db
complete -F _shell_completion shell
complete -F _psql_completion psql
complete -F _migrate_completion migrate
complete -F _rebuild_completion rebuild
complete -F _set_completion set

