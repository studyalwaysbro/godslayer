-- Godslayer guild sync: everyone in your guild who runs the addon broadcasts their
-- totals on the hidden addon channel, and the leaderboard is built from what arrives.
-- Totals are self-reported. Nothing here is visible in chat.

local _, ns = ...
local plain, try = ns.plain, ns.try

local PREFIX = "Godslayer"
local PROTO = 1
local MIN_GAP = 5            -- seconds between our own broadcasts
local ROSTER_MAX_AGE = 60 * 86400

local Comm = { handlers = {} }
ns.Comm = Comm

local dirty, lastSend, lastReply, helloTries = false, 0, 0, 0
-- The game does not always report our own name the way we read it, so every message
-- carries a random tag for this session and we drop the ones that carry ours.
local token = ("%06x"):format(math.random(0, 0xFFFFFF))

local function guildName()
  if not plain(try(IsInGuild)) then return nil end
  local g = plain((try(GetGuildInfo, "player")))
  if type(g) == "string" and g ~= "" then return g end
end
ns.MyGuild = guildName

local function lockedDown()
  return C_ChatInfo and C_ChatInfo.InChatMessagingLockdown and plain(try(C_ChatInfo.InChatMessagingLockdown)) == true
end
ns.ChatLockedDown = lockedDown

local function send(msg)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) then return false end
  if not plain(try(IsInGuild)) or lockedDown() then return false end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, msg, "GUILD")
  res = plain(res)
  -- newer clients return a result code (0 = sent), older ones true, some nothing
  local sent = ok and (res == nil or res == true or res == 0)
  if not sent then ns.Log("comm", "send refused: " .. tostring(res)) end
  return sent
end

local function statsMessage()
  local c = ns.char
  return table.concat({ "S", PROTO, c.kills, c.points, c.uniques, c.kb, c.orig, c.class or "", ns.VERSION, c.kings or 0, token }, ";")
end

local function broadcast()
  if not dirty then return end
  if GetTime() - lastSend < MIN_GAP then return end
  lastSend = GetTime()
  if send(statsMessage()) then dirty = false end
end

function Comm.MarkDirty()
  dirty = true
  C_Timer.After(MIN_GAP + 0.5, broadcast)
end

local function hello()
  -- the guild name is not known for the first moments after login
  if not guildName() or not send("H;" .. PROTO .. ";" .. token) then
    helloTries = helloTries + 1
    if helloTries < 6 and plain(try(IsInGuild)) then C_Timer.After(15, hello) end
    return
  end
  dirty = true
  C_Timer.After(2, broadcast)
end

local function shortName(sender)
  -- strip a realm suffix when there is one; Forever names are "First Last" with none
  if type(Ambiguate) == "function" then
    local a = plain(try(Ambiguate, sender, "guild"))
    if type(a) == "string" and a ~= "" then return a end
  end
  return sender
end

local function count(v)
  v = tonumber(v)
  if not v or v < 0 or v > 1e7 or v ~= math.floor(v) then return nil end
  return v
end

local RELEASES = "github.com/studyalwaysbro/godslayer/releases"
-- A guildmate running a newer version means there is one to get. Said once per session.
local function versionNumber(v)
  local a, b, c = tostring(v):match("^(%d+)%.(%d+)%.?(%d*)")
  if not a then return nil end
  return tonumber(a) * 1000000 + tonumber(b) * 1000 + (tonumber(c) or 0)
end
local toldNewer = false
local function noteVersion(theirs)
  if toldNewer or type(theirs) ~= "string" or #theirs > 12 then return end
  local mine, other = versionNumber(ns.VERSION), versionNumber(theirs)
  if not (mine and other) or other <= mine then return end
  toldNewer = true
  ns.Print(("version %s is out and you have %s. With Yeeterson Forge it arrives by itself. Otherwise download it from %s"):format(theirs, ns.VERSION, RELEASES))
end
Comm.NoteVersion = noteVersion

