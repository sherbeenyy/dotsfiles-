#!/bin/bash
swaymsg input type:keyboard xkb_switch_layout next

# Give Sway a tiny moment to apply it
sleep 0.1

# Get the current layout name
LAYOUT=$(swaymsg -t get_inputs | jq -r '.[] | select(.type=="keyboard") | .xkb_active_layout_name' | head -n1)

if [[ "$LAYOUT" == *"Arabic"* ]]; then
    ~/.config/sway/osd.sh "󰌌" "العربية"
else
    ~/.config/sway/osd.sh "󰌌" "English"
fi
