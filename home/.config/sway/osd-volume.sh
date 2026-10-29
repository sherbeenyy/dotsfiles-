#!/bin/bash
# Volume up/down with OSD. Allows boosting up to 150%.
DIR=$1 # "up", "down", or nothing to just show the current level
STEP=${2:-5}
MAX=1.5

if [ "$DIR" = "up" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ 0
    wpctl set-volume -l $MAX @DEFAULT_AUDIO_SINK@ "$STEP%+"
elif [ "$DIR" = "down" ]; then
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$STEP%-"
fi

STATUS=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
VOL=$(awk '{printf "%d", $2 * 100 + 0.5}' <<<"$STATUS")

if [[ "$STATUS" == *"[MUTED]"* ]]; then
    exec ~/.config/sway/osd.sh "󰝟" "Muted" 0
fi

if   [ "$VOL" -eq 0 ];  then ICON="󰝟"
elif [ "$VOL" -lt 35 ]; then ICON="󰕿"
elif [ "$VOL" -lt 70 ]; then ICON="󰖀"
else                         ICON="󰕾"
fi

if [ "$VOL" -gt 100 ]; then
    exec ~/.config/sway/osd.sh "$ICON" "$VOL%  <span alpha='60%'>boost</span>" 100
fi
exec ~/.config/sway/osd.sh "$ICON" "$VOL%" "$VOL"
