-- Godslayer flag: chat and score widgets make the calls; map positions only answer /flag.
--
-- Positions say which flag and where it is. They do not say home, carried or dropped, so none of
-- those states is inferred here. CHAT_MSG_BG_SYSTEM_* is authoritative when its text is recognised;
-- WSG widgets 1891/1892 are the conservative fallback.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Flag = { handlers = {} }
ns.Flag = Flag

local POLL, FLOOR, SAMPLES, MIN_DT = 1, 0.5, 5, 0.4
local FUMBLE, HOME_AFTER, LINE_MAX_AGE, DUPLICATE = 2.5, 12, 4, 1
local STILL = 1.0
local ALLIANCE_FLAG, HORDE_FLAG = 137200, 137218
local GOLD, RED, BLUE = { 1, 0.82, 0 }, { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }
local TWO_PI = math.pi * 2

local positions, positionOrder = {}, {}
local mapId, lastTick = nil, 0
local resetTurn, widgetsReady, widgetsAfter = 0, false, 0
local widgetLast = {}

local function newFlag(faction)
  return { faction = faction, state = "unknown", since = 0, recent = {}, lastVoice = -100000 }
end
local states = { Alliance = newFlag("Alliance"), Horde = newFlag("Horde") }

local function num(v)
  v = plain(v)
  if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then return nil end
  return v
end

local function now()
  return num(try(GetTime)) or 0
end

local function opts()
  local root = GodslayerDB and GodslayerDB.opts
  if not root then return { calls = "important", voice = true, repeatGap = 30 } end
  root.flag = type(root.flag) == "table" and root.flag or {}
  local o = root.flag
  if o.calls ~= "important" and o.calls ~= "all" and o.calls ~= "off" then o.calls = "important" end
  if o.voice == nil then o.voice = true end
  local gap = tonumber(o.repeatGap)
  o.repeatGap = gap and math.max(10, math.min(120, math.floor(gap + 0.5))) or 30
  return o
end
Flag.Options = opts

local function inBattleground()
  return plain(try(C_PvP and C_PvP.IsBattleground)) == true
end

local function myFaction()
  local n = num(try(_G.GetBattlefieldArenaFaction))
  if n == 0 then return "Horde" end
  if n == 1 then return "Alliance" end
  local faction = plain(try(UnitFactionGroup, "player"))
  if faction == "Alliance" or faction == "Horde" then return faction end
end

local function mine(faction)
  local side = myFaction()
  return side and faction == side or false
end

--------------------------------------------------------------------------------
-- Position readout. Records are keyed by the texture's faction identity, never by the engine's
-- reorderable flag index.
--------------------------------------------------------------------------------

