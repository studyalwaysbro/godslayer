-- Godslayer on a realm that may not have Olympus: lua tests/rival.lua
-- The point of this file is the default. The widened hunt must be invisible until it is needed,
-- because a realm that does have Olympus must score exactly as 2.2.0 scored.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", race = "Scourge", sex = 2, faction = "Horde", isMe = true })
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local c = ns.char
local function say(text) SlashCmdList["GODSLAYER"](text) end
local gid = 0
local function enemy(name, guild, extra)
  gid = gid + 1
  local u = { name = name, guid = ("Player-1-0000C%03d"):format(gid), guild = guild,
              faction = "Alliance", combat = true, player = true }
  for k, v in pairs(extra or {}) do u[k] = v end
  M.addUnit("target", u)
  M.fire("PLAYER_TARGET_CHANGED")
  return u
end
local function kill(u) M.fire("PARTY_KILL", ME, u.guid) M.advance(1) end

-- ---------------------------------------------------------------------------
-- 1. The default: nothing changes
-- ---------------------------------------------------------------------------
eq(ns.ClassifyWide("Random Strangers"), "any", "a random guild joins the open ring by default")
eq(ns.ClassifyWide("OLYMPUS"), "original", "Olympus is still the original")
eq(ns.ClassifyWide("OLYMPUS BETZ"), "network", "an Olympus network guild still classifies")
eq(GodslayerDB.wide.on, true, "the login at startup already opened the rings")

eq(ns.PointsFor("original"), 5, "original is still 5 points")
eq(ns.PointsFor("network"), 1, "network is still 1 point")
eq(ns.PointsFor("rival"), 3, "a rival is worth 3")
eq(ns.PointsFor("any"), 1, "the open ring is worth one point now")

local before, beforeP = c.kills, c.points
kill(enemy("Nobody Special", "Random Strangers"))
eq(c.kills, before + 1, "a random guild's kill scores in the open ring")
eq(c.points, beforeP + 1, "worth one point")

kill(enemy("Zeus Guy", "OLYMPUS"))
eq(c.kills, before + 2, "an Olympus kill still scores")
eq(c.points, beforeP + 1 + 5, "an Olympus kill is still worth 5")

-- ---------------------------------------------------------------------------
-- 2. Gnomes
-- ---------------------------------------------------------------------------
eq(ns.Rival.GnomeRank(0), nil, "no title for no gnomes")
eq(ns.Rival.GnomeRank(1), "Gnome Starter Kit", "the first gnome has a name for it")
eq(ns.Rival.GnomeRank(2), "Gnome Starter Kit", "below the next threshold the title holds")
eq(ns.Rival.GnomeRank(3), "Tinker Tamperer", "three gnomes is a promotion")
eq(ns.Rival.GnomeRank(7), "Machine Elf Whisperer", "seven gnomes and the machine elves know you")
eq(ns.Rival.GnomeRank(10000), "They Tell Stories About You In Tinkertown", "the top title sticks")

kill(enemy("Tiny Problem", "Random Strangers", { race = "Gnome" }))
eq(GodslayerDB.wide.race.Gnome, 1, "a gnome is counted whatever ring the guild sits in")
kill(enemy("Another Gnome", "OLYMPUS", { race = "Gnome" }))
eq(GodslayerDB.wide.race.Gnome, 2, "gnomes in Olympus count as gnomes too")
kill(enemy("Big Lad", "Random Strangers", { race = "Tauren" }))
eq(GodslayerDB.wide.race.Tauren, 1, "other races are counted as well")
eq(GodslayerDB.wide.race.Gnome, 2, "a tauren is not a gnome")

-- A race whose token is not its name. GetPlayerInfoByGUID returns "Undead" third and "Scourge"
-- fourth, and the count is keyed on the fourth: an Undead filed under "Undead" matches nothing
-- in RACE_TOKENS, so it used to be a kill that vanished -- on an English client for the Undead
-- and the Night Elves, and on any other client for every race in the game.
kill(enemy("Rotten Pete", "Random Strangers", { race = "Scourge" }))
eq(GodslayerDB.wide.race.Scourge, 1, "an Undead is counted under its token")
eq(GodslayerDB.wide.race.Undead, nil, "and never under its localised name")
kill(enemy("Shadowmelder", "Random Strangers", { race = "NightElf" }))
eq(GodslayerDB.wide.race.NightElf, 1, "a Night Elf keeps the token's spelling, with no space")

-- A token the client offers that this addon has never heard of is dropped, not filed.
kill(enemy("Something New", "Random Strangers", { race = "Vulpera" }))
eq(GodslayerDB.wide.race.Vulpera, nil, "an unknown race token is not counted")
eq(GodslayerDB.wide.race.Scourge, 1, "and does not disturb the ones that are")

-- ---------------------------------------------------------------------------
-- 3. Opening by itself after a quiet realm
-- ---------------------------------------------------------------------------
GodslayerDB.wide = nil                      -- a fresh realm
ns.Rival.NoteKill(nil, nil, nil)            -- touch the table into existence
GodslayerDB.wide.quiet = 0
ns.Rival.OnLogin()
eq(GodslayerDB.wide.on, true, "the rings open on the first login now")
eq(GodslayerDB.wide.opened, 1, "and the open state is remembered so it is not reopened over an off")

