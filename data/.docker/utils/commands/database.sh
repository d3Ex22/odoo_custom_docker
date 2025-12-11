#!/bin/bash
# ============================================================================
# database - Database management menu
# ============================================================================
# Usage: db [-h|--help] <command> [args]
# Alias: db
# ============================================================================

source /home/odoo/docker_dev/.env 2>/dev/null
source /home/odoo/docker_dev/data/theme.conf 2>/dev/null

COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
C=$(printf '\033[38;2;%s;%s;%sm' "$R" "$G" "$B")
RST=$(printf '\033[0m')

PROJECT="${COMPOSE_PROJECT_NAME:-odoo}"
DB_CONTAINER="${PROJECT}_db"
ODOO_CONTAINER="${PROJECT}_odoo"
DB_USER="${POSTGRES_USER:-odoo}"
ZIP_DIR="/home/odoo/docker_dev/db_zip"
TMP_DIR="/home/odoo/docker_dev/db_zip/.tmp"
FILESTORE_BASE="/home/odoo/docker_dev/data/volumes/odoo/filestore"

cleanup() {
    rm -rf "$TMP_DIR" 2>/dev/null
    [ -n "$TMP_ANON_DB" ] && docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_ANON_DB\";" >/dev/null 2>&1
}
trap cleanup EXIT

show_help() {
    echo ""
    echo "database - Database management"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db <command> [args]"
    echo "       db"
    echo ""
    printf "   ${C}POSTGRESQL${RST}\n"
    echo "       anon        ${C}Anonymize database     ${RST}"
    echo "       drop        ${C}Drop database          ${RST}"
    echo "       duplicate   ${C}Duplicate database     ${RST}"
    echo "       list        ${C}List all databases     ${RST}"
    echo "       select      ${C}Set active database    ${RST}"
    echo ""
    printf "   ${C}FILES${RST}\n"
    echo "       anon_file   ${C}Anonymize backup file  ${RST}"
    echo "       backup      ${C}Backup database to zip ${RST}"
    echo "       restore     ${C}Restore from backup    ${RST}"
    echo ""
    printf "   ${C}NOTES${RST}\n"
    echo "       Use 'db <command> --help' for command details"
    echo "       Backups stored in ./db_zip/"
    echo ""
}

help_anon() {
    echo ""
    echo "db anon - Anonymize database"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db anon [name]"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       name        ${C}Database name (default: SELECTED_DB)    ${RST}"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Anonymizes the database for safe development use:"
    echo "         - Clears all email addresses"
    echo "         - Resets admin login/password to 'admin'"
    echo "         - Disables all crons"
    echo "         - Disables mail servers"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       db anon                ${C}Anonymize current DB             ${RST}"
    echo "       db anon production     ${C}Anonymize specific DB            ${RST}"
    echo ""
}

help_anon_file() {
    echo ""
    echo "db anon_file - Anonymize backup file"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db anon_file"
    echo ""
    printf "   ${C}SUPPORTED FORMATS${RST}\n"
    echo "       .sql, .dump, .zip, .7z, .tar.gz, .tgz"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Lists backups in ./db_zip/ (excluding anon_* files),"
    echo "       imports into temp DB, anonymizes, exports, and creates"
    echo "       a new file prefixed with 'anon_'. Original is deleted."
    echo ""
    printf "   ${C}ANONYMIZATION RULES${RST}\n"
    echo "         - Clears all email addresses"
    echo "         - Resets admin login/password to 'admin'"
    echo "         - Disables all crons"
    echo "         - Disables mail servers"
    echo ""
}

help_backup() {
    echo ""
    echo "db backup - Backup database to zip"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db backup [-fs|--filestore] [name]"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -fs, --filestore  ${C}Include filestore in backup          ${RST}"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       name              ${C}Database name (default: SELECTED_DB) ${RST}"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       db backup                  ${C}Backup current DB             ${RST}"
    echo "       db backup --filestore      ${C}Backup with filestore         ${RST}"
    echo "       db backup mydb             ${C}Backup specific DB            ${RST}"
    echo "       db backup -fs mydb         ${C}With filestore + specific DB  ${RST}"
    echo ""
}

help_drop() {
    echo ""
    echo "db drop - Drop database"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db drop [-y|--yes] <name>"
    echo "       db drop -f|--force [-y|--yes]"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -y, --yes     ${C}Skip confirmation                    ${RST}"
    echo "       -f, --force   ${C}Drop current DB and restart Odoo     ${RST}"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       name          ${C}Database name to drop                ${RST}"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       db drop mydb           ${C}Drop with confirmation            ${RST}"
    echo "       db drop --yes mydb     ${C}Drop without confirmation         ${RST}"
    echo "       db drop --force        ${C}Drop current DB + restart Odoo    ${RST}"
    echo "       db drop -f -y          ${C}Same, skip confirmation           ${RST}"
    echo ""
}

