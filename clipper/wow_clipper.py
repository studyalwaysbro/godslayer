#!/usr/bin/env python3
"""Godslayer clipper: keeps a clip of every hunt, with the song and the announcer in it.

While the game runs, GPU Screen Recorder holds the last few minutes in memory and writes
nothing. When a hunt ends, Godslayer draws its clip mark and takes a screenshot (Clip.lua);
this program sees the screenshot land, reads the mark, asks the recorder for the stretch that
matters and cuts it down to the hunt. Any other screenshot keeps the last minute.

Nothing here touches the game: it reads the Screenshots folder and the process list.

  wow_clipper.py run | setup | status | list | keep <clip> | short <clip> [zoom|mid|fit]
"""
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

CONFIG = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "wow-clipper" / "config.json"
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp")) / "wow-clipper"
RAW, STATE, LOG = RUNTIME / "raw", RUNTIME / "state.json", RUNTIME / "recorder.log"
FLATPAK = "com.dec05eba.gpu_screen_recorder"

DEFAULTS = {
    "wow_dir": "",                # the folder holding Screenshots/ (…/World of Warcraft/_classic_beta_)
    "process": "WowB.exe",
    "library": str(Path.home() / "Videos" / "wow-clips"),
    "library_mount": "",          # when set, the library is only used while this is a mounted drive
    "fallback_library": str(Path.home() / "Videos" / "wow-clips"),
    "cap_gb": 60,                 # oldest clips outside keep/ are deleted past this
    "fallback_cap_gb": 15,
    "min_free_gb": 50,            # never write to a drive with less free than this
    "buffer_seconds": 600,        # held in memory, not on disk
    "fps": 60,
    "codec": "hevc",
    "bitrate_kbps": 20000,
    "audio": "game",              # game = the game's own sound only; desktop = everything you hear
    "audio_match": "wow|warcraft",
    "lead_in": 25,                # seconds kept before the first kill
    "tail": 10,                   # seconds kept after the last kill
    "card_seconds": 8,            # the hunt card, cut onto the end of a hunt that ran out
    "peak_lead": 12, "peak_tail": 6,
    "manual_seconds": 60,         # /godslayer clip
    "screenshot_seconds": 60,     # any other screenshot; 0 = ignore them
    "min_kills": 1,
    "notify": True,
}

# Hype.lua's ladder, by place. test_clipper.py checks this against the addon.
LADDER = ["FIRST BLOOD", "MEGA KILL", "ULTRA KILL", "GODLIKE", "UNSTOPPABLE", "BEYOND GODLIKE", "GODSLAYER",
          "TWENTY KILLS", "TWENTY FIVE", "THIRTY", "FORTY", "FIFTY"]
GRADES = ["", "C", "B", "A", "S", "S+"]
KINDS = {1: "quiet", 2: "died", 3: "manual"}
COLS, ROWS, MAGIC = 32, 4, 0xAC
# what each save signal keeps, shortest first (SIGRTMIN+n; plain SIGUSR1 keeps the whole buffer)
SAVES = [(10, 1), (30, 2), (60, 3), (300, 4), (600, 5), (1800, 6)]


def log(*parts):
    print(datetime.now().strftime("%H:%M:%S"), *parts, flush=True)


def load_config():
    cfg = dict(DEFAULTS)
    if CONFIG.exists():
        cfg.update(json.loads(CONFIG.read_text()))
    return cfg


# ---------------------------------------------------------------- the mark

def crc8(data):
    crc = 0
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = ((crc << 1) ^ 0x07) & 0xFF if crc & 0x80 else (crc << 1) & 0xFF
    return crc


