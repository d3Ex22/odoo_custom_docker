#!/bin/bash
# ============================================================================
# lib/ui.sh — output conventions, help layout, prompts
# ui_* / h_* / die / confirm / pick_one. Colors off when piped or NO_COLOR.
# Sourced by common.sh (every command) — not meant to be sourced alone.
# ============================================================================

# ----------------------------------------------------------------------------
# 2. Output conventions
#    ✓ success   ✗ error (stderr)   ! warning   › step   ? question   · detail
# ----------------------------------------------------------------------------
ui_ok()   { printf "${CSUCCESS}✓${RST} %s\n" "$*"; }
ui_err()  { printf "${CERROR}✗${RST} %s\n" "$*" >&2; _pane_flag; }
ui_warn() { printf "${CWARN}!${RST} %s\n" "$*"; _pane_flag; }
# Inside a side pane: remember that something went wrong so the pane stays
# open at the end instead of closing by itself (see run_in_pane, smart mode).
_pane_flag() { [ -n "${UTILS_PANE_FLAG:-}" ] && : > "$UTILS_PANE_FLAG"; return 0; }
ui_step() { printf "${CPRIMARY}›${RST} %s\n" "$*"; }
ui_note() { printf "  ${CMUTED}%s${RST}\n" "$*"; }
ui_kv()   { printf "  ${CMUTED}%-16s${RST}%s\n" "$1" "$2"; }
ui_item() { printf "  ${CPRIMARY}•${RST} %s\n" "$*"; }

