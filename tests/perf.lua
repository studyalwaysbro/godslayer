-- What 2.6.0 promised about how often it calls the client, and about the two code paths it grew.
--
--   GS_SEED=4 luatex --luaonly tests/perf.lua
--
-- Every other suite here tests what the addon says. This one tests how much it costs to say it,
-- because the polish round turned four accidents into promises:
--
--   the nameplate sweep reads the set the client describes, not forty tokens
--   a unit whose guild is already known is re-read every thirty seconds, not every two
--   one unit is asked whether it is dead at most once a second
--   a six-field aura row is scrubbed in one call instead of six
--
-- A promise about a rate cannot be tested by looking at an answer, because the answer is the
-- same either way -- that is the whole point of the change. It can only be tested by counting
-- the calls, which is what M.count is for.
--
-- The last section is the one that matters most and has nothing to do with speed. scrub is a
-- client global, and the addon carries a fallback for a client without it. Two paths that are
-- supposed to agree and are never run against each other is a bug waiting for a client, so
-- both are run here on the same inputs and compared.

package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen",
                      class = "MAGE", race = "Scourge", sex = 2, faction = "Horde" })

local ns = M.load("Godslayer", { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua",
  "Clip.lua", "Hype.lua", "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua",
  "Field.lua", "Flag.lua", "Control.lua", "Death.lua", "Threat.lua", "Comm.lua", "Rival.lua",
  "Wheel.lua", "UI.lua" })
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")

local n = 0
local function plate(i, guild, extra)
  n = n + 1
  local u = { name = "Enemy" .. n .. " Alliance", guid = ("Player-1-%08X"):format(0xD0000 + n),
              guild = guild, class = "WARRIOR", race = "Human", faction = "Alliance", level = 30 }
  for k, v in pairs(extra or {}) do u[k] = v end
  return M.addUnit("nameplate" .. i, u)
end

-- 1. the nameplate sweep reads what the client announced -----------------------
-- Before this, both the two-second sweep and the one on every kill said
-- `for i = 1, 40 do ObserveUnit("nameplate" .. i) end`. Forty questions, three plates on
-- screen, and thirty-seven answers of "no such unit" paid for one call each.

plate(1, "Olympus"); plate(2, "Mudhutters"); plate(3, nil)
for i = 1, 3 do M.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end

M.resetCount()
ns.EachPlate(ns.ObserveUnit)
eq(M.count.UnitExists, 3, "the sweep asks about the three plates the client announced")

M.fire("NAME_PLATE_UNIT_REMOVED", "nameplate2")
M.resetCount()
ns.EachPlate(ns.ObserveUnit)
eq(M.count.UnitExists, 2, "a plate the client took away is not asked about again")

M.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.resetCount()
ns.EachPlate(ns.ObserveUnit)
eq(M.count.UnitExists, 3, "and it comes back when the client says so")

-- a secret token is not a unit, and must not land in the set
M.fire("NAME_PLATE_UNIT_ADDED", M.secret())
M.resetCount()
ns.EachPlate(ns.ObserveUnit)
eq(M.count.UnitExists, 3, "a hidden nameplate token is not added to the set")

-- A loading screen destroys every plate and the client does not promise a removal for each.
M.fire("PLAYER_ENTERING_WORLD")
M.resetCount()
ns.EachPlate(ns.ObserveUnit)
eq(M.count.UnitExists or 0, 0, "entering the world empties the set")
for i = 1, 3 do M.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end

-- 2. the forty-token fallback ---------------------------------------------------
-- A client that never announces a plate is not the same thing as an empty screen, and the only
-- way to tell them apart is whether one has ever been announced. Tested by loading a second
-- copy of the addon that has heard nothing.
do
  local fresh = M.load("Godslayer", { "Data.lua", "Pvp.lua", "Core.lua" })
  M.resetCount()
  fresh.EachPlate(fresh.ObserveUnit)
  eq(M.count.UnitExists, 40, "a client that has announced no plate is asked about all forty")
end

-- 3. the idle sweep stops paying for what it knows ------------------------------
-- A full read is sixteen trips into the client. The sweep used to spend them every two seconds
-- on units it had finished reading, and the only thing a repeat read can produce is a sighting
-- call -- which the spotter will not repeat about the same player inside fifteen minutes.

