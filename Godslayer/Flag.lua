-- Godslayer flag: where the flag is while the map is shut.
--
-- THIS ONE IS NOT A GAP. Every other file added in 2.6.0 reads something the client is willing to
-- say and shows it where nothing else does. This one does not get that excuse, because Forever
-- already draws the flags, on both maps:
--
--     Blizzard_WorldMap/Blizzard_WorldMap.lua:209
--       self:AddDataProvider(CreateFromMixins(BattlefieldFlagDataProviderMixin));
--     Blizzard_BattlefieldMap/Mainline/Blizzard_BattlefieldMap.lua:199
--       self:AddDataProvider(CreateFromMixins(BattlefieldFlagDataProviderMixin));
--
-- `Blizzard_SharedMapDataProviders` is gated `AllowLoadGameType: mainline`, and camelot is inside
-- the mainline family, so that provider is in this game. An earlier round of these notes said the
-- flags wanted a map pin. They have one.
--
-- WHAT A PIN CANNOT DO. It is a texture at a normalised position, refreshed in `OnUpdate`:
--
--     BattlefieldFlagDataProvider.lua:43
--       local flagX, flagY, flagTexture = C_PvP.GetBattlefieldFlagPosition(self.flagIndex, ...)
--
-- So it is live, and it tells you where. It does not tell you how far in yards, which way to
-- turn, how fast that is moving, whether it has stopped -- and it does not exist at all while the
-- map is closed, which in a Warsong game is all of the time that matters. Everything below is
-- arithmetic on the same two returns, said out loud.
--
-- THE MATH, because it is the part that can be quietly wrong. `GetBattlefieldFlagPosition` and
-- `C_Map.GetPlayerMapPosition` both answer in normalised map space, which is not a distance: the
-- same 0.1 is a different number of yards on every map and a different number across a map than
-- down it. So both points go through `C_Map.GetWorldPosFromMapPos`, which hands back real world
-- yards, and the distance is taken there. World coordinates run x north and y west, and
-- `GetPlayerFacing` is radians counter-clockwise from north, so a bearing of `atan2(dy, dx)` is
-- already in the same frame as the player's facing and the difference is the turn to make.
--
-- WHICH FLAG IS WHICH, learned rather than hard-coded. `GetBattlefieldFlagPosition` gives an
-- index and a texture id and no faction, and there is no call anywhere that says whose flag an
-- index is. But a flag sits at its own base until somebody takes it, so the first position an
-- index holds is that flag's home -- and when the gates open you are standing at yours. Both
-- readings are inferences and both are gated on their own confidence: if the first sighting was
-- already moving, this does not claim a home, and if your first reading was not clearly nearer
-- one base than the other, it does not claim a side. It says "a flag" and gives you the yards.
--
-- The cap run falls out of the homes for free and without knowing anything about the map: you
-- score by carrying their flag to yours, so the destination of a carried flag is the *other*
-- flag's home. With one flag on the map there is no other home and that call is simply not made.
--
--   /godslayer flag        both flags, distance, bearing, speed
--   /godslayer flag watch  turn the callouts on or off

local _, ns = ...
local plain, try = ns.plain, ns.try

local Flag = { handlers = {} }
ns.Flag = Flag

local POLL = 1              -- seconds between readings
local FLOOR = 0.5           -- the throttle, deliberately under POLL for the reason in Field.lua:
                            -- a floor equal to the period throws away every tick that lands early
local SAMPLES = 5           -- positions kept per flag, oldest to newest
local MIN_DT = 0.4          -- the shortest gap worth dividing by for a speed
local STILL = 1.0           -- yards per second below which a flag is not moving
local HOME_R = 25           -- yards from its home inside which a flag counts as at home
local MINE_NEAR = 120       -- your first reading has to be this close to one home to claim it
local MINE_FAR = 220        -- and this far from every other one
local CALL_GAP = 4          -- seconds between two callouts
local CLOSE_AT = 60         -- yards from the cap at which a carrier is called as closing
local DROP_AFTER = 1.5      -- seconds still, off home, before a flag is called dropped
local GOLD, RED, BLUE = { 1, 0.82, 0 }, { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }

local TWO_PI = math.pi * 2

