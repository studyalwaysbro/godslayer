-- Godslayer and where the flag is: lua tests/flag.lua
--
-- Two things are under test and only one of them is logic.
--
-- The first is a coordinate conversion, and it is the kind that is wrong in a way nothing notices.
-- The client answers flag and player positions in normalised map space; distance only exists in
-- world yards. Normalised x runs east while world y runs **west**, and normalised y runs south
-- while world x runs **north**, so both axes are flipped. A sign error gives distances that are
-- plausible, bearings that are mirrored, and a cap call that fires when the carrier is running
-- the wrong way. So the mock is driven in yards and converts the other way for the calls the
-- addon makes: every distance here is a number the test asked for, and the round trip has to
-- return it.
--
-- The second is two inferences the engine refuses to make. `GetBattlefieldFlagPosition` gives an
-- index and a texture and no faction, so which flag is whose is learned -- from where a flag sits
-- when nobody has it, and from where you were standing when the gates opened. Both are gated on
-- their own confidence and the tests below push on the cases where the confidence is not there,
-- because an inference that guesses when it should abstain is worse than no inference.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function near(a, b, tol, label)
  check(type(a) == "number" and math.abs(a - b) <= tol,
    label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. " +/- " .. tostring(tol) .. ")")
end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen",
                      class = "MAGE", race = "Scourge", sex = 2, faction = "Horde", isMe = true })
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua",
                "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua",
                "Flag.lua", "Control.lua", "Death.lua", "Threat.lua", "Comm.lua", "Rival.lua",
                "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local F = ns.Flag
local function say(text) SlashCmdList["GODSLAYER"](text) end
local function printed() return table.concat(M.printed, "\n") end

local PI = math.pi

-- The sound files have to exist on disk before PlaySoundFile will admit to playing one, which is
-- the mock being right: Hype.Sfx returns false for a clip the addon does not ship, so a callout
-- wired to a name nobody recorded is a silent banner and these tests would not notice.
for name in pairs(ns.SFX or {}) do
  M.audio.files["Interface\\AddOns\\Godslayer\\Sounds\\sfx\\" .. name .. ".ogg"] = true
end

-- Both bases of a Warsong-shaped map, in world yards. The numbers are arbitrary and that is the
-- point: nothing in Flag.lua knows them, it learns them from the flags standing on them.
local OURS = { north = 300, west = 500 }
local THEIRS = { north = 900, west = 500 }

local function tick(dt)
  M.advance(dt or 1)
  F.Tick()
end

-- ---------------------------------------------------------------------------
-- 1. The bearing arithmetic, before any of it is wired to a map
-- ---------------------------------------------------------------------------
-- World x is north and y is west, and GetPlayerFacing counts counter-clockwise from north, so a
-- target due north of a player facing north is a turn of zero and a target due west is +pi/2.
near(F.Turn(100, 0, 0), 0, 1e-9, "due north, facing north, is no turn")
near(F.Turn(0, 100, 0), PI / 2, 1e-9, "due west, facing north, is a quarter turn left")
near(F.Turn(0, -100, 0), -PI / 2, 1e-9, "due east is a quarter turn right")
near(F.Turn(-100, 0, 0), PI, 1e-9, "due south is half a turn")
-- the wrap, which is the only part of this that can be visibly silly
near(F.Turn(100, 0, 0.1), -0.1, 1e-9, "turning ten degrees left makes the target ten degrees right")
check(F.Turn(100, 0, 6.2) > 0, "a facing just short of a full circle reads as a small left turn, not a huge right one")
near(F.Turn(100, 0, 6.2), 2 * PI - 6.2, 1e-9, "and by the right amount")
eq(F.Turn(0, 0, 0), nil, "standing on it is no bearing at all")
eq(F.Turn(100, 0, nil), nil, "no facing is no bearing")
-- A facing that is not a number is not the same as no facing, and the soak found this one: a NaN
-- compares false against every threshold in the module, so it does no visible damage until a
-- `%d` in the report refuses it. Nothing non-finite may reach the arithmetic.
local NAN, INF = 0 / 0, math.huge
eq(F.Turn(100, 0, NAN), nil, "a facing of NaN is no bearing")
eq(F.Turn(100, 0, INF), nil, "an infinite facing is no bearing")
eq(F.Turn(NAN, 0, 0), nil, "a NaN offset is no bearing")
eq(F.Turn(INF, 0, 0), nil, "an infinite offset is no bearing")
eq(F.Clock(NAN), nil, "and a NaN turn is no hour")
eq(F.Clock(INF), nil, "nor an infinite one")
eq(F.Where(NAN), nil, "so there is nothing to say about it")
eq(F.Turn(100, 0, "north"), nil, "and a facing that is words is no bearing")