def parse_mark(b):
    """16 bytes from the squares -> a dict, or None when they are not a mark."""
    if len(b) != 16 or b[0] != MAGIC or crc8(b[:15]) != b[15]:
        return None
    version, kind = b[1] >> 4, b[1] & 15
    if version != 1 or kind not in KINDS or b[9] >= len(GRADES) or b[7] > len(LADDER):
        return None
    return {
        "kind": KINDS[kind], "kills": b[2], "seconds": b[3] * 256 + b[4], "since": b[5] * 256 + b[6],
        "rung": LADDER[b[7] - 1] if b[7] else "", "run": b[8], "grade": GRADES[b[9]], "points": b[10],
        "pretend": bool(b[11] & 1), "record": bool(b[11] & 2), "king": bool(b[11] & 4), "flawless": bool(b[11] & 8),
        "peak": b[12] * 256 + b[13], "serial": b[14],
    }


def decode_mark(image_path):
    """Read the clip mark out of a screenshot's top left corner. None when there is none."""
    import numpy as np
    from PIL import Image
    with Image.open(image_path) as im:
        a = np.asarray(im.convert("L").crop((0, 0, min(im.width, 640), min(im.height, 140))))
    # the squares are meant to be 8 pixels; an odd interface scale may land them a little off
    sizes = [8.0] + [s / 4 for s in range(16, 73) if s != 32]
    cols, rows = np.arange(COLS) + 1.5, np.arange(ROWS) + 1.5
    edge = np.arange(COLS + 2) + 0.5
    for cell in sizes:
        if (COLS + 2) * cell > a.shape[1] or (ROWS + 2) * cell > a.shape[0]:
            continue
        for oy in (0, -1, 1, -2, 2):
            for ox in (0, -1, 1, -2, 2):
                xs, ys = (cols * cell + ox).astype(int), (rows * cell + oy).astype(int)
                if xs.min() < 0 or ys.min() < 0:
                    continue
                bits = a[np.ix_(ys, xs)] > 128
                if not (bits[0, 0] and not bits[0, 1] and bits[0, 2]):  # 0xAC opens 1 0 1
                    continue
                mark = parse_mark(bytes(np.packbits(bits.flatten())))
                if not mark:
                    continue
                # the border is black all the way round, which a lucky photograph is not
                ex = np.clip((edge * cell + ox).astype(int), 0, a.shape[1] - 1)
                top, bottom = int(max(0, 0.5 * cell + oy)), int((ROWS + 1.5) * cell + oy)
                if a[top, ex].max() < 90 and a[bottom, ex].max() < 90:
                    return mark
    return None


# ---------------------------------------------------------------- the library

def library(cfg):
    """(folder, cap in GB) to write to now, or (None, why)."""
    mount = cfg["library_mount"]
    choices = []
    if not mount or os.path.ismount(mount):
        choices.append((Path(cfg["library"]), cfg["cap_gb"]))
    choices.append((Path(cfg["fallback_library"]), cfg["fallback_cap_gb"]))
    why = "no library"
    for folder, cap in choices:
        try:
            folder.mkdir(parents=True, exist_ok=True)
            free = shutil.disk_usage(folder).free / 1e9
        except OSError as e:
            why = f"{folder}: {e}"
            continue
        if free < cfg["min_free_gb"]:
            why = f"{folder}: only {free:.0f} GB free, floor is {cfg['min_free_gb']}"
            continue
        return folder, cap
    return None, why


def clips(folder, kept=True):
    out = []
    for p in folder.rglob("*.mp4"):
        if kept or "keep" not in p.relative_to(folder).parts:
            out.append(p)
    return sorted(out, key=lambda p: p.stat().st_mtime)


def usage_gb(folder):
    return sum(p.stat().st_size for p in folder.rglob("*") if p.is_file()) / 1e9


def prune(folder, cap):
    """Delete the oldest clips outside keep/ until the library is under its cap."""
    over = usage_gb(folder) - cap
    for p in clips(folder, kept=False):
        if over <= 0:
            break
        over -= p.stat().st_size / 1e9
        log("pruned", p.name)
        p.unlink()
        p.with_suffix(".jpg").unlink(missing_ok=True)
    for d in sorted((d for d in folder.rglob("*") if d.is_dir()), reverse=True):
        if d.name != "keep" and not any(d.iterdir()):
            d.rmdir()