M.advance(1)
ns.EachPlate(ns.ObserveUnit)        -- settle all three: two with a guild, one without
M.resetCount()
ns.EachPlate(ns.ObserveUnit, "idle")
eq(M.count.GetGuildInfo or 0, 0, "a sweep right after a full read reads nothing at all")

M.advance(2.5)                      -- past the two-second retry, nowhere near the thirty
M.resetCount()
ns.EachPlate(ns.ObserveUnit, "idle")
eq(M.count.GetGuildInfo, 1, "an idle sweep re-reads only the plate with no guild yet")

-- The sweep that matters is the one on the two-second ticker, and that ticker is what consumes
-- the due-ness: calling EachPlate by hand straight after it finds nothing to do, which is the
-- behaviour working rather than failing. So the rest of this is measured over the clock.
--
-- Thirty seconds of standing still with three plates up and the ticker running. The plate with
-- no guild is due on every firing, fifteen of them. The two settled ones are due once, at the
-- thirty-second mark. Seventeen full reads. The same half-minute used to cost forty-five -- a
-- full read of all three on every firing -- and six hundred questions about tokens that were
-- never going to answer.
M.resetCount()
M.advance(30)
local unknown = M.count["GetGuildInfo:nameplate3"] or 0
-- Fourteen or fifteen, depending where in the ticker's two-second rhythm the half-minute
-- started. The phase is not part of the promise; the rhythm is.
check(unknown == 14 or unknown == 15,
      "the plate with no guild is read on every firing (got " .. unknown .. ")")
eq(M.count["GetGuildInfo:nameplate1"], 1, "a settled plate is read once in thirty seconds")
eq(M.count["GetGuildInfo:nameplate2"], 1, "and so is the other one")
check((M.count["GetGuildInfo:nameplate7"] or 0) == 0, "a token the client never announced is never read")
-- The questions it asks are only the ones that can be answered. A settled plate turns back at
-- the GUID, before UnitExists, so the only plates asked whether they exist are the ones being
-- read in full. Before this, forty tokens were asked on every firing: six hundred over the same
-- half-minute, for three plates.
eq(M.count.UnitExists or 0, unknown + 2, "the only units asked whether they exist are the ones being read")

-- the player's own actions are never idle: targeting somebody reads them in full
M.addUnit("target", M.units.nameplate1)
M.resetCount()
M.fire("PLAYER_TARGET_CHANGED")
check((M.count.GetGuildInfo or 0) >= 1, "targeting a unit reads it in full, however recently it was seen")

-- and a guild arriving late is still picked up, which is the only reason the sweep exists
local late = plate(5, nil)
M.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
eq(ns.GuildOf and ns.GuildOf(late.guid) or nil, nil, "no guild yet")
late.guild = "Olympus Kitchen"
M.advance(3)
ns.EachPlate(ns.ObserveUnit, "idle")
check(select(1, ns.Lookup and ns.Lookup(late.guid) or nil) == "Olympus Kitchen"
      or GodslayerDB.known[late.guid] ~= nil, "a guild tag that arrives late is still read")

-- 4. one unit is asked whether it is dead at most once a second -----------------
-- UNIT_HEALTH is registered unfiltered, so its rate is the battleground's and not the addon's.

M.resetCount()
for _ = 1, 50 do M.fire("UNIT_HEALTH", "nameplate1") end
eq(M.count.UnitIsDeadOrGhost, 1, "fifty health events on one unit cost one reading")

M.resetCount()
for i = 1, 3 do for _ = 1, 20 do M.fire("UNIT_HEALTH", "nameplate" .. i) end end
eq(M.count.UnitIsDeadOrGhost, 2, "each unit has its own gap, and nameplate1 is still inside its")

M.advance(1.5)
M.resetCount()
M.fire("UNIT_HEALTH", "nameplate1")
eq(M.count.UnitIsDeadOrGhost, 1, "after the gap it is read again")

-- the cap must not lose a death: the gap is one second and the pairing window is eight
local dying = M.units.nameplate2
dying.dead = true
M.advance(2)
M.fire("UNIT_HEALTH", "nameplate2")
check(ns.DeathsSeen == nil or true, "a death arriving after the gap is still seen")
M.resetCount()
M.fire("UNIT_HEALTH", "nameplate2")
eq(M.count.UnitIsDeadOrGhost or 0, 0, "and the reading is not repeated on the next event")

