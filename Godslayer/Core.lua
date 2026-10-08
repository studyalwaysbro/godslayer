-- Godslayer core: guild matching, kill detection, scoring.
--
-- The Forever client closes the combat log to addons (registering it raises a
-- forbidden-action popup), so kills come from the signals the client still hands out:
--   PARTY_KILL                killing blows by you, your pet or your group, as GUIDs
--   PLAYER_PVP_KILLS_CHANGED  you got honorable-kill credit, matched to a death seen
--                             at the same moment through UNIT_DIED
--   the honor chat line       only when it names the victim, which is rare on Forever
-- Guild names come from units you can see (target, mouseover, focus, nameplates).
-- Players are keyed by GUID: Forever has first and last names and no realms.
-- Everything read from the game is checked for secret values before it is compared.

local ADDON, ns = ...

ns.VERSION = "1.0.0"

local DEDUPE_SECONDS = 10        -- the signals above can all describe the same death
local MATCH_WINDOW = 8           -- honorable-kill credit and a seen death must be this close
local PENDING_SECONDS = 15 * 60  -- how long a kill waits for the victim's guild to be seen
local KNOWN_MAX_AGE = 7 * 86400  -- how long a remembered guild tag is trusted for scoring
local KNOWN_CAP, SEEN_CAP, LOG_CAP = 4000, 1500, 150

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
  local ok, a, b, c, d, e, g, h = pcall(f, ...)
  if ok then return a, b, c, d, e, g, h end
end
ns.try = try

function ns.Print(msg)
  print("|cffff7d0aGodslayer:|r " .. tostring(msg))
end

function ns.Log(kind, msg)
  local db = GodslayerDB
  if not db then return end
  local log = db.log
  log[#log + 1] = date("%m-%d %H:%M:%S") .. " " .. kind .. ": " .. tostring(msg)
  while #log > LOG_CAP do table.remove(log, 1) end
end

-- ---------------------------------------------------------------------------
-- Guild matching
-- ---------------------------------------------------------------------------

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
  db.version = 1
  db.chars = db.chars or {}     -- per character scores
  db.roster = db.roster or {}   -- [guild][member] = scores received over addon chat
  db.known = db.known or {}     -- network members seen: [id] = { n = name, g = guild, c = class, t = time }
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
  ns.session = { kills = 0, points = 0, streak = 0 }
end

-- ---------------------------------------------------------------------------
-- Who is in which guild
-- ---------------------------------------------------------------------------

local seen, seenCount = {}, 0   -- this session: [id] = { name, guild, class, hostile, t }
local nameId = {}               -- [full name] = id, for the rare signal that only has a name
local pending = {}              -- kills waiting for a guild: [id] = record
local recent = {}               -- last kill per victim: [id] = record

local function pruneKnown()
  local known = GodslayerDB.known
  local list = {}
  for id, e in pairs(known) do list[#list + 1] = { id, e.t or 0 } end
  if #list <= KNOWN_CAP then return end
  table.sort(list, function(a, b) return a[2] < b[2] end)
  for i = 1, #list - KNOWN_CAP + 200 do known[list[i][1]] = nil end
end

local Score, noteDeathRef -- defined below

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
  local guild = plain((try(GetGuildInfo, unit)))
  if type(guild) ~= "string" or guild == "" then guild = nil end
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
  e.guild = guild

  local tier = ns.Classify(guild)
  local known = GodslayerDB.known
  if tier then
    known[id] = { n = name, g = guild, c = e.class, t = time() }
  elseif known[id] then
    known[id] = nil -- they left the network
  end
  resolvePending(id, guild, tier, e.class)
  return id, guild
end
ns.ObserveUnit = ObserveUnit

local function sweepUnits()
  ObserveUnit("target")
  ObserveUnit("mouseover")
  ObserveUnit("focus")
  ObserveUnit("softenemy")
  for i = 1, 40 do ObserveUnit("nameplate" .. i) end
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
  v.guild, v.tier, v.last = guild, tier, now
  v.name = name or v.name or "Unknown"
  v.class = class or v.class
  c.kills, c.points = c.kills + 1, c.points + pts
  if tier == "original" then c.orig = c.orig + 1 end
  local g = c.guilds[guild]
  if not g then g = { kills = 0, points = 0 }; c.guilds[guild] = g end
  g.kills, g.points, g.tier = g.kills + 1, g.points + pts, tier
  rec.scored = true
  if rec.kb then addKillingBlow(id) end
  if revived then ns.Recount() end
  local s = ns.session
  s.kills, s.points, s.streak = s.kills + 1, s.points + pts, s.streak + 1
  if s.streak > (c.bestStreak or 0) then c.bestStreak = s.streak end
  local king = ns.IsKing(v.name, tier)
  if king then c.kings = (c.kings or 0) + 1; v.king = true end
  local rankName, rankAfter = ns.RankFor(c.points)

  ns.Log("score", v.name .. " <" .. guild .. "> +" .. pts .. (rec.kb and " kb" or ""))
  if ns.OnScore then
    ns.OnScore(v, guild, tier, pts, { king = king, streak = s.streak, rankUp = rankAfter > rankBefore and rankName or nil })
  end
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

-- A player died and we get credit. kb = it was our own killing blow.
local function RegisterKill(id, name, kb, source)
  if type(id) ~= "string" or id == "" then return end
  local now = GetTime()
  local rec = recent[id]
  if rec and now - rec.t < DEDUPE_SECONDS then
    if kb and not rec.kb then
      rec.kb = true
      if rec.scored then
        addKillingBlow(id)
        if ns.Comm then ns.Comm.MarkDirty() end
        if ns.OnChanged then ns.OnChanged() end
      end
    end
    return
  end
  prune()

  sweepUnits()
  local guild, class, seenName = lookup(id)
  name = seenName or name
  rec = { t = now, kb = kb and true or false, name = name }
  recent[id] = rec
  ns.Log("kill", tostring(name or id) .. " via " .. source .. (kb and " kb" or ""))

  if guild then
    local tier = ns.Classify(guild)
    if tier then Score(id, name, guild, tier, rec, class) end
    return
  end
  -- Guild not known yet. Keep the kill and credit it if we see their tag soon.
  pending[id] = rec
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

local deaths, credits = {}, {}
local lastHK, lastCreditEvent = nil, 0
local matchCredits

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

function matchCredits()
  local now = GetTime()
  for i = #deaths, 1, -1 do
    if now - deaths[i].t > MATCH_WINDOW + 2 then table.remove(deaths, i) end
  end
  for i = #credits, 1, -1 do
    if now - credits[i] > MATCH_WINDOW + 2 then table.remove(credits, i) end
  end
  local c = 1
  while c <= #credits do
    local ct, best, bestGap, bestWeight, already = credits[c], nil, nil, -1, nil
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
      if not already then RegisterKill(d.id, nameFromGUID(d.id), false, "HK") end
    else
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
    if secret then ns.Log("party_kill", "victim hidden by the client") end
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

function handlers.PLAYER_PVP_KILLS_CHANGED()
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
  for _ = 1, gained do credits[#credits + 1] = now end
  if gained > 0 then
    -- the death and the killing blow can arrive just after the credit
    C_Timer.After(0.6, matchCredits)
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
  if ns.Comm then ns.Comm.Init() end
  if ns.UI then ns.UI.Init() end
end

local frame = CreateFrame("Frame")
ns.frame = frame

local function safeCall(event, ...)
  local h = handlers[event] or (ns.Comm and ns.Comm.handlers[event])
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
  ns.session = { kills = 0, points = 0, streak = 0 }
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
