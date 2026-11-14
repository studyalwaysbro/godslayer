-- Coordinate-only flag readout tests. Calls from chat/widgets live in phase1.lua;
-- map positions must never invent flag state.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0

local function check(value, label)
  if value then passed = passed + 1
  else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(got, want, label)
  check(got == want, label .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end
local function near(got, want, tolerance, label)
  check(type(got) == "number" and math.abs(got - want) <= tolerance,
    label .. " (got " .. tostring(got) .. ", want " .. tostring(want) .. ")")
end
local function contains(value, fragment, label)
  check(type(value) == "string" and value:find(fragment, 1, true) ~= nil, label)
end

M.addUnit("player", {
  name = "Vesh Torchman", guid = "Player-1-0000AAAA", faction = "Horde", class = "MAGE",
})
local ns = M.load("Godslayer", {
  "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Sound.lua", "Stage.lua", "Clip.lua",
  "Hype.lua", "Flag.lua",
})
local F = ns.Flag

-- Bearing arithmetic is independent of the map API.
eq(F.Clock(0), 12, "straight ahead is twelve")
eq(F.Clock(-math.pi / 2), 3, "right is three")
eq(F.Clock(math.pi), 6, "behind is six")
eq(F.Clock(math.pi / 2), 9, "left is nine")
eq(F.Where(0), "ahead", "ahead wording")
eq(F.Where(math.pi), "behind", "behind wording")
eq(F.Turn(0, 0, 0), nil, "zero-length bearing is absent")
eq(F.Turn(M.secret(), 1, 0), nil, "secret bearing is ignored")

F.Reset()
M.playerAt(500, 500)
M.flagsAt({})
F.Tick()
local rows, why = F.Read()
eq(rows, nil, "empty map has no rows")
eq(why, "no carried flags on this map", "empty map reason")
M.printed = {}
F.Command("")
contains(table.concat(M.printed, "\n"), "No flags: no carried flags on this map.", "empty command is helpful")

-- The mock accepts yards and crosses both normalised/world coordinate transforms.
local ALLIANCE, HORDE = 137200, 137218
local function one(north, west, texture, facing)
  M.facing = facing or 0
  M.flagsAt({ { north = north, west = west, texture = texture or ALLIANCE } })
  M.advance(0.6)
  F.Tick()
  return assert(F.Read())[1]
end

local r = one(600, 500, ALLIANCE)
near(r.yards, 100, 0.01, "north distance uses world yards")
eq(r.where, "ahead", "north is ahead while facing north")
eq(r.name, "Alliance flag", "Alliance texture identifies Alliance flag")
eq(r.faction, "Alliance", "Alliance texture supplies faction identity")
eq(r.state, nil, "position row has no state")
eq(r.home, nil, "position row has no home inference")
eq(r.toCap, nil, "position row has no capture-distance inference")

r = one(500, 400, HORDE)
near(r.yards, 100, 0.01, "east-west axis preserves distance")
eq(r.where, "3 o'clock", "east is three o'clock in mock orientation")
eq(r.name, "Horde flag", "Horde texture identifies Horde flag")
r = one(400, 500, ALLIANCE)
eq(r.where, "behind", "south is behind")
r = one(500, 600, ALLIANCE)
eq(r.where, "9 o'clock", "west is nine o'clock")
r = one(600, 600, ALLIANCE, math.pi / 2)
near(r.yards, math.sqrt(20000), 0.01, "diagonal distance")
eq(r.where, "2 o'clock", "facing rotates relative bearing")

-- Engine indices may reorder. Texture identity remains authoritative.
M.facing = 0
M.flagsAt({
  { north = 540, west = 500, texture = ALLIANCE },
  { north = 700, west = 500, texture = HORDE },
  { north = 800, west = 500, texture = 999999 },
  { north = 900, west = 500, texture = ALLIANCE, onMap = false },
})
M.advance(0.6); F.Tick()
rows = assert(F.Read())
eq(#rows, 3, "nil map coordinates are omitted")
eq(rows[1].name, "Alliance flag", "nearest known texture named before reorder")
eq(rows[2].name, "Horde flag", "second known texture named before reorder")
eq(rows[3].name, "A flag", "unknown texture stays generic")

M.flagsAt({
  { north = 530, west = 500, texture = HORDE },
  { north = 720, west = 500, texture = ALLIANCE },
})
M.advance(0.6); F.Tick()
rows = assert(F.Read())
eq(rows[1].name, "Horde flag", "texture identity survives index reorder")
eq(rows[2].name, "Alliance flag", "other texture survives index reorder")
check(rows[1].speed and rows[1].speed >= 1, "movement produces speed")
local clause = assert(F.Clause())
contains(clause, "Horde flag is", "clause names texture identity")
check(not clause:lower():find("home", 1, true), "clause does not claim home")
check(not clause:lower():find("down", 1, true), "clause does not claim down")
check(not clause:lower():find("capture", 1, true), "clause does not claim capture")
local lines = assert(F.Lines())
eq(lines[1], "2 carried flags on this map:", "readout describes carried map markers")
contains(F.Row(rows[1]), "y/s", "moving flag row shows speed")

-- Position polling cannot call or banner, regardless of movement and disappearance.
local voices, banners = 0, 0
ns.Hype = { Say = function() voices = voices + 1 end }
ns.Stage = { FlagBanner = function() banners = banners + 1 end }
M.flagsAt({ { north = 900, west = 900, texture = HORDE } })
M.advance(1); F.Tick()
M.flagsAt({})
M.advance(1); F.Tick()
eq(voices, 0, "position movement and disappearance make no voice call")
eq(banners, 0, "position movement and disappearance make no banner")

-- Reset and missing-client surfaces fail closed and explain themselves.
F.Reset()
rows, why = F.Read()
eq(rows, nil, "zone reset clears position rows")
eq(why, "no map", "zone reset clears cached map")
local oldCount = GetNumBattlefieldFlagPositions
GetNumBattlefieldFlagPositions = nil
eq(F.Available(), false, "missing count API is unavailable")
rows, why = F.Read()
eq(rows, nil, "unavailable client has no rows")
eq(why, "this client has no flag positions", "unavailable-client reason")
M.printed = {}
F.Command("")
contains(table.concat(M.printed, "\n"), "flag-position API", "unavailable command names missing API")
GetNumBattlefieldFlagPositions = oldCount

-- Erroring and secret map inputs are swallowed by the addon boundary.
local oldMap = C_Map.GetBestMapForUnit
C_Map.GetBestMapForUnit = function() error("map failed") end
M.advance(0.6)
check(pcall(F.Tick), "map API error is contained")
C_Map.GetBestMapForUnit = function() return M.secret() end
M.advance(0.6)
check(pcall(F.Tick), "secret map ID is contained")
C_Map.GetBestMapForUnit = oldMap

M.realPrint(("flag: %d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
