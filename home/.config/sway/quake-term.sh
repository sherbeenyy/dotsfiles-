#!/bin/bash
if swaymsg -t get_tree | grep -q '"app_id": "quake_term"'; then
    swaymsg '[app_id="quake_term"] resize set width 1536 px height 918 px, move position center, scratchpad show'
else
    # It doesn't exist, spawn it!
    # Because of the for_window rule in sway config, it will automatically
    # go to the scratchpad, so we wait 0.5s and then show it.
    foot -a quake_term &
    sleep 0.2
    swaymsg '[app_id="quake_term"] resize set width 1536 px height 918 px, move position center, scratchpad show'
fi
