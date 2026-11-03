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

-- How many times the addon asked. Four calls carry a counter because the rate at which the
-- addon makes them stopped being an accident in 2.6.0 and became something it promises: the
-- nameplate sweep reads the set the client describes rather than forty tokens, the idle sweep
-- re-reads a settled unit every thirty seconds rather than every two, and one unit is asked
-- whether it is dead at most once a second. A promise about how often something is called can
-- only be tested by counting the calls.
M.count = {}
local function tally(name)
  M.count[name] = (M.count[name] or 0) + 1
end
M.tally = tally
function M.resetCount() M.count = {} end


-- The client's bulk scrubber, documented in FrameScriptDocumentation: every argument that is
-- secret, or that is not a string, number or boolean, comes back nil. Blizzard's own FrameXML
-- calls it unqualified, so it is a plain global here too.
--
-- M.noScrub takes it away, because an addon that has grown a fast path on a global has to be
-- tested on the client that does not have it. The explicit length in the unpack is not
-- decoration: a scrubbed list is full of holes by design, and unpack without it stops at the
-- first one.
local function scrubOne(v)
  local t = type(v)
  if t == "string" or t == "number" or t == "boolean" then return v end
  return nil      -- a secret value is a table here, so this covers it and everything else
end

-- Spelled out to eight rather than looped through a table, because the real one is a single C
-- call that returns on the stack and allocates nothing: a mock that built a table here would
-- show up in the profiler as garbage the client does not make, and not making garbage was the
-- whole reason for reaching for scrub. The length is dispatched on rather than padded to eight,
-- because the real one returns exactly as many values as it was given and a mock that always
-- returns eight hides every arity mistake made against it. Past eight the table is honest
-- enough; nothing in the addon scrubs that many values at once.
local function scrubN(n, a, b, c, d, e, f, g, h)
  if n == 0 then return end
  if n == 1 then return scrubOne(a) end
  if n == 2 then return scrubOne(a), scrubOne(b) end
  if n == 3 then return scrubOne(a), scrubOne(b), scrubOne(c) end
  if n == 4 then return scrubOne(a), scrubOne(b), scrubOne(c), scrubOne(d) end
  if n == 5 then return scrubOne(a), scrubOne(b), scrubOne(c), scrubOne(d), scrubOne(e) end
  if n == 6 then return scrubOne(a), scrubOne(b), scrubOne(c), scrubOne(d), scrubOne(e), scrubOne(f) end
  if n == 7 then return scrubOne(a), scrubOne(b), scrubOne(c), scrubOne(d), scrubOne(e), scrubOne(f), scrubOne(g) end
  return scrubOne(a), scrubOne(b), scrubOne(c), scrubOne(d), scrubOne(e), scrubOne(f), scrubOne(g), scrubOne(h)
end

function scrub(...)
  if M.noScrub then error("scrub is not on this client") end
  M.scrubs = (M.scrubs or 0) + 1
  local n = select("#", ...)
  if n <= 8 then return scrubN(n, ...) end
  local out = {}
  for i = 1, n do out[i] = scrubOne((select(i, ...))) end
  return unpack(out, 1, n)
end

function GetTime() return M.now end
-- Whole seconds, like the client's. The mock clock drifts fractional because timers are
-- scheduled at fractions of a second and M.advance moves the wall by whatever the next one is
-- due in, but the game's time() is a Unix timestamp and has never had a fraction in it. Handing
-- the addon a float here is not a harsher test, it is a different client: os.date refuses one,
-- the addon's try() swallows the error, and every kill silently loses its day and its hour.
function time() return math.floor(M.wall) end
-- like the client's date(): a format and an optional time; UTC here so runs are repeatable.
-- A fractional time is counted as well as rejected, because try() eats the error and the damage
-- otherwise shows up as a missing day three hundred assertions later.
M.dateFloats = 0
function date(fmt, t)
  if M.dateError then error("date blew up") end
  -- The default is the clock as the addon sees it, not the mock's internal one: date() with no
  -- time means "now", and now is a whole second.
  t = t or time()
  if type(t) == "number" and t % 1 ~= 0 then
    M.dateFloats = M.dateFloats + 1
    error("date got a fractional time (" .. tostring(t) .. "); the client's time() returns whole seconds")
  end
  return os.date("!" .. (fmt or "%c"), t)
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

