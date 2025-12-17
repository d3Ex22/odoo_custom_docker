#!/bin/bash
# test-ui - Demo of UI library and Gum capabilities

source /home/odoo/docker_dev/data/.docker/utils/config/theme.conf 2>/dev/null
source /home/odoo/docker_dev/data/.docker/utils/lib/ui.sh 2>/dev/null

clear
echo ""

# ============================================================================
# HEADER
# ============================================================================
gum style --border double --align center --width 50 --foreground "$NEON_CYAN" --border-foreground "$NEON_CYAN" \
    "UI LIBRARY TEST" \
    "Gum + Cyberpunk Theme" | ui_center

# ============================================================================
# COLOR PALETTE
# ============================================================================

echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "Cyberpunk Palette"
echo ""
gum style --foreground "$CYBER_CYAN" "  ████ CYBER_CYAN     $CYBER_CYAN"
gum style --foreground "$CYBER_MAGENTA" "  ████ CYBER_MAGENTA  $CYBER_MAGENTA"
gum style --foreground "$CYBER_PINK" "  ████ CYBER_PINK     $CYBER_PINK"
gum style --foreground "$CYBER_PURPLE" "  ████ CYBER_PURPLE   $CYBER_PURPLE"
gum style --foreground "$CYBER_TEAL" "  ████ CYBER_TEAL     $CYBER_TEAL"
gum style --foreground "$CYBER_LIGHT" "  ████ CYBER_LIGHT    $CYBER_LIGHT"
gum style --foreground "$CYBER_YELLOW" "  ████ CYBER_YELLOW   $CYBER_YELLOW"
gum style --foreground "$CYBER_OLIVE" "  ████ CYBER_OLIVE    $CYBER_OLIVE"
gum style --foreground "$CYBER_RED" "  ████ CYBER_RED      $CYBER_RED"
gum style --foreground "$CYBER_DARKRED" "  ████ CYBER_DARKRED  $CYBER_DARKRED"
gum style --foreground "$CYBER_BLUE" "  ████ CYBER_BLUE     $CYBER_BLUE"
gum style --foreground "$CYBER_DARK" "  ████ CYBER_DARK     $CYBER_DARK"

echo ""
gum style --border rounded --width 50 --foreground "$NEON_CYAN" --border-foreground "$NEON_PURPLE" "Neon Palette"
echo ""
gum style --foreground "$NEON_PINK" "  ████ NEON_PINK      $NEON_PINK"
gum style --foreground "$NEON_PURPLE" "  ████ NEON_PURPLE    $NEON_PURPLE"
gum style --foreground "$NEON_BLUE" "  ████ NEON_BLUE      $NEON_BLUE"
gum style --foreground "$NEON_LIGHT" "  ████ NEON_LIGHT     $NEON_LIGHT"
gum style --foreground "$NEON_CYAN" "  ████ NEON_CYAN      $NEON_CYAN"
gum style --foreground "$NEON_ORANGE" "  ████ NEON_ORANGE    $NEON_ORANGE"
gum style --foreground "$NEON_LIME" "  ████ NEON_LIME      $NEON_LIME"

export CLASSIC_RED="#ff0000" # #ff0000
export CLASSIC_GREEN="#00ff00" # #00ff00
export CLASSIC_YELLOW="#ffff00" # #ffff00
export CLASSIC_BLUE="#0000ff" # #0000ff
export CLASSIC_MAGENTA="#ff00ff" # #ff00ff
export CLASSIC_CYAN="#00ffff" # #00ffff
export CLASSIC_WHITE="#ffffff" # #ffffff
export CLASSIC_BLACK="#000000" # #000000
export CLASSIC_GRAY="#808080" # #808080
export CLASSIC_LIGHT_GRAY="#d3d3d3" # #d3d3d3
export CLASSIC_DARK_GRAY="#404040" # #404040

