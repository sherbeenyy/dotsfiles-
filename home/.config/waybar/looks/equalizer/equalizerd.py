#!/usr/bin/python3
"""Draws the level bars for the "equalizer" waybar look.

The sensors, tooltips and startup all come from ../orbit/orbitd.py, so that file
has to stay. This one only changes how each stat is drawn and where it is saved.

CPU: one live bar per thread. GPU and network: bars scrolling through recent history.
RAM and battery: a rising wedge of bars, lit up to the current level.
"""
import math
import os
import sys
from collections import deque
from pathlib import Path

import cairo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "orbit"))
import orbitd  # noqa: E402

HEIGHT = 24
BARS_X = 48         # bars start here, after the icon and number
TOP, BOTTOM = 3, HEIGHT - 3
BAR, GAP = 2, 1
COLUMNS = 14
# Keep "size" in config equal to these widths
CPU_WIDTH, WIDTH = 110, 92
CPU_ICON, GPU_ICON, RAM_ICON = "󰻠", "󰢮", "󰍛"

C = orbitd.C
cores = []
gpu_history = deque([0.0] * COLUMNS, maxlen=COLUMNS)
down_history = deque([0.0] * COLUMNS, maxlen=COLUMNS)
up_history = deque([0.0] * COLUMNS, maxlen=COLUMNS)


class Cpu(orbitd.Cpu):
    """Also keeps each thread's usage for the bars."""

    def sample(self):
        usage = super().sample()
        cores[:] = [v for k, v in usage.items() if k != "cpu"]
        return usage


def meter():
    """Like an audio meter: accent for normal levels, then yellow, then red at the very top."""
    paint = cairo.LinearGradient(0, BOTTOM, 0, TOP)
    paint.add_color_stop_rgb(0, *C["accent"])
    paint.add_color_stop_rgb(0.62, *C["accent"])
    paint.add_color_stop_rgb(0.80, *C["yellow"])
    paint.add_color_stop_rgb(1, *C["red"])
    return paint


def columns(ctx, levels, paint):
    """One bar per level (0-1), each on a dim track."""
    span = BOTTOM - TOP
    for i, level in enumerate(levels):
        x = BARS_X + i * (BAR + GAP)
        ctx.rectangle(x, TOP, BAR, span)
        ctx.set_source_rgba(*C["fg"], 0.08)
        ctx.fill()
        height = max(1.0, min(level, 1.0) * span)
        ctx.rectangle(x, BOTTOM - height, BAR, height)
        ctx.set_source(paint)
        ctx.fill()


def wedge(ctx, pct, color):
    """Bars rising from short to tall, lit up to the level."""
    span = BOTTOM - TOP
    for i in range(COLUMNS):
        x = BARS_X + i * (BAR + GAP)
        height = span * (0.28 + 0.72 * i / (COLUMNS - 1))
        lit = (i + 1) / COLUMNS <= pct / 100 + 1 / (2 * COLUMNS)
        ctx.rectangle(x, BOTTOM - height, BAR, height)
        if lit:
            ctx.set_source_rgb(*color)
        else:
            ctx.set_source_rgba(*C["fg"], 0.12)
        ctx.fill()


def gauge(icon, value, pct, color):
    width = CPU_WIDTH if icon == CPU_ICON else WIDTH
    surface, ctx = orbitd.canvas(width)
    middle = HEIGHT / 2

    ctx.set_font_size(15)
    ctx.move_to(0, middle + 5.5)
    ctx.set_source_rgb(*color)
    ctx.show_text(icon)
    ctx.set_font_size(13)
    ctx.move_to(BARS_X - 4 - ctx.text_extents(value).x_advance, middle + 4.5)
    ctx.set_source_rgba(*C["fg"], 0.95)
    ctx.show_text(value)

    # Square root, so everyday low usage still shows up
    if icon == CPU_ICON:
        columns(ctx, [math.sqrt(v / 100) for v in cores], meter())
    elif icon == GPU_ICON:
        gpu_history.append(math.sqrt(pct / 100))
        columns(ctx, gpu_history, meter())
    else:
        wedge(ctx, pct, color)  # RAM and battery
    return surface


def net_tile(down, up, online):
    surface, ctx = orbitd.canvas(WIDTH)
    ctx.set_font_size(11)
    for arrow, rate, baseline, color in (("󰁅", down, 10.5, C["cyan"]), ("󰁝", up, 22, C["magenta"])):
        ctx.move_to(0, baseline)
        ctx.set_source_rgb(*color)
        ctx.show_text(arrow)
        text = orbitd.human(rate) if online else "--"
        ctx.move_to(14, baseline)
        ctx.set_source_rgba(*C["fg"], 0.95)
        ctx.show_text(text)

    def level(rate):  # log scale: 1 KB/s to 100 MB/s
        return min(math.log10(rate / 1024) / 5, 1.0) if rate > 1024 else 0.0

    down_history.append(level(down))
    up_history.append(level(up))
    # Download grows up from the center line, upload grows down from it
    middle = HEIGHT / 2
    reach = middle - TOP
    for i in range(COLUMNS):
        x = BARS_X + i * (BAR + GAP)
        for value, direction, color in ((down_history[i], -1, C["cyan"]), (up_history[i], 1, C["magenta"])):
            height = max(0.8, value * reach)
            ctx.rectangle(x, middle if direction > 0 else middle - height, BAR, height)
            ctx.set_source_rgba(*color, 1.0 if value else 0.25)
            ctx.fill()
    return surface


if __name__ == "__main__":
    orbitd.OUT = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "waybar-equalizer"
    orbitd.HEIGHT = HEIGHT
    orbitd.GAUGE_WIDTH = WIDTH
    orbitd.NET_WIDTH = WIDTH
    orbitd.Cpu = Cpu
    orbitd.gauge = gauge
    orbitd.net_tile = net_tile
    orbitd.main()
