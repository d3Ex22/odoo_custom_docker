#!/bin/bash
set -uo pipefail
# ============================================================================
# database - Database management menu
# ============================================================================
# Usage: db [-h|--help] <command> [args]
# Alias: db
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

ZIP_DIR="${_PROJECT_ROOT}/db_files"
TMP_DIR="${_PROJECT_ROOT}/db_files/.tmp"
FILESTORE_BASE="${_PROJECT_ROOT}/.data/volumes/odoo-container/odoo/filestore"

TMP_ANON_DB=""

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null
    [ -n "$TMP_ANON_DB" ] && docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_ANON_DB\";" >/dev/null 2>&1
}
trap cleanup EXIT

extract_archive() {
    local file="$1" dest="$2"
    local ext_lower=$(echo "$file" | tr '[:upper:]' '[:lower:]')
    case "$ext_lower" in
        *.zip) unzip -qo "$file" -d "$dest" ;;
        *.7z) 7z x -y "$file" -o"$dest" >/dev/null ;;
        *.tar.gz|*.tgz) tar -xzf "$file" -C "$dest" ;;
    esac
}

is_archive() {
    local ext_lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    [[ "$ext_lower" =~ \.(zip|7z|tar\.gz|tgz)$ ]]
}

find_sql_in_dir() {
    find "$1" -type f \( -iname "*.sql" -o -iname "*.dump" \) | head -n 1
}

import_sql() {
    local sql_file="$1" dbname="$2"
    local ext_lower=$(echo "$sql_file" | tr '[:upper:]' '[:lower:]')
    if [[ "$ext_lower" =~ \.dump$ ]]; then
        docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$dbname" --no-owner < "$sql_file" 2>/dev/null
    else
        docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$dbname" < "$sql_file" >/dev/null 2>&1
    fi
}

restore_filestore_from_dir() {
    local src="$1" db="$2"
    [ -z "$src" ] || [ ! -d "$src" ] && return 1
    if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$ODOO_CONTAINER"; then
        echo "❌ Odoo container ($ODOO_CONTAINER) must be running to restore filestore (writes as root, then chown odoo)."
        return 1
    fi
    docker exec -u 0 "$ODOO_CONTAINER" rm -rf "/var/lib/odoo/filestore/${db}"
    docker exec -u 0 "$ODOO_CONTAINER" mkdir -p "/var/lib/odoo/filestore/${db}"
    if ! tar -C "$src" -cf - . 2>/dev/null | docker exec -i -u 0 "$ODOO_CONTAINER" tar -xf - -C "/var/lib/odoo/filestore/${db}"; then
        echo "❌ Failed to stream filestore into Odoo container"
        return 1
    fi
    docker exec -u 0 "$ODOO_CONTAINER" chown -R odoo:odoo "/var/lib/odoo/filestore/${db}" 2>/dev/null || true
    return 0
}

show_help() {
    echo ""
    echo "database - Database management"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db <command> [args]"
    echo "       db"
    echo ""
    printf "   ${CPRIMARY}SANITIZE${RST}\n"
    echo "       sanitize    ${CPRIMARY}Neutralize / anonymize (DB or file) ${RST}"
    echo ""
    printf "   ${CPRIMARY}POSTGRESQL${RST}\n"
    echo "       drop        ${CPRIMARY}Drop database          ${RST}"
    echo "       clone       ${CPRIMARY}Clone database         ${RST}"
    echo "       list        ${CPRIMARY}List all databases     ${RST}"
    echo "       select      ${CPRIMARY}Set active database    ${RST}"
    echo ""
    printf "   ${CPRIMARY}FILES${RST}\n"
    echo "       backup      ${CPRIMARY}Backup database to zip ${RST}"
    echo "       restore     ${CPRIMARY}Restore from backup    ${RST}"
    echo ""
    printf "   ${CPRIMARY}NOTES${RST}\n"
    echo "       Use 'db <command> --help' for command details"
    echo "       Backups stored in ./db_files/"
    echo ""
}

