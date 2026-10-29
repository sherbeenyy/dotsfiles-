#!/usr/bin/env bash
# Display control for sway (laptop panel + one external monitor).
#
#   display.sh menu                         fuzzel menu with every option
#   display.sh extend right|left|above|below
#   display.sh mirror                       primary is shown on the other screen (needs wl-mirror)
#   display.sh laptop | external            use only one screen
#   display.sh primary laptop|external      workspaces 1-5 go on primary, 6-10 on secondary
#   display.sh swap                         swap primary and secondary
#   display.sh refresh 144|60               laptop panel refresh rate
#   display.sh resolution [output]          control center: resolution / refresh / scale per screen
#   display.sh focus-other | window-other | workspace-other
#   display.sh swap-workspaces             trade the shown workspaces between the two screens
#   display.sh apply                        re-apply saved layout
#   display.sh watch                        apply now and again on every plug/unplug
#
# Choices are saved in ~/.config/sway/display.state and restored on hotplug/login.
# Per-monitor resolution/scale overrides live in display-modes.state, keyed by
# make/model/serial so they follow the monitor even if its output name changes.

STATE="$HOME/.config/sway/display.state"
WS_CONF="$HOME/.config/sway/display-workspaces.conf"  # generated
MODES_STATE="$HOME/.config/sway/display-modes.state"   # key<TAB>mode<TAB>scale
MODE=extend SIDE=right PRIMARY=laptop LAPTOP_HZ=max
[ -f "$STATE" ] && . "$STATE"

save() { printf 'MODE=%s\nSIDE=%s\nPRIMARY=%s\nLAPTOP_HZ=%s\n' "$MODE" "$SIDE" "$PRIMARY" "$LAPTOP_HZ" > "$STATE"; }
notify() { notify-send -a Display -t 2500 "Display" "$1"; }

OUTPUTS=$(swaymsg -t get_outputs -r)
LAPTOP=$(jq -r '[.[] | select(.name | test("^(eDP|LVDS|DSI)"))][0].name // empty' <<<"$OUTPUTS")
EXTERNAL=$(jq -r '[.[] | select(.name | test("^(eDP|LVDS|DSI)") | not)][0].name // empty' <<<"$OUTPUTS")

# Highest resolution, then highest refresh ("60" caps refresh at ~60Hz)
best_mode() {
    jq -r --arg o "$1" --arg hz "$2" '
        .[] | select(.name == $o) | .modes
        | (if $hz == "60" then map(select(.refresh < 61000)) else . end)
        | max_by([.width * .height, .refresh])
        | if . == null then empty else "\(.width)x\(.height)@\(.refresh / 1000)Hz" end' <<<"$OUTPUTS"
}

out_key() { jq -r --arg o "$1" '.[] | select(.name == $o) | "\(.make) \(.model) \(.serial)"' <<<"$OUTPUTS"; }

# Saved override for an output: field 2 = mode, 3 = scale
saved() { [ -n "$1" ] && awk -F'\t' -v k="$(out_key "$1")" -v f="$2" '$1 == k { print $f }' "$MODES_STATE" 2>/dev/null; }

# set_saved <output> <mode> <scale>; both empty removes the override
set_saved() {
    local k
    k=$(out_key "$1")
    { grep -vF -- "$k"$'\t' "$MODES_STATE" 2>/dev/null; [ -n "$2$3" ] && printf '%s\t%s\t%s\n' "$k" "$2" "$3"; } > "$MODES_STATE.tmp"
    mv "$MODES_STATE.tmp" "$MODES_STATE"
}

mode_for() { local m; m=$(saved "$1" 2); echo "${m:-$(best_mode "$1" "$2")}"; }
scale_for() { local s; s=$(saved "$1" 3); echo "${s:-1}"; }

# Logical (scaled) size of a mode, as "W H"
logical() { local m=${1%%@*}; awk -v w="${m%x*}" -v h="${m#*x}" -v s="$2" 'BEGIN { printf "%d %d", w / s, h / s }'; }

primary_output() { [ "$PRIMARY" = external ] && [ -n "$EXTERNAL" ] && echo "$EXTERNAL" || echo "$LAPTOP"; }
secondary_output() { [ "$(primary_output)" = "$LAPTOP" ] && echo "$EXTERNAL" || echo "$LAPTOP"; }

