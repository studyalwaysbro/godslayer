-- Offline tests for the cooldown ledger: lua tests/ledger.lua   (from the project root, Lua 5.1)
-- What an enemy has spent, what that cost them in their shared groups, and what is left.
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

local L, H = ns.Ledger, ns.Hype
check(L ~= nil, "the ledger loaded")
H.Opts().pack = "titan"

local PALLY = "Player-1-0000BBBB"
local SHAMAN = "Player-1-0000CCCC"

-- 1. the generated client data is what the ledger runs on ----------------------
check(ns.PVP ~= nil, "the generated PvP table is loaded")
check(ns.PVP_BUILD and ns.PVP_BUILD:match("^1%.60%."), "and it names the build it came from: " .. tostring(ns.PVP_BUILD))
eq(ns.PVP["Divine Shield"].cat, 37, "Divine Shield is in cooldown category 37")
eq(ns.PVP["Divine Shield"].catName, "Invulnerability", "which the client calls Invulnerability")
eq(ns.PVP["Ice Block"].cat, 37, "and Ice Block is in the same one")
eq(ns.PVP_BY_ID[642], "Divine Shield", "ids map back to names without asking the client")

local info = L.SpellInfo("Divine Shield")
eq(info.wait, 300, "a bubble is five minutes on this build")
eq(L.SpellInfo("Fireball"), nil, "a spell with no cooldown has no ledger entry to make")

-- 2. one cast, and what it cost them ------------------------------------------
local pally = M.addUnit("target", { name = "Holy Guy", guid = PALLY, class = "PALADIN", faction = "Alliance", level = 60 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 642)

check(L.Left(PALLY, "Divine Shield") > 295, "the bubble is on cooldown")
check(not L.Ready(PALLY, "Divine Shield"), "so it is not ready")

-- The whole point: they never cast Divine Protection, and it is down anyway.
local left, why, by = L.Left(PALLY, "Divine Protection")
check(left > 295, "Divine Protection is down too, having never been cast")
check(why and why:find("Invulnerability"), "because of the shared group: " .. tostring(why))
eq(by, "Divine Shield", "and the ledger names what spent it")

eq(L.Left(PALLY, "Lay on Hands"), 0, "a spell in another group is untouched")
eq(L.Left("Player-1-NOBODY", "Divine Shield"), 0, "a player never seen has nothing on cooldown")

-- 3. the shaman shock lockout, straight out of the client ----------------------
M.addUnit("target", { name = "Shock Guy", guid = SHAMAN, class = "SHAMAN", faction = "Alliance", level = 60 })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 8042) -- Earth Shock
local fl = L.Left(SHAMAN, "Frost Shock")
check(fl > 5 and fl <= 6, "an Earth Shock locks Frost Shock for six seconds (got " .. fl .. ")")
check(L.Left(SHAMAN, "Flame Shock") > 5, "and Flame Shock with it")
eq(L.Left(SHAMAN, "Divine Shield"), 0, "and nothing outside the group")

M.advance(7)
eq(L.Left(SHAMAN, "Frost Shock"), 0, "six seconds later the shock is back")

-- 4. a group lock is the casting spell's own number, not the group's ----------
-- Power Word: Shield locks category 56 for four seconds. Lay on Hands locks the same group for
-- twenty minutes. A ledger that stored one number per group would get one of them very wrong.
local PRIEST = "Player-1-0000DDDD"
M.addUnit("target", { name = "Shield Guy", guid = PRIEST, class = "PRIEST", faction = "Alliance" })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 17) -- Power Word: Shield
local shortLock = L.Left(PRIEST, "Lay on Hands")
check(shortLock > 0 and shortLock <= 4, "a shield locks the group for four seconds only (got " .. shortLock .. ")")

M.advance(5)
eq(L.Left(PRIEST, "Lay on Hands"), 0, "and it is gone five seconds later")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 633) -- Lay on Hands
check(L.Left(PRIEST, "Power Word: Shield") > 1100, "whereas a Lay on Hands locks it for twenty minutes")

-- 4b. the same group, two different locks, read off the client at 70707 ------
-- Frost Nova and Fire Nova are both in category 35. Frost Nova locks it for 25 seconds and
-- Fire Nova for 10, which is the per-spell rule again and the reason a group cannot be stored
-- as one number. A ledger that did would call a mage's nova back fifteen seconds early.
eq(ns.PVP["Frost Nova"].cat, 35, "Frost Nova is in cooldown category 35")
eq(ns.PVP["Fire Nova"].cat, 35, "and so is Fire Nova")
eq(ns.PVP["Frost Nova"].catCd, 25, "Frost Nova locks the group for 25 seconds")
eq(ns.PVP["Fire Nova"].catCd, 10, "and Fire Nova for 10")

local MAGE_FOE = "Player-1-0000FFFF"
M.addUnit("target", { name = "Nova Guy", guid = MAGE_FOE, class = "MAGE", faction = "Alliance" })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 122) -- Frost Nova
local novaLock = L.Left(MAGE_FOE, "Fire Nova")
check(novaLock > 24 and novaLock <= 25, "a Frost Nova locks the group for its own 25 (got " .. novaLock .. ")")
M.advance(26)
eq(L.Left(MAGE_FOE, "Fire Nova"), 0, "and it is clear 26 seconds later")

-- 5. only enemy players are written down --------------------------------------
local before = 0
for _ in pairs(GodslayerDB.cds) do before = before + 1 end

