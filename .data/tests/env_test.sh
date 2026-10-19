#!/bin/bash
set -uo pipefail
# ============================================================================
# env_test.sh - Self-test of the environment (run from the HOST, not utils)
# ============================================================================
# Copies this project twice under a temp folder (envtest_a / envtest_b), brings
# both up behind the shared proxy, checks the containers, the hub, the URLs,
# the MCP server, the mail catcher and the main utils commands, then tears
# everything down. The running proxy is reused when present (stopped at the
# end only if this script started it); your own projects are never touched.
#
#   bash .data/tests/env_test.sh [-k|--keep] [-1|--single] [-v|--verbose]
#     -k  keep the test projects running (inspect, then: env_test.sh --clean)
#     -1  a single project (faster)
#     -v  show the output of every command
#     --clean  tear down what a previous --keep left
#
# Needs: docker (compose v2), curl, rsync, python3. First run builds the images
# (several minutes); the copies reuse the images of this project afterwards.
# ENV_TEST_DIR (default $TMPDIR/odoo_env_test) and ENV_TEST_PROXY (default
# localhost:80, the Traefik entrypoint) can be overridden.
# Output is TAP-like (ok / not ok), exit 1 when a check failed.
# ============================================================================

SRC="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${ENV_TEST_DIR:-${TMPDIR:-/tmp}/odoo_env_test}"
KEEP=false; SINGLE=false; VERBOSE=false; CLEAN=false
for a in "$@"; do
    case "$a" in
        -k|--keep) KEEP=true ;; -1|--single) SINGLE=true ;; -v|--verbose) VERBOSE=true ;; --clean) CLEAN=true ;;
        -h|--help) sed -n '3,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done
PROJECTS=(envtest_a); $SINGLE || PROJECTS+=(envtest_b)
HUB="odoo.docker.localhost"; PASS=0; FAIL=0; N=0
PROXY="${ENV_TEST_PROXY:-localhost:80}"   # where Traefik listens (host:port); e.g. odoo_proxy_traefik:80 from a container
STARTED_PROXY=false

say()  { printf '\n\033[1;36m» %s\033[0m\n' "$*"; }
ok()   { N=$((N+1)); PASS=$((PASS+1)); printf 'ok %d - %s\n' "$N" "$1"; }
nok()  { N=$((N+1)); FAIL=$((FAIL+1)); printf '\033[31mnot ok %d - %s\033[0m\n' "$N" "$1"; [ -n "${2:-}" ] && printf '  # %s\n' "$2"; }
check() {   # check "description" command...  → ok when it exits 0 (eval'd: functions and pipes allowed)
    local desc="$1"; shift; local out
    if out=$(eval "$@" 2>&1); then ok "$desc"; $VERBOSE && [ -n "$out" ] && sed 's/^/    /' <<< "$out"; return 0
    else nok "$desc" "$(tail -3 <<< "$out" | tr '\n' ' ' | cut -c1-200)"; return 1; fi
}
http() { curl -s -m "${3:-5}" -o /dev/null -w '%{http_code}' -H "Host: $1" "http://${PROXY}$2" 2>/dev/null; }
wait_for() {   # wait_for SECONDS "description" command...
    local t="$1" desc="$2"; shift 2; local i=0
    while [ $i -lt "$t" ]; do eval "$@" >/dev/null 2>&1 && { ok "$desc (${i}s)"; return 0; }; sleep 2; i=$((i+2)); done
    nok "$desc" "timeout after ${t}s"; return 1
}
utils() { docker exec -u utils -e NO_COLOR=1 "$1_utils" bash "/home/utils/odoo_custom_docker/.data/scripts/commands/$2.sh" "${@:3}"; }
internal() { docker exec -u utils -e NO_COLOR=1 "$1_utils" bash "/home/utils/odoo_custom_docker/.data/scripts/internal/$2.sh" "${@:3}"; }
dc() { docker compose --project-directory "$WORK/$1" "${@:2}"; }