local function world(x, y)
  if not (mapId and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
  local vec = plain(try(CreateVector2D, x, y))
  if type(vec) ~= "table" then return nil end
  local _, pos = try(C_Map.GetWorldPosFromMapPos, mapId, vec)
  pos = plain(pos)
  if type(pos) ~= "table" or type(pos.GetXY) ~= "function" then return nil end
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

function Flag.Turn(dx, dy, facing)
  dx, dy, facing = num(dx), num(dy), num(facing)
  if not (dx and dy and facing) or (dx == 0 and dy == 0) then return nil end
  local rel = math.atan2(dy, dx) - facing
  while rel > math.pi do rel = rel - TWO_PI end
  while rel <= -math.pi do rel = rel + TWO_PI end
  return rel
end

function Flag.Clock(rel)
  rel = num(rel)
  if not rel then return nil end
  local hour = math.floor((-rel) / (TWO_PI / 12) + 0.5) % 12
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

function Flag.Count()
  local get = _G.GetNumBattlefieldFlagPositions
  return type(get) == "function" and (num(try(get)) or 0) or 0
end

function Flag.Available()
  return type(_G.GetNumBattlefieldFlagPositions) == "function"
     and type(C_PvP and C_PvP.GetBattlefieldFlagPosition) == "function"
end

local function identity(texture)
  if texture == ALLIANCE_FLAG then return "Alliance", "Alliance flag" end
  if texture == HORDE_FLAG then return "Horde", "Horde flag" end
  if texture then return "texture:" .. tostring(texture), "A flag" end
end

local function sample(p, t, x, y)
  local s = p.samples
  s[#s + 1] = { t = t, x = x, y = y }
  while #s > SAMPLES do table.remove(s, 1) end
end

local function speed(p)
  local s = p.samples
  if #s < 2 then return nil end
  local a, b = s[1], s[#s]
  local dt = b.t - a.t
  if dt < MIN_DT then return nil end
  return dist(a.x, a.y, b.x, b.y) / dt
end

function Flag.Read()
  if not Flag.Available() then return nil, "this client has no flag positions" end
  if not mapId then return nil, "no map" end
  local mx, my = me()
  local facing = num(try(GetPlayerFacing))
  local rows = {}
  for _, key in ipairs(positionOrder) do
    local p = positions[key]
    local s = p and p.samples[#p.samples]
    if s then
      local row = { texture = p.texture, faction = p.faction, name = p.name, speed = speed(p) }
      if mx and my then
        row.yards = dist(mx, my, s.x, s.y)
        row.turn = Flag.Turn(s.x - mx, s.y - my, facing)
        row.where = row.turn and Flag.Where(row.turn) or nil
      end
      rows[#rows + 1] = row
    end
  end
  if #rows == 0 then return nil, "no carried flags on this map" end
  table.sort(rows, function(a, b)
    local ay, by = a.yards or math.huge, b.yards or math.huge
    if ay ~= by then return ay < by end
    return (a.name or "") < (b.name or "")
  end)
  return rows
end

function Flag.Row(row)
  local bits = { ("%-14s"):format(row.name or "A flag") }
  bits[#bits + 1] = row.yards and ("%5.0fy"):format(row.yards) or "    ?"
  bits[#bits + 1] = ("%-11s"):format(row.where or "")
  if row.speed and row.speed >= STILL then bits[#bits + 1] = ("%.1f y/s"):format(row.speed) end
  return "  " .. (table.concat(bits, " "):gsub("%s+$", ""))
end

function Flag.Lines()
  local rows, why = Flag.Read()
  if not rows then return nil, why end
  local out = { ("%d carried flag%s on this map:"):format(#rows, #rows == 1 and "" or "s") }
  for i = 1, #rows do out[#out + 1] = Flag.Row(rows[i]) end
  return out
end

function Flag.Clause()
  local rows = Flag.Read()
  local r = rows and rows[1]
  if not r then return nil end
  if r.yards and r.where then return ("%s is %.0f yards %s."):format(r.name, r.yards, r.where) end
  return r.name .. " is visible on the map."
end

--------------------------------------------------------------------------------
-- Calls
--------------------------------------------------------------------------------

local TITLES = {
  taken = "FLAG TAKEN", repick = "FLAG RE-PICKED", drop = "FLAG DOWN",
  returned = "FLAG RETURNED", auto = "FLAG RETURNED", captured = "FLAG CAPTURED",
}
local CLIPS = { taken = "flagtaken", repick = "flagtaken", drop = "flagdown",
  returned = "flaghome", auto = "flaghome", captured = "flaghome" }

local function titleFor(faction, event)
  local side = myFaction()
  local prefix = side and (faction == side and "YOUR" or "THEIR") or faction:upper()
  if event == "captured" then prefix = side and (faction == side and "THEY" or "YOUR TEAM") or prefix end
  return prefix .. " " .. TITLES[event]
end

local function colourFor(faction, event)
  if event == "drop" then return BLUE end
  if event == "returned" or event == "auto" then return mine(faction) and BLUE or GOLD end
  if event == "captured" then return GOLD end
  return mine(faction) and RED or GOLD
end

local function importantVoice(f, event, firstDrop)
  if event == "taken" or event == "captured" then return true end
  if event == "drop" then return firstDrop == true end
  if event == "returned" then return mine(f.faction) end
  return false
end

local function announce(f, event, line, happenedAt, firstDrop)
  local o = opts()
  if o.calls == "off" or now() - happenedAt > LINE_MAX_AGE then return end
  local title = titleFor(f.faction, event)
  local colour = colourFor(f.faction, event)
  if ns.Stage then
    if ns.Stage.FlagBanner then
      pcall(ns.Stage.FlagBanner, f.faction, title, colour, line or "", { size = 2 })
    elseif ns.Stage.Banner then
      pcall(ns.Stage.Banner, title, colour, line or "", { size = 2 })
    end
  end

  local voice = o.calls == "all" or importantVoice(f, event, firstDrop)
  if not voice or o.voice == false then return end
  if event == "drop" or event == "repick" or event == "returned" or event == "auto" then
    if now() - f.lastVoice < o.repeatGap then return end
    f.lastVoice = now()
  end
  if ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, CLIPS[event], 2, LINE_MAX_AGE) end
end

local function duplicate(f, event, t)
  local last = f.recent[event]
  if last and t - last <= DUPLICATE then return true end
  f.recent[event] = t
  return false
end

local function cancelDrop(f) f.pending = nil end

local confirmDrop
confirmDrop = function(f, token)
  local p = f.pending
  if not p or p.token ~= token then return end
  local t = now()
  if t < p.at + FUMBLE then return end
  f.pending = nil
  if f.state ~= "carried" then return end
  f.state, f.since = "down", t
  local first = not f.hadDrop
  f.hadDrop = true
  if not duplicate(f, "drop", p.at) then announce(f, "drop", p.line, p.at, first) end
end

local function service(t)
  for _, f in pairs(states) do
    if f.pending and t >= f.pending.at + FUMBLE then confirmDrop(f, f.pending.token) end
    if (f.state == "down" or f.state == "respawning") and t - f.since > HOME_AFTER then
      f.state, f.since, f.inCarry, f.hadDrop = "home", t, nil, nil
      cancelDrop(f)
    end
  end
end

local function carried(faction, line, source, t)
  service(t)
  local f = states[faction]
  if not f then return end
  if f.pending then
    if t - f.pending.at <= FUMBLE then cancelDrop(f); return end
    confirmDrop(f, f.pending.token)
  end
  if f.state == "carried" then return end
  local was = f.state
  f.state, f.since = "carried", t
  if was == "unknown" then f.inCarry, f.hadDrop = true, false; return end
  if was == "down" then
    if not duplicate(f, "repick", t) then announce(f, "repick", line, t) end
  else
    f.inCarry, f.hadDrop = true, false
    if not duplicate(f, "taken", t) then announce(f, "taken", line, t) end
  end
end

local dropToken = 0
local function dropped(faction, line, source, t)
  service(t)
  local f = states[faction]
  if not f or f.state ~= "carried" then return end
  if f.pending then
    -- Chat is stronger than the widget that may have fired first; keep the original clock so the
    -- duplicate cannot extend the fumble window.
    if source == "chat" then f.pending.line, f.pending.source = line, source end
    return
  end
  dropToken = dropToken + 1
  f.pending = { at = t, line = line, source = source, token = dropToken }
  local token = dropToken
  if C_Timer and type(C_Timer.After) == "function" then
    try(C_Timer.After, FUMBLE, function() confirmDrop(f, token) end)
  end
end

local function returned(faction, line, kind, t)
  service(t)
  local f = states[faction]
  if not f then return end
  cancelDrop(f)
  local was = f.state
  f.state, f.since, f.inCarry, f.hadDrop = "home", t, nil, nil
  if was == "unknown" or was == "home" then return end
  local event = kind == "auto" and "auto" or "returned"
  if not duplicate(f, event, t) then announce(f, event, line, t) end
end

local function captured(faction, line, source, t)
  service(t)
  local f = states[faction]
  if not f then return end
  cancelDrop(f)
  local was = f.state
  f.state, f.since, f.inCarry, f.hadDrop = "respawning", t, nil, nil
  if was == "unknown" or duplicate(f, "captured", t) then return end
  announce(f, "captured", line, t)
end

local function silentHome(faction, t)
  local f = states[faction]
  if not f then return end
  cancelDrop(f)
  f.state, f.since, f.inCarry, f.hadDrop = "home", t, nil, nil
end

function Flag.State(faction)
  local f = states[faction]
  return f and f.state, f
end

--------------------------------------------------------------------------------
-- Chat and widgets
--------------------------------------------------------------------------------

local unparsed, unparsedCount = nil, 0 -- unrecognised flag lines already written to the log, capped

local function safeLine(text)
  text = plain(text)
  if type(text) ~= "string" or #text > 240 then return nil end
  return text
end

-- The emulator texts write "flag" in lower case, other builds of the same lines capitalise it ("The
-- Horde Flag was picked up by ..."), and Forever's own text table cannot be read offline. So the
-- match ignores case and the closing punctuation; only the faction and the shape of the line count.
local SIDE = { alliance = "Alliance", horde = "Horde" }
local function side(word) return word and SIDE[word] end

local function parseLine(text)
  local low = text:lower():gsub("%s+$", ""):gsub("[!%.]+$", "")
  local faction = side(low:match("^the (%a+) flag was picked up by .+$"))
  if faction then return "carried", faction end
  faction = side(low:match("^the (%a+) flag was dropped by .+$"))
  if faction then return "dropped", faction end
  faction = side(low:match("^the (%a+) flag was returned to its base by .+$"))
  if faction then return "returned", faction end
  faction = side(low:match("^.+ captured the (%a+) flag$"))
  if faction then return "captured", faction end
  faction = side(low:match("^the (%a+) flag is now placed at its base$"))
  if faction then return "auto", faction end
  if low == "the flags are now placed at their bases" then return "reset" end
end

local function chat(text)
  text = safeLine(text)
  if not text then return end
  local event, faction = parseLine(text)
  if not event then
    -- A flag line this file does not recognise is exactly what the first real match needs to show,
    -- so it goes to the log ring once per distinct text and is otherwise ignored.
    if inBattleground() and ns.Log and text:lower():find("flag", 1, true) then
      unparsed = unparsed or {}
      if not unparsed[text] and unparsedCount < 12 then
        unparsed[text], unparsedCount = true, unparsedCount + 1
        ns.Log("flag", "unparsed " .. text)
      end
    end
    return
  end
  local t = now()
  if inBattleground() and ns.Log then ns.Log("flag", "chat " .. text) end
  if event == "carried" then carried(faction, text, "chat", t)
  elseif event == "dropped" then dropped(faction, text, "chat", t)
  elseif event == "returned" then returned(faction, text, "defender", t)
  elseif event == "captured" then captured(faction, text, "chat", t)
  elseif event == "auto" then returned(faction, text, "auto", t)
  elseif event == "reset" then silentHome("Alliance", t); silentHome("Horde", t) end
end

local WIDGET_TARGET = { [1891] = "Horde", [1892] = "Alliance" }

local function identify1640(info)
  local words = {}
  for _, key in ipairs({ "widgetTag", "textureKit", "frameTextureKit" }) do
    local value = plain(info[key])
    if type(value) == "string" then words[#words + 1] = value:lower() end
  end
  local joined = table.concat(words, " ")
  if not joined:find("flag", 1, true) then return nil end
  if joined:find("alliance", 1, true) then return "Horde" end
  if joined:find("horde", 1, true) then return "Alliance" end
end

local function widget(id, initializing)
  if not (C_UIWidgetManager and type(C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo) == "function") then return end
  local info = plain(try(C_UIWidgetManager.GetIconAndTextWidgetVisualizationInfo, id))
  if type(info) ~= "table" then return end
  local state = num(info.state)
  local text = plain(info.text)
  if state == nil or type(text) ~= "string" then return end
  local target = WIDGET_TARGET[id] or (id == 1640 and identify1640(info))
  local count = tonumber(text:match("%d+"))
  local signature = tostring(state) .. ":" .. text
  local old = widgetLast[id]
  if old and old.signature == signature and old.target == target then return end
  local isCarried = state == 2 or state == 3
  widgetLast[id] = { signature = signature, state = state, count = count, target = target, carried = isCarried }
  if inBattleground() and ns.Log then
    ns.Log("flag", ("widget %d state %s text %s"):format(id, tostring(state), text:sub(1, 80)))
  end
  if not target or (state ~= 1 and not isCarried) then return end

  local t, f = now(), states[target]
  if initializing or f.state == "unknown" then
    if f.state == "unknown" then
      f.state, f.since = isCarried and "carried" or "home", t
      f.inCarry, f.hadDrop = isCarried and true or nil, isCarried and false or nil
    end
    return
  end
  if count and old and old.count and count > old.count then
    captured(target, "Capture count increased to " .. count .. ".", "widget", t)
  elseif isCarried then
    carried(target, "Flag widget shows a carrier.", "widget", t)
  elseif (old and old.carried) or f.state == "carried" then
    dropped(target, "Flag widget no longer shows a carrier.", "widget", t)
  end
end

local function pollWidgets(initializing)
  if not inBattleground() then return end
  widget(1891, initializing)
  widget(1892, initializing)
  widget(1640, initializing)
  widgetsReady = true
end

--------------------------------------------------------------------------------
-- Tick, events, command
--------------------------------------------------------------------------------

function Flag.Tick(t)
  t = t or now()
  service(t)
  if not widgetsReady then
    if t >= widgetsAfter then pollWidgets(true) end
  else
    pollWidgets(false)
  end
  if not Flag.Available() or t - lastTick < FLOOR then return end
  lastTick = t
  mapId = num(try(C_Map and C_Map.GetBestMapForUnit, "player"))
  local n = Flag.Count()
  if n <= 0 or not mapId then positions, positionOrder = {}, {}; return end

  local seen, order = {}, {}
  for i = 1, n do
    local x, y, texture = try(C_PvP.GetBattlefieldFlagPosition, i, mapId)
    x, y, texture = num(x), num(y), num(texture)
    local key, name = identity(texture)
    if x and y and key then
      local wx, wy = world(x, y)
      if wx and wy then
        seen[key], order[#order + 1] = true, key
        local p = positions[key]
        if not p then
          p = { samples = {}, faction = (key == "Alliance" or key == "Horde") and key or nil }
          positions[key] = p
        end
        p.texture, p.name = texture, name
        sample(p, t, wx, wy)
      end
    end
  end
  for key in pairs(positions) do if not seen[key] then positions[key] = nil end end
  positionOrder = order
end

local function reset()
  -- Timers close over their old flag table. Clear pending evidence before replacing the table so a
  -- drop due on the far side of a loading screen cannot announce from the abandoned match.
  for _, f in pairs(states) do cancelDrop(f) end
  positions, positionOrder, widgetLast = {}, {}, {}
  states = { Alliance = newFlag("Alliance"), Horde = newFlag("Horde") }
  mapId, lastTick, widgetsReady, widgetsAfter = nil, 0, false, now() + 1
  resetTurn = resetTurn + 1
  local mineTurn = resetTurn
  if C_Timer and type(C_Timer.After) == "function" then
    try(C_Timer.After, 2, function() if mineTurn == resetTurn then pollWidgets(true) end end)
  end
end
Flag.Reset = reset

local h = Flag.handlers
h.PLAYER_ENTERING_WORLD = reset
h.ZONE_CHANGED_NEW_AREA = reset
h.CHAT_MSG_BG_SYSTEM_ALLIANCE = chat
h.CHAT_MSG_BG_SYSTEM_HORDE = chat
h.CHAT_MSG_BG_SYSTEM_NEUTRAL = chat
h.UPDATE_UI_WIDGET = function(info)
  info = plain(info)
  local id = type(info) == "table" and num(info.widgetID) or nil
  if (id == 1891 or id == 1892 or id == 1640) and (widgetsReady or now() >= widgetsAfter) then
    widget(id, not widgetsReady)
    widgetsReady = true
  end
end

function Flag.Command(rest)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local o = opts()
  if rest == "watch" then
    o.calls = o.calls == "off" and "important" or "off"
    ns.Print(o.calls == "off" and "Flag callouts off." or "Flag callouts on (important).")
    return
  end
  local calls = rest:match("^calls%s+(%S+)$")
  if calls then
    if calls ~= "important" and calls ~= "all" and calls ~= "off" then ns.Print("Use /godslayer flag calls important|all|off.")
    else o.calls = calls; ns.Print("Flag calls: " .. calls .. ".") end
    return
  end
  local voice = rest:match("^voice%s+(%S+)$")
  if voice then
    if voice ~= "on" and voice ~= "off" then ns.Print("Use /godslayer flag voice on|off.")
    else o.voice = voice == "on"; ns.Print("Flag voice " .. voice .. ".") end
    return
  end
  local gap = rest:match("^repeat%s+(%S+)$")
  if gap then
    gap = tonumber(gap)
    if not gap or gap < 10 or gap > 120 then ns.Print("Use /godslayer flag repeat <10-120>.")
    else o.repeatGap = math.floor(gap + 0.5); ns.Print("Flag voice repeat: " .. o.repeatGap .. " seconds.") end
    return
  end
  if rest ~= "" then ns.Print("Flag settings: calls important|all|off, voice on|off, repeat <10-120>, or watch."); return end
  if not Flag.Available() then ns.Print("This client has no flag-position API, so there is nothing to read."); return end
  Flag.Tick()
  local lines, why = Flag.Lines()
  if not lines then ns.Print("No flags: " .. tostring(why) .. ".")
  else for _, line in ipairs(lines) do ns.Print(line) end end
  ns.Print(("Calls: %s; voice %s; repeat %ds. Positions only report texture identity, distance and direction.")
    :format(o.calls, o.voice and "on" or "off", o.repeatGap))
end

function Flag.Init()
  reset()
  if not Flag.Available() and ns.Log then ns.Log("flag", "no GetNumBattlefieldFlagPositions on this client") end
  if C_Timer and type(C_Timer.NewTicker) == "function" then try(C_Timer.NewTicker, POLL, function() Flag.Tick() end) end
end
