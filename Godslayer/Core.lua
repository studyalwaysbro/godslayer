-- Godslayer core: guild matching, kill detection, scoring.
--
-- The Forever client closes the combat log to addons (registering it raises a
-- forbidden-action popup), so kills come from the signals the client still hands out:
--   PARTY_KILL                killing blows by you, your pet or your group, as GUIDs
--   PLAYER_PVP_KILLS_CHANGED  you got honorable-kill credit, matched to a death seen
--                             at the same moment through UNIT_DIED
--   the honor chat line       only when it names the victim, which is rare on Forever
-- Guild names come from units you can see (target, mouseover, focus, nameplates).
-- So does everything in a victim's dossier: level, race, guild rank, PvP title. The
-- client may hide any of those, and then the dossier simply has a gap.
-- Players are keyed by GUID: Forever has first and last names and no realms.
-- Everything read from the game is checked for secret values before it is compared.

local ADDON, ns = ...

ns.VERSION = "2.0.0"

local DEDUPE_SECONDS = 10        -- the signals above can all describe the same death
local MATCH_WINDOW = 8           -- honorable-kill credit and a seen death must be this close
local PENDING_SECONDS = 15 * 60  -- how long a kill waits for the victim's guild to be seen
local KNOWN_MAX_AGE = 7 * 86400  -- how long a remembered guild tag is trusted for scoring
local KNOWN_CAP, SEEN_CAP, LOG_CAP = 4000, 1500, 150
local HIST_CAP = 12              -- kills remembered in detail per victim
local ZONE_CAP = 12              -- zones remembered per victim; the rest go under ELSEWHERE
local TEXT_MAX = 40              -- longest rank, race, title or zone name kept
local RANK_CAP = 6               -- guild ranks remembered per victim; the rest go under OTHER_RANKS
local DETAIL_CAP = 2500          -- victims that keep a kill-by-kill history; older feuds keep their totals
local ELSEWHERE, OTHER_RANKS = "Elsewhere", "Other ranks"
ns.HIST_CAP, ns.ZONE_CAP, ns.RANK_CAP, ns.DETAIL_CAP, ns.KNOWN_CAP = HIST_CAP, ZONE_CAP, RANK_CAP, DETAIL_CAP, KNOWN_CAP
ns.ELSEWHERE, ns.OTHER_RANKS = ELSEWHERE, OTHER_RANKS

local issecret = issecretvalue or function() return false end
-- the bare global is only a deprecation shim on this client
local IsGUIDInGroup = (C_PartyInfo and C_PartyInfo.IsGUIDInGroup) or IsGUIDInGroup

-- The value, or nil when it is secret.
local function plain(v)
  if issecret(v) then return nil end
  return v
end
ns.plain = plain

-- Call a game function that may be missing or may reject its arguments.
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b, c, d, e, g, h, i = pcall(f, ...)
  if ok then return a, b, c, d, e, g, h, i end
end
ns.try = try

