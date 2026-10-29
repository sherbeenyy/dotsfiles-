#!/bin/bash
# Toggle mute with OSD. Target is "speaker" or "mic".
TARGET=$1

if [ "$TARGET" = "mic" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
    if [[ $(wpctl get-volume @DEFAULT_AUDIO_SOURCE@) == *"[MUTED]"* ]]; then
        exec ~/.config/sway/osd.sh "󰍭" "Mic muted"
    else
        exec ~/.config/sway/osd.sh "󰍬" "Mic on"
    fi

elif [ "$TARGET" = "speaker" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
    # Unmuted: show the volume level it came back to
    exec ~/.config/sway/osd-volume.sh
fi
