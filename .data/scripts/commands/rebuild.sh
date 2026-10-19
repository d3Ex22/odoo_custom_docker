#!/bin/bash
set -uo pipefail
# ============================================================================
# rebuild - Build the odoo / db / utils images of the .env stack when missing
# ============================================================================
# Usage: rebuild [-h|--help] [-a|--all] [-n|--nightly] [-nc|--no-cache]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh
PANE=always   # long: runs in a side pane of the utils terminal

show_help() {
    h_name "rebuild" "Build the odoo / db / utils images for the .env versions"
    h_sec "USAGE"
    h_use "rebuild [-a] [-n] [-nc]"
    h_sec "OPTIONS"
    h_opt "-a, --all" "Rebuild the odoo and db images even if they exist"
    h_opt "-n, --nightly" "Rebuild the odoo image on the latest nightly (ODOO_BUILD=latest)"
    h_opt "-nc, --no-cache" "Ignore the Docker build cache"
    h_sec "DESCRIPTION"
    h_text "Images are tagged by stack (+ Dockerfile revision) and shared by every project:"
    h_opt "$(odoo_image)" ""
    h_opt "$(db_image)" ""
    h_opt "$(utils_image)" ""
    h_text "Without option only the missing images are built, then the containers"
    h_text "are recreated on them. Switching ODOO_VERSION / PYTHON_VERSION /"
    h_text "POSTGRES_VERSION back to a stack already built takes seconds."
    h_text "ODOO_BUILD=latest means the nightly of the day the image was built:"
    h_text "a newer nightly never forces a rebuild, use -n to refresh it."
    h_text "Changing POSTGRES_VERSION wipes every database (confirmation asked)."
    h_text "Containers are recreated with host paths so 'docker compose' keeps"
    h_text "working from the host afterwards. Takes minutes: runs in a side pane."
    h_text "ENTERPRISE_PATH / ODOO_PATH git repos are pulled to the build commit"
    h_text "(see: pull --help). Images unused for IMAGE_RETENTION_DAYS are removed daily."
    h_text "Entrypoints, scripts and web terminal are mounted: only a Dockerfile"
    h_text "change makes a new revision (then 'rebuild' builds it, the utils"
    h_text "container is recreated last and this terminal reconnects)."
    h_sec "EXAMPLES"
    h_ex "rebuild" "Build what is missing"
    h_ex "rebuild -n" "Latest nightly"
    h_ex "rebuild -a" "Rebuild the odoo and db images from the cache"
    h_ex "rebuild -a -nc" "From scratch"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
NO_CACHE=""
FORCE_ALL=false
NIGHTLY=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -nc|--no-cache) NO_CACHE="--no-cache"; shift ;;
        -a|--all) FORCE_ALL=true; shift ;;
        -n|--nightly) NIGHTLY=true; shift ;;
        *) die "Unknown option: $1" "See: rebuild --help" ;;
    esac
done

