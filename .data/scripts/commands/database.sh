#!/bin/bash
set -uo pipefail
# ============================================================================
# db - Database management (list, select, drop, clone, backup, restore, sanitize)
# ============================================================================
# Usage: db [-h|--help] <command> [args]
# Alias: database
# ============================================================================

CMD_NAME="db"
source /home/utils/odoo_custom_docker/.data/scripts/common.sh

ZIP_DIR="${_PROJECT_ROOT}/db_files"
TMP_DIR="${ZIP_DIR}/.tmp"
FILESTORE_BASE="${_PROJECT_ROOT}/.data/volumes/odoo-container/odoo/filestore"
BACKUP_GLOB=(-iname "*.sql" -o -iname "*.dump" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz")

TMP_ANON_DB=""
cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null
    [ -n "$TMP_ANON_DB" ] && drop_db_force "$TMP_ANON_DB" 2>/dev/null
}
trap cleanup EXIT

# ----------------------------------------------------------------------------
# Help
# ----------------------------------------------------------------------------
show_help() {
    h_name "db" "Database management"
    h_sec "USAGE"
    h_use "db                         overview (selected DB, databases, backups)"
    h_use "db <command> [options]"
    h_sec "COMMANDS"
    h_opt "list" "List databases (size, Odoo version) and the backups of ./db_files/"
    h_opt "select [name]" "Set the active database and reboot Odoo"
    h_opt "drop <name> | drop -f" "Drop a database (-f: the active one, Odoo recreates it)"
    h_opt "clone <src> <dst>" "Copy a database (and its filestore)"
    h_opt "backup [-fs] [--keep N] [name]" "Backup to ./db_files/<name>_<date>.zip (--keep: rotation)"
    h_opt "restore [opts] <name>" "Restore a backup from ./db_files/ (sanitized)"
    h_opt "sanitize [-a] [name]" "Neutralize / anonymize a DB or a backup file"
    h_sec "NOTES"
    h_text "Use 'db <command> --help' for details."
    h_text "Long operations (restore, backup, sanitize) run in a side pane of the"
    h_text "utils terminal (closes by itself on success, stays open on error)."
    h_global
    h_end
}

help_list() {
    h_name "db list" "List databases"
    h_sec "USAGE"
    h_use "db list"
    h_sec "DESCRIPTION"
    h_text "Name, size, Odoo version (base module), creation date (when the"
    h_text "database was created or restored here) and last Odoo login of every"
    h_text "database. The selected database (SELECTED_DB) is marked with ●."
    h_end
}

help_select() {
    h_name "db select" "Set the active database"
    h_sec "USAGE"
    h_use "db select [name]"
    h_sec "ARGUMENTS"
    h_opt "name" "Database to select (interactive picker when omitted)"
    h_sec "DESCRIPTION"
    h_text "Writes SELECTED_DB in .env and reboots Odoo. If the database does"
    h_text "not exist yet, asks for confirmation: Odoo creates it on start."
    h_sec "EXAMPLES"
    h_ex "db select" "Pick from the list"
    h_ex "db select mydb" "Select an existing DB"
    h_ex "db select -y newdb" "Select a DB that Odoo will create"
    h_global
    h_end
}

help_drop() {
    h_name "db drop" "Drop a database"
    h_sec "USAGE"
    h_use "db drop <name>"
    h_use "db drop -f"
    h_sec "OPTIONS"
    h_opt "-f, --force" "Drop the selected DB (SELECTED_DB) and restart Odoo on a fresh one"
    h_sec "DESCRIPTION"
    h_text "Active sessions are terminated first. The filestore is removed too."
    h_sec "EXAMPLES"
    h_ex "db drop mydb" "Drop with confirmation"
    h_ex "db drop -y mydb" "Drop without confirmation"
    h_ex "db drop -f -y" "Reset the selected DB, no prompt"
    h_global
    h_end
}

help_clone() {
    h_name "db clone" "Copy a database"
    h_sec "USAGE"
    h_use "db clone <source> <destination>"
    h_sec "OPTIONS"
    h_opt "-f, --force" "Replace the destination if it already exists"
    h_sec "DESCRIPTION"
    h_text "Uses CREATE DATABASE ... TEMPLATE (sessions on the source are closed"
    h_text "for a second, Odoo reconnects by itself) and copies the filestore."
    h_sec "EXAMPLES"
    h_ex "db clone main main_backup" ""
    h_ex "db clone -f prod test" "Overwrite 'test'"
    h_global
    h_end
}

