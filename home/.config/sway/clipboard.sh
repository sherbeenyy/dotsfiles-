#!/bin/bash
# Clipboard history picker (cliphist + fuzzel), with thumbnails for images.
# cliphist lines are "<id>\t<preview>"; only the preview is shown, and the
# picked line is found again by its index.

THUMBS="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist-thumbs"
mkdir -p "$THUMBS"

LIST=$(cliphist list)
[ -z "$LIST" ] && { ~/.config/sway/osd.sh "󰅌" "Clipboard empty"; exit 0; }

# Decode an image entry ($1 = id, $2 = the full cliphist line) once and keep
# a 256px thumbnail + its "WxH" size
thumbnail() {
    cliphist decode <<<"$2" | python3 -c '
import sys, gi
gi.require_version("GdkPixbuf", "2.0")
from gi.repository import GdkPixbuf
loader = GdkPixbuf.PixbufLoader()
loader.write(sys.stdin.buffer.read()); loader.close()
p = loader.get_pixbuf()
w, h = p.get_width(), p.get_height()
# Centered on a transparent square: fuzzel draws icons in a square slot
s = min(1, 256 / max(w, h))
tw, th = max(1, int(w * s)), max(1, int(h * s))
canvas = GdkPixbuf.Pixbuf.new(GdkPixbuf.Colorspace.RGB, True, 8, 256, 256)
canvas.fill(0)
p.scale_simple(tw, th, GdkPixbuf.InterpType.BILINEAR).copy_area(0, 0, tw, th, canvas, (256 - tw) // 2, (256 - th) // 2)
canvas.savev(sys.argv[1], "png", [], [])
open(sys.argv[2], "w").write(f"{w}x{h}")
' "$THUMBS/$1.png" "$THUMBS/$1.size" 2>/dev/null
}

menu() {
    local id preview
    while IFS=$'\t' read -r id preview; do
        if [[ $preview == "binary data image/"* ]]; then
            [ -f "$THUMBS/$id.png" ] || thumbnail "$id" "$id"$'\t'"$preview"
            printf '󰋩  Image  %s\0icon\x1f%s\n' "$(cat "$THUMBS/$id.size" 2>/dev/null)" "$THUMBS/$id.png"
        else
            printf '%s\n' "$preview"
        fi
    done <<<"$LIST"
}

IDX=$(menu | fuzzel -d --index -p "󰅌   " -w 60 -l 8 --line-height 40) || exit 0

LINE=$(sed -n "$((IDX + 1))p" <<<"$LIST")
cliphist decode <<<"$LINE" | wl-copy

# Picked an image: show it in a notification as a preview
ID=${LINE%%$'\t'*}
[ -f "$THUMBS/$ID.png" ] && notify-send -a Screenshot -i "$THUMBS/$ID.png" "Image copied" "$(cat "$THUMBS/$ID.size" 2>/dev/null)"

# Drop thumbnails of entries that left the history
for t in "$THUMBS"/*.png; do
    id=$(basename "$t" .png)
    grep -q "^$id"$'\t' <<<"$LIST" || rm -f "$t" "$THUMBS/$id.size"
done
