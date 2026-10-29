#!/bin/bash
# Brightness up/down with OSD
DIR=$1 # "up", "down"
STEP=${2:-5}
DEV=nvidia_wmi_ec_backlight

if [ "$DIR" = "up" ]; then
    brightnessctl -q -d $DEV set "+$STEP%"
elif [ "$DIR" = "down" ]; then
    brightnessctl -q -d $DEV set "$STEP%-"
fi

PERC=$(( $(brightnessctl -d $DEV g) * 100 / $(brightnessctl -d $DEV m) ))

if   [ "$PERC" -lt 35 ]; then ICON="󰃞"
elif [ "$PERC" -lt 70 ]; then ICON="󰃟"
else                          ICON="󰃠"
fi

exec ~/.config/sway/osd.sh "$ICON" "$PERC%" "$PERC"