local flags = {}            -- [index] = { samples, home, homeSure, mine, state, since, texture }
local mapId, lastTick, lastCall, firstRead = nil, 0, 0, false
local watching = true

-- A number from the engine, or nil. The finiteness test is not decoration: this file is the only
-- one in the addon that does arithmetic on the engine's answers, and a NaN compares false against
-- everything, so every threshold here quietly says no, every state reads as unknown, and the
-- first thing to actually complain is a `%d` in the report three screens away. The soak found
-- that exact crash from a facing of 0/0.
local function num(v)
  v = plain(v)
  if type(v) ~= "number" then return nil end
  if v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

--------------------------------------------------------------------------------
-- Positions
--------------------------------------------------------------------------------

-- A normalised map point in world yards, or nil. `GetWorldPosFromMapPos` is declared
-- `MayReturnNothing`, so an absent answer is the documented case and not an error.
local function world(x, y)
  if not (mapId and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local vec = plain(try(CreateVector2D, x, y))
  if type(vec) ~= "table" then return nil end
  local _, pos = try(C_Map.GetWorldPosFromMapPos, mapId, vec)
  pos = plain(pos)
  if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
  -- try() first and plain() per value, never plain(try(...)) around a call that returns more than
  -- one thing: plain takes a single value, so wrapping it round the call throws the rest away and
  -- the second coordinate silently becomes nil.
  local wx, wy = try(pos.GetXY, pos)
  wx, wy = num(wx), num(wy)
  if not (wx and wy) then return nil end
  return wx, wy
end

local function me()
  if not (mapId and C_Map and C_Map.GetPlayerMapPosition) then return nil end
  local pos = plain(try(C_Map.GetPlayerMapPosition, mapId, "player"))
  if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
  local x, y = try(pos.GetXY, pos)
  x, y = num(x), num(y)
  if not (x and y) then return nil end
  return world(x, y)
end

local function dist(ax, ay, bx, by)
  local dx, dy = bx - ax, by - ay
  return math.sqrt(dx * dx + dy * dy)
end

--------------------------------------------------------------------------------
-- Bearing
--------------------------------------------------------------------------------

-- The turn to make, in radians, positive to the left. World y runs west and `GetPlayerFacing`
-- counts counter-clockwise from north, so both are already in one frame and this is a plain
-- subtraction; the wrap is what keeps it in (-pi, pi] so that 350 degrees reads as ten to the
-- right rather than three hundred and fifty to the left.
function Flag.Turn(dx, dy, facing)
  dx, dy = num(dx), num(dy)
  if not (dx and dy) then return nil end
  if dx == 0 and dy == 0 then return nil end
  if dx ~= dx or dy ~= dy then return nil end
  facing = num(facing)
  if not facing then return nil end
  local rel = math.atan2(dy, dx) - facing
  while rel > math.pi do rel = rel - TWO_PI end
  while rel <= -math.pi do rel = rel + TWO_PI end
  return rel
end

-- A turn as a clock face, which is how anybody actually says it. Twelve is straight ahead and the
-- numbers go up to the right, so a target to the right is a negative turn and the sign flips here.
function Flag.Clock(rel)
  rel = num(rel)
  if not rel then return nil end
  local hour = math.floor((-rel) / (TWO_PI / 12) + 0.5) % 12
  if hour ~= hour then return nil end
  if hour == 0 then hour = 12 end
  return hour
end

function Flag.Where(rel)
  local hour = Flag.Clock(rel)
  if not hour then return nil end
  if hour == 12 then return "ahead" end
  if hour == 6 then return "behind" end
  return ("%d o'clock"):format(hour)
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Flag.Count()
  local get = _G.GetNumBattlefieldFlagPositions
  if type(get) ~= "function" then return 0 end
  return num(try(get)) or 0
end

-- Whether this client has the call at all. It is used by `BattlefieldFlagDataProvider` and is in
-- none of the 642 generated documentation files, so its absence is a real possibility rather than
-- a defensive flourish, and the command says so plainly rather than reporting an empty field.
function Flag.Available()
  return type(_G.GetNumBattlefieldFlagPositions) == "function"
     and type(C_PvP and C_PvP.GetBattlefieldFlagPosition) == "function"
end

local function sample(f, now, wx, wy)
  local s = f.samples
  s[#s + 1] = { t = now, x = wx, y = wy }
  while #s > SAMPLES do table.remove(s, 1) end
end

-- Yards per second over the whole window rather than the last pair. One pair across a short tick
-- is mostly jitter; the window is still under three seconds, which is well inside the time a
-- carrier takes to cross anything worth calling.
local function speed(f)
  local s = f.samples
  if #s < 2 then return nil end
  local a, b = s[1], s[#s]
  local dt = b.t - a.t
  if dt < MIN_DT then return nil end
  return dist(a.x, a.y, b.x, b.y) / dt
end

--------------------------------------------------------------------------------
-- Homes, and which one is yours
--------------------------------------------------------------------------------

-- The first position an index holds is that flag's home, and whether to believe it is decided by
-- whether the thing was moving when we first saw it. Zoning in halfway through a match with their
-- flag already out gives a "home" that is really somebody's feet, so that case is recorded as
-- unsure and every claim built on a home is skipped for it.
local function learnHome(f)
  if f.home then
    -- A flag that is still, near the home we guessed, tightens the guess. A still flag far from it
    -- is a dropped flag, not a correction, so it is left alone.
    local sp = speed(f)
    if sp and sp < STILL and f.homeSure then
      local s = f.samples[#f.samples]
      if dist(f.home.x, f.home.y, s.x, s.y) <= HOME_R then f.home = { x = s.x, y = s.y } end
    end
    return
  end
  if #f.samples < 2 then return end
  local sp = speed(f)
  if sp == nil then return end
  local s = f.samples[#f.samples]
  f.home = { x = s.x, y = s.y }
  f.homeSure = (sp < STILL)
end

-- Which flag is yours, from where you were standing the first time we could read any of this. The
-- gates open with you at your own base, so the nearest home is yours -- but only if it is clearly
-- nearest, because a player who zoned in late or is already at midfield has no claim to make and
-- a wrong one here mislabels every line in the report.
local function learnSide(mx, my)
  if firstRead then return end
  local near, nearD, secondD = nil, nil, nil
  for i, f in pairs(flags) do
    if f.home and f.homeSure then
      local d = dist(mx, my, f.home.x, f.home.y)
      if not nearD or d < nearD then
        secondD = nearD
        near, nearD = i, d
      elseif not secondD or d < secondD then
        secondD = d
      end
    end
  end
  if not near then return end
  firstRead = true
  if nearD > MINE_NEAR then return end
  if secondD and secondD < MINE_FAR then return end
  flags[near].mine = true
  for i, f in pairs(flags) do if i ~= near then f.mine = false end end
end

function Flag.Name(f)
  if f.mine == true then return "Yours" end
  if f.mine == false then return "Theirs" end
  return "A flag"
end

-- Where a carried flag has to get to. You cap by bringing their flag to your base, so the
-- destination is the other flag's home; with any number of flags other than two there is no
-- single other home and this returns nil rather than picking one.
local function capAt(index)
  local other, n = nil, 0
  for i, f in pairs(flags) do
    n = n + 1
    if i ~= index and f.home and f.homeSure then other = f.home end
  end
  if n ~= 2 then return nil end
  return other
end

--------------------------------------------------------------------------------
-- State
--------------------------------------------------------------------------------

-- Nil until there is enough history to know, which matters more than it looks. One sample gives
-- no speed, and a flag with no speed is indistinguishable from a flag standing still -- so an
-- earlier version of this called every flag "on the floor" for its first second and then
-- announced each of them coming home. A state nobody can know yet is not a state.
local function stateOf(f)
  local s = f.samples[#f.samples]
  if not s then return nil end
  local sp = speed(f)
  if sp == nil then return nil end
  if f.home and f.homeSure and dist(f.home.x, f.home.y, s.x, s.y) <= HOME_R then return "home" end
  if sp >= STILL then return "carried" end
  return "dropped"
end

-- The sounds are picked from the ones the addon actually ships -- `ns.SFX` is the list, and
-- `Hype.Sfx` quietly returns false for a name that is not in it, which is exactly how a sound
-- that was never recorded becomes a silent banner nobody can explain.
local function call(title, colour, line, sound, clip)
  if not watching then return end
  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.on == false then return end
  local now = plain(try(GetTime)) or 0
  if now - lastCall < CALL_GAP then return end
  lastCall = now
  if ns.Stage and ns.Stage.Banner then pcall(ns.Stage.Banner, title, colour, line or "", { size = 2 }) end
  if sound and ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, sound) end
  if clip and ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, clip, 2) end
end

-- One transition, one call. The states are deliberately coarse -- a flag is at a base, in hands,
-- or on the floor -- because a carrier who stops for two seconds to fight has not dropped it and
-- an addon that says so twice a fight is an addon people turn off.
local function changed(f, was, now, row)
  if was == now then return end
  local who = Flag.Name(f)
  if now == "carried" and was == "home" then
    call(who:upper() .. " FLAG TAKEN", f.mine == true and RED or GOLD,
      row and row.line or "", "horn", "flagtaken")
  elseif now == "dropped" then
    call(who:upper() .. " FLAG DOWN", BLUE, row and row.line or "", "sig_ground", "flagdown")
  elseif now == "home" and was ~= nil then
    call(who:upper() .. " FLAG HOME", f.mine == true and BLUE or GOLD, "", "fanfare", "flaghome")
  end
end

--------------------------------------------------------------------------------
-- The rows
--------------------------------------------------------------------------------

-- Every flag the engine will place on this map, with the arithmetic done. Returns nil and a
-- reason rather than an empty list, because "no flags here" and "this client cannot answer" are
-- different answers and a caller that cannot tell them apart will print the wrong one.
function Flag.Read()
  if not Flag.Available() then return nil, "this client has no flag positions" end
  local n = Flag.Count()
  if n <= 0 then return nil, "no flags on this map" end
  if not mapId then return nil, "no map" end

  local mx, my = me()
  local facing = num(try(GetPlayerFacing))
  local rows = {}
  for i = 1, n do
    local f = flags[i]
    if f then
      local s = f.samples[#f.samples]
      if s then
        local row = { index = i, state = f.state, mine = f.mine, name = Flag.Name(f),
                      speed = speed(f), texture = f.texture, home = f.home and f.homeSure or false }
        if mx and my then
          row.yards = dist(mx, my, s.x, s.y)
          row.turn = Flag.Turn(s.x - mx, s.y - my, facing)
          row.where = row.turn and Flag.Where(row.turn) or nil
        end
        local cap = (f.state == "carried") and capAt(i) or nil
        if cap then row.toCap = dist(s.x, s.y, cap.x, cap.y) end
        rows[#rows + 1] = row
      end
    end
  end
  if #rows == 0 then return nil, "nothing read yet" end
  table.sort(rows, function(a, b)
    if (a.mine == true) ~= (b.mine == true) then return a.mine == true end
    local ay, by = a.yards or math.huge, b.yards or math.huge
    if ay ~= by then return ay < by end
    return a.index < b.index
  end)
  return rows
end

local STATE_TEXT = { home = "at home", carried = "carried", dropped = "on the floor" }

function Flag.Row(row)
  local bits = {}
  bits[#bits + 1] = ("%-7s"):format(row.name)
  bits[#bits + 1] = ("%-11s"):format(row.state and (STATE_TEXT[row.state] or row.state) or "just seen")
  bits[#bits + 1] = row.yards and ("%5.0fy"):format(row.yards) or "    ?"
  bits[#bits + 1] = ("%-11s"):format(row.where or "")
  if row.speed and row.speed >= STILL then bits[#bits + 1] = ("%.1f y/s"):format(row.speed) end
  if row.toCap then bits[#bits + 1] = ("%.0fy from the cap"):format(row.toCap) end
  return "  " .. (table.concat(bits, " "):gsub("%s+$", ""))
end

function Flag.Lines()
  local rows, why = Flag.Read()
  if not rows then return nil, why end
  local out = { ("%d flag%s on this map:"):format(#rows, #rows == 1 and "" or "s") }
  for i = 1, #rows do out[#out + 1] = Flag.Row(rows[i]) end
  local unsure = 0
  for _, f in pairs(flags) do if f.home and not f.homeSure then unsure = unsure + 1 end end
  if unsure > 0 then
    out[#out + 1] = ("%d of them were already moving when I first saw them, so I am not calling a base for those."):format(unsure)
  end
  return out
end

-- One line for the battleground report and the death card. Only the things worth interrupting
-- somebody with: a flag in hands, and how close it is to scoring.
function Flag.Clause()
  local rows = Flag.Read()
  if not rows then return nil end
  for i = 1, #rows do
    local r = rows[i]
    if r.state == "carried" then
      if r.toCap and r.toCap <= CLOSE_AT then
        return ("%s flag is %.0f yards from the cap."):format(r.name, r.toCap)
      end
      if r.yards and r.where then
        return ("%s flag is up, %.0f yards %s."):format(r.name, r.yards, r.where)
      end
      return ("%s flag is up."):format(r.name)
    end
  end
  return nil
end

--------------------------------------------------------------------------------
-- The tick
--------------------------------------------------------------------------------

function Flag.Tick(now)
  if not Flag.Available() then return end
  now = now or plain(try(GetTime)) or 0
  if now - lastTick < FLOOR then return end
  lastTick = now

  mapId = num(try(C_Map and C_Map.GetBestMapForUnit, "player"))
  local n = Flag.Count()
  if n <= 0 or not mapId then return end

  local get = C_PvP.GetBattlefieldFlagPosition
  local seen = {}
  for i = 1, n do
    local x, y, texture = try(get, i, mapId)
    x, y, texture = num(x), num(y), num(texture)
    -- A nil x is the engine saying this flag is not on the map being asked about. Blizzard's own
    -- pin reads the same thing and hides itself; here it means leave the flag's history alone
    -- rather than record a position of zero.
    if x and y then
      local wx, wy = world(x, y)
      if wx and wy then
        seen[i] = true
        local f = flags[i]
        if not f then f = { samples = {} } flags[i] = f end
        f.texture = texture or f.texture
        sample(f, now, wx, wy)
        learnHome(f)
        local was = f.state
        f.state = stateOf(f)
        if was ~= f.state then f.since = now end
        if was and was ~= f.state then
          -- The row is built before the callout so the banner can carry the yards.
          local rows = Flag.Read()
          local row = nil
          for k = 1, #(rows or {}) do if rows[k].index == i then row = rows[k] end end
          if row then row.line = Flag.Row(row):gsub("^%s+", "") end
          changed(f, was, f.state, row)
        end
      end
    end
  end

  local mx, my = me()
  if mx and my then learnSide(mx, my) end

  for i in pairs(flags) do if not seen[i] then flags[i] = nil end end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Flag.handlers

local function reset()
  flags, firstRead, lastTick, lastCall = {}, false, 0, 0
  mapId = nil
end
Flag.Reset = reset

function h.PLAYER_ENTERING_WORLD()
  reset()
end

function h.ZONE_CHANGED_NEW_AREA()
  reset()
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

function Flag.Command(rest)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()

  if rest == "watch" then
    watching = not watching
    ns.Print(watching and "Flag callouts on." or "Flag callouts off.")
    return
  end

  if not Flag.Available() then
    ns.Print("This client has no GetNumBattlefieldFlagPositions, so there is nothing to read.")
    ns.Print("Forever's own map pins use that call, so if the maps draw flags and this does not, say so.")
    return
  end

  Flag.Tick()
  local lines, why = Flag.Lines()
  if not lines then
    ns.Print("No flags: " .. tostring(why) .. ".")
    ns.Print("Only some battlegrounds have a moving flag. Arathi Basin has none.")
    return
  end
  for _, line in ipairs(lines) do ns.Print(line) end
  local clause = Flag.Clause()
  if clause then ns.Print(clause) end
  ns.Print("Blizzard draws these on the map too. This is the half you can read with it shut.")
end

function Flag.Init()
  if not Flag.Available() then
    if ns.Log then ns.Log("flag", "no GetNumBattlefieldFlagPositions on this client") end
    return
  end
  local ticker = C_Timer and C_Timer.NewTicker
  if type(ticker) == "function" then try(ticker, POLL, function() Flag.Tick() end) end
end
