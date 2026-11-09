#!/usr/bin/env python3
"""Offline tests for the combat-log trigger: python3 clipper/test_combatlog.py"""
import os
import sys
import time
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import wow_clipper as W

ME = "Player-6926-00103EDC"       # us (Yeet-Yeeterson)
MATE = "Player-6800-001C5CEA"     # a groupmate; PARTY_KILL fires for the whole party
# the real Forever timestamp: M/D/YYYY, a -5 tz suffix, two spaces before the event
TS = "11/8/2026 18:00:00.000-5  "


def kill_line(src, dest):
    return f'{TS}PARTY_KILL,{src},"Src-PvP-US",0x512,0x0,{dest},"Victim",0x10548,0x0,0'


def died_line(guid):
    return f'{TS}UNIT_DIED,0000000000000000,nil,0x80000000,0x80000000,{guid},"Who-PvP-US",0x511,0x0,0'


def feed(clog, line, now, cfg):
    payload = W.cl_payload(line)
    ev = W.parse_cl_event(payload) if payload else None
    return W.feed_combatlog(clog, ev, now, cfg) if ev else None


def low_cfg(**over):
    """A config whose combat-log floor is 1, so small synthetic hunts still clip."""
    base = dict(W.load_config(), combatlog_min_kills=1, player_guid=None)
    base.update(over)
    return base


class Rungs(unittest.TestCase):
    def test_places_match_hype(self):
        for kills, place in [(0, 0), (1, 1), (2, 2), (3, 3), (4, 3), (5, 4), (6, 4),
                             (7, 5), (9, 5), (10, 6), (14, 6), (15, 7), (19, 7),
                             (20, 8), (25, 9), (30, 10), (40, 11), (50, 12), (73, 12)]:
            self.assertEqual(W.rung_place(kills), place, f"{kills} kills")

    def test_rung_names(self):
        name = lambda k: W.LADDER[W.rung_place(k) - 1] if W.rung_place(k) else ""
        self.assertEqual(name(1), "FIRST BLOOD")
        self.assertEqual(name(7), "UNSTOPPABLE")
        self.assertEqual(name(11), "BEYOND GODLIKE")
        self.assertEqual(name(15), "GODSLAYER")


class Parse(unittest.TestCase):
    def test_payload_split_real_timestamp(self):
        # the Forever date has a 4-digit year and a -5 tz; the split is on the two spaces
        self.assertEqual(W.cl_payload(kill_line(ME, "Creature-0-77")).split(",")[0], "PARTY_KILL")
        self.assertIsNone(W.cl_payload("no double space here just one"))

    def test_events(self):
        self.assertEqual(W.parse_cl_event(W.cl_payload(kill_line(ME, "Creature-0-77"))), ("kill", ME, "Creature-0-77"))
        self.assertEqual(W.parse_cl_event(W.cl_payload(died_line(ME))), ("died", ME))
        other = f'{TS}SPELL_DAMAGE,{ME},"Me",0x511,0x0,Creature-0-1,"Boar",0x10a48,0x0,116,"Frostbolt"'
        self.assertIsNone(W.parse_cl_event(W.cl_payload(other)))


