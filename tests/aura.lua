-- Offline tests for the aura layer: lua tests/aura.lua   (from the project root, Lua 5.1)
-- What is on you, what is on them, and the diminishing returns this server is measured to have.
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

local A, H = ns.Aura, ns.Hype
check(A ~= nil, "the aura module loaded")
H.Opts().pack = "titan"

M.spells = M.spells or {}
local function title() return GodslayerHypeBanner and GodslayerHypeBanner.title.__text end
local function line() return GodslayerHypeBanner and GodslayerHypeBanner.line.__text or "" end
local function clearBanner()
  if GodslayerHypeBanner then GodslayerHypeBanner.title.__text = nil; GodslayerHypeBanner.line.__text = nil end
end

-- Every call is throttled on purpose, so the clock moves between the things being tested.
local function later(seconds)
  M.advance(seconds or 7)
  clearBanner()
end

-- 1. the module knows the charter of spells it is meant to ---------------------
eq(A.CC["Hammer of Justice"].cat, "stun", "Hammer of Justice is a stun")
eq(A.CC["Polymorph"].cat, "incap", "Polymorph is an incapacitate")
eq(A.CC["Death Coil"].cat, "horror", "Death Coil is its own thing, not a plain fear")
eq(A.DEFENCE["Ice Block"].kind, "immune", "Ice Block means stop casting")
eq(A.DEFENCE["Shield Wall"].kind, "soak", "Shield Wall only makes it cost more")
eq(A.DEFENCE["Vanish"].kind, "gone", "Vanish means they are not there")
eq(A.OFFENCE["Recklessness"].words, "RECKLESS", "Recklessness has words")
check(A.OFFENCE["Ice Block"] == nil, "a defensive is not also an offensive")

local cats = {}
for _, info in pairs(A.CC) do cats[info.cat] = true end
for _, cat in ipairs({ "stun", "fear", "incap", "root", "disorient", "silence", "charm", "snare" }) do
  check(cats[cat], "something covers the " .. cat .. " category")
end

-- 2. crowd control landing on you ---------------------------------------------
local enemy = M.addUnit("target", { name = "Bad Guy", guid = "Player-1-0000BBBB", class = "PALADIN", faction = "Alliance", level = 60 })
M.addUnit("nameplate1", enemy)

M.aura("player", "HARMFUL", "Hammer of Justice", 853, 6, "target")
M.fire("UNIT_AURA", "player")
eq(title(), "STUNNED", "a stun on you is called")
check(line():find("Bad Guy", 1, true), "and names who did it: " .. line())
check(line():find("6s", 1, true), "and how long for: " .. line())
check((ns.char.ccSeconds or 0) >= 6, "the seconds you could not act are counted")
eq(ns.char.ccCount, 1, "and so is the number of times")

-- The same aura is not called twice while it is still the same aura.
later(1)
M.fire("UNIT_AURA", "player")
eq(title(), nil, "the same stun is not called again a second later")

-- A different category is called in its own words.
later()
M.clearAuras("player")
M.aura("player", "HARMFUL", "Polymorph", 118, 10, "target")
M.fire("UNIT_AURA", "player")
eq(title(), "INCAPACITATED", "a sheep is called as an incapacitate")

later()
M.clearAuras("player")
M.aura("player", "HARMFUL", "Psychic Scream", 8122, 8)
M.fire("UNIT_AURA", "player")
eq(title(), "FEARED", "a scream is a fear")
check(line():find("Something", 1, true), "an unknown caster is still called: " .. line())

-- 3. their defence ------------------------------------------------------------
later()
M.clearAuras("player")
M.aura("target", "HELPFUL", "Ice Block", 11958, 10)
M.fire("UNIT_AURA", "target")
eq(title(), "ICE BLOCK", "their Ice Block is called")
check(line():find("Bad Guy", 1, true), "with whose it is: " .. line())

later()
M.clearAuras("target")
M.aura("target", "HELPFUL", "Blessing of Protection", 1022, 10)
M.fire("UNIT_AURA", "target")
eq(title(), "HAND OF PROTECTION", "Hand of Protection is called")
check(line():find("physical only", 1, true), "and says what it does not stop: " .. line())

