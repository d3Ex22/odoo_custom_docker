#!/bin/bash
# ============================================================================
# Shared tmux session configuration.
# Called from both odoo and utils entrypoints after creating the tmux session.
#
# Usage: tmux_setup.sh <session_name> <logo_height> <status_left_cmd> [iot_pane_cols]
# Optional iot_pane_cols: reapplies -x on ${SESSION}:0.2 when the client attaches/resizes.
# ============================================================================

SESSION="$1"
LOGO_HEIGHT="${2:-6}"
STATUS_LEFT_CMD="$3"
IOT_PANE_COLS="${4:-}"

# --- Input & clipboard ---
tmux set-option -g mouse on
tmux set-option -g set-clipboard on
tmux set-window-option -g history-limit "${TMUX_SCROLLBACK:-50000}"
tmux set-option -ga terminal-overrides ",xterm-256color:Ss=\\E[%p1%d q:Se=\\E[2 q"
tmux set-option -ga terminal-overrides ",xterm-256color:Ms=\\E]52;c%p1%.0s;%p2%s\\007"

# --- Redirect clicks/scrolls on logo pane (index 0) to main pane ---
tmux bind -T root MouseDown1Pane "if-shell '[ #{pane_index} -eq 0 ]' 'select-pane -t ${SESSION}:0.1' 'select-pane -t =; send-keys -M'"
tmux bind -T root WheelUpPane   "if-shell '[ #{pane_index} -eq 0 ]' 'select-pane -t ${SESSION}:0.1' 'copy-mode -et='"
tmux bind -T root WheelDownPane "if-shell '[ #{pane_index} -eq 0 ]' 'select-pane -t ${SESSION}:0.1' 'send-keys -M'"
tmux bind -T root MouseDrag1Pane    "if-shell '[ #{pane_index} -eq 0 ]' '' 'copy-mode -M'"
tmux bind -T root MouseDragEnd1Pane "if-shell '[ #{pane_index} -eq 0 ]' '' 'copy-selection-and-cancel'"
tmux unbind -T root MouseDrag1Border

# --- Pane & window styles ---
tmux set-option -g pane-border-style        "fg=${TMUX_BORDER_FG},bg=${TMUX_BORDER_BG}"
tmux set-option -g pane-active-border-style "fg=${TMUX_BORDER_FG},bg=${TMUX_BORDER_BG}"
tmux set-option -g window-style             "bg=${TMUX_BG},fg=${TMUX_FG}"
tmux set-option -g window-active-style      "bg=${TMUX_BG},fg=${TMUX_FG}"

# --- Logo height; optional IoT column width after client attach/resize ---
if [ -n "$IOT_PANE_COLS" ]; then
    tmux set-hook -g client-attached "resize-pane -t ${SESSION}:0.0 -y $LOGO_HEIGHT ; resize-pane -t ${SESSION}:0.2 -x $IOT_PANE_COLS"
    tmux set-hook -g client-resized "run-shell \"tmux resize-pane -t ${SESSION}:0.0 -y $LOGO_HEIGHT && tmux resize-pane -t ${SESSION}:0.2 -x $IOT_PANE_COLS\""
else
    tmux set-hook -g client-attached "resize-pane -t ${SESSION}:0.0 -y $LOGO_HEIGHT"
    tmux set-hook -g client-resized "run-shell \"tmux resize-pane -t ${SESSION}:0.0 -y $LOGO_HEIGHT\""
fi

# --- Status bar ---
tmux set-option -g status on
tmux set-option -g status-position   bottom
tmux set-option -g status-style      "bg=${TMUX_STATUS_BG} fg=${TMUX_STATUS_FG}"
tmux set-option -g status-interval   1
tmux set-option -g status-left-length  80
tmux set-option -g status-right-length 40
tmux set-option -g status-justify    centre
tmux set-option -g window-status-current-format ""
tmux set-option -g window-status-format         ""
tmux set-option -g status-left  "$STATUS_LEFT_CMD"
tmux set-option -g status-right "#[fg=${TMUX_STATUS_FG}]#(TZ=Europe/Paris date '+%%d/%%m %%H:%%M:%%S')"