# Workspaces 1-5 belong to primary and 6-10 to secondary; existing ones are moved over.
assign_workspaces() {
    local p s cmds="" n
    p=$(primary_output) s=$(secondary_output)
    case "$MODE" in
        laptop) p=$LAPTOP s= ;;
        external) p=$EXTERNAL s= ;;
        mirror) s= ;;
    esac
    [ -z "$EXTERNAL" ] && p=$LAPTOP s=

    # Assignments go in an included file + reload: runtime "workspace N output"
    # commands stack up instead of replacing, so sway would keep old outputs.
    # One output per workspace, or sway auto-creates primary's workspaces on secondary.
    for n in 1 2 3 4 5 6 7 8 9 10; do
        if [ $n -le 5 ] || [ -z "$s" ]; then cmds+="workspace $n output $p"$'\n'; else cmds+="workspace $n output $s"$'\n'; fi
    done
    if [ "$cmds" != "$(cat "$WS_CONF" 2>/dev/null)"$'\n' ]; then
        printf '%s' "$cmds" > "$WS_CONF"
        swaymsg reload >/dev/null
        sleep 0.3
    fi

    local cur num name out want
    cur=$(swaymsg -t get_workspaces -r | jq -r '.[] | select(.focused).name')
    while IFS=$'\t' read -r num name out; do
        [ "$num" -ge 1 ] && [ "$num" -le 10 ] || continue
        if [ "$num" -le 5 ] || [ -z "$s" ]; then want=$p; else want=$s; fi
        [ "$out" != "$want" ] && swaymsg "workspace \"$name\"; move workspace to output $want" >/dev/null
    done < <(swaymsg -t get_workspaces -r | jq -r '.[] | "\(.num)\t\(.name)\t\(.output)"')
    swaymsg "workspace \"$cur\"" >/dev/null

    # XWayland apps/games open on the primary screen
    command -v xrandr >/dev/null && xrandr --output "$p" --primary 2>/dev/null
}

start_mirror() {
    local src dst
    src=$(primary_output) dst=$(secondary_output)
    if ! command -v wl-mirror >/dev/null; then
        notify "Mirror needs wl-mirror: sudo apt install wl-mirror"
        return
    fi
    swaymsg "focus output $dst" >/dev/null
    wl-mirror --fullscreen-output "$dst" "$src" >/dev/null 2>&1 &
    disown
    sleep 0.5
    swaymsg "focus output $src" >/dev/null
}

apply() {
    pkill -x wl-mirror 2>/dev/null
    local lm em ls es lw lh ew eh lp ep
    lm=$(mode_for "$LAPTOP" "$LAPTOP_HZ") ls=$(scale_for "$LAPTOP")

    if [ -z "$EXTERNAL" ]; then
        swaymsg "output $LAPTOP enable ${lm:+mode $lm} scale $ls pos 0 0" >/dev/null
        assign_workspaces
        return
    fi

    em=$(mode_for "$EXTERNAL" max) es=$(scale_for "$EXTERNAL")
    read -r lw lh <<<"$(logical "$lm" "$ls")"
    read -r ew eh <<<"$(logical "$em" "$es")"

    case "$MODE" in
        extend|mirror)
            local side=$SIDE
            [ "$MODE" = mirror ] && side=right
            case "$side" in
                right) lp="0 0" ep="$lw 0" ;;
                left)  lp="$ew 0" ep="0 0" ;;
                above) lp="0 $eh" ep="0 0" ;;
                below) lp="0 0" ep="0 $lh" ;;
            esac
            swaymsg "output $LAPTOP enable ${lm:+mode $lm} scale $ls pos $lp; output $EXTERNAL enable ${em:+mode $em} scale $es pos $ep" >/dev/null
            ;;
        laptop)
            swaymsg "output $LAPTOP enable ${lm:+mode $lm} scale $ls pos 0 0; output $EXTERNAL disable" >/dev/null ;;
        external)
            swaymsg "output $EXTERNAL enable ${em:+mode $em} scale $es pos 0 0; output $LAPTOP disable" >/dev/null ;;
    esac

    assign_workspaces
    [ "$MODE" = mirror ] && start_mirror
}

# Re-apply whenever the set of connected outputs changes (plug/unplug)
watch() {
    local last now
    apply
    last=$(jq -r '[.[].name] | sort | join(",")' <<<"$OUTPUTS")
    swaymsg -t subscribe -m '["output"]' | while read -r _; do
        now=$(swaymsg -t get_outputs -r | jq -r '[.[].name] | sort | join(",")')
        if [ "$now" != "$last" ]; then
            last=$now
            sleep 1
            "$0" apply
        fi
    done
}

other_output() { swaymsg -t get_outputs -r | jq -r '[.[] | select(.active and (.focused | not))][0].name // empty'; }

