#!/bin/bash
# Power menu for the waybar power button

CHOICE=$(printf '%s\n' "󰌾  Lock" "󰤄  Suspend" "󰍃  Log out" "󰜉  Reboot" "󰐥  Shut down" \
    | fuzzel -d -p "󰐥   " --lines 5 -w 22)

case "$CHOICE" in
    *Lock)       swaylock ;;
    *Suspend)    swaylock -f && systemctl suspend ;;
    *"Log out")  swaymsg exit ;;
    *Reboot)     systemctl reboot ;;
    *"Shut down") systemctl poweroff ;;
esac
