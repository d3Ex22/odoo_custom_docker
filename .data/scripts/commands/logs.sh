#!/bin/bash
# ============================================================================
# logs - Records of the current Odoo run at a log level and above, in a pane
# ============================================================================
# Usage: logs [LEVEL] [-g PATTERN]
#   LEVEL: DEBUG | INFO | WARNING (default) | ERROR | CRITICAL
# ============================================================================

source /home/utils/odoo_custom_docker/.data/scripts/common.sh

show_help() {
    h_name "logs" "Records of the current Odoo run, filtered by level"
    h_sec "USAGE"
    h_use "logs [LEVEL] [-g PATTERN]"
    h_sec "OPTIONS"
    h_opt "LEVEL" "DEBUG, INFO, WARNING (default), ERROR or CRITICAL: that level and above"
    h_opt "-g, --grep PATTERN" "Keep the lines matching PATTERN (case-insensitive)"
    h_sec "DESCRIPTION"
    h_text "Reads the logs pane since the last start of Odoo and keeps the records"
    h_text "at LEVEL and above with their continuation lines (tracebacks). In the"
    h_text "utils terminal the list opens in a side pane (wheel to scroll, any key"
    h_text "to close); without a terminal it is printed. The live log stays in the"
    h_text "hub's logs tab."
    h_sec "EXAMPLES"
    h_ex "logs" "Warnings and errors of the current run"
    h_ex "logs error" "Errors only"
    h_ex "logs info -g my_module" "Everything about my_module"
    h_global
    h_end
}

parse_global_flags "$@"
set -- "${ARGS[@]}"
LEVEL=WARNING PATTERN=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -g|--grep) PATTERN="${2:-}"; [ -z "$PATTERN" ] && die "-g needs a pattern" "See: logs --help"; shift 2 ;;
        -*) die "Unknown option: $1" "See: logs --help" ;;
        *) LEVEL=$(echo "$1" | tr a-z A-Z)
           case "$LEVEL" in DEBUG|INFO|WARNING|ERROR|CRITICAL) ;; WARN) LEVEL=WARNING ;; *) die "Unknown level: $1" "Usage: logs [DEBUG|INFO|WARNING|ERROR|CRITICAL] [-g PATTERN]" ;; esac
           shift ;;
    esac
done
require_odoo_container

INTERNAL="${_PROJECT_ROOT}/.data/scripts/internal/logs.sh"
force_pane "logs" hold   # utils terminal: side pane (scroll with the wheel, any key closes); no-op elsewhere
[ -n "${UTILS_IN_PANE:-}" ] && printf "${CPRIMARY}%s${RST} ${CMUTED}and above · current run%s${RST}\n\n" "$LEVEL" "${PATTERN:+ · grep '$PATTERN'}"
exec bash "$INTERNAL" -l "$LEVEL" ${PATTERN:+-g "$PATTERN"}
