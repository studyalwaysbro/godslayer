-- Offline tests for the ladder: lua tests/rank.lua   (from the project root, Lua 5.1)
-- Fourteen rungs kept as renown on a major faction, two title families, and two number scales.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", race = "Scourge", sex = 2,
                      faction = "Horde", sex = 2, isMe = true })
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua",
                "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua",
                "Rival.lua", "Wheel.lua", "UI.lua" }

-- The character already holds rank 6 before the addon has ever run, which is the case that must
-- never produce a rank-up banner.
M.renown = { renownLevel = 6, renownReputationEarned = 1200, renownLevelThreshold = 3000 }
M.lifetimeHK, M.lifetimeBest = 4211, 9   -- enum 9 is rank 5, not rank 9
M.hk, M.dk = 12, 0
M.hkYesterday, M.dkYesterday = 31, 1
M.season, M.seasonEnds = 3, 14 * 86400

local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")

local R, H = ns.Rank, ns.Hype
check(R ~= nil, "the rank part loaded")
H.Opts().pack = "titan"

local function title() return GodslayerHypeBanner and GodslayerHypeBanner.title.__text end
local function clearBanner() if GodslayerHypeBanner then GodslayerHypeBanner.title.__text = nil end end

-- 1. the ladder's titles, and the family that is not it ------------------------
-- PVP_RANK_<enum>_<faction> is this ladder. PVP_RANK_<n>_NAME is the modern rated one. Rank 0 is
-- "Civilian" in both, which is exactly why the wrong family passes a casual look.
eq(R.Title(0, "Horde", 2), "Civilian", "rank 0 is Civilian")
eq(R.Title(1, "Horde", 2), "Scout", "rank 1 Horde is Scout")
eq(R.Title(2, "Horde", 2), "Grunt", "rank 2 Horde is Grunt")
eq(R.Title(14, "Horde", 2), "High Warlord", "rank 14 Horde is High Warlord")
eq(R.Title(1, "Alliance", 2), "Private", "rank 1 Alliance is Private")
eq(R.Title(14, "Alliance", 2), "Grand Marshal", "rank 14 Alliance is Grand Marshal")
check(R.Title(1, "Horde", 2) ~= PVP_RANK_1_NAME, "rank 1 is not the rated ladder's Combatant I")
eq(PVP_RANK_1_NAME, "Combatant I", "and that other family really is sitting there to be picked by mistake")
eq(R.Title(99, "Horde", 2), "High Warlord", "past the top it stays at the top")

-- The enum is the reason the keys are offset. Rank 1 reads PVP_RANK_5_0, not PVP_RANK_1_0.
eq(Enum.PvPRanks.Rank_1, 5, "Enum.PvPRanks.Rank_1 is 5 on this build")
eq(_G["PVP_RANK_" .. Enum.PvPRanks.Rank_1 .. "_0"], "Scout", "so rank 1 Horde is key PVP_RANK_5_0")

-- 2. reading the rung ----------------------------------------------------------
local now = R.Read()
check(now ~= nil, "the ladder reads")
eq(now.level, 6, "rank 6")
eq(now.points, 1200, "1200 points into it")
eq(now.threshold, 3000, "out of 3000")
eq(now.left, 1800, "so 1800 to go")

M.renownSecret = true
eq(R.Read(), nil, "a secret answer is no answer, not a zero")
M.renownSecret = nil

-- 3. the lifetime scale, which is the other one -------------------------------
-- GetPVPLifetimeStats hands back a PvPRanks enum value. renownLevel does not. Four apart.
local lt = R.Lifetime()
eq(lt.hk, 4211, "lifetime honorable kills come straight through")
eq(lt.best, 5, "enum 9 is rank 5, and a straight read would have called it rank 9")
eq(R.Title(lt.best, "Horde", 2), "First Sergeant", "which is First Sergeant, not Centurion")

eq(select(1, R.Today()), 12, "today's honorable kills")
eq(select(1, R.Yesterday()), 31, "yesterday's")
eq(select(2, R.Yesterday()), 1, "and yesterday's dishonorable one")

-- 4. honor off the wire, in every shape the client sends it --------------------
-- Patterns are built from the client's own format strings, so this works on a localised client.
local honor, victim = R.ParseHonor("Gnomechomsky dies (Honorable Kill: Grunt). You gain 31 Honor.")
eq(honor, 31, "an honorable kill carries its honor")
eq(victim, "Gnomechomsky", "and who it was")

honor, victim = R.ParseHonor("Gnomechomsky dies (Honorable Kill). You gain 31 Honor.")
eq(honor, 31, "the no-rank line reads too")
eq(victim, "Gnomechomsky", "and still names them")

honor, victim = R.ParseHonor("Gnomechomsky dies (Honorable Kill: Grunt). You gain 31 Honor (Rested 50% bonus).")
eq(honor, 31, "the rested line is not confused by its bonus clause")
eq(victim, "Gnomechomsky", "and keeps the victim")

honor, victim = R.ParseHonor("You have been awarded 25 Honor.")
eq(honor, 25, "an objective award is honor")
eq(victim, nil, "but it is nobody's death, so it is not a kill")