-- The quiet count is still kept as a record of the realm; it just no longer gates anything.
GodslayerDB.wide.quiet = 2
ns.Rival.NoteKill("Player-1-0000D001", "OLYMPUS", "original")
eq(GodslayerDB.wide.quiet, 0, "an Olympus sighting still resets the quiet count")
ns.Rival.OnLogin()
eq(GodslayerDB.wide.on, true, "and the hunt stays open whether or not Olympus is ever seen")

-- ---------------------------------------------------------------------------
-- 4. With the hunt open
-- ---------------------------------------------------------------------------
say("rival on")
eq(GodslayerDB.wide.on, true, "the command opens the hunt")
eq(ns.ClassifyWide("Random Strangers"), "any", "an unknown guild joins the open ring")
eq(ns.ClassifyWide("OLYMPUS"), "original", "Olympus still answers first and is never overridden")

GodslayerDB.ignore[ns.NormGuild("Peace Treaty")] = true
eq(ns.ClassifyWide("Peace Treaty"), nil, "an ignored guild stays ignored even in the open ring")

local k0, p0 = c.kills, c.points
kill(enemy("Open Ring Guy", "Some Other Guild"))
eq(c.kills, k0 + 1, "an open-ring kill is counted")
eq(c.points, p0 + 1, "and is worth one point")

-- ---------------------------------------------------------------------------
-- 5. Naming a rival
-- ---------------------------------------------------------------------------
say("rival The Big Bads")
eq(GodslayerDB.wide.rival, ns.NormGuild("The Big Bads"), "the command names a rival")
eq(GodslayerDB.wide.rivalLocked, true, "a rival you named is not replaced automatically")
eq(ns.ClassifyWide("The Big Bads"), "rival", "the named guild classifies as the rival")
eq(ns.ClassifyWide("the big bads"), "rival", "capitalisation does not matter")

local k1, p1 = c.kills, c.points
kill(enemy("Rival Guy", "The Big Bads"))
eq(c.kills, k1 + 1, "a rival kill is counted")
eq(c.points, p1 + 3, "a rival kill is worth 3")

say("rival clear")
eq(GodslayerDB.wide.rival, nil, "clear forgets the rival")
eq(GodslayerDB.wide.rivalLocked, nil, "and unlocks the automatic pick")
eq(ns.ClassifyWide("The Big Bads"), "any", "they drop back to the open ring")

say("rival off")
eq(GodslayerDB.wide.on, nil, "off stops the rival nomination")
eq(GodslayerDB.wide.off, true, "and remembers that you turned it off")
eq(ns.ClassifyWide("Some Other Guild"), "any", "but every kill still counts one point")
ns.Rival.OnLogin() ns.Rival.OnLogin() ns.Rival.OnLogin() ns.Rival.OnLogin()
eq(GodslayerDB.wide.on, nil, "a nomination you turned off does not turn itself back on")

-- ---------------------------------------------------------------------------
-- 6. Picking a rival from the blood between you
-- ---------------------------------------------------------------------------
GodslayerDB.wide = nil
ns.Rival.NoteKill(nil, nil, nil)
local w = GodslayerDB.wide
w.on = true
-- Under the encounter floor, nothing is nominated however lopsided it looks.
for i = 1, 3 do ns.Rival.NoteKill(nil, "Small Fry", "any") end
w.since = ns.RIVAL.reviewAfter
ns.Rival.NoteKill(nil, "Small Fry", "any")
eq(w.rival, nil, "a guild under the encounter floor is not nominated")

-- A guild you have killed less but that has killed you more should still win, because a death
-- counts double. Eight of theirs down versus four kills on you plus one of theirs.
for i = 1, 8 do ns.Rival.NoteKill(nil, "Gentle Folk", "any") end
for i = 1, 4 do ns.Rival.NoteDeath("Actual Problem") end
ns.Rival.NoteKill(nil, "Actual Problem", "any")
w.since = ns.RIVAL.reviewAfter
ns.Rival.NoteKill(nil, "Actual Problem", "any")
eq(w.rival, ns.NormGuild("Actual Problem"), "the guild that keeps killing you is the rival, not the one you farm")

local f = w.feud[ns.NormGuild("Actual Problem")]
eq(f.theirs, 4, "deaths to them are recorded")
eq(f.mine, 2, "and kills on them")

-- ---------------------------------------------------------------------------
-- 7. The death heuristic only speaks when it actually knows something
-- ---------------------------------------------------------------------------
GodslayerDB.wide = nil
ns.Rival.NoteKill(nil, nil, nil)
w = GodslayerDB.wide

M.addUnit("target", { name = "Angry Boar", player = false, faction = "Alliance", combat = true })
M.fire("PLAYER_TARGET_CHANGED")
M.fire("PLAYER_DEAD")
eq(next(w.feud), nil, "dying to a boar blames no guild")

M.addUnit("target", { name = "Friendly Pal", guid = "Player-1-0000E001", guild = "The True Torchmen", faction = "Horde", player = true })
M.fire("PLAYER_TARGET_CHANGED")
M.fire("PLAYER_DEAD")
eq(next(w.feud), nil, "dying with a friendly targeted blames nobody")

local killer = enemy("Ganker Prime", "Actual Problem")
M.fire("PLAYER_DEAD")
local kf = w.feud[ns.NormGuild("Actual Problem")]
check(kf ~= nil and kf.theirs == 1, "dying with a hostile player of a known guild targeted credits them")

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