help_duplicate() {
    echo ""
    echo "db duplicate - Duplicate database"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db duplicate <source> <destination>"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       source      ${C}Source database name                 ${RST}"
    echo "       destination ${C}New database name                    ${RST}"
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       db duplicate production test  "
    echo "       db duplicate main backup_main "
    echo ""
}

help_list() {
    echo ""
    echo "db list - List all databases"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db list"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Shows all PostgreSQL databases with details."
    echo ""
}

help_restore() {
    echo ""
    echo "db restore - Restore database from backup"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db restore [-s] [-na] <name>"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -s, --switch    ${C}Switch to restored DB after restore  ${RST}"
    echo "       -na, --no-anon  ${C}Skip auto-anonymization              ${RST}"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       name        ${C}Target database name (required)          ${RST}"
    echo ""
    printf "   ${C}SUPPORTED FORMATS${RST}\n"
    echo "       .sql, .dump, .zip, .7z, .tar.gz, .tgz"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Lists available backups in ./db_zip/ and prompts"
    echo "       for selection. Automatically anonymizes the restored"
    echo "       database (use -na to skip). Detects and restores filestore."
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       db restore newdb          ${C}Restore + anonymize              ${RST}"
    echo "       db restore -s newdb       ${C}Restore, anonymize and switch    ${RST}"
    echo "       db restore -na newdb      ${C}Restore without anonymization    ${RST}"
    echo ""
}