M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 642)
M.addUnit("target", { name = "Friend", guid = "Player-1-FRIEND", faction = "Horde" })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 642)
M.addUnit("target", { name = "Boar", guid = "Creature-1-1", faction = "Alliance", player = false })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 642)

local after = 0
for _ in pairs(GodslayerDB.cds) do after = after + 1 end
eq(after, before, "your own cast, a friendly's and a boar's are all ignored")

-- 6. the card ------------------------------------------------------------------
M.addUnit("target", pally)
local card = L.Card(PALLY)
eq(card.name, "Holy Guy", "the card knows whose it is")
eq(card.class, "PALADIN", "and their class")
check(#card.rows >= 2, "it lists the bubble and what shares its group (" .. #card.rows .. " rows)")
local seen = {}
for _, r in ipairs(card.rows) do seen[r.spell] = r end
check(seen["Divine Shield"], "Divine Shield is on the card")
check(seen["Divine Protection"], "and so is the one they never cast")
check(seen["Divine Shield"].major, "a five minute cooldown counts as major")
check(not seen["Divine Shield"].ready, "and it is not ready")

local line = L.Line(PALLY)
check(line and line:find("Divine Shield"), "the one-line summary names it: " .. tostring(line))
check(line:find("m"), "with a time on it")

-- Once everything is back up the line says so instead of listing nothing.
M.advance(400)
line = L.Line(PALLY)
check(line and line:find("up"), "when it is all back the line says so: " .. tostring(line))
check(L.Ready(PALLY, "Divine Shield"), "and the bubble is ready again")

-- A player with nothing notable has no line at all.
eq(L.Line("Player-1-NOBODY"), nil, "a stranger gets no line")

-- 7. formatting ----------------------------------------------------------------
eq(L.Short(0), "up", "zero reads as up")
eq(L.Short(-5), "up", "and so does a negative")
eq(L.Short(45), "45s", "under a minute is seconds")
eq(L.Short(60), "1m", "a round minute has no seconds on it")
eq(L.Short(125), "2m5s", "otherwise both")
eq(L.Short(3700), "1h1m", "over an hour reads in hours")

-- 8. it survives a reload ------------------------------------------------------
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 642)
local saved = GodslayerDB
local ns2 = M.load("Godslayer", FILES)
GodslayerDB = saved
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
check(ns2.Ledger.Left(PALLY, "Divine Shield") > 290, "the cooldown is still there after a reload")

-- 9. housekeeping --------------------------------------------------------------
GodslayerDB.cds["Player-1-ANCIENT"] = { t = time() - 40 * 86400, spells = {}, cats = {} }
local dropped = ns2.Ledger.Prune()
check(dropped >= 1, "a player not seen for over a month is forgotten")
eq(GodslayerDB.cds["Player-1-ANCIENT"], nil, "and is gone from the book")
check(GodslayerDB.cds[PALLY] ~= nil, "while a recent one is kept")

-- The book is capped, so a battleground weekend cannot grow it without limit.
for i = 1, 400 do
  GodslayerDB.cds["Player-1-FILL" .. i] = { t = time() - i, spells = {}, cats = {} }
end
ns2.Ledger.Prune()
local count = 0
for _ in pairs(GodslayerDB.cds) do count = count + 1 end
check(count <= 300, "the ledger is capped at three hundred players (got " .. count .. ")")

-- 10. a major with no aura to see is called out --------------------------------
local function title() return GodslayerHypeBanner and GodslayerHypeBanner.title.__text end
if GodslayerHypeBanner then GodslayerHypeBanner.title.__text = nil end
M.advance(10)
local ROGUE = "Player-1-0000EEEE"
M.addUnit("target", { name = "Stabby", guid = ROGUE, class = "ROGUE", faction = "Alliance" })
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 14185) -- Preparation, 600s, nothing to see on them
eq(title(), "PREPARATION", "a long cooldown with no aura is called")

-- Anything the aura layer already calls is left to it, so nothing is said twice.
if GodslayerHypeBanner then GodslayerHypeBanner.title.__text = nil end
M.advance(10)
M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, 1856) -- Vanish: Aura.DEFENCE has it
eq(title(), nil, "a cooldown the aura layer handles is not announced twice")
check(ns2.Ledger.Left(ROGUE, "Vanish") > 0, "but it is still written down")

-- 11. the commands that make any of this visible -------------------------------
local said = {}
local realPrint = print
print = function(...) local b = {} for i = 1, select("#", ...) do b[#b+1] = tostring((select(i, ...))) end said[#said+1] = table.concat(b, " ") end
local function spoke(fragment)
  for _, l in ipairs(said) do if l:find(fragment, 1, true) then return l end end
end
local function say(text) said = {}; SlashCmdList["GODSLAYER"](text) end

M.addUnit("target", pally)
say("cds")
check(spoke("Divine Shield"), "/godslayer cds lists the target's spent cooldowns")
check(spoke("Divine Protection"), "including the one they never cast")
check(spoke("spent by Divine Shield"), "and names what spent it")

say("cds Holy")
check(spoke("Divine Shield"), "a partial name finds them too")
say("cds Nobody At All")
check(spoke("Nothing on record"), "and an unknown name says so plainly")

M.units.target = nil
say("cds")
check(spoke("Target an enemy"), "with no target it asks for one")

say("dr")
check(spoke("diminishing returns on this build"), "/godslayer dr prints the build")
check(spoke("Polymorph"), "and the client's groups")
check(spoke("Entangling Roots"), "including the root group")

print = realPrint

eq(ns.errors, nil, "no handler errors in the ledger tests")

M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