-- auras: M.auras[token][filter] is the list the game would hand back, in order.
-- A row may carry secret = true to stand for a value this client refuses to give an addon.
M.auras = {}
C_UnitAuras = {
  GetAuraDataByIndex = function(unit, i, filter)
    tally("GetAuraDataByIndex")
    local byFilter = M.auras[unit]
    local list = byFilter and byFilter[filter or "HELPFUL"]
    local a = list and list[i]
    if not a then return nil end
    if a.secret then return { name = M.secret(), spellId = M.secret() } end
    return a
  end,
}
-- put an aura on a unit. seconds nil means no timer, which is how a stance or a stealth reads.
function M.aura(unit, filter, name, spellId, seconds, source, stacks)
  M.auras[unit] = M.auras[unit] or {}
  local list = M.auras[unit][filter] or {}
  M.auras[unit][filter] = list
  list[#list + 1] = {
    name = name, spellId = spellId, duration = seconds or 0,
    expirationTime = seconds and (M.now + seconds) or 0,
    sourceUnit = source, applications = stacks or 0,
  }
  return list[#list]
end
function M.clearAuras(unit)
  if unit then M.auras[unit] = nil else M.auras = {} end
end
function UIFrameFadeOut(frame, seconds, from, to) frame.__fading = true end
function UIFrameFadeRemoveFrame(frame) frame.__fading = nil end
UISpecialFrames = {}
SlashCmdList = {}
function GetBuildInfo() return "1.60.1", "70245", "Oct 6 2026", 16001 end
function GetCursorPosition() return 0, 0 end
Enum = {
  TooltipDataType = { Unit = 2 },
  -- Rank_1 is 5 on this build: every rank number in Rank.lua is an offset from it
  PvPRanks = { RankNone = 0, RankPariah = 1, RankOutlaw = 2, RankExiled = 3, RankDishonored = 4 },
  DamageMeterType = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4,
    Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9,
    EnemyDamageTaken = 10 },
  DamageMeterSessionType = { Overall = 0, Current = 1, Expired = 2 },
  DamageMeterSourceDisplayType = { None = 0, Ally = 1, Enemy = 2 },
  PvPMatchState = { Inactive = 0, Waiting = 1, StartUp = 2, Engaged = 3, PostRound = 4, Complete = 5 },
  SpellBookSpellBank = { Player = 0, Pet = 1 },
}
for i = 1, 14 do Enum.PvPRanks["Rank_" .. i] = i + 4 end
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
function UnitExists(t) tally("UnitExists") tally("UnitExists:" .. tostring(t)) return U(t) ~= nil end
function UnitIsPlayer(t) return U(t) and U(t).player ~= false end
function UnitName(t) local u = U(t) if not u then return nil end local first, last = u.name:match("^(%S+)%s*(.*)$") return first, last end
function GetUnitName(t, full) local u = U(t) if not u then return nil end if u.secretName then return M.secret() end return u.name end
-- Counted as well, because the targeted search for a kill's victim asks every plate for a GUID
-- and nothing else, and that is the shape the test has to be able to see.
function UnitGUID(t) tally("UnitGUID") local u = U(t) if not u then return nil end if u.secretGUID then return M.secret() end return u.guid end
function GetGuildInfo(t)
  tally("GetGuildInfo")
  -- also per unit, because the interesting question is how often one plate was read and the
  -- aggregate carries every other caller's traffic with it -- Comm asks about "player" on its
  -- own ticker, which is enough to make an exact total unassertable
  tally("GetGuildInfo:" .. tostring(t))
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
-- A race has three forms and the client hands back all three: the localised name, the stable
-- token, and the id. They are not the same string -- Undead is token Scourge and id 5, Night Elf
-- is token NightElf -- so the mock keeps them apart the way ChrRaces.db2 does. A fixture carries
-- the token, which is the only one that is the same on every client.
M.RACES = {
  Scourge   = { name = "Undead",     id = 5 },
  Orc       = { name = "Orc",        id = 2 },
  Tauren    = { name = "Tauren",     id = 6 },
  Troll     = { name = "Troll",      id = 8 },
  BloodElf  = { name = "Blood Elf",  id = 10 },
  Human     = { name = "Human",      id = 1 },
  Dwarf     = { name = "Dwarf",      id = 3 },
  NightElf  = { name = "Night Elf",  id = 4 },
  Gnome     = { name = "Gnome",      id = 7 },
  Draenei   = { name = "Draenei",    id = 11 },
  Goblin    = { name = "Goblin",     id = 9 },
  Worgen    = { name = "Worgen",     id = 22 },
  Pandaren  = { name = "Pandaren",   id = 24 },
}
local function raceForms(token)
  local r = M.RACES[token]
  if r then return r.name, token, r.id end
  return token, token, 0
