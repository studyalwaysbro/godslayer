-- Godslayer in a battleground: lua tests/field.lua
--
-- The whole point of this file is the seal. `C_PvP.GetScoreInfo` carries
-- `SecretInActivePvPMatch`, so while the match is running every number on the scoreboard is a
-- secret value and only seven fields come through. The mock models that, which is what makes
-- these assertions mean something: a read that quietly turned a secret into zero would pass a
-- mock that handed over plain numbers, and would ship a battleground report full of noughts.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function near(a, b, label) check(type(a) == "number" and math.abs(a - b) < 0.05, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen",
                      class = "MAGE", race = "Scourge", sex = 2, faction = "Horde", isMe = true })
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua",
                "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua",
                "Control.lua", "Death.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local F = ns.Field
local function say(text) SlashCmdList["GODSLAYER"](text) end
local function printed() return table.concat(M.printed, "\n") end

-- Horde, so my faction index is 0 and theirs is 1. The client's own scoreboard treats 1 as
-- Alliance, which is the only reason that direction is fixed rather than guessed.
local US, THEM = 0, 1

local ROWS = {
  -- mine
  { name = "Vesh Torchman", faction = US, race = "Undead",  gender = 2, class = "Mage",    token = "MAGE",    rank = 6,
    guid = ME, kb = 7, hk = 21, deaths = 2, honor = 340, damage = 128400, healing = 0,
    stats = { { name = "Flag Captures", value = 1 }, { name = "Flag Returns", value = 0 } } },
  { name = "Grimfang",      faction = US, race = "Orc",     gender = 2, class = "Warrior", token = "WARRIOR", rank = 4,
    guid = "Player-1-0000B001", kb = 3, hk = 14, deaths = 5, honor = 180, damage = 96000, healing = 0 },
  { name = "Softhands",     faction = US, race = "Troll",   gender = 3, class = "Priest",  token = "PRIEST",  rank = 2,
    guid = "Player-1-0000B002", kb = 0, hk = 9,  deaths = 1, honor = 150, damage = 4000, healing = 212000 },
  { name = "Freshmeat",     faction = US, race = "Tauren",  gender = 2, class = "Druid",   token = "DRUID",   rank = 0,
    guid = "Player-1-0000B003", kb = 0, hk = 2,  deaths = 7, honor = 20,  damage = 1200, healing = 8000 },
  -- theirs
  { name = "Sir Problem",   faction = THEM, race = "Human",    gender = 2, class = "Paladin", token = "PALADIN", rank = 11,
    guid = "Player-1-0000C001", kb = 12, hk = 30, deaths = 1, honor = 520, damage = 88000, healing = 140000,
    stats = { { name = "Flag Captures", value = 2 }, { name = "Flag Returns", value = 3 } } },
  { name = "Tiny Problem",  faction = THEM, race = "Gnome",    gender = 2, class = "Mage",    token = "MAGE",    rank = 9,
    guid = "Player-1-0000C002", kb = 9,  hk = 26, deaths = 3, honor = 480, damage = 171000, healing = 0 },
  { name = "Shadowmelder",  faction = THEM, race = "Night Elf", gender = 3, class = "Druid",  token = "DRUID",   rank = 7,
    guid = "Player-1-0000C003", kb = 2,  hk = 18, deaths = 2, honor = 300, damage = 30000, healing = 96000 },
  { name = "Nobody Yet",    faction = THEM, race = "Dwarf",    gender = 2, class = "Hunter",  token = "HUNTER",  rank = 0,
    guid = "Player-1-0000C004", kb = 0,  hk = 1,  deaths = 6, honor = 10,  damage = 900, healing = 0 },
}

-- ---------------------------------------------------------------------------
-- 1. Not in a battleground
-- ---------------------------------------------------------------------------
eq(F.In(), false, "no match means not in one")
eq(F.Sealed(), false, "and nothing is sealed")
local board, why = F.Board()
eq(board, nil, "and there is no board")
eq(why, "you are not in a battleground", "with the reason said plainly")

M.printed = {}
say("field")
check(printed():find("not in a battleground", 1, true), "the command says so too: " .. printed())

-- ---------------------------------------------------------------------------
-- 2. The seal
-- ---------------------------------------------------------------------------
M.battleground({ rows = ROWS, cols = { "Flag Captures", "Flag Returns" } })
M.fire("PLAYER_JOINED_PVP_MATCH")