help_sanitize() {
    echo ""
    echo "db sanitize - Neutralize and/or anonymize a database or backup file"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db sanitize [-a|--all] [database]"
    echo "       db sanitize [-a|--all] -f|--file [path]"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -a, --all       ${CPRIMARY}Run neutralize then anonymize (no prompt)     ${RST}"
    echo "       -f, --file      ${CPRIMARY}Process a backup under ./db_files/ instead of a live DB${RST}"
    echo "                       ${CPRIMARY}If path omitted, lists files and prompts for choice ${RST}"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       database        ${CPRIMARY}PostgreSQL database (default: SELECTED_DB)      ${RST}"
    echo ""
    printf "   ${CPRIMARY}INTERACTIVE${RST}\n"
    echo "       Without --all, prompts: (1) neutralize only, (2) anonymize only,"
    echo "       (3) both — same order as restore: neutralize then anonymize."
    echo ""
    printf "   ${CPRIMARY}NEUTRALIZE (Odoo CLI)${RST}\n"
    echo "       Disables crons, mail servers, fetchmail, payments, carriers,"
    echo "       clears API keys, sets neutralization flag. Requires Odoo container."
    echo ""
    printf "   ${CPRIMARY}ANONYMIZE (SQL)${RST}\n"
    echo "       Clears partner emails, sets admin user login/password to admin/admin."
    echo ""
    printf "   ${CPRIMARY}FILE MODE (-f)${RST}\n"
    echo "       Imports into a temporary database, applies chosen steps, exports."
    echo "       Output prefix: anon_ (anonymize only), neutral_ (neutralize only),"
    echo "       sanitized_ (both). Excludes anon_*, neutral_*, sanitized_* from listing."
    echo "       Original file is removed after success."
    echo ""
    printf "   ${CPRIMARY}SUPPORTED FILE FORMATS${RST}\n"
    echo "       .sql, .dump, .zip, .7z, .tar.gz, .tgz"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       db sanitize                    ${CPRIMARY}Prompt ops on SELECTED_DB        ${RST}"
    echo "       db sanitize -a mydb            ${CPRIMARY}Full sanitize on mydb           ${RST}"
    echo "       db sanitize -f                 ${CPRIMARY}Pick file from ./db_files/        ${RST}"
    echo "       db sanitize -a -f backup.zip   ${CPRIMARY}Full sanitize export from file   ${RST}"
    echo ""
}

help_backup() {
    echo ""
    echo "db backup - Backup database to zip"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db backup [-fs|--filestore] [name]"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -fs, --filestore  ${CPRIMARY}Include filestore in backup          ${RST}"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       name              ${CPRIMARY}Database name (default: SELECTED_DB) ${RST}"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       db backup                  ${CPRIMARY}Backup current DB             ${RST}"
    echo "       db backup --filestore      ${CPRIMARY}Backup with filestore         ${RST}"
    echo "       db backup mydb             ${CPRIMARY}Backup specific DB            ${RST}"
    echo "       db backup -fs mydb         ${CPRIMARY}With filestore + specific DB  ${RST}"
    echo ""
}

help_drop() {
    echo ""
    echo "db drop - Drop database"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db drop [-y|--yes] <name>"
    echo "       db drop -f|--force [-y|--yes]"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -y, --yes     ${CPRIMARY}Skip confirmation                    ${RST}"
    echo "       -f, --force   ${CPRIMARY}Drop current DB and restart Odoo     ${RST}"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       name          ${CPRIMARY}Database name to drop                ${RST}"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       db drop mydb           ${CPRIMARY}Drop with confirmation            ${RST}"
    echo "       db drop --yes mydb     ${CPRIMARY}Drop without confirmation         ${RST}"
    echo "       db drop --force        ${CPRIMARY}Drop current DB + restart Odoo    ${RST}"
    echo "       db drop -f -y          ${CPRIMARY}Same, skip confirmation           ${RST}"
    echo ""
}

help_clone() {
    echo ""
    echo "db clone - Clone database"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db clone <source> <destination>"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       source      ${CPRIMARY}Source database name                 ${RST}"
    echo "       destination ${CPRIMARY}New database name                    ${RST}"
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       db clone production test  "
    echo "       db clone main backup_main "
    echo ""
}

