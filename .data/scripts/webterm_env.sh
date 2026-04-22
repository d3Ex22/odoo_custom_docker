#!/bin/bash
# ============================================================================
# Build WEBTERM_* environment variables and generate the xterm.js theme JSON.
# Source this after loading web-terminal.conf and TERM_* color variables.
# Expects: WEBTERM_CMD and WEBTERM_TITLE to be set by the caller.
# ============================================================================

export WEBTERM_FONT_FAMILY="${WEBTERM_FONT_FAMILY}"
export WEBTERM_FONT_SIZE="${WEBTERM_FONT_SIZE}"
export WEBTERM_FONT_WEIGHT="${WEBTERM_FONT_WEIGHT}"
export WEBTERM_FONT_WEIGHT_BOLD="${WEBTERM_FONT_WEIGHT_BOLD}"
export WEBTERM_SCROLLBACK="${WEBTERM_SCROLLBACK:-50000}"
export WEBTERM_MSG_CONNECTING="${WEBTERM_MSG_CONNECTING}"
export WEBTERM_MSG_RECONNECTING="${WEBTERM_MSG_RECONNECTING}"
export WEBTERM_MSG_COPIED="${WEBTERM_MSG_COPIED}"
export WEBTERM_OVERLAY_COLOR="${WEBTERM_OVERLAY_COLOR}"
export WEBTERM_OVERLAY_BG="${WEBTERM_OVERLAY_BG}"
export WEBTERM_THEME=$(python3 -c "
import json, os
g = os.environ.get
print(json.dumps({
    'background': g('TERM_BG',''), 'foreground': g('TERM_FG',''),
    'cursor': g('TERM_CURSOR',''), 'cursorAccent': g('TERM_BG',''),
    'selection': g('TERM_SELECTION',''), 'black': g('TERM_BLACK',''),
    'red': g('TERM_RED',''), 'green': g('TERM_GREEN',''),
    'yellow': g('TERM_YELLOW',''), 'blue': g('TERM_BLUE',''),
    'magenta': g('TERM_MAGENTA',''), 'cyan': g('TERM_CYAN',''),
    'white': g('TERM_WHITE',''), 'brightBlack': g('TERM_BRIGHT_BLACK',''),
    'brightRed': g('TERM_BRIGHT_RED',''), 'brightGreen': g('TERM_BRIGHT_GREEN',''),
    'brightYellow': g('TERM_BRIGHT_YELLOW',''), 'brightBlue': g('TERM_BRIGHT_BLUE',''),
    'brightMagenta': g('TERM_BRIGHT_MAGENTA',''), 'brightCyan': g('TERM_BRIGHT_CYAN',''),
    'brightWhite': g('TERM_BRIGHT_WHITE',''),
}))
")