-- 4. their offence outranks their defence -------------------------------------
later()
M.clearAuras("target")
M.aura("target", "HELPFUL", "Shield Wall", 871, 10)
M.aura("target", "HELPFUL", "Recklessness", 1719, 15)
M.fire("UNIT_AURA", "target")
eq(title(), "RECKLESS", "with both up, the one with a countdown on your life is called")

-- 5. a unit that is not an enemy player is left alone -------------------------
later()
M.clearAuras()
local friend = M.addUnit("target", { name = "Friendly", guid = "Player-1-0000CCCC", faction = "Horde" })
M.aura("target", "HELPFUL", "Recklessness", 1719, 15)
M.fire("UNIT_AURA", "target")
eq(title(), nil, "a friendly unit's cooldowns are not called")

M.addUnit("target", { name = "Critter", guid = "Creature-1-1", faction = "Alliance", player = false })
M.aura("target", "HELPFUL", "Recklessness", 1719, 15)
M.fire("UNIT_AURA", "target")
eq(title(), nil, "and neither are a non-player's")

M.addUnit("target", enemy)

-- 6. a value the client refuses to hand over stops the read -------------------
later()
M.clearAuras()
M.auras.target = { HELPFUL = { { secret = true }, { name = "Recklessness", spellId = 1719, duration = 15, expirationTime = M.now + 15 } } }
M.fire("UNIT_AURA", "target")
eq(title(), nil, "a secret row stops the list rather than being guessed past")
eq(#A.Read("target", "HELPFUL"), 0, "and the reader returns nothing for it")
eq(ns.errors, nil, "and nothing errored")

-- The list also stops at the first gap, so a half-sent roster cannot read as a short one.
M.clearAuras()
M.auras.target = { HELPFUL = { nil, { name = "Ice Block", spellId = 11958, duration = 5, expirationTime = M.now + 5 } } }
eq(#A.Read("target", "HELPFUL"), 0, "the read stops at the first missing row")

-- 7. diminishing returns, measured ---------------------------------------------
later()
M.clearAuras()
M.spells[122] = "Frost Nova"
M.addUnit("target", enemy)

local function land(spellId, name, seconds)
  M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, spellId)
  M.clearAuras("target")
  M.aura("target", "HARMFUL", name, spellId, seconds)
  M.advance(0.2)
  M.fire("UNIT_AURA", "target")
end

-- The groups come from the client, and four of them are not what a person would assume.
eq(A.DRGroup("Frost Nova"), A.DRGroup("Entangling Roots"), "Frost Nova and Roots share a group")
eq(A.DRGroup("Cheap Shot"), A.DRGroup("Hammer of Justice"), "Cheap Shot shares with Hammer of Justice")
check(A.DRGroup("Kidney Shot") ~= A.DRGroup("Cheap Shot"), "but Kidney Shot is its own group on this build")
eq(A.DRGroup("Seduction"), A.DRGroup("Fear"), "Seduction diminishes with fears, not with charms")
eq(A.DRGroup("Scatter Shot"), A.DRGroup("Polymorph"), "Scatter Shot diminishes with Polymorph")
eq(A.DRGroup("Blind"), 0, "and Blind does not diminish at all on this build")

-- Build 70707 put two of Forever's own spells into the Polymorph group, which took it from
-- eight members to ten. Chastise is the one that matters to a mage: a priest landing it eats
-- into the same diminishing returns as your sheep, and nothing says so in game.
eq(A.DRGroup("Chastise"), A.DRGroup("Polymorph"), "Forever's Chastise diminishes with Polymorph")
eq(A.DRGroup("Confounding Flash"), A.DRGroup("Polymorph"), "and so does Confounding Flash")
eq((ns.DR_GROUPS[A.DRGroup("Polymorph")] or {}).members, 10, "which makes ten in that group")
eq(A.DRGroup("Not A Spell"), 0, "an unknown spell has no group")
eq(A.GroupLabel(0), "no group", "group zero is named for what it is")
eq(A.GroupLabel(A.DRGroup("Polymorph")), "Polymorph", "a group is named after a member you know")

local ROOT = A.DRGroup("Frost Nova")
check(ROOT > 0, "roots are a real group")

land(122, "Frost Nova", 8)
local rows = A.DRTable()
local root
for _, r in ipairs(rows) do if r.group == ROOT then root = r end end
check(root ~= nil, "the first root was written down")
eq(root.total, 1, "one observation so far")
eq(root.steps[1].median, 8, "and it lasted the full eight seconds")
eq(root.label, "Entangling Roots", "the row is labelled from the client's group")

-- A second root moments later comes back shorter, which is the thing worth knowing.
clearBanner()
M.advance(3)
land(122, "Frost Nova", 4)
eq(title(), "DIMINISHED", "the shortened root is called")
check(line():find("50%", 1, true), "with the share it kept: " .. line())

M.advance(3)
land(122, "Frost Nova", 2)
rows = A.DRTable()
for _, r in ipairs(rows) do if r.group == ROOT then root = r end end
eq(root.total, 3, "three observations")
eq(root.steps[2].median, 4, "the second lasted four")
eq(root.steps[3].median, 2, "the third lasted two")
eq(root.steps[2].share, 0.5, "half on the second")
eq(root.steps[3].share, 0.25, "a quarter on the third")

-- Past the window the game forgets, and the next one is full length again.
M.advance(60)
land(122, "Frost Nova", 8)
rows = A.DRTable()
for _, r in ipairs(rows) do if r.group == ROOT then root = r end end
eq(root.steps[1].count, 2, "a root after the window counts as a first again")

local widest = A.DRWindow()
check(widest and widest >= 3, "the window learned from what was seen is at least the gap that diminished: " .. tostring(widest))

-- Nothing is recorded for a cast that never landed.
local before = #GodslayerDB.dr[ROOT]
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 122)
M.clearAuras("target")
M.advance(0.2)
M.fire("UNIT_AURA", "target")
eq(#GodslayerDB.dr[ROOT], before, "a crowd control that did not land is not an observation")

-- A spell that is not crowd control is not tracked at all.
M.spells[133] = "Fireball"
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 133)
M.clearAuras("target")
M.aura("target", "HARMFUL", "Fireball", 133, 8)
M.advance(0.2)
M.fire("UNIT_AURA", "target")
eq(GodslayerDB.dr[A.DRGroup("Fireball")], nil, "a Fireball is not a diminishing category at all")