help_backup() {
    h_name "db backup" "Backup a database to ./db_files"
    h_sec "USAGE"
    h_use "db backup [-fs] [--keep N] [name]"
    h_sec "OPTIONS"
    h_opt "-fs, --filestore" "Include the filestore (attachments) in the zip"
    h_opt "--keep N" "Rotation: keep only the N most recent backups of this database in ./db_files"
    h_sec "ARGUMENTS"
    h_opt "name" "Database (default: SELECTED_DB, asked when empty)"
    h_sec "EXAMPLES"
    h_ex "db backup" "Backup the selected DB"
    h_ex "db backup -fs mydb" "With filestore"
    h_ex "db backup --keep 5" "Keep the last 5 backups of the selected DB"
    h_global
    h_end
}

help_restore() {
    h_name "db restore" "Restore a backup from ./db_files"
    h_sec "USAGE"
    h_use "db restore [-s] [-f] [-na] [--file FILE | --last] <name>"
    h_sec "OPTIONS"
    h_opt "-s, --switch" "Select the restored DB and reboot Odoo"
    h_opt "-f, --force" "Replace <name> if it exists, without asking"
    h_opt "-na, --no-sanitize" "Skip neutralize + anonymize"
    h_opt "-F, --file FILE" "Backup to restore (otherwise picker; a single file is taken directly)"
    h_opt "-l, --last" "Most recent backup of <name> in ./db_files (else the most recent of all)"
    h_sec "ARGUMENTS"
    h_opt "name" "Target database name"
    h_sec "FORMATS"
    h_text ".sql  .dump (pg_restore)  .zip  .7z  .tar.gz  .tgz"
    h_text "Archives may contain a filestore/ folder (Odoo backup layout)."
    h_sec "DESCRIPTION"
    h_text "Creates <name> (replaces it only if it exists), imports the dump,"
    h_text "restores the filestore, then neutralizes (crons, mail servers, ...)"
    h_text "and anonymizes (emails → @test.test, admin/admin). Use -na to skip."
    h_sec "EXAMPLES"
    h_ex "db restore newdb" "Pick a backup, restore sanitized"
    h_ex "db restore -s newdb" "... then select it and reboot"
    h_ex "db restore -y -F prod.zip -f main" "Fully non-interactive"
    h_ex "db restore --last -f main" "Latest main_*.zip back over main"
    h_global
    h_end
}

help_sanitize() {
    h_name "db sanitize" "Neutralize and/or anonymize a database or a backup file"
    h_sec "USAGE"
    h_use "db sanitize [-a] [name]"
    h_use "db sanitize [-a] --file [FILE]"
    h_sec "OPTIONS"
    h_opt "-a, --all" "Neutralize then anonymize (no question asked)"
    h_opt "-F, --file [FILE]" "Work on a backup under ./db_files/ (picker when FILE omitted; a single file is taken directly)"
    h_sec "ARGUMENTS"
    h_opt "name" "Database (default: SELECTED_DB, asked when empty)"
    h_sec "STEPS"
    h_opt "neutralize" "Odoo CLI: crons, mail servers, payment providers, API keys..."
    h_opt "anonymize" "SQL: partner/user emails → @test.test, admin login/password → admin"
    h_sec "FILE MODE"
    h_text "Imports into a temporary DB, applies the steps, exports again as"
    h_text "neutral_<file>, anon_<file> or sanitized_<file> and removes the original."
    h_sec "EXAMPLES"
    h_ex "db sanitize" "Ask which steps, on SELECTED_DB"
    h_ex "db sanitize -a mydb" "Both steps on mydb"
    h_ex "db sanitize -a --file prod.zip" "Sanitized copy of a backup"
    h_global
    h_end
}

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
extract_archive() {
    local file="$1" dest="$2"
    case "$(echo "$file" | tr '[:upper:]' '[:lower:]')" in
        *.zip) unzip -qo "$file" -d "$dest" ;;
        *.7z) 7z x -y "$file" -o"$dest" >/dev/null ;;
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$dest" ;;
    esac
}
is_archive() { [[ "$(echo "$1" | tr '[:upper:]' '[:lower:]')" =~ \.(zip|7z|tar\.gz|tgz)$ ]]; }
find_sql_in_dir() { find "$1" -type f \( -iname "*.sql" -o -iname "*.dump" \) | head -n 1; }
file_size() { du -h "$1" 2>/dev/null | cut -f1; }

list_backup_files() {   # list_backup_files [exclude_sanitized]
    mkdir -p "$ZIP_DIR"
    if [ "${1:-}" = "exclude_sanitized" ]; then
        find "$ZIP_DIR" -maxdepth 1 -type f \( "${BACKUP_GLOB[@]}" \) \
            ! -iname "anon_*" ! -iname "neutral_*" ! -iname "sanitized_*" 2>/dev/null | sort -r
    else
        find "$ZIP_DIR" -maxdepth 1 -type f \( "${BACKUP_GLOB[@]}" \) 2>/dev/null | sort -r
    fi
}