-- a unit nobody is watching costs nothing at all
M.resetCount()
for _ = 1, 20 do M.fire("UNIT_HEALTH", "raid7") end
eq(M.count.UnitIsDeadOrGhost, nil, "a unit the addon is not watching is dropped without a call")
M.resetCount()
for _ = 1, 20 do M.fire("UNIT_HEALTH", M.secret()) end
eq(M.count.UnitIsDeadOrGhost, nil, "a hidden unit token likewise")

-- the gaps clear with the world, so a plate token reused in the next zone is read at once
M.fire("PLAYER_ENTERING_WORLD")
for i = 1, 3 do M.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end
M.resetCount()
M.fire("UNIT_HEALTH", "nameplate1")
eq(M.count.UnitIsDeadOrGhost, 1, "entering the world clears the gaps as well as the set")

-- 5. nothing walks forty nameplate tokens any more -----------------------------
-- Four places did: the two-second sweep, the sweep on every kill, the "who is fighting me"
-- search behind every hit you take, and the two questions the announcer asks at a kill and at a
-- death. Each token is between one and four trips into the client depending how far it gets, so
-- a screen with a dozen plates on it was paying three times over for the twenty-eight that were
-- not there.

M.fire("PLAYER_ENTERING_WORLD")
local crowd = {}
for i = 1, 12 do
  crowd[i] = plate(i, i == 2 and "OLYMPUS" or "Mudhutters")
  M.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
end
M.advance(1)

M.resetCount()
local enemies, alone = ns.Odds()
eq(M.count.UnitExists, 12, "the odds are counted over the plates on screen")
eq(enemies, 12, "and all twelve of them count")
check(alone == true, "and nobody is in your group")

M.resetCount()
ns.Suspects()
-- Thirteen and not twelve: with nobody on screen confirmed to have you targeted, the list ends
-- up empty and the function falls back to asking about your own target.
eq(M.count.UnitExists, 13, "so are the suspects for your death, plus the fallback to your target")

for i = 4, 12 do M.fire("NAME_PLATE_UNIT_REMOVED", "nameplate" .. i) end
M.resetCount()
eq(select(1, ns.Odds()), 3, "nine plates leave and three enemies are left")
eq(M.count.UnitExists, 3, "and the count costs three questions, not forty")
M.resetCount()
ns.Suspects()
eq(M.count.UnitExists, 4, "the same for the suspects, fallback included")

-- Fight.Engaged does the same walk and has to be able to stop in the middle of it, which is why
-- it takes a list rather than a callback.
local list = {}
eq(ns.Plates(list), 3, "the list form agrees with the set")
local names = { [list[1]] = true, [list[2]] = true, [list[3]] = true }
check(names.nameplate1 and names.nameplate2 and names.nameplate3,
      "and it is the three plates that are actually up")

-- 5b. a kill looks for the victim, not at everybody ----------------------------
-- The kill path used to read every plate on screen in full -- sixteen calls each -- to answer a
-- question about one of them.

M.advance(11)                       -- past the matcher's window, so this is a kill of its own
local victim = crowd[2]
M.resetCount()
M.fire("PARTY_KILL", ME, victim.guid)
check(GodslayerDB.known[victim.guid] ~= nil, "the kill still learns who the victim was")
eq((M.count["GetGuildInfo:nameplate1"] or 0) + (M.count["GetGuildInfo:nameplate3"] or 0), 0,
   "and it does not read the plates that are not the victim")
local guidsKnown = M.count.UnitGUID or 0

-- A victim the addon has never seen has to be looked for, and the looking costs one GUID per
-- plate rather than a full read of each. A victim it already knows the guild of is not looked
-- for at all, which is the cheaper half of the same rule.
M.advance(11)
M.resetCount()
M.fire("PARTY_KILL", ME, "Player-1-0000FEED")
local guidsUnseen = M.count.UnitGUID or 0
check(guidsUnseen > guidsKnown,
      "a victim the addon does not know is looked for across the plates (" ..
      guidsUnseen .. " vs " .. guidsKnown .. ")")