end
function UnitRace(t) local u = U(t) if not u or not u.race then return nil end if u.secretRace then return M.secret(), M.secret(), M.secret() end return raceForms(u.race) end
function UnitSex(t) local u = U(t) if not u then return nil end if u.secretSex then return M.secret() end return u.sex end
function UnitPVPName(t) local u = U(t) if not u then return nil end if u.secretTitle then return M.secret() end return u.pvpName or u.name end
function GetRealZoneText() if M.secretZone then return M.secret() end return M.zone end
function GetSubZoneText() if M.secretZone then return M.secret() end return M.subzone end
function UnitClass(t) local u = U(t) if not u then return nil end return "Class", u.class or "WARRIOR" end
function UnitFactionGroup(t) local u = U(t) if not u then return nil end return u.faction or "Alliance" end
function UnitCanAttack(a, t) local u = U(t) return u and (u.faction or "Alliance") ~= "Horde" end
C_PartyInfo = { IsGUIDInGroup = function(g) return M.group[g] == true end }
function UnitIsDeadOrGhost(t) tally("UnitIsDeadOrGhost") local u = U(t) return u and u.dead == true or false end
function UnitIsFeignDeath(t) local u = U(t) return u and u.feign == true or false end
function UnitTokenFromGUID(g) for token, u in pairs(M.units) do if u.guid == g then return token end end end
function GetPlayerInfoByGUID(g)
  local u = M.guids[g]
  if not u then return nil end
  if u.secretRace then return M.secret(), M.secret(), M.secret(), M.secret(), M.secret(), M.secret(), M.secret(), M.secret() end
  local localised, token = raceForms(u.race or "Human")
  return "Class", u.class or "WARRIOR", localised, token, u.sex or 2, (u.name:match("^(%S+)")), "", u.level
end
function GetPVPSessionStats() return M.hk, M.dk or 0 end
function GetPVPYesterdayStats() return M.hkYesterday or 0, M.dkYesterday or 0 end
-- the best rank ever held comes back on the PvPRanks enum scale, four above the rank itself
function GetPVPLifetimeStats() return M.lifetimeHK or 0, M.lifetimeBest or 0 end
function GetCurrentArenaSeason() return M.season or 1 end
C_SeasonInfo = { GetTimeUntilCurrentPVPSeasonEnd = function() return M.seasonEnds or 0 end }

-- the ladder: rank is renown on a major faction on this build
M.renown = nil   -- { renownLevel, renownReputationEarned, renownLevelThreshold }
C_MajorFactions = {
  GetMajorFactionProgressionInfo = function(id)
    if id ~= 2800 then return nil end
    if M.renownSecret then return M.secret() end
    return M.renown
  end,
}

-- GetText picks the gendered form. UnitSex is 2 for male and 3 for female.
function GetText(key, sex)
  if sex == 3 and _G[key .. "_FEMALE"] then return _G[key .. "_FEMALE"] end
  return _G[key]
end

-- The ladder's title strings, exactly as the client spells them: PVP_RANK_<enum>_<faction>,
-- faction 0 Horde and 1 Alliance, enum starting at 5 for rank 1. The _NAME family below is the
-- modern rated ladder and is deliberately present, because mixing the two is the trap.
PVP_RANK_0_NAME = "Civilian"
PVP_RANK_1_NAME = "Combatant I"
PVP_RANK_2_NAME = "Challenger I"
local HORDE_LADDER = { "Scout", "Grunt", "Sergeant", "Senior Sergeant", "First Sergeant",
  "Stone Guard", "Blood Guard", "Legionnaire", "Centurion", "Champion", "Lieutenant General",
  "General", "Warlord", "High Warlord" }
local ALLIANCE_LADDER = { "Private", "Corporal", "Sergeant", "Master Sergeant", "Sergeant Major",
  "Knight", "Knight-Lieutenant", "Knight-Captain", "Knight-Champion", "Lieutenant Commander",
  "Commander", "Marshal", "Field Marshal", "Grand Marshal" }