eq(F.Clock(0), 12, "straight ahead is twelve o'clock")
eq(F.Clock(-PI / 2), 3, "a quarter turn right is three o'clock")
eq(F.Clock(PI / 2), 9, "a quarter turn left is nine")
eq(F.Clock(PI), 6, "behind is six")
-- The whole dial, because an off-by-one here is a report that sends people the wrong way and
-- reads perfectly well while doing it. Twelve hours, each from the middle of its own wedge.
for hour = 1, 12 do
  local rel = -(hour % 12) * (2 * PI / 12)
  eq(F.Clock(rel), hour, ("the dial is right at %d o'clock"):format(hour))
end
check(F.Clock(0) ~= 0, "and no bearing is ever reported as zero o'clock")
eq(F.Clock(-0.26), 12, "just off straight ahead still reads ahead")
eq(F.Clock(-0.27), 1, "and the next wedge over is one")
eq(F.Where(0), "ahead", "and twelve is said as ahead")
eq(F.Where(PI), "behind", "six is said as behind")
eq(F.Where(-PI / 2), "3 o'clock", "the rest are said as the hour")

-- ---------------------------------------------------------------------------
-- 2. Nothing to read
-- ---------------------------------------------------------------------------
check(F.Available(), "the mock has the call, so this client can answer")
M.flagsAt({})
eq(F.Count(), 0, "no flags means a count of zero")
local rows, why = F.Read()
eq(rows, nil, "and no rows")
eq(why, "no flags on this map", "with the reason said rather than an empty list")
eq(F.Clause(), nil, "and no clause for the battleground report")

M.printed = {}
say("flag")
check(printed():find("No flags", 1, true), "the command says there are none")
check(printed():find("Arathi Basin has none", 1, true), "and that this is normal for some battlegrounds")