class Hunt(unittest.TestCase):
    def setUp(self):
        self.cfg = low_cfg()
        self.clog = W.new_combatlog()

    def _me(self, now=99.0):
        feed(self.clog, kill_line(ME, "Creature-seed"), now, self.cfg)   # one blow teaches "me"

    def test_party_kill_only_learns_me_never_ticks(self):
        # a PARTY_KILL (even ours) does not start a hunt; deaths do.
        self.assertIsNone(feed(self.clog, kill_line(ME, "Creature-0-1"), 100.0, self.cfg))
        self.assertEqual(self.clog["player"], ME)
        self.assertIsNone(self.clog["hunt"])

    def test_pack_melt_counts_every_death(self):
        # the live case: a frozen pack dropping. Every enemy death near us is a kill,
        # mob or player, no matter who in the party landed the final blow.
        self._me()
        feed(self.clog, died_line("Creature-0-1"), 100.0, self.cfg)
        feed(self.clog, died_line("Creature-0-2"), 101.0, self.cfg)
        feed(self.clog, died_line("Player-9-ENEMY"), 102.0, self.cfg)   # an enemy player too
        self.assertEqual(self.clog["hunt"]["kills"], 3)

    def test_learns_me_by_frequency(self):
        feed(self.clog, kill_line(MATE, "Creature-a"), 100.0, self.cfg)
        feed(self.clog, kill_line(ME, "Creature-b"), 100.1, self.cfg)
        feed(self.clog, kill_line(ME, "Creature-c"), 100.2, self.cfg)   # ME now leads
        self.assertEqual(self.clog["player"], ME)

    def test_pinned_guid_wins_over_frequency(self):
        cfg = low_cfg(player_guid=ME)
        for _ in range(5):
            feed(self.clog, kill_line(MATE, "Creature-0-1"), 100.0, cfg)   # mate dominates the log
        self.assertEqual(self.clog["player"], ME)                # pin holds regardless

    def test_my_death_ends_hunt_and_is_not_a_kill(self):
        self._me()
        feed(self.clog, died_line("Creature-0-1"), 100.0, self.cfg)
        feed(self.clog, died_line("Creature-0-2"), 102.0, self.cfg)
        feed(self.clog, died_line("Creature-0-3"), 103.0, self.cfg)
        self.assertEqual(self.clog["hunt"]["kills"], 3)
        done = feed(self.clog, died_line(ME), 110.0, self.cfg)   # we die: hunt over, we are not a kill
        self.assertEqual(done, ("end", "died", 110.0))
        mark = W.hunt_mark(self.clog, "died", 110.0, self.cfg)
        self.assertEqual((mark["kind"], mark["kills"], mark["rung"]), ("died", 3, "ULTRA KILL"))
        self.assertEqual(mark["seconds"], 10)                    # 110 - first death at 100
        self.assertFalse(mark["flawless"])

    def test_my_death_without_a_hunt_is_quiet(self):
        self._me()
        self.assertIsNone(feed(self.clog, died_line(ME), 120.0, self.cfg))

    def test_quiet_mark_flawless(self):
        self._me(99.0)
        for t in range(100, 110):
            feed(self.clog, died_line(f"Creature-0-{t}"), float(t), self.cfg)
        self.assertEqual(self.clog["hunt"]["kills"], 10)
        taken = 109 + self.cfg["combatlog_quiet"]
        mark = W.hunt_mark(self.clog, "quiet", taken, self.cfg)
        self.assertEqual((mark["kind"], mark["rung"]), ("quiet", "BEYOND GODLIKE"))
        self.assertEqual(mark["since"], self.cfg["combatlog_quiet"])
        self.assertTrue(mark["flawless"])                        # survived 10+, never died

    def test_burst_floor_gates_small_clusters(self):
        cfg = low_cfg(combatlog_min_kills=10)
        self._me()
        for i in range(8):                                       # eight down: below the floor of ten
            feed(self.clog, died_line(f"Creature-0-{i}"), 100.0 + i, cfg)
        self.assertIsNone(W.hunt_mark(self.clog, "quiet", 130.0, cfg))
        feed(self.clog, died_line("Creature-0-8"), 108.0, cfg)
        feed(self.clog, died_line("Creature-0-9"), 109.0, cfg)  # now ten: a real burst
        self.assertEqual(W.hunt_mark(self.clog, "quiet", 130.0, cfg)["kills"], 10)

    def test_one_player_gank_clips_under_the_floor(self):
        # PvP: a single enemy player we killed is a clip even with the ten-mob floor up
        cfg = low_cfg(combatlog_min_kills=10)
        self._me()
        feed(self.clog, kill_line(ME, "Player-9-VICTIM"), 100.0, cfg)
        feed(self.clog, died_line("Player-9-VICTIM"), 100.2, cfg)
        mark = W.hunt_mark(self.clog, "quiet", 100.2 + cfg["combatlog_quiet"], cfg)
        self.assertEqual(mark["kills"], 1)

    def test_player_death_before_killing_blow_still_clips(self):
        # the death line can land in the log before the PARTY_KILL line
        cfg = low_cfg(combatlog_min_kills=10)
        self._me()
        feed(self.clog, died_line("Player-9-VICTIM"), 100.0, cfg)
        feed(self.clog, kill_line(ME, "Player-9-VICTIM"), 100.1, cfg)
        mark = W.hunt_mark(self.clog, "quiet", 100.1 + cfg["combatlog_quiet"], cfg)
        self.assertEqual(mark["kills"], 1)

    def test_creature_killing_blow_stays_gated(self):
        # PvE keeps the floor: one mob's killing blow is not a clip
        cfg = low_cfg(combatlog_min_kills=10)
        self._me()
        feed(self.clog, kill_line(ME, "Creature-0-1"), 100.0, cfg)
        feed(self.clog, died_line("Creature-0-1"), 100.2, cfg)
        self.assertIsNone(W.hunt_mark(self.clog, "quiet", 130.0, cfg))

    def test_our_own_death_is_not_a_pvp_flag(self):
        # an enemy's killing blow on US must not flag a burst as our gank
        cfg = low_cfg(combatlog_min_kills=10, player_guid=ME)
        self._me()
        feed(self.clog, kill_line("Player-9-ENEMY", ME), 100.0, cfg)
        self.assertIsNone(self.clog["hunt"] and self.clog["hunt"].get("pkills"))

    def test_arm_clears_hunt(self):
        self._me()
        for i in range(5):
            feed(self.clog, died_line(f"Creature-0-{i}"), 100.0 + i, self.cfg)
        W.arm_pending(self.clog, "died", 106.0, self.cfg)
        self.assertIsNone(self.clog["hunt"])
        self.assertIsNotNone(self.clog["pending"])
        self.assertEqual(self.clog["pending"]["mark"]["kills"], 5)


class Newest(unittest.TestCase):
    def test_picks_most_recent_dated_file(self):
        with tempfile.TemporaryDirectory() as d:
            logs = Path(d) / "Logs"
            logs.mkdir()
            old = logs / "WoWCombatLog-110726_120000.txt"
            new = logs / "WoWCombatLog-110826_085641.txt"
            old.write_text("old\n")
            new.write_text("new\n")
            os.utime(old, (time.time() - 3600, time.time() - 3600))
            os.utime(new, None)
            cfg = dict(W.load_config(), wow_dir=d, combatlog_file=None,
                       combatlog_dir="Logs", combatlog_glob="WoWCombatLog*.txt")
            self.assertEqual(W.newest_combatlog(cfg), new)

    def test_none_when_no_logs(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "Logs").mkdir()
            cfg = dict(W.load_config(), wow_dir=d, combatlog_file=None)
            self.assertIsNone(W.newest_combatlog(cfg))

    def test_pinned_file_overrides(self):
        with tempfile.TemporaryDirectory() as d:
            logs = Path(d) / "Logs"
            logs.mkdir()
            pinned = logs / "mylog.txt"
            pinned.write_text("x\n")
            cfg = dict(W.load_config(), wow_dir=d, combatlog_file="Logs/mylog.txt")
            self.assertEqual(W.newest_combatlog(cfg), pinned)


if __name__ == "__main__":
    unittest.main(verbosity=2)