eq(F.In(), true, "joining puts us in a match")
eq(F.Complete(), false, "which is not over")
eq(F.Sealed(), true, "so the numbers are sealed")

board = F.Board()
check(board ~= nil, "there is a board during the match")
eq(board.sealed, true, "and it knows it is sealed")
eq(#board.us, 4, "four on my side")
eq(#board.them, 4, "four on theirs")
eq(#board.unknown, 0, "and nobody unplaced")
eq(board.factional, true, "the client says the match is factional, which is what makes the faction split safe")

-- The seven that survive, and the ones that do not. nil here is the honest answer and must never
-- be a zero: a sealed scoreboard reported as noughts is worse than no report.
local theirs = board.them[1]
eq(theirs.name, "Sir Problem", "a name comes through the seal")
eq(theirs.faction, THEM, "and a faction")
eq(theirs.race, "Human", "and a race")
eq(theirs.token, "PALADIN", "and a class token")
eq(theirs.class, "Paladin", "and the localised class name")
eq(theirs.gender, 2, "and a gender, which the title needs")
eq(theirs.rank, 11, "and honorLevel, which in Camelot is the rank")
eq(theirs.kb, nil, "killing blows are sealed")
eq(theirs.hk, nil, "honorable kills are sealed")
eq(theirs.deaths, nil, "deaths are sealed")
eq(theirs.honor, nil, "honor is sealed")
eq(theirs.damage, nil, "damage is sealed")
eq(theirs.healing, nil, "healing is sealed")
eq(theirs.guid, nil, "and the guid is sealed too, which is why a live roster cannot be keyed by it")

-- The objective columns are a different case: which ones this battleground scores is public, and
-- only the values are hidden.
check(type(theirs.stats) == "table" and #theirs.stats == 2, "the stat columns come through")
eq(theirs.stats[1].name, "Flag Captures", "named")
eq(theirs.stats[1].value, nil, "with the value sealed")
check(board.cols and #board.cols == 2 and board.cols[1] == "Flag Captures", "and the match's own column list is readable")

-- ---------------------------------------------------------------------------
-- 3. The rank is a rank, and gets the right ladder
-- ---------------------------------------------------------------------------
eq(theirs.title, "Commander", "an Alliance rank 11 is a Commander")
eq(board.them[2].title, "Knight-Champion", "and rank 9 a Knight-Champion")
eq(board.me.title, "Stone Guard", "my own rank 6 is read off the Horde ladder")
check(board.me.title ~= "Challenger I", "and never off the modern rated family")

-- A rank 0 player is ranked nowhere and is deliberately not titled, because PVP_RANK_0_NAME is
-- "Civilian" in both families and saying it would be the one place the wrong family looks right.
eq(board.them[4].rank, 0, "an unranked player reads as 0")
eq(board.them[4].title, nil, "and gets no title")

-- A honorLevel past the fourteenth rung is not a Camelot rank. On a standard client it is the
-- modern honor level, which runs into the hundreds; titling it would invent a rung.
M.battleground({ rows = { { name = "Retail Leak", faction = THEM, gender = 2, token = "ROGUE", rank = 262 } } })
local leak = F.Board()
eq(leak.them[1].rank, nil, "a honorLevel past 14 is not treated as a rank")
eq(leak.them[1].title, nil, "and is not titled")

-- ---------------------------------------------------------------------------
-- 4. What a side amounts to
-- ---------------------------------------------------------------------------
M.battleground({ rows = ROWS, cols = { "Flag Captures", "Flag Returns" } })
board = F.Board()
local us, them = F.Shape(board.us), F.Shape(board.them)

eq(us.n, 4, "my side is four")
eq(us.classes.MAGE, 1, "one mage")
eq(us.classes.PRIEST, 1, "one priest")
eq(us.healers, 2, "two of mine are in a class that can heal")
eq(them.healers, 2, "and two of theirs")

-- The average is over the players who have a rung, not over the side. A rank 0 recruit and a
-- player the client declined to rank are different facts and neither is a zero to average in.
eq(us.ranked, 3, "three of mine are on the ladder")
near(us.avg, 4, "my side averages rank 4 over those three")
eq(them.ranked, 3, "three of theirs")
near(them.avg, 9, "and they average 9")
eq(them.top.name, "Sir Problem", "their highest rung is the paladin")
eq(them.top.rank, 11, "at rank 11")

eq(them.ladder[1].name, "Sir Problem", "the ladder is sorted highest first")
eq(them.ladder[3].name, "Shadowmelder", "down to the lowest ranked")
eq(#them.ladder, 3, "and the unranked are not on it")

-- ---------------------------------------------------------------------------
-- 5. The dossier, by name, because the scoreboard has no guild column
-- ---------------------------------------------------------------------------
ns.char.victims["Player-1-0000C002"] = { name = "Tiny Problem", kills = 5, guild = "Random Strangers" }
ns.char.victims["Player-1-0000C009"] = { name = "Never Met", kills = 3 }
local known = F.Known(board.them)
eq(#known, 1, "one name on their side is in the dossier")
eq(known[1].name, "Tiny Problem", "and it is the one actually standing here")
eq(known[1].kills, 5, "with the count you have on them")

-- A partial name must not be mistaken for a match: FindVictim answers prefixes, and "Sir Problem"
-- is not "Tiny Problem" however much the dossier wants to be helpful.
ns.char.victims["Player-1-0000C002"] = nil
ns.char.victims["Player-1-0000C009"] = nil
eq(#F.Known(board.them), 0, "an empty dossier matches nobody")

-- ---------------------------------------------------------------------------
-- 6. The scouting report
-- ---------------------------------------------------------------------------
M.battleground({ rows = ROWS, cols = { "Flag Captures" } })
M.printed = {}
-- Zoning into a battleground is a world change, and the addon treats it as a new match: without
-- that, a match left early is never closed and the next one inherits its scouted flag.
M.fire("PLAYER_ENTERING_WORLD")
M.fire("PLAYER_JOINED_PVP_MATCH")
check(M.bgRequests >= 1, "joining asks the client for the scoreboard at once")

M.fire("UPDATE_BATTLEFIELD_SCORE")
local report = printed()
check(report:find("sealed", 1, true), "the report leads with the seal: " .. report)
check(report:find("average rank 9.0", 1, true), "and gives their ladder average")
check(report:find("Sir Problem", 1, true), "and names their highest rung")
check(report:find("5.0 rungs above you", 1, true), "and says how far above you they are")
check(report:find("2 of them can heal", 1, true), "and counts the classes that can heal")
check(report:find("Flag Captures", 1, true), "and says what this one scores")

-- Said once. A battleground sends UPDATE_BATTLEFIELD_SCORE constantly and a report on each would
-- be the addon shouting over the match it is describing.
M.printed = {}
M.fire("UPDATE_BATTLEFIELD_SCORE")
M.fire("UPDATE_BATTLEFIELD_SCORE")
eq(printed(), "", "and only once per match")

-- The next battleground of the night is a new battleground. This is the bug the lifecycle had:
-- a match left early never reports itself complete, so without a reset on the world change the
-- stale match survived, `startMatch` returned at its own guard, and the second report never came.
M.bgLeave()
M.battleground({ rows = ROWS, cols = { "Flag Captures" } })
M.fire("PLAYER_ENTERING_WORLD")
M.fire("PLAYER_JOINED_PVP_MATCH")
M.printed = {}
M.fire("UPDATE_BATTLEFIELD_SCORE")
check(printed():find("average rank 9.0", 1, true), "the next battleground gets its own report: " .. printed())

-- With nobody read on the other side there is nothing to report, and nothing is said.
M.bgLeave()
M.battleground({ rows = { ROWS[1], ROWS[2] } })
M.fire("PLAYER_ENTERING_WORLD")
M.printed = {}
M.fire("UPDATE_BATTLEFIELD_SCORE")
eq(printed(), "", "a roster with only your own side says nothing yet")
local ok, scoutWhy = F.Scout()
eq(ok, nil, "and scouting declines")
eq(scoutWhy, "the other side has not been read yet", "with the reason")

-- ---------------------------------------------------------------------------
-- 7. The seal lifts, all at once
-- ---------------------------------------------------------------------------
M.bgLeave()
M.battleground({ rows = ROWS, cols = { "Flag Captures", "Flag Returns" } })
M.fire("PLAYER_JOINED_PVP_MATCH")

local no, noWhy = F.Finish()
eq(no, nil, "a finish asked for mid-match gets nothing")
eq(noWhy, "the match is not over, so the numbers are still sealed", "and says why")

M.bgComplete(US, 1080)
eq(F.Sealed(), false, "the match being over lifts the seal")
eq(F.Complete(), true, "and it knows it is over")

M.printed = {}
M.fire("PVP_MATCH_COMPLETE")
eq(printed(), "", "nothing is read inside the handler: the client is still rebuilding its own table")
M.advance(1.2)
local card = GodslayerDB.field.last
check(card ~= nil, "a card lands one tick later")
eq(card.won, true, "we won, because the winner is our faction index")
eq(card.us, 4, "four of ours")
eq(card.them, 4, "four of theirs")
eq(card.duration, 1080, "and the match's own duration")

eq(card.me.kb, 7, "my killing blows arrive")
eq(card.me.hk, 21, "and honorable kills")
eq(card.me.deaths, 2, "and deaths")
eq(card.me.honor, 340, "and honor")
eq(card.me.damage, 128400, "and damage")

-- Placement counts every row the client gave a number for, both sides, because being fourth of
-- eight in a battleground is the honest answer and being first of four is not.
eq(card.me.kbOf, 8, "placement counts all eight rows")
eq(card.me.kbPlace, 3, "and puts me third on killing blows")
eq(card.me.dmgPlace, 2, "second on damage")
-- Zero healing is a number the client handed over, not an absence, so it places honestly: fifth
-- of the eight, behind the four who healed anything. What the card must not do is say it.
eq(card.me.healPlace, 5, "zero healing still places, because zero is an answer")
eq(card.me.healOf, 8, "out of the eight")

check(card.me.objectives ~= nil and #card.me.objectives == 1, "only objectives I actually scored are kept")
eq(card.me.objectives[1].name, "Flag Captures", "named")
eq(card.me.objectives[1].value, 1, "with the value, now that it is unsealed")

eq(card.theirBest.name, "Sir Problem", "their best killer is named")
eq(card.theirBest.kb, 12, "with the count")
eq(card.theirBest.rank, 11, "and the rung they did it from")

local said = printed()
check(said:find("Won", 1, true), "the card says we won: " .. said)
check(said:find("7 killing blows", 1, true), "and what I did")
check(said:find("3 of 8 on killing blows", 1, true), "and where that placed me")
check(not said:find("on healing", 1, true), "and does not report a healing placing I did not earn")
check(said:find("Flag Captures 1", 1, true), "and the objective")
check(said:find("Their best was Sir Problem at rank 11, 12 killing blows", 1, true), "and theirs")

-- A loss reads as a loss rather than as an absent win.
M.bgLeave()
M.battleground({ rows = ROWS })
M.fire("PLAYER_JOINED_PVP_MATCH")
M.bgComplete(THEM, 600)
M.printed = {}
M.fire("PVP_MATCH_COMPLETE") M.advance(1.2)
eq(GodslayerDB.field.last.won, false, "losing is recorded as a loss")
check(printed():find("Lost", 1, true), "and said as one")

-- No winner given at all is neither: the card holds nil and says "Match".
M.bgLeave()
M.battleground({ rows = ROWS })
M.fire("PLAYER_JOINED_PVP_MATCH")
M.bgComplete(nil, 300)
M.printed = {}
M.fire("PVP_MATCH_COMPLETE") M.advance(1.2)
eq(GodslayerDB.field.last.won, nil, "no winner is not a loss")
check(printed():find("Match in", 1, true) or printed():find("Match at", 1, true) or printed():find("Match:", 1, true),
  "and is not announced as either: " .. printed())

-- ---------------------------------------------------------------------------
-- 8. The command
-- ---------------------------------------------------------------------------
M.bgLeave()
M.battleground({ rows = ROWS, cols = { "Flag Captures" } })
M.fire("PLAYER_JOINED_PVP_MATCH")

M.printed = {}
say("field them")
local roster = printed()
check(roster:find("Theirs, 4 players", 1, true), "their roster gives the head count: " .. roster)
check(roster:find("11 Sir Problem", 1, true), "with the top rung first")
check(roster:find("Commander", 1, true), "and the title")
check(roster:find("unranked: Nobody Yet", 1, true), "and the unranked listed apart")

M.printed = {}
say("field us")
check(printed():find("Yours, 4 players", 1, true), "and my own side on request")

M.printed = {}
say("field")
check(printed():find("average rank 9.0", 1, true), "the bare command gives both sides")

M.printed = {}
say("field last")
check(printed():find("Match", 1, true) or printed():find("Won", 1, true) or printed():find("Lost", 1, true),
  "and the book holds the last finished match: " .. printed())

-- ---------------------------------------------------------------------------
-- 9. A board that cannot be split is not reported
-- ---------------------------------------------------------------------------
M.bgLeave()
M.battleground({ rows = { { name = "Faceless One", gender = 2, token = "ROGUE", rank = 3 } } })
local split, splitWhy = F.Board()
eq(split, nil, "a scoreboard with no faction on it is refused")
eq(splitWhy, "the client would not say which side anyone is on",
  "rather than reporting the enemy's ladder using your own team's ranks")

M.bgLeave()
M.battleground({ rows = {} })
local empty, emptyWhy = F.Board()
eq(empty, nil, "an empty scoreboard is refused")
eq(emptyWhy, "the scoreboard has not arrived yet", "as not-yet rather than as nobody")

-- ---------------------------------------------------------------------------
-- 10. The polling, and the throttle
-- ---------------------------------------------------------------------------
M.bgLeave()
M.battleground({ rows = ROWS })
M.fire("PLAYER_ENTERING_WORLD")
M.fire("PLAYER_JOINED_PVP_MATCH")
M.advance(6)                       -- past the floor the join itself set
local at = M.bgRequests
F.Tick()
eq(M.bgRequests, at + 1, "a tick asks for the scoreboard")
F.Tick() F.Tick()
eq(M.bgRequests, at + 1, "and two more in the same second do not")
-- The floor is five seconds and the ticker runs every ten, so a tick is never thrown away by the
-- throttle meant to protect it. First the floor itself, then the ticker on its own: an eleven
-- second window always contains a firing of a ten second ticker, whatever its phase, so this is
-- the assertion that would have caught the beat the two numbers were set to avoid.
M.advance(6)
F.Tick()
eq(M.bgRequests, at + 2, "and one six seconds later does")
-- Sixteen seconds rather than eleven, and the arithmetic is the point. The ticker's phase is
-- whatever it was when the addon loaded, so one period is not enough to promise a firing that
-- also clears a five second floor. Two periods always are: of two firings ten seconds apart, one
-- must land at least five seconds in. That only holds because the floor is under the period, and
-- that is the property these two constants exist to keep.
local ticked = M.bgRequests
M.advance(16)
check(M.bgRequests > ticked, "and the ticker asks on its own without being called")

M.bgLeave()
M.fire("PLAYER_ENTERING_WORLD")
local idle = M.bgRequests
M.advance(6)
F.Tick() F.Tick()
eq(M.bgRequests, idle, "and nothing is asked for outside a match")

-- ---------------------------------------------------------------------------
-- 11. The call this file exists to not make
-- ---------------------------------------------------------------------------
-- GetBattlefieldScore is defined only in Blizzard_Deprecated/Mainline/Deprecated_12_0_1.lua, and
-- the toc gates that file [AllowLoadGameType mainline]. Forever is camelot, so the file never
-- loads and the global is never defined. Any call to it here would be a nil call in game, and the
-- mock cannot catch that because the mock does not define it either -- so the source is checked.
do
  local f = assert(io.open("Godslayer/Field.lua"))
  local src = f:read("*a") f:close()
  local calls = src:gsub("%-%-[^\n]*", "")
  eq(calls:find("GetBattlefieldScore%s*%("), nil, "the module never calls GetBattlefieldScore")
  check(src:find("C_PvP.GetScoreInfo", 1, true), "it calls C_PvP.GetScoreInfo instead")
  check(src:find("GetNumBattlefieldScores", 1, true), "walked from GetNumBattlefieldScores")
  eq(_G.GetBattlefieldScore, nil, "and the global is absent here as it is on Forever")
end

eq(ns.errors, nil, "no errors anywhere in this suite")
for _, line in ipairs(GodslayerDB.log) do
  if line:find(" error: ", 1, true) then check(false, "logged error: " .. line) end
end

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