for i = 1, 14 do
  _G["PVP_RANK_" .. (i + 4) .. "_0"] = HORDE_LADDER[i]
  _G["PVP_RANK_" .. (i + 4) .. "_1"] = ALLIANCE_LADDER[i]
end
-- Spell schools. The client keys these on the school INDEX while every mask is 1 << index, and
-- the two are a step apart: Frost is index 4 and mask 16.
local SCHOOL_CAPS = { "Physical", "Holy", "Fire", "Nature", "Frost", "Shadow", "Arcane" }
for i = 1, #SCHOOL_CAPS do _G["SPELL_SCHOOL" .. (i - 1) .. "_CAP"] = SCHOOL_CAPS[i] end

PVP_RANK_NUMBER_AND_TITLE = "Rank %d - %s"
PVP_RANK_CURRENT_PROGRESS = "Rank Points: %d / %d"
COMBATLOG_HONORGAIN = "%s dies (Honorable Kill: %s). You gain %d Honor."
COMBATLOG_HONORGAIN_NO_RANK = "%s dies (Honorable Kill). You gain %d Honor."
COMBATLOG_HONORGAIN_EXHAUSTION1 = "%s dies (Honorable Kill: %s). You gain %d Honor (%s %s bonus)."
COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1 = "%s dies (Honorable Kill). You gain %d Honor (%s %s bonus)."
COMBATLOG_HONORAWARD = "You have been awarded %d Honor."
COMBATLOG_DISHONORGAIN = "%s dies, dishonorable kill."

-- the engine's damage meter. M.meter.sessions[session][type] is a session; M.meter.spells keys
-- the same two plus a guid. A row with secret = true stands for an in-combat read.
M.meter = { available = true, reason = "", sessions = {}, spells = {} }
local function meterBox(t, a, b)
  t[a] = t[a] or {}
  t[a][b] = t[a][b] or {}
  return t[a][b]
end
function M.session(session, kind, sources, duration)
  local box = meterBox(M.meter.sessions, session, kind)
  box.sources = sources or {}
  box.duration = duration
  local total, max = 0, 0
  for _, src in ipairs(box.sources) do
    total = total + (src.amount or 0)
    if (src.amount or 0) > max then max = src.amount end
  end
  box.total, box.max = total, max
  return box
end
function M.meterSpells(session, kind, guid, rows)
  local box = meterBox(M.meter.spells, session, kind)
  local total = 0
  for _, r in ipairs(rows or {}) do total = total + (r.amount or 0) end
  box[guid] = { rows = rows or {}, total = total }
  return box[guid]
end
function M.clearMeter()
  M.meter.sessions, M.meter.spells = {}, {}
end
C_DamageMeter = {
  IsDamageMeterAvailable = function() return M.meter.available, M.meter.reason end,
  ResetAllCombatSessions = function() M.clearMeter() end,
  GetSessionDurationSeconds = function(session)
    local box = M.meter.sessions[session]
    local any = box and (box[0] or box[7])
    return any and any.duration or nil
  end,
  GetAvailableCombatSessions = function() return M.meter.listed or {} end,
  GetCombatSessionFromType = function(session, kind)
    local box = M.meter.sessions[session] and M.meter.sessions[session][kind]
    if not box then return nil end
    local sources = {}
    for i, src in ipairs(box.sources) do
      sources[i] = {
        sourceGUID = src.secret and M.secret() or src.guid,
        name = src.secret and M.secret() or src.name,
        classFilename = src.class or "WARRIOR",
        totalAmount = src.secret and M.secret() or src.amount,
        amountPerSecond = src.ps or 0,
        isLocalPlayer = src.mine == true,
        sourceDisplayType = src.side,
        factionGroup = src.faction,
        deathTimeSeconds = src.deathTime or 0,
        deathRecapID = 0,
        classification = src.classification or "player",
      }
    end
    return { combatSources = sources, totalAmount = box.total or 0, maxAmount = box.max or 0,
             durationSeconds = box.duration }
  end,
  GetCombatSessionFromID = function(id, kind) return nil end,
  GetCombatSessionSourceFromType = function(session, kind, guid)
    local box = M.meter.spells[session] and M.meter.spells[session][kind]
    local row = box and box[guid]
    if not row then return nil end
    local spells = {}
    for i, sp in ipairs(row.rows) do
      spells[i] = {
        spellID = sp.id,
        totalAmount = sp.secret and M.secret() or sp.amount,
        amountPerSecond = sp.ps or 0,
        overkillAmount = sp.overkill or 0,
        isAvoidable = sp.avoidable == true,
        isDeadly = sp.deadly == true,
        creatureName = sp.by,
        combatSpellDetails = {},
      }
    end
    return { combatSpells = spells, totalAmount = row.total or 0, maxAmount = row.max or 0 }
  end,
  GetCombatSessionSourceFromID = function() return nil end,
}
-- The battleground scoreboard, with the seal modelled rather than assumed. `C_PvP.GetScoreInfo`
-- carries SecretInActivePvPMatch, so while the match is running every field except the seven the
-- client marks NeverSecret comes back as a secret value. A mock that handed over plain numbers
-- during the match would let a broken read pass, which is the only thing these tests are for.
M.bg = nil
local NEVER_SECRET_NOTE = "name faction raceName gender className classToken honorLevel"
M.NEVER_SECRET = NEVER_SECRET_NOTE
M.bgRequests = 0