eq(R.ParseHonor("Vesh Torchman says hello"), nil, "an unrelated line is not honor")
eq(R.ParseDishonor("Farmer Dalson dies, dishonorable kill."), "Farmer Dalson", "a dishonorable kill is read")
eq(R.ParseDishonor("Gnomechomsky dies (Honorable Kill). You gain 31 Honor."), nil, "an honorable one is not")

-- 5. what it keeps -------------------------------------------------------------
local before = GodslayerDB.rank.honor
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Gnomechomsky dies (Honorable Kill: Grunt). You gain 31 Honor.")
eq(GodslayerDB.rank.honor, before + 31, "honor is added up")
eq(GodslayerDB.rank.kills, 1, "and the kill counted")
eq(R.session.honor, 31, "the session has it too")

M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 25 Honor.")
eq(GodslayerDB.rank.honor, before + 56, "an award adds honor")
eq(GodslayerDB.rank.kills, 1, "without adding a kill")

local day = GodslayerDB.rank.days
local keys = {}
for k in pairs(day) do keys[#keys + 1] = k end
eq(#keys, 1, "it is all filed under one day")
eq(day[keys[1]].honor, 56, "with the day's honor")
eq(day[keys[1]].kills, 1, "and the day's kills")

-- 6. a dishonorable kill is the only thing here that can cost you a rung -------
clearBanner()
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Farmer Dalson dies, dishonorable kill.")
eq(title(), "DISHONORABLE", "a dishonorable kill is called out")
eq(GodslayerDB.rank.dks, 1, "and written down")
eq(R.session.dk, 1, "and counted for the session")

-- 7. moving rungs --------------------------------------------------------------
-- Nothing was announced at login, because the rank was already held.
eq(R.Check(false), nil, "a rank that has not moved is not a change")

clearBanner()
M.renown = { renownLevel = 7, renownReputationEarned = 0, renownLevelThreshold = 4000 }
M.fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2800)
eq(title(), "BLOOD GUARD", "rank 7 Horde announces itself by name")
eq(GodslayerDB.rank.level, 7, "and is remembered")
eq(GodslayerDB.rank.best, 7, "and is the best so far")

-- Another faction's renown is not the ladder.
clearBanner()
M.renown = { renownLevel = 8, renownReputationEarned = 0, renownLevelThreshold = 5000 }
M.fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2507)
eq(title(), nil, "renown on some other faction is not a rank")
eq(GodslayerDB.rank.level, 7, "and does not move the rung")

M.fire("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", 2800)
eq(GodslayerDB.rank.level, 8, "the right faction does")

-- Down again: dishonorable kills can take a rung off, so the drop has to be sayable.
clearBanner()
M.renown = { renownLevel = 7, renownReputationEarned = 200, renownLevelThreshold = 4000 }
local dir, to, from = R.Check(true)
eq(dir, "down", "a lost rung is a change downward")
eq(to, 7, "to rank 7")
eq(from, 8, "from rank 8")
eq(title(), "RANK LOST", "and it says so")
eq(GodslayerDB.rank.best, 8, "while the best ever held is kept")

-- 8. the pace, and the honesty about not having one ---------------------------
local card = R.Card()
eq(card.level, 7, "the card knows the rung")
eq(card.title, "Blood Guard", "and its name")
eq(card.next, "Legionnaire", "and what the next one is called")
eq(card.left, 3800, "and what is left")
check(card.lifetime.best == 5, "and the lifetime best on the right scale")
eq(card.season, 3, "and the season")

M.advance(1800)
card = R.Card()
check(card.rate and card.rate > 0, "with honor earned and time passed there is a rate")
check(card.killsLeft and card.killsLeft > 0, "and an estimate in kills: " .. tostring(card.killsLeft))

-- 9. the command ---------------------------------------------------------------
local said = {}
local realPrint = print
print = function(...) local b = {} for i = 1, select("#", ...) do b[#b+1] = tostring((select(i, ...))) end said[#said+1] = table.concat(b, " ") end
local function spoke(fragment)
  for _, l in ipairs(said) do if l:find(fragment, 1, true) then return l end end
end
local function say(text) said = {}; SlashCmdList["GODSLAYER"](text) end

say("rank")
check(spoke("Rank 7 of 14"), "/godslayer rank gives the rung out of fourteen")
check(spoke("Blood Guard"), "by name")
check(spoke("Rank points"), "with the points inside it")
check(spoke("Legionnaire"), "and what is next")
check(spoke("4211"), "and the lifetime kills")
check(spoke("dishonorable"), "and the dishonorable kills it has seen")
check(spoke("Season 3"), "and the season countdown")

-- A client that will not answer is said so, not guessed at.
M.renownSecret = true
say("rank")
check(spoke("will not tell me your rank"), "a client that refuses gets an honest answer")
M.renownSecret = nil

print = realPrint

-- 10. housekeeping -------------------------------------------------------------
for i = 1, 40 do GodslayerDB.rank.days["2026-01-" .. string.format("%02d", i % 28 + 1) .. "-" .. i] = { honor = 1, kills = 0, dk = 0 } end
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 1 Honor.")
local n = 0
for _ in pairs(GodslayerDB.rank.days) do n = n + 1 end
check(n <= 30, "the day book is capped at thirty days (got " .. n .. ")")

eq(ns.errors, nil, "no handler errors in the rank tests")

M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