# Trade the workspaces shown on the two screens; run again to trade them back.
# Focus stays on the same screen, which now shows the other workspace.
swap_workspaces() {
    local here there a b
    here=$(swaymsg -t get_outputs -r | jq -r '.[] | select(.focused) | .name')
    there=$(other_output)
    [ -n "$here" ] && [ -n "$there" ] || return
    a=$(swaymsg -t get_outputs -r | jq -r --arg o "$here" '.[] | select(.name == $o) | .current_workspace')
    b=$(swaymsg -t get_outputs -r | jq -r --arg o "$there" '.[] | select(.name == $o) | .current_workspace')
    # Moving is repeated after showing each one, since an empty workspace that
    # gets hidden mid-swap is recreated on its assigned screen
    swaymsg "workspace --no-auto-back-and-forth \"$a\", move workspace to output $there, \
             workspace --no-auto-back-and-forth \"$b\", move workspace to output $here, \
             workspace --no-auto-back-and-forth \"$a\", move workspace to output $there, \
             workspace --no-auto-back-and-forth \"$b\", move workspace to output $here" >/dev/null
}

# ---------- Resolution control center ----------

describe() {
    jq -r --arg o "$1" '.[] | select(.name == $o) | "\(.current_mode.width)x\(.current_mode.height) @ \(.current_mode.refresh / 1000 | round)Hz   ×\(.scale)"' <<<"$OUTPUTS"
}

# Ask to keep the new settings; no answer within 15s counts as "revert"
confirm() {
    local c
    c=$(printf '%s\n' "󰄬   Keep these settings" "󰕍   Revert" | timeout 15 fuzzel -d -p "Keep? reverts in 15s   " -w 40 -l 2)
    [[ $c == *Keep* ]]
}

# try_set <output> <mode> <scale>: apply, then keep or roll back
try_set() {
    local out=$1 old_mode old_scale
    old_mode=$(saved "$out" 2) old_scale=$(saved "$out" 3)
    set_saved "$out" "$2" "$3"
    apply
    if ! confirm; then
        set_saved "$out" "$old_mode" "$old_scale"
        apply
        notify "Display settings reverted"
    fi
}

# Show "label<TAB>value" lines in fuzzel, print the picked value
pick() {
    local prompt=$1 lines idx
    lines=$(cat)
    idx=$(cut -f1 <<<"$lines" | fuzzel -d --index -p "$prompt" -w 36 -l 10) || return 1
    sed -n "$((idx + 1))p" <<<"$lines" | cut -f2
}

# One screen's menu; returns 1 when closed so resolution() stops looping
screen_menu() {
    local out=$1 name w h hz scale choice new
    OUTPUTS=$(swaymsg -t get_outputs -r)
    [ "$out" = "$LAPTOP" ] && name="󰌢   Laptop" || name="󰍹   External"
    read -r w h hz scale <<<"$(jq -r --arg o "$out" '.[] | select(.name == $o) | "\(.current_mode.width) \(.current_mode.height) \(.current_mode.refresh) \(.scale)"' <<<"$OUTPUTS")"

    choice=$(printf '%s\n' \
        "󰩨   Resolution      ${w}x${h}" \
        "󰑓   Refresh rate    $(( (hz + 500) / 1000 )) Hz" \
        "󰁌   Scale           ×$scale" \
        "󰑐   Reset to automatic" \
        | fuzzel -d -p "$name   " -w 40 -l 4) || return 1

    case "$choice" in
        *Resolution*)
            # Each resolution at its highest refresh rate, largest first
            new=$(jq -r --arg o "$out" --arg cur "${w}x${h}" '.[] | select(.name == $o) | .modes
                | group_by("\(.width)x\(.height)") | map(max_by(.refresh)) | sort_by(-(.width * .height)) | .[]
                | "\(if "\(.width)x\(.height)" == $cur then "● " else "   " end)\(.width)x\(.height)\t\(.width)x\(.height)@\(.refresh / 1000)Hz"' <<<"$OUTPUTS" \
                | pick "󰩨   ") || return 0
            try_set "$out" "$new" "$(saved "$out" 3)" ;;
        *Refresh*)
            new=$(jq -r --arg o "$out" --argjson w "$w" --argjson h "$h" --argjson hz "$hz" '.[] | select(.name == $o) | .modes
                | map(select(.width == $w and .height == $h)) | unique_by(.refresh) | sort_by(-.refresh) | .[]
                | "\(if .refresh == $hz then "● " else "   " end)\(.refresh / 10 | round / 100) Hz\t\(.width)x\(.height)@\(.refresh / 1000)Hz"' <<<"$OUTPUTS" \
                | pick "󰑓   ") || return 0
            try_set "$out" "$new" "$(saved "$out" 3)" ;;
        *Scale*)
            new=$(for s in 1 1.25 1.5 1.75 2; do
                    awk -v s="$s" -v c="$scale" 'BEGIN { printf "%s×%s\t%s\n", (s + 0 == c + 0 ? "● " : "   "), s, s }'
                  done | pick "󰁌   ") || return 0
            try_set "$out" "$(saved "$out" 2)" "$new" ;;
        *Reset*)
            try_set "$out" "" "" ;;
    esac
}