-- Text from the game made safe to keep and show: no escape codes, no control
-- characters, bounded, and never cut in the middle of a UTF-8 character.
local function clean(s, max)
  s = plain(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("|", ""):gsub("%c", ""):match("^%s*(.-)%s*$")
  max = max or TEXT_MAX
  if #s > max then
    local cut = max
    while cut > 0 do
      local b = s:byte(cut + 1)
      if not b or b < 128 or b >= 192 then break end
      cut = cut - 1
    end
    s = s:sub(1, cut)
  end
  if s == "" then return nil end
  return s
end
ns.clean = clean

function ns.Print(msg)
  print("|cffff7d0aGodslayer:|r " .. tostring(msg))
end

function ns.Log(kind, msg)
  local db = GodslayerDB
  if not db then return end
  local log = db.log
  local when = try(date, "%m-%d %H:%M:%S")
  log[#log + 1] = (type(when) == "string" and when or "?") .. " " .. kind .. ": " .. tostring(msg)
  while #log > LOG_CAP do table.remove(log, 1) end
end

-- ---------------------------------------------------------------------------
-- Guild matching
-- ---------------------------------------------------------------------------

-- The announcer is decoration: a fault in it is logged and counted, and never costs a kill its score.
local function hype(what, ...)
  local ok, result = pcall(ns.Hype[what], ...)
  if ok then return result end
  ns.errors = (ns.errors or 0) + 1
  if ns.errors <= 25 then ns.Log("error", "hype " .. what .. ": " .. tostring(result)) end
end

function ns.NormGuild(guild)
  return (guild:lower():gsub("[^%w]", ""))
end

local function withinOneEdit(a, b)
  local la, lb = #a, #b
  if a == b then return true end
  if math.abs(la - lb) > 1 then return false end
  local i, j, edits = 1, 1, 0
  while i <= la and j <= lb do
    if a:byte(i) == b:byte(j) then
      i, j = i + 1, j + 1
    else
      edits = edits + 1
      if edits > 1 then return false end
      if la > lb then i = i + 1
      elseif lb > la then j = j + 1
      else i, j = i + 1, j + 1 end
    end
  end
  return edits + (la - i + 1) + (lb - j + 1) <= 1
end

-- Returns "original", "network" or nil.
function ns.Classify(guild)
  if type(guild) ~= "string" or guild == "" then return nil end
  local db = GodslayerDB
  local norm = ns.NormGuild(guild)
  if norm == "" then return nil end
  if db and db.ignore[norm] then return nil end
  -- the original must be spelled exactly; "Oly mpus" is a network guild at best
  if guild:lower():match("^%s*(.-)%s*$") == ns.ORIGINAL then return "original" end
  if ns.AFFILIATES[norm] or (db and db.custom[norm]) then return "network" end
  -- 0lympus, OLYMPVS, Olympuss and friends
  local leet = guild:lower():gsub("0", "o"):gsub("[1!|]", "l"):gsub("v", "u"):gsub("3", "e")
  local squashed = leet:gsub("[^%w]", "")
  for _, kw in ipairs(ns.KEYWORDS) do
    if norm:find(kw, 1, true) or squashed:find(kw, 1, true) then return "network" end
    for word in leet:gmatch("%a+") do
      if withinOneEdit(word, kw) then return "network" end
    end
  end
  return nil
end

function ns.PointsFor(tier)
  return tier == "original" and ns.ORIGINAL_POINTS or ns.NETWORK_POINTS
end

-- Title for a point total: name, index, and the points the next title needs (nil at the top).
function ns.RankFor(points)
  local index = 1
  for i, rank in ipairs(ns.RANKS) do
    if points >= rank[1] then index = i end
  end
  local nextRank = ns.RANKS[index + 1]
  return ns.RANKS[index][2], index, nextRank and nextRank[1], nextRank and nextRank[2]
end

function ns.IsKing(name, tier)
  if tier ~= "original" or type(name) ~= "string" then return false end
  local king = ns.KING:lower()
  name = name:lower()
  return name == king or name == king:match("^(%S+)")
end

-- ---------------------------------------------------------------------------
-- Saved data
-- ---------------------------------------------------------------------------

local function initDB()
  GodslayerDB = type(GodslayerDB) == "table" and GodslayerDB or {}
  local db = GodslayerDB
  -- version 2 (1.1.0) adds optional detail fields to victims and known players; records
  -- written by 1.0.0 are valid as they are and simply have less to show
  db.version = 2
  db.chars = db.chars or {}     -- per character scores
  db.roster = db.roster or {}   -- [guild][member] = scores received over addon chat
  db.known = db.known or {}     -- network members seen: [id] = { n = name, g = guild, c = class, t = time,
                                --   l = level, r = race, s = sex, k = guild rank, p = PvP title, z = zone seen in }
  db.custom = db.custom or {}   -- extra guilds added with /godslayer add
  db.ignore = db.ignore or {}   -- guilds excluded with /godslayer ignore
  db.opts = db.opts or {}
  db.log = db.log or {}
  local o = db.opts
  if o.sound == nil then o.sound = true end
  if o.toast == nil then o.toast = true end
  if o.chat == nil then o.chat = true end
  if o.tooltip == nil then o.tooltip = true end
  if o.minimap == nil then o.minimap = true end
end

local function newChar()
  return { kills = 0, points = 0, uniques = 0, kb = 0, orig = 0, kings = 0, bestStreak = 0, victims = {}, guilds = {} }
end

local myName, myGUID, myFaction

-- "First Last" on Forever, plain name elsewhere.
local function fullName(unit)
  local name = plain(try(GetUnitName, unit, true))
  if type(name) ~= "string" or name == "" then name = plain((try(UnitName, unit))) end
  if type(name) == "string" and name ~= "" and name ~= UNKNOWNOBJECT then return name end
end
ns.FullName = fullName

local function initChar()
  myName = fullName("player") or "Unknown"
  myGUID = plain(try(UnitGUID, "player"))
  myFaction = plain(try(UnitFactionGroup, "player"))
  local db = GodslayerDB
  db.chars[myName] = db.chars[myName] or newChar()
  local c = db.chars[myName]
  for k, v in pairs(newChar()) do if c[k] == nil then c[k] = v end end
  local _, class = try(UnitClass, "player")
  c.class = plain(class) or c.class
  ns.char, ns.myName = c, myName
  -- life counts our own deaths: a kill belongs to the life it happened in, even when it
  -- is only scored later, once the victim's guild tag is seen
  ns.session = { kills = 0, points = 0, streak = 0, runs = {}, life = 1 }
  -- only so many victims keep their kill-by-kill history; the oldest feuds keep the totals
  local list = {}
  for _, v in pairs(c.victims) do
    if v.hist then list[#list + 1] = v end
  end
  if #list > DETAIL_CAP then
    table.sort(list, function(a, b) return (a.last or 0) < (b.last or 0) end)
    for i = 1, #list - DETAIL_CAP do list[i].hist = nil end
  end
end

-- ---------------------------------------------------------------------------
-- Who is in which guild
-- ---------------------------------------------------------------------------

local seen, seenCount = {}, 0   -- this session: [id] = { name, guild, class, hostile, t }
local nameId = {}               -- [full name] = id, for the rare signal that only has a name
local pending = {}              -- kills waiting for a guild: [id] = record
local recent = {}               -- last kill per victim: [id] = record

local knownCount = 0            -- entries in GodslayerDB.known, kept so the cap holds mid-session

local function pruneKnown()
  local known = GodslayerDB.known
  local list = {}
  for id, e in pairs(known) do list[#list + 1] = { id, e.t or 0 } end
  knownCount = #list
  if #list <= KNOWN_CAP then return end
  table.sort(list, function(a, b) return a[2] < b[2] end)
  local drop = #list - KNOWN_CAP + 200
  for i = 1, drop do known[list[i][1]] = nil end
  knownCount = #list - drop
end

local Score, noteDeathRef -- defined below

-- The PvP title in front of (or behind) a name, when the client shows one.
local function pvpTitle(unit, name)
  local full = clean((try(UnitPVPName, unit)), 90)
  if not full or full == name then return nil end
  local rest, found = full, false
  for word in name:gmatch("%S+") do
    local at, to = rest:find(word, 1, true)
    if at then rest, found = rest:sub(1, at - 1) .. " " .. rest:sub(to + 1), true end
  end
  if not found then return nil end
  return clean((rest:gsub("[%s,]+", " ")))
end

-- Level, race, sex and title of a visible player. Any of them can be hidden.
local function observeDetails(unit, e, name)
  local level = plain(try(UnitLevel, unit))
  if type(level) == "number" and level >= 1 and level <= 200 then e.level = math.floor(level) end
  e.race = clean((try(UnitRace, unit))) or e.race
  local sex = plain(try(UnitSex, unit))
  if sex == 2 or sex == 3 then e.sex = sex end
  e.title = pvpTitle(unit, name) or e.title
end

local function resolvePending(id, guild, tier, class)
  local rec = pending[id]
  if not rec then return end
  pending[id] = nil
  if tier and GetTime() - rec.t <= PENDING_SECONDS then
    local name = (seen[id] and seen[id].name) or rec.name
    ns.Log("late", (name or id) .. " <" .. guild .. ">")
    Score(id, name, guild, tier, rec, class)
  end
end

-- Record what a visible unit tells us. Returns its id and guild when it is a player.
local function ObserveUnit(unit)
  if not plain(try(UnitExists, unit)) then return end
  if not plain(try(UnitIsPlayer, unit)) then return end
  local name = fullName(unit)
  if not name then return end
  local guid = plain(try(UnitGUID, unit))
  if type(guid) ~= "string" then guid = nil end
  if guid and guid == myGUID then return end
  if not guid and name == myName then return end

  local id = guid or ("name:" .. name)
  local guild, rank = try(GetGuildInfo, unit)
  guild = plain(guild)
  if type(guild) ~= "string" or guild == "" then guild = nil end
  rank = guild and clean(rank) or nil
  local _, class = try(UnitClass, unit)
  class = plain(class)
  if type(class) ~= "string" then class = nil end

  local e = seen[id]
  if not e then
    if seenCount >= SEEN_CAP then seen, nameId, seenCount = {}, {}, 0 end
    e = {}
    seen[id], seenCount = e, seenCount + 1
  end
  e.t, e.name = GetTime(), name
  e.class = class or e.class
  nameId[name] = id
  observeDetails(unit, e, name)

  local faction = plain(try(UnitFactionGroup, unit))
  if type(faction) == "string" and myFaction then
    e.hostile = faction ~= myFaction
  elseif plain(try(UnitCanAttack, "player", unit)) == true then
    e.hostile = true
  end

  -- only a change from alive to dead is a death; a corpse we walk up to is old news
  local dead = plain(try(UnitIsDeadOrGhost, unit))
  if dead == true and e.dead == false and guid and noteDeathRef then noteDeathRef(guid) end
  if dead == true or dead == false then e.dead = dead end

  if not guild then return id, e.guild end -- guild data may simply not have arrived yet
  if e.guild ~= guild then e.rank = nil end -- a rank belongs to the guild it was read in
  e.guild = guild
  e.rank = rank or e.rank

  local tier = ns.Classify(guild)
  local known = GodslayerDB.known
  if tier then
    if not known[id] then knownCount = knownCount + 1 end
    known[id] = { n = name, g = guild, c = e.class, t = time(), l = e.level, r = e.race, s = e.sex,
                  k = e.rank, p = e.title, z = clean((try(GetRealZoneText))) }
    if knownCount > KNOWN_CAP then pruneKnown() end -- a thousand-player raid can walk past in one sitting
    -- alive, hostile and in view: the announcer says so
    if dead == false and e.hostile and ns.Hype and ns.Hype.Spot then pcall(ns.Hype.Spot, id, name, guild, tier, ns.IsKing(name, tier)) end
  elseif known[id] then
    known[id] = nil -- they left the network
    knownCount = knownCount - 1
  end
  resolvePending(id, guild, tier, e.class)
  return id, guild
end
ns.ObserveUnit = ObserveUnit

local function sweepUnits()
  ns.sweeping = true -- a look around to put a name to a kill is not a sighting
  ObserveUnit("target")
  ObserveUnit("mouseover")
  ObserveUnit("focus")
  ObserveUnit("softenemy")
  for i = 1, 40 do ObserveUnit("nameplate" .. i) end
  ns.sweeping = false
end

-- Guild, class and name for a player, from what is on screen or was seen earlier.
local function lookup(id)
  local e = seen[id]
  local k = GodslayerDB.known[id]
  local name = (e and e.name) or (k and k.n)
  local class = (e and e.class) or (k and k.c)
  if e and e.guild then return e.guild, class, name end
  if k and time() - (k.t or 0) <= KNOWN_MAX_AGE then return k.g, class, name end
  return nil, class, name
end

-- Everything else known about a player, from the screen, from memory, or (for race,
-- sex and level) from the client's own cache when they were never on screen.
local function details(id)
  local e, k = seen[id], GodslayerDB.known[id]
  local d = {
    level = (e and e.level) or (k and k.l), race = (e and e.race) or (k and k.r),
    sex = (e and e.sex) or (k and k.s), rank = (e and e.rank) or (k and k.k),
    title = (e and e.title) or (k and k.p),
  }
  if not (d.race and d.sex and d.level) and id:sub(1, 7) == "Player-" then
    local _, _, race, _, sex, _, _, level = try(GetPlayerInfoByGUID, id)
    sex, level = plain(sex), plain(level)
    d.race = d.race or clean(race)
    if not d.sex and (sex == 2 or sex == 3) then d.sex = sex end
    if not d.level and type(level) == "number" and level >= 1 and level <= 200 then d.level = math.floor(level) end
  end
  return d
end

-- What the announcer may want to know about someone: class and level when they were ever on screen.
function ns.VictimInfo(id)
  if type(id) ~= "string" then return nil end
  local e, k = seen[id], GodslayerDB.known[id]
  local class, level = (e and e.class) or (k and k.c), (e and e.level) or (k and k.l)
  local myLevel = plain(try(UnitLevel, "player"))
  return { class = class, level = level, myLevel = type(myLevel) == "number" and myLevel > 0 and myLevel or nil, name = (e and e.name) or (k and k.n) }
end

-- Living enemy players on screen right now, and whether you are alone.
function ns.Odds()
  local enemies = 0
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if plain(try(UnitExists, unit)) and plain(try(UnitIsPlayer, unit)) and plain(try(UnitCanAttack, "player", unit)) == true
       and plain(try(UnitIsDeadOrGhost, unit)) ~= true then
      enemies = enemies + 1
    end
  end
  local group = plain(try(GetNumGroupMembers))
  return enemies, type(group) ~= "number" or group <= 1
end

-- Who probably killed you: enemy players who had you targeted, when the client says; otherwise
-- the one you were fighting. A guess, and treated as one.
function ns.Suspects()
  local list, have = {}, {}
  local function add(unit)
    if not (plain(try(UnitExists, unit)) and plain(try(UnitIsPlayer, unit)) and plain(try(UnitCanAttack, "player", unit)) == true) then return end
    local guid = plain(try(UnitGUID, unit))
    if type(guid) ~= "string" or have[guid] or #list >= 5 then return end
    have[guid] = true
    list[#list + 1] = { id = guid, name = fullName(unit) }
  end
  local readable = false
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if plain(try(UnitExists, unit)) then
      local onMe = try(UnitIsUnit, unit .. "target", "player")
      if not issecret(onMe) then
        readable = true
        if onMe then add(unit) end
      end
    end
  end
  if #list == 0 then add("target") end
  GodslayerDB.probe = GodslayerDB.probe or {}
  GodslayerDB.probe.targeting = readable and "readable" or "hidden"
  return list
end

-- For the tooltip: tier and guild of a visible unit, if it is in the network.
function ns.UnitTier(unit)
  local id, guild = ObserveUnit(unit)
  if id and guild then return ns.Classify(guild), guild, id end
end

-- ---------------------------------------------------------------------------
-- Scoring
-- ---------------------------------------------------------------------------

local function addKillingBlow(id)
  local c = ns.char
  local v = c.victims[id]
  if not v then return end
  v.kb = (v.kb or 0) + 1
  if v.tier then c.kb = c.kb + 1 end -- an ignored guild's records stay out of the totals
end

-- Count one more under a key, folding new keys into the overflow key once the table is full.
local function bump(counts, key, cap, overflow)
  if counts[key] == nil and key ~= overflow then
    local n = 0
    for _ in pairs(counts) do n = n + 1 end
    if n >= cap then key = overflow end
  end
  counts[key] = (counts[key] or 0) + 1
end

-- The dossier side of a kill: who they were, where and when it happened.
local function recordDetails(id, v, rec, guildChanged)
  local d = details(id)
  if guildChanged then v.rank = nil end
  v.level, v.race, v.sex = d.level or v.level, d.race or v.race, d.sex or v.sex
  v.rank, v.title = d.rank or v.rank, d.title or v.title
  if v.rank then
    -- counted per kill: people get promoted, and old kills must keep the rank they had
    v.ranks = v.ranks or {}
    bump(v.ranks, v.rank, RANK_CAP, OTHER_RANKS)
  end
  if rec.zone then
    v.zones = v.zones or {}
    bump(v.zones, rec.zone, ZONE_CAP, ELSEWHERE)
  end
  if rec.hour then
    v.hours = v.hours or {}
    v.hours[rec.hour] = (v.hours[rec.hour] or 0) + 1
  end
  if rec.day then
    if v.day ~= rec.day then v.day, v.today = rec.day, 0 end
    v.today = (v.today or 0) + 1
    if v.today > (v.dayBest or 0) then v.dayBest = v.today end
  end
  -- kills on them since we last died; a kill scored after we died since is a run of its own
  if rec.life == ns.session.life then
    local runs = ns.session.runs
    runs[id] = (runs[id] or 0) + 1
    if runs[id] > (v.bestRun or 0) then v.bestRun = runs[id] end
  elseif (v.bestRun or 0) < 1 then
    v.bestRun = 1
  end
  -- how far above us they were, at most
  if d.level and rec.myLevel then
    local diff = d.level - rec.myLevel
    if not v.up or diff > v.up then v.up = diff end
  end
  -- { when, zone, subzone, killing blow, their level, our level }
  local entry = { rec.wall or time(), rec.zone or "", rec.sub or "", rec.kb and 1 or 0, d.level or 0, rec.myLevel or 0 }
  v.hist = v.hist or {}
  v.hist[#v.hist + 1] = entry
  while #v.hist > HIST_CAP do table.remove(v.hist, 1) end
  rec.entry = entry
end

function Score(id, name, guild, tier, rec, class)
  local c = ns.char
  local pts = ns.PointsFor(tier)
  local now = time()
  local _, rankBefore = ns.RankFor(c.points)
  local v = c.victims[id]
  -- a record with no tier sits in a guild that was ignored; its old kills come back with it
  local revived = v and not v.tier
  if not v then
    v = { kills = 0, points = 0, kb = 0, first = now }
    c.victims[id] = v
    c.uniques = c.uniques + 1
  end
  -- ok = kills made while they wore the original tag; people change guilds
  v.kills, v.points = v.kills + 1, v.points + pts
  if tier == "original" then v.ok = (v.ok or 0) + 1 end
  local guildChanged = v.guild ~= nil and v.guild ~= guild
  v.guild, v.tier, v.last = guild, tier, now
  v.name = name or v.name or "Unknown"
  v.class = class or v.class
  c.kills, c.points = c.kills + 1, c.points + pts
  if tier == "original" then c.orig = c.orig + 1 end
  local g = c.guilds[guild]
  if not g then g = { kills = 0, points = 0 }; c.guilds[guild] = g end
  g.kills, g.points, g.tier = g.kills + 1, g.points + pts, tier
  rec.scored = true
  recordDetails(id, v, rec, guildChanged)
  if rec.kb then addKillingBlow(id) end
  if revived then ns.Recount() end
  local s = ns.session
  local sameLife = rec.life == s.life
  s.kills, s.points = s.kills + 1, s.points + pts
  if sameLife then s.streak = s.streak + 1 end
  if math.max(s.streak, 1) > (c.bestStreak or 0) then c.bestStreak = math.max(s.streak, 1) end
  local king = ns.IsKing(v.name, tier)
  if king then c.kings = (c.kings or 0) + 1; v.king = true end
  local rankName, rankAfter = ns.RankFor(c.points)

  ns.Log("score", v.name .. " <" .. guild .. "> +" .. pts .. (rec.kb and " kb" or ""))
  local info = { king = king, streak = sameLife and s.streak or 1, rankUp = rankAfter > rankBefore and rankName or nil,
                 first = v.kills == 1, zone = rec.zone, sub = rec.sub, kb = rec.kb and true or false }
  -- true when the announcer is calling this one, so the plain chime stays out of its way
  if ns.Hype then info.announced = hype("Olympus", id, v, tier, pts, info, rankAfter) and true or false end
  if ns.OnScore then ns.OnScore(v, guild, tier, pts, info) end
end

local function prune()
  local now = GetTime()
  for id, rec in pairs(pending) do
    if now - rec.t > PENDING_SECONDS then pending[id] = nil end
  end
  for id, rec in pairs(recent) do
    if now - rec.t > PENDING_SECONDS then recent[id] = nil end
  end
end

local function retryPending(id)
  if not pending[id] then return end
  sweepUnits() -- ObserveUnit settles the record if the victim is still visible
  if not pending[id] then return end
  local guild, class = lookup(id)
  if guild then resolvePending(id, guild, ns.Classify(guild), class) end
end

-- A player died and we get credit. kb = it was our own killing blow. calledAs = the name the
-- announcer already called this kill under, when it was called before anyone knew whose it was.
local claimCalled
local deaths, credits = {}, {}
local matchCredits
local function RegisterKill(id, name, kb, source, calledAs)
  if type(id) ~= "string" or id == "" then return end
  local now = GetTime()
  local rec = recent[id]
  if rec and now - rec.t < DEDUPE_SECONDS then
    if kb and not rec.kb then
      rec.kb = true
      -- counted late for someone who only wants their own killing blows
      if ns.Hype and not rec.hyped then rec.hyped = true hype("Kill", rec.name or name, true, id) end
      if rec.scored then
        addKillingBlow(id)
        if rec.entry then rec.entry[4] = 1 end
        if ns.Comm then ns.Comm.MarkDirty() end
        if ns.OnChanged then ns.OnChanged() end
      end
    end
    return
  end
  prune()
  -- a killing blow or an honor line that arrives after its credit was called: the same kill
  if not calledAs and source ~= "HK" and claimCalled then calledAs = claimCalled() end

  sweepUnits()
  local guild, class, seenName = lookup(id)
  name = seenName or name
  rec = { t = now, kb = kb and true or false, name = name, life = ns.session.life }
  -- where and when, taken now: a kill waiting for its guild tag is scored later
  local wall = time()
  local hour, myLevel = tonumber((try(date, "%H", wall))), plain(try(UnitLevel, "player"))
  local day = try(date, "%Y%m%d", wall)
  rec.wall, rec.day = wall, type(day) == "string" and day or nil
  rec.hour = hour and hour >= 0 and hour <= 23 and math.floor(hour) or nil
  rec.zone, rec.sub = clean((try(GetRealZoneText))), clean((try(GetSubZoneText)))
  rec.myLevel = type(myLevel) == "number" and myLevel >= 1 and math.floor(myLevel) or nil
  recent[id] = rec
  if source ~= "HK" then
    -- this kill's own honor credit must find it, whatever noteDeath thinks of the victim
    local have
    for _, d in ipairs(deaths) do if d.id == id and now - d.t < 5 then have = d end end
    if not have then have = { id = id, t = now } deaths[#deaths + 1] = have end
    if calledAs then have.used = true end
  end
  ns.Log("kill", tostring(name or id) .. " via " .. source .. (kb and " kb" or ""))
  if ns.Hype then
    local mode = GodslayerDB.opts.hype and GodslayerDB.opts.hype.mode
    if kb or mode ~= "blows" then rec.hyped = true end
    -- the announcer may already have called this kill before anyone knew whose it was: give it its name
    if not (calledAs and hype("Named", calledAs, id, name, kb and true or false)) then
      hype("Kill", name, kb and true or false, id)
    end
  end

  if guild then
    local tier = ns.Classify(guild)
    if tier then Score(id, name, guild, tier, rec, class) end
    if source ~= "HK" and #credits > 0 then matchCredits() end
    return
  end
  -- Guild not known yet. Keep the kill and credit it if we see their tag soon.
  pending[id] = rec
  if source ~= "HK" and #credits > 0 then matchCredits() end
  C_Timer.After(1.5, function() retryPending(id) end)
  C_Timer.After(6, function() retryPending(id) end)
end
ns.RegisterKill = RegisterKill

local function nameFromGUID(guid)
  local e = seen[guid]
  if e and e.name then return e.name end
  local k = GodslayerDB.known[guid]
  if k and k.n then return k.n end
  local _, _, _, _, _, name = try(GetPlayerInfoByGUID, guid)
  name = plain(name)
  if type(name) == "string" and name ~= "" then return name end
end

-- ---------------------------------------------------------------------------
-- Honorable-kill credit matched to a death we saw
-- ---------------------------------------------------------------------------

local ANON_AFTER, anonCount = 1.2, 0 -- seconds a credit waits for its death before it is called without a name
local lastHK, lastCreditEvent = nil, 0

-- An enemy player died near us. Two events can report the same death.
local function noteDeath(guid)
  if type(guid) ~= "string" or guid:sub(1, 7) ~= "Player-" or guid == myGUID then return end
  if plain(try(IsGUIDInGroup, guid)) then return end
  local e = seen[guid]
  if e and e.hostile == false then return end
  local now = GetTime()
  for _, d in ipairs(deaths) do
    if d.id == guid and now - d.t < 5 then return end
  end
  deaths[#deaths + 1] = { id = guid, t = now }
  if #credits > 0 then matchCredits() end
end

-- How good a match a death is for a credit: a known network member beats a known
-- enemy, which beats a stranger whose faction we never saw.
noteDeathRef = noteDeath

local function deathWeight(d)
  local e = seen[d.id]
  local guild = lookup(d.id)
  if guild and ns.Classify(guild) then return 2 end
  if e and e.hostile then return 1 end
  return 0
end

local function feigning(guid)
  local unit = plain(try(UnitTokenFromGUID, guid))
  return type(unit) == "string" and plain(try(UnitIsFeignDeath, unit)) == true
end

-- The credit that was called without a name and is still waiting for its death, if there is one.
claimCalled = function()
  local now = GetTime()
  for i, credit in ipairs(credits) do
    if credit.called and now - credit.t <= MATCH_WINDOW then
      table.remove(credits, i)
      return credit.called
    end
  end
end

function matchCredits()
  local now = GetTime()
  for i = #deaths, 1, -1 do
    if now - deaths[i].t > MATCH_WINDOW + 2 then table.remove(deaths, i) end
  end
  for i = #credits, 1, -1 do
    if now - credits[i].t > MATCH_WINDOW + 2 then table.remove(credits, i) end
  end
  local c = 1
  while c <= #credits do
    local credit = credits[c]
    local ct, best, bestGap, bestWeight, already = credit.t, nil, nil, -1, nil
    for _, d in ipairs(deaths) do
      local gap = math.abs(d.t - ct)
      if not d.used and gap <= MATCH_WINDOW then
        local rec = recent[d.id]
        if rec and now - rec.t < DEDUPE_SECONDS then already = d; break end
        if feigning(d.id) then
          d.used = true
        else
          local weight = deathWeight(d)
          if weight > bestWeight or (weight == bestWeight and gap < bestGap) then
            best, bestGap, bestWeight = d, gap, weight
          end
        end
      end
    end
    local d = already or best
    if d then
      d.used = true
      table.remove(credits, c)
      if not already then RegisterKill(d.id, nameFromGUID(d.id), false, "HK", credit.called) end
    else
      -- credit for a kill nobody saw die (too far, behind a wall, a crowd): it is still a kill, and
      -- the announcer says so now. If the death turns up in the next seconds it gets its name then.
      if not credit.called and now - ct >= ANON_AFTER and ns.Hype then
        anonCount = anonCount + 1
        credit.called = "anon:" .. anonCount
        ns.Log("kill", "unseen victim via HK")
        hype("Kill", nil, false, credit.called)
      end
      c = c + 1
    end
  end
end

-- ---------------------------------------------------------------------------
-- Honor chat line that names the victim: "<name> dies, honorable kill ..."
-- Patterns are built from the client's own format strings so they follow its wording.
-- ---------------------------------------------------------------------------

local HONOR_GLOBALS = {
  "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK",
  "COMBATLOG_HONORGAIN_EXHAUSTION1", "COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1",
}
local honorPatterns = {}

-- Turns "%s dies, honorable kill Rank: %s (%d)" into a Lua pattern, and says which
-- capture holds the first format argument (the victim).
local function formatToPattern(fmt)
  local out, i, capture, auto, nameCapture = { "^" }, 1, 0, 0, nil
  while i <= #fmt do
    local ch = fmt:sub(i, i)
    if ch == "%" then
      if fmt:sub(i + 1, i + 1) == "%" then
        out[#out + 1] = "%%"
        i = i + 2
      else
        local pos, spec, nextI = fmt:match("^%%(%d+)%$[%-%+ #0]*%d*%.?%d*([a-zA-Z])()", i)
        if not pos then
          spec, nextI = fmt:match("^%%[%-%+ #0]*%d*%.?%d*([a-zA-Z])()", i)
          auto = auto + 1
          pos = auto
        end
        if not spec then return nil end
        capture = capture + 1
        if tonumber(pos) == 1 then nameCapture = capture end
        out[#out + 1] = (spec == "s") and "(.-)" or "(%-?[%d%.,]+)"
        i = nextI
      end
    else
      out[#out + 1] = (ch:gsub("[%^%$%(%)%.%[%]%*%+%-%?]", "%%%0"))
      i = i + 1
    end
  end
  if not nameCapture then return nil end
  out[#out + 1] = "$"
  return table.concat(out), nameCapture
end
ns.formatToPattern = formatToPattern

local function buildHonorPatterns()
  honorPatterns = {}
  for _, g in ipairs(HONOR_GLOBALS) do
    local fmt = _G[g]
    if type(fmt) == "string" then
      local pattern, cap = formatToPattern(fmt)
      if pattern then honorPatterns[#honorPatterns + 1] = { pattern, cap } end
    end
  end
  honorPatterns[#honorPatterns + 1] = { "^(.-) dies, honorable kill", 1 }
end

local function parseHonorLine(text)
  for _, p in ipairs(honorPatterns) do
    local caps = { text:match(p[1]) }
    local who = caps[p[2]]
    if who and who ~= "" then return who end
  end
end
ns.parseHonorLine = parseHonorLine

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

local handlers = {}

function handlers.PARTY_KILL(attackerGUID, targetGUID)
  local secret = issecret(attackerGUID) or issecret(targetGUID)
  attackerGUID, targetGUID = plain(attackerGUID), plain(targetGUID)
  if type(targetGUID) ~= "string" then
    -- the client hides creatures' identities, so every dungeon pull would write this: say it once
    if secret and not ns.hiddenLogged then ns.hiddenLogged = true ns.Log("party_kill", "victim hidden by the client (logged once per session)") end
    return
  end
  if targetGUID:sub(1, 7) ~= "Player-" then return end
  if type(attackerGUID) ~= "string" then attackerGUID = nil end

  local mine = attackerGUID and (attackerGUID == myGUID or attackerGUID == plain(try(UnitGUID, "pet")))
  if not mine and not (attackerGUID and plain(try(IsGUIDInGroup, attackerGUID))) then
    ns.Log("party_kill", "not ours" .. (secret and " (attacker hidden)" or ""))
    return
  end
  RegisterKill(targetGUID, nameFromGUID(targetGUID), mine and true or false, "PARTY_KILL")
  -- the killing blow is also a death seen: the honor credit for it must not be called as a second kill
  noteDeath(targetGUID)
end

function handlers.UNIT_DIED(guid)
  noteDeath(plain(guid))
end

-- Second way to see a death, for clients where UNIT_DIED does not report bystanders.
function handlers.UNIT_HEALTH(unit)
  unit = plain(unit)
  if type(unit) ~= "string" then return end
  if unit ~= "target" and unit ~= "focus" and unit:sub(1, 9) ~= "nameplate" then return end
  if plain(try(UnitIsDeadOrGhost, unit)) ~= true then return end
  ObserveUnit(unit)
end

function handlers.PLAYER_PVP_KILLS_CHANGED(unit)
  -- the event names whose count changed; only your own is a credit, and a hidden name is not known to be yours
  if issecret(unit) then return end
  unit = plain(unit)
  if unit ~= nil and unit ~= "player" then return end
  local now = GetTime()
  local hk = plain(try(GetPVPSessionStats))
  local gained
  if type(hk) == "number" then
    -- the event can fire twice per kill, so trust the counter and not the event count
    if lastHK == nil or hk < lastHK then
      gained = 1
    else
      gained = math.min(hk - lastHK, 5)
    end
    lastHK = hk
  else
    gained = (now - lastCreditEvent > 0.5) and 1 or 0
  end
  lastCreditEvent = now
  for _ = 1, gained do credits[#credits + 1] = { t = now } end
  if gained > 0 then
    -- the death and the killing blow can arrive just after the credit
    C_Timer.After(0.6, matchCredits)
    C_Timer.After(ANON_AFTER + 0.05, matchCredits)
    C_Timer.After(3, matchCredits)
    C_Timer.After(MATCH_WINDOW + 0.5, matchCredits)
  end
end

function handlers.CHAT_MSG_COMBAT_HONOR_GAIN(text)
  if issecret(text) then ns.Log("honor", "text hidden by the client"); return end
  if type(text) ~= "string" then return end
  local who = parseHonorLine(text)
  if not who then
    -- the usual Forever line names nobody; keep a few samples for debugging
    ns.unparsed = (ns.unparsed or 0) + 1
    if ns.unparsed <= 5 then ns.Log("honor?", text) end
    return
  end
  local id = nameId[who]
  if not id then
    -- the line may carry a first name only
    for full, candidate in pairs(nameId) do
      if full:match("^(%S+)") == who then
        if id then id = nil; break end -- two people share it; do not guess
        id = candidate
      end
    end
  end
  RegisterKill(id or ("name:" .. who), who, false, "HONOR")
end

function handlers.PLAYER_DEAD()
  if ns.Hype then hype("Died") end
  ns.session.runs, ns.session.life = {}, ns.session.life + 1
  if ns.session.streak > 0 then
    ns.session.streak = 0
    if ns.OnChanged then ns.OnChanged() end
  end
end

function handlers.PLAYER_TARGET_CHANGED() ObserveUnit("target") end
function handlers.UPDATE_MOUSEOVER_UNIT() ObserveUnit("mouseover") end
function handlers.PLAYER_FOCUS_CHANGED() ObserveUnit("focus") end

function handlers.NAME_PLATE_UNIT_ADDED(unit)
  unit = plain(unit)
  if type(unit) == "string" then ObserveUnit(unit) end
end

function handlers.PLAYER_LOGIN()
  initChar()
  buildHonorPatterns()
  pruneKnown()
  local hk = plain(try(GetPVPSessionStats))
  if type(hk) == "number" then lastHK = hk end
  ns.Log("login", myName .. " v" .. ns.VERSION .. " build " .. tostring((try(GetBuildInfo))))
  -- guild tags can arrive a moment after a nameplate does, so keep re-reading them
  C_Timer.NewTicker(2, function()
    for i = 1, 40 do ObserveUnit("nameplate" .. i) end
  end)
  if ns.Hype then hype("Login") end
  if ns.Comm then ns.Comm.Init() end
  if ns.UI then ns.UI.Init() end
end

local frame = CreateFrame("Frame")
ns.frame = frame

local function safeCall(event, ...)
  local h = handlers[event] or (ns.Comm and ns.Comm.handlers[event]) or (ns.Hype and ns.Hype.handlers and ns.Hype.handlers[event])
  if not h then return end
  local ok, err = pcall(h, ...)
  if not ok then
    ns.errors = (ns.errors or 0) + 1
    if ns.errors <= 25 then ns.Log("error", event .. ": " .. tostring(err)) end
  end
end

frame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == ADDON then
      initDB()
      frame:UnregisterEvent("ADDON_LOADED")
    end
    return
  end
  if not GodslayerDB then return end
  if event ~= "PLAYER_LOGIN" and not ns.char then return end
  safeCall(event, ...)
end)

frame:RegisterEvent("ADDON_LOADED")
-- COMBAT_LOG_EVENT_UNFILTERED is deliberately absent: addons may not register it here.
for _, event in ipairs({
  "PLAYER_LOGIN", "PARTY_KILL", "UNIT_DIED", "UNIT_HEALTH", "PLAYER_PVP_KILLS_CHANGED",
  "CHAT_MSG_COMBAT_HONOR_GAIN", "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT",
  "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED", "CHAT_MSG_ADDON",
  "PLAYER_GUILD_UPDATE", "PLAYER_ENTERING_WORLD", "PLAYER_DEAD",
  -- the announcer's own: duels, interrupts, coming back to life
  "DUEL_REQUESTED", "DUEL_FINISHED", "CHAT_MSG_SYSTEM", "UNIT_SPELLCAST_SUCCEEDED", "UNIT_SPELLCAST_INTERRUPTED",
  "PLAYER_UNGHOST", "PLAYER_ALIVE",
}) do
  pcall(frame.RegisterEvent, frame, event) -- an event this client lacks must not stop the rest
end

-- ---------------------------------------------------------------------------
-- Maintenance used by the slash commands
-- ---------------------------------------------------------------------------

function ns.ResetCharacter()
  local c = ns.char
  local class = c.class
  for k in pairs(c) do c[k] = nil end
  for k, v in pairs(newChar()) do c[k] = v end
  c.class = class
  ns.session = { kills = 0, points = 0, streak = 0, runs = {}, life = 1 }
  pending, recent = {}, {}
end

-- Rebuild totals after the guild rules change (add / ignore).
function ns.Recount()
  local c = ns.char
  c.kills, c.points, c.uniques, c.kb, c.orig, c.guilds = 0, 0, 0, 0, 0, {}
  -- regicides and the best streak are history, not totals, so they are left alone
  for id, v in pairs(c.victims) do
    local tier = v.guild and ns.Classify(v.guild)
    v.tier = tier -- nil keeps the record but leaves it out of the totals and lists
    if tier then
      local ok = math.min(v.ok or 0, v.kills)
      v.points = ok * ns.ORIGINAL_POINTS + (v.kills - ok) * ns.NETWORK_POINTS
      c.kills, c.points, c.uniques = c.kills + v.kills, c.points + v.points, c.uniques + 1
      c.kb = c.kb + (v.kb or 0)
      c.orig = c.orig + ok
      local g = c.guilds[v.guild]
      if not g then g = { kills = 0, points = 0, tier = tier }; c.guilds[v.guild] = g end
      g.kills, g.points = g.kills + v.kills, g.points + v.points
    end
  end
end

-- ---------------------------------------------------------------------------
-- Things worked out from the kill records, for the window and the brag lines
-- ---------------------------------------------------------------------------

-- What a player is to you after this many kills: label and the count the next one needs.
function ns.VictimTier(kills)
  local label, nextAt
  for _, tier in ipairs(ns.VICTIM_TIERS) do
    if kills >= tier[1] then label = tier[2] elseif not nextAt then nextAt = tier[1] end
  end
  return label, nextAt
end

function ns.KillsToday()
  local day, n = try(date, "%Y%m%d", time()), 0
  if type(day) ~= "string" then return 0 end
  for _, v in pairs(ns.char.victims) do
    if v.tier and v.day == day then n = n + (v.today or 0) end
  end
  return n
end

-- The player you have killed most, once it is more than a coincidence.
function ns.Nemesis()
  local best, bestId
  for id, v in pairs(ns.char.victims) do
    if v.tier and v.kills >= 2 then
      if not best or v.kills > best.kills or (v.kills == best.kills and (v.last or 0) > (best.last or 0)) then
        best, bestId = v, id
      end
    end
  end
  return best, bestId
end

-- Kills split by class, zone, guild rank and hour, plus a few records. Built from the
-- victims every time, so it can never drift from the totals.
function ns.Aggregates()
  local a = { class = {}, zone = {}, rank = {}, hour = {}, kills = 0, zoned = 0, timed = 0 }
  for id, v in pairs(ns.char.victims) do
    if v.tier then
      a.kills = a.kills + v.kills
      if v.class then a.class[v.class] = (a.class[v.class] or 0) + v.kills end
      for rank, n in pairs(v.ranks or {}) do a.rank[rank] = (a.rank[rank] or 0) + n end
      for zone, n in pairs(v.zones or {}) do a.zone[zone] = (a.zone[zone] or 0) + n; a.zoned = a.zoned + n end
      for hour, n in pairs(v.hours or {}) do a.hour[hour] = (a.hour[hour] or 0) + n; a.timed = a.timed + n end
      if v.level and (not a.highest or v.level > a.highest.level) then a.highest = v end
      if v.up and (not a.upset or v.up > a.upset.up) then a.upset = v end
      if v.dayBest and (not a.day or v.dayBest > a.day.dayBest) then a.day = v end
      if v.bestRun and (not a.run or v.bestRun > a.run.bestRun) then a.run = v end
    end
  end
  return a
end

-- Network members you have seen and not killed yet, the original guild first, then the
-- most recently seen.
function ns.HitList()
  local list, victims = {}, ns.char.victims
  for id, k in pairs(GodslayerDB.known) do
    local v = victims[id]
    if not (v and v.tier) and type(k.n) == "string" then
      local tier = ns.Classify(k.g)
      if tier then
        list[#list + 1] = { id = id, name = k.n, guild = k.g, class = k.c, level = k.l, race = k.r, rank = k.k,
                            zone = k.z, t = k.t or 0, tier = tier }
      end
    end
  end
  table.sort(list, function(x, y)
    if x.tier ~= y.tier then return x.tier == "original" end
    if x.t ~= y.t then return x.t > y.t end
    return x.name < y.name
  end)
  return list
end

-- A victim by name: exact first, then the start of a name, any capitalisation.
function ns.FindVictim(text)
  if type(text) ~= "string" or text == "" then return nil end
  local want, partial, partialId = text:lower(), nil, nil
  for id, v in pairs(ns.char.victims) do
    local name = type(v.name) == "string" and v.name:lower() or ""
    if name == want then return v, id end
    if name:sub(1, #want) == want and (not partial or v.kills > partial.kills) then partial, partialId = v, id end
  end
  return partial, partialId
end
