#!/bin/bash
# ============================================================================
# lib/panes.sh — global flags and tmux side panes of the utils terminal
# parse_global_flags (-y, -p, --no-color), run_in_pane, force_pane.
# Sourced by common.sh (every command) — not meant to be sourced alone.
# ============================================================================

# ----------------------------------------------------------------------------
# 3. Global flags — parse_global_flags "$@"; then: set -- "${ARGS[@]}"
#    -y/--yes → ASSUME_YES ; --no-color ; -p/--pane → re-run self in a pane
#
#    PANE=always, set by a script BEFORE parse_global_flags: long / verbose
#    commands run in a side pane when started from the utils terminal
#    (-p is implied). The pane opens only when the script calls open_pane,
#    after its arguments are checked: usage errors and help print in the
#    prompt pane, the side pane shows the long run and its prompts. Without
#    a terminal (agents, docker exec, pipes) everything runs inline. The pane
#    is "smart": closes by itself on success, stays open on error or warning.
#    A pane still open when the next command starts (done, waiting for a key)
#    is closed first: the side column shows the last run.
# ----------------------------------------------------------------------------
ASSUME_YES="${ASSUME_YES:-false}"
PANE="${PANE:-optional}"
ORIG_ARGS=()

# A human in the utils terminal: stdout is a tty owned by a pane of the utils
# tmux session (the shell is started with 'su -', so $TMUX is not inherited),
# and not already inside a side pane.
in_utils_terminal() {
    [ -t 1 ] && [ -z "${UTILS_IN_PANE:-}" ] || return 1
    local tty; tty=$(tty 2>/dev/null) || return 1
    utils_tmux list-panes -t utils -F '#{pane_tty}' 2>/dev/null | grep -qx "$tty"
}

parse_global_flags() {
    ARGS=()
    ORIG_ARGS=("$@")
    local want_pane=false help=false a
    for a in "$@"; do
        case "$a" in
            -y|--yes)   ASSUME_YES=true ;;
            -p|--pane)  want_pane=true ;;
            --no-color) export NO_COLOR=1; disable_colors ;;
            -h|--help)  help=true; ARGS+=("$a") ;;
            *) ARGS+=("$a") ;;
        esac
    done
    [ -n "${UTILS_IN_PANE:-}" ] && return 0
    $help && return 0   # help is read here, never in a pane
    if [ "$PANE" = "always" ]; then
        in_utils_terminal && PANE_PENDING=true   # opened by open_pane, after the checks
    elif $want_pane; then
        in_utils_terminal || ui_note "-p needs the utils terminal — running here"
        force_pane "$CMD_NAME"
    fi
    return 0
}

# open_pane — called by a PANE=always script once its arguments are valid:
# moves to the side pane when parse_global_flags decided so, no-op otherwise.
open_pane() { [ "${PANE_PENDING:-false}" = true ] && force_pane "$CMD_NAME"; return 0; }

# force_pane ROLE [MODE] — move to a side pane now (db restore, logs -f...):
# re-runs the command with its original arguments; no-op outside the terminal.
force_pane() {
    local role="$1" mode="${2:-smart}"
    in_utils_terminal || return 0
    run_in_pane "$role" "50%" "$mode" "$0" "${ORIG_ARGS[@]}" || exit 1
    ui_ok "$role running in a side pane"
    exit 0
}

# ----------------------------------------------------------------------------
# 4. tmux side panes (utils terminal). Panes are tagged with a role; a second
#    pane of the same role gets a numbered suffix (test, test·2). The first
#    pane splits the prompt in two columns, the next ones stack in the side
#    column (the prompt keeps its width).
# ----------------------------------------------------------------------------
utils_tmux() {
    if [ "$(id -u)" -eq 0 ]; then tmux -S "$UTILS_TMUX_SOCKET" "$@"
    else sudo tmux -S "$UTILS_TMUX_SOCKET" "$@"; fi
}
pane_exists() { utils_tmux list-panes -t utils:0 -F '#{@role}' 2>/dev/null | grep -qx "$1"; }
unique_role() {   # unique_role ROLE → ROLE, ROLE·2, ROLE·3...
    local role="$1" n=2
    pane_exists "$role" || { echo "$role"; return; }
    while pane_exists "${role}·${n}"; do n=$((n + 1)); done
    echo "${role}·${n}"
}

# run_in_pane ROLE SIZE MODE CMD [ARGS...]
#   SIZE: tmux -l value of the first side pane (e.g. 50% or 40 columns).
#   MODE: smart = close 2s after a clean exit, wait for a key when the exit
#         code is not 0 or a ui_warn / ui_err was printed (UTILS_PANE_FLAG)
#         close = close as soon as CMD exits (interactive tools)
#         hold  = always wait for a key
run_in_pane() {
    local role="$1" size="$2" mode="$3"; shift 3
    utils_tmux has-session -t utils 2>/dev/null || { ui_err "utils tmux session not found"; return 1; }
    # Panes left open after their command ended (waiting for a key) make room
    # for the new one: a side pane shows the last command only.
    local done_pane
    for done_pane in $(utils_tmux list-panes -t utils:0 -F '#{pane_id} #{@done}' 2>/dev/null | awk '$2 == 1 {print $1}'); do
        utils_tmux kill-pane -t "$done_pane" 2>/dev/null
    done
    role=$(unique_role "$role")
    local script="/tmp/.pane_$$.sh" flag="/tmp/.pane_$$.flag"
    local mark; printf -v mark 'sudo tmux -S %q set-option -p -t "$TMUX_PANE" @done 1 2>/dev/null' "$UTILS_TMUX_SOCKET"
    {
        echo '#!/bin/bash'
        echo 'export UTILS_IN_PANE=1'
        [ "$mode" != "close" ] && printf 'export UTILS_PANE_FLAG=%q\n' "$flag"
        printf 'rm -f %q\n' "$script"
        printf '%q ' "$@"; echo
        case "$mode" in
            hold)
                echo 'rc=$?; echo'
                echo 'printf "\033[2m── done (exit %s) · press any key to close ──\033[0m" "$rc"'
                echo "$mark"
                echo 'read -rsn1' ;;
            smart)
                echo 'rc=$?; echo'
                printf 'if [ "$rc" -ne 0 ] || [ -e %q ]; then\n' "$flag"
                echo '    printf "\033[2m── done (exit %s) · press any key to close ──\033[0m" "$rc"'
                echo "    $mark"
                echo '    read -rsn1'
                echo 'else'
                echo '    printf "\033[2m── done · closing ──\033[0m"; sleep 2'
                echo 'fi'
                printf 'rm -f %q\n' "$flag" ;;
        esac
    } > "$script"
    chmod 755 "$script"
    # First pane: split the prompt horizontally. Next ones: split the tallest
    # side pane vertically so the prompt keeps its width.
    local target="utils:0.1" dir="-h" tallest
    tallest=$(utils_tmux list-panes -t utils:0 -F '#{pane_height} #{pane_id} #{@role}' 2>/dev/null \
        | awk 'NF == 3' | sort -rn | head -1 | cut -d' ' -f2)
    [ -n "$tallest" ] && { target="$tallest"; dir="-v"; size="50%"; }
    local id
    id=$(utils_tmux split-window -t "$target" $dir -l "$size" -P -F '#{pane_id}' \
        "su utils -s /bin/bash $script") || { rm -f "$script"; return 1; }
    utils_tmux set-option -p -t "$id" @role "$role" 2>/dev/null
    utils_tmux select-pane -t "$id" -T "$role" 2>/dev/null
    return 0
}