help_select() {
    echo ""
    echo "db select - Set active database"
    echo ""
    printf "   ${C}USAGE${RST}\n"
    echo "       db select [-y|--yes] <name>"
    echo ""
    printf "   ${C}OPTIONS${RST}\n"
    echo "       -y, --yes    ${C}Skip confirmation for new databases       ${RST}"
    echo ""
    printf "   ${C}ARGUMENTS${RST}\n"
    echo "       name         ${C}Database name to select                   ${RST}"
    echo ""
    printf "   ${C}DESCRIPTION${RST}\n"
    echo "       Sets SELECTED_DB in .env file."
    echo "       If database doesn't exist, Odoo will create it."
    echo "       Restart Odoo with 'r' to apply changes."
    echo ""
    printf "   ${C}EXAMPLES${RST}\n"
    echo "       db select mydb          ${C}Select existing DB                   ${RST}"
    echo "       db select --yes newdb   ${C}Select/create new DB                 ${RST}"
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
        UPDATE ir_cron SET active = false WHERE active IS NOT NULL;
        UPDATE ir_mail_server SET active = false WHERE active IS NOT NULL;
        UPDATE fetchmail_server SET active = false WHERE active IS NOT NULL;
    " >/dev/null 2>&1
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

if [ -z "$1" ]; then
    echo "Selected: ${SELECTED_DB:-none}"
    echo ""
    echo "Available databases:"
    list_databases
    echo ""
    echo "PostgreSQL commands:"
    printf "  db anon [name]              ${C}Anonymize database                     ${RST}\n"
    printf "  db drop [-y] <name>         ${C}Drop database                          ${RST}\n"
    printf "  db duplicate <src> <dst>    ${C}Duplicate database                     ${RST}\n"
    printf "  db list                     ${C}Full database list                     ${RST}\n"
    printf "  db select [-y] <name>       ${C}Select active database                 ${RST}\n"
    echo ""
    echo "File commands (./db_zip/):"
    printf "  db anon_file                ${C}Anonymize backup file                  ${RST}\n"
    printf "  db backup [-fs] [name]      ${C}Backup to zip                          ${RST}\n"
    printf "  db restore [-s] [-na] <n>   ${C}Restore from backup (auto-anon)        ${RST}\n"
    exit 0
fi

case "$1" in
    anon)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_anon
            exit 0
        fi
        DBNAME="$2"
        [ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"
        if [ -z "$DBNAME" ]; then
            echo "❌ No database specified and no SELECTED_DB in .env"
            exit 1
        fi
        DB_EXISTS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DBNAME';" 2>/dev/null)
        if [ "$DB_EXISTS" != "1" ]; then
            echo "❌ Database '$DBNAME' does not exist"
            exit 1
        fi
        echo "Anonymizing '$DBNAME'..."
        anonymize_db "$DBNAME"
        echo "✓ Database anonymized: $DBNAME"
        echo "   - Emails cleared"
        echo "   - Admin: admin/admin"
        echo "   - Crons disabled"
        echo "   - Mail servers disabled"
        ;;
    anon_file)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_anon_file
            exit 0
        fi
        mkdir -p "$ZIP_DIR"
        IMPORT_LIST=($(find "$ZIP_DIR" -maxdepth 1 -type f \( -iname "*.sql" -o -iname "*.dump" -o -iname "*.zip" -o -iname "*.7z" -o -iname "*.tar.gz" -o -iname "*.tgz" \) ! -iname "anon_*" 2>/dev/null | sort -r))
        if [ ${#IMPORT_LIST[@]} -eq 0 ]; then
            echo "❌ No backup files found in $ZIP_DIR (excluding anon_*)"
            exit 1
        fi
        echo "Available backups to anonymize:"
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
        BASENAME=$(basename "$SELECTED_FILE")
        echo "Selected: $BASENAME"
        TMP_ANON_DB="anon_tmp_$$"
        EXT_LOWER=$(echo "$SELECTED_FILE" | tr '[:upper:]' '[:lower:]')
        IS_ARCHIVE=false
        [[ "$EXT_LOWER" =~ \.(zip|7z|tar\.gz|tgz)$ ]] && IS_ARCHIVE=true
        rm -rf "$TMP_DIR"
        mkdir -p "$TMP_DIR"
        SQL_FILE=""
        if $IS_ARCHIVE; then
            echo "Extracting archive..."
            case "$EXT_LOWER" in
                *.zip) unzip -qo "$SELECTED_FILE" -d "$TMP_DIR" ;;
                *.7z) 7z x -y "$SELECTED_FILE" -o"$TMP_DIR" >/dev/null ;;
                *.tar.gz|*.tgz) tar -xzf "$SELECTED_FILE" -C "$TMP_DIR" ;;
            esac
            SQL_FILE=$(find "$TMP_DIR" -type f \( -iname "*.sql" -o -iname "*.dump" \) | head -n 1)
            if [ -z "$SQL_FILE" ]; then
                echo "❌ No .sql or .dump file found in archive"
                exit 1
            fi
        else
            cp "$SELECTED_FILE" "$TMP_DIR/"
            SQL_FILE="$TMP_DIR/$(basename "$SELECTED_FILE")"
        fi
        echo "Creating temporary database..."
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_ANON_DB\";" >/dev/null 2>&1
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "CREATE DATABASE \"$TMP_ANON_DB\" OWNER $DB_USER;" >/dev/null
        echo "Importing data..."
        EXT_SQL=$(echo "$SQL_FILE" | tr '[:upper:]' '[:lower:]')
        if [[ "$EXT_SQL" =~ \.dump$ ]]; then
            docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$TMP_ANON_DB" --no-owner < "$SQL_FILE" 2>/dev/null
        else
            docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$TMP_ANON_DB" < "$SQL_FILE" >/dev/null 2>&1
        fi
        echo "Anonymizing..."
        anonymize_db "$TMP_ANON_DB"
        echo "Exporting anonymized dump..."
        docker exec "$DB_CONTAINER" pg_dump -U "$DB_USER" "$TMP_ANON_DB" > "$TMP_DIR/dump.sql"
        rm -f "$SQL_FILE" 2>/dev/null
        mv "$TMP_DIR/dump.sql" "$SQL_FILE" 2>/dev/null || cp "$TMP_DIR/dump.sql" "$SQL_FILE"
        ANON_FILE="${ZIP_DIR}/anon_${BASENAME}"
        if $IS_ARCHIVE; then
            echo "Creating anonymized archive..."
            rm -f "$TMP_DIR/dump.sql" 2>/dev/null
            (cd "$TMP_DIR" && zip -rq "$ANON_FILE" .)
        else
            cp "$SQL_FILE" "$ANON_FILE"
        fi
        echo "Cleaning up..."
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -c "DROP DATABASE IF EXISTS \"$TMP_ANON_DB\";" >/dev/null 2>&1
        TMP_ANON_DB=""
        rm -f "$SELECTED_FILE"
        echo "✓ Created: anon_${BASENAME}"
        echo "  Original file deleted"
        ;;
    backup)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
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
        [ -z "$DBNAME" ] && DBNAME="${SELECTED_DB:-}"
        if [ -z "$DBNAME" ]; then
            echo "❌ No database specified and no SELECTED_DB in .env"
            exit 1
        fi
        DB_EXISTS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DBNAME';" 2>/dev/null)
        if [ "$DB_EXISTS" != "1" ]; then
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
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
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
            DBNAME="${SELECTED_DB:-}"
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
    duplicate)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_duplicate
            exit 0
        fi
        if [ -z "$2" ] || [ -z "$3" ]; then
            echo "❌ Usage: db duplicate <source> <destination>"
            echo "   Use 'db duplicate --help' for details"
            exit 1
        fi
        docker exec "$DB_CONTAINER" createdb -U "$DB_USER" -T "$2" "$3"
        echo "✓ Database duplicated: $2 → $3"
        ;;
    list)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_list
            exit 0
        fi
        docker exec "$DB_CONTAINER" psql -U "$DB_USER" -l
        ;;
    restore)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
            help_restore
            exit 0
        fi
        SWITCH=false
        ANON=true
        DBNAME=""
        shift
        while [[ $# -gt 0 ]]; do
            case $1 in
                -s|--switch) SWITCH=true; shift ;;
                -na|--no-anon) ANON=false; shift ;;
                *) DBNAME="$1"; shift ;;
            esac
        done
        if [ -z "$DBNAME" ]; then
            echo "❌ Usage: db restore [-s] <name>"
            echo "   Use 'db restore --help' for details"
            exit 1
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
        EXT_LOWER=$(echo "$SELECTED_FILE" | tr '[:upper:]' '[:lower:]')
        IS_ARCHIVE=false
        [[ "$EXT_LOWER" =~ \.(zip|7z|tar\.gz|tgz)$ ]] && IS_ARCHIVE=true
        SQL_FILE=""
        FILESTORE_FOUND=""
        if $IS_ARCHIVE; then
            rm -rf "$TMP_DIR"
            mkdir -p "$TMP_DIR"
            echo "Extracting archive..."
            case "$EXT_LOWER" in
                *.zip) unzip -qo "$SELECTED_FILE" -d "$TMP_DIR" ;;
                *.7z) 7z x -y "$SELECTED_FILE" -o"$TMP_DIR" >/dev/null ;;
                *.tar.gz|*.tgz) tar -xzf "$SELECTED_FILE" -C "$TMP_DIR" ;;
            esac
            SQL_FILE=$(find "$TMP_DIR" -type f \( -iname "*.sql" -o -iname "*.dump" \) | head -n 1)
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
        EXT_SQL=$(echo "$SQL_FILE" | tr '[:upper:]' '[:lower:]')
        if [[ "$EXT_SQL" =~ \.dump$ ]]; then
            docker exec -i "$DB_CONTAINER" pg_restore -U "$DB_USER" -d "$DBNAME" --no-owner < "$SQL_FILE" 2>/dev/null
        else
            docker exec -i "$DB_CONTAINER" psql -U "$DB_USER" -d "$DBNAME" < "$SQL_FILE" >/dev/null
        fi
        if [ -n "$FILESTORE_FOUND" ]; then
            echo "Copying filestore..."
            mkdir -p "$FILESTORE_BASE/$DBNAME"
            cp -r "$FILESTORE_FOUND/"* "$FILESTORE_BASE/$DBNAME/" 2>/dev/null
            echo "✓ Filestore restored"
        fi
        if $ANON; then
            echo "Anonymizing database..."
            anonymize_db "$DBNAME"
            echo "✓ Database anonymized"
        fi
        echo "✓ Database restored: $DBNAME"
        if $SWITCH; then
            TMP_ENV="/tmp/.env.tmp.$$"
            sed "s/^SELECTED_DB=.*/SELECTED_DB=$DBNAME/" /home/odoo/docker_dev/.env > "$TMP_ENV"
            cat "$TMP_ENV" > /home/odoo/docker_dev/.env
            rm -f "$TMP_ENV"
            echo "✓ Switched to $DBNAME"
            echo "  Restart Odoo with 'r' to apply"
        fi
        ;;
    select)
        if [ "$2" = "-h" ] || [ "$2" = "--help" ]; then
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
        DB_EXISTS=$(docker exec "$DB_CONTAINER" psql -U "$DB_USER" -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname = '$DBNAME';" 2>/dev/null)
        if [ "$DB_EXISTS" != "1" ]; then
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
        TMP_ENV="/tmp/.env.tmp.$$"
        sed "s/^SELECTED_DB=.*/SELECTED_DB=$DBNAME/" /home/odoo/docker_dev/.env > "$TMP_ENV"
        cat "$TMP_ENV" > /home/odoo/docker_dev/.env
        rm -f "$TMP_ENV"
        echo "✓ Selected database: $DBNAME"
        echo "  Restart Odoo with 'r' to apply"
        ;;
    *)
        echo "❌ Unknown command: $1"
        echo "   Use 'db --help' for available commands"
        exit 1
        ;;
esac