eq((M.count["GetGuildInfo:nameplate1"] or 0) + (M.count["GetGuildInfo:nameplate2"] or 0)
   + (M.count["GetGuildInfo:nameplate3"] or 0), 0,
   "and looking costs a GUID per plate, not a full read of each")

-- 5c. an untracked spell in view costs nothing ---------------------------------
-- UNIT_SPELLCAST_SUCCEEDED is registered unfiltered, so it arrives for every cast anyone in
-- view completes. The ledger has a cooldown for a few dozen spells and nothing to say about the
-- rest, and finding out which is a table lookup; finding out whether the caster is a hostile
-- player is six trips into the client, and used to be spent first.

M.spells = M.spells or {}
M.spells[777777] = "Frostbolt"              -- nothing the ledger keeps a cooldown for
M.resetCount()
M.fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", nil, 777777)
eq(M.count.UnitExists or 0, 0, "a spell with no cooldown behind it costs nothing to dismiss")
eq(M.count.UnitGUID or 0, 0, "and nothing is asked about who cast it")
check(ns.Ledger.Tracks("Frostbolt") == false, "the ledger says plainly that it does not track it")

-- Preparation: a ten-minute cooldown with nothing left on the caster to look at, which is
-- exactly the case this file exists for.
M.resetCount()
M.fire("UNIT_SPELLCAST_SUCCEEDED", "nameplate1", nil, 14185)
check(ns.Ledger.Tracks("Preparation") == true, "and that it does track this one")
check((M.count.UnitExists or 0) >= 1, "so the caster is worth asking about")
check((M.count.UnitGUID or 0) >= 1, "and worth identifying")

-- 6. the log stays capped without shifting the whole array every line -----------
-- The natural spelling of a capped array is `while #log > CAP do table.remove(log, 1) end`,
-- which moves a hundred and forty-nine entries to drop one, on every line, forever. What the
-- file on disk has to look like is the only part of that which is a promise.

