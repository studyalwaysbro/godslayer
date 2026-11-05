-- Offline tests for the 2.7.0 pivot: lua tests/pivot.lua   (from the project root, Lua 5.1)
--
-- Olympus launched on the PvE ruleset, so on this server every player kill scores one point,
-- the named rings are a bonus, and a character upgrading from 2.4-2.6 (where open-ring kills
-- were banked at zero) must have those kills lifted to the floor on the first login. This file
-- pins the migration, the always-open ring, and the version-tolerant leaderboard receiver.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", race = "Scourge", sex = 2, faction = "Horde", isMe = true })

-- A character as 2.6.0 left it: no schema, and the open-ring kills banked at zero points, which
-- is the deficit that made 2.6 clients report points < kills and get dropped from the board.
GodslayerDB = {
  version = 2, log = {}, roster = {}, ignore = {}, custom = {}, known = {},
  opts = { minimap = true, toast = true, tooltip = true, sound = true, chat = true },
  chars = {
    ["Vesh Torchman"] = {
      class = "MAGE", kills = 6, points = 10, uniques = 2, kb = 1, orig = 2, kings = 0, bestStreak = 2,
      guilds = {
        ["OLYMPUS"] = { kills = 2, points = 10, tier = "original" },
        ["Random Mob"] = { kills = 4, points = 0, tier = "any" },
      },
      victims = {
        ["Player-1-0000B001"] = { kills = 2, points = 10, kb = 1, ok = 2, guild = "OLYMPUS", tier = "original", name = "Old Olympian", class = "ROGUE", first = 1791000000, last = 1791300000 },
        ["Player-1-0000B002"] = { kills = 4, points = 0, kb = 0, guild = "Random Mob", tier = "any", name = "Old Random", class = "WARRIOR", first = 1791000000, last = 1791300000 },
      },
    },
  },
}

local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local c = ns.char

-- ---------------------------------------------------------------------------
-- 1. The migration ran, exactly once, and lifted the deficit
-- ---------------------------------------------------------------------------
eq(c.schema, 27, "the character is stamped with the new schema")
eq(c.victims["Player-1-0000B002"].points, 4, "the open-ring victim's four kills are lifted to four points")
eq(c.victims["Player-1-0000B002"].tier, "any", "and stay in the open ring")
eq(c.victims["Player-1-0000B001"].points, 10, "the Olympus victim is untouched")
eq(c.orig, 2, "the original count is unchanged by the lift")
eq(c.kills, 6, "the kill count is unchanged")
eq(c.points, 14, "the points are 10 Olympus plus 4 lifted")
check(c.points >= c.kills, "and points are no longer fewer than kills, which is what the board rejected")

-- the running totals now equal a fresh recount: the migration did not leave them adrift
local before = { c.kills, c.points, c.uniques, c.kb, c.orig }
ns.Recount()
check(before[1] == c.kills and before[2] == c.points and before[3] == c.uniques and before[4] == c.kb and before[5] == c.orig,
  ("totals stable across a recount: %d/%d kills %d/%d points"):format(before[1], c.kills, before[2], c.points))

-- ---------------------------------------------------------------------------
-- 2. A second login does not migrate again
-- ---------------------------------------------------------------------------
c.victims["Player-1-0000B002"].points = 99  -- if the migration re-ran it would reset this to 4
M.fire("PLAYER_LOGIN")
eq(ns.char.victims["Player-1-0000B002"].points, 99, "a character already at schema 27 is left alone")

-- ---------------------------------------------------------------------------
-- 3. The open ring is on by default: no three-session wait, no rival needed
-- ---------------------------------------------------------------------------
eq(ns.ClassifyWide("Some Random Guild"), "any", "an unknown guild scores in the open ring from the start")
eq(ns.ClassifyWide("OLYMPUS"), "original", "Olympus still answers first")
eq(ns.PointsFor("any"), 1, "an open-ring kill is worth one point")

-- ---------------------------------------------------------------------------
-- 4. The leaderboard accepts a 2.6 client's honest row, deficit and all
-- ---------------------------------------------------------------------------
-- A client still on 2.6.0 computes points with the open ring at zero, so it can report fewer
-- points than kills. That is the truth, not a cheat, and the receiver must keep it on the board.
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;12;4;5;2;0;WARRIOR;2.6.0;0;abc123;2", "GUILD", "Old Client Guildmate")
local board = ns.Comm.Leaderboard()
local found
for _, r in ipairs(board) do if r.name == "Old Client Guildmate" then found = r end end
check(found ~= nil, "a guildmate on the old version still appears on the board")
eq(found and found.kills, 12, "with their real kill count")
eq(found and found.points, 4, "and their real points, low as they are")
-- an impossible row (more points than five a kill) is still refused
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;2;99;1;0;0;MAGE;2.7.0;0;def456;0", "GUILD", "Liar")
board = ns.Comm.Leaderboard()
local liar
for _, r in ipairs(board) do if r.name == "Liar" then liar = r end end
eq(liar, nil, "a row claiming more than five points a kill is still dropped")

M.realPrint(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
