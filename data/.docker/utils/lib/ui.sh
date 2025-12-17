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

ui_debug()   { gum style --bold --foreground "${COLOR_DEBUG}" "○ $*"; }
ui_info()    { gum style --bold --foreground "${COLOR_INFO}" "● $*"; }
ui_success() { gum style --bold --foreground "${COLOR_SUCCESS}" "✓ $*"; }
ui_warn()    { gum style --bold --foreground "${COLOR_WARNING}" "⚠ $*"; }
ui_error()   { gum style --bold --foreground "${COLOR_ERROR}" "✗ $*"; }
ui_fatal()   { gum style --bold --background "${COLOR_ERROR}" --foreground "${CLASSIC_BLACK}" "✗✗ $*"; }

# ============================================================================
# STYLED LOG - gum log doesn't support per-level colors, use gum style
# ============================================================================

ui_log_debug() { 
    local tag=$(gum style --bold --foreground "${COLOR_DEBUG}" "[DEBUG]")
    local msg=$(gum style --foreground "${COLOR_DEBUG}" " $*")
    gum join "$tag" "$msg"
}
ui_log_info()  { 
    local tag=$(gum style --bold --foreground "${COLOR_INFO}" "[INFO]")
    local msg=$(gum style --foreground "${COLOR_INFO}" " $*")
    gum join "$tag" "$msg"
}
ui_log_ok()    { 
    local tag=$(gum style --bold --foreground "${COLOR_SUCCESS}" "[OK]")
    local msg=$(gum style --foreground "${COLOR_SUCCESS}" " $*")
    gum join "$tag" "$msg"
}
ui_log_warn()  { 
    local tag=$(gum style --bold --foreground "${COLOR_WARNING}" "[WARN]")
    local msg=$(gum style --foreground "${COLOR_WARNING}" " $*")
    gum join "$tag" "$msg"
}
ui_log_error() { 
    local tag=$(gum style --bold --foreground "${COLOR_ERROR}" "[ERROR]")
    local msg=$(gum style --foreground "${COLOR_ERROR}" " $*")
    gum join "$tag" "$msg"
}
ui_log_fatal() {
    local tag=$(gum style --bold --foreground "${CLASSIC_BLACK}" --background "${COLOR_ERROR}" "[FATAL]")
    local msg=$(gum style --foreground "${COLOR_ERROR}" " $*")
    gum join "$tag" "$msg"
}
