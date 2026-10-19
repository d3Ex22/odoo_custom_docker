#!/bin/bash
# ============================================================================
# watch - Auto 'u <module>' when a module's __manifest__.py is saved
# ============================================================================
# Usage: watch [on|off]
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

# ADDONS_PATH is relative to the project folder (./addons)
_rel="${ADDONS_PATH:-addons}"; _rel="${_rel#./}"
ADDONS_DIR="${_PROJECT_ROOT}/${_rel%/}"; unset _rel
STAMP="/tmp/.watch_stamp"
INTERVAL=2

show_help() {
    h_name "watch" "Auto-update a module when its __manifest__.py is saved"
    h_sec "USAGE"
    h_use "watch"
    h_use "watch on|off"
    h_sec "COMMANDS"
    h_opt "(none)" "Show whether the watcher is on and its pane is open"
    h_opt "on" "Start the watcher in a side pane and save AUTO_UPDATE=true"
    h_opt "off" "Close the pane and save AUTO_UPDATE=false"
    h_sec "DESCRIPTION"
    h_text "Every ${INTERVAL}s the watcher looks for __manifest__.py files modified under"
    h_text "addons/. Saving one (e.g. bumping the version) triggers 'u <module> -w'"
    h_text "in the pane; several saves within a few seconds are grouped in one"
    h_text "update. Only manifests trigger it, so plain code edits never restart"
    h_text "Odoo behind your back. AUTO_UPDATE is persisted in .env: the pane"
    h_text "reopens on the next 'docker compose up'. Without SELECTED_DB"
    h_text "(multi-db mode) the pane asks once which database(s) to update."
    h_sec "EXAMPLES"
    h_ex "watch on" "Enable"
    h_ex "watch off" "Disable"
    h_global
    h_end
}

watch_pane_id() { utils_tmux list-panes -t utils:0 -F '#{pane_id} #{@role}' 2>/dev/null | awk '$2 == "watch" {print $1}'; }

# --- the loop running inside the pane ---
watch_loop() {
    SECONDS=0
    ui_title "Watch" "__manifest__.py saved → u <module>"
    ui_note "Stop: watch off"
    echo
    [ -d "$ADDONS_DIR" ] || die "addons/ folder not found: $ADDONS_DIR"
    # Multi-db mode: -u needs a database, asked once for the whole watch session.
    local -a db_opt=()
    if [ -z "${SELECTED_DB:-}" ]; then
        pick_db "Auto-update which database?" all || exit 1
        db_opt=(-d "$PICKED")
        ui_ok "Updates will run on ${PICKED//,/, }  (watch off / on to change)"
        echo
    fi
    touch "$STAMP"
    local -a changed
    local pending="" f mod
    while true; do
        sleep "$INTERVAL"
        changed=()
        while IFS= read -r f; do changed+=("$f"); done < <(find "$ADDONS_DIR" -name '__manifest__.py' -newer "$STAMP" -not -path '*/.*' 2>/dev/null)
        touch "$STAMP"
        if [ ${#changed[@]} -gt 0 ]; then
            for f in "${changed[@]}"; do
                mod=$(basename "$(dirname "$f")")
                [[ ",$pending," == *",$mod,"* ]] || pending="${pending:+$pending,}$mod"
            done
            continue   # debounce: wait one quiet interval before updating
        fi
        [ -z "$pending" ] || {
            printf "${CMUTED}%s${RST}  " "$(date +%H:%M:%S)"; ui_step "Manifest saved → u ${pending}"
            bash "${_PROJECT_ROOT}/.data/scripts/commands/update.sh" -w "${db_opt[@]}" "$pending"
            echo
            pending=""
            touch "$STAMP"   # ignore changes made by the update itself
        }
    done
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
case "${1:-}" in
    -h|--help) show_help; exit 0 ;;
    --loop) watch_loop ;;
    --resume)   # from the entrypoint: reopen the pane when AUTO_UPDATE=true, no .env write
        [ "${AUTO_UPDATE:-false}" = "true" ] || exit 0
        pane_exists watch && exit 0
        run_in_pane "watch" "40%" close bash "${_PROJECT_ROOT}/.data/scripts/commands/watch.sh" --loop ;;
    on)
        set_env_value "AUTO_UPDATE" "true"
        if pane_exists watch; then
            ui_ok "Watcher already running"
        else
            run_in_pane "watch" "40%" close bash "${_PROJECT_ROOT}/.data/scripts/commands/watch.sh" --loop || exit 1
            ui_ok "Watcher started in a side pane"
        fi
        ui_note "Save a __manifest__.py under addons/ to trigger u <module>  ·  watch off to stop" ;;
    off)
        set_env_value "AUTO_UPDATE" "false"
        id=$(watch_pane_id)
        if [ -n "$id" ]; then utils_tmux kill-pane -t "$id" 2>/dev/null; ui_ok "Watcher stopped"
        else ui_ok "Watcher was not running"; fi ;;
    "")
        if [ "${AUTO_UPDATE:-false}" = "true" ]; then
            if pane_exists watch; then ui_ok "Watcher is on (pane open)"
            else ui_warn "AUTO_UPDATE=true but the pane is closed"; ui_note "watch on to reopen it"; fi
        else
            ui_note "Watcher is off  (watch on to enable)"
        fi ;;
    *) die "Unknown option: $1" "See: watch --help" ;;
esac