-- ---------------------------------------------------------------------------
-- 3. The round trip: a flag at a known distance reads back at that distance
-- ---------------------------------------------------------------------------
-- This is the assertion the whole file is built around. The flag is placed 200 yards due north of
-- the player in world yards; the mock converts to normalised space, the addon converts back, and
-- the number has to survive both.
M.playerAt(500, 500)
M.facing = 0
M.flagsAt({ { north = 700, west = 500 } })
tick(1)
tick(1)
rows = F.Read()
check(type(rows) == "table" and #rows == 1, "one flag is read")
near(rows[1].yards, 200, 0.5, "and it is 200 yards away, through two conversions")
eq(rows[1].where, "ahead", "due north of a player facing north is ahead")
check(M.worldCalls > 0, "which went through the client's own world conversion rather than a scale guess")

-- the two axis flips, each on its own, which is the only way to tell a flip from a swap
M.flagsAt({ { north = 500, west = 300 } })   -- 200 yards EAST (west decreasing)
F.Reset()
tick(1) tick(1)
rows = F.Read()
near(rows[1].yards, 200, 0.5, "a flag 200 yards east is also 200 yards away")
eq(rows[1].where, "3 o'clock", "and it is on the right")

M.flagsAt({ { north = 500, west = 700 } })   -- 200 yards WEST
F.Reset()
tick(1) tick(1)
rows = F.Read()
eq(F.Read()[1].where, "9 o'clock", "a flag to the west is on the left")

M.flagsAt({ { north = 300, west = 500 } })   -- 200 yards SOUTH
F.Reset()
tick(1) tick(1)
eq(F.Read()[1].where, "behind", "a flag to the south is behind")

-- and the bearing moves with the player rather than with the map
M.facing = PI / 2                            -- facing west
M.flagsAt({ { north = 700, west = 500 } })   -- due north again
F.Reset()
tick(1) tick(1)
eq(F.Read()[1].where, "3 o'clock", "facing west, the flag due north is on the right")
M.facing = 0

-- a diagonal, so the distance is not just one subtraction either way
M.playerAt(500, 500)
M.flagsAt({ { north = 800, west = 900 } })   -- 300 north, 400 west
F.Reset()
tick(1) tick(1)
near(F.Read()[1].yards, 500, 0.5, "a 300 by 400 offset is 500 yards, not 700")

-- ---------------------------------------------------------------------------
-- 4. A flag the engine will not place on this map
-- ---------------------------------------------------------------------------
-- The documented behaviour is a nil x, and Blizzard's own pin hides itself on it. Here it has to
-- leave the flag out rather than record a position of zero, which would read as the map's corner.
M.playerAt(500, 500)
M.flagsAt({ { north = 700, west = 500 }, { north = 400, west = 400, onMap = false } })
F.Reset()
tick(1) tick(1)
rows = F.Read()
eq(#rows, 1, "the flag that is not on this map is not in the rows")
eq(rows[1].index, 1, "and the one that is, is")

-- the whole map going away is the same thing for every flag at once
M.flagsAt({ { north = 700, west = 500 } })
F.Reset()
local keep = M.map
M.map = nil
tick(1)
rows, why = F.Read()
eq(rows, nil, "with no map there is nothing to read")
M.map = keep

-- ---------------------------------------------------------------------------
-- 5. Learning where a flag lives
-- ---------------------------------------------------------------------------
F.Reset()
M.playerAt(OURS.north, OURS.west)
M.flagsAt({ { north = OURS.north, west = OURS.west }, { north = THEIRS.north, west = THEIRS.west } })
tick(1) tick(1)
rows = F.Read()
eq(#rows, 2, "both flags are read")
check(rows[1].home, "a flag that was standing still when first seen has a base")
eq(rows[1].state, "home", "and it is at it")
eq(rows[2].state, "home", "so is the other one")

-- the side, from where the player was standing when the gates opened
eq(rows[1].name, "Yours", "the base you were standing on is yours")
eq(rows[2].name, "Theirs", "and the other one is theirs")

-- ---------------------------------------------------------------------------
-- 6. The flag goes up
-- ---------------------------------------------------------------------------
-- Their flag starts moving toward our base. 7 yards a second is a player on foot.
M.stage = M.stage or {}
local function moveFlag(i, north, west)
  M.flags[i].north, M.flags[i].west = north, west
end

for step = 1, 4 do
  moveFlag(2, THEIRS.north - step * 7, THEIRS.west)
  tick(1)
end
rows = F.Read()
local theirs
for _, r in ipairs(rows) do if r.name == "Theirs" then theirs = r end end
check(theirs ~= nil, "their flag is still in the rows")
eq(theirs.state, "carried", "a flag off its base and moving is being carried")
near(theirs.speed, 7, 1.5, "at about the speed it was moved")
check(theirs.toCap ~= nil, "and it has somewhere to be")
near(theirs.toCap, THEIRS.north - 4 * 7 - OURS.north, 2,
  "which is the other flag's base, worked out without knowing anything about the map")

-- the clause the battleground report and the death card use
local clause = F.Clause()
check(type(clause) == "string" and clause:find("Theirs flag is up", 1, true),
  "the clause names a flag in hands: " .. tostring(clause))

-- carried to within the callout distance of the cap
moveFlag(2, OURS.north + 40, OURS.west)
tick(1)
clause = F.Clause()
check(type(clause) == "string" and clause:find("from the cap", 1, true),
  "and close to the cap it says so instead: " .. tostring(clause))

-- ---------------------------------------------------------------------------
-- 7. Dropped, and home again
-- ---------------------------------------------------------------------------
-- A carrier who stops is a carrier who is fighting, and that is the window worth having.
for _ = 1, 5 do tick(1) end
for _, r in ipairs(F.Read()) do if r.name == "Theirs" then theirs = r end end
eq(theirs.state, "dropped", "a flag off its base and not moving is on the floor")

moveFlag(2, THEIRS.north, THEIRS.west)
for _ = 1, 5 do tick(1) end
for _, r in ipairs(F.Read()) do if r.name == "Theirs" then theirs = r end end
eq(theirs.state, "home", "back on its base it is home again")

-- ---------------------------------------------------------------------------
-- 8. Where the inferences refuse to answer
-- ---------------------------------------------------------------------------
-- Zoning in with the flag already out. The first sighting is moving, so there is no base to
-- learn, and nothing that depends on a base may be claimed.
F.Reset()
M.playerAt(500, 500)
M.flagsAt({ { north = 600, west = 500 } })
for step = 1, 4 do
  moveFlag(1, 600 + step * 8, 500)
  tick(1)
end
rows = F.Read()
eq(rows[1].home, false, "a flag first seen moving does not get a base")
eq(rows[1].state, "carried", "it is plainly being carried")
check(rows[1].yards ~= nil, "the distance is still exact, because it needs no base at all")
eq(rows[1].toCap, nil, "but there is no cap to measure to")
local lines = F.Lines()
check(table.concat(lines, "\n"):find("already moving when I first saw them", 1, true),
  "and the report says which flags it is abstaining on")

-- A player standing at midfield when the gates open has no claim to a side.
F.Reset()
M.playerAt(600, 500)   -- 300 from ours, 300 from theirs
M.flagsAt({ { north = OURS.north, west = OURS.west }, { north = THEIRS.north, west = THEIRS.west } })
tick(1) tick(1)
rows = F.Read()
eq(rows[1].name, "A flag", "from the middle of the map, neither flag is claimed as yours")
eq(rows[2].name, "A flag", "nor the other one")

-- Near one base but not clearly: both within the far threshold.
F.Reset()
M.playerAt(OURS.north + 60, OURS.west)
M.flagsAt({ { north = OURS.north, west = OURS.west }, { north = OURS.north + 200, west = OURS.west } })
tick(1) tick(1)
rows = F.Read()
eq(rows[1].name, "A flag", "two bases close together is not a side either")

-- ---------------------------------------------------------------------------
-- 9. The cap needs exactly two flags
-- ---------------------------------------------------------------------------
-- With one flag there is no other base; with three there is no single other base. Both cases
-- return nothing rather than picking one, because picking one would be an invented objective.
F.Reset()
M.playerAt(500, 500)
M.flagsAt({ { north = OURS.north, west = OURS.west },
            { north = THEIRS.north, west = THEIRS.west },
            { north = 600, west = 900 } })
tick(1) tick(1)
moveFlag(2, THEIRS.north - 30, THEIRS.west)
tick(1) tick(1)
for _, r in ipairs(F.Read()) do
  if r.state == "carried" then eq(r.toCap, nil, "with three flags on the map there is no cap to name") end
end

F.Reset()
M.flagsAt({ { north = THEIRS.north, west = THEIRS.west } })
tick(1) tick(1)
moveFlag(1, THEIRS.north - 30, THEIRS.west)
tick(1) tick(1)
eq(F.Read()[1].toCap, nil, "with one flag there is no cap either")

-- ---------------------------------------------------------------------------
-- 10. The callouts
-- ---------------------------------------------------------------------------
F.Reset()
M.playerAt(OURS.north, OURS.west)
M.flagsAt({ { north = OURS.north, west = OURS.west }, { north = THEIRS.north, west = THEIRS.west } })
tick(1) tick(1)
local sounds0 = #M.audio.played

for step = 1, 4 do
  moveFlag(2, THEIRS.north - step * 7, THEIRS.west)
  tick(1)
end
check(#M.audio.played > sounds0, "a flag going up makes a sound")
local heard = ""
for _, a in ipairs(M.audio.played) do heard = heard .. " " .. tostring(a.path) end
check(heard:find("horn", 1, true), "and it is one the addon actually ships: " .. heard)

-- the throttle: a second transition inside the gap does not speak again. The state has to really
-- change or this assertion passes for the wrong reason.
local before = #M.audio.played
local stateBefore
for _, r in ipairs(F.Read()) do if r.index == 2 then stateBefore = r.state end end
moveFlag(2, THEIRS.north - 4 * 7, THEIRS.west)
for _ = 1, 4 do tick(0.5) end
local stateAfter
for _, r in ipairs(F.Read()) do if r.index == 2 then stateAfter = r.state end end
check(stateBefore ~= stateAfter, "the flag did change state inside the gap (" ..
  tostring(stateBefore) .. " -> " .. tostring(stateAfter) .. ")")
eq(#M.audio.played, before, "and the second call inside the gap is held")

-- and the toggle turns them off for good
M.printed = {}
say("flag watch")
check(printed():find("off", 1, true), "flag watch turns the callouts off")
before = #M.audio.played
F.Reset()
M.flagsAt({ { north = OURS.north, west = OURS.west }, { north = THEIRS.north, west = THEIRS.west } })
tick(1) tick(1)
for step = 1, 4 do moveFlag(2, THEIRS.north - step * 9, THEIRS.west) tick(1) end
eq(#M.audio.played, before, "and then a flag going up is silent")
M.printed = {}
say("flag watch")
check(printed():find("on", 1, true), "and the toggle turns them back on")

-- ---------------------------------------------------------------------------
-- 11. The report, and the battleground report that carries it
-- ---------------------------------------------------------------------------
F.Reset()
M.playerAt(OURS.north, OURS.west)
M.flagsAt({ { north = OURS.north, west = OURS.west }, { north = THEIRS.north, west = THEIRS.west } })
tick(1) tick(1)
M.printed = {}
say("flag")
local out = printed()
check(out:find("2 flags on this map", 1, true), "the report counts them")
check(out:find("Yours", 1, true), "and names your side")
check(out:find("at home", 1, true), "with the state in words")
check(out:find("Blizzard draws these on the map too", 1, true),
  "and says plainly that the map already has a pin for this")

-- the flag clause reaches the battleground report
moveFlag(2, THEIRS.north - 40, THEIRS.west)
tick(1) tick(1) tick(1)
M.battleground({
  rows = {
    { name = "Vesh Torchman", faction = 0, race = "Scourge", gender = 2, class = "Mage", token = "MAGE", rank = 7, guid = ME },
    { name = "Sir Problem", faction = 1, race = "Human", gender = 2, class = "Paladin", token = "PALADIN", rank = 11, guid = "Player-1-0000BBBB" },
  },
})
local board = ns.Field.Board()
check(board ~= nil, "there is a board to report on")
local fieldLines = table.concat(ns.Field.Lines(board) or {}, "\n")
check(fieldLines:find("flag is up", 1, true),
  "and the battleground report ends with where the flag is: " .. fieldLines:gsub("\n", " | "))
M.bg = nil

-- ---------------------------------------------------------------------------
-- 12. Zoning resets everything
-- ---------------------------------------------------------------------------
M.fire("ZONE_CHANGED_NEW_AREA")
M.flagsAt({})
rows, why = F.Read()
eq(rows, nil, "after a zone change there is nothing held over")
eq(why, "no flags on this map", "and the reason is the honest one")

-- ---------------------------------------------------------------------------
-- 13. A client without the call
-- ---------------------------------------------------------------------------
-- The call is used by Blizzard's own pin and appears in none of the 642 generated documentation
-- files, so its absence is a real possibility and the addon has to say so rather than report an
-- empty battleground.
local realCount = GetNumBattlefieldFlagPositions
GetNumBattlefieldFlagPositions = nil
eq(F.Available(), false, "without the call this client cannot answer")
rows, why = F.Read()
eq(rows, nil, "so there are no rows")
eq(why, "this client has no flag positions", "and the reason names the call rather than the map")
M.printed = {}
say("flag")
check(printed():find("GetNumBattlefieldFlagPositions", 1, true), "and the command names it too")
F.Tick()   -- must not throw
GetNumBattlefieldFlagPositions = realCount
check(F.Available(), "and it comes back when the call does")

-- ---------------------------------------------------------------------------
-- 13b. Every sound named in the module is one the addon actually ships
-- ---------------------------------------------------------------------------
-- Hype.Sfx returns false for a name that is not in ns.SFX and says nothing about it, so a typo
-- costs a silent banner and no error anywhere. This reads the names out of the source rather
-- than trusting that the callout tests happened to cover all three.
do
  local fh = io.open("Godslayer/Flag.lua")
  local body = fh:read("*a")
  fh:close()
  -- Each callout passes a sound and then a voice clip, and every clip name starts with "flag".
  local n = 0
  for sound, clip in body:gmatch('"([%w_]+)",%s*"(flag%w+)"') do
    n = n + 1
    check(ns.SFX[sound] ~= nil, "the sound " .. sound .. " behind " .. clip .. " is one the addon ships")
  end
  eq(n, 3, "all three transitions were found in the source")
end

-- ---------------------------------------------------------------------------
-- 14. Wiring
-- ---------------------------------------------------------------------------
M.printed = {}
say("help")
check(printed():find("/godslayer flag", 1, true), "the help lists it")
local tables = ns.DispatchTables()
local found = false
for _, t in ipairs(tables) do if t == F.handlers then found = true end end
check(found, "and its handlers are in the dispatch list")

-- ---------------------------------------------------------------------------
-- 15. Nothing broke on the way through
-- ---------------------------------------------------------------------------
eq(ns.errors, nil, "no errors anywhere in this suite")
eq(M.dateFloats, 0, "nothing asked date() for a fractional second")
for _, l in ipairs(GodslayerDB.log) do
  if l:find(" error: ", 1, true) then check(false, "logged error: " .. l) end
end

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
