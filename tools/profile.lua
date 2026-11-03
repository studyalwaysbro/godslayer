-- What Godslayer costs the client, measured instead of guessed.
--
--   luatex --luaonly tools/profile.lua            the report
--   luatex --luaonly tools/profile.lua --check    the report, and a non-zero exit over budget
--
-- WHY THIS EXISTS. An addon's cost in WoW is not its line count and it is barely its Lua
-- arithmetic. It is two things:
--
--   1. calls across the Lua/C boundary. Every UnitGUID, every GetTime, every C_Map call is a
--      trip into the client. A hundred of them an event is invisible; ten thousand a second in
--      a full battleground is a frame hitch, and a frame hitch in a fight is the whole reason
--      anyone installs a PvP addon.
--   2. garbage. Lua's collector runs during the frame, so every table and every concatenated
--      string the addon makes on a hot event is a stutter it pays for later, at a moment it
--      does not choose.
--
-- Neither is visible from reading the code, because both are about how often a line runs and
-- not what it says. So this harness boots the real addon against the test mock, drives a
-- battleground at a rate a real one actually reaches, and counts both.
--
-- HOW THE COUNTING WORKS. Every client function is replaced with one that bumps a counter and
-- forwards. The wrapping happens before the addon loads, which matters: several files capture
-- client functions into locals at load time (`local IsGUIDInGroup = ...`), and a wrapper
-- installed afterwards would never be seen by them. Lua's own library is left alone -- a
-- string.format is not a trip into the client -- so the standard names are listed out and
-- skipped.
--
-- The numbers are not WoW's. LuaTeX is Lua 5.3 and the game is 5.1, so a table costs a
-- different number of bytes here. What carries across is the shape: which calls dominate, how
-- many of them there are per second of play, and whether a change made it better or worse.

package.path = "tests/?.lua;" .. package.path

local CHECK = false
for i = 1, #arg do if arg[i] == "--check" then CHECK = true end end

-- ---------------------------------------------------------------------------
-- Budgets
-- ---------------------------------------------------------------------------
-- Measured, then given room to move. The run below came in at 546 calls and 43 kb per simulated
-- second after the 2.6.0 polish round, down from 1,088 and 67 before it; these are those figures
-- with about fifteen percent of slack. They are not a target to optimise towards -- they are a
-- tripwire, so that the next round to put a module on a hot event has to notice that it did.
local BUDGET = {
  callsPerSecond = 630,    -- client calls per simulated second of a busy battleground
  kbPerSecond = 50,        -- garbage made per simulated second
}

local M = require("mock")
-- the mock replaces print() so that the addon's own output can be asserted on; the report has
-- to go round it or it lands in M.printed and the run looks silent
local out = M.realPrint

-- ---------------------------------------------------------------------------
-- Count every trip into the client
-- ---------------------------------------------------------------------------

-- Lua's own, which cost the client nothing and must not be wrapped: wrapping pcall alone breaks
-- every try() in the addon.
local LUA_OWN = {}
for word in ([[assert collectgarbage dofile error getmetatable ipairs load loadfile loadstring
next pairs pcall print rawequal rawget rawlen rawset require select setmetatable tonumber
tostring type unpack xpcall gcinfo newproxy rawequal module coroutine debug io math os package
string table utf8 bit32 arg _G _VERSION]]):gmatch("%S+") do LUA_OWN[word] = true end

local counts = {}
local wrapped = {}

local function wrap(name, f)
  if wrapped[f] then return wrapped[f] end
  counts[name] = 0
  local w = function(...)
    counts[name] = counts[name] + 1
    return f(...)
  end
  wrapped[f] = w
  return w
end

local function wrapTable(t, prefix, depth)
  for k, v in pairs(t) do
    if type(k) == "string" and not LUA_OWN[k] then
      if type(v) == "function" then
        t[k] = wrap(prefix .. k, v)
      elseif type(v) == "table" and depth > 0 and k:match("^C_") then
        wrapTable(v, k .. ".", depth - 1)
      end
    end
  end
end

-- the C_ namespaces first, then the bare globals, so a function living in both is counted once
for k, v in pairs(_G) do
  if type(k) == "string" and type(v) == "table" and k:match("^C_") then wrapTable(v, k .. ".", 1) end
end
wrapTable(_G, "", 0)

local function totalCalls()
  local n = 0
  for _, c in pairs(counts) do n = n + c end
  return n
end

