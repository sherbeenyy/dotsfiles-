#!/bin/bash

CURRENT=$(basename $(readlink ~/.config/themes/current))
ALL_THEMES="tokyo-night gruvbox catppuccin nord dracula one-dark rose-pine everforest monokai-pro kanagawa pitch-black"

THEME_LIST=""
for t in $ALL_THEMES; do
    if [ "$t" = "$CURRENT" ]; then
        THEME_LIST="${THEME_LIST}${t} (Active)\n"
    else
        THEME_LIST="${THEME_LIST}${t}\n"
    fi
done

# Fuzzel dropdown for themes
CHOICE=$(echo -e "$THEME_LIST" | fuzzel -d -p "󰏘   " --lines 11 -w 30)

if [ ! -z "$CHOICE" ]; then
    # Strip the (Active) part
    CLEAN_CHOICE=$(echo "$CHOICE" | awk '{print $1}')
    if [ "$CLEAN_CHOICE" != "$CURRENT" ]; then
        ~/.config/themes/switch-theme.sh "$CLEAN_CHOICE"
    fi
fi
