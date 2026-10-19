#!/bin/bash
set -uo pipefail
# ============================================================================
# env-update - Refresh the environment files of this project from the template
# ============================================================================
# Usage: env-update [-n] [--ref REF | --from PATH]
#
# Each project is a self-contained copy of the template repository (its own
# git). This command fetches the template (ENV_TEMPLATE_REPO / ENV_TEMPLATE_REF
# in .env, or a local working copy with --from: a folder of the host as Docker
# sees it, or one visible in this container) and replaces the
# environment-owned files only:
#   .data/**          (except volumes/ and host_project_path.map)
#   docker-compose.yml .dockerignore AGENTS.md
# README*, CHANGELOG.md, docs/ and .gitignore only serve the template repository:
# never copied to a project, removed from it when a copy brought them.
# User-owned files are never overwritten: .env (new keys are appended with
# their comments), .config/**, addons/**, db_files/** — files of
# .config/ are copied only when missing here (or ours is a comments-only placeholder).
# Files owned by the environment that the template no longer has are removed.
# .data/.template_rev remembers the template commit. .data/VERSION is the release of the
# environment: the status loop compares it with the template's and the hub
# proposes this command when a newer one is published (bump it to publish).
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "env-update" "Update the environment files from the template repository"
    h_sec "USAGE"
    h_use "env-update [-n|--dry-run] [--ref REF | --from PATH]"
    h_sec "OPTIONS"
    h_opt "-n, --dry-run" "Show what would change, write nothing"
    h_opt "--ref REF" "Template branch / tag / commit (default: ENV_TEMPLATE_REF, else default branch)"
    h_opt "--from PATH" "Local working copy of the template instead of a clone: a host folder"
    h_opt "" "(as Docker sees it, e.g. /Users/me/odoo_custom_docker) or one visible here"
    h_sec "DESCRIPTION"
    h_text "Fetches ENV_TEMPLATE_REPO (.env) — or copies --from — and refreshes the environment files"
    h_text "of this project: .data/ (scripts, images, proxy, MCP, web terminal),"
    h_text "docker-compose.yml, .dockerignore, AGENTS.md (README*, CHANGELOG.md, docs/ and the"
    h_text "template .gitignore stay in the template: removed from a project)."
    h_text "Never overwritten: .env (missing keys are appended, values kept),"
    h_text ".config/ (new files only), addons/, db_files/, volumes."
    h_text "The project stays a single standalone git repository: review the"
    h_text "result with 'git status' / 'git diff' and commit it."
    h_text "Afterwards, as reported: rebuild (Dockerfile changed), docker compose"
    h_text "up -d from the host (compose changed). The hub and the MCP server are"
    h_text "restarted here when their files changed."
    h_sec "EXAMPLES"
    h_ex "env-update -n" "Preview"
    h_ex "env-update" "Apply (asks for confirmation)"
    h_ex "env-update --ref 19.0" "Follow a specific branch of the template"
    h_ex "env-update --from /Users/me/odoo_custom_docker" "Try the template you are editing before publishing it"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
DRY=false; REF="${ENV_TEMPLATE_REF:-}"; FROM=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -n|--dry-run) DRY=true; shift ;;
        --ref) REF="${2:-}"; [ -z "$REF" ] && die "--ref needs a value"; shift 2 ;;
        --from) FROM="${2:-}"; [ -z "$FROM" ] && die "--from needs a path"; shift 2 ;;
        *) die "Unknown option: $1" "See: env-update --help" ;;
    esac
done
[ -z "$FROM" ] && [ -z "${ENV_TEMPLATE_REPO:-}" ] && die "ENV_TEMPLATE_REPO is not set in .env" "ENV_TEMPLATE_REPO=https://github.com/<you>/odoo_custom_docker.git (hub config / .env)"

ROOT="$_PROJECT_ROOT"
REV_FILE="${ROOT}/.data/.template_rev"
TMP=$(mktemp -d /tmp/env-update.XXXXXX); trap 'rm -rf "$TMP"' EXIT
TPL="${TMP}/template"