teardown() {
    say "Teardown"
    for p in "${PROJECTS[@]}"; do
        [ -d "$WORK/$p" ] && dc "$p" down --remove-orphans -t 2 >/dev/null 2>&1 && echo "  $p down"
    done
    docker run --rm -v odoo_env_meta:/m alpine sh -c 'rm -f /m/projects/envtest_*' >/dev/null 2>&1
    if $STARTED_PROXY; then docker compose --project-directory "$WORK/${PROJECTS[0]}/.data/proxy" down -t 2 >/dev/null 2>&1 && echo "  proxy down"; fi
    rm -rf "$WORK"/* "$WORK"/.[!.]* 2>/dev/null || docker run --rm -v "$WORK:/w" alpine sh -c 'rm -rf /w/* /w/.[!.]*' >/dev/null 2>&1
    rmdir "$WORK" 2>/dev/null; echo "  $WORK emptied"
}
if $CLEAN; then PROJECTS=(envtest_a envtest_b); teardown; exit 0; fi
trap '$KEEP || teardown' EXIT

# --- Prepare the copies -------------------------------------------------------
say "Preparing ${#PROJECTS[@]} copy(ies) under $WORK"
mkdir -p "$WORK"; rm -rf "$WORK"/* "$WORK"/.[!.]* 2>/dev/null
for p in "${PROJECTS[@]}"; do
    rsync -a --exclude .git --exclude '.data/volumes' --exclude 'db_files/*' --exclude '.data/host_project_path.map' "$SRC/" "$WORK/$p/"
    mkdir -p "$WORK/$p/addons" "$WORK/$p/db_files" "$WORK/$p/.data/volumes/shared"
    touch "$WORK/$p/.data/volumes/shared/.setup_done"   # skip the first-start wizard
    sed -i.bak -E 's/^(SELECTED_DB)=.*/\1=main/; s/^(COMPOSE_PROFILES)=.*/\1=mail/; s/^(ENTERPRISE_PATH|ODOO_PATH|SSH_PATH|ODOO_UPDATE|COMPOSE_PROJECT_NAME)=.*/\1=/; s/^(AUTO_UPDATE)=.*/\1=false/; s/^(DEBUGPY)=.*/\1=false/' "$WORK/$p/.env" && rm -f "$WORK/$p/.env.bak"
    # image tags carry the Dockerfile revision: use the current one, not the value left in .env
    sed -i.bak -E "s/^(ODOO_IMAGE_REV)=.*/\1=$(bash "$SRC/.data/scripts/image_rev.sh" odoo "$SRC")/; s/^(UTILS_IMAGE_REV)=.*/\1=$(bash "$SRC/.data/scripts/image_rev.sh" utils "$SRC")/" "$WORK/$p/.env" && rm -f "$WORK/$p/.env.bak"
done
ok "copies ready"

# --- Images -------------------------------------------------------------------
say "Images"
A="${PROJECTS[0]}"
for s in db odoo utils; do
    IMG=$(dc "$A" config --format json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['services']['$s']['image'])")
    if docker image inspect "$IMG" >/dev/null 2>&1; then ok "image $IMG present"
    else
        say "building $s ($IMG) — first run, this takes a while"
        check "build $s" dc "$A" build "$s"
    fi
done
[ "$FAIL" -gt 0 ] && { echo "cannot continue without the images"; exit 1; }

# --- Up -----------------------------------------------------------------------
say "Starting"
docker ps --format '{{.Names}}' | grep -qx odoo_proxy_traefik || STARTED_PROXY=true
for p in "${PROJECTS[@]}"; do
    check "docker compose up -d ($p)" dc "$p" up -d --quiet-pull
done
for p in "${PROJECTS[@]}"; do
    for c in db odoo utils mail; do
        wait_for 60 "$p: container ${p}_$c running" "docker inspect -f '{{.State.Running}}' ${p}_$c 2>/dev/null | grep -q true"
    done
done
wait_for 30 "proxy up (traefik + hub)" 'docker ps --format "{{.Names}}" | grep -qx odoo_proxy_traefik && docker ps --format "{{.Names}}" | grep -qx odoo_proxy_hub'
wait_for 60 "hub answers on http://$HUB" "[ \"\$(curl -s -m 3 -o /dev/null -w '%{http_code}' -H 'Host: $HUB' http://${PROXY}/api/projects)\" = 200 ]"

# --- Per project --------------------------------------------------------------
for p in "${PROJECTS[@]}"; do
    say "Project $p"
    wait_for 60 "$p: utils entrypoint done (status.json)" docker exec "${p}_utils" test -f /var/shared/status.json
    check "$p: project name resolved from the folder" "docker exec ${p}_utils cat /var/shared/.project_name | grep -qx $p"
    check "$p: registered in the shared registry" docker run --rm -v odoo_env_meta:/m:ro alpine test -f "/m/projects/$p"
    check "$p: .env image revs written" "grep -qE '^ODOO_IMAGE_REV=[0-9a-f]{8}' '$WORK/$p/.env' && grep -qE '^UTILS_IMAGE_REV=[0-9a-f]{8}' '$WORK/$p/.env'"
    check "$p: scripts linked in the odoo container" docker exec "${p}_odoo" test -x /usr/local/bin/check_paths_version.sh
    wait_for 240 "$p: Odoo ready (logs -w)" "docker exec -u utils ${p}_utils bash /home/utils/odoo_custom_docker/.data/scripts/internal/logs.sh -w 5 >/dev/null 2>&1; docker exec ${p}_utils grep -qE '^(ready|errors)\|' /var/shared/.last_start"
    check "$p: http://$p.odoo.docker.localhost → 200/303" "http $p.odoo.docker.localhost /web/login 10 | grep -qE '^(200|303)$'"
    check "$p: websocket router answers (/websocket)" "http $p.odoo.docker.localhost /websocket 5 | grep -qE '^(400|426|200)$'"
    check "$p: utils terminal served" "http $p.utils.docker.localhost / | grep -qx 200"
    check "$p: logs view served" "http $p.logs.docker.localhost / | grep -qx 200"
    wait_for 30 "$p: MCP /health through the proxy" "http $p.mcp.docker.localhost /health | grep -qx 200"
    check "$p: mail catcher served" "http $p.mail.docker.localhost /api/v1/messages | grep -qx 200"
    check "$p: odoo.conf points smtp to the mail catcher" "docker exec ${p}_odoo grep -qx 'smtp_server = mail' /etc/odoo/odoo.conf"
    check "$p: status.json has odoo=true" "docker exec ${p}_utils python3 -c \"import json;d=json.load(open('/var/shared/status.json'));assert d['project']=='$p' and d['odoo'] and d['db']\""
    check "$p: internal status" internal "$p" status
    check "$p: db list shows main" "utils $p database list | grep -q main"
    check "$p: db backup --keep 1 (x2 → one file)" "utils $p database backup -y --keep 1 main >/dev/null && utils $p database backup -y --keep 1 main >/dev/null && [ \$(ls '$WORK/$p/db_files'/main_*.zip | wc -l) -eq 1 ]"
    check "$p: db restore --last into main2" utils "$p" database restore -y -f --last main2
    check "$p: db drop main2" utils "$p" database drop -y main2
    check "$p: conf set/clear" "internal $p conf ODOO_UPDATE base >/dev/null && grep -qx 'ODOO_UPDATE=base' '$WORK/$p/.env' && internal $p conf ODOO_UPDATE - >/dev/null && grep -qx 'ODOO_UPDATE=' '$WORK/$p/.env'"
    check "$p: logs --mark / --since" "M=\$(internal $p logs --mark) && internal $p logs --since \"\$M\" >/dev/null"
    check "$p: debug status" utils "$p" debug
    check "$p: env-update dry run" utils "$p" env-update -n
    check "$p: MCP tools/list via proxy" "curl -s -m 10 -H 'Host: $p.mcp.docker.localhost' -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}' http://${PROXY}/mcp | grep -q odoo_status"
done

# --- Hub ------------------------------------------------------------------------
say "Hub"
for p in "${PROJECTS[@]}"; do
    check "hub lists $p as running with status" "curl -s -m 5 -H 'Host: $HUB' http://${PROXY}/api/projects | python3 -c \"import json,sys; d={x['name']:x for x in json.load(sys.stdin)}; p=d['$p']; assert p['running'] and (p.get('status') or {}).get('odoo') is not None, p\""
done
check "hub page served" "http $HUB / | grep -qx 200"
check "traefik dashboard served" "http traefik.docker.localhost /dashboard/ | grep -qx 200"
if ! $SINGLE; then
    say "Stop ${PROJECTS[1]}, ${PROJECTS[0]} must stay routed"
    check "docker compose stop (${PROJECTS[1]})" dc "${PROJECTS[1]}" stop -t 2
    wait_for 30 "hub shows ${PROJECTS[1]} offline (start menu)" "curl -s -m 5 -H 'Host: $HUB' http://${PROXY}/api/projects | python3 -c \"import json,sys; d={x['name']:x for x in json.load(sys.stdin)}; assert not d['${PROJECTS[1]}']['running'] and d['${PROJECTS[0]}']['running']\""
    check "${PROJECTS[0]} still answers" "http ${PROJECTS[0]}.odoo.docker.localhost /web/login 10 | grep -qE '^(200|303)$'"
    TOKEN=$(curl -s -m 5 -H "Host: $HUB" "http://${PROXY}/" | sed -n 's/.*hub-token" content="\([^"]*\)".*/\1/p')
    check "hub /api/start restarts ${PROJECTS[1]}" "curl -s -m 10 -X POST -H 'Host: $HUB' -H 'X-Hub-Token: $TOKEN' 'http://${PROXY}/api/start?project=${PROJECTS[1]}' | grep -q '\"ok\": true'"
    wait_for 90 "${PROJECTS[1]} back online" "http ${PROJECTS[1]}.odoo.docker.localhost /web/login 10 | grep -qE '^(200|303)$'"
fi

echo
printf '%d checks: \033[32m%d ok\033[0m, \033[31m%d failed\033[0m\n' "$N" "$PASS" "$FAIL"
$KEEP && echo "kept running under $WORK — bash .data/tests/env_test.sh --clean to remove"
[ "$FAIL" -eq 0 ]