-- rows are { name, faction, race, gender, class, token, rank, guid, kb, hk, deaths, honor,
--            damage, healing, stats = { { name, value } } }
function M.battleground(t)
  t = t or {}
  M.bg = {
    state = t.state or Enum.PvPMatchState.Engaged,
    factional = t.factional ~= false,
    winner = t.winner,
    duration = t.duration or 0,
    cols = t.cols,
    rows = t.rows or {},
  }
  M.bgRequests = 0
  return M.bg
end

function M.bgComplete(winner, duration)
  if not M.bg then return nil end
  M.bg.state = Enum.PvPMatchState.Complete
  if winner ~= nil then M.bg.winner = winner end
  if duration then M.bg.duration = duration end
  return M.bg
end

function M.bgLeave() M.bg = nil end

local function bgSealed()
  return M.bg ~= nil and M.bg.state > Enum.PvPMatchState.Inactive and M.bg.state < Enum.PvPMatchState.Complete
end

-- A value the engine would hide right now. nil stays nil: a field the row never had is absent,
-- not secret, and the two must not be confused.
local function sealed(v)
  if v == nil then return nil end
  if bgSealed() then return M.secret() end
  return v
end

function GetNumBattlefieldScores() return M.bg and #M.bg.rows or 0 end
function RequestBattlefieldScoreData() M.bgRequests = M.bgRequests + 1 end

local function scoreRow(row)
  if not row then return nil end
  local stats
  if row.stats then
    stats = {}
    for i, st in ipairs(row.stats) do
      stats[i] = {
        pvpStatID = st.id or i,
        orderIndex = st.order or i,
        name = st.name,
        tooltip = st.tooltip or "",
        iconName = st.icon or "",
        pvpStatValue = sealed(st.value),
      }
    end
  end
  return {
    -- the seven the client marks NeverSecret
    name = row.name,
    faction = row.faction,
    raceName = row.race,
    gender = row.gender,
    className = row.class,
    classToken = row.token,
    honorLevel = row.rank,
    -- everything else is sealed while the match is on, guid included
    guid = sealed(row.guid),
    killingBlows = sealed(row.kb),
    honorableKills = sealed(row.hk),
    deaths = sealed(row.deaths),
    honorGained = sealed(row.honor),
    damageDone = sealed(row.damage),
    healingDone = sealed(row.healing),
    rating = sealed(row.rating),
    ratingChange = sealed(row.ratingChange),
    prematchMMR = sealed(row.prematchMMR),
    mmrChange = sealed(row.mmrChange),
    postmatchMMR = sealed(row.postmatchMMR),
    talentSpec = sealed(row.spec),
    roleAssigned = sealed(row.role),
    stats = stats,
  }
end