# Files owned by the environment (relative paths, as tracked by the template).
env_owned() {   # env_owned PATH → 0 when the template version must replace ours
    case "$1" in
        .data/volumes/*|.data/host_project_path.map|.data/.template_rev) return 1 ;;
        .data/*|docker-compose.yml|.dockerignore|AGENTS.md) return 0 ;;
        *) return 1 ;;
    esac
}
# Files that only serve the template repository: never copied to a project,
# removed when a copy brought them (the utils entrypoint does the same at start).
TEMPLATE_ONLY=(README.md README.fr.md CHANGELOG.md docs .gitignore)
# .config/ files are the user's: only copied when missing here, or when ours
# holds nothing but comments (an untouched placeholder of a previous release).
# .config/utils/.zshrc of releases < 4.0 held the whole shell (now .data/scripts/zshrc.sh): replaced too.
config_wanted() {
    case "$1" in
        .config/utils/.zshrc) [ ! -e "${ROOT}/$1" ] || grep -q '^_CMDS=' "${ROOT}/$1" || ! grep -qvE '^\s*(#|$)' "${ROOT}/$1" ;;
        .config/*) [ ! -e "${ROOT}/$1" ] || ! grep -qvE '^\s*(#|$)' "${ROOT}/$1" ;;
        *) return 1 ;;
    esac
}

OLD_REV=$(cat "$REV_FILE" 2>/dev/null || true)
if [ -n "$FROM" ]; then
    ui_title "Environment update" "local copy ${FROM}"
    ui_step "Copying the working copy..."
    if [ -d "$FROM" ]; then
        cp -a "$FROM" "$TPL"
    else   # a host folder: the daemon mounts it into a throwaway container of our own image
        mkdir -p "$TPL"
        docker run --rm --entrypoint tar -v "${FROM}:/src:ro" "$(docker inspect --format '{{.Config.Image}}' "$UTILS_CONTAINER")" \
            -C /src -cf - --exclude=./.data/volumes . 2>"${TMP}/copy.err" | tar -C "$TPL" -xf - \
            || die "Cannot read ${FROM}" "$(tail -1 "${TMP}/copy.err")"
    fi
    [ -f "${TPL}/.data/VERSION" ] || die "${FROM} is not an environment template (.data/VERSION missing)"
    # tracked + untracked files of a working copy (not the ignored ones); plain folder → every file
    if git -C "$TPL" rev-parse --git-dir >/dev/null 2>&1; then
        NEW_REV=$(git -C "$TPL" rev-parse HEAD); git -C "$TPL" diff --quiet HEAD 2>/dev/null || NEW_REV="${NEW_REV}-dirty"
        git -C "$TPL" ls-files -co --exclude-standard > "${TMP}/files"
    else
        NEW_REV="local"; (cd "$TPL" && find . -type f ! -path './.git/*' | sed 's|^\./||') > "${TMP}/files"
    fi
    LABEL="$FROM"
else
    ui_title "Environment update" "${ENV_TEMPLATE_REPO}${REF:+ @ $REF}"
    ui_step "Fetching the template..."
    git clone -q "$ENV_TEMPLATE_REPO" "$TPL" 2>"${TMP}/clone.err" || die "Cannot fetch the template" "$(tail -1 "${TMP}/clone.err")"
    if [ -n "$REF" ]; then
        git -C "$TPL" checkout -q "$REF" 2>"${TMP}/clone.err" || die "Unknown template ref: ${REF}" "$(tail -1 "${TMP}/clone.err")"
    fi
    NEW_REV=$(git -C "$TPL" rev-parse HEAD)
    git -C "$TPL" ls-files > "${TMP}/files"
    LABEL=$(git -C "$TPL" log -1 --format='%h  %cs  %s' | cut -c1-70)
    if [ -n "$OLD_REV" ] && [ "$OLD_REV" = "$NEW_REV" ]; then ui_ok "Already up to date"; exit 0; fi
fi
NEW_VER=$(cat "${TPL}/.data/VERSION" 2>/dev/null)
ui_kv "Template" "${NEW_VER:+v$NEW_VER  }${LABEL}"
ui_kv "This project" "v$(cat "${ROOT}/.data/VERSION" 2>/dev/null || echo '?')${OLD_REV:+  (template ${OLD_REV:0:7})}"

# Compare the template tree with ours: ADD / UPDATE / DELETE lists
ADDED=(); UPDATED=(); DELETED=(); CONFIG_NEW=()
while IFS= read -r f; do
    if env_owned "$f"; then
        if [ ! -e "${ROOT}/$f" ]; then ADDED+=("$f")
        elif ! cmp -s "${TPL}/$f" "${ROOT}/$f"; then UPDATED+=("$f"); fi
    elif config_wanted "$f"; then
        CONFIG_NEW+=("$f")
    fi
done < "${TMP}/files"
# environment-owned files we have that the template no longer has (caches aside)
while IFS= read -r f; do
    env_owned "$f" && ! grep -qxF "$f" "${TMP}/files" && DELETED+=("$f")
done < <(cd "$ROOT" && find .data -type f ! -path '*/__pycache__/*' ! -name '*.pyc' ! -path './.data/volumes/*' | sed 's|^\./||')
REPO_NAME=$(git -C "$ROOT" config --get remote.origin.url 2>/dev/null | sed -E 's#/+$##; s#.*[/:]##; s/\.git$//')
if [ -z "$REPO_NAME" ] || [ "$(basename "$(cat "${ROOT}/.data/host_project_path.map" 2>/dev/null)")" != "$REPO_NAME" ]; then
    for f in "${TEMPLATE_ONLY[@]}"; do [ -e "${ROOT}/$f" ] && DELETED+=("$f"); done
fi

# .env: keys of the template missing here, with the comment lines above them
ENV_MISSING="${TMP}/env_missing"; : > "$ENV_MISSING"
awk -v ours="${ROOT}/.env" '
    BEGIN { while ((getline l < ours) > 0) if (match(l, /^[A-Za-z_][A-Za-z0-9_]*=/)) have[substr(l, 1, RLENGTH - 1)] = 1 }
    /^#/ { buf = buf $0 "\n"; next }
    /^[A-Za-z_][A-Za-z0-9_]*=/ { k = $0; sub(/=.*/, "", k); if (!(k in have)) { printf "%s%s\n\n", buf, $0; buf = "" }; next }
    { buf = "" }