# resolve_backup_file PATH_OR_NAME → echoes the absolute path (or fails)
resolve_backup_file() {
    local f="$1"
    [ -f "$f" ] && { echo "$f"; return 0; }
    [ -f "$ZIP_DIR/$f" ] && { echo "$ZIP_DIR/$f"; return 0; }
    [ -f "$ZIP_DIR/$(basename "$f")" ] && { echo "$ZIP_DIR/$(basename "$f")"; return 0; }
    return 1
}

# pick_backup_file [exclude_sanitized] → PICKED_FILE
pick_backup_file() {
    local -a files=() labels=()
    local f
    while IFS= read -r f; do [ -n "$f" ] && files+=("$f"); done < <(list_backup_files "${1:-}")
    [ ${#files[@]} -eq 0 ] && die "No backup file in ./db_files/" "Supported: .sql .dump .zip .7z .tar.gz .tgz"
    if [ ${#files[@]} -eq 1 ]; then   # nothing to choose: take it
        PICKED_FILE="${files[0]}"
        ui_note "Only backup in ./db_files/: $(basename "$PICKED_FILE") ($(file_size "$PICKED_FILE"))"
        return 0
    fi
    for f in "${files[@]}"; do labels+=("$(printf '%s  %s(%s)%s' "$(basename "$f")" "$CMUTED" "$(file_size "$f")" "$RST")"); done
    ui_step "Backups in ./db_files/"
    pick_one "Select a backup" "${labels[@]}" || exit 1
    local i
    for i in "${!labels[@]}"; do [ "${labels[$i]}" = "$PICKED" ] && PICKED_FILE="${files[$i]}"; done
    SECONDS=0   # the elapsed time shown at the end must not include the picker
}

import_sql() {
    local sql_file="$1" dbname="$2"
    local log="${TMP_DIR}/.import.log"
    mkdir -p "$TMP_DIR"
    if [[ "$(echo "$sql_file" | tr '[:upper:]' '[:lower:]')" =~ \.dump$ ]]; then
        docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$dbname" --no-owner < "$sql_file" 2>"$log"
    else
        # PG18 plain SQL dumps use inherited NOT NULL syntax unsupported on PG17
        local import_file="$sql_file"
        if grep -q 'CONSTRAINT ir_actions_name_not_null NOT NULL name,\|^[[:space:]]*NOT NULL name,$' "$sql_file" 2>/dev/null; then
            import_file="${TMP_DIR}/.import_pg17.sql"
            sed -e '/CONSTRAINT ir_actions_name_not_null NOT NULL name,/d' \
                -e '/^[[:space:]]*NOT NULL name,$/d' \
                "$sql_file" > "$import_file"
        fi
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$dbname" -q -v ON_ERROR_STOP=0 < "$import_file" >/dev/null 2>"$log"
    fi
    # Errors are not fatal (ON_ERROR_STOP=0) but must not be silent.
    local errors
    errors=$(grep -ci 'error' "$log" 2>/dev/null)
    if [ "${errors:-0}" -gt 0 ]; then
        ui_warn "${errors} error(s) during import (first 5):"
        grep -i 'error' "$log" | head -5 | sed 's/^/    /'
    fi
}

# Filestore lives in the odoo container volume; written as root then chowned.
restore_filestore_from_dir() {
    local src="$1" db="$2"
    [ -d "$src" ] || return 1
    if ! container_running "$ODOO_CONTAINER"; then
        ui_warn "Odoo container not running — filestore not restored"
        return 1
    fi
    docker exec -u 0 "$ODOO_CONTAINER" rm -rf "/var/lib/odoo/filestore/${db}"
    docker exec -u 0 "$ODOO_CONTAINER" mkdir -p "/var/lib/odoo/filestore/${db}"
    tar -C "$src" -cf - . 2>/dev/null | docker exec -i -u 0 "$ODOO_CONTAINER" tar -xf - -C "/var/lib/odoo/filestore/${db}" || return 1
    docker exec -u 0 "$ODOO_CONTAINER" chown -R odoo:odoo "/var/lib/odoo/filestore/${db}" 2>/dev/null || true
}
# db table: name | size | odoo version | created | last used, selected marked.
# Created = when the database appeared here (CREATE DATABASE / restore: mtime of
# its PG_VERSION file); last used = last Odoo login (res_users_log).
print_db_table() {
    local rows
    rows=$(docker exec -i "$DB_CONTAINER" bash -s "$DB_USER" <<'EOS'
U="$1"
psql -U "$U" -d postgres -tAc "SELECT datname || '|' || pg_size_pretty(pg_database_size(datname)) || '|' || COALESCE(to_char((pg_stat_file('base/' || oid || '/PG_VERSION', true)).modification, 'YYYY-MM-DD'), '-') FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY datname;" \
| while IFS='|' read -r name size created; do
    v=$(psql -U "$U" -d "$name" -tAc "SELECT latest_version FROM ir_module_module WHERE name = 'base';" 2>/dev/null)
    used=$(psql -U "$U" -d "$name" -tAc "SELECT to_char(max(create_date), 'YYYY-MM-DD HH24:MI') FROM res_users_log;" 2>/dev/null)
    echo "${name}|${size}|${v:--}|${created}|${used:--}"
done
EOS
)
    if [ -z "$rows" ]; then ui_note "no database yet"; return; fi
    printf "  ${CMUTED}  %-28s %-10s %-10s %-12s %s${RST}\n" "DATABASE" "SIZE" "ODOO" "CREATED" "LAST LOGIN"
    while IFS='|' read -r name size ver created used; do
        if [ "$name" = "${SELECTED_DB:-}" ]; then
            printf "  ${CSUCCESS}●${RST} ${BFG}%-28s${RST} %-10s %-10s %-12s %s\n" "$name" "$size" "$ver" "$created" "$used"
        else
            printf "    %-28s %-10s ${CMUTED}%-10s %-12s %s${RST}\n" "$name" "$size" "$ver" "$created" "$used"
        fi
    done <<< "$rows"
}

print_backup_table() {   # backups available in ./db_files/ (db restore -F)
    local files f
    files=$(list_backup_files)
    echo
    if [ -z "$files" ]; then ui_note "no backup in ./db_files/"; return; fi
    printf "  ${CMUTED}  %-50s %-10s %s${RST}\n" "BACKUP (./db_files/)" "SIZE" "MODIFIED"
    while IFS= read -r f; do
        printf "    %-50s %-10s ${CMUTED}%s${RST}\n" "$(basename "$f")" "$(file_size "$f")" "$(date -r "$f" '+%Y-%m-%d %H:%M')"
    done <<< "$files"
}

anonymize_db() {
    # test.test is reserved (RFC 2606): fields stay valid, nothing can reach a
    # real customer (neutralize also disables the outgoing mail servers).
    docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$1" -q -v ON_ERROR_STOP=1 <<'EOSQL' >/dev/null
-- Partners: one unique email per record
UPDATE res_partner
SET email = CASE
    WHEN NOT COALESCE(active, true) THEN 'disabled@test.test'
    WHEN is_company THEN 'company' || id::text || '@test.test'
    ELSE 'partner' || id::text || '@test.test'
END
WHERE COALESCE(email, '') <> '';

-- Users: email-like logins → test addresses, admin reset to admin/admin
UPDATE res_users
SET login = 'user' || id::text || '@test.test'
WHERE id <> 2 AND login LIKE '%@%';

UPDATE res_users SET login = 'admin' WHERE id = 2;
UPDATE res_users SET password = 'admin' WHERE id = 2;
UPDATE res_users SET active = true WHERE id = 2;

-- Derived fields / messages (depending on the Odoo version)
DO $$
BEGIN
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'res_partner' AND column_name = 'email_normalized'
    ) THEN
        UPDATE res_partner SET email_normalized = lower(email) WHERE email IS NOT NULL;
    END IF;
    IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema = 'public' AND table_name = 'mail_message' AND column_name = 'email_from'
    ) THEN
        UPDATE mail_message
        SET email_from = 'noreply@test.test'
        WHERE COALESCE(email_from, '') <> '' AND email_from NOT LIKE '%@test.test';
    END IF;
END $$;
EOSQL
}

neutralize_db() {
    if ! container_running "$ODOO_CONTAINER"; then
        ui_warn "Odoo container not running — neutralize skipped"
        return 1
    fi
    docker exec "$ODOO_CONTAINER" odoo neutralize -d "$1" -c /etc/odoo/odoo.conf --stop-after-init 2>&1 | grep -E "ERROR|Traceback|Error" >&2
    return "${PIPESTATUS[0]}"
}

sanitize_pick_ops() {   # sets SAN_DO_NEUTRAL / SAN_DO_ANON
    SAN_DO_NEUTRAL=false
    SAN_DO_ANON=false
    if [ "${1:-}" = "all" ] || [ "$ASSUME_YES" = true ]; then
        SAN_DO_NEUTRAL=true; SAN_DO_ANON=true
        return 0
    fi
    pick_one "Sanitization" \
        "Neutralize only  ${CMUTED}(Odoo: crons, mail servers, API keys...)${RST}" \
        "Anonymize only   ${CMUTED}(SQL: test emails, admin/admin)${RST}" \
        "Both             ${CMUTED}(neutralize, then anonymize)${RST}" || return 1
    case "$PICKED" in
        Neutralize*) SAN_DO_NEUTRAL=true ;;
        Anonymize*)  SAN_DO_ANON=true ;;
        Both*)       SAN_DO_NEUTRAL=true; SAN_DO_ANON=true ;;
    esac
    echo
}

