#!/bin/bash
# ============================================================================
# UI Library - Positioning and message helpers
# Gum commands use theme from config/theme.conf via GUM_* env vars
# ============================================================================

# Load theme
source /home/odoo/docker_dev/data/.docker/utils/config/theme.conf 2>/dev/null

# ============================================================================
# POSITIONING - Gum doesn't have native horizontal positioning
# ============================================================================

ui_left() {
    if [[ $# -gt 0 ]]; then echo "$*"; else cat; fi
}

ui_center() {
    local width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    if [[ $# -gt 0 ]]; then
        echo "$*" | gum style --align center --width "$width"
    else
        gum style --align center --width "$width"
    fi
}

ui_right() {
    local width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    if [[ $# -gt 0 ]]; then
        echo "$*" | gum style --align right --width "$width"
    else
        gum style --align right --width "$width"
    fi
}

ui_quarter_left() {
    local width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    local margin=$((width / 4))
    if [[ $# -gt 0 ]]; then
        echo "$*" | gum style --margin "0 0 0 $margin"
    else
        gum style --margin "0 0 0 $margin"
    fi
}

ui_quarter_right() {
    local width="${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}"
    local margin=$((width * 3 / 4))
    if [[ $# -gt 0 ]]; then
        echo "$*" | gum style --margin "0 0 0 $margin"
    else
        gum style --margin "0 0 0 $margin"
    fi
}

# ============================================================================
# QUICK MESSAGES - Styled output shortcuts
# ============================================================================

ui_success() { gum style --foreground "${COLOR_SUCCESS}" "✓ $*"; }
ui_error()   { gum style --foreground "${COLOR_ERROR}" "✗ $*"; }
ui_warn()    { gum style --foreground "${COLOR_WARNING}" "⚠ $*"; }
ui_info()    { gum style --foreground "${COLOR_INFO}" "● $*"; }
ui_debug()   { gum style --foreground "${COLOR_DEBUG}" "○ $*"; }

# ============================================================================
# STYLED LOG - gum log doesn't support per-level colors, use gum style
# ============================================================================

ui_log_debug() { gum style --foreground "${COLOR_DEBUG}" "[DEBUG] $*"; }
ui_log_info()  { gum style --foreground "${COLOR_INFO}" "[INFO]  $*"; }
ui_log_ok()    { gum style --foreground "${COLOR_SUCCESS}" "[OK]    $*"; }
ui_log_warn()  { gum style --foreground "${COLOR_WARNING}" "[WARN]  $*"; }
ui_log_error() { gum style --foreground "${COLOR_ERROR}" "[ERROR] $*"; }
ui_log_fatal() {
    local tag=$(gum style --foreground "${CLASSIC_BLACK}" --background "${COLOR_ERROR}" "[FATAL]")
    local msg=$(gum style --foreground "${COLOR_ERROR}" " $*")
    gum join "$tag" "$msg"
}
