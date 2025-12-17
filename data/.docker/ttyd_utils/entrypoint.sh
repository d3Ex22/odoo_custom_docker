#!/bin/bash

CONTAINER="${UTILS_CONTAINER:-odoo_utils}"

# Load theme config for colors
source /etc/theme.conf 2>/dev/null
COLOR="${UTILS_COLOR:-#2ecc71}"
R=$((16#${COLOR:1:2}))
G=$((16#${COLOR:3:2}))
B=$((16#${COLOR:5:2}))
ANSI="\033[1;38;2;${R};${G};${B}m"
RST="\033[0m"

# Create tmux session with logo
tmux new-session -d -s utils "
echo -e \"${ANSI}    ____        __                      __  __  __    _   __         ${RST}\"
echo -e \"${ANSI}   / __ \  ____/ / ____    ____        / / / / / /_  (_) / / _____   ${RST}\"
echo -e \"${ANSI}  / / / / / __  / / __ \  / __ \      / / / / / __/ / / / / / ___/   ${RST}\"
echo -e \"${ANSI} / /_/ / / /_/ / / /_/ / / /_/ /     / /_/ / / /_  / / / / (__  )    ${RST}\"
echo -e \"${ANSI} \____/  \____/  \____/  \____/      \____/  \__/ /_/ /_/ /____/     ${RST}\"
exec sleep infinity"

# Split and create main pane with reconnect loop (logo keeps 5 lines)
tmux split-window -t utils:0 -v -p 90 "
echo -e '\033[33mConnecting to utils container...\033[0m'
until docker exec $CONTAINER true 2>/dev/null; do sleep 1; done
while true; do
    docker exec -e TERM=xterm-256color -it $CONTAINER su - odoo
    EXIT_CODE=\$?
    if [ \$EXIT_CODE -ne 0 ]; then
        sleep 2
        if docker exec $CONTAINER true 2>/dev/null; then
            echo -e '\n\033[33m  Reconnecting...\033[0m'
        else
            echo -e '\033[33mWaiting for utils container...\033[0m'
            until docker exec $CONTAINER true 2>/dev/null; do sleep 1; done
        fi
    fi
done"

tmux select-pane -t utils:0.1

# Fix logo pane height (5 lines + 1 border + 1 margin = 7)
LOGO_HEIGHT=7
tmux resize-pane -t utils:0.0 -y $LOGO_HEIGHT

# Configure tmux
tmux set-option -g mouse on
tmux set-option -g pane-border-style "fg=black,bg=black"
tmux set-option -g pane-active-border-style "fg=black,bg=black"
tmux unbind -n MouseDrag1Border
tmux unbind -n MouseDrag1Pane

# Resize logo pane on client attach/resize
tmux set-hook -g client-attached "resize-pane -t utils:0.0 -y $LOGO_HEIGHT"
tmux set-hook -g client-resized "resize-pane -t utils:0.0 -y $LOGO_HEIGHT"

# Status bar
tmux set-option -g status on
tmux set-option -g status-position bottom
tmux set-option -g status-style "bg=#000000 fg=#ffffff"
tmux set-option -g status-interval 1
tmux set-option -g status-left-length 80
tmux set-option -g status-right-length 40
tmux set-option -g status-left "#(docker exec $CONTAINER /home/odoo/docker_dev/data/.docker/utils/commands/utils/status_version.sh 2>/dev/null)"
tmux set-option -g status-right "#[fg=#ffffff]#(TZ=Europe/Paris date '+%%d/%%m %%H:%%M:%%S')"
tmux set-option -g status-justify centre
tmux set-option -g window-status-current-format ""
tmux set-option -g window-status-format ""

# Load theme config
source /etc/ttyd.conf 2>/dev/null
source /etc/theme.conf 2>/dev/null

# Build theme JSON
TTYD_THEME="{\"background\": \"${TERM_BG:-#000000}\", \"foreground\": \"${TERM_FG:-#ffffff}\", \"cursor\": \"${TERM_CURSOR:-#ffffff}\", \"cursorAccent\": \"${TERM_BG:-#000000}\", \"selection\": \"${TERM_SELECTION:-#333333}\", \"black\": \"${ANSI_BLACK:-#000000}\", \"red\": \"${ANSI_RED:-#ff5555}\", \"green\": \"${ANSI_GREEN:-#50fa7b}\", \"yellow\": \"${ANSI_YELLOW:-#f1fa8c}\", \"blue\": \"${ANSI_BLUE:-#bd93f9}\", \"magenta\": \"${ANSI_MAGENTA:-#ff79c6}\", \"cyan\": \"${ANSI_CYAN:-#8be9fd}\", \"white\": \"${ANSI_WHITE:-#f8f8f2}\", \"brightBlack\": \"${ANSI_BRIGHT_BLACK:-#666666}\", \"brightWhite\": \"${ANSI_BRIGHT_WHITE:-#ffffff}\"}"

# Start ttyd
exec ttyd -W \
    -t fontFamily="\"${TTYD_FONT_FAMILY:-monospace}\"" \
    -t fontSize="${TTYD_FONT_SIZE:-14}" \
    -t fontWeight="${TTYD_FONT_WEIGHT:-500}" \
    -t fontWeightBold="${TTYD_FONT_WEIGHT_BOLD:-700}" \
    -t cursorStyle="${TTYD_CURSOR_STYLE:-block}" \
    -t cursorBlink="${TTYD_CURSOR_BLINK:-true}" \
    -t scrollback="${TTYD_SCROLLBACK:-50000}" \
    -t theme="${TTYD_THEME}" \
    tmux attach -t utils