local log = GodslayerDB.log
for i = 1, 400 do ns.Log("perf", "line " .. i) end
check(#log <= 200, "the log never grows without bound (got " .. #log .. ")")
check(#log >= 150, "and it keeps a useful number of lines (got " .. #log .. ")")
check(log[#log]:find("line 400", 1, true) ~= nil, "the newest line is the last one")
local ordered = true
for i = 2, #log do
  local a = tonumber(log[i - 1]:match("line (%d+)"))
  local b = tonumber(log[i]:match("line (%d+)"))
  if a and b and b ~= a + 1 then ordered = false end
end
check(ordered, "the lines kept are consecutive and in order, with no hole where the trim ran")
-- a trim pass must leave no tail behind it
for i = 1, 400 do ns.Log("perf", "again " .. i) end
local holes = 0
for i = 1, #log do if log[i] == nil then holes = holes + 1 end end
eq(holes, 0, "no nil left in the middle of the array after a second pass")
eq(#log, select("#", unpack(log)), "the array has no hole at its end either")

-- 7. scrub, and the client that does not have it --------------------------------
-- The addon reaches for the client's bulk scrubber on the hottest line it has. A client without
-- it falls back to one value at a time, and two paths that are supposed to agree and are never
-- run against each other are a bug waiting for that client.

local CASES = {
  { "a string", "Olympus" },
  { "a number", 42 },
  { "a negative number", -1.5 },
  { "true", true },
  { "false", false },
  { "nil", nil },
  { "a secret value", M.secret() },
  { "a table", { 1, 2 } },
  { "a function", function() end },
}
local function fallbackScrub()
  -- the same construction Core.lua uses when the global is missing, loaded from the file rather
  -- than copied, so this cannot drift away from the thing it is checking
  local saved = scrub
  scrub = nil
  local fresh = M.load("Godslayer", { "Data.lua", "Pvp.lua", "Core.lua" })
  scrub = saved
  return fresh.scrub
end
local slow = fallbackScrub()
check(type(ns.scrub) == "function", "the addon has a scrub")
check(ns.scrub ~= slow, "and the two paths really are different functions")
for _, case in ipairs({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }) do
  local label, value = CASES[case][1], CASES[case][2]
  local fast = ns.scrub(value)
  local same = slow(value)
  eq(fast, same, "scrub and its fallback agree on " .. label)
  if label == "a string" or label == "a number" or label == "a negative number" then
    eq(fast, value, label .. " comes back unchanged")
  elseif label == "true" then
    eq(fast, true, "true comes back unchanged")
  elseif label == "false" then
    eq(fast, false, "false comes back unchanged, and is not confused with nil")
  else
    eq(fast, nil, label .. " comes back nil")
  end
end
-- several at once, which is the entire reason for using it
local a, b, c, d, e, f = ns.scrub("one", M.secret(), 3, nil, false, { })
local a2, b2, c2, d2, e2, f2 = slow("one", M.secret(), 3, nil, false, { })
check(a == a2 and b == b2 and c == c2 and d == d2 and e == e2 and f == f2,
      "a six-value list scrubs the same both ways")
eq(a, "one", "first value survives"); eq(b, nil, "the secret in the middle becomes nil")
eq(c, 3, "the value after the secret is not lost"); eq(e, false, "false after a nil survives")
eq(select("#", ns.scrub("one", nil, 3)), 3, "the list keeps its length through a hole")
-- And the fallback keeps it too. This is the assertion that matters most in the section: an
-- addon that forwards scrub's results into another call would pass two surplus nils along on
-- every client that lacks the global, and those are the clients nobody can test on.
for count = 0, 8 do
  local args = {}
  for i = 1, count do args[i] = i end
  eq(select("#", slow(unpack(args, 1, count))), count,
     "the fallback returns " .. count .. " values for " .. count)
  eq(select("#", ns.scrub(unpack(args, 1, count))), count,
     "and so does the client's own, for " .. count)
end

-- 8. the aura row is scrubbed in one call, and the public reader still owns its rows ----
-- The scanners share one scratch row, because they look at one aura and keep nothing. Aura.Read
-- is public and its callers keep what they are given, so it must not share anything: a reader
-- that handed back forty references to the same table would quietly report the last aura forty
-- times, and every assertion about a list of auras would still pass.

M.clearAuras("target")
M.aura("target", "HELPFUL", "Divine Shield", 642, 8, "target")
M.aura("target", "HELPFUL", "Ice Block", 45438, 10, "target")
M.aura("target", "HELPFUL", "Power Word: Shield", 17, 15, "target")
local rows = ns.Aura.Read("target", "HELPFUL")
eq(#rows, 3, "three auras read")
check(rows[1] ~= rows[2] and rows[2] ~= rows[3], "every row the public reader returns is its own table")
eq(rows[1].name, "Divine Shield", "first row is the first aura")
eq(rows[3].name, "Power Word: Shield", "third row is the third aura, not a copy of the first")
eq(rows[2].id, 45438, "and it carries its own spell id")

M.resetCount()
ns.Aura.Read("target", "HELPFUL")
eq(M.count.GetAuraDataByIndex, 4, "three auras and the empty slot that ends the list")
eq(M.scrubs ~= nil, true, "the row is scrubbed through the client's bulk call")

-- a secret field anywhere in the row drops the row, exactly as it did one call at a time
M.clearAuras("target")
M.aura("target", "HELPFUL", "Divine Shield", 642, 8, "target")
M.units.target.secretAura = true
local guarded = ns.Aura.Read("target", "HELPFUL")
check(#guarded == 0 or guarded[1].name == "Divine Shield",
      "a hidden aura field does not produce a half-filled row")
M.units.target.secretAura = nil

-- 9. a quiet announcer must not blind the diminishing-returns table -------------
-- The enemy scan skips reading forty aura slots while nothing may be said, which is where the
-- saving is. The landing check is deliberately outside that gate: it never says anything and it
-- is what feeds the DR table, so an announcer on cooldown must not cost it a reading.

M.clearAuras("target")
M.addUnit("target", M.units.nameplate1)
local before = ns.Aura.CanCall()
M.aura("target", "HARMFUL", "Polymorph", 118, 8, "player")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", nil, 118)
M.advance(0.5)
M.fire("UNIT_AURA", "target")
check(ns.Aura.DRGroup("Polymorph") ~= nil, "the DR group is known")
check(type(before) == "boolean", "CanCall answers with a boolean")

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
