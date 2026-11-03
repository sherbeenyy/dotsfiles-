#!/usr/bin/python3
"""Draws the live stats for the "telemetry" waybar look: icon, number, thin graph.

Once a second it renders one small PNG per stat, plus a .meta file holding that
stat's path and tooltip. Waybar's image modules read the .meta files.

Waybar starts one copy per bar. A lock keeps a single copy drawing; the others
wait on it and take over if the drawing copy goes away. Every copy exits with
its bar. Colors come from the active theme.
"""
import ctypes
import fcntl
import html
import json
import math
import os
import re
import shutil
import signal
import subprocess
import sys
import threading
import time
from collections import deque
from pathlib import Path

import cairo

OUT = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "waybar-telemetry"
THEME = Path.home() / ".config/themes/current/waybar-colors.css"
FONT = "Iosevka Nerd Font"
WIDTH, HEIGHT = 92, 24  # keep "size" in config equal to WIDTH
GRAPH_X = 48            # the graph takes the space from here to the right edge
SAMPLES = 22            # seconds of history in the graph
GPU_POLL_SECONDS = 5

C = {}


def load_theme():
    for name, value in re.findall(r"@define-color\s+([\w-]+)\s+#([0-9a-fA-F]{6})", THEME.read_text()):
        C[name] = tuple(int(value[i:i + 2], 16) / 255 for i in (0, 2, 4))


def status_color(pct):
    """The accent normally. Yellow or red only when something is actually high."""
    return C["red"] if pct >= 90 else C["yellow"] if pct >= 75 else C["accent"]


# ---------------------------------------------------------------- drawing
def line(ctx, values, color, alpha=1.0, fill=True):
    """Thin smooth line over a soft fade. Values run from 0 to 1."""
    values = list(values)
    if len(values) < 2:
        return
    top, bottom = 5.0, HEIGHT - 5.0
    step = (WIDTH - GRAPH_X - 2) / (SAMPLES - 1)
    start = WIDTH - 2 - step * (len(values) - 1)
    points = [(start + i * step, bottom - max(0.0, min(v, 1.0)) * (bottom - top))
              for i, v in enumerate(values)]

    def trace():
        ctx.move_to(*points[0])
        for (x0, y0), (x1, y1) in zip(points, points[1:]):
            middle = (x0 + x1) / 2
            ctx.curve_to(middle, y0, middle, y1, x1, y1)

    if fill:
        trace()
        ctx.line_to(points[-1][0], bottom)
        ctx.line_to(points[0][0], bottom)
        ctx.close_path()
        fade = cairo.LinearGradient(0, top, 0, bottom)
        fade.add_color_stop_rgba(0, *color, 0.30)
        fade.add_color_stop_rgba(1, *color, 0.0)
        ctx.set_source(fade)
        ctx.fill()
    trace()
    ctx.set_source_rgba(*color, alpha)
    ctx.set_line_width(1.4)
    ctx.set_line_cap(cairo.LINE_CAP_ROUND)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.stroke()


def tile(icon, value, color):
    """A new image with the icon and number in place. The caller adds the graph."""
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, WIDTH, HEIGHT)
    ctx = cairo.Context(surface)
    options = cairo.FontOptions()
    options.set_antialias(cairo.ANTIALIAS_GRAY)
    options.set_hint_style(cairo.HINT_STYLE_SLIGHT)
    options.set_hint_metrics(cairo.HINT_METRICS_ON)
    ctx.set_font_options(options)
    ctx.select_font_face(FONT, cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)

    baseline = HEIGHT / 2 + 4.5
    ctx.set_font_size(16)
    ctx.move_to(0, baseline + 1)
    ctx.set_source_rgba(*color, 1.0)
    ctx.show_text(icon)
    ctx.set_font_size(13)
    # Right-aligned, so the graph stays put as the number changes
    ctx.move_to(GRAPH_X - 4 - ctx.text_extents(value).x_advance, baseline)
    ctx.set_source_rgba(*C["fg"], 0.92)
    ctx.show_text(value)
    return surface, ctx


def publish(name, surface, tooltip):
    tmp = OUT / f".{name}.png"
    path = OUT / f"{name}.png"
    surface.write_to_png(str(tmp))
    os.replace(tmp, path)
    tmp = OUT / f".{name}.meta"
    tmp.write_text(f"{path}\n{tooltip.replace(chr(10), '&#10;')}\n")
    os.replace(tmp, OUT / f"{name}.meta")


def hide(name):
    """Waybar hides an image module whose file is missing."""
    (OUT / f"{name}.png").unlink(missing_ok=True)
    (OUT / f"{name}.meta").write_text(f"{OUT / (name + '.png')}\n\n")