help_list() {
    echo ""
    echo "db list - List all databases"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db list"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Shows all PostgreSQL databases with details."
    echo ""
}

help_restore() {
    echo ""
    echo "db restore - Restore database from backup"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db restore [-s] [-na] [-f] <name>"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -s, --switch    ${CPRIMARY}Switch to restored DB after restore  ${RST}"
    echo "       -na, --no-anon  ${CPRIMARY}Skip auto-neutralize + anonymize     ${RST}"
    echo "       -f, --force     ${CPRIMARY}Overwrite existing DB without prompt ${RST}"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       name        ${CPRIMARY}Target database name (required)          ${RST}"
    echo ""
    printf "   ${CPRIMARY}SUPPORTED FORMATS${RST}\n"
    echo "       .sql, .dump, .zip, .7z, .tar.gz, .tgz"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Lists available backups in ./db_files/ and prompts"
    echo "       for selection. Automatically neutralizes + anonymizes the"
    echo "       restored database (use -na to skip). Detects and restores filestore"
    echo "       via Odoo container (needs Odoo running for correct ownership)."
    echo "       If the target database already exists, asks for confirmation unless -f."
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       db restore newdb          ${CPRIMARY}Restore + neutralize + anonymize ${RST}"
    echo "       db restore -s newdb       ${CPRIMARY}Restore, neutralize + switch     ${RST}"
    echo "       db restore -na newdb      ${CPRIMARY}Restore without neutralize/anon  ${RST}"
    echo "       db restore -f mydb        ${CPRIMARY}Replace mydb without prompt      ${RST}"
    echo ""
}

help_select() {
    echo ""
    echo "db select - Set active database"
    echo ""
    printf "   ${CPRIMARY}USAGE${RST}\n"
    echo "       db select [-y|--yes] <name>"
    echo ""
    printf "   ${CPRIMARY}OPTIONS${RST}\n"
    echo "       -y, --yes    ${CPRIMARY}Skip confirmation for new databases       ${RST}"
    echo ""
    printf "   ${CPRIMARY}ARGUMENTS${RST}\n"
    echo "       name         ${CPRIMARY}Database name to select                   ${RST}"
    echo ""
    printf "   ${CPRIMARY}DESCRIPTION${RST}\n"
    echo "       Sets SELECTED_DB in .env and restarts Odoo (reboot) when the container runs."
    echo "       If database doesn't exist, Odoo will create it on next start."
    echo ""
    printf "   ${CPRIMARY}EXAMPLES${RST}\n"
    echo "       db select mydb          ${CPRIMARY}Select existing DB                   ${RST}"
    echo "       db select --yes newdb   ${CPRIMARY}Select/create new DB                 ${RST}"
    echo ""
}

list_databases() {
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -l -t 2>/dev/null | \
        grep -v template | grep -v postgres | awk -F'|' '{gsub(/^ +| +$/, "", $1); if($1!="" && $1!~/^\|/)print "  " $1}'
}

anonymize_db() {
    local DB="$1"
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d "$DB" -c "
        UPDATE res_partner SET email = NULL WHERE email IS NOT NULL;
        UPDATE res_users SET login = 'admin' WHERE id = 2;
        UPDATE res_users SET password = 'admin' WHERE id = 2;
        UPDATE res_users SET active = true WHERE id = 2;
    " >/dev/null 2>&1
}

neutralize_db() {
    local DB="$1"
    docker exec "$ODOO_CONTAINER" odoo neutralize -d "$DB" -c /etc/odoo/odoo.conf --stop-after-init >/dev/null 2>&1
}

