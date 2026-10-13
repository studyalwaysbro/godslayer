#!/usr/bin/env python3
"""Offline tests for the clipper: python3 clipper/test_clipper.py  (from the project root)"""
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).parent))
import wow_clipper as W

ROOT = Path(__file__).parent.parent
# the bytes tests/v2.lua checks the addon's CRC against
VECTOR = [0xAC, 0x11, 7, 0, 200, 0, 98, 5, 3, 3, 5, 2, 0, 120, 9, 0x03]


def screenshot(data, cell=8.0, shift=(0, 0), quality=25, size=(2560, 1440), seed=1):
    """A noisy screen with the mark drawn the way Clip.lua draws it, saved the way the game saves."""
    rng = np.random.default_rng(seed)
    a = rng.integers(0, 256, (size[1], size[0], 3), dtype=np.uint8)
    x0, y0 = shift
    a[y0:y0 + round((W.ROWS + 2) * cell), x0:x0 + round((W.COLS + 2) * cell)] = 0
    bits = np.unpackbits(np.array(data, dtype=np.uint8))
    for i, bit in enumerate(bits):
        if bit:
            cx, cy = (i % W.COLS + 1) * cell + x0, (i // W.COLS + 1) * cell + y0
            a[round(cy):round(cy + cell), round(cx):round(cx + cell)] = 255
    f = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
    Image.fromarray(a).save(f.name, quality=quality)
    return f.name


class Mark(unittest.TestCase):
    def test_vector(self):
        self.assertEqual(W.crc8(VECTOR[:15]), VECTOR[15])
        m = W.parse_mark(bytes(VECTOR))
        self.assertEqual((m["kind"], m["kills"], m["seconds"], m["since"], m["rung"], m["run"], m["grade"], m["points"], m["peak"]),
                         ("quiet", 7, 200, 98, "UNSTOPPABLE", 3, "A", 5, 120))
        self.assertTrue(m["record"] and not m["pretend"])

    def test_reads_a_screenshot(self):
        for cell in (8.0, 6.0, 7.5, 10.67, 12.0, 16.0):
            for shift in ((0, 0), (1, 1), (2, 0)):
                for quality in (15, 60):
                    path = screenshot(VECTOR, cell, shift, quality)
                    m = W.decode_mark(path)
                    os.unlink(path)
                    self.assertIsNotNone(m, f"cell {cell} shift {shift} quality {quality}")
                    self.assertEqual(m["kills"], 7)

    def test_no_mark_in_ordinary_pictures(self):
        rng = np.random.default_rng(7)
        for i in range(60):
            a = rng.integers(0, 256, (300, 700, 3), dtype=np.uint8)
            if i % 3 == 0:
                a[:60] = 0  # a black bar along the top, like a letterbox
            if i % 3 == 1:
                a = np.kron(rng.integers(0, 2, (38, 88, 1), dtype=np.uint8) * 255, np.ones((8, 8, 3), dtype=np.uint8))[:300, :700]
            f = tempfile.NamedTemporaryFile(suffix=".png", delete=False)
            Image.fromarray(a.astype(np.uint8)).save(f.name)
            self.assertIsNone(W.decode_mark(f.name))
            os.unlink(f.name)

    def test_a_damaged_mark_is_refused(self):
        bad = list(VECTOR)
        bad[2] = 8
        path = screenshot(bad)
        self.assertIsNone(W.decode_mark(path))
        os.unlink(path)

    def test_ladder_matches_the_addon(self):
        lua = (ROOT / "Godslayer" / "Hype.lua").read_text()
        block = lua[lua.index("local LADDER = {"):lua.index("Hype.LADDER = LADDER")]
        self.assertEqual(re.findall(r'\{ \d+, "([^"]+)"', block), W.LADDER)

    def test_layout_matches_the_addon(self):
        lua = (ROOT / "Godslayer" / "Clip.lua").read_text()
        self.assertIn(f"local COLS, ROWS, CELL = {W.COLS}, {W.ROWS}, 8", lua)
        self.assertIn("local MAGIC, VERSION = 0xAC, 1", lua)


class Plan(unittest.TestCase):
    cfg = dict(W.DEFAULTS)

    def mark(self, **kw):
        m = W.parse_mark(bytes(VECTOR))
        m.update(kw)
        return m

    def test_a_hunt_that_ran_out(self):
        # 200 s hunt, last kill 98 s before the mark, replay 300 s long, screenshot 1 s before the save
        spans, peak = W.plan(self.mark(), self.cfg, 1.0, 300.0)
        self.assertEqual(len(spans), 2)
        self.assertAlmostEqual(spans[0][0], 300 - 1 - 225)       # 25 s before the first kill
        self.assertAlmostEqual(spans[0][1], 300 - 1 - 98 + 10)   # 10 s after the last
        self.assertAlmostEqual(spans[1][0], 300 - 1 - 8.5)       # the card
        self.assertAlmostEqual(spans[1][1], 300 - 1 - 0.5)       # and not the mark
        self.assertAlmostEqual(peak[0], 300 - 1 - 120 - 12)
        self.assertAlmostEqual(peak[1], 300 - 1 - 120 + 6)

    def test_a_hunt_you_died_in(self):
        spans, peak = W.plan(self.mark(kind="died", seconds=40, since=4, peak=4, grade=""), self.cfg, 0.5, 60.0)
        self.assertEqual(len(spans), 1)
        self.assertAlmostEqual(spans[0][0], 0.0)  # the replay is shorter than the lead in asks for
        self.assertAlmostEqual(spans[0][1], 59.0)

    def test_no_card_no_second_span(self):
        spans, _ = W.plan(self.mark(grade="", kills=1, seconds=90, since=90, peak=90), self.cfg, 1.0, 300.0)
        self.assertEqual(len(spans), 1)

    def test_manual_and_plain(self):
        spans, peak = W.plan(self.mark(kind="manual"), self.cfg, 1.0, 300.0)
        self.assertEqual((round(spans[0][0], 1), round(spans[0][1], 1), peak), (239.0, 298.5, None))
        spans, _ = W.plan(None, self.cfg, 1.0, 300.0)
        self.assertEqual(spans, [(240.0, 300.0)])

    def test_names(self):
        from datetime import datetime
        when = datetime(2026, 10, 13, 21, 14, 7)
        self.assertEqual(W.clip_name(self.mark(), when), "211407_7-kills_UNSTOPPABLE_A")
        self.assertEqual(W.clip_name(self.mark(kills=1, rung="FIRST BLOOD", grade=""), when), "211407_1-kill_FIRST-BLOOD")
        self.assertEqual(W.clip_name(self.mark(grade="S+", king=True), when), "211407_7-kills_UNSTOPPABLE_REGICIDE_Splus")
        self.assertEqual(W.clip_name(None, when), "211407_clip")


class Files(unittest.TestCase):
    def test_cut_and_join(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            W.RAW = d
            raw = d / "raw.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "testsrc=s=640x360:r=30:d=60", "-f", "lavfi", "-i",
                            "sine=f=440:d=60", "-c:v", "libx264", "-preset", "ultrafast", "-g", "60", "-c:a", "aac", str(raw)], check=True)
            self.assertTrue(W.cut(raw, [(10, 30)], d / "one.mp4"))
            self.assertAlmostEqual(W.duration(d / "one.mp4"), 20, delta=2.5)
            self.assertTrue(W.cut(raw, [(4, 24), (50, 58)], d / "two.mp4"))
            self.assertAlmostEqual(W.duration(d / "two.mp4"), 28, delta=4.5)
            self.assertFalse(W.cut(d / "missing.mp4", [(0, 5)], d / "none.mp4"))
            self.assertFalse((d / "none.mp4").exists())

    def test_prune_spares_keep(self):
        with tempfile.TemporaryDirectory() as d:
            d = Path(d)
            (d / "2026-10-01").mkdir()
            (d / "keep").mkdir()
            for i, rel in enumerate(["2026-10-01/a.mp4", "2026-10-01/b.mp4", "keep/k.mp4", "c.mp4"]):
                (d / rel).write_bytes(b"x" * 1_000_000)
                os.utime(d / rel, (time.time() - 1000 + i, time.time() - 1000 + i))
            (d / "2026-10-01" / "a.jpg").write_bytes(b"x")
            W.prune(d, 0.0025)  # room for two and a half
            left = sorted(str(p.relative_to(d)) for p in d.rglob("*.mp4"))
            self.assertEqual(left, ["c.mp4", "keep/k.mp4"])
            self.assertFalse((d / "2026-10-01").exists())

    def test_library_needs_its_drive(self):
        with tempfile.TemporaryDirectory() as d:
            cfg = dict(W.DEFAULTS, library=d + "/main", library_mount=d + "/not-a-mount", fallback_library=d + "/fallback", min_free_gb=0)
            self.assertEqual(W.library(cfg), (Path(d) / "fallback", cfg["fallback_cap_gb"]))
            cfg["library_mount"] = ""
            self.assertEqual(W.library(cfg), (Path(d) / "main", cfg["cap_gb"]))
            cfg["min_free_gb"] = 10 ** 9
            self.assertIsNone(W.library(cfg)[0])


if __name__ == "__main__":
    unittest.main()