ui_rule() {                       # ui_rule [char] — full-width rule
    local ch="${1:-─}" out=""
    local i; for ((i = 0; i < UI_WIDTH; i++)); do out+="$ch"; done
    printf "${CMUTED}%s${RST}\n" "$out"
}
ui_title() {                      # ui_title "Title" ["subtitle"]
    echo
    ui_rule "═"
    printf "${BPRIMARY}  %s${RST}" "$1"
    [ -n "${2:-}" ] && printf "  ${CMUTED}%s${RST}" "$2"
    echo
    ui_rule "═"
    echo
}
ui_section() {                    # ui_section "Name" — light separator
    local label="  $1 "
    local pad=$((UI_WIDTH - ${#label} - 2))
    local fill=""; local i; for ((i = 0; i < pad; i++)); do fill+="─"; done
    printf "\n${CPRIMARY}──%s${RST}${CMUTED}%s${RST}\n\n" "$label" "$fill"
}

# die "message" ["hint" ...] — error + optional hints, exit 1
die() {
    ui_err "$1"; shift
    local h; for h in "$@"; do ui_note "$h"; done
    exit 1
}

fmt_duration() {                  # fmt_duration SECONDS → "1m 12s"
    local s="$1"
    if [ "$s" -ge 3600 ]; then printf "%dh %dm" $((s / 3600)) $(((s % 3600) / 60))
    elif [ "$s" -ge 60 ]; then printf "%dm %ds" $((s / 60)) $((s % 60))
    else printf "%ds" "$s"; fi
}
ui_done() {                       # ui_done "message" — success + elapsed time
    ui_ok "$1 ${CMUTED}($(fmt_duration "$SECONDS"))${RST}"
}

# --- Help layout (every --help uses these) ---
h_name() { printf "\n${BPRIMARY}%s${RST} ${CMUTED}—${RST} %s\n" "$1" "$2"; }
h_sec()  { printf "\n  ${CPRIMARY}%s${RST}\n" "$1"; }
h_use()  { printf "    %s\n" "$1"; }
h_opt()  { _h_row 24 "${CSUCCESS}" "" "$1" "${2:-}"; }
h_ex()   { _h_row 32 "" "${CMUTED}" "$1" "${2:-}"; }
_h_row() {                        # _h_row WIDTH KEYCOLOR DESCCOLOR key desc — wraps desc when key is too long
    local w="$1" kc="$2" dc="$3" key="$4" desc="$5"
    if [ -z "$desc" ]; then printf "    ${kc}%s${RST}\n" "$key"
    elif [ "${#key}" -ge "$w" ]; then printf "    ${kc}%s${RST}\n    %${w}s${dc}%s${RST}\n" "$key" "" "$desc"
    else printf "    ${kc}%-${w}s${RST}${dc}%s${RST}\n" "$key" "$desc"; fi
}
h_text() { printf "    %s\n" "$1"; }
h_global() {
    h_sec "GLOBAL FLAGS"
    h_opt "-y, --yes" "Yes to every confirmation (needed without a terminal)"
    if [ "$PANE" = "always" ]; then
        h_opt "-p, --pane" "Implied: always runs in a side pane of the utils terminal"
        h_text "                        (closes by itself on success, stays open on error/warning;"
        h_text "                        inline when no terminal is attached)"
    else
        h_opt "-p, --pane" "Run in a new side pane of the utils terminal"
    fi
    h_opt "--no-color" "Plain output (automatic when piped or NO_COLOR is set)"
}
h_end() { echo; }

# --- Prompts ---
# confirm "Question?" → 0 yes / 1 no. Honors -y; refuses silently-blocking
# prompts when no terminal is attached (AI agents, scripts).
confirm() {
    local q="$1"
    if [ "${ASSUME_YES:-false}" = true ]; then
        ui_note "$q → yes (-y)"
        return 0
    fi
    # No terminal: never block; a prompt that cannot be answered is a hard stop.
    [ -t 0 ] || die "'$q' needs confirmation but no terminal is attached" "Re-run with -y to confirm automatically"
    printf "${CWARN}?${RST} %s ${CMUTED}[y/N]${RST} " "$q"
    local a; read -r -n 1 a; echo
    SECONDS=0   # elapsed time reported by ui_done must not include the prompt
    [[ "$a" =~ ^[Yy]$ ]]
}

# pick_one "Prompt" item... → sets PICKED. Returns 1 on cancel; dies without a terminal.
pick_one() {
    local prompt="$1"; shift
    local -a items=("$@")
    PICKED=""
    [ ${#items[@]} -eq 0 ] && return 1
    [ -t 0 ] || die "'$prompt' needs an interactive choice but no terminal is attached" "Pass the value as an argument instead"
    local i
    for i in "${!items[@]}"; do
        printf "  ${CPRIMARY}%2d.${RST} %s\n" "$((i + 1))" "${items[$i]}"
    done
    echo
    printf "${CWARN}?${RST} %s ${CMUTED}[1-%d]${RST} " "$prompt" "${#items[@]}"
    local c; read -r c
    if ! [[ "$c" =~ ^[0-9]+$ ]] || [ "$c" -lt 1 ] || [ "$c" -gt ${#items[@]} ]; then
        ui_err "Invalid selection"
        return 1
    fi
    PICKED="${items[$((c - 1))]}"
}

# pick_many "Prompt" item... → sets the PICKED_ITEMS array ("1,3" / empty or
# "all" = every item). Returns 1 on an invalid answer; dies without a terminal.
pick_many() {
    local prompt="$1"; shift
    local -a items=("$@")
    PICKED_ITEMS=()
    [ ${#items[@]} -eq 0 ] && return 1
    [ -t 0 ] || die "'$prompt' needs an interactive choice but no terminal is attached" "Pass the value as an argument instead"
    local i
    for i in "${!items[@]}"; do
        printf "  ${CPRIMARY}%2d.${RST} %s\n" "$((i + 1))" "${items[$i]}"
    done
    echo
    printf "${CWARN}?${RST} %s ${CMUTED}(1,2,3 / all) [all]${RST} " "$prompt"
    local c n; read -r c
    if [ -z "$c" ] || [ "$c" = "all" ]; then PICKED_ITEMS=("${items[@]}"); return 0; fi
    for n in ${c//,/ }; do
        if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt ${#items[@]} ]; then
            ui_err "Invalid selection: $n"
            return 1
        fi
        PICKED_ITEMS+=("${items[$((n - 1))]}")
    done
}
