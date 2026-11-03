#!/usr/bin/python3
"""Provides the stat icons and hover popups for the "telemetry" waybar look.

The bar shows icons and live percentages. Once a second this writes one JSON file per
stat, holding that, its popup text (numbers plus a small history graph) and a warning class
when the stat is high. Waybar's custom modules read those files.

Waybar starts one copy per bar. A lock keeps a single copy writing; the others wait
on it and take over if the writing copy goes away. Every copy exits with its bar.
Colors come from the active theme.
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

OUT = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "waybar-telemetry"
THEME = Path.home() / ".config/themes/current/waybar-colors.css"
SAMPLES = 30            # seconds of history in the popup graph
GPU_POLL_SECONDS = 5
BLOCKS = "▁▂▃▄▅▆▇█"

C = {}


def load_theme():
    C.update(re.findall(r"@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6})", THEME.read_text()))


# ---------------------------------------------------------------- output
def level_class(pct):
    return "critical" if pct >= 90 else "warning" if pct >= 75 else ""


def publish(name, icon, tooltip, css_class=""):
    tmp = OUT / f".{name}.json"
    tmp.write_text(json.dumps({"text": icon, "tooltip": tooltip, "class": css_class}) + "\n")
    os.replace(tmp, OUT / f"{name}.json")


def graph(values, color_name="accent"):
    """Values from 0 to 1 drawn as block characters, in a theme color."""
    bars = "".join(BLOCKS[min(int(max(v, 0.0) * len(BLOCKS)), len(BLOCKS) - 1)] for v in values)
    return f"<span foreground='{C[color_name]}'>{bars}</span>"


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

    def write(self):
        usage = self.sample()
        total = usage.get("cpu", 0.0)
        cores = [v for k, v in usage.items() if k != "cpu"]
        temp = read_int(self.sensor / "temp1_input") // 1000 if self.sensor else 0
        # Square root, so everyday low usage still shows up in the graph
        self.history.append(math.sqrt(total / 100))
        freqs = [read_int(p) for p in Path("/sys/devices/system/cpu").glob("cpu[0-9]*/cpufreq/scaling_cur_freq")]
        publish("cpu", f"CPU {total:2.0f}%", "\n".join([
            title(self.model),
            "",
            row("Usage", f"{total:.0f}%"),
            row("History", graph(self.history)),
            row("Threads", graph(math.sqrt(v / 100) for v in cores)),
            row("Temp", f"{temp}°C"),
            row("Peak clock", f"{max(freqs, default=0) / 1e6:.2f} GHz"),
            row("Load", " ".join(read("/proc/loadavg").split()[:3])),
            "",
            HINT.format("Click for btop"),
        ]), level_class(total))


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

    def write(self):
        stats = self.stats
        if not stats or not self.active():
            self.history.clear()
            publish("gpu", "", "")  # empty text hides the icon while the card sleeps
            return
        self.history.append(math.sqrt(stats["util"] / 100))
        publish("gpu", f"GPU {stats['util']:2.0f}%", "\n".join([
            title(stats["name"]),
            "",
            row("Usage", f"{stats['util']:.0f}%"),
            row("History", graph(self.history)),
            row("VRAM", f"{stats['used'] / 1024:.1f} / {stats['total'] / 1024:.1f} GiB"),
            row("Temp", f"{stats['temp']:.0f}°C"),
            row("Power", f"{stats['power']} W"),
        ]), level_class(stats["util"]))


class Memory:
    def __init__(self):
        self.history = deque(maxlen=SAMPLES)

    def write(self):
        info = {}
        for text in read("/proc/meminfo").splitlines():
            key, value = text.split(":", 1)
            info[key] = int(value.split()[0]) * 1024
        gib = 1024 ** 3
        used = info["MemTotal"] - info["MemAvailable"]
        pct = 100 * used / info["MemTotal"]
        self.history.append(pct / 100)
        disk = os.statvfs("/")
        disk_total = disk.f_blocks * disk.f_frsize
        disk_used = disk_total - disk.f_bfree * disk.f_frsize
        publish("mem", f"MEM {pct:2.0f}%", "\n".join([
            title("Memory and storage"),
            "",
            row("RAM", f"{used / gib:.1f} / {info['MemTotal'] / gib:.1f} GiB  ({pct:.0f}%)"),
            row("History", graph(self.history)),
            row("Cached", f"{info['Cached'] / gib:.1f} GiB"),
            row("Swap", f"{(info['SwapTotal'] - info['SwapFree']) / gib:.1f} / {info['SwapTotal'] / gib:.1f} GiB"),
            row("Disk /", f"{disk_used / gib:.0f} / {disk_total / gib:.0f} GiB"),
            "",
            HINT.format("Click for btop"),
        ]), level_class(pct))


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

    def write(self):
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
        rx, tx = counters if counters else (0, 0)
        publish("net", f"󰁅 {human(down) if interface else 'off':>4}", "\n".join([
            title(interface or "No network"),
            "",
            row("Down", f"{human(down)}/s"),
            row("History", graph(self.down)),
            row("Up", f"{human(up)}/s"),
            row("History", graph(self.up, "magenta")),
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
                stat.write()
            except Exception as error:  # one bad sensor must not stop the others
                print(f"telemetryd: {type(stat).__name__}: {error}", file=sys.stderr, flush=True)
        next_tick += 1.0
        time.sleep(max(next_tick - time.monotonic(), 0.05))


if __name__ == "__main__":
    main()
