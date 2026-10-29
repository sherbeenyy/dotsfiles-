#!/bin/bash
# Show an on-screen display popup through mako (category "osd").
#   osd.sh <icon> <text> [percent]
# With a percent, mako fills the pill from the left like a progress bar.
# All OSDs share one synchronous id so a new one replaces the previous one.

ICON=$1 TEXT=$2 VALUE=$3
ARGS=(-c osd -a "System OSD" -h string:x-canonical-private-synchronous:sys-osd)
[ -n "$VALUE" ] && ARGS+=(-h "int:value:$VALUE")

notify-send "${ARGS[@]}" "osd" "$ICON   $TEXT"