# ---------------------------------------------------------------- the recorder

def recorder_pid():
    """The recorder we started: found by the raw folder on its command line, never by name alone."""
    for p in Path("/proc").iterdir():
        if not p.name.isdigit():
            continue
        try:
            if (p / "comm").read_text().strip() != "gpu-screen-reco":
                continue
            if str(RAW).encode() in (p / "cmdline").read_bytes():
                return int(p.name)
        except OSError:
            pass
    return None


def game_running(cfg):
    for p in Path("/proc").iterdir():
        if p.name.isdigit():
            try:
                if (p / "comm").read_text().strip() == cfg["process"][:15]:
                    return True
            except OSError:
                pass
    return False


def gsr(*args):
    return ["flatpak", "run", f"--filesystem=xdg-run/{RUNTIME.name}", "--command=gpu-screen-recorder", FLATPAK, *args]


def game_audio(cfg):
    if cfg["audio"] != "game":
        return "default_output"
    out = subprocess.run(gsr("--list-application-audio"), capture_output=True, text=True, timeout=30).stdout
    for name in out.splitlines():
        if re.search(cfg["audio_match"], name, re.I):
            return "app:" + name.strip()
    return None


def start_recorder(cfg, audio, seconds=None):
    RAW.mkdir(parents=True, exist_ok=True)
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    cmd = gsr("-w", "portal", "-restore-portal-session", "yes",
              "-portal-session-token-filepath", str(CONFIG.parent / "portal_token"),
              "-f", str(cfg["fps"]), "-fm", "cfr", "-k", cfg["codec"], "-bm", "cbr", "-q", str(cfg["bitrate_kbps"]),
              "-ac", "aac", "-a", audio, "-c", "mp4", "-r", str(seconds or cfg["buffer_seconds"]),
              "-replay-storage", "ram", "-o", str(RAW))
    log("recorder:", " ".join(cmd[4:]))
    return subprocess.Popen(cmd, stdout=open(LOG, "ab"), stderr=subprocess.STDOUT, start_new_session=True)


def stop_recorder(proc):
    pid = recorder_pid()
    if pid:
        os.kill(pid, signal.SIGINT)  # in replay mode this stops without saving
    if proc:
        try:
            proc.wait(timeout=8)
        except subprocess.TimeoutExpired:
            proc.terminate()
    # a recorder still waiting on the screen picker ignores the polite signal
    for _ in range(20):
        if not recorder_pid():
            break
        time.sleep(0.25)
    pid = recorder_pid()
    if pid:
        os.kill(pid, signal.SIGKILL)
    for p in RAW.glob("*"):
        p.unlink()


def save_replay(seconds, buffer_seconds):
    """Ask the recorder for the last `seconds`; returns (file, time asked) once it is written."""
    pid = recorder_pid()
    if not pid:
        return None, 0
    before = set(RAW.glob("*.mp4"))
    sig = signal.SIGUSR1
    for length, n in SAVES:
        if length >= seconds and length <= buffer_seconds:
            sig = signal.SIGRTMIN + n
            break
    asked = time.time()
    os.kill(pid, sig)
    last, steady = -1, 0
    while time.time() - asked < 30:
        time.sleep(0.25)
        new = set(RAW.glob("*.mp4")) - before
        if not new:
            continue
        f = new.pop()
        size = f.stat().st_size
        steady = steady + 1 if size == last and size > 0 else 0
        last = size
        if steady >= 3:
            return f, asked
    return None, asked


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(path)],
                         capture_output=True, text=True).stdout.strip()
    return float(out) if out else 0.0