sanitize_apply_to_db() {
    local db="$1"
    if $SAN_DO_NEUTRAL; then
        ui_step "Neutralizing $db..."
        neutralize_db "$db" && ui_ok "Neutralized (crons, mail servers, payment providers disabled)" || ui_warn "Neutralize failed on $db"
    fi
    if $SAN_DO_ANON; then
        ui_step "Anonymizing $db..."
        anonymize_db "$db" && ui_ok "Anonymized (emails → @test.test, admin/admin)" || ui_warn "Anonymize failed on $db"
    fi
}

sanitize_output_prefix() {
    if $SAN_DO_NEUTRAL && $SAN_DO_ANON; then echo "sanitized_"
    elif $SAN_DO_NEUTRAL; then echo "neutral_"
    else echo "anon_"; fi
}

sanitize_run_file() {
    local file="$1"
    local base sql_file out_prefix out_path
    base=$(basename "$file")
    ui_title "Sanitize backup" "$base ($(file_size "$file"))"
    TMP_ANON_DB="sanitize_tmp_$$"
    rm -rf "$TMP_DIR"; mkdir -p "$TMP_DIR"
    if is_archive "$file"; then
        ui_step "Extracting archive..."
        extract_archive "$file" "$TMP_DIR"
        sql_file=$(find_sql_in_dir "$TMP_DIR")
        [ -z "$sql_file" ] && die "No .sql or .dump file found in the archive"
    else
        cp "$file" "$TMP_DIR/"
        sql_file="$TMP_DIR/$base"
    fi
    ui_step "Importing into a temporary database..."
    drop_db_force "$TMP_ANON_DB" && create_db "$TMP_ANON_DB" || die "Could not create the temporary database"
    import_sql "$sql_file" "$TMP_ANON_DB"
    sanitize_apply_to_db "$TMP_ANON_DB"
    ui_step "Exporting..."
    # Export next to the original dump, then replace it (same name, so the
    # archive layout is preserved — the dump may itself be named dump.sql).
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$TMP_ANON_DB" > "$TMP_DIR/.export.sql" || die "Export failed"
    mv -f "$TMP_DIR/.export.sql" "$sql_file"
    out_prefix=$(sanitize_output_prefix)
    out_path="${ZIP_DIR}/${out_prefix}${base}"
    if is_archive "$file"; then
        rm -f "$TMP_DIR"/.import.log "$TMP_DIR"/.import_pg17.sql
        (cd "$TMP_DIR" && zip -rq "$out_path" .) || die "zip failed"
    else
        cp "$sql_file" "$out_path"
    fi
    drop_db_force "$TMP_ANON_DB"; TMP_ANON_DB=""
    rm -f "$file"
    echo
    ui_done "Created ${out_prefix}${base} ($(file_size "$out_path")) — original removed"
}

