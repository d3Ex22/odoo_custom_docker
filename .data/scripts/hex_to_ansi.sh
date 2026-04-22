#!/bin/bash
# ============================================================================
# Converts COLOR_* hex variables into ANSI escape sequences.
# Source this AFTER loading the active theme.
# C* = normal, B* = bold
# ============================================================================

_hex_to_ansi() {
    local hex="${1#\#}"
    printf '\033[38;2;%s;%s;%sm' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}

_hex_to_ansi_bold() {
    local hex="${1#\#}"
    printf '\033[1;38;2;%s;%s;%sm' "$((16#${hex:0:2}))" "$((16#${hex:2:2}))" "$((16#${hex:4:2}))"
}
# --- ANSI Reset Sequence ---
RST=$(printf '\033[0m')

# --- ANSI Colors ---
CPRIMARY=$(_hex_to_ansi "${COLOR_PRIMARY}")
CSECONDARY=$(_hex_to_ansi "${COLOR_SECONDARY}")
CTERTIARY=$(_hex_to_ansi "${COLOR_TERTIARY}")
CACCENT=$(_hex_to_ansi "${COLOR_ACCENT}")
CSURFACE=$(_hex_to_ansi "${COLOR_SURFACE}")
CMUTED=$(_hex_to_ansi "${COLOR_MUTED}")

CBG=$(_hex_to_ansi "${COLOR_BG}")
CFG=$(_hex_to_ansi "${COLOR_FG}")

CDEBUG=$(_hex_to_ansi "${COLOR_DEBUG}")
CINFO=$(_hex_to_ansi "${COLOR_INFO}")
CSUCCESS=$(_hex_to_ansi "${COLOR_SUCCESS}")
CWARN=$(_hex_to_ansi "${COLOR_WARNING}")
CERROR=$(_hex_to_ansi "${COLOR_ERROR}")
CDANGER=$(_hex_to_ansi "${COLOR_DANGER}")

# --- ANSI Bold Colors ---
BPRIMARY=$(_hex_to_ansi_bold "${COLOR_PRIMARY}")
BSECONDARY=$(_hex_to_ansi_bold "${COLOR_SECONDARY}")
BTERTIARY=$(_hex_to_ansi_bold "${COLOR_TERTIARY}")
BACCENT=$(_hex_to_ansi_bold "${COLOR_ACCENT}")
BSURFACE=$(_hex_to_ansi_bold "${COLOR_SURFACE}")
BMUTED=$(_hex_to_ansi_bold "${COLOR_MUTED}")

BBG=$(_hex_to_ansi_bold "${COLOR_BG}")
BFG=$(_hex_to_ansi_bold "${COLOR_FG}")

BDEBUG=$(_hex_to_ansi_bold "${COLOR_DEBUG}")
BINFO=$(_hex_to_ansi_bold "${COLOR_INFO}")
BSUCCESS=$(_hex_to_ansi_bold "${COLOR_SUCCESS}")
BWARN=$(_hex_to_ansi_bold "${COLOR_WARNING}")
BERROR=$(_hex_to_ansi_bold "${COLOR_ERROR}")
BDANGER=$(_hex_to_ansi_bold "${COLOR_DANGER}")
