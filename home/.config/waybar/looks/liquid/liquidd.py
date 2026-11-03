#!/usr/bin/python3
"""Draws the liquid tiles for the "liquid" waybar look.

The sensors, tooltips and startup all come from ../orbit/orbitd.py, so that file
has to stay. This one only changes how each stat is drawn and where it is saved.
"""
import math
import os
import sys
import time
from pathlib import Path

import cairo

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "orbit"))
import orbitd  # noqa: E402

WIDTH, HEIGHT = 68, 30  # keep "size" in config equal to WIDTH
C = orbitd.C


def base():
    """A rounded dark tile. The bar itself is see-through, so this is its background."""
    surface, ctx = orbitd.canvas(WIDTH)
    radius = 10
    ctx.new_sub_path()
    for x, y, start in ((WIDTH - radius, radius, -0.5), (WIDTH - radius, HEIGHT - radius, 0),
                        (radius, HEIGHT - radius, 0.5), (radius, radius, 1)):
        ctx.arc(x, y, radius, start * math.pi, (start + 0.5) * math.pi)
    ctx.close_path()
    ctx.clip()
    ctx.set_source_rgba(*C["bg"], 0.92)
    ctx.paint()
    return surface, ctx


def liquid(ctx, pct, color):
    """Liquid rising from the bottom of the tile, with a slow wave on its surface."""
    if pct < 1:
        return
    level = HEIGHT * (1 - min(pct, 100) / 100)
    phase = time.monotonic() * 0.9
    ctx.move_to(0, HEIGHT)
    for x in range(WIDTH + 1):
        ctx.line_to(x, level + math.sin(x / WIDTH * 2 * math.pi + phase) * 1.2)
    ctx.line_to(WIDTH, HEIGHT)
    ctx.close_path()
    fade = cairo.LinearGradient(0, level, 0, HEIGHT)
    fade.add_color_stop_rgba(0, *color, 0.70)
    fade.add_color_stop_rgba(1, *color, 0.28)
    ctx.set_source(fade)
    ctx.fill()


def write(ctx, text, x, baseline, size, right=False):
    """Text with a soft dark edge, so it stays readable on top of the liquid."""
    ctx.set_font_size(size)
    if right:
        x -= ctx.text_extents(text).x_advance
    ctx.move_to(x, baseline)
    ctx.text_path(text)
    ctx.set_source_rgba(*C["bg"], 0.55)
    ctx.set_line_width(2.2)
    ctx.stroke()
    ctx.move_to(x, baseline)
    ctx.set_source_rgba(*C["fg"], 0.97)
    ctx.show_text(text)


def gauge(icon, value, pct, color):
    surface, ctx = base()
    liquid(ctx, pct, color)
    write(ctx, icon, 8, HEIGHT / 2 + 5.5, 15)
    write(ctx, value, WIDTH - 8, HEIGHT / 2 + 4.5, 13, right=True)
    return surface


def net_tile(down, up, online):
    surface, ctx = base()
    # 1 KB/s is an empty tile and 100 MB/s a full one
    liquid(ctx, min(math.log10(down / 1024) * 20, 100) if down > 1024 else 0, C["cyan"])
    for arrow, rate, baseline in (("↓", down, 13), ("↑", up, 25.5)):
        write(ctx, arrow, 8, baseline, 11)
        write(ctx, orbitd.human(rate) if online else "--", WIDTH - 8, baseline, 11, right=True)
    return surface


if __name__ == "__main__":
    orbitd.OUT = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "waybar-liquid"
    orbitd.HEIGHT = HEIGHT
    orbitd.GAUGE_WIDTH = orbitd.NET_WIDTH = WIDTH
    orbitd.gauge = gauge
    orbitd.net_tile = net_tile
    orbitd.main()