echo ""
gum style --border rounded --width 50 --foreground "$CLASSIC_WHITE" --border-foreground "$CLASSIC_GRAY" "Classic Palette"
echo ""
gum style --foreground "$CLASSIC_RED" "  ████ CLASSIC_RED      $CLASSIC_RED"
gum style --foreground "$CLASSIC_GREEN" "  ████ CLASSIC_GREEN    $CLASSIC_GREEN"
gum style --foreground "$CLASSIC_YELLOW" "  ████ CLASSIC_YELLOW   $CLASSIC_YELLOW"
gum style --foreground "$CLASSIC_BLUE" "  ████ CLASSIC_BLUE     $CLASSIC_BLUE"
gum style --foreground "$CLASSIC_MAGENTA" "  ████ CLASSIC_MAGENTA  $CLASSIC_MAGENTA"
gum style --foreground "$CLASSIC_CYAN" "  ████ CLASSIC_CYAN     $CLASSIC_CYAN"
gum style --foreground "$CLASSIC_WHITE" "  ████ CLASSIC_WHITE    $CLASSIC_WHITE"
gum style --foreground "$CLASSIC_BLACK" "  ████ CLASSIC_BLACK    $CLASSIC_BLACK"
gum style --foreground "$CLASSIC_GRAY" "  ████ CLASSIC_GRAY     $CLASSIC_GRAY"
gum style --foreground "$CLASSIC_LIGHT_GRAY" "  ████ CLASSIC_LIGHT_GRAY $CLASSIC_LIGHT_GRAY"
gum style --foreground "$CLASSIC_DARK_GRAY" "  ████ CLASSIC_DARK_GRAY $CLASSIC_DARK_GRAY"

# ============================================================================
# POSITIONING (ui.sh functions)
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "Positioning (ui.sh)" | ui_center
echo ""

gum style --border rounded --width 15 --foreground "$CYBER_CYAN" "ui_left" | ui_left
gum style --border rounded --width 20 --foreground "$CYBER_MAGENTA" "ui_quarter_left" | ui_quarter_left
gum style --border rounded --width 15 --foreground "$CYBER_PINK" "ui_center" | ui_center
gum style --border rounded --width 20 --foreground "$CYBER_YELLOW" "ui_quarter_right" | ui_quarter_right
gum style --border rounded --width 15 --foreground "$CYBER_TEAL" "ui_right" | ui_right
echo ""

# ============================================================================
# QUICK MESSAGES (ui.sh functions)
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "Quick Messages (ui.sh)"
echo ""

ui_success "Success message"
ui_error "Error message"
ui_warn "Warning message"
ui_info "Info message"
ui_debug "Debug message"

# ============================================================================
# GUM STYLE
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum style"
echo ""

gum style --border none --width 40 --padding "0 1" --align left "none border"
gum style --border hidden --width 40 --padding "0 1" --align left "hidden border"
gum style --border normal --width 40 --padding "0 1" --align center "normal border"
gum style --border rounded --width 40 --padding "0 1" --align center "rounded border"
gum style --border thick --width 40 --padding "0 1" --align right "thick border"
gum style --border double --width 40 --padding "0 1" --align right "double border"
gum style --bold "  Bold text"
gum style --faint "  Faint text"
gum style --italic "  Italic text"
gum style --strikethrough "  Strikethrough text"
gum style --underline "  Underline text"
gum style --foreground "$CYBER_CYAN" --background "$CYBER_DARK" "  Cyan on dark"

# ============================================================================
# GUM FILTER
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum filter"
echo ""

# All gum filters below are set to use minimal/no-fullscreen display via --height or --width for prompt-mode where possible.

# Basic filtering usage with placeholder, single line prompt mode
echo -e "Apple\nBanana\nOrange\nStrawberry\nGrape" | gum filter --placeholder "Type to filter fruit..." --height=10

# Advanced: filter with custom indicator, header, prompt, color, limit, single line mode
echo -e "Dog\nCat\nRabbit\nParrot\nHamster" | gum filter \
  --indicator "➤" \
  --header "Choose your favorite pets:" \
  --prompt "Pet> " \
  --limit 2 \
  --indicator.foreground="$CYBER_MAGENTA" \
  --header.foreground="$CYBER_YELLOW" \
  --prompt.foreground="$CYBER_CYAN" \
  --height=10

