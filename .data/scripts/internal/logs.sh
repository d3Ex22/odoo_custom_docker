#!/bin/bash
set -uo pipefail
# ============================================================================
# logs - Read the Odoo logs pane (tail, grep, errors, wait until ready)
# Internal: odoo_logs* / odoo_wait_ready MCP tools, start/reboot/update -w,
# docker exec. Humans read the logs in the hub (logs tab). Not a utils command.
# ============================================================================
# Usage: logs [-n N] [-g PATTERN] [-e] [-l LEVEL] [-w [SECONDS]] [--since TS] [--mark] [--clear]
#   -l LEVEL: records of the current run at LEVEL and above (DEBUG|INFO|WARNING|ERROR|CRITICAL),
#            with their continuation lines (tracebacks); the 'logs' utils command shows them in a pane.
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh


LINES=50
PATTERN=""
ERRORS_ONLY=false
LEVEL=""
WAIT=false
WAIT_SECONDS=120
CLEAR=false
SINCE=""

parse_global_flags "$@"
set -- "${ARGS[@]}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--lines) LINES="${2:-}"; [ -z "$LINES" ] && die "-n needs a number of lines"; shift 2 ;;
        -g|--grep) PATTERN="${2:-}"; [ -z "$PATTERN" ] && die "-g needs a pattern"; shift 2 ;;
        -e|--errors) ERRORS_ONLY=true; shift ;;
        -l|--level) LEVEL=$(echo "${2:-}" | tr a-z A-Z); shift 2
            case "$LEVEL" in DEBUG|INFO|WARNING|ERROR|CRITICAL) ;; WARN) LEVEL=WARNING ;; *) die "-l needs a level: DEBUG, INFO, WARNING, ERROR or CRITICAL" ;; esac ;;
        -w|--wait)
            WAIT=true; shift
            if [[ "${1:-}" =~ ^[0-9]+$ ]]; then WAIT_SECONDS="$1"; shift; fi ;;
        --clear) CLEAR=true; shift ;;
        --since) SINCE="${2:-}"; [ -z "$SINCE" ] && die "--since needs a timestamp 'YYYY-MM-DD HH:MM:SS' (UTC)"; shift 2 ;;
        --mark) date -u '+%Y-%m-%d %H:%M:%S'; exit 0 ;;
        *) die "Unknown option: $1" ;;
    esac
done
[[ "$LINES" =~ ^[0-9]+$ ]] || die "Invalid line count: $LINES"

require_odoo_container
LOGS_PANE="${ODOO_TMUX_SESSION}:0.1"
docker exec "$ODOO_CONTAINER" tmux has-session -t "$ODOO_TMUX_SESSION" 2>/dev/null \
    || die "Odoo logs session not started yet" "Wait for the odoo container entrypoint to finish"

# capture [START] — pane history from line START (negative = from the end,
# "-" = whole history). Colors kept only on a terminal. Wrapped lines joined.
capture() {
    local esc=""
    [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && esc="-e"
    docker exec "$ODOO_CONTAINER" tmux capture-pane -t "$LOGS_PANE" -p -J $esc -S "${1:--}" 2>/dev/null \
        | sed -e :a -e '/^[[:space:]]*$/{$d;N;ba' -e '}'
}
# Terminal output: highlight the files of your addons (tracebacks, warnings)
highlight() {
    if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
        sed -E "s#(/mnt/extra-addons/[^\"'<>, ]+)#${BPRIMARY}\1${RST}#g"
    else
        cat
    fi
}
# Lines whose log timestamp is >= TS (continuation lines follow their record)
since_ts() {
    awk -v ts="$1" '{ if ($0 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9]/) show = (substr($0, 1, 19) >= ts) } show { print }'
}

# Lines since the last start header printed by odoo_header.sh.
current_run() {
    capture - | awk '/Addon paths:/ { buf = "" } { buf = buf $0 "\n" } END { printf "%s", buf }'
}

# Records at LEVEL and above (a record = a log line with its continuation lines).
at_level() {
    awk -v min="$1" '
        BEGIN { rank["DEBUG"] = 0; rank["INFO"] = 1; rank["WARNING"] = 2; rank["ERROR"] = 3; rank["CRITICAL"] = 4; show = 0 }
        /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9] [0-9][0-9]:[0-9][0-9]:[0-9][0-9],[0-9]+ [0-9]+ [A-Z]+ / { show = (rank[$4] >= rank[min]) }
        show { print }
    '
}

# Error blocks: from an ERROR/CRITICAL/Traceback line until the next INFO line.
error_blocks() {
    awk '
        /(ERROR|CRITICAL|Traceback \(most recent call last\))/ { show = 1 }
        / INFO / && show && !/Traceback/ { show = 0 }
        show { print }
    '
}