' "${TPL}/.env" > "$ENV_MISSING"
ENV_KEYS=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_MISSING" | tr -d '=' | paste -sd' ' -)

TOTAL=$(( ${#ADDED[@]} + ${#UPDATED[@]} + ${#DELETED[@]} + ${#CONFIG_NEW[@]} ))
if [ "$TOTAL" -eq 0 ] && [ -z "$ENV_KEYS" ]; then
    $DRY || { echo "$NEW_REV" > "$REV_FILE"; sync_image_revs; }
    ui_ok "Environment files already match the template"; exit 0
fi
echo
[ ${#UPDATED[@]} -gt 0 ] && { ui_section "Updated (${#UPDATED[@]})"; printf "  ${CMUTED}~${RST} %s\n" "${UPDATED[@]}"; }
[ ${#ADDED[@]} -gt 0 ]   && { ui_section "Added (${#ADDED[@]})";   printf "  ${CSUCCESS}+${RST} %s\n" "${ADDED[@]}"; }
[ ${#DELETED[@]} -gt 0 ] && { ui_section "Removed (${#DELETED[@]})"; printf "  ${CERROR}-${RST} %s\n" "${DELETED[@]}"; }
[ ${#CONFIG_NEW[@]} -gt 0 ] && { ui_section "New config files (${#CONFIG_NEW[@]})"; printf "  ${CSUCCESS}+${RST} %s\n" "${CONFIG_NEW[@]}"; }
[ -n "$ENV_KEYS" ] && { ui_section ".env keys appended"; ui_note "$ENV_KEYS"; }
echo
if $DRY; then ui_note "dry run: nothing written"; exit 0; fi
confirm "Apply to this project? (.env values, .config/, addons/, db_files/ untouched)" || exit 0

for f in "${UPDATED[@]}" "${ADDED[@]}" "${CONFIG_NEW[@]}"; do
    [ -z "$f" ] && continue
    mkdir -p "$(dirname "${ROOT}/$f")"
    cp -p "${TPL}/$f" "${ROOT}/$f.env-update.tmp" && mv -f "${ROOT}/$f.env-update.tmp" "${ROOT}/$f"
done
for f in "${DELETED[@]}"; do [ -n "$f" ] && rm -rf "${ROOT:?}/$f"; done
if [ -n "$ENV_KEYS" ]; then
    { sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "${ROOT}/.env"; printf '\n# --- Added by env-update (%s) ---\n' "$(date +%F)"
      sed -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$ENV_MISSING"; } > "${TMP}/env_full" \
        && cat "${TMP}/env_full" > "${ROOT}/.env"   # in place: keeps the inode
fi
chmod +x "${ROOT}"/.data/scripts/*.sh "${ROOT}"/.data/scripts/commands/*.sh 2>/dev/null
sync_image_revs   # .env follows the new Dockerfiles: the hub and status bar flag the rebuild now
echo "$NEW_REV" > "$REV_FILE"
rm -f /var/shared/.env_update   # status loop: re-check the template release now
ui_done "Environment ${NEW_VER:-} updated to ${NEW_REV:0:7}"

CHANGED=$(printf '%s\n' "${UPDATED[@]}" "${ADDED[@]}" "${DELETED[@]}")
ui_section "Next steps"
ui_item "git status / git diff — review, then commit in this project"
echo "$CHANGED" | grep -qE '^\.data/docker/' && ui_item "rebuild — Dockerfiles changed (new image revision)"
echo "$CHANGED" | grep -qx 'docker-compose.yml' && ui_item "docker compose up -d (from the host) — docker-compose.yml changed"
echo "$CHANGED" | grep -qE '^\.data/scripts/' && ui_item "exec zsh — reload completion / aliases in this terminal"
[ -n "$ENV_KEYS" ] && ui_item "review the new .env keys appended at the end of the file (hub config)"
# Always-on services: restart them here when their files changed (in the
# background: when the hub or the MCP server itself started this command,
# the restart must not cut the report short).
BG_LOG=/var/shared/env-update.log
if echo "$CHANGED" | grep -qE '^\.data/mcp/'; then
    ui_item "MCP server restarting (server changed) — log: .data/volumes/shared/env-update.log"
    (sleep 2; bash "${_PROJECT_ROOT}/.data/scripts/internal/mcp.sh" restart) >> "$BG_LOG" 2>&1 &
fi
if echo "$CHANGED" | grep -qE '^\.data/proxy/'; then
    ui_item "hub recreating in the background (shared proxy / hub changed) — log: .data/volumes/shared/env-update.log"
    (sleep 2; proxy_up --build --force-recreate && echo "$(date '+%F %T') hub recreated" || echo "$(date '+%F %T') hub recreate FAILED") >> "$BG_LOG" 2>&1 &
fi
exit 0
