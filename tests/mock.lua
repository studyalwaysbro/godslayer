-- Minimal stand-in for the WoW client API, enough to load and drive Godslayer offline.
local M = { now = 1000, wall = 1791400000, timers = {}, units = {}, guids = {}, group = {},
            sentAddon = {}, sentChat = {}, printed = {}, events = {}, frames = {}, lockdown = false,
            inGuild = true, myGuild = "The True Torchmen", hk = 0, addonResult = 0,
            zone = "Stranglethorn Vale", subzone = "Nesingwary's Expedition", myLevel = 30 }

-- secret values: any use other than passing them around blows up
local secretMT = {
  __index = function() error("indexed a secret value") end,
  __concat = function() error("concatenated a secret value") end,
  __lt = function() error("compared a secret value") end,
  __call = function() error("called a secret value") end,
  __tostring = function() return "<secret>" end,
}
function M.secret() return setmetatable({}, secretMT) end
function issecretvalue(v) return getmetatable(v) == secretMT end

function GetTime() return M.now end
function time() return M.wall end
-- like the client's date(): a format and an optional time; UTC here so runs are repeatable
function date(fmt, t)
  if M.dateError then error("date blew up") end
  return os.date("!" .. (fmt or "%c"), t or M.wall)
end
local realPrint = print
function print(...) local t = {} for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end M.printed[#M.printed + 1] = table.concat(t, " ") end
M.realPrint = realPrint
function strsplit(sep, s) local out = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end return unpack(out) end
function Ambiguate(n) return (n:gsub("%-.*$", "")) end
UNKNOWNOBJECT = "Unknown"
RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
SOUNDKIT = { RAID_WARNING = 8959 }
function PlaySound() end
-- sound files and music: M.audio.files names the files that exist on disk
M.audio = { files = {}, played = {}, stopped = {}, music = nil, musicStops = 0, cvars = { Sound_EnableAllSound = "1", Sound_EnableMusic = "1" }, next = 0 }
function PlaySoundFile(path, channel)
  assert(type(path) == "string" and (channel == "Master" or channel == "Dialog" or channel == "SFX"), "PlaySoundFile(path, channel)")
  M.audio.channel = channel
  if not M.audio.files[path] then return false end
  M.audio.next = M.audio.next + 1
  M.audio.played[#M.audio.played + 1] = { path = path, handle = M.audio.next, at = M.now }
  return true, M.audio.next
end
function StopSound(handle, fade) assert(type(handle) == "number") M.audio.stopped[handle] = fade or 0 end
function PlayMusic(path) assert(M.audio.files[path], "PlayMusic on a missing file") M.audio.music = path end
function StopMusic() if M.audio.music then M.audio.musicStops = M.audio.musicStops + 1 end M.audio.music = nil end
function GetCVar(name) return M.audio.cvars[name] end
function SetCVar(name, value) if M.audio.lockCVars then return end M.audio.cvars[name] = tostring(value) M.audio.sets = (M.audio.sets or 0) + 1 end
M.audio.cvars.Sound_MusicVolume = "0.8"
M.shots = 0
function Screenshot() M.shots = M.shots + 1 end
function UnitHealth(t) if M.secretHealth then return M.secret() end return t == "player" and (M.myHealth or 100) or 100 end
function UnitHealthMax(t) return 100 end
function GetNumGroupMembers() return M.groupSize or 0 end
function IsInRaid() return (M.groupSize or 0) > 5 end
-- combat: M.inCombat for you, u.combat for anyone else (true, false, or "secret")
function UnitAffectingCombat(t)
  if t == "player" then return M.inCombat == true end
  local u = M.units[t]
  if not u then return false end
  if u.combat == "secret" then return M.secret() end
  return u.combat == true
end
function InCombatLockdown() return M.inCombat == true end
function UnitIsUnit(a, b) if M.secretTargets then return M.secret() end local x, y = M.units[a], M.units[b] if b == "player" then return x ~= nil and x.isMe == true end return x ~= nil and x == y end
C_Spell = { GetSpellName = function(id) return M.spells and M.spells[id] end }
function UIFrameFadeOut(frame, seconds, from, to) frame.__fading = true end
function UIFrameFadeRemoveFrame(frame) frame.__fading = nil end
UISpecialFrames = {}
SlashCmdList = {}
function GetBuildInfo() return "1.60.1", "70245", "Oct 6 2026", 16001 end
function GetCursorPosition() return 0, 0 end
Enum = { TooltipDataType = { Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) M.tooltipHook = fn end }

C_Timer = {
  After = function(delay, fn) M.timers[#M.timers + 1] = { at = M.now + delay, fn = fn } end,
  NewTicker = function(period, fn) M.timers[#M.timers + 1] = { at = M.now + period, fn = fn, period = period } end,
}
-- advance the clock, running timers in order
function M.advance(seconds)
  local target = M.now + seconds
  while true do
    local best
    for i, t in ipairs(M.timers) do
      if t.at <= target and (not best or t.at < M.timers[best].at) then best = i end
    end
    if not best then break end
    local t = table.remove(M.timers, best)
    M.wall = M.wall + (t.at - M.now)
    M.now = t.at
    if t.period then M.timers[#M.timers + 1] = { at = t.at + t.period, fn = t.fn, period = t.period } end
    t.fn()
  end
  M.wall = M.wall + (target - M.now)
  M.now = target
end

-- units ---------------------------------------------------------------------
local function U(token) return M.units[token] end
function UnitExists(t) return U(t) ~= nil end
function UnitIsPlayer(t) return U(t) and U(t).player ~= false end
function UnitName(t) local u = U(t) if not u then return nil end local first, last = u.name:match("^(%S+)%s*(.*)$") return first, last end
function GetUnitName(t, full) local u = U(t) if not u then return nil end if u.secretName then return M.secret() end return u.name end
function UnitGUID(t) local u = U(t) if not u then return nil end if u.secretGUID then return M.secret() end return u.guid end
function GetGuildInfo(t)
  local u = U(t)
  if not u then return nil end
  if u.secretGuild then return M.secret(), M.secret(), M.secret() end
  if not u.guild then return nil end
  return u.guild, u.secretRank and M.secret() or u.rank or "Member", 3
end
function UnitLevel(t)
  if t == "player" then return M.secretMyLevel and M.secret() or M.myLevel end
  local u = U(t) if not u then return 0 end
  if u.secretLevel then return M.secret() end
  return u.level or -1 -- the client says -1 for a player too far above you
end
function UnitRace(t) local u = U(t) if not u or not u.race then return nil end if u.secretRace then return M.secret(), M.secret(), M.secret() end return u.race, u.race, 1 end
function UnitSex(t) local u = U(t) if not u then return nil end if u.secretSex then return M.secret() end return u.sex end
function UnitPVPName(t) local u = U(t) if not u then return nil end if u.secretTitle then return M.secret() end return u.pvpName or u.name end
function GetRealZoneText() if M.secretZone then return M.secret() end return M.zone end
function GetSubZoneText() if M.secretZone then return M.secret() end return M.subzone end
function UnitClass(t) local u = U(t) if not u then return nil end return "Class", u.class or "WARRIOR" end
function UnitFactionGroup(t) local u = U(t) if not u then return nil end return u.faction or "Alliance" end
function UnitCanAttack(a, t) local u = U(t) return u and (u.faction or "Alliance") ~= "Horde" end
C_PartyInfo = { IsGUIDInGroup = function(g) return M.group[g] == true end }
function UnitIsDeadOrGhost(t) local u = U(t) return u and u.dead == true or false end
function UnitIsFeignDeath(t) local u = U(t) return u and u.feign == true or false end
function UnitTokenFromGUID(g) for token, u in pairs(M.units) do if u.guid == g then return token end end end
function GetPlayerInfoByGUID(g)
  local u = M.guids[g]
  if not u then return nil end
  if u.secretRace then return M.secret(), M.secret(), M.secret(), M.secret(), M.secret(), M.secret(), M.secret(), M.secret() end
  return "Class", u.class or "WARRIOR", u.race or "Human", u.race or "Human", u.sex or 2, (u.name:match("^(%S+)")), "", u.level
end
function GetPVPSessionStats() return M.hk, 0 end
function IsInGuild() return M.inGuild end
function M.addUnit(token, u) M.units[token] = u if u.guid then M.guids[u.guid] = u end return u end

C_ChatInfo = {
  RegisterAddonMessagePrefix = function(p) M.prefix = p return 0 end,
  InChatMessagingLockdown = function() return M.lockdown end,
  SendAddonMessage = function(prefix, msg, channel) if M.lockdown then return 11 end if M.addonResult ~= 0 then return M.addonResult end M.sentAddon[#M.sentAddon + 1] = { prefix, msg, channel, M.now } return 0 end,
  SendChatMessage = function(msg, channel) M.sentChat[#M.sentChat + 1] = { msg, channel } end,
}

-- frames --------------------------------------------------------------------
local frameMT = {}
frameMT.__index = function(self, key)
  local known = {
    RegisterEvent = function(f, e) f.__events[e] = true end,
    RegisterUnitEvent = function(f, e) f.__events[e] = true end,
    UnregisterEvent = function(f, e) f.__events[e] = nil end,
    SetScript = function(f, name, fn) f.__scripts[name] = fn end,
    GetScript = function(f, name) return f.__scripts[name] end,
    HookScript = function(f, name, fn) f.__scripts[name] = fn end,
    Show = function(f) local was = f.__shown f.__shown = true if not was and f.__scripts.OnShow then f.__scripts.OnShow(f) end end,
    Hide = function(f) f.__shown = false end,
    IsShown = function(f) return f.__shown end,
    SetShown = function(f, shown) f.__shown = shown and true or false end,
    SetText = function(f, t) assert(type(t) == "string" or type(t) == "number", "SetText needs text, got " .. type(t)) f.__text = t end,
    GetText = function(f) return f.__text end,
    GetName = function(f) return f.__name end,
    GetParent = function(f) return f.__parent end,
    GetWidth = function() return 140 end,
    GetCenter = function() return 0, 0 end,
    GetEffectiveScale = function() return 1 end,
    CreateFontString = function(f) return M.newFrame("FontString", nil, f) end,
    CreateTexture = function(f) return M.newFrame("Texture", nil, f) end,
    -- animations: what was played is written down, nothing moves
    CreateAnimationGroup = function(f) if M.noAnimations then return nil end local g = M.newFrame("AnimationGroup", nil, f) g.__plays = 0 return g end,
    CreateAnimation = function(f, kind) return M.newFrame(kind, nil, f) end,
    Play = function(f) f.__plays = (f.__plays or 0) + 1 f.__playing = true end,
    Stop = function(f) f.__playing = false end,
    SetAlpha = function(f, a) f.__alpha = a end,
    GetAlpha = function(f) return f.__alpha or 1 end,
    SetWidth = function(f, w) f.__width = w end,
    SetTexture = function(f, path) if M.failTexture then error("no texture") end f.__texture = path end,
    SetVertexColor = function(f, r, g, b) f.__color = { r, g, b } end,
    SetTextColor = function(f, r, g, b) f.__color = { r, g, b } end,
    AddLine = function(f, text) assert(type(text) == "string") f.__lines[#f.__lines + 1] = text end,
    GetUnit = function(f) return "x", f.__unit end,
    StartMoving = function() end, StopMovingOrSizing = function() end,
  }
  if known[key] then return known[key] end
  if key == "TitleText" or key == "TitleContainer" then return nil end
  if type(key) == "string" and key:match("^[A-Z]") then return function() end end -- any other widget method
  return nil
end
function M.newFrame(kind, name, parent, template)
  if template == "BasicFrameTemplateWithInset" and M.failTemplate then error("no such template") end
  local f = setmetatable({ __events = {}, __scripts = {}, __shown = true, __name = name, __parent = parent, __lines = {}, __kind = kind }, frameMT)
  M.frames[#M.frames + 1] = f
  if name then _G[name] = f end
  return f
end
function CreateFrame(kind, name, parent, template) return M.newFrame(kind, name, parent, template) end
UIParent = M.newFrame("Frame", "UIParent")
WorldFrame = M.newFrame("Frame", "WorldFrame")
function GetPhysicalScreenSize() return 2560, 1440 end
Minimap = M.newFrame("Frame", "Minimap")
GameTooltip = M.newFrame("GameTooltip", "GameTooltip")

function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    if f.__events[event] and f.__scripts.OnEvent then f.__scripts.OnEvent(f, event, ...) end
  end
end

function M.load(dir, files)
  local ns = {}
  for _, file in ipairs(files) do
    local chunk = assert(loadfile(dir .. "/" .. file))
    chunk("Godslayer", ns)
  end
  M.ns = ns
  return ns
end

return M