if $CLEAR; then
    tty=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$LOGS_PANE" -p '#{pane_tty}' 2>/dev/null)
    [ -n "$tty" ] && docker exec "$ODOO_CONTAINER" bash -c "printf '\033[2J\033[H' > $tty" 2>/dev/null
    docker exec "$ODOO_CONTAINER" tmux clear-history -t "$LOGS_PANE"
    ui_ok "Logs cleared"
    exit 0
fi

if $WAIT; then
    HAS_DB=false; docker exec "$ODOO_CONTAINER" cat /tmp/.odoo_cmd 2>/dev/null | grep -q -- ' -d ' && HAS_DB=true
    started=$SECONDS
    status=""
    while true; do
        dead=$(docker exec "$ODOO_CONTAINER" tmux display-message -t "$LOGS_PANE" -p '#{pane_dead}' 2>/dev/null)
        run=$(current_run)
        if echo "$run" | grep -qE 'Failed to initialize database|Failed to load registry'; then
            status="failed"          # -u/-i aborted; the process may stay alive without a registry
        elif echo "$run" | grep -qE 'Registry loaded in|Modules loaded\.'; then
            status="ready"
        elif ! $HAS_DB && echo "$run" | grep -q 'HTTP service (werkzeug) running'; then
            status="ready"
        elif [ "$dead" = "1" ]; then
            status="dead"
        elif [ $((SECONDS - started)) -ge "$WAIT_SECONDS" ]; then
            status="timeout"
        fi
        [ -n "$status" ] && break
        sleep 1
    done
    elapsed=$((SECONDS - started))
    errors=$(echo "$run" | error_blocks)
    n_err=$(echo "$run" | grep -cE ' (ERROR|CRITICAL) ')
    n_warn=$(echo "$run" | grep -cE ' WARNING ')
    # Outcome for the status bar / hub (status.py): ready|errors|failed|dead|timeout
    { [ "$status" = "ready" ] && [ -n "$errors" ] && echo "errors|${n_err}|$(date +%s)" || echo "${status}|${n_err}|$(date +%s)"; } > /var/shared/.last_start 2>/dev/null
    case "$status" in
        ready)
            if [ -n "$errors" ]; then
                ui_warn "Odoo ready after $(fmt_duration "$elapsed") — ${n_err} error(s), ${n_warn} warning(s)"
                echo "$errors" | tail -60 | sed 's/^/  /'
                exit 2
            fi
            ui_ok "Odoo ready after $(fmt_duration "$elapsed") ${CMUTED}(${n_warn} warning(s))${RST}"
            exit 0 ;;
        failed)
            ui_err "Odoo failed to load the database after $(fmt_duration "$elapsed") — ${n_err} error(s)"
            echo "$errors" | tail -60 | sed 's/^/  /'
            ui_note "Fix the module, then: u <module>"
            exit 2 ;;
        dead)
            ui_err "Odoo process exited after $(fmt_duration "$elapsed")"
            { [ -n "$errors" ] && echo "$errors" || echo "$run"; } | tail -60 | sed 's/^/  /'
            exit 2 ;;
        timeout)
            ui_err "Odoo not ready after ${WAIT_SECONDS}s"
            echo "$run" | tail -20 | sed 's/^/  /'
            exit 1 ;;
    esac
fi

if [ -n "$LEVEL" ]; then
    out=$(current_run | at_level "$LEVEL")
    [ -n "$PATTERN" ] && out=$(echo "$out" | grep -i -- "$PATTERN")
    if [ -z "$out" ]; then ui_ok "No ${LEVEL}${PATTERN:+ matching '$PATTERN'} in the current run"; exit 0; fi
    echo "$out" | highlight
    exit 0
fi

if $ERRORS_ONLY; then
    out=$(current_run | error_blocks)
    if [ -z "$out" ]; then ui_ok "No error in the current run"; exit 0; fi
    [ -n "$PATTERN" ] && out=$(echo "$out" | grep -i -- "$PATTERN")
    echo "$out" | highlight
    exit 0
fi

if [ -n "$SINCE" ]; then
    [[ "$SINCE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] || die "Invalid --since value: $SINCE" "Format: 'YYYY-MM-DD HH:MM:SS' (UTC); --mark prints one"
    out=$(capture - | since_ts "$SINCE")
elif [ "$LINES" -eq 0 ]; then out=$(capture -); else out=$(capture "-$((LINES + 5))" | tail -n "$LINES"); fi
[ -n "$PATTERN" ] && out=$(echo "$out" | grep -i -- "$PATTERN")
[ -z "$out" ] && exit 0
printf '%s\n' "$out" | highlight
