#!/bin/bash


while true; do
    BAT_STATUS=$(cat /sys/class/power_supply/BAT*/status | head -n 1 2>/dev/null)
    BAT_CAPACITY=$(cat /sys/class/power_supply/BAT*/capacity | head -n 1 2>/dev/null)
    
    if [ -n "$BAT_CAPACITY" ] && [ "$BAT_STATUS" = "Discharging" ] && [ "$BAT_CAPACITY" -le 20 ]; then
        notify-send -c battery -u critical -a "Power Manager" "󰂃 Low Battery ($BAT_CAPACITY%)" "plug in the charger now !"
        
        # Sleep for 5 minutes so it doesn't spam every minute, but will remind them again if they ignore it
        sleep 300
    else
        # Check every 60 seconds
        sleep 60
    fi
done
