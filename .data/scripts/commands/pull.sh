#!/bin/bash
# ============================================================================
# pull - Bring the mounted Odoo / Enterprise git repos to ODOO_VERSION
# ============================================================================
# Usage: pull [odoo|enterprise] [--build DATE|latest] [-f]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "pull" "Update the mounted Odoo / Enterprise repos to ODOO_VERSION"
    h_sec "USAGE"
    h_use "pull                       both repos (ENTERPRISE_PATH, ODOO_PATH)"
    h_use "pull odoo|enterprise       one repo"
    h_sec "OPTIONS"
    h_opt "--build DATE|latest" "Target build instead of ODOO_BUILD (used by rebuild)"
    h_opt "-f, --force" "Discard local changes first (git reset --hard)"
    h_sec "DESCRIPTION"
    h_text "For each configured path that is a git repository: fetch origin,"
    h_text "check out the ${ODOO_VERSION} branch, then move it to the right commit:"
    h_opt "ODOO_BUILD=YYYYMMDD" "last commit before that nightly build (same code as the server)"
    h_opt "ODOO_BUILD=latest" "same, with the nightly the odoo image was built on"
    h_opt "--build latest" "tip of origin/${ODOO_VERSION}"
    h_text "Runs automatically at the start of 'rebuild'. Paths that are not git"
    h_text "repositories are skipped. Odoo refuses to start when a mounted repo"
    h_text "is on another series (see: s / logs)."
    h_sec "CREDENTIALS (enterprise is a private repo)"
    h_opt "GITHUB_TOKEN" "in .env.secrets — https remotes (fine-grained token, repo read)"
    h_opt "SSH_PATH" "in .env — host ~/.ssh mounted read-only for ssh remotes"
    h_sec "EXAMPLES"
    h_ex "pull" "Both repos to the ODOO_BUILD commit"
    h_ex "pull enterprise" ""
    h_ex "pull --build latest" "Tip of the ${ODOO_VERSION} branch"
    h_ex "pull -f" "Even with local modifications"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
BUILD="${ODOO_BUILD:-latest}"
BUILD_GIVEN=false
FORCE=false
TARGETS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        --build) BUILD="${2:-}"; BUILD_GIVEN=true; [ -z "$BUILD" ] && die "--build needs a value"; shift 2 ;;
        -f|--force) FORCE=true; shift ;;
        odoo|enterprise) TARGETS+=("$1"); shift ;;
        *) die "Unknown argument: $1" "See: pull --help" ;;
    esac