sanitize_pick_ops() {
    SAN_DO_NEUTRAL=false
    SAN_DO_ANON=false
    if [ "${1:-}" = "all" ]; then
        SAN_DO_NEUTRAL=true
        SAN_DO_ANON=true
        return 0
    fi
    echo "Select sanitization:"
    echo "  1) Neutralize only (Odoo: crons, mail, keys, …)"
    echo "  2) Anonymize only (SQL: emails, admin/admin)"
    echo "  3) Both (neutralize, then anonymize)"
    read -r -p "Choice [1-3]: " san_choice
    echo ""
    case "$san_choice" in
        1) SAN_DO_NEUTRAL=true ;;
        2) SAN_DO_ANON=true ;;
        3)
            SAN_DO_NEUTRAL=true
            SAN_DO_ANON=true
            ;;
        *)
            echo "❌ Invalid choice"
            return 1
            ;;
    esac
    return 0
}

sanitize_apply_to_db() {
    local db="$1"
    if $SAN_DO_NEUTRAL; then
        echo "Neutralizing '$db'..."
        neutralize_db "$db"
        echo "✓ Neutralized"
    fi
    if $SAN_DO_ANON; then
        echo "Anonymizing '$db'..."
        anonymize_db "$db"
        echo "✓ Anonymized (emails cleared, admin/admin)"
    fi
}

sanitize_output_prefix() {
    if $SAN_DO_NEUTRAL && $SAN_DO_ANON; then
        echo "sanitized_"
    elif $SAN_DO_NEUTRAL; then
        echo "neutral_"
    else
        echo "anon_"
    fi
}