def cut(raw, spans, out):
    """Copy the given (start, end) stretches of raw into out, no re-encode."""
    out.parent.mkdir(parents=True, exist_ok=True)
    if len(spans) == 1:
        a, b = spans[0]
        cmd = ["ffmpeg", "-v", "error", "-y", "-ss", f"{a:.2f}", "-to", f"{b:.2f}", "-i", str(raw)]
    else:
        listing = RAW / "cut.txt"
        listing.write_text("".join(f"file '{raw}'\ninpoint {a:.2f}\noutpoint {b:.2f}\n" for a, b in spans))
        cmd = ["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", str(listing)]
    cmd += ["-c", "copy", "-avoid_negative_ts", "make_zero", "-movflags", "+faststart", str(out)]
    done = subprocess.run(cmd, capture_output=True, text=True)
    if done.returncode != 0 or not out.exists() or out.stat().st_size == 0:
        log("cut failed:", done.stderr.strip()[-300:])
        out.unlink(missing_ok=True)
        return False
    return True


def plan(mark, cfg, shot_age, length):
    """Where to cut. Times are seconds into a saved replay `length` long whose end is now;
    the screenshot was taken shot_age seconds before that. Returns (spans, peak span or None)."""
    def at(ago):  # seconds before the screenshot -> seconds into the file
        return max(0.0, min(length, length - shot_age - ago))
    end = at(0.5)  # stop short of the mark itself
    if mark is None:
        return [(max(0.0, length - cfg["screenshot_seconds"]), length)], None
    if mark["kind"] == "manual":
        return [(at(cfg["manual_seconds"]), end)], None
    start = at(mark["seconds"] + cfg["lead_in"])
    spans = [(start, end)]
    card = cfg["card_seconds"] + 0.5
    if mark["kind"] == "quiet" and mark["since"] > cfg["tail"] + card + 4:
        # the fuse burned down in silence: keep the fight, drop the wait, land on the card
        spans = [(start, at(mark["since"] - cfg["tail"]))]
        if mark["grade"]:
            spans.append((at(card), end))
    peak = None
    if mark["kills"] >= 2 and sum(b - a for a, b in spans) > 45:
        peak = (max(start, at(mark["peak"] + cfg["peak_lead"])), min(spans[0][1], at(mark["peak"] - cfg["peak_tail"])))
        if peak[1] - peak[0] < 5:
            peak = None
    return [s for s in spans if s[1] - s[0] > 0.5], peak


def clip_name(mark, when):
    stamp = when.strftime("%H%M%S")
    if mark is None or mark["kind"] == "manual":
        return f"{stamp}_clip"
    parts = [stamp, f"{mark['kills']}-kill{'s' if mark['kills'] != 1 else ''}"]
    if mark["rung"]:
        parts.append(mark["rung"].replace(" ", "-"))
    if mark["king"]:
        parts.append("REGICIDE")
    if mark["grade"]:
        parts.append(mark["grade"].replace("+", "plus"))
    return "_".join(parts)


def notify(cfg, text):
    if cfg["notify"] and shutil.which("notify-send"):
        subprocess.run(["notify-send", "-a", "Godslayer clipper", "-t", "3000", "-h", "int:transient:1",
                        "Godslayer clipper", text], check=False)