done
[ ${#TARGETS[@]} -eq 0 ] && TARGETS=(enterprise odoo)
[[ "$BUILD" = "latest" || "$BUILD" =~ ^[0-9]{8}$ ]] || die "--build must be 'latest' or a date YYYYMMDD"
# ODOO_BUILD=latest: follow the nightly actually installed (only an explicit
# '--build latest' targets the tip of the branch)
if [ "$BUILD" = "latest" ] && ! $BUILD_GIVEN; then
    IFS='|' read -r _iv _ib <<< "$(installed_odoo_build)"
    [ "$_iv" = "$ODOO_VERSION" ] && [[ "$_ib" =~ ^[0-9]{8}$ ]] && BUILD="$_ib"
fi
BRANCH="${ODOO_VERSION}"
[ -z "$BRANCH" ] && die "ODOO_VERSION is empty in .env"

export GIT_TERMINAL_PROMPT=0
export GIT_SSH_COMMAND="ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes"
# Mounted repos belong to the host user: allow them. A GitHub token (from
# .env.secrets) authenticates https remotes; without one, an ssh key (SSH_PATH)
# is used for https://github.com remotes too — nothing touches the repo config.
g() {
    local -a cfg=(-c safe.directory='*' -c advice.detachedHead=false)
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        cfg+=(-c "credential.helper=!f() { echo username=x-access-token; echo password=${GITHUB_TOKEN}; }; f")
    elif ls ~/.ssh/id_* >/dev/null 2>&1; then
        cfg+=(-c "url.git@github.com:.insteadOf=https://github.com/")
    fi
    git "${cfg[@]}" "$@"
}

# Commit to check out: tip of the branch, or the last commit before the
# nightly tarball was built (its Last-Modified header; 04:00 UTC fallback).
target_commit() {
    local dir="$1"
    if [ "$BUILD" = "latest" ]; then
        g -C "$dir" rev-parse "origin/${BRANCH}"
        return
    fi
    local ts
    ts=$(curl -sI --connect-timeout 5 "https://nightly.odoo.com/${BRANCH}/nightly/src/odoo_${BRANCH}.${BUILD}.tar.gz" 2>/dev/null \
        | grep -i '^last-modified:' | cut -d' ' -f2- | tr -d '\r')
    [ -z "$ts" ] && ts="${BUILD:0:4}-${BUILD:4:2}-${BUILD:6:2} 04:00:00 +0000"
    g -C "$dir" rev-list -1 --before="$ts" "origin/${BRANCH}"
}

pull_repo() {
    local name="$1" dir="$2" host_path="$3"
    local before after dirty
    ui_step "$name  ${CMUTED}${host_path}${RST}"
    if [ -z "$host_path" ]; then
        ui_note "not configured (${name^^}_PATH is empty) — skipped"
        return 0
    fi
    if ! g -C "$dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        ui_note "not a git repository — skipped (version is still checked at Odoo start)"
        return 0
    fi
    dirty=$(g -C "$dir" status --porcelain --untracked-files=no 2>/dev/null)
    if [ -n "$dirty" ]; then
        if $FORCE; then
            g -C "$dir" reset -q --hard && ui_note "local changes discarded (-f)"
        else
            ui_err "$name has local changes — commit/stash them, or: pull -f"
            echo "$dirty" | head -5 | sed 's/^/    /'
            return 1
        fi
    fi
    if ! out=$(g -C "$dir" fetch -q origin "$BRANCH" 2>&1); then
        ui_err "$name: fetch failed"
        echo "$out" | tail -3 | sed 's/^/    /'
        echo "$out" | grep -qiE "authentication|permission|denied|could not read" \
            && ui_note "Private repo: GITHUB_TOKEN in .env.secrets, or a key in SSH_PATH (.env) — github.com https remotes then go over ssh"
        return 1
    fi
    before=$(g -C "$dir" rev-parse --short HEAD)
    local before_branch; before_branch=$(g -C "$dir" rev-parse --abbrev-ref HEAD 2>/dev/null)
    after=$(target_commit "$dir") || { ui_err "$name: no commit found for ${BRANCH} / ${BUILD}"; return 1; }
    [ -z "$after" ] && { ui_err "$name: no commit found before build ${BUILD} on ${BRANCH}"; return 1; }
    g -C "$dir" checkout -q -B "$BRANCH" "$after" 2>/dev/null || { ui_err "$name: checkout failed"; return 1; }
    g -C "$dir" branch -q --set-upstream-to="origin/${BRANCH}" "$BRANCH" 2>/dev/null
    local short date
    short=$(g -C "$dir" rev-parse --short HEAD)
    date=$(g -C "$dir" log -1 --format=%cs HEAD)
    if [ "$short" = "$before" ] && [ "$before_branch" = "$BRANCH" ]; then
        ui_ok "$name already on ${BRANCH} @ ${short} ${CMUTED}(${date})${RST}"
    elif [ "$short" = "$before" ]; then
        ui_ok "$name → ${BRANCH} @ ${short} ${CMUTED}(${date}, was on ${before_branch})${RST}"
    else
        ui_ok "$name → ${BRANCH} @ ${short} ${CMUTED}(${date}, was ${before})${RST}"
    fi
}

ui_title "Pull" "branch ${BRANCH} · build ${BUILD}"
FAILED=0
for t in "${TARGETS[@]}"; do
    case "$t" in
        enterprise) pull_repo enterprise "${_PROJECT_ROOT}/${ENTERPRISE_PATH}" "${ENTERPRISE_PATH:-}" || FAILED=$((FAILED + 1)) ;;
        odoo)       pull_repo odoo "/home/utils/odoo_src" "${ODOO_PATH:-}" || FAILED=$((FAILED + 1)) ;;
    esac
done
echo
[ "$FAILED" -gt 0 ] && die "Pull finished with ${FAILED} error(s)"
ui_done "Repos up to date"
if container_running "$ODOO_CONTAINER" && odoo_process_running; then
    ui_note "u all to reload the code into the running database (or r)"
fi
exit 0