local function snapshot()
  local s = {}
  for k, v in pairs(counts) do s[k] = v end
  return s
end

local function since(s)
  local out, total = {}, 0
  for k, v in pairs(counts) do
    local d = v - (s[k] or 0)
    if d > 0 then out[#out + 1] = { name = k, n = d }; total = total + d end
  end
  table.sort(out, function(a, b) return a.n > b.n end)
  return out, total
end

-- ---------------------------------------------------------------------------
-- Boot
-- ---------------------------------------------------------------------------

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen",
                      class = "MAGE", race = "Scourge", sex = 2, faction = "Horde" })

local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua",
                "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua",
                "Flag.lua", "Control.lua", "Death.lua", "Threat.lua", "Comm.lua", "Rival.lua",
                "Wheel.lua", "UI.lua" }

local loadStart = os.clock()
local ns = M.load("Godslayer", FILES)
local loadTime = os.clock() - loadStart

M.fire("ADDON_LOADED", "Godslayer")
local bootCalls = snapshot()
local bootStart = os.clock()
M.fire("PLAYER_LOGIN")
local bootTime = os.clock() - bootStart
local bootList, bootTotal = since(bootCalls)

-- ---------------------------------------------------------------------------
-- Name every handler, so a cost can be attributed to the file that asked for it
-- ---------------------------------------------------------------------------

local MODULES = { "Fight", "Aura", "Ledger", "Rank", "Recap", "Field", "Flag", "Control",
                  "Death", "Threat", "Comm", "Hype" }
local owner = {}
for _, name in ipairs(MODULES) do
  local mod = ns[name]
  if mod and type(mod.handlers) == "table" then owner[mod.handlers] = name end
end

-- Time, garbage and client calls per handler. The garbage figure is exact rather than
-- sampled: the collector is stopped for the whole run below, so collectgarbage("count") only
-- ever grows and the difference across a call is what that call allocated. The wrapper's own
-- three locals are the only thing it adds to that, and they are stack slots, not heap.
local spent, fired, made, crossed = {}, {}, {}, {}
for _, t in ipairs(ns.DispatchTables()) do
  local name = owner[t] or "Core"
  for event, fn in pairs(t) do
    if type(fn) == "function" then
      local key = name .. "." .. event
      spent[key], fired[key], made[key], crossed[key] = 0, 0, 0, 0
      t[event] = function(...)
        local kb, calls, at = collectgarbage("count"), totalCalls(), os.clock()
        fired[key] = fired[key] + 1
        local a, b, c = fn(...)
        spent[key] = spent[key] + (os.clock() - at)
        made[key] = made[key] + (collectgarbage("count") - kb)
        crossed[key] = crossed[key] + (totalCalls() - calls)
        return a, b, c
      end
    end
  end
end
-- the dispatcher caches the list it built, and the tables above are the ones it cached, so the
-- wrappers are what it will call from here on

-- ---------------------------------------------------------------------------
-- A battleground, at a rate a real one reaches
-- ---------------------------------------------------------------------------
-- Warsong Gulch, ten a side, both teams in view. The numbers below are not invented: a full
-- team of nameplates is 10-20 units, UNIT_HEALTH fires on every one of them taking damage,
-- UNIT_AURA on every buff and debuff landing, and a two-minute fight over a flag is hundreds of
-- each. The point is to be somewhere near the worst minute of a real match, not an average one.

local SECONDS = tonumber(os.getenv("GS_PROFILE_SECONDS") or "180")
local PLATES = 15               -- enemy nameplates in view
local HEALTH_PER_SECOND = 40    -- UNIT_HEALTH fires across all of them
local AURA_PER_SECOND = 12      -- auras landing on you and your target
local SPELLS_PER_SECOND = 3     -- casts finishing near you
local KILL_EVERY = 12           -- seconds between kills in view

math.randomseed(7)