def handle_shot(cfg, shot):
    try:
        mark = decode_mark(shot)
    except Exception as e:  # a half-written or odd file is just a screenshot with no mark
        log("could not read", shot.name, e)
        mark = None
    taken = shot.stat().st_mtime
    if mark is None and not cfg["screenshot_seconds"]:
        return
    if mark and mark["kind"] != "manual" and mark["kills"] < cfg["min_kills"]:
        log("hunt under min_kills, skipped")
        return
    folder, cap = library(cfg)
    if folder is None:
        log("not saved:", cap)
        notify(cfg, "Clip not saved: " + cap)
        return
    if mark is None:
        want = cfg["screenshot_seconds"]
    elif mark["kind"] == "manual":
        want = cfg["manual_seconds"] + 3
    else:
        want = mark["seconds"] + cfg["lead_in"] + 5
    raw, asked = save_replay(want + (time.time() - taken), cfg["buffer_seconds"])
    if raw is None:
        log("the recorder gave nothing back for", shot.name)
        return
    try:
        length = duration(raw)
        spans, peak = plan(mark, cfg, asked - taken, length)
        when = datetime.fromtimestamp(taken)
        day = folder / ("tests" if mark and mark["pretend"] else when.strftime("%Y-%m-%d"))
        out = day / (clip_name(mark, when) + ".mp4")
        if not spans or not cut(raw, spans, out):
            return
        if peak:
            cut(raw, [peak], out.with_name(out.stem + "_peak.mp4"))
        if mark:
            shutil.move(str(shot), str(out.with_suffix(".jpg")))  # the marked screenshot is the clip's still
        with open(folder / "index.jsonl", "a") as f:
            f.write(json.dumps({"clip": str(out.relative_to(folder)), "taken": when.isoformat(timespec="seconds"),
                                "seconds": round(duration(out), 1), "mark": mark}) + "\n")
        log("saved", out, f"{out.stat().st_size / 1e6:.0f} MB")
        notify(cfg, "Saved " + out.stem.split("_", 1)[1].replace("_", " "))
        prune(folder, cap)
    finally:
        raw.unlink(missing_ok=True)


def write_state(**state):
    RUNTIME.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state))


def run():
    cfg = load_config()
    shots_dir = Path(cfg["wow_dir"]) / "Screenshots"
    if not cfg["wow_dir"] or not Path(cfg["wow_dir"]).is_dir():
        sys.exit(f"Set wow_dir in {CONFIG}")
    seen = set(shots_dir.glob("*")) if shots_dir.is_dir() else set()
    proc, audio, since, retry_at, pending = None, None, 0, 0, {}
    log("watching", shots_dir)

    def stop(*_):
        stop_recorder(proc)
        write_state(recording=False, game=False)
        sys.exit(0)
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    while True:
        game = game_running(cfg)
        if game and proc is None and time.time() >= retry_at:
            since = since or time.time()
            audio = game_audio(cfg)
            # the game has no sound stream until its login screen is up; give it a minute
            if audio is None and time.time() - since > 60:
                audio = "default_output"
                log("the game's own sound was not found; recording desktop sound")
            if audio:
                proc = start_recorder(cfg, audio)
        elif proc is not None and (not game or proc.poll() is not None):
            if game:
                log("the recorder stopped (see", LOG, "); trying again in two minutes")
                notify(cfg, "The recorder stopped. Run: wow-clipper setup")
                retry_at = time.time() + 120
            stop_recorder(proc)
            proc, since = None, 0
        if not game:
            since = 0
        write_state(recording=proc is not None, game=game, audio=audio, at=time.time())
        if proc is None:
            time.sleep(5)
            if shots_dir.is_dir():
                seen = set(shots_dir.glob("*"))
            continue
        # a new screenshot, once its size has stopped changing
        for _ in range(8):
            time.sleep(0.25)
            now = set(shots_dir.glob("*")) if shots_dir.is_dir() else set()
            for shot in now - seen:
                size = shot.stat().st_size
                if size and pending.get(shot) == size:
                    seen.add(shot)
                    pending.pop(shot, None)
                    try:
                        handle_shot(cfg, shot)
                    except Exception as e:
                        log("clip failed:", repr(e))
                else:
                    pending[shot] = size


# ---------------------------------------------------------------- commands

def setup():
    """Ask once which screen to record; the choice is remembered for every later session."""
    cfg = load_config()
    print("A 'share your screen' window is about to open. Pick the monitor the game runs on and confirm.")
    proc = start_recorder(cfg, "default_output", seconds=10)
    token = CONFIG.parent / "portal_token"
    deadline = time.time() + 180
    while time.time() < deadline and proc.poll() is None and not (recorder_pid() and token.exists()):
        time.sleep(1)
    ok = proc.poll() is None and token.exists()
    if ok:
        time.sleep(4)
        raw, _ = save_replay(10, 10)
        ok = raw is not None and duration(raw) > 1
        if ok:
            probe = Path(cfg["fallback_library"]) / "setup-check.mp4"
            probe.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(raw), str(probe))
            print("Recording works. A few seconds of your screen:", probe)
    stop_recorder(proc)
    if not ok:
        sys.exit(f"The recorder did not start. Its log: {LOG}")