-- 8. a client in another language ---------------------------------------------
M.spells[853] = "Hammer der Gerechtigkeit"
A.Init()
eq(A.alias["Hammer der Gerechtigkeit"], "Hammer of Justice", "the local name is learned from the id")
later()
M.clearAuras()
M.aura("player", "HARMFUL", "Hammer der Gerechtigkeit", 853, 6, "target")
M.fire("UNIT_AURA", "player")
eq(title(), "STUNNED", "and a German stun is still a stun")

-- 9. the switch ---------------------------------------------------------------
later()
M.clearAuras()
H.Opts().aura = false
M.aura("player", "HARMFUL", "Polymorph", 118, 10, "target")
M.fire("UNIT_AURA", "player")
eq(title(), nil, "with the aura calls off, nothing is called")
H.Opts().aura = true

later()
M.clearAuras()
H.Opts().on = false
M.aura("player", "HARMFUL", "Polymorph", 118, 10, "target")
M.fire("UNIT_AURA", "player")
eq(title(), nil, "and the master switch still turns it all off")
H.Opts().on = true

-- 10. housekeeping -------------------------------------------------------------
later()
M.clearAuras()
M.fire("PLAYER_ENTERING_WORLD")
eq(title(), nil, "changing world says nothing")
M.advance(200)
check(A.Sweep() >= 0, "the sweep runs and returns a count")

-- Nothing in any of that reached the error log.
eq(ns.errors, nil, "no handler errors in the aura tests")

M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