C_PvP = {
  GetScoreInfo = function(i) return scoreRow(M.bg and M.bg.rows[i]) end,
  GetScoreInfoByPlayerGuid = function(guid)
    if not M.bg then return nil end
    for _, row in ipairs(M.bg.rows) do if row.guid == guid then return scoreRow(row) end end
  end,
  GetActiveMatchState = function() return M.bg and M.bg.state or Enum.PvPMatchState.Inactive end,
  GetActiveMatchWinner = function() return M.bg and M.bg.winner or nil end,
  GetActiveMatchDuration = function() return M.bg and M.bg.duration or 0 end,
  IsMatchActive = function() return bgSealed() end,
  IsMatchComplete = function() return M.bg ~= nil and M.bg.state >= Enum.PvPMatchState.Complete end,
  IsMatchFactional = function() return M.bg ~= nil and M.bg.factional == true end,
  IsBattleground = function() return M.bg ~= nil end,
  GetMatchPVPStatColumns = function()
    if not (M.bg and M.bg.cols) then return {} end
    local out = {}
    for i, name in ipairs(M.bg.cols) do
      out[i] = { pvpStatID = i, columnHeaderID = i, orderIndex = i, name = name, tooltipTitle = name, tooltip = "" }
    end
    return out
  end,
}

-- The map, the flags, and the two coordinate systems between them.
--
-- The client answers flag and player positions in NORMALISED map space and distances only exist
-- in world yards, so the addon has to convert and the conversion is the part that can be silently
-- wrong: normalised x runs east while world y runs **west**, and normalised y runs south while
-- world x runs **north**. Both axes are flipped and neither flip is visible in a position that
-- happens to be near the middle of the map.
--
-- So the mock is driven in yards -- `M.playerAt(north, west)`, `M.flagsAt{...}` -- and converts
-- the other way for the calls the addon actually makes. A sign error or a swapped axis in
-- Flag.lua comes back as a distance that does not match the one the test asked for, which is the
-- only way a test can tell the difference.
M.map = { id = 1339, north = 1000, west = 1000, tall = 1000, wide = 1000 }
M.facing = 0          -- radians counter-clockwise from north, like GetPlayerFacing
M.flags = {}
M.me = { north = 500, west = 500 }
M.worldCalls = 0

local function toNormal(north, west)
  local m = M.map
  return (m.west - west) / m.wide, (m.north - north) / m.tall
end

local function toWorld(nx, ny)
  local m = M.map
  return m.north - ny * m.tall, m.west - nx * m.wide
end

function M.playerAt(north, west)
  M.me = { north = north, west = west }
end

-- rows are { north, west, texture, onMap }; onMap = false models the engine's documented nil x,
-- which is how it says "that flag is not on the map you asked about".
function M.flagsAt(rows)
  M.flags = {}
  for i, r in ipairs(rows or {}) do
    M.flags[i] = { north = r.north, west = r.west, texture = r.texture or (1000 + i), onMap = r.onMap ~= false }
  end
end

function GetNumBattlefieldFlagPositions() return #M.flags end

function GetPlayerFacing() return M.facing end

function CreateVector2D(x, y)
  return { x = x, y = y, GetXY = function(self) return self.x, self.y end }
end

C_Map = {
  GetBestMapForUnit = function(unit)
    if unit ~= "player" then return nil end
    return M.map and M.map.id or nil
  end,
  GetPlayerMapPosition = function(uiMapID, unit)
    if not (M.map and uiMapID == M.map.id and unit == "player" and M.me) then return nil end
    local x, y = toNormal(M.me.north, M.me.west)
    return CreateVector2D(x, y)
  end,
  -- MayReturnNothing in the documentation, so an unknown map returns nothing at all here rather
  -- than a zero, and the addon has to cope with that rather than with a convenient default.
  GetWorldPosFromMapPos = function(uiMapID, pos)
    M.worldCalls = M.worldCalls + 1
    if not (M.map and uiMapID == M.map.id and type(pos) == "table" and pos.GetXY) then return end
    local x, y = pos:GetXY()
    if type(x) ~= "number" or type(y) ~= "number" then return end
    local north, west = toWorld(x, y)
    return 1, CreateVector2D(north, west)
  end,
}

C_PvP.GetBattlefieldFlagPosition = function(index, uiMapID)
  local f = M.flags[index]
  if not f then return nil, nil, 0 end
  if not (M.map and uiMapID == M.map.id) then return nil, nil, f.texture end
  if not f.onMap then return nil, nil, f.texture end
  local x, y = toNormal(f.north, f.west)
  return x, y, f.texture
end