def status():
    cfg = load_config()
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    alive = time.time() - state.get("at", 0) < 30
    print("Service:  ", "running" if alive else "not running (systemctl --user start wow-clipper)")
    print("Game:     ", "running" if alive and state.get("game") else "not running")
    print("Recorder: ", f"holding the last {cfg['buffer_seconds'] // 60} minutes in memory, sound from {state.get('audio')}"
          if alive and state.get("recording") else "idle (it starts with the game)")
    print("Screen:   ", "chosen" if (CONFIG.parent / "portal_token").exists() else "not chosen yet: run wow-clipper setup")
    folder, cap = library(cfg)
    if folder is None:
        print("Library:   none usable:", cap)
        return
    disk = shutil.disk_usage(folder)
    found = clips(folder)
    print(f"Library:   {folder}")
    print(f"           {usage_gb(folder):.1f} GB of a {cap} GB cap in {len(found)} clips; the drive has {disk.free / 1e9:.0f} GB free of {disk.total / 1e9:.0f}")
    if found:
        print("Newest:   ", found[-1])


def find_clip(cfg, name):
    folder, _ = library(cfg)
    p = Path(name)
    if p.is_file():
        return folder, p
    hits = [c for c in clips(folder) if name in c.name] if folder else []
    if len(hits) != 1:
        sys.exit(f"{len(hits)} clips match '{name}'. wow-clipper list shows them.")
    return folder, hits[0]


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    cfg = load_config()
    if cmd == "run":
        run()
    elif cmd == "setup":
        setup()
    elif cmd == "status":
        status()
    elif cmd == "list":
        folder, _ = library(cfg)
        for c in clips(folder) if folder else []:
            print(f"{datetime.fromtimestamp(c.stat().st_mtime):%m-%d %H:%M}  {c.stat().st_size / 1e6:6.0f} MB  {c.relative_to(folder)}")
    elif cmd == "keep" and len(sys.argv) > 2:
        folder, clip = find_clip(cfg, sys.argv[2])
        (folder / "keep").mkdir(exist_ok=True)
        for f in (clip, clip.with_suffix(".jpg")):
            if f.exists():
                shutil.move(str(f), str(folder / "keep" / f.name))
        print("Kept. It will never be pruned:", folder / "keep" / clip.name)
    elif cmd == "short" and len(sys.argv) > 2:
        _, clip = find_clip(cfg, sys.argv[2])
        mode = sys.argv[3] if len(sys.argv) > 3 else "mid"
        out = clip.with_name(clip.stem + "_vertical.mp4")
        blur = "[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=24:4[bg];"
        graph = {
            "zoom": "[0:v]scale=-2:1920,crop=1080:1920[v]",                                  # the middle third, full height
            "mid": blur + "[0:v]crop=ih*4/5:ih,scale=1080:1350[fg];[bg][fg]overlay=0:(H-h)/2[v]",  # a 4:5 window on a blurred frame
            "fit": blur + "[0:v]scale=1080:-2[fg];[bg][fg]overlay=0:(H-h)/2[v]",                 # the whole screen, small
        }[mode]
        subprocess.run(["ffmpeg", "-v", "error", "-stats", "-y", "-i", str(clip), "-filter_complex", graph, "-map", "[v]", "-map", "0:a?",
                        "-c:v", "h264_nvenc", "-preset", "p6", "-b:v", "12M", "-c:a", "aac", "-b:a", "192k",
                        "-movflags", "+faststart", str(out)], check=True)
        print(out)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