local roster = {}
local GUILDS = { "Olympus", "OLYMPUS BETZ", "Dark Olympus", "Mudhutters", "Method", "The Enclave" }
local CLASSES = { "WARRIOR", "MAGE", "ROGUE", "PRIEST", "DRUID", "HUNTER" }
local RACES = { "Human", "Dwarf", "Gnome", "NightElf", "Draenei", "Worgen" }
for i = 1, PLATES do
  local token = "nameplate" .. i
  roster[i] = M.addUnit(token, {
    name = "Enemy" .. i .. " Alliance",
    guid = ("Player-1-%08X"):format(0xB0000 + i),
    guild = GUILDS[(i % #GUILDS) + 1],
    class = CLASSES[(i % #CLASSES) + 1],
    race = RACES[(i % #RACES) + 1],
    faction = "Alliance",
    level = 30,
  })
  roster[i].token = token
end
M.addUnit("target", roster[1])

M.battleground({ rows = (function()
  local rows = {}
  for i = 1, 20 do
    rows[i] = { name = "Body" .. i, faction = i <= 10 and 0 or 1, race = RACES[(i % #RACES) + 1],
                gender = 2, class = CLASSES[(i % #CLASSES) + 1],
                token = CLASSES[(i % #CLASSES) + 1], rank = 7,
                guid = ("Player-1-%08X"):format(0xC0000 + i),
                kb = i, hk = i * 2, deaths = i % 5, honor = i * 10,
                damage = i * 1000, healing = i * 100 }
  end
  return rows
end)() })
M.flagsAt({ { north = 900, west = 900 }, { north = 100, west = 100 } })
M.playerAt(500, 500)
M.facing = 0.7
M.inCombat = true

M.fire("PLAYER_ENTERING_WORLD")
M.fire("PVP_MATCH_ACTIVE")
M.fire("PLAYER_REGEN_DISABLED")
-- The client announces each nameplate as it appears. Firing these is not a convenience: the
-- addon reads the set the client describes and only falls back to asking about all forty tokens
-- on a client that never announces one, so a simulation that stays silent measures the fallback
-- and not the addon.
for i = 1, PLATES do M.fire("NAME_PLATE_UNIT_ADDED", "nameplate" .. i) end

local AURAS = { { "Power Word: Shield", 17 }, { "Frost Nova", 122 }, { "Polymorph", 118 },
                { "Divine Shield", 642 }, { "Blessing of Protection", 1022 }, { "Ice Block", 45438 },
                { "Hand of Freedom", 1044 }, { "Cloak of Shadows", 31224 } }
local SPELLS = { 118, 122, 45438, 2139, 1766, 19647 }

collectgarbage("collect")
local kbBefore = collectgarbage("count")
collectgarbage("stop")
local runCalls = snapshot()
local runStart = os.clock()

local kills = 0
for second = 1, SECONDS do
  for _ = 1, HEALTH_PER_SECOND do
    M.fire("UNIT_HEALTH", "nameplate" .. math.random(PLATES))
  end
  for _ = 1, AURA_PER_SECOND do
    local a = AURAS[math.random(#AURAS)]
    local unit = math.random(2) == 1 and "player" or "target"
    M.aura(unit, "HELPFUL", a[1], a[2], 8, "target")
    M.fire("UNIT_AURA", unit)
  end
  for _ = 1, SPELLS_PER_SECOND do
    M.fire("UNIT_SPELLCAST_SUCCEEDED", "target", nil, SPELLS[math.random(#SPELLS)])
  end
  if second % KILL_EVERY == 0 then
    local v = roster[math.random(PLATES)]
    M.addUnit("target", v)
    M.fire("PLAYER_TARGET_CHANGED")
    M.fire("PARTY_KILL", ME, v.guid)
    M.hk = M.hk + 1
    M.fire("PLAYER_PVP_KILLS_CHANGED", "player")
    kills = kills + 1
  end
  -- Plates come and go as people run in and out of range, and the set has to be exercised both
  -- ways: a removal the addon never hears leaves it reading a unit that is not there.
  if second % 7 == 0 then
    local gone = "nameplate" .. math.random(PLATES)
    M.fire("NAME_PLATE_UNIT_REMOVED", gone)
    M.fire("NAME_PLATE_UNIT_ADDED", gone)
  end
  -- the player moves, so the flag watch has something to divide by
  M.playerAt(500 + math.random(-60, 60), 500 + math.random(-60, 60))
  M.advance(1)
end

local runTime = os.clock() - runStart
local kbAfter = collectgarbage("count")
collectgarbage("restart")
local runList, runTotal = since(runCalls)

-- ---------------------------------------------------------------------------
-- Report
-- ---------------------------------------------------------------------------

local function pct(n, of) return of > 0 and ("%5.1f%%"):format(n / of * 100) or "    -" end

out(("load      %21s   %d files"):format(("%.0f ms"):format(loadTime * 1000), #FILES))
out(("login     %21s   %d client calls"):format(("%.0f ms"):format(bootTime * 1000), bootTotal))
out()
out(("battleground: %d simulated seconds, %d kills, %d events"):format(
  SECONDS, kills, SECONDS * (HEALTH_PER_SECOND + AURA_PER_SECOND + SPELLS_PER_SECOND)))
out(("  cpu          %s  (%.2f ms per simulated second)"):format(
  ("%.0f ms"):format(runTime * 1000), runTime * 1000 / SECONDS))
local cps = runTotal / SECONDS
local kbs = (kbAfter - kbBefore) / SECONDS
out(("  client calls %7d   %6.0f per second   budget %d"):format(runTotal, cps, BUDGET.callsPerSecond))
out(("  garbage      %7.0f kb %6.1f kb per second   budget %d"):format(
  kbAfter - kbBefore, kbs, BUDGET.kbPerSecond))

if not CHECK then
out()
out("the calls that dominate")
for i = 1, math.min(18, #runList) do
  local r = runList[i]
  out(("  %-34s %8d %s %6.0f/s"):format(r.name, r.n, pct(r.n, runTotal), r.n / SECONDS))
end

out()
out(("%-32s %9s %9s %9s %8s"):format("handler", "ms", "kb", "calls", "fires"))
local byHandler = {}
for key, t in pairs(spent) do
  if fired[key] > 0 then
    byHandler[#byHandler + 1] = { key = key, t = t, n = fired[key], kb = made[key], c = crossed[key] }
  end
end
table.sort(byHandler, function(a, b) return a.c > b.c end)
for i = 1, math.min(14, #byHandler) do
  local h = byHandler[i]
  out(("  %-30s %9.1f %9.0f %9d %8d"):format(h.key, h.t * 1000, h.kb, h.c, h.n))
end
local function tail(field, label)
  local t = 0
  for _, h in ipairs(byHandler) do t = t + h[field] end
  out(("  %-30s %s accounted for by handlers"):format(label, pct(t, field == "kb" and (kbAfter - kbBefore) or runTotal)))
end
tail("c", "")
tail("kb", "")

out()
out(("login's own %d calls"):format(bootTotal))
for i = 1, math.min(8, #bootList) do
  out(("  %-34s %8d"):format(bootList[i].name, bootList[i].n))
end
end -- not CHECK

-- One handler's own bill, when you are working on that handler. GS_PROFILE_ONLY=Aura.UNIT_AURA
-- prints the calls that happened inside it rather than across the whole run, which is the
-- difference between knowing a handler is expensive and knowing what it spent the money on.
local ONLY = os.getenv("GS_PROFILE_ONLY")
if ONLY then
  local target
  for _, t in ipairs(ns.DispatchTables()) do
    local name = owner[t] or "Core"
    for event, fn in pairs(t) do
      if name .. "." .. event == ONLY then target = fn end
    end
  end
  if not target then
    out()
    out("no handler called " .. ONLY)
  else
    out()
    out("inside " .. ONLY .. ", one fire at a time")
    for _, unit in ipairs({ "player", "target" }) do
      local mark = snapshot()
      local kb = collectgarbage("count")
      collectgarbage("stop")
      -- the clock has to move or every fire after the first is thrown away by a throttle, and
      -- the measurement becomes a measurement of the throttle. Moved directly rather than
      -- through M.advance, which would run the tickers into the middle of the sample.
      for _ = 1, 100 do M.now = M.now + 0.3; target(unit) end
      local used = collectgarbage("count") - kb
      collectgarbage("restart")
      local list, total = since(mark)
      out(("  %-8s %6.1f calls and %5.2f kb per fire"):format(unit, total / 100, used / 100))
      for i = 1, math.min(6, #list) do
        out(("      %-32s %5.2f per fire"):format(list[i].name, list[i].n / 100))
      end
    end
  end
end

if CHECK then
  local bad = 0
  if cps > BUDGET.callsPerSecond then
    out()
    out(("OVER BUDGET: %.0f client calls per second, budget %d"):format(cps, BUDGET.callsPerSecond))
    bad = bad + 1
  end
  if kbs > BUDGET.kbPerSecond then
    out()
    out(("OVER BUDGET: %.1f kb of garbage per second, budget %d"):format(kbs, BUDGET.kbPerSecond))
    bad = bad + 1
  end
  if bad > 0 then os.exit(1) end
  out()
  out(("within budget: %.0f calls/s of %d, %.1f kb/s of %d"):format(
    cps, BUDGET.callsPerSecond, kbs, BUDGET.kbPerSecond))
end
