#!/bin/bash
# Screenshot straight into satty: the shot goes to the clipboard right away,
# then satty opens fullscreen on the focused screen with the crop tool ready.
#   screenshot-menu.sh          focused screen
#   screenshot-menu.sh all      all screens
#
# In satty: drag to crop, annotate, Enter = copy + save, Esc = close
# (the unedited shot is already in the clipboard).

# satty lives in ~/.local/bin, which sway's own PATH may not include
export PATH="$HOME/.local/bin:$PATH"

SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"
FILE="$SAVE_DIR/screenshot_$(date +%Y-%m-%d_%H-%M-%S).png"
TMP=$(mktemp --suffix=.png)
trap 'rm -f "$TMP"' EXIT

notify() { notify-send -a Screenshot -i "$2" "$1" "$3"; }

if [ "$1" = all ]; then
    grim "$TMP"
else
    grim -o "$(swaymsg -t get_outputs -r | jq -r '.[] | select(.focused).name')" "$TMP"
fi

[ -s "$TMP" ] || exit 1
wl-copy --type image/png < "$TMP"

# Config: ~/.config/satty/config.toml (Enter copies with wl-copy and saves to $FILE)
satty --filename "$TMP" --output-filename "$FILE" --fullscreen --initial-tool crop

if [ -s "$FILE" ]; then
    notify "Screenshot copied & saved" "$FILE" "~/Pictures/Screenshots/$(basename "$FILE")"
else
    # Preview what's in the clipboard now (the edited image after Ctrl+C);
    # $TMP can't be used as it's deleted on exit
    LAST="${XDG_CACHE_HOME:-$HOME/.cache}/screenshot-last.png"
    wl-paste --type image/png > "$LAST" 2>/dev/null || cp "$TMP" "$LAST"
    notify "Screenshot copied" "$LAST" "Not saved to disk."
fi
