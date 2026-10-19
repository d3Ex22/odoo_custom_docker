#!/bin/bash
# ============================================================================
# Common utilities for all command scripts — source this at the start of each.
# The helpers live in lib/ (one file per concern, loaded in this order):
#   lib/env.sh      environment, container names, colors (lib/theme.sh), docker shim
#   lib/ui.sh       output conventions (ui_*), help layout (h_*), prompts
#   lib/panes.sh    global flags (-y, -p, --no-color), tmux side panes
#   lib/odoo.sh     containers, Odoo process control, compose from utils, proxy
#   lib/project.sh  images, modules, .env edition, version compatibility
#   lib/db.sh       PostgreSQL helpers
# ============================================================================
_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib"
for _f in env ui panes odoo project db; do source "${_LIB}/${_f}.sh"; done
unset _f