# Filter with no limit, multiple selection, minimal height
echo -e "Red\nGreen\nBlue\nYellow\nPurple" | gum filter --header "Select all your favorite colors:" --no-limit --height=10

# Fuzzy off and pre-filled value, minimized height
echo -e "Paris\nLondon\nBerlin\nMadrid\nRome" | gum filter --placeholder "Filter city..." --fuzzy=false --value "Par" --height=10

# Custom selected/unselected prefix, reverse display, styled match, minimal height
echo -e "Jazz\nRock\nBlues\nClassical\nPop" | gum filter \
  --selected-prefix="[x]" \
  --unselected-prefix="[ ]" \
  --reverse \
  --header "What music styles?" \
  --match.foreground="$CYBER_PINK" \
  --height=10

# Timeout for filter input, minimal height
echo -e "One\nTwo\nThree\nFour" | gum filter --timeout 5s --header "Select a number fast (5s)!" --height=1

# ============================================================================
# GUM CONFIRM
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum confirm"
echo ""

if gum confirm "Continue?"; then
    ui_success "Confirmed!"
else
    ui_warn "Cancelled!"
fi

# ============================================================================
# GUM INPUT
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum input"
echo ""

INPUT=$(gum input --header "  Your name:" --placeholder "John..." --width 40)
ui_success "Hello, $INPUT!"

# ============================================================================
# GUM SPIN (all spinners)
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum spin (all spinners)"
echo ""

gum spin --spinner line --title "  line" -- sleep 5
gum spin --spinner dot --title "  dot" -- sleep 5
gum spin --spinner minidot --title "  minidot" -- sleep 5
gum spin --spinner jump --title "  jump" -- sleep 5
gum spin --spinner pulse --title "  pulse" -- sleep 5
gum spin --spinner points --title "  points" -- sleep 5
gum spin --spinner meter --title "  meter" -- sleep 5
ui_success "All spinners done!"

# ============================================================================
# GUM JOIN (layout boxes side by side)
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum join (horizontal)"
echo ""

BOX1=$(gum style --border rounded --width 20 --foreground "$CYBER_CYAN" "Box 1")
BOX2=$(gum style --border rounded --width 20 --foreground "$CYBER_MAGENTA" "Box 2")
BOX3=$(gum style --border rounded --width 20 --foreground "$CYBER_PINK" "Box 3")
gum join --horizontal "$BOX1" "$BOX2" "$BOX3"

echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum join (vertical)"
echo ""

BOX4=$(gum style --border rounded --width 30 --foreground "$CYBER_TEAL" "Top Box")
BOX5=$(gum style --border rounded --width 30 --foreground "$CYBER_YELLOW" "Bottom Box")
gum join --vertical "$BOX4" "$BOX5"

echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum join (align)"
echo ""

TALL=$(gum style --border rounded --width 15 --height 5 --foreground "$NEON_PINK" "Tall")
SHORT=$(gum style --border rounded --width 15 --foreground "$NEON_CYAN" "Short")
gum join --horizontal --align top "$TALL" "$SHORT"
echo ""
gum join --horizontal --align center "$TALL" "$SHORT"
echo ""
gum join --horizontal --align bottom "$TALL" "$SHORT"

# ============================================================================
# GUM TABLE
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "gum table"
echo ""

echo "Module,Version,Status
base,19.0,✓
sale,19.0,✓
stock,19.0,○" | gum table --print

# ============================================================================
# STYLED LOG MESSAGES
# ============================================================================
echo ""
gum style --border rounded --width 50 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_BLUE" "Styled Log Messages"
echo ""

ui_log_debug "Debug message"
ui_log_info "Info message"
ui_log_ok "Success message"
ui_log_warn "Warning message"
ui_log_error "Error message"
ui_log_fatal "Fatal message"

# ============================================================================
# DONE
# ============================================================================
echo ""
gum style --border double --align center --width 30 --foreground "$CYBER_CYAN" --border-foreground "$CYBER_PURPLE" \
    "Test Complete!" | ui_center
echo ""