def row(key, value):
    return f"<span alpha='60%'>{key:<10}</span> {value}"


def title(text):
    return f"<b>{html.escape(text)}</b>"


HINT = "<span alpha='60%'>{}</span>"


# ---------------------------------------------------------------- readers
def read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except OSError:
        return default


def read_int(path, default=0):
    try:
        return int(read(path))
    except ValueError:
        return default


def human(num):
    for suffix in ("", "K", "M", "G"):
        if num < 1024 or suffix == "G":
            return f"{num:.1f}{suffix}" if suffix and num < 10 else f"{num:.0f}{suffix}"
        num /= 1024


# ---------------------------------------------------------------- stats
class Cpu:
    def __init__(self):
        self.prev = {}
        self.history = deque(maxlen=SAMPLES)
        self.sensor = next((h for h in Path("/sys/class/hwmon").iterdir()
                            if read(h / "name") == "coretemp"), None)
        self.model = next((l.split(":", 1)[1].strip() for l in read("/proc/cpuinfo").splitlines()
                           if l.startswith("model name")), "CPU")

    def sample(self):
        usage = {}
        for text in read("/proc/stat").splitlines():
            if not text.startswith("cpu"):
                break
            name, *fields = text.split()
            fields = [int(x) for x in fields[:8]]
            idle, total = fields[3] + fields[4], sum(fields)
            old_idle, old_total = self.prev.get(name, (idle, total))
            delta = total - old_total
            usage[name] = 100 * (1 - (idle - old_idle) / delta) if delta else 0.0
            self.prev[name] = (idle, total)
        return usage

    def draw(self):
        usage = self.sample()
        total = usage.get("cpu", 0.0)
        cores = [v for k, v in usage.items() if k != "cpu"]
        temp = read_int(self.sensor / "temp1_input") // 1000 if self.sensor else 0
        # Square root, so everyday low usage still moves the line
        self.history.append(math.sqrt(total / 100))

        color = status_color(total)
        surface, ctx = tile("󰻠", f"{total:.0f}%", color)
        line(ctx, self.history, color)

        freqs = [read_int(p) for p in Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq")]
        busiest = sorted(enumerate(cores), key=lambda item: -item[1])[:3]
        publish("cpu", surface, "\n".join([
            title(self.model),
            "",
            row("Usage", f"{total:.0f}%  ({len(cores)} threads)"),
            row("Temp", f"{temp}°C"),
            row("Peak clock", f"{max(freqs, default=0) / 1e6:.2f} GHz"),
            row("Load", " ".join(read("/proc/loadavg").split()[:3])),
            row("Busiest", "  ".join(f"#{i} {v:.0f}%" for i, v in busiest)),
            "",
            HINT.format("Click for btop"),
        ]))


class Gpu:
    def __init__(self):
        self.history = deque(maxlen=SAMPLES)
        self.stats = None
        self.pci = next((d for d in Path("/sys/bus/pci/devices").iterdir()
                         if read(d / "vendor") == "0x10de" and read(d / "class").startswith("0x03")), None)
        if self.pci and shutil.which("nvidia-smi"):
            threading.Thread(target=self.poll, daemon=True).start()

    def active(self):
        return read(self.pci / "power/runtime_status") == "active"

    def poll(self):
        """Asks nvidia-smi only while the card is already awake, so it never wakes a sleeping card."""
        query = "name,utilization.gpu,memory.used,memory.total,temperature.gpu,power.draw"
        while True:
            stats = None
            if self.active():
                try:
                    out = subprocess.run(["nvidia-smi", f"--query-gpu={query}", "--format=csv,noheader,nounits"],
                                         capture_output=True, text=True, timeout=4).stdout
                    name, util, used, total, temp, power = [p.strip() for p in out.splitlines()[0].split(",")]
                    stats = {"name": name, "util": float(util), "used": float(used),
                             "total": float(total), "temp": float(temp), "power": power}
                except (subprocess.SubprocessError, OSError, IndexError, ValueError):
                    pass
            self.stats = stats
            time.sleep(GPU_POLL_SECONDS)

    def draw(self):
        stats = self.stats
        if not stats or not self.active():
            self.history.clear()
            hide("gpu")
            return
        self.history.append(math.sqrt(stats["util"] / 100))
        color = status_color(stats["util"])
        surface, ctx = tile("󰢮", f"{stats['util']:.0f}%", color)
        line(ctx, self.history, color)
        publish("gpu", surface, "\n".join([
            title(stats["name"]),
            "",
            row("Usage", f"{stats['util']:.0f}%"),
            row("VRAM", f"{stats['used'] / 1024:.1f} / {stats['total'] / 1024:.1f} GiB"),
            row("Temp", f"{stats['temp']:.0f}°C"),
            row("Power", f"{stats['power']} W"),
        ]))


class Memory:
    def __init__(self):
        self.history = deque(maxlen=SAMPLES)

    def draw(self):
        info = {}
        for text in read("/proc/meminfo").splitlines():
            key, value = text.split(":", 1)
            info[key] = int(value.split()[0]) * 1024
        gib = 1024 ** 3
        used = info["MemTotal"] - info["MemAvailable"]
        pct = 100 * used / info["MemTotal"]
        self.history.append(pct / 100)

        color = status_color(pct)
        surface, ctx = tile("󰍛", f"{used / gib:.1f}G", color)
        line(ctx, self.history, color)

        disk = os.statvfs("/")
        disk_total = disk.f_blocks * disk.f_frsize
        disk_used = disk_total - disk.f_bfree * disk.f_frsize
        publish("mem", surface, "\n".join([
            title("Memory and storage"),
            "",
            row("RAM", f"{used / gib:.1f} / {info['MemTotal'] / gib:.1f} GiB  ({pct:.0f}%)"),
            row("Cached", f"{info['Cached'] / gib:.1f} GiB"),
            row("Swap", f"{(info['SwapTotal'] - info['SwapFree']) / gib:.1f} / {info['SwapTotal'] / gib:.1f} GiB"),
            row("Disk /", f"{disk_used / gib:.0f} / {disk_total / gib:.0f} GiB"),
            "",
            HINT.format("Click for btop"),
        ]))


class Network:
    def __init__(self):
        self.prev = None
        self.down = deque(maxlen=SAMPLES)
        self.up = deque(maxlen=SAMPLES)

    @staticmethod
    def interface():
        for text in read("/proc/net/route").splitlines()[1:]:
            fields = text.split()
            if fields[1] == "00000000":
                return fields[0]
        return None

    @staticmethod
    def counters(interface):
        for text in read("/proc/net/dev").splitlines()[2:]:
            name, values = text.split(":", 1)
            if name.strip() == interface:
                values = values.split()
                return int(values[0]), int(values[8])
        return None

    @staticmethod
    def level(rate):
        """Log scale: 1 KB/s is the bottom of the graph and 100 MB/s the top."""
        return min(math.log10(rate / 1024) / 5, 1.0) if rate > 1024 else 0.0

    def draw(self):
        interface = self.interface()
        counters = self.counters(interface) if interface else None
        now = time.monotonic()
        down = up = 0.0
        if counters and self.prev and self.prev[0] == interface:
            elapsed = max(now - self.prev[2], 0.001)
            down = max(counters[0] - self.prev[1][0], 0) / elapsed
            up = max(counters[1] - self.prev[1][1], 0) / elapsed
        self.prev = (interface, counters, now) if counters else None
        self.down.append(self.level(down))
        self.up.append(self.level(up))

        surface, ctx = tile("󰁅", human(down) if interface else "off", C["accent"] if interface else C["red"])
        line(ctx, self.up, C["fg"], alpha=0.45, fill=False)
        line(ctx, self.down, C["accent"])
        rx, tx = counters if counters else (0, 0)
        publish("net", surface, "\n".join([
            title(interface or "No network"),
            "",
            row("Down", f"{human(down)}/s"),
            row("Up", f"{human(up)}/s"),
            row("Session", f"↓ {human(rx)}  ↑ {human(tx)}"),
            "",
            HINT.format("Click for network settings"),
        ]))


# ---------------------------------------------------------------- main
def main():
    try:  # stop when the bar that started this goes away
        ctypes.CDLL("libc.so.6").prctl(1, signal.SIGTERM)  # PR_SET_PDEATHSIG
    except OSError:
        pass
    parent = os.getppid()
    OUT.mkdir(parents=True, exist_ok=True)
    print(json.dumps({"text": ""}), flush=True)  # this helper shows nothing itself

    lock = open(OUT / ".lock", "w")
    while True:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if os.getppid() != parent:
                return
            time.sleep(1)

    load_theme()
    stats = [Cpu(), Gpu(), Memory(), Network()]
    next_tick = time.monotonic()
    while os.getppid() == parent:
        for stat in stats:
            try:
                stat.draw()
            except Exception as error:  # one bad sensor must not stop the others
                print(f"telemetryd: {type(stat).__name__}: {error}", file=sys.stderr, flush=True)
        next_tick += 1.0
        time.sleep(max(next_tick - time.monotonic(), 0.05))


if __name__ == "__main__":
    main()