reboot_if_running() {   # reboot_if_running [DB] — (re)start Odoo on DB (empty = multi-db), says so
    local on="${1:+on $1}"
    if container_running "$ODOO_CONTAINER"; then
        ui_step "Starting Odoo ${on:-(multi-db)}..."
        SELECTED_DB="${1:-}" launch_odoo && ui_ok "Odoo started ${on:-(multi-db)}"
    else
        ui_warn "Odoo container not running — start it to use this database"
    fi
}

# ----------------------------------------------------------------------------
# Dispatch
# ----------------------------------------------------------------------------
parse_global_flags "$@"
set -- "${ARGS[@]}"

case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    "")
        require_db_container
        echo
        if [ -n "${SELECTED_DB:-}" ]; then
            printf "  Selected database: ${BFG}%s${RST}\n\n" "$SELECTED_DB"
        else
            printf "  Selected database: ${CMUTED}none (multi-db mode)${RST}\n\n"
        fi
        print_db_table
        print_backup_table
        echo
        h_opt "db select [name]" "Set the active database"
        h_opt "db backup [-fs] [name]" "Backup to ./db_files/"
        h_opt "db restore [-s] <name>" "Restore a backup (sanitized)"
        h_opt "db clone <src> <dst>" "Copy a database"
        h_opt "db drop <name>" "Drop a database"
        h_opt "db sanitize [-a] [name]" "Neutralize / anonymize"
        echo
        ui_note "db --help for details"
        exit 0 ;;