require_host_project_dir
open_pane
dc() { dc_host "$PROJECT" "$HOST_PROJECT_DIR" "$@"; }
# The hub shows the current step in the project's tab (/var/odoo-env/progress/<name>:
# '<epoch>\n<label>'), also once this terminal is gone (utils container recreated).
PROGRESS_FILE="/var/odoo-env/progress/${PROJECT}"
REBUILD_T0=$(date +%s)
progress() { mkdir -p "${PROGRESS_FILE%/*}" 2>/dev/null && printf '%s\n%s\n' "$REBUILD_T0" "$*" > "$PROGRESS_FILE" 2>/dev/null; }
trap 'rm -f "$PROGRESS_FILE"' EXIT
dc_build() {   # dc_build SERVICE [build options]: plain progress, each '#N [svc stage k/n]' step reported to the hub
    local svc="$1" line
    dc build --progress=plain "$@" 2>&1 | while IFS= read -r line; do
        printf '%s\n' "$line"
        [[ "$line" =~ ^#[0-9]+\ \[[^]]*\ ([0-9]+)/([0-9]+)\] ]] && progress "building ${svc} ${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    done
    return "${PIPESTATUS[0]}"
}
# Tags carry the Dockerfile revision: make sure .env holds the current one
sync_image_revs && ui_note "Image revision updated in .env (Dockerfile changed)"

WANTED_ODOO="${ODOO_VERSION}"
WANTED_PY="${PYTHON_VERSION}"
WANTED_PG="${POSTGRES_VERSION}"
WANTED_BUILD="${ODOO_BUILD}"
ODOO_IMG=$(odoo_image)
DB_IMG=$(db_image)
UTILS_IMG=$(utils_image)
IFS='|' read -r INSTALLED_ODOO INSTALLED_BUILD <<< "$(installed_odoo_build)"
INSTALLED_PG=$(docker exec "$DB_CONTAINER" postgres --version 2>/dev/null | grep -oP '\d+' | head -1)

NIGHTLY_BUILDS=$(nightly_builds "$WANTED_ODOO")
LATEST_BUILD=$(echo "$NIGHTLY_BUILDS" | tail -1)

if [ "$WANTED_BUILD" = "latest" ]; then
    # Resolved date is passed as build-arg: the Dockerfile ARG change
    # invalidates only the Odoo source layer, no --no-cache needed.
    BUILD_DATE="${LATEST_BUILD:-latest}"
else
    $NIGHTLY && die "ODOO_BUILD is pinned to ${WANTED_BUILD}" "Set ODOO_BUILD=latest (hub config / .env), then: rebuild -n"
    BUILD_DATE="$WANTED_BUILD"
    if [ -n "$NIGHTLY_BUILDS" ] && ! echo "$NIGHTLY_BUILDS" | grep -q "^${WANTED_BUILD}$"; then
        ui_err "Build ${WANTED_BUILD} not found on nightly.odoo.com"
        ui_note "Last builds for Odoo ${WANTED_ODOO}: $(echo "$NIGHTLY_BUILDS" | tail -5 | paste -sd' ' -)"
        ui_note "Set ODOO_BUILD=latest or one of these dates (hub config / .env)"
        exit 1
    fi
fi

if ! check_compat "$WANTED_ODOO" "$WANTED_PY" "$WANTED_PG" "$COMPAT_FILE"; then
    ui_err "Incompatible versions in .env"
    grep -E "^$WANTED_ODOO[[:space:]]*:" "$COMPAT_FILE" | while IFS=: read -r _ _ py _ pg; do
        ui_note "Odoo $WANTED_ODOO supports Python $(echo "$py" | tr -d ' ') and PostgreSQL $(echo "$pg" | tr -d ' ')"
    done
    ui_note "Fix PYTHON_VERSION / POSTGRES_VERSION in .env (hub config)"
    exit 1
fi

# --- What to build -----------------------------------------------------------
ODOO_IMG_ID=$(image_id "$ODOO_IMG")
DB_IMG_ID=$(image_id "$DB_IMG")
UTILS_IMG_ID=$(image_id "$UTILS_IMG")
BUILD_ODOO=false
BUILD_DB=false
BUILD_UTILS=false
ODOO_WHY=""
if $FORCE_ALL; then
    BUILD_ODOO=true; BUILD_DB=true; ODOO_WHY="forced (-a)"
elif $NIGHTLY; then
    if [ -n "$ODOO_IMG_ID" ] && [ "$INSTALLED_BUILD" = "$LATEST_BUILD" ] && [ "$INSTALLED_ODOO" = "$WANTED_ODOO" ]; then
        ui_ok "Already on the latest nightly ${LATEST_BUILD} ${CMUTED}(${ODOO_IMG})${RST}"
        exit 0
    fi
    BUILD_ODOO=true; ODOO_WHY="nightly ${INSTALLED_BUILD:-?} → ${BUILD_DATE}"
fi
[ -z "$ODOO_IMG_ID" ] && { BUILD_ODOO=true; ODOO_WHY="image missing"; }
[ -z "$DB_IMG_ID" ] && BUILD_DB=true
[ -z "$UTILS_IMG_ID" ] && BUILD_UTILS=true

# PostgreSQL major change: the per-project data directory cannot be reused.
WIPE_PG=false
[ -n "$INSTALLED_PG" ] && [ "$WANTED_PG" != "$INSTALLED_PG" ] && WIPE_PG=true

# Containers not running the wanted image (other stack, image rebuilt by
# another project) are recreated by compose.
RECREATE=""
runs_image() {   # runs_image CONTAINER TAG ID — created on that tag and still on its current id
    [ "$(docker inspect "$1" --format '{{.Config.Image}}' 2>/dev/null)" = "$2" ] && [ "$(container_image_id "$1")" = "$3" ]
}
! $BUILD_ODOO && ! runs_image "$ODOO_CONTAINER" "$ODOO_IMG" "$ODOO_IMG_ID" && RECREATE="$RECREATE odoo"
! $BUILD_DB && ! runs_image "$DB_CONTAINER" "$DB_IMG" "$DB_IMG_ID" && RECREATE="$RECREATE db"
! $BUILD_UTILS && ! runs_image "$UTILS_CONTAINER" "$UTILS_IMG" "$UTILS_IMG_ID" && RECREATE="$RECREATE utils"

# Mounted Odoo / Enterprise git repos follow the server code: the commit of
# the nightly that is (or will be) installed. Not fatal: the Odoo start guard
# refuses to run on a mismatched series anyway.
pull_repos() {
    [ -z "${ENTERPRISE_PATH:-}${ODOO_PATH:-}" ] && return 0
    local build="$BUILD_DATE"
    ! $BUILD_ODOO && [ -n "$INSTALLED_BUILD" ] && [ "$INSTALLED_ODOO" = "$WANTED_ODOO" ] && build="$INSTALLED_BUILD"
    local -a flags=(--build "$build")
    [ "$ASSUME_YES" = true ] && flags+=(-y)
    bash "${_PROJECT_ROOT}/.data/scripts/commands/pull.sh" "${flags[@]}" \
        || ui_warn "Repos not updated — run 'pull' after fixing the error above"
}

if ! $BUILD_ODOO && ! $BUILD_DB && ! $BUILD_UTILS && ! $WIPE_PG && [ -z "$RECREATE" ]; then
    pull_repos
    ledger_touch_current
    ui_ok "Images ready and containers up to date"
    ui_kv "Odoo" "${ODOO_IMG}  ${CMUTED}build ${INSTALLED_BUILD:-?}${RST}"
    ui_kv "PostgreSQL" "${DB_IMG}"
    ui_kv "Utils" "${UTILS_IMG}"
    if [ "$WANTED_BUILD" = "latest" ] && [ -n "$LATEST_BUILD" ] && [ "$INSTALLED_BUILD" != "$LATEST_BUILD" ]; then
        ui_note "Newer nightly ${LATEST_BUILD}: rebuild -n"
    else
        ui_note "rebuild -a to force"
    fi
    exit 0
fi

ui_title "Rebuild" "$PROJECT"
$BUILD_ODOO && ui_kv "Odoo" "${ODOO_IMG}  ${CMUTED}${ODOO_WHY}${RST}"
$BUILD_DB && ui_kv "PostgreSQL" "${DB_IMG}  ${CMUTED}image missing${RST}"
$BUILD_UTILS && ui_kv "Utils" "${UTILS_IMG}  ${CMUTED}image missing${RST}"
[ -n "$RECREATE" ] && ui_kv "Recreate" "${RECREATE# }  ${CMUTED}(image already built)${RST}"
$WIPE_PG && ui_kv "PostgreSQL" "${INSTALLED_PG} → ${WANTED_PG}  ${CMUTED}data wiped${RST}"
[ -n "$NO_CACHE" ] && ui_kv "Cache" "disabled"
echo
progress "pulling repos"
pull_repos

if $WIPE_PG; then
    ui_warn "Changing the PostgreSQL major deletes every existing database (back them up first: db backup)"
    confirm "Continue and wipe PostgreSQL ${INSTALLED_PG} data?" || { ui_note "Cancelled"; exit 0; }
    ui_step "Stopping db and odoo..."
    dc down db odoo 2>/dev/null
    ui_step "Wiping PostgreSQL data..."
    docker run --rm --user root -v "${HOST_PROJECT_DIR}/.data/volumes/db-container/pgdata:/data" "postgres:${INSTALLED_PG}" sh -c "rm -rf /data/*"
    ui_step "Wiping Odoo filestore and sessions..."
    docker run --rm --user root -v "${HOST_PROJECT_DIR}/.data/volumes/odoo-container/odoo:/data" "postgres:${INSTALLED_PG}" sh -c "rm -rf /data/filestore/* /data/sessions/*"
    RECREATE="$RECREATE db odoo"
    echo
fi

TO_UP=""
if $BUILD_ODOO; then
    ui_step "Building ${ODOO_IMG}..."
    progress "building odoo"
    dc_build odoo $NO_CACHE \
        --build-arg "ODOO_VERSION=${WANTED_ODOO}" \
        --build-arg "ODOO_BUILD=${BUILD_DATE}" \
        --build-arg "PYTHON_VERSION=${WANTED_PY}" || die "odoo build failed"
    TO_UP="$TO_UP odoo"
fi
if $BUILD_DB; then
    ui_step "Building ${DB_IMG}..."
    progress "building db"
    dc_build db $NO_CACHE --build-arg "POSTGRES_VERSION=${WANTED_PG}" || die "db build failed"
    TO_UP="$TO_UP db"
fi
if $BUILD_UTILS; then
    ui_step "Building ${UTILS_IMG}..."
    progress "building utils"
    dc_build utils $NO_CACHE || die "utils build failed"
fi
for svc in $RECREATE; do
    [[ " $TO_UP " == *" $svc "* ]] || TO_UP="$TO_UP $svc"
done
# utils last: recreating it ends this terminal (it reconnects by itself)
UP_UTILS=false
if $BUILD_UTILS || [[ " $TO_UP " == *" utils "* ]]; then UP_UTILS=true; TO_UP="${TO_UP/ utils/}"; fi

if [ -n "$TO_UP" ]; then
    ui_step "Recreating containers:${TO_UP}..."
    progress "recreating${TO_UP}"
    dc up -d --no-build --force-recreate $TO_UP || die "docker compose up failed"
fi
cp "$ENV_FILE" /var/shared/.env.applied 2>/dev/null   # the stack now matches .env: no 'env changed' flag in the hub
ledger_touch_current
# Previous versions of the rebuilt tags are now untagged: drop them right away
for old in "$ODOO_IMG_ID" "$DB_IMG_ID"; do
    [ -n "$old" ] && [ "$old" != "$(image_id "$ODOO_IMG")" ] && [ "$old" != "$(image_id "$DB_IMG")" ] \
        && docker rmi "$old" >/dev/null 2>&1
done

echo
ui_done "Rebuild complete"
ui_note "Odoo is starting (hub → logs)"
if $UP_UTILS; then
    ui_warn "Recreating the utils container on ${UTILS_IMG}: this terminal restarts in a few seconds"
    progress "recreating utils"; trap - EXIT   # the new utils container removes the file when it is up
    sleep 2
    dc up -d --no-build --force-recreate utils >/dev/null 2>&1 &
    sleep 1
fi