-- A big moment of our own, for the guild: GODLIKE, a RAMPAGE, GODSLAYER, the King. Older versions
-- do not know the message and drop it.
-- One that cannot go now (inside an instance, or right after the last) waits its turn, for a while.
local lastStreak, pendingStreaks = -1000, {}
local STREAK_GAP, STREAK_KEEP, STREAK_PENDING = 20, 600, 4
local function flushStreaks()
  local now = GetTime()
  while pendingStreaks[1] and now - pendingStreaks[1].t > STREAK_KEEP do table.remove(pendingStreaks, 1) end
  local p = pendingStreaks[1]
  if not p or (p.kind ~= "regicide" and now - lastStreak < STREAK_GAP) then return end
  if not send(table.concat({ "R", PROTO, p.kind, token }, ";")) then return end
  table.remove(pendingStreaks, 1)
  lastStreak = now
  if pendingStreaks[1] then C_Timer.After(STREAK_GAP + 0.5, flushStreaks) end
end
function Comm.Streak(kind)
  if not (ns.Hype and ns.Hype.STREAKS and ns.Hype.STREAKS[kind]) then return false end
  if #pendingStreaks >= STREAK_PENDING then table.remove(pendingStreaks, 1) end
  pendingStreaks[#pendingStreaks + 1] = { kind = kind, t = GetTime() }
  local waiting = #pendingStreaks
  flushStreaks()
  if #pendingStreaks >= waiting and pendingStreaks[1] then C_Timer.After(STREAK_GAP + 0.5, flushStreaks) end
  return true
end
Comm.PendingStreaks = function() return #pendingStreaks end

-- The chat wheel, for the people you are grouped with: their Godslayer plays the same line.
function Comm.Wheel(n)
  if not (C_ChatInfo and C_ChatInfo.SendAddonMessage) or lockedDown() then return false end
  local group = plain(try(GetNumGroupMembers)) or 0
  if group <= 1 then return false end
  local channel = plain(try(IsInRaid)) and "RAID" or "PARTY"
  -- a group the game made for a battleground talks on its own channel
  local instance = LE_PARTY_CATEGORY_INSTANCE
  if instance and plain(try(IsInGroup, instance)) then channel = "INSTANCE_CHAT" end
  local ok, res = pcall(C_ChatInfo.SendAddonMessage, PREFIX, table.concat({ "W", PROTO, n, token }, ";"), channel)
  res = plain(res)
  return ok and (res == nil or res == true or res == 0)
end

function Comm.handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
  prefix, text, channel, sender = plain(prefix), plain(text), plain(channel), plain(sender)
  if prefix ~= PREFIX then return end
  if channel ~= "GUILD" and channel ~= "PARTY" and channel ~= "RAID" and channel ~= "INSTANCE_CHAT" then return end
  if type(text) ~= "string" or type(sender) ~= "string" then return end
  local who = shortName(sender):gsub("|", ""):sub(1, 48) -- no escape codes in the roster
  if who == ns.myName or sender == ns.myName then return end -- our own message echoed back

  local kind, proto, a, b, c, d, e, class, ver, kings, tag = strsplit(";", text)
  if tonumber(proto) ~= PROTO then return end
  -- the group hears the wheel; everything else is the guild's
  if (kind == "W") ~= (channel ~= "GUILD") then return end
  if kind == "W" or kind == "R" then
    if b == token then return end
    if kind == "W" and ns.Wheel then
      local ok, err = pcall(ns.Wheel.Heard, who, tonumber(a))
      if not ok then ns.errors = (ns.errors or 0) + 1 ns.Log("error", "wheel: " .. tostring(err)) end
    elseif kind == "R" and ns.Hype then
      local ok, err = pcall(ns.Hype.AllyStreak, who, a)
      if not ok then ns.errors = (ns.errors or 0) + 1 ns.Log("error", "hype streak: " .. tostring(err)) end
    end
    return
  end
  if tag == token or (kind == "H" and a == token) then return end -- ours, under another spelling of our name
  if kind == "H" then
    if GetTime() - lastReply > 20 then
      lastReply = GetTime()
      dirty = true
      C_Timer.After(1 + math.random() * 5, broadcast) -- spread replies out
    end
  elseif kind == "S" then
    local kills, points, uniques, kb, orig = count(a), count(b), count(c), count(d), count(e)
    if not (kills and points and uniques and kb and orig) then return end
    -- totals that cannot come from the scoring rules are dropped
    if points < kills or points > kills * ns.ORIGINAL_POINTS or uniques > kills or kb > kills or orig > kills then return end
    local guild = guildName()
    if not guild then return end
    local db = GodslayerDB
    db.roster[guild] = db.roster[guild] or {}
    -- their score went up since we last heard from them: that is a kill worth knowing about.
    -- A first sighting or a stale record is not, or logging in would announce everyone.
    local before = db.roster[guild][who]
    local gained = before and time() - (before.t or 0) < 6 * 3600 and points - (before.points or 0) or 0
    local newKills = before and kills - (before.kills or 0) or 0
    -- points with no kills behind them, or more than a handful at once, are a recount or a lie, not a kill
    if gained >= 1 and newKills >= 1 and newKills <= 5 and gained <= newKills * ns.ORIGINAL_POINTS and ns.Hype then
      local ok, err = pcall(ns.Hype.Ally, who, gained)
      if not ok then ns.errors = (ns.errors or 0) + 1 ns.Log("error", "hype ally: " .. tostring(err)) end
    end
    db.roster[guild][who] = {
      kills = kills, points = points, uniques = uniques, kb = kb, orig = orig,
      class = (type(class) == "string" and class:match("^%u+$")) and class or nil,
      ver = type(ver) == "string" and ver:match("^[%w%.%-]+$") and ver:sub(1, 12) or nil,
      kings = math.min(count(kings) or 0, orig),
      t = time(),
    }
    noteVersion(db.roster[guild][who].ver)
    if ns.OnChanged then ns.OnChanged() end
  end
end

function Comm.handlers.PLAYER_ENTERING_WORLD()
  if dirty then C_Timer.After(MIN_GAP, broadcast) end
  -- out of an instance: whatever we could not tell the guild in there goes now
  if pendingStreaks[1] then C_Timer.After(MIN_GAP, flushStreaks) end
end

-- Everyone we have totals for in the current guild, plus ourselves, best first.
function Comm.Leaderboard()
  local rows = {}
  local c = ns.char
  rows[1] = { name = ns.myName, kills = c.kills, points = c.points, uniques = c.uniques,
              kb = c.kb, orig = c.orig, kings = c.kings or 0, class = c.class, me = true }
  local guild = guildName()
  local roster = guild and GodslayerDB.roster[guild]
  if roster then
    for name, r in pairs(roster) do
      if name ~= ns.myName then
        rows[#rows + 1] = { name = name, kills = r.kills, points = r.points, uniques = r.uniques,
                            kb = r.kb, orig = r.orig, kings = r.kings or 0, class = r.class, t = r.t }
      end
    end
  end
  table.sort(rows, function(x, y)
    if x.points ~= y.points then return x.points > y.points end
    if x.kills ~= y.kills then return x.kills > y.kills end
    return x.name < y.name
  end)
  return rows, guild
end

function Comm.ForgetRoster()
  local guild = guildName()
  if guild then GodslayerDB.roster[guild] = nil end
end

function Comm.Init()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX)
  end
  local now = time()
  for _, roster in pairs(GodslayerDB.roster) do
    for name, r in pairs(roster) do
      if now - (r.t or 0) > ROSTER_MAX_AGE then roster[name] = nil end
    end
  end
  C_Timer.After(10, hello)
  C_Timer.NewTicker(30, function() broadcast() flushStreaks() end) -- picks up anything a lockdown or throttle held back
end