sanitize_pick_file_interactive() {
    SAN_SELECTED_FILE=""
    mkdir -p "$ZIP_DIR"
    local -a list=()
    local line
    while IFS= read -r line; do
        [ -n "$line" ] && list+=("$line")
    done < <(find "$ZIP_DIR" -maxdepth 1 -type f \( -iname "*.sql" -o -iname "*.dump" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" \) ! -iname "anon_*" ! -iname "neutral_*" ! -iname "sanitized_*" 2>/dev/null | sort -r)
    if [ ${#list[@]} -eq 0 ]; then
        echo "❌ No eligible backup files in $ZIP_DIR"
        return 1
    fi
    echo "Available backups:"
    local i
    for i in "${!list[@]}"; do
        echo "  $((i + 1)). $(basename "${list[$i]}")"
    done
    echo ""
    read -r -p "Select file [1-${#list[@]}]: " CHOICE
    if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#list[@]} ]; then
        echo "❌ Invalid selection"
        return 1
    fi
    SAN_SELECTED_FILE="${list[$((CHOICE - 1))]}"
    return 0
}

sanitize_run_file() {
    local SELECTED_FILE="$1"
    local BASENAME sql_file out_prefix out_path
    BASENAME=$(basename "$SELECTED_FILE")
    echo "Selected: $BASENAME"
    TMP_ANON_DB="sanitize_tmp_$$"
    rm -rf "$TMP_DIR"
    mkdir -p "$TMP_DIR"
    sql_file=""
    if is_archive "$SELECTED_FILE"; then
        echo "Extracting archive..."
        extract_archive "$SELECTED_FILE" "$TMP_DIR"
        sql_file=$(find_sql_in_dir "$TMP_DIR")
        if [ -z "$sql_file" ]; then
            echo "❌ No .sql or .dump file found in archive"
            return 1
        fi
    else
        cp "$SELECTED_FILE" "$TMP_DIR/"
        sql_file="$TMP_DIR/$(basename "$SELECTED_FILE")"
    fi
    echo "Creating temporary database..."
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_ANON_DB\";" >/dev/null 2>&1
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$TMP_ANON_DB\" OWNER $DB_USER;" >/dev/null
    echo "Importing data..."
    import_sql "$sql_file" "$TMP_ANON_DB"
    sanitize_apply_to_db "$TMP_ANON_DB"
    echo "Exporting..."
    docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$TMP_ANON_DB" > "$TMP_DIR/dump.sql"
    rm -f "$sql_file" 2>/dev/null
    mv "$TMP_DIR/dump.sql" "$sql_file" 2>/dev/null || cp "$TMP_DIR/dump.sql" "$sql_file"
    out_prefix=$(sanitize_output_prefix)
    out_path="${ZIP_DIR}/${out_prefix}${BASENAME}"
    if is_archive "$SELECTED_FILE"; then
        rm -f "$TMP_DIR/dump.sql" 2>/dev/null
        (cd "$TMP_DIR" && zip -rq "$out_path" .)
    else
        cp "$sql_file" "$out_path"
    fi
    echo "Cleaning up temp database..."
    docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_ANON_DB\";" >/dev/null 2>&1
    TMP_ANON_DB=""
    rm -f "$SELECTED_FILE"
    echo "✓ Created: ${out_prefix}${BASENAME}"
    echo "  Original file removed"
    return 0
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

if [ -z "${1:-}" ]; then
    echo "Selected: ${SELECTED_DB}"
    echo ""
    echo "Available databases:"
    list_databases
    echo ""
    printf "  db sanitize [-a] [-f] [db]  ${CPRIMARY}Neutralize / anonymize (DB or file)    ${RST}\n"
    echo ""
    echo "PostgreSQL:"
    printf "  db drop [-y] <name>         ${CPRIMARY}Drop database                          ${RST}\n"
    printf "  db clone <src> <dst>        ${CPRIMARY}Clone database                         ${RST}\n"
    printf "  db list                     ${CPRIMARY}Full database list                     ${RST}\n"
    printf "  db select [-y] <name>       ${CPRIMARY}Select active database                 ${RST}\n"
    echo ""
    echo "Files (./db_files/):"
    printf "  db backup [-fs] [name]      ${CPRIMARY}Backup to zip                          ${RST}\n"
    printf "  db restore [-s] [-na] [-f] <n> ${CPRIMARY}Restore from backup (neutralize+anon)  ${RST}\n"
    exit 0
fi

case "$1" in
    backup)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_backup
            exit 0
        fi
        WITH_FILESTORE=false
        DBNAME=""
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                -fs|--filestore) WITH_FILESTORE=true; shift ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        [ -z "$DBNAME" ] && DBNAME="${SELECTED_DB}"
        if [ -z "$DBNAME" ]; then
            echo "❌ No database specified and no SELECTED_DB in .env"
            exit 1
        fi
        if ! db_exists "$DBNAME"; then
            echo "❌ Database '$DBNAME' does not exist"
            exit 1
        fi
        mkdir -p "$ZIP_DIR" "$TMP_DIR"
        rm -rf "$TMP_DIR"/*
        DATE_TAG=$(date +%Y%m%d_%H%M%S)
        BACKUP_ZIP="${ZIP_DIR}/${DBNAME}_${DATE_TAG}.zip"
        echo "Exporting database '$DBNAME'..."
        docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$DBNAME" > "$TMP_DIR/dump.sql"
        if [ $? -ne 0 ]; then
            echo "❌ Failed to export database"
            exit 1
        fi
        if $WITH_FILESTORE; then
            FS_PATH="$FILESTORE_BASE/$DBNAME"
            if [ -d "$FS_PATH" ]; then
                echo "Copying filestore..."
                cp -r "$FS_PATH" "$TMP_DIR/filestore"
            else
                echo "⚠️  No filestore found at $FS_PATH"
            fi
        fi
        echo "Compressing..."
        cd "$TMP_DIR" && zip -rq "$BACKUP_ZIP" . && cd - >/dev/null
        echo "✓ Backup created: $BACKUP_ZIP"
        ;;
    drop)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_drop
            exit 0
        fi
        FORCE=false
        CONFIRM=false
        DBNAME=""
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                -f|--force) FORCE=true; shift ;;
                -y|--yes) CONFIRM=true; shift ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        if $FORCE; then
            DBNAME="${SELECTED_DB}"
            if [ -z "$DBNAME" ]; then
                echo "❌ No database selected"
                exit 1
            fi
        fi
        if [ -z "$DBNAME" ]; then
            echo "❌ Usage: db drop [-y] <name>"
            echo "         db drop -f [-y]"
            echo "   Use 'db drop --help' for details"
            exit 1
        fi
        if ! $CONFIRM; then
            if $FORCE; then
                echo "⚠️  Drop current database '$DBNAME' and restart Odoo? [y/N]"
            else
                echo "⚠️  Drop database '$DBNAME'? [y/N]"
            fi
            read -r -n 1 confirm
            echo ""
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "Cancelled"
                exit 0
            fi
        fi
        if $FORCE; then
            echo "Stopping Odoo..."
            docker stop "$ODOO_CONTAINER" >/dev/null 2>&1
            sleep 1
        fi
        docker exec "$DB_CONTAINER" dropdb -U "$DB_USER" "$DBNAME" 2>/dev/null
        echo "✓ Database dropped: $DBNAME"
        if $FORCE; then
            echo "Starting Odoo..."
            docker start "$ODOO_CONTAINER" >/dev/null 2>&1
            echo "✓ Odoo restarted (will create new database)"
        fi
        ;;
    clone)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_clone
            exit 0
        fi
        if [ -z "${2:-}" ] || [ -z "${3:-}" ]; then
            echo "❌ Usage: db clone <source> <destination>"
            echo "   Use 'db clone --help' for details"
            exit 1
        fi
        docker exec "$DB_CONTAINER" createdb -U "$DB_USER" -T "$2" "$3"
        echo "✓ Database cloned: ${2} → ${3}"
        ;;
    list)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_list
            exit 0
        fi
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -l
        ;;
    restore)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_restore
            exit 0
        fi
        SWITCH=false
        ANON=true
        RESTORE_FORCE=false
        DBNAME=""
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                -s|--switch) SWITCH=true; shift ;;
                -na|--no-anon) ANON=false; shift ;;
                -f|--force) RESTORE_FORCE=true; shift ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        if [ -z "$DBNAME" ]; then
            echo "❌ Usage: db restore [-s] [-na] [-f] <name>"
            echo "   Use 'db restore --help' for details"
            exit 1
        fi
        if db_exists "$DBNAME" && ! $RESTORE_FORCE; then
            echo "⚠️  Database '$DBNAME' already exists. Restore will DROP and replace it."
            echo "   Continue? [y/N]"
            read -r -n 1 confirm
            echo ""
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                echo "Cancelled"
                exit 0
            fi
        fi
        mkdir -p "$ZIP_DIR"
        IMPORT_LIST=($(find "$ZIP_DIR" -maxdepth 1 -type f \( -iname "*.sql" -o -iname "*.dump" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" \) 2>/dev/null | sort -r))
        if [ ${#IMPORT_LIST[@]} -eq 0 ]; then
            echo "❌ No backup files found in $ZIP_DIR"
            exit 1
        fi
        echo "Available backups:"
        for i in "${!IMPORT_LIST[@]}"; do
            echo "  $((i + 1)). $(basename "${IMPORT_LIST[$i]}")"
        done
        echo ""
        read -p "Select backup [1-${#IMPORT_LIST[@]}]: " CHOICE
        if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || [ "$CHOICE" -lt 1 ] || [ "$CHOICE" -gt ${#IMPORT_LIST[@]} ]; then
            echo "❌ Invalid selection"
            exit 1
        fi
        SELECTED_FILE="${IMPORT_LIST[$((CHOICE - 1))]}"
        echo "Selected: $(basename "$SELECTED_FILE")"
        SQL_FILE=""
        FILESTORE_FOUND=""
        if is_archive "$SELECTED_FILE"; then
            rm -rf "$TMP_DIR"
            mkdir -p "$TMP_DIR"
            echo "Extracting archive..."
            extract_archive "$SELECTED_FILE" "$TMP_DIR"
            SQL_FILE=$(find_sql_in_dir "$TMP_DIR")
            if [ -z "$SQL_FILE" ]; then
                echo "❌ No .sql or .dump file found in archive"
                exit 1
            fi
            FILESTORE_FOUND=$(find "$TMP_DIR" -type d -name "filestore" | head -n 1)
        else
            SQL_FILE="$SELECTED_FILE"
        fi
        echo "Creating database '$DBNAME'..."
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$DBNAME\";" 2>/dev/null
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$DBNAME\" OWNER $DB_USER;"
        echo "Importing data..."
        import_sql "$SQL_FILE" "$DBNAME"
        if [ -n "$FILESTORE_FOUND" ]; then
            echo "Restoring filestore..."
            if restore_filestore_from_dir "$FILESTORE_FOUND" "$DBNAME"; then
                echo "✓ Filestore restored"
            else
                exit 1
            fi
        fi
        if $ANON; then
            echo "Neutralizing database..."
            neutralize_db "$DBNAME"
            echo "✓ Database neutralized"
            echo "Anonymizing database..."
            anonymize_db "$DBNAME"
            echo "✓ Database anonymized"
        fi
        echo "✓ Database restored: $DBNAME"
        if $SWITCH; then
            set_env_value "SELECTED_DB" "$DBNAME"
            echo "✓ Switched to $DBNAME"
            echo "  Restart Odoo with 'r' to apply"
        fi
        ;;
    sanitize)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_sanitize
            exit 0
        fi
        SAN_ALL=false
        SAN_FILE_MODE=false
        SAN_FILE_PATH=""
        DBNAME=""
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                -a|--all)
                    SAN_ALL=true
                    shift
                    ;;
                -f|--file)
                    SAN_FILE_MODE=true
                    if [[ -n "${2:-}" && "$2" != -* ]]; then
                        SAN_FILE_PATH="$2"
                        shift 2
                    else
                        shift
                    fi
                    ;;
                *)
                    DBNAME="$1"
                    shift
                    ;;
            esac
        done
        if $SAN_ALL; then
            sanitize_pick_ops all || exit 1
        else
            sanitize_pick_ops || exit 1
        fi
        if $SAN_FILE_MODE; then
            SAN_SEL=""
            if [ -n "$SAN_FILE_PATH" ]; then
                SAN_SEL="$SAN_FILE_PATH"
                if [ ! -f "$SAN_SEL" ] && [ -f "$ZIP_DIR/$(basename "$SAN_SEL")" ]; then
                    SAN_SEL="$ZIP_DIR/$(basename "$SAN_SEL")"
                fi
                if [ ! -f "$SAN_SEL" ]; then
                    echo "❌ File not found: $SAN_FILE_PATH"
                    exit 1
                fi
            else
                sanitize_pick_file_interactive || exit 1
                SAN_SEL="$SAN_SELECTED_FILE"
            fi
            sanitize_run_file "$SAN_SEL" || exit 1
            exit 0
        fi
        [ -z "$DBNAME" ] && DBNAME="${SELECTED_DB}"
        if [ -z "$DBNAME" ]; then
            echo "❌ No database specified and no SELECTED_DB in .env"
            exit 1
        fi
        if ! db_exists "$DBNAME"; then
            echo "❌ Database '$DBNAME' does not exist"
            exit 1
        fi
        sanitize_apply_to_db "$DBNAME"
        echo "✓ Sanitize finished: $DBNAME"
        ;;
    select)
        if [ "${2:-}" = "-h" ] || [ "${2:-}" = "--help" ]; then
            help_select
            exit 0
        fi
        FORCE=false
        DBNAME=""
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                -y|--yes) FORCE=true; shift ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        if [ -z "$DBNAME" ]; then
            echo "❌ Usage: db select [-y|--yes] <name>"
            echo "   Use 'db select --help' for details"
            exit 1
        fi
        if ! db_exists "$DBNAME"; then
            if ! $FORCE; then
                echo "⚠️  Database '$DBNAME' does not exist"
                echo "   Odoo will create it on startup. Continue? [y/N]"
                read -r -n 1 confirm
                echo ""
                if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                    echo "Cancelled"
                    exit 0
                fi
            fi
        fi
        set_env_value "SELECTED_DB" "$DBNAME"
        echo "✓ Selected database: $DBNAME"
        if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "$ODOO_CONTAINER"; then
            bash "${_PROJECT_ROOT}/.data/scripts/commands/reboot.sh" || exit 1
        else
            echo "⚠️  Odoo container not running; start it to use this database."
        fi
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo "   Use 'db --help' for available commands"
        exit 1
        ;;
esac
