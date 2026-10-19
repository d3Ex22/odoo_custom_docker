#!/bin/bash
# ============================================================================
# lib/db.sh — PostgreSQL helpers
# psql_admin / db_exists / pick_db / drop_db_force / clone_db (filestore included).
# Sourced by common.sh (every command) — not meant to be sourced alone.
# ============================================================================

psql_admin() {   # psql_admin SQL — run on the postgres maintenance DB, tuples only
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "$1" 2>/dev/null
}

db_exists() {
    local dbname="$1"
    [ -z "$dbname" ] && return 1
    [ "$(psql_admin "SELECT 1 FROM pg_database WHERE datname = '$dbname';")" = "1" ]
}

db_list_names() {
    psql_admin "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres' ORDER BY datname;"
}

valid_db_name() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]; }

# Databases initialized by Odoo (ir_module_module present): the only ones where
# -u / shell make sense (Odoo would install base on an empty one with -u).
db_initialized() {
    [ "$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$1" -tAc \
        "SELECT 1 FROM information_schema.tables WHERE table_name = 'ir_module_module';" 2>/dev/null)" = "1" ]
}
odoo_db_list_names() { local d; for d in $(db_list_names); do db_initialized "$d" && echo "$d"; done; }

# pick_db "Prompt" [all] — sets PICKED to a database name. Called when a command
# needs a database and SELECTED_DB is empty (multi-db mode). With "all", an
# extra entry selects every Odoo database (comma-separated). Dies without a
# terminal (agents / scripts must pass the database).
pick_db() {
    local prompt="$1" with_all="${2:-}"
    [ -t 0 ] || die "No database given and SELECTED_DB is empty (multi-db mode)" \
        "Pass the database to the command, or select one: db select <name>"
    local -a dbs=() items=()
    mapfile -t dbs < <(odoo_db_list_names)
    [ ${#dbs[@]} -eq 0 ] && die "No Odoo database found" "db restore  ·  db select <name> (created on start)"
    ui_note "No selected database (multi-db mode)"
    items=("${dbs[@]}")
    [ -n "$with_all" ] && [ ${#dbs[@]} -gt 1 ] && items+=("all (${#dbs[@]} databases)")
    pick_one "$prompt" "${items[@]}" || return 1
    [[ "$PICKED" == all\ * ]] && PICKED=$(IFS=,; echo "${dbs[*]}")
    return 0
}

# odoo_may_use_db DB — Odoo is running and may hold DB open: the selected one,
# or any database in multi-db mode (every database browsed stays loaded).
odoo_may_use_db() {
    { [ -z "${SELECTED_DB:-}" ] || [ "$1" = "$SELECTED_DB" ]; } \
        && container_running "$ODOO_CONTAINER" && odoo_process_running
}

# Terminate every session on a database (needed before DROP / clone template).
db_terminate_sessions() {
    psql_admin "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = '$1' AND pid <> pg_backend_pid();" >/dev/null
}

drop_db_force() {
    local dbname="$1"
    [ -z "$dbname" ] && return 1
    db_exists "$dbname" || return 0
    db_terminate_sessions "$dbname"
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -v ON_ERROR_STOP=1 -qc \
        "DROP DATABASE \"$dbname\";" >/dev/null
}

create_db() {
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -q -v ON_ERROR_STOP=1 -c \
        "CREATE DATABASE \"$1\" OWNER $DB_USER;" >/dev/null
}
# Filestore lives in the odoo container volume (root-owned writes, chowned back).
copy_filestore() {   # copy_filestore SRC_DB DST_DB
    container_running "$ODOO_CONTAINER" || return 1
    docker exec -u 0 "$ODOO_CONTAINER" bash -c "
        [ -d /var/lib/odoo/filestore/$1 ] || exit 1
        rm -rf /var/lib/odoo/filestore/$2
        cp -a /var/lib/odoo/filestore/$1 /var/lib/odoo/filestore/$2 && chown -R odoo:odoo /var/lib/odoo/filestore/$2" 2>/dev/null
}
remove_filestore() {
    container_running "$ODOO_CONTAINER" || return 0
    docker exec -u 0 "$ODOO_CONTAINER" rm -rf "/var/lib/odoo/filestore/$1" 2>/dev/null
}

# clone_db SRC DST — CREATE DATABASE ... TEMPLATE needs an idle source: sessions
# are terminated first; when Odoo itself may hold SRC it is paused for the copy
# and restarted right after (~2s).
clone_db() {
    local src="$1" dst="$2" paused=false
    db_terminate_sessions "$src"
    local sql="CREATE DATABASE \"$dst\" WITH TEMPLATE \"$src\" OWNER $DB_USER;"
    if ! docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -q -v ON_ERROR_STOP=1 -c "$sql" >/dev/null 2>&1; then
        if odoo_may_use_db "$src"; then
            ui_note "Odoo may be using $src: paused during the copy"
            stop_odoo; paused=true; sleep 0.3
            db_terminate_sessions "$src"
        fi
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -q -v ON_ERROR_STOP=1 -c "$sql" >/dev/null
        local rc=$?
        $paused && launch_odoo >/dev/null
        [ $rc -eq 0 ] || return 1
    fi
    if copy_filestore "$src" "$dst"; then ui_ok "Filestore copied"; else ui_note "no filestore to copy"; fi
}