-- C_Spell.GetSchoolString: the client joins a mask into one string, and it is the only call that
-- knows how the game itself words a two-school lockout.
function GetSchoolStringMock(mask)
  mask = tonumber(mask) or 0
  if mask <= 0 then return "" end
  local parts = {}
  for i = 1, #SCHOOL_CAPS do
    local bit = 2 ^ (i - 1)
    if (mask % (bit * 2)) >= bit then parts[#parts + 1] = SCHOOL_CAPS[i] end
  end
  if #parts == 0 then return "" end
  if #parts == 1 then return parts[1] end
  return table.concat(parts, " and ")
end
C_Spell.GetSchoolString = GetSchoolStringMock

-- The spellbook, as a set of ids the player knows. M.knowAll makes every id known, which is what
-- a test about schools rather than about learning wants.
M.known = {}
M.knowAll = false
C_SpellBook = {
  IsSpellKnown = function(id, bank)
    if bank ~= nil and bank ~= Enum.SpellBookSpellBank.Player then return false end
    if M.knowAll then return true end
    return M.known[id] == true
  end,
}
function M.know(...)
  for _, id in ipairs({ ... }) do M.known[id] = true end
end
function M.forgetAll() M.known = {} M.knowAll = false end

Constants = Constants or {}
Constants.LossOfControlConsts = { LOSS_OF_CONTROL_ACTIVE_INDEX = 1 }
Constants.DeathRecapConsts = { SWING_DAMAGE_SPELL_ID = 88163 }

ACTION_SWING = "Melee"
ACTION_ENVIRONMENTAL_DAMAGE_FALLING = "Falling"
ACTION_ENVIRONMENTAL_DAMAGE_DROWNING = "Drowning"
ACTION_ENVIRONMENTAL_DAMAGE_FIRE = "Fire"

-- The death recap. `DeathRecapEventInfo` is in the client's generated documentation with an
-- EMPTY field list, so these names are not from the API docs: they are read off the client's own
-- Blizzard_DeathRecap UI, which ships in the interface source and is gated out of this game type.
-- Two things the mock models rather than smooths over, because both are traps:
--   * the engine hands the rows back NEWEST FIRST, so index 1 is the killing blow
--   * maxHealth is not a field on a row, it is a separate call for the whole recap
M.recaps = {}
M.recapMax = 0
function M.death(rows, maxHealth, id)
  id = id or 0
  M.recaps[id] = rows or {}
  M.recapMax = maxHealth or 0
  M.recaps.last = id
  return M.recaps[id]
end
function M.clearDeaths() M.recaps = {} M.recapMax = 0 end

local function recapRows(id)
  if id == nil then id = M.recaps.last or 0 end
  return M.recaps[id]
end

C_DeathRecap = {
  GetRecapEvents = function(id) return recapRows(id) end,
  GetRecapMaxHealth = function() return M.recapMax end,
  HasRecapEvents = function(id)
    local r = recapRows(id)
    return type(r) == "table" and #r > 0
  end,
  GetRecapLink = function(id) return "|cff71d5ff|Hdeathrecap:" .. tostring(id or 0) .. "|h[Death]|h|r" end,
}

-- Loss of control. `C_LossOfControl` is one of the very few interesting namespaces on this client
-- with no secrecy on its returns, so the mock hands the rows back plainly: faking a seal here
-- would be testing a rule the client does not have.
-- rows are { kind, id, spell, duration, left, school, show, priority }
M.loc = {}
function M.control(rows)
  M.loc = rows or {}
  return M.loc
end
function M.clearControl() M.loc = {} end

C_LossOfControl = {
  GetActiveLossOfControlDataCount = function() return #M.loc end,
  GetActiveLossOfControlDataCountByUnit = function(unit) return (unit == "player") and #M.loc or 0 end,
  GetActiveLossOfControlData = function(i)
    local r = M.loc[i]
    if not r then return nil end
    return {
      locType = r.kind,
      spellID = r.id or 0,
      displayText = r.spell or r.kind,
      iconTexture = r.icon or 0,
      startTime = r.start or M.now,
      timeRemaining = r.left,
      duration = r.duration,
      lockoutSchool = r.school or 0,
      priority = r.priority or 1,
      displayType = r.show or 2,
      auraInstanceID = r.instance,
    }
  end,
  GetActiveLossOfControlDataByUnit = function(unit, i)
    if unit ~= "player" then return nil end
    return C_LossOfControl.GetActiveLossOfControlData(i)
  end,
}

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