resolution() {
    local out=$1 c
    if [ -z "$out" ]; then
        if [ -z "$EXTERNAL" ] || [ "$MODE" = laptop ]; then
            out=$LAPTOP
        elif [ "$MODE" = external ]; then
            out=$EXTERNAL
        else
            c=$(printf '%s\n' "󰌢   Laptop       $(describe "$LAPTOP")" "󰍹   External     $(describe "$EXTERNAL")" \
                | fuzzel -d -p "󰍹   " -w 46 -l 2) || exit 0
            [[ $c == *Laptop* ]] && out=$LAPTOP || out=$EXTERNAL
        fi
    fi
    while screen_menu "$out"; do :; done
}

menu() {
    [ -z "$EXTERNAL" ] && { notify "No external display detected ($LAPTOP only)."; exit 0; }
    local dot cur_hz
    dot() { [ "$1" = "$2" ] && echo "● " || echo "   "; }
    [ "$LAPTOP_HZ" = 60 ] && cur_hz="60Hz" || cur_hz="max (144Hz)"
    local choice
    choice=$(printf '%s\n' \
        "$(dot "$MODE$SIDE" extendright)Extend — external on the RIGHT" \
        "$(dot "$MODE$SIDE" extendleft)Extend — external on the LEFT" \
        "$(dot "$MODE$SIDE" extendabove)Extend — external ABOVE" \
        "$(dot "$MODE$SIDE" extendbelow)Extend — external BELOW" \
        "$(dot "$MODE" mirror)Mirror (duplicate primary)" \
        "$(dot "$MODE" laptop)Laptop screen only" \
        "$(dot "$MODE" external)External screen only" \
        "$(dot "$PRIMARY" laptop)Primary: laptop ($LAPTOP)" \
        "$(dot "$PRIMARY" external)Primary: external ($EXTERNAL)" \
        "   Laptop refresh: $cur_hz (toggle)" \
        "   Resolution & scale…" \
        "   Re-detect / re-apply" \
        | fuzzel -d -p "󰍹   " -w 45 -l 12)

    case "$choice" in
        *"on the RIGHT"*) MODE=extend SIDE=right ;;
        *"on the LEFT"*)  MODE=extend SIDE=left ;;
        *ABOVE*)          MODE=extend SIDE=above ;;
        *BELOW*)          MODE=extend SIDE=below ;;
        *Mirror*)         MODE=mirror ;;
        *"Laptop screen only"*)   MODE=laptop ;;
        *"External screen only"*) MODE=external ;;
        *"Primary: laptop"*)   PRIMARY=laptop ;;
        *"Primary: external"*) PRIMARY=external ;;
        *"Laptop refresh"*) [ "$LAPTOP_HZ" = 60 ] && LAPTOP_HZ=max || LAPTOP_HZ=60; set_saved "$LAPTOP" "" "$(saved "$LAPTOP" 3)" ;;
        *"Resolution & scale"*) resolution; exit 0 ;;
        *"Re-detect"*) ;;
        *) exit 0 ;;
    esac
    save
    apply
}

case "$1" in
    menu)     menu ;;
    resolution) resolution "$2" ;;
    apply)    apply ;;
    watch)    watch ;;
    extend)   MODE=extend SIDE=${2:-right}; save; apply; notify "Extend: external $SIDE" ;;
    mirror)   MODE=mirror; save; apply ;;
    laptop)   MODE=laptop; save; apply; notify "Laptop screen only" ;;
    external) MODE=external; save; apply; notify "External screen only" ;;
    primary)  PRIMARY=${2:-laptop}; save; apply; notify "Primary: $PRIMARY" ;;
    swap)     [ "$PRIMARY" = laptop ] && PRIMARY=external || PRIMARY=laptop; save; apply; notify "Primary: $PRIMARY" ;;
    refresh)  [ "$2" = 60 ] && LAPTOP_HZ=60 || LAPTOP_HZ=max; save; set_saved "$LAPTOP" "" "$(saved "$LAPTOP" 3)"; apply; notify "Laptop refresh: $LAPTOP_HZ" ;;
    focus-other)     o=$(other_output); [ -n "$o" ] && swaymsg "focus output $o" ;;
    window-other)    o=$(other_output); [ -n "$o" ] && swaymsg "move container to output $o, focus output $o" ;;
    workspace-other) o=$(other_output); [ -n "$o" ] && swaymsg "move workspace to output $o" ;;
    swap-workspaces) swap_workspaces ;;
    *) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//' ;;
esac