esac

SUB="$1"; shift
[ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] && { "help_${SUB}" 2>/dev/null || show_help; exit 0; }
require_db_container

case "$SUB" in
    # ------------------------------------------------------------------ list
    list)
        [ $# -gt 0 ] && die "db list takes no argument"
        echo
        print_db_table
        print_backup_table
        echo ;;

    # ---------------------------------------------------------------- select
    select)
        DBNAME="${1:-}"
        [ $# -gt 1 ] && die "Usage: db select [name]"
        if [ -z "$DBNAME" ]; then
            mapfile -t ALL_DBS < <(db_list_names)
            [ ${#ALL_DBS[@]} -eq 0 ] && die "No database to select" "Create one with: db select -y <name>"
            pick_one "Select the active database" "${ALL_DBS[@]}" || exit 1
            DBNAME="$PICKED"
        fi
        valid_db_name "$DBNAME" || die "Invalid database name: $DBNAME"
        if [ "$DBNAME" = "${SELECTED_DB:-}" ]; then
            ui_ok "$DBNAME is already the selected database"
            exit 0
        fi
        if ! db_exists "$DBNAME"; then
            ui_warn "Database '$DBNAME' does not exist"
            confirm "Select it anyway? Odoo will create it on start" || { ui_note "Cancelled"; exit 0; }
        fi
        set_env_value "SELECTED_DB" "$DBNAME"
        ui_ok "Selected database: $DBNAME"
        reboot_if_running "$DBNAME" ;;

    # ------------------------------------------------------------------ drop
    drop)
        FORCE=false; DBNAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -f|--force) FORCE=true; shift ;;
                -*) die "Unknown option: $1" "See: db drop --help" ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        if $FORCE; then
            [ -n "$DBNAME" ] && die "db drop -f works on the selected database, do not pass a name" "To drop another DB: db drop <name>"
            DBNAME="${SELECTED_DB:-}"
            [ -z "$DBNAME" ] && die "No selected database (SELECTED_DB is empty)"
        fi
        [ -z "$DBNAME" ] && die "Usage: db drop <name>  |  db drop -f" "See: db drop --help"
        if ! db_exists "$DBNAME"; then
            ui_err "Database '$DBNAME' does not exist"
            ui_note "db list to see the databases"
            exit 1
        fi
        if $FORCE; then
            confirm "Drop the selected database '$DBNAME' and restart Odoo on a fresh one?" || { ui_note "Cancelled"; exit 0; }
            ui_step "Stopping Odoo..."
            stop_odoo
        else
            confirm "Drop database '$DBNAME'?" || { ui_note "Cancelled"; exit 0; }
        fi
        drop_db_force "$DBNAME" || die "Failed to drop '$DBNAME'"
        remove_filestore "$DBNAME"
        ui_ok "Database dropped: $DBNAME"
        if $FORCE; then
            ui_step "Starting Odoo (will create $DBNAME)..."
            launch_odoo || die "Failed to start Odoo"
            ui_ok "Odoo started"
        fi ;;

    # ----------------------------------------------------------------- clone
    clone)
        FORCE=false; SRC=""; DST=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -f|--force) FORCE=true; shift ;;
                -*) die "Unknown option: $1" "See: db clone --help" ;;
                *) if [ -z "$SRC" ]; then SRC="$1"; elif [ -z "$DST" ]; then DST="$1"; else die "Too many arguments"; fi; shift ;;
            esac
        done
        [ -z "$SRC" ] || [ -z "$DST" ] && die "Usage: db clone <source> <destination>" "See: db clone --help"
        valid_db_name "$DST" || die "Invalid database name: $DST"
        [ "$SRC" = "$DST" ] && die "Source and destination are the same"
        db_exists "$SRC" || die "Source database '$SRC' does not exist" "db list to see the databases"
        if db_exists "$DST"; then
            if ! $FORCE; then
                ui_warn "Database '$DST' already exists"
                confirm "Replace it?" || { ui_note "Cancelled"; exit 0; }
            fi
            drop_db_force "$DST" || die "Failed to drop '$DST'"
        fi
        ui_step "Cloning $SRC → $DST..."
        clone_db "$SRC" "$DST" || die "Clone failed" "Another session holds '$SRC' — retry, or stop Odoo first"
        ui_done "Database cloned: $SRC → $DST" ;;

    # ---------------------------------------------------------------- backup
    backup)
        WITH_FILESTORE=false; DBNAME=""; KEEP=0
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -fs|--filestore) WITH_FILESTORE=true; shift ;;
                --keep) KEEP="${2:-}"; [[ "$KEEP" =~ ^[0-9]+$ ]] && [ "$KEEP" -gt 0 ] || die "--keep needs a number of backups to keep"; shift 2 ;;
                -*) die "Unknown option: $1" "See: db backup --help" ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        force_pane "db backup"
        [ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"
        [ -z "$DBNAME" ] && { pick_db "Backup which database?" || exit 1; DBNAME="$PICKED"; echo; }
        db_exists "$DBNAME" || die "Database '$DBNAME' does not exist" "db list to see the databases"
        mkdir -p "$ZIP_DIR"; rm -rf "$TMP_DIR"; mkdir -p "$TMP_DIR"
        BACKUP_ZIP="${ZIP_DIR}/${DBNAME}_$(date +%Y%m%d_%H%M%S).zip"
        ui_title "Backup" "$DBNAME → $(basename "$BACKUP_ZIP")"
        ui_step "Dumping database..."
        docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DBNAME" > "$TMP_DIR/dump.sql" || die "pg_dump failed"
        if $WITH_FILESTORE; then
            if [ ! -d "$FILESTORE_BASE/$DBNAME" ]; then
                ui_warn "No filestore for $DBNAME"
            elif ! container_running "$ODOO_CONTAINER"; then
                ui_warn "Odoo container not running — filestore skipped"
            else
                ui_step "Copying filestore..."
                mkdir -p "$TMP_DIR/filestore"
                # read as root in the odoo container: the bind mount keeps the container's uid
                docker exec -u 0 "$ODOO_CONTAINER" tar -C "/var/lib/odoo/filestore/${DBNAME}" -cf - . | tar -xf - -C "$TMP_DIR/filestore" || die "Filestore copy failed"
            fi
        fi
        ui_step "Compressing..."
        (cd "$TMP_DIR" && zip -rq "$BACKUP_ZIP" .) || die "zip failed"
        echo
        ui_done "Backup created: db_files/$(basename "$BACKUP_ZIP") ($(file_size "$BACKUP_ZIP"))"
        if [ "$KEEP" -gt 0 ]; then
            # Rotation: this database's own backups (<name>_<date>.zip), newest first
            OLD=$(find "$ZIP_DIR" -maxdepth 1 -type f -name "${DBNAME}_[0-9]*_[0-9]*.zip" | sort -r | tail -n +$((KEEP + 1)))
            if [ -n "$OLD" ]; then
                echo "$OLD" | while read -r f; do rm -f "$f"; ui_note "removed $(basename "$f")"; done
            fi
            ui_note "$(find "$ZIP_DIR" -maxdepth 1 -type f -name "${DBNAME}_[0-9]*_[0-9]*.zip" | wc -l | tr -d ' ') backup(s) of ${DBNAME} kept (--keep ${KEEP})"
        fi ;;

    # --------------------------------------------------------------- restore
    restore)
        SWITCH=false; ANON=true; FORCE=false; FILE=""; DBNAME=""; LAST=false
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -s|--switch) SWITCH=true; shift ;;
                -l|--last) LAST=true; shift ;;
                -na|--no-sanitize) ANON=false; shift ;;
                -f|--force) FORCE=true; shift ;;
                -F|--file) FILE="${2:-}"; [ -z "$FILE" ] && die "--file needs a path"; shift 2 ;;
                -*) die "Unknown option: $1" "See: db restore --help" ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        [ -z "$DBNAME" ] && die "Usage: db restore [-s] [-f] [-na] [--file FILE | --last] <name>" "See: db restore --help"
        valid_db_name "$DBNAME" || die "Invalid database name: $DBNAME"
        $LAST && [ -n "$FILE" ] && die "--last is exclusive with --file"
        force_pane "db restore"
        if $LAST; then
            FILE=$(find "$ZIP_DIR" -maxdepth 1 -type f -name "${DBNAME}_*" \( "${BACKUP_GLOB[@]}" \) 2>/dev/null | sort -r | head -1)
            [ -z "$FILE" ] && FILE=$(list_backup_files exclude_sanitized | head -1)
            [ -z "$FILE" ] && die "No backup file in ./db_files/" "db backup first, or copy a backup there"
            ui_note "latest backup: $(basename "$FILE")"
        fi
        EXISTS=false
        if db_exists "$DBNAME"; then
            EXISTS=true
            if ! $FORCE; then
                ui_warn "Database '$DBNAME' already exists"
                confirm "Replace it with the backup?" || { ui_note "Cancelled"; exit 0; }
            fi
        fi
        if [ -n "$FILE" ]; then
            SELECTED_FILE=$(resolve_backup_file "$FILE") || die "File not found: $FILE" "Backups live in ./db_files/"
        else
            pick_backup_file
            SELECTED_FILE="$PICKED_FILE"
        fi
        ui_title "Restore" "$(basename "$SELECTED_FILE") ($(file_size "$SELECTED_FILE")) → $DBNAME"
        SQL_FILE=""; FILESTORE_FOUND=""
        if is_archive "$SELECTED_FILE"; then
            rm -rf "$TMP_DIR"; mkdir -p "$TMP_DIR"
            ui_step "Extracting archive..."
            extract_archive "$SELECTED_FILE" "$TMP_DIR"
            SQL_FILE=$(find_sql_in_dir "$TMP_DIR")
            [ -z "$SQL_FILE" ] && die "No .sql or .dump file found in the archive"
            FILESTORE_FOUND=$(find "$TMP_DIR" -type d -name "filestore" | head -n 1)
        else
            SQL_FILE="$SELECTED_FILE"
        fi
        STOPPED=false
        if $EXISTS; then
            # Odoo keeps the registry of every database it served: replacing one
            # under it needs a restart (selected DB, or any DB in multi-db mode).
            if odoo_may_use_db "$DBNAME"; then
                if [ -n "${SELECTED_DB:-}" ]; then ui_step "Stopping Odoo (running on $DBNAME)..."
                else ui_step "Stopping Odoo (multi-db: $DBNAME may be loaded)..."; fi
                stop_odoo && STOPPED=true && ui_ok "Odoo stopped"
            fi
            ui_step "Replacing database $DBNAME..."
            drop_db_force "$DBNAME" || die "Failed to drop '$DBNAME'"
        else
            ui_step "Creating database $DBNAME..."
        fi
        create_db "$DBNAME" || die "Failed to create '$DBNAME'"
        ui_step "Importing data..."
        import_sql "$SQL_FILE" "$DBNAME"
        if [ -n "$FILESTORE_FOUND" ]; then
            ui_step "Restoring filestore..."
            restore_filestore_from_dir "$FILESTORE_FOUND" "$DBNAME" && ui_ok "Filestore restored" || ui_warn "Filestore not restored"
        fi
        if $ANON; then
            SAN_DO_NEUTRAL=true; SAN_DO_ANON=true
            sanitize_apply_to_db "$DBNAME"
        else
            ui_warn "Not sanitized (-na): crons and mail servers are still active"
        fi
        if $SWITCH; then
            set_env_value "SELECTED_DB" "$DBNAME"
            ui_ok "Selected database: $DBNAME"
            reboot_if_running "$DBNAME"
        elif $STOPPED; then
            reboot_if_running "${SELECTED_DB:-}"
        fi
        echo
        ui_done "Database restored: $DBNAME" ;;

    # -------------------------------------------------------------- sanitize
    sanitize)
        SAN_ALL=false; FILE_MODE=false; FILE=""; DBNAME=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                -a|--all) SAN_ALL=true; shift ;;
                -F|--file)
                    FILE_MODE=true
                    if [[ -n "${2:-}" && "$2" != -* ]]; then FILE="$2"; shift 2; else shift; fi ;;
                -f) die "Unknown option: -f" "Did you mean --file (-F)?" ;;
                -*) die "Unknown option: $1" "See: db sanitize --help" ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        force_pane "db sanitize"
        if $FILE_MODE; then
            if [ -n "$FILE" ]; then
                SELECTED_FILE=$(resolve_backup_file "$FILE") || die "File not found: $FILE" "Backups live in ./db_files/"
            else
                pick_backup_file exclude_sanitized
                SELECTED_FILE="$PICKED_FILE"
                echo
            fi
            if $SAN_ALL; then sanitize_pick_ops all; else sanitize_pick_ops || exit 1; fi
            sanitize_run_file "$SELECTED_FILE"
            exit 0
        fi
        [ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"
        [ -z "$DBNAME" ] && { pick_db "Sanitize which database?" || exit 1; DBNAME="$PICKED"; echo; }
        db_exists "$DBNAME" || die "Database '$DBNAME' does not exist" "db list to see the databases"
        if $SAN_ALL; then sanitize_pick_ops all; else sanitize_pick_ops || exit 1; fi
        sanitize_apply_to_db "$DBNAME"
        echo
        ui_done "Sanitize finished: $DBNAME" ;;

    *)
        die "Unknown command: $SUB" "db --help for the list of commands" ;;
esac
