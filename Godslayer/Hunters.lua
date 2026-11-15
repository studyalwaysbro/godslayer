-- Godslayer Hunters: a first-hand, self-reported cross-realm leaderboard.
--
-- The custom channel is a directory only. Every byte of addon data travels by
-- WHISPER, and a ranked row is owned by the sender of the R message that supplied it.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Hunters = { handlers = {} }
ns.Hunters = Hunters

local PREFIX, PROTO, CHANNEL = "GodslayerG", "1", "GodslayerHunters"
local MAX_PAYLOAD, MAX_INTRO = 240, 220
local ROW_TTL, CANDIDATE_TTL, PARTNER_TTL = 7 * 86400, 7 * 86400, 1800
local PENDING_TTL, NONCE_TTL = 20, 600
local ROW_CAP, CANDIDATE_CAP = 6000, 300
local PARTNER_CAP, PENDING_CAP, NONCE_CAP = 6, 32, 256
local QUEUE_CAP, PER_TARGET_CAP = 24, 2
local CLASSES = { DRUID=true, HUNTER=true, MAGE=true, PALADIN=true, PRIEST=true,
  ROGUE=true, SHAMAN=true, WARLOCK=true, WARRIOR=true }
local BACKOFF = { 1800, 4 * 3600, 24 * 3600, 7 * 86400 }
local THROTTLE = { 10, 20, 40, 80, 120 }
local NOTICE = "Slayers is on. It shares your name, class, kill counts, Olympus kills, rung, and your kills as they happen, including the victim's name and class when known, with other Godslayer users of your faction and ruleset by addon whisper across realms. Their clients may keep it for up to 7 days. /godslayer slayers off stops sharing, but cannot erase copies already received."
local NEWS_QUIET, NEWS_HARD, NEWS_FRESH = 12, 30, 300
local NEWS_PER_MINUTE, NON_RESPONSE_PER_MINUTE, OFFLINE_COOLDOWN = 6, 8, 1800
local FEED_LAST_CAP, NEWS_OFFLINE_CAP = 64, 300

Hunters.PREFIX, Hunters.CHANNEL = PREFIX, CHANNEL
Hunters.NOTICE = NOTICE
Hunters.LIMITS = {
  payload = MAX_PAYLOAD, introduction = MAX_INTRO, rows = ROW_CAP, candidates = CANDIDATE_CAP,
  partners = PARTNER_CAP, pending = PENDING_CAP, completed = NONCE_CAP,
  queue = QUEUE_CAP, perTarget = PER_TARGET_CAP,
}

local runtime = {
  queue = {}, snapshots = {}, sentMinute = {}, sentBurst = {}, nonResponseBurst = {}, snapshotMinute = {}, nonResponseMinute = {}, responseMinute = {}, introMinute = {},
  inboundMinute = {}, inboundBySender = {}, responseScheduled = 0,
  throttleStep = 0, throttleSuccess = 0, pauseUntil = 0, lastSend = -1e9,
  world = false, directory = "starting", board = {}, boardRevision = 0,
  offlineTargets = {}, offlineOrder = {}, directoryNames = {}, feedMinute = {}, feedPending = {}, guildNews = {},
  notifiedRows = {}, newsBase = {},
}

local function now()
  local v = plain(try(GetTime))
  return type(v) == "number" and v or 0
end

local function serverNow()
  local v = type(GetServerTime) == "function" and plain(try(GetServerTime)) or nil
  if type(v) ~= "number" then v = type(time) == "function" and plain(try(time)) or nil end
  return type(v) == "number" and math.floor(v) or 0
end

local function rateNow()
  local mono = now()
  return serverNow() + (mono - math.floor(mono))
end

local function profileMS()
  if type(debugprofilestop) == "function" then
    local v = plain(try(debugprofilestop))
    if type(v) == "number" then return v end
  end
  return nil
end

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"
local function base36(n)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return "0" end
  local out = ""
  while n > 0 do
    local d = n % 36
    out = DIGITS:sub(d + 1, d + 1) .. out
    n = math.floor(n / 36)
  end
  return out
end

local function unbase36(text, cap)
  if type(text) ~= "string" or text == "" or #text > 12 or not text:match("^[0-9a-z]+$") then return nil end
  local n = 0
  for i = 1, #text do
    local b = text:byte(i)
    local d = b >= 48 and b <= 57 and b - 48 or b >= 97 and b <= 122 and b - 87 or nil
    if not d then return nil end
    n = n * 36 + d
    if n > (cap or 1e12) then return nil end
  end
  if n ~= math.floor(n) then return nil end
  return n
end
Hunters.Base36, Hunters.Unbase36 = base36, unbase36

local function split(text, sep)
  local fields, at = {}, 1
  while true do
    local cut = text:find(sep, at, true)
    if not cut then fields[#fields + 1] = text:sub(at); break end
    fields[#fields + 1] = text:sub(at, cut - 1)
    at = cut + #sep
  end
  return fields
end

local function utf8Codepoints(text)
  local out, i = {}, 1
  while i <= #text do
    local a = text:byte(i)
    local cp, n
    if a < 0x80 then cp, n = a, 1
    elseif a >= 0xC2 and a <= 0xDF then
      local b = text:byte(i + 1); if not b or b < 0x80 or b > 0xBF then return nil end
      cp, n = (a - 0xC0) * 0x40 + b - 0x80, 2
    elseif a >= 0xE0 and a <= 0xEF then
      local b, c = text:byte(i + 1), text:byte(i + 2)
      if not b or not c or b < 0x80 or b > 0xBF or c < 0x80 or c > 0xBF
         or (a == 0xE0 and b < 0xA0) or (a == 0xED and b > 0x9F) then return nil end
      cp, n = (a - 0xE0) * 0x1000 + (b - 0x80) * 0x40 + c - 0x80, 3
    elseif a >= 0xF0 and a <= 0xF4 then
      local b, c, d = text:byte(i + 1), text:byte(i + 2), text:byte(i + 3)
      if not b or not c or not d or b < 0x80 or b > 0xBF or c < 0x80 or c > 0xBF
         or d < 0x80 or d > 0xBF or (a == 0xF0 and b < 0x90) or (a == 0xF4 and b > 0x8F) then return nil end
      cp, n = (a - 0xF0) * 0x40000 + (b - 0x80) * 0x1000 + (c - 0x80) * 0x40 + d - 0x80, 4
    else return nil end
    out[#out + 1] = cp
    i = i + n
  end
  return out
end

local function scriptOf(cp)
  if (cp >= 65 and cp <= 90) or (cp >= 97 and cp <= 122)
     or (cp >= 0xC0 and cp <= 0xD6) or (cp >= 0xD8 and cp <= 0xF6)
     or (cp >= 0xF8 and cp <= 0x24F) or (cp >= 0x1E00 and cp <= 0x1EFF) then return "latin" end
  if (cp >= 0x370 and cp <= 0x373) or (cp >= 0x376 and cp <= 0x377)
     or (cp >= 0x37B and cp <= 0x37D) or cp == 0x386 or (cp >= 0x388 and cp <= 0x38A)
     or cp == 0x38C or (cp >= 0x38E and cp <= 0x3E1) or (cp >= 0x3F0 and cp <= 0x3FF) then return "greek" end
  if (cp >= 0x400 and cp <= 0x481) or (cp >= 0x48A and cp <= 0x52F) then return "cyrillic" end
end

local function utf8Char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- Lua 5.1's string.lower is byte-oriented. Forever names can contain the Latin, Greek and
-- Cyrillic alphabets, so fold their ordinary uppercase ranges explicitly before building a key.
local LOWER_SPECIAL = {
  [0x130]=0x69, [0x178]=0xFF,
  [0x386]=0x3AC, [0x388]=0x3AD, [0x389]=0x3AE, [0x38A]=0x3AF,
  [0x38C]=0x3CC, [0x38E]=0x3CD, [0x38F]=0x3CE,
}
local function lowerCodepoint(cp)
  if cp >= 65 and cp <= 90 then return cp + 32 end
  if (cp >= 0xC0 and cp <= 0xD6) or (cp >= 0xD8 and cp <= 0xDE) then return cp + 32 end
  if cp >= 0x100 and cp <= 0x12F and cp % 2 == 0 then return cp + 1 end
  if cp >= 0x132 and cp <= 0x137 and cp % 2 == 0 then return cp + 1 end
  if cp >= 0x139 and cp <= 0x148 and cp % 2 == 1 then return cp + 1 end
  if cp >= 0x14A and cp <= 0x177 and cp % 2 == 0 then return cp + 1 end
  if cp >= 0x179 and cp <= 0x17E and cp % 2 == 1 then return cp + 1 end
  if (cp >= 0x391 and cp <= 0x3A1) or (cp >= 0x3A3 and cp <= 0x3AB) then return cp + 32 end
  if cp >= 0x400 and cp <= 0x40F then return cp + 80 end
  if cp >= 0x410 and cp <= 0x42F then return cp + 32 end
  if cp >= 0x460 and cp <= 0x481 and cp % 2 == 0 then return cp + 1 end
  return LOWER_SPECIAL[cp] or cp
end

local function lowercaseName(text)
  local cps = utf8Codepoints(text); if not cps then return nil end
  local out = {}
  for i, cp in ipairs(cps) do out[i] = utf8Char(lowerCodepoint(cp)) end
  return table.concat(out)
end

local function realmToken(text)
  return type(text) == "string" and text:lower():gsub("[^%a%d]", "") or nil
end

local realmTokensCache
local function knownRealmTokens()
  if realmTokensCache then return realmTokensCache end
  local known = {}
  local probes = {}
  if type(GetRealmName) == "function" then probes[#probes + 1] = GetRealmName end
  if type(GetNormalizedRealmName) == "function" then probes[#probes + 1] = GetNormalizedRealmName end
  for _, fn in ipairs(probes) do
    if type(fn) == "function" then
      local value = plain(try(fn))
      local realm = realmToken(value)
      if realm and realm ~= "" then known[realm] = true end
    end
  end
  realmTokensCache = known
  return known
end

local function backendRealmToken(text)
  local label = type(text) == "string" and text:lower() or ""
  return label:match("^camwow%a+%d+realm%d+%a*$") ~= nil
end

local function canonicalName(raw)
  raw = plain(raw)
  if type(raw) ~= "string" then return nil end
  raw = raw:match("^%s*(.-)%s*$") or ""
  if raw == "" or #raw > 49 or raw:find("[|:;%c]") then return nil end
  if not utf8Codepoints(raw) then return nil end
  local known = knownRealmTokens()
  local first, rest = raw:match("^([^%-]+)%-(.+)$")
  if first then
    if first:find(" ", 1, true) then
      -- Forever may append the backend label to an already complete "First Last" name.
      raw = first
    else
      local parts = split(raw, "-")
      if #parts == 2 and parts[1] ~= "" and parts[2] ~= "" then
        if known[realmToken(parts[2]) or ""] or backendRealmToken(parts[2]) then raw = parts[1]
        else raw = parts[1] .. " " .. parts[2] end
      elseif #parts == 3 and parts[1] ~= "" and parts[2] ~= "" and parts[3] ~= "" then
        raw = parts[1] .. " " .. parts[2]
      else
        return nil
      end
    end
  end
  if raw:find("  ", 1, true) or select(2, raw:gsub(" ", "")) > 1 then return nil end
  local script
  for segment in raw:gmatch("[^ ]+") do
    if segment == "" or segment:find("[^%a\128-\255']") or segment:sub(1, 1) == "'" or segment:sub(-1) == "'" then return nil end
    local cps = utf8Codepoints(segment); if not cps then return nil end
    for _, cp in ipairs(cps) do
      if cp < 32 or (cp >= 127 and cp <= 159) then return nil end
      local s = cp ~= 39 and scriptOf(cp) or nil
      if cp ~= 39 and not s then return nil end
      if s and script and s ~= script then return nil end
      script = s or script
    end
  end
  local segments = 0
  for _ in raw:gmatch("[^ ]+") do segments = segments + 1 end
  if segments < 1 or segments > 2 then return nil end
  return raw
end
Hunters.CanonicalName = canonicalName

local function parseRulesetValue(value, depth)
  if value == nil or (depth or 0) > 2 then return nil end
  if type(value) == "table" then
    for _, key in ipairs({ "ruleset", "ruleSet", "rulesetName", "ruleSetName", "gameMode", "gameModeName", "realmType", "type", "category", "name" }) do
      local found = parseRulesetValue(value[key], (depth or 0) + 1)
      if found then return found end
    end
    return nil
  end
  local word = tostring(value):lower():gsub("[^%a%d]", "")
  if word:find("hardcore", 1, true) or word == "hc" then return "hardcore" end
  local rp = word:find("roleplay", 1, true) or word == "rp" or word:find("rppvp", 1, true)
  local pvp = word:find("pvp", 1, true)
  if rp and pvp then return "rppvp" end
  if rp then return "rp" end
  if pvp then return "pvp" end
  if word:find("normal", 1, true) or word:find("pve", 1, true) then return "standard" end
end

local function detectRuleset()
  local hardcoreAPI = C_GameRules and C_GameRules.IsHardcoreActive
  if type(hardcoreAPI) == "function" and plain(try(hardcoreAPI)) == true then return "hardcore" end

  local realmProbes = {}
  if type(GetNormalizedRealmName) == "function" then realmProbes[#realmProbes + 1] = GetNormalizedRealmName end
  if type(GetRealmName) == "function" then realmProbes[#realmProbes + 1] = GetRealmName end
  for _, fn in ipairs(realmProbes) do
    local label = plain(try(fn))
    if type(label) == "string" then
      local suffix = label:lower():gsub("[^%a%d]", ""):match("realm%d+(%a*)$")
      if suffix ~= nil then return suffix == "" and "standard" or (parseRulesetValue(suffix) or suffix) end
    end
  end

  local probes = {}
  if type(GetRealmRuleset) == "function" then probes[#probes + 1] = GetRealmRuleset end
  if type(GetCurrentRealmRuleset) == "function" then probes[#probes + 1] = GetCurrentRealmRuleset end
  if C_RealmInfo and type(C_RealmInfo.GetCurrentRealmInfo) == "function" then probes[#probes + 1] = C_RealmInfo.GetCurrentRealmInfo end
  if C_RealmList and type(C_RealmList.GetCurrentRealmInfo) == "function" then probes[#probes + 1] = C_RealmList.GetCurrentRealmInfo end
  for _, fn in ipairs(probes) do
    local found = parseRulesetValue(plain(try(fn)))
    if found then return found end
  end
  for _, fn in ipairs(realmProbes) do
    local found = parseRulesetValue(plain(try(fn)))
    if found then return found end
  end

  -- Some clients may grow explicit ruleset enum keys. Probe only keys that really exist; the
  -- current 1.60.1 enum does not expose the three speculative keys older mocks invented.
  local rules, api = Enum and Enum.GameRule, C_GameRules and C_GameRules.IsGameRuleActive
  if type(api) == "function" and type(rules) == "table"
     and (rules.HardcoreRuleset ~= nil or rules.RPRuleset ~= nil or rules.PvPRuleset ~= nil) then
    local function active(rule)
      if rule == nil then return nil end
      local value = plain(try(api, rule))
      if value == nil then return nil end
      return value == true
    end
    local hc, rp, pvp = active(rules.HardcoreRuleset), active(rules.RPRuleset), active(rules.PvPRuleset)
    if hc then return "hardcore" end
    if rp and pvp then return "rppvp" end
    if rp then return "rp" end
    if pvp then return "pvp" end
    if hc == false and rp == false and pvp == false then return "standard" end
  end
end

local REGIONS = { [1]="us", [2]="kr", [3]="eu", [4]="tw", [5]="cn" }
local function validProtocolScope(scope)
  return type(scope) == "string" and #scope <= 24 and scope:match("^[a-z0-9]+/[a-z0-9]+$") ~= nil
end

local function protocolScope(id)
  if type(id) ~= "string" then return nil end
  local region, ruleset = id:match("^([^/]+)/[^/]+/([^/]+)$")
  local scope = region and (region .. "/" .. ruleset) or nil
  return validProtocolScope(scope) and scope or nil
end

local function detectScope()
  local region = type(GetCurrentRegionName) == "function" and plain(try(GetCurrentRegionName)) or nil
  if type(region) ~= "string" or region == "" then
    local id = type(GetCurrentRegion) == "function" and tonumber(plain(try(GetCurrentRegion))) or nil
    region = id and REGIONS[id] or nil
  end
  region = type(region) == "string" and region:lower():match("^%s*([a-z0-9]+)%s*$") or nil
  local faction = type(UnitFactionGroup) == "function" and plain(try(UnitFactionGroup, "player")) or nil
  if faction ~= "Alliance" and faction ~= "Horde" then faction = nil end
  local ruleset = detectRuleset()
  if not region then return nil, "Slayers disabled: region could not be determined." end
  if not faction then return nil, "Slayers disabled: faction could not be determined." end
  if not ruleset then return nil, "Slayers disabled: ruleset could not be determined." end
  local id = region .. "/" .. faction:lower() .. "/" .. ruleset
  if not protocolScope(id) then return nil, "Slayers disabled: region/ruleset scope is invalid." end
  runtime.faction = faction
  return id
end
Hunters.DetectScope = detectScope

local function root()
  if type(GodslayerDB) ~= "table" then return nil end
  GodslayerDB.hunters = type(GodslayerDB.hunters) == "table" and GodslayerDB.hunters or {}
  local h = GodslayerDB.hunters
  h.version = 2
  if h.enabled == nil then h.enabled = true end
  h.feed = type(h.feed) == "table" and h.feed or {}
  if h.feed.mode ~= "off" and h.feed.mode ~= "top10" and h.feed.mode ~= "everyone" then h.feed.mode = "everyone" end
  if h.feed.voice == nil then h.feed.voice = false end
  if h.feed.banner == nil then h.feed.banner = false end
  h.scopes = type(h.scopes) == "table" and h.scopes or {}
  if not runtime.cleanedSavedHeaps then
    local at = serverNow()
    for _, scope in pairs(h.scopes) do
      if type(scope) == "table" then
        scope.routes = nil
        scope.expiry, scope.rowExpiry, scope.candidateExpiry, scope.routeExpiry = nil, nil, nil, nil
        if type(scope.meta) == "table" then scope.meta.routeCount = nil end
        if type(scope.partners) == "table" then
          for key, partner in pairs(scope.partners) do
            if type(partner) ~= "table" or at - (tonumber(partner.heard) or 0) > PARTNER_TTL then
              scope.partners[key] = nil
            end
          end
        end
      end
    end
    runtime.cleanedSavedHeaps = true
  end
  return h
end

local function countTable(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

local touch, heapPush, rebuildHeaps

local function ensureScope()
  local h = root()
  if not h then return nil end
  local id, why = detectScope()
  runtime.scopeID, runtime.wireScope, runtime.disabledReason = id, protocolScope(id), why
  if not id then runtime.scope = nil; return nil end
  local s = h.scopes[id]
  if type(s) ~= "table" then s = {}; h.scopes[id] = s end
  for _, key in ipairs({ "rows", "candidates", "partners", "pending", "completedNonces", "meta" }) do
    s[key] = type(s[key]) == "table" and s[key] or {}
  end
  s.routes = nil
  -- Heaps are derived indexes, never durable data. Remove arrays written by the phase-2 snapshot.
  s.expiry, s.rowExpiry, s.candidateExpiry, s.routeExpiry = nil, nil, nil, nil
  local m = s.meta
  m.rowCount = countTable(s.rows)
  m.candidateCount = countTable(s.candidates)
  m.routeCount = nil
  m.pendingCount = countTable(s.pending)
  m.completedCount = countTable(s.completedNonces)
  local newRuntimeScope = runtime.scope ~= s or type(runtime.heaps) ~= "table"
  runtime.scope = s
  m.sentMinute = type(m.sentMinute) == "table" and m.sentMinute or {}
  m.sentBurst = type(m.sentBurst) == "table" and m.sentBurst or {}
  m.responseMinute = type(m.responseMinute) == "table" and m.responseMinute or {}
  m.introMinute = type(m.introMinute) == "table" and m.introMinute or {}
  m.snapshotMinute = type(m.snapshotMinute) == "table" and m.snapshotMinute or {}
  m.nonResponseMinute = type(m.nonResponseMinute) == "table" and m.nonResponseMinute or {}
  m.nonResponseBurst = type(m.nonResponseBurst) == "table" and m.nonResponseBurst or {}
  runtime.sentMinute, runtime.sentBurst = m.sentMinute, m.sentBurst
  runtime.responseMinute, runtime.introMinute = m.responseMinute, m.introMinute
  runtime.snapshotMinute, runtime.nonResponseMinute, runtime.nonResponseBurst = m.snapshotMinute, m.nonResponseMinute, m.nonResponseBurst
  runtime.lastSend = tonumber(m.lastSend) or -1e9
  local at = serverNow()
  for key, partner in pairs(s.partners) do
    if type(partner) ~= "table" or at - (tonumber(partner.heard) or 0) > PARTNER_TTL then
      s.partners[key] = nil
    end
  end
  if newRuntimeScope then rebuildHeaps(s, at) end
  return s
end

local function rowKey(name)
  local canon = canonicalName(name)
  return runtime.scopeID and canon and (runtime.scopeID .. "\031" .. lowercaseName(canon)) or nil
end
Hunters.RowKey = rowKey

local function heapLess(a, b)
  if a.x ~= b.x then return a.x < b.x end
  if a.k ~= b.k then return a.k < b.k end
  return tostring(a.id) < tostring(b.id)
end
heapPush = function(heap, value)
  local i = #heap + 1; heap[i] = value
  while i > 1 do
    local p = math.floor(i / 2)
    if not heapLess(value, heap[p]) then break end
    heap[i], heap[p], i = heap[p], value, p
  end
end
local function heapPop(heap)
  local first, last = heap[1], heap[#heap]
  heap[#heap] = nil
  if #heap > 0 then
    heap[1] = last
    local i = 1
    while true do
      local a, b = i * 2, i * 2 + 1
      if a > #heap then break end
      local child = b <= #heap and heapLess(heap[b], heap[a]) and b or a
      if not heapLess(heap[child], heap[i]) then break end
      heap[i], heap[child], i = heap[child], heap[i], child
    end
  end
  return first
end

local function defaultExpiry(kind, row, at)
  if kind == "row" then return (tonumber(row.confirmed) or at) + ROW_TTL end
  if kind == "candidate" then return (tonumber(row.t) or at) + CANDIDATE_TTL end
  if kind == "pending" then return at + PENDING_TTL end
  return at + NONCE_TTL
end

local function heapMap(s, kind)
  return kind == "row" and s.rows or kind == "candidate" and s.candidates
    or kind == "pending" and s.pending or s.completedNonces
end

local function heapName(kind)
  return kind == "row" and "rowExpiry" or kind == "candidate" and "candidateExpiry"
    or nil
end

local function rebuildHeap(name)
  local s, heaps, at = runtime.scope, runtime.heaps, serverNow()
  if not (s and heaps) then return end
  local fresh = {}
  local function add(kind)
    for key, row in pairs(heapMap(s, kind)) do
      row.rev = math.max(0, math.floor(tonumber(row.rev) or 0))
      row.expires = tonumber(row.expires) or defaultExpiry(kind, row, at)
      heapPush(fresh, { x=row.expires, k=kind, id=key, r=row.rev })
    end
  end
  if name == "expiry" then
    add("row"); add("candidate"); add("pending"); add("nonce")
  elseif name == "rowExpiry" then add("row")
  elseif name == "candidateExpiry" then add("candidate") end
  heaps[name] = fresh
end

rebuildHeaps = function(s, at)
  runtime.heaps = { expiry={}, rowExpiry={}, candidateExpiry={} }
  rebuildHeap("expiry")
  rebuildHeap("rowExpiry")
  rebuildHeap("candidateExpiry")
end

local function heapLive(name)
  local s = runtime.scope
  if name == "rowExpiry" then return s.meta.rowCount or 0 end
  if name == "candidateExpiry" then return s.meta.candidateCount or 0 end
  return (s.meta.rowCount or 0) + (s.meta.candidateCount or 0)
    + (s.meta.pendingCount or 0) + (s.meta.completedCount or 0)
end

local function compactHeapIfNeeded(name)
  local heap = runtime.heaps and runtime.heaps[name]
  if heap and #heap > 2 * heapLive(name) + 64 then rebuildHeap(name) end
end

touch = function(kind, key, record, expires)
  local s = runtime.scope
  if not s then return end
  record.rev = (tonumber(record.rev) or 0) + 1
  record.expires = expires
  local entry = { x = expires, k = kind, id = key, r = record.rev }
  local heaps = runtime.heaps
  if not heaps then rebuildHeaps(s, serverNow()); heaps = runtime.heaps end
  heapPush(heaps.expiry, entry)
  local name = heapName(kind)
  if name then heapPush(heaps[name], { x=entry.x, k=entry.k, id=entry.id, r=entry.r }) end
  compactHeapIfNeeded("expiry")
  if name then compactHeapIfNeeded(name) end
end

local function markBoard(key)
  runtime.boardRevision = runtime.boardRevision + 1
  for _, build in pairs(runtime.board) do
    if build.building then build.journal[key or "*"] = true end
    build.dirty = true
  end
  if ns.OnHuntersChanged then pcall(ns.OnHuntersChanged) end
end

local function removeRecord(kind, key)
  local s = runtime.scope; if not s then return end
  local map, counter
  if kind == "row" then map, counter = s.rows, "rowCount"
  elseif kind == "candidate" then map, counter = s.candidates, "candidateCount"
  elseif kind == "pending" then map, counter = s.pending, "pendingCount"
  elseif kind == "nonce" then map, counter = s.completedNonces, "completedCount" end
  if map and map[key] then
    map[key] = nil
    s.meta[counter] = math.max(0, (tonumber(s.meta[counter]) or 1) - 1)
    if kind == "row" then
      runtime.notifiedRows[key] = nil
      runtime.newsBase[key] = nil
      runtime.feedLast = runtime.feedLast or {}
      runtime.feedLast[key], runtime.feedPending[key] = nil, nil
      markBoard(key)
    end
  end
end

local function evictFromHeap(kind, exclude)
  local s = runtime.scope
  if not s then return false end
  local name = heapName(kind) or "expiry"
  local heap = runtime.heaps and runtime.heaps[name]
  if not heap then return false end
  for _ = 1, 64 do
    local e = heapPop(heap)
    if not e then break end
    if e.k == kind then
      local map = kind == "row" and s.rows or kind == "candidate" and s.candidates
        or kind == "pending" and s.pending or kind == "nonce" and s.completedNonces
      local rec = map[e.id]
      if rec and rec.rev == e.r and e.id ~= exclude then
        removeRecord(kind, e.id)
        return true
      end
    end
  end
  return false
end

local function trimWindow(list, seconds, at)
  local first = 1
  while list[first] and at - list[first] >= seconds do first = first + 1 end
  if first > 1 then
    local n = 1
    for i = first, #list do list[n], n = list[i], n + 1 end
    for i = n, #list do list[i] = nil end
  end
end

local function enabled()
  local h = root()
  return h and h.enabled == true and runtime.scope ~= nil
end

local function inInstance()
  if type(IsInInstance) ~= "function" then return false end
  return plain(try(IsInInstance)) == true
end

local function inCombat()
  return type(InCombatLockdown) == "function" and plain(try(InCombatLockdown)) == true
end

local function lockedDown()
  return C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown) == "function"
    and plain(try(C_ChatInfo.InChatMessagingLockdown)) == true
end

local function makeNonce()
  local meta = runtime.scope and runtime.scope.meta
  if not meta then return nil end
  meta.nonceSerial = (math.floor(tonumber(meta.nonceSerial) or 0) + 1) % 2821109907456 -- 36^8
  local text = base36(meta.nonceSerial)
  return ("00000000" .. text):sub(-8)
end

local function completeNonce(key)
  local s = runtime.scope; if not s then return end
  if not s.completedNonces[key] then
    if s.meta.completedCount >= NONCE_CAP then
      local oldestKey, oldest = nil, math.huge
      for nonce, row in pairs(s.completedNonces) do
        local expiry = tonumber(row.expires) or 0
        if expiry < oldest then oldestKey, oldest = nonce, expiry end
      end
      if oldestKey then removeRecord("nonce", oldestKey) end
    end
    if s.meta.completedCount >= NONCE_CAP then return end
    s.meta.completedCount = s.meta.completedCount + 1
  end
  local rec = s.completedNonces[key] or {}
  s.completedNonces[key] = rec
  touch("nonce", key, rec, serverNow() + NONCE_TTL)
end

local function addPending(kind, target, key, nonce)
  local s = runtime.scope
  if not s or s.meta.pendingCount >= PENDING_CAP then return nil end
  local rec = { kind = kind, target = target, key = key, at = serverNow() }
  s.pending[nonce], s.meta.pendingCount = rec, s.meta.pendingCount + 1
  touch("pending", nonce, rec, serverNow() + PENDING_TTL)
  return rec
end

local function candidateFailure(key)
  local s = runtime.scope; local c = s and s.candidates[key]
  if not c then return end
  c.fail = (tonumber(c.fail) or 0) + 1
  local at = serverNow()
  c.nextTry = at + BACKOFF[math.min(c.fail, #BACKOFF)]
  if c.fail >= 4 then
    -- The fourth miss retires the address immediately from discovery; its seven-day backoff is
    -- also the bounded retention period before maintenance physically evicts the record.
    c.retired = true
    touch("candidate", key, c, c.nextTry)
  else
    touch("candidate", key, c, at + CANDIDATE_TTL)
  end
end

local function finishPending(nonce, success)
  local s = runtime.scope; local p = s and s.pending[nonce]
  if not p then return end
  removeRecord("pending", nonce)
  completeNonce("out:" .. nonce)
  if success then
    local c = s.candidates[p.key]
    if c then
      local confirmed = tonumber(s.meta.rowCount) or 0
      local refresh = confirmed <= 20 and 1800 or (confirmed <= 100 and 7200 or 6 * 3600)
      c.fail, c.lastConfirmed, c.nextTry = 0, serverNow(), serverNow() + refresh
      touch("candidate", p.key, c, serverNow() + CANDIDATE_TTL)
    end
  elseif success == false and p.kind == "Q" then candidateFailure(p.key) end
end

local function queueCount(target)
  local n = 0
  local folded = lowercaseName(target)
  for _, item in ipairs(runtime.queue) do if lowercaseName(item.target) == folded then n = n + 1 end end
  return n
end

local function enqueue(priority, target, payload, kind, nonce, ttl, due, responseKey)
  local response = kind == "response"
  if not enabled() or not canonicalName(target) or (not response and queueCount(target) >= PER_TARGET_CAP) then return false end
  local q = runtime.queue
  if #q >= QUEUE_CAP then
    if not (response and #q < QUEUE_CAP + 8) then
      local worst
      for i, item in ipairs(q) do
        if item.p > priority and (not worst or item.p > q[worst].p or (item.p == q[worst].p and item.created < q[worst].created)) then worst = i end
      end
      if not worst then return false end
      local dropped = table.remove(q, worst)
      if dropped.nonce and (dropped.kind == "Q" or dropped.kind == "D") then finishPending(dropped.nonce, nil) end
      if dropped.responseKey and runtime.owedResponses then runtime.owedResponses[dropped.responseKey] = nil end
    end
  end
  q[#q + 1] = { p=priority, target=target, payload=payload, kind=kind, nonce=nonce,
    responseKey=responseKey, created=now(), ttl=ttl or 60, due=due or now() }
  return true
end

local function localWeekStart()
  if runtime.weekCache and serverNow() < runtime.weekCache + 604800 then return runtime.weekCache end
  local api = C_DateAndTime and C_DateAndTime.GetSecondsUntilWeeklyReset
  if type(api) ~= "function" then return nil end
  local untilReset = tonumber(plain(try(api)))
  if not untilReset or untilReset <= 0 or untilReset > 604800 then return nil end
  local start = serverNow() + untilReset - 604800
  start = math.floor(start / 60 + 0.5) * 60
  runtime.weekCache = start
  return start
end

local function ensureCharacter()
  local c = ns.char
  if type(c) ~= "table" then return nil end
  if not tonumber(c.hunterGen) then c.hunterGen, c.hunterSeq = serverNow(), 0 end
  c.hunterGen = math.max(0, math.floor(tonumber(c.hunterGen) or serverNow()))
  c.hunterSeq = math.max(0, math.floor(tonumber(c.hunterSeq) or 0))
  local week = localWeekStart()
  runtime.weekKnown = week ~= nil
  if week then
    if not tonumber(c.weekStart) then
      c.weekStart, c.wkKills, c.wkPoints, c.weekComplete = week, 0, 0, 0
    elseif week > c.weekStart then
      c.weekStart, c.wkKills, c.wkPoints, c.weekComplete = week, 0, 0, 1
      c.hunterSeq = c.hunterSeq + 1
    end
  end
  c.wkKills, c.wkPoints = math.max(0, math.floor(tonumber(c.wkKills) or 0)), math.max(0, math.floor(tonumber(c.wkPoints) or 0))
  c.weekComplete = c.weekComplete == 1 and 1 or 0
  if c.hunterClass and c.class and c.hunterClass ~= c.class then c.hunterSeq = c.hunterSeq + 1 end
  c.hunterClass = c.class
  return c
end

local function localTuple()
  local c = ensureCharacter(); if not c then return nil end
  return tostring(c.hunterGen) .. ":" .. tostring(c.hunterSeq)
end

local function nonnegativeInteger(value)
  return math.max(0, math.floor(tonumber(value) or 0))
end

local function ownStats()
  local c = ensureCharacter(); if not c then return nil end
  local kills = nonnegativeInteger(c.kills)
  local points = math.min(nonnegativeInteger(c.points), kills * 5)
  local kb = math.min(nonnegativeInteger(c.kb), kills)
  local orig = math.min(nonnegativeInteger(c.orig), kills)
  local kings = math.min(nonnegativeInteger(c.kings), orig)
  return {
    kills=kills, points=points, kb=kb, orig=orig, kings=kings,
    wkKills=math.min(nonnegativeInteger(c.wkKills), kills),
    wkPoints=math.min(nonnegativeInteger(c.wkPoints), points),
  }
end
Hunters.OwnStats = ownStats

local function ownFields()
  local c = ensureCharacter(); if not c or not CLASSES[c.class or ""] then return nil end
  local stats = ownStats(); if not stats then return nil end
  local rung = ns.Rank and tonumber(ns.Rank.Level and ns.Rank.Level()) or 0
  rung = rung and math.max(0, math.min(14, math.floor(rung))) or 0
  local week = runtime.weekKnown and tonumber(c.weekStart) or 0
  local complete = week > 0 and c.weekComplete or 0
  return {
    base36(c.hunterGen), base36(c.hunterSeq), base36(serverNow()), base36(week), base36(complete), c.class,
    base36(stats.kills), base36(stats.points), base36(stats.kb), base36(stats.orig), base36(stats.kings),
    base36(rung), base36(week > 0 and stats.wkKills or 0), base36(week > 0 and stats.wkPoints or 0), ns.VERSION,
  }
end

local function ownMessage(nonce)
  local fields = ownFields(); if not fields then return nil end
  local values = { "R", PROTO, nonce }
  for i = 1, #fields do values[#values + 1] = fields[i] end
  if not validProtocolScope(runtime.wireScope) then return nil end
  values[#values + 1] = runtime.wireScope
  local msg = table.concat(values, ";")
  return #msg <= MAX_PAYLOAD and msg or nil
end
Hunters.OwnMessage = ownMessage

local function rowMessage(fields, nonce)
  if not fields or not validProtocolScope(runtime.wireScope) then return nil end
  local values = { "R", PROTO, nonce }
  for i = 1, #fields do values[#values + 1] = fields[i] end
  values[#values + 1] = runtime.wireScope
  local msg = table.concat(values, ";")
  return #msg <= MAX_PAYLOAD and msg or nil
end

local function newsMessage(batch, frozenFields)
  local fields = frozenFields or batch.fields or ownFields()
  if not fields or not validProtocolScope(runtime.wireScope) then return nil end
  local victimName = canonicalName(batch.victimName) or ""
  local victimClass = CLASSES[batch.victimClass or ""] and batch.victimClass or ""
  local values = { "N", PROTO }
  for i = 1, #fields do values[#values + 1] = fields[i] end
  values[#values + 1] = runtime.wireScope
  values[#values + 1] = runtime.faction or ""
  values[#values + 1] = base36(batch.kills)
  values[#values + 1] = base36(batch.points)
  values[#values + 1] = victimName
  values[#values + 1] = victimClass
  local msg = table.concat(values, ";")
  return #msg <= MAX_PAYLOAD and msg or nil
end
Hunters.NewsMessage = newsMessage

local function currentPartner(key)
  local s, at = runtime.scope, serverNow()
  local p = s and s.partners[key]
  if type(p) == "table" and p.verified and at - (tonumber(p.heard) or 0) <= PARTNER_TTL then return p end
end

local function currentPartners()
  local rows, s = {}, runtime.scope
  for key, p in pairs(s and s.partners or {}) do
    if currentPartner(key) then rows[#rows + 1] = { key=key, row=p } end
  end
  table.sort(rows, function(a,b) if a.row.heard ~= b.row.heard then return a.row.heard > b.row.heard end return a.key < b.key end)
  return rows
end

local fanoutLatest
local reciprocalQuery

local function versionAtLeast(value, major, minor)
  local a, b = tostring(value or ""):match("^(%d+)%.(%d+)")
  a, b = tonumber(a), tonumber(b)
  return a and (a > major or (a == major and b >= minor)) or false
end

local function activeTargets()
  local s, chosen, partners, rest = runtime.scope, {}, {}, {}
  if not s then return partners, rest end
  local at = serverNow()
  for _, p in ipairs(currentPartners()) do
    local row = s.rows[p.key]
    if row and not chosen[p.key] then
      chosen[p.key] = true
      partners[#partners + 1] = { key=p.key, name=row.name, version=row.version, partner=true }
    end
  end
  for key, row in pairs(s.rows) do
    local present = runtime.directoryNames[lowercaseName(row.name)] == true
    local heard = row.confirmed and at - row.confirmed <= PARTNER_TTL
    if not chosen[key] and (present or heard) then
      rest[#rest + 1] = { key=key, name=row.name, version=row.version }
    end
  end
  table.sort(rest, function(a, b) return a.key < b.key end)
  return partners, rest
end

local function selectedTargets()
  local partners, rest = activeTargets()
  local eligible = {}
  for _, target in ipairs(rest) do
    if versionAtLeast(target.version, 3, 1) then eligible[#eligible + 1] = target end
  end
  return partners, eligible, #partners + #eligible
end

local function pruneNewsOffline()
  local map, wall = runtime.newsOffline, serverNow()
  if not map then return 0, nil end
  local count, oldestKey, oldest = 0, nil, math.huge
  for key, expires in pairs(map) do
    if expires <= wall then map[key] = nil
    else
      count = count + 1
      if expires < oldest then oldestKey, oldest = key, expires end
    end
  end
  return count, oldestKey
end

local function newsTargetAvailable(key)
  local map = runtime.newsOffline
  local untilAt = map and map[key]
  return not untilAt
end

local function addSnapshot(batch, target)
  if batch.selected[target.key] or batch.delivered[target.key] or not newsTargetAvailable(target.key)
     or (not batch.newsPayload and not currentPartner(target.key)) then return false end
  local pending = 0
  for _ in pairs(runtime.snapshots) do
    pending = pending + 1
    if pending >= 20 then return false end
  end
  local id = tostring(batch.serial) .. "\031" .. target.key
  batch.selected[target.key] = true
  runtime.snapshots[id] = { id=id, target=target.name, key=target.key, version=target.version,
    batch=batch, created=now(), due=now() }
  return true
end

local function carriedTarget(key)
  local s = runtime.scope
  local row = s and s.rows[key]
  if not row then return nil end
  if versionAtLeast(row.version, 3, 1) then
    return { key=key, name=row.name, version=row.version }
  end
  local partner = currentPartner(key)
  if partner then
    return { key=key, name=row.name, version=row.version, partner=true }
  end
end

local function selectBatchTargets(batch, initial)
  pruneNewsOffline()
  local partners, rest, total = selectedTargets()
  if initial then
    batch.limit = total <= 20 and 20 or (total <= 100 and 12 or 10)
  end
  local limit, selected = batch.limit or 0, 0
  for _ in pairs(batch.selected) do selected = selected + 1 end
  local function take(target)
    if selected < limit and addSnapshot(batch, target) then selected = selected + 1; return true end
    return false
  end
  local carried = {}
  for key in pairs(batch.carriedTargets or {}) do carried[#carried + 1] = key end
  table.sort(carried)
  for _, key in ipairs(carried) do
    local target = carriedTarget(key)
    -- A carried target replaces one pending item deleted from the older batch. It therefore keeps
    -- its place even when a smaller new fan-out limit would otherwise exclude it.
    if target and addSnapshot(batch, target) then selected = selected + 1 end
  end
  for _, target in ipairs(partners) do take(target) end
  if selected >= limit then return end
  if initial and total > 20 and #rest > 0 then
    local rotating = total <= 100 and 12 or 4
    local room = math.min(rotating, limit - selected)
    local cursor = math.floor(tonumber(runtime.scope.meta.fanoutCursor) or 0) % #rest
    local added = 0
    for i = 1, #rest do
      if added >= room then break end
      if take(rest[(cursor + i - 1) % #rest + 1]) then added = added + 1 end
    end
    -- Cursor movement belongs to finalization only, and counts selected rotating targets only.
    runtime.scope.meta.fanoutCursor = (cursor + added) % #rest
  elseif total <= 20 then
    -- Small boards select everyone. Above 20, later wakes add only partners and carried targets;
    -- the rotating set is frozen at finalization and only its selection moves the cursor.
    for _, target in ipairs(rest) do if selected >= limit then break end; take(target) end
  end
end

fanoutLatest = function()
  local batch = runtime.latestSnapshot
  if not batch or not enabled() then return end
  batch.delivered, batch.selected = batch.delivered or {}, batch.selected or {}
  selectBatchTargets(batch, false)
end

local function finalizeSnapshot(batch)
  if runtime.coalesce ~= batch then return end
  local fields = ownFields()
  local stats = ownStats()
  if not fields or not stats then
    if not batch.freezeRetry then
      local retryRevision = batch.quietRevision
      batch.freezeRetry = true
      C_Timer.After(NEWS_QUIET, function()
        if runtime.coalesce == batch then
          batch.freezeRetry = nil
          if batch.quietRevision == retryRevision then finalizeSnapshot(batch) end
        end
      end)
    end
    return
  end
  batch.freezeRetry = nil
  runtime.coalesce = nil
  batch.carriedTargets = {}
  local folded = {}
  for id, item in pairs(runtime.snapshots) do
    local older = item.batch
    if older ~= batch then
      runtime.snapshots[id] = nil
      batch.carriedTargets[item.key] = true
      -- A reset starts a new lifetime tuple. Its row supersedes the old queue, but old-generation
      -- kills cannot be represented as news against the reset totals.
      if older and older.news and older.fields and older.fields[1] == fields[1] and not folded[older] then
        folded[older] = true
        batch.news = true
        batch.kills = batch.kills + (tonumber(older.kills) or 0)
        local olderBase = tonumber(older.basePoints)
        if olderBase and (batch.basePoints == nil or olderBase < batch.basePoints) then
          batch.basePoints = olderBase
        end
      end
    end
  end
  local maxPoints = batch.kills * (ns.ORIGINAL_POINTS or 5)
  batch.points = batch.news and math.max(0, math.min(maxPoints, stats.points - (batch.basePoints or stats.points))) or 0
  runtime.snapshotSerial = (runtime.snapshotSerial or 0) + 1
  batch.serial, batch.fields = runtime.snapshotSerial, fields
  batch.tuple, batch.made, batch.delivered, batch.selected = fields[1] .. ":" .. fields[2], unbase36(fields[3]) or serverNow(), {}, {}
  batch.newsPayload = batch.news and batch.kills <= stats.kills and newsMessage(batch, fields) or nil
  assert(batch.newsPayload == nil or batch.kills <= stats.kills,
    "frozen Slayers news cannot exceed its row total")
  batch.rowPayload = rowMessage(fields, "0")
  runtime.latestSnapshot = batch
  selectBatchTargets(batch, true)
  -- Only finalization may use the carried-item exemption. Later partner notes and wakes must obey
  -- the frozen batch limit, even if a carried target becomes eligible again.
  batch.carriedTargets = nil
end

local function scheduleSnapshot(points, victim)
  if not enabled() then return end
  local batch = runtime.coalesce
  if not batch then
    batch = { opened=now(), kills=0, points=0, news=false }
    runtime.coalesce = batch
  end
  if points ~= nil then
    if not batch.firstKill then
      local stats = ownStats()
      batch.firstKill = now()
      batch.basePoints = math.max(0, (stats and stats.points or 0) - math.max(0, math.floor(tonumber(points) or 0)))
      C_Timer.After(NEWS_HARD, function() finalizeSnapshot(batch) end)
    end
    batch.news, batch.kills = true, batch.kills + 1
    if type(victim) == "table" then
      local victimName = canonicalName(victim.name)
      local folded = victimName and lowercaseName(victimName)
      if folded ~= "unknown" and folded ~= "unknown victim" then
        batch.victimName = victimName
        batch.victimClass = victimName and CLASSES[victim.class or ""] and victim.class or nil
      else
        batch.victimName, batch.victimClass = nil, nil
      end
    end
  end
  batch.quietRevision = (batch.quietRevision or 0) + 1
  local revision = batch.quietRevision
  C_Timer.After(NEWS_QUIET, function()
    if runtime.coalesce == batch and batch.quietRevision == revision then finalizeSnapshot(batch) end
  end)
end

local function schedulePush() scheduleSnapshot(nil) end

function Hunters.Score(points, victim)
  local c = ensureCharacter(); if not c then return end
  if runtime.weekKnown then
    c.wkKills, c.wkPoints = c.wkKills + 1, c.wkPoints + (tonumber(points) or 0)
    if type(victim) == "table" then
      if type(victim.wk) ~= "table" or victim.wk.start ~= c.weekStart then
        victim.wk = { start=c.weekStart, kills=0 }
      end
      victim.wk.kills = math.max(0, math.floor(tonumber(victim.wk.kills) or 0)) + 1
    end
  end
  c.hunterSeq = c.hunterSeq + 1
  scheduleSnapshot(points, victim); markBoard("self")
end

function Hunters.LocalChanged()
  local c = ensureCharacter(); if not c then return end
  c.hunterSeq = c.hunterSeq + 1
  schedulePush(); markBoard("self")
end

function Hunters.AdjustWeekly(points, kills)
  local c = ensureCharacter(); if not c then return end
  if runtime.weekKnown then
    c.wkKills = math.max(0, c.wkKills + (tonumber(kills) or 0))
    c.wkPoints = math.max(0, c.wkPoints + (tonumber(points) or 0))
  end
  c.hunterSeq = c.hunterSeq + 1
  schedulePush(); markBoard("self")
end

function Hunters.AfterReset(oldGeneration)
  local c = ns.char; if not c then return end
  c.hunterGen = math.max((tonumber(oldGeneration) or 0) + 1, serverNow())
  c.hunterSeq, c.wkKills, c.wkPoints, c.weekComplete, c.weekStart = 0, 0, 0, 0, localWeekStart()
  c.hunterClass = c.class
  runtime.weekKnown = c.weekStart ~= nil
  runtime.lastPushedTuple = nil
  schedulePush(); markBoard("self")
end

function Hunters.GuildTail()
  local f = ownFields(); if not f then return nil end
  -- schema, generation, sequence, made, week, completeness, weekly kills, weekly points
  return { "3", f[1], f[2], f[3], f[4], f[5], f[13], f[14] }
end

local function parseMessage(text)
  text = plain(text)
  if type(text) ~= "string" or #text > MAX_PAYLOAD then return nil end
  local f = split(text, ";")
  if f[2] ~= PROTO then return nil end
  local op = f[1]
  if op == "Q" then
    if #f ~= 4 or not f[3]:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$")
       or not validProtocolScope(f[4]) then return nil end
    return { op=op, nonce=f[3], scope=f[4] }
  elseif op == "D" then
    if #f ~= 3 or not f[3]:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$") then return nil end
    return { op=op, nonce=f[3] }
  elseif op == "I" then
    if #f ~= 4 or #text > MAX_INTRO or not f[3]:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$") then return nil end
    local names = split(f[4], "|")
    if #names < 1 or #names > 8 then return nil end
    local seen = {}
    for i, name in ipairs(names) do
      name = canonicalName(name)
      local folded = name and lowercaseName(name)
      if not name or seen[folded] then return nil end
      names[i], seen[folded] = name, true
    end
    return { op=op, nonce=f[3], names=names }
  elseif op == "R" then
    if #f ~= 19 or (f[3] ~= "0" and not f[3]:match("^[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z]$")) then return nil end
    local gen, seq = unbase36(f[4]), unbase36(f[5])
    local made, week, complete = unbase36(f[6]), unbase36(f[7]), unbase36(f[8], 1)
    local kills, points, kb = unbase36(f[10], 1e7), unbase36(f[11], 1e7), unbase36(f[12], 1e7)
    local orig, kings, rung = unbase36(f[13], 1e7), unbase36(f[14], 1e7), unbase36(f[15], 14)
    local wkKills, wkPoints = unbase36(f[16], 1e7), unbase36(f[17], 1e7)
    if not (gen and seq and made and week and complete and kills and points and kb and orig and kings and rung and wkKills and wkPoints) then return nil end
    if not CLASSES[f[9]] or made > serverNow() + 300 or kb > kills or orig > kills or kings > orig
       or points > kills * 5 or wkKills > kills or wkPoints > points
       or (week == 0 and (complete ~= 0 or wkKills ~= 0 or wkPoints ~= 0))
       or type(f[18]) ~= "string" or #f[18] > 12 or not f[18]:match("^[%w%.%-]+$")
       or not validProtocolScope(f[19]) then return nil end
    return { op=op, nonce=f[3], gen=gen, seq=seq, made=made, week=week, complete=complete,
      class=f[9], kills=kills, points=points, kb=kb, orig=orig, kings=kings, rung=rung,
      wkKills=wkKills, wkPoints=wkPoints, version=f[18], scope=f[19] }
  elseif op == "N" then
    if #f ~= 23 then return nil end
    local gen, seq = unbase36(f[3]), unbase36(f[4])
    local made, week, complete = unbase36(f[5]), unbase36(f[6]), unbase36(f[7], 1)
    local kills, points, kb = unbase36(f[9], 1e7), unbase36(f[10], 1e7), unbase36(f[11], 1e7)
    local orig, kings, rung = unbase36(f[12], 1e7), unbase36(f[13], 1e7), unbase36(f[14], 14)
    local wkKills, wkPoints = unbase36(f[15], 1e7), unbase36(f[16], 1e7)
    local batchKills, batchPoints = unbase36(f[20], 1e7), unbase36(f[21], 1e7)
    if not (gen and seq and made and week and complete and kills and points and kb and orig and kings
       and rung and wkKills and wkPoints and batchKills and batchPoints) then return nil end
    local victimName = f[22] ~= "" and canonicalName(f[22]) or nil
    local victimClass = f[23] ~= "" and f[23] or nil
    if not CLASSES[f[8]] or made > serverNow() + 300 or kb > kills or orig > kills or kings > orig
       or points > kills * 5 or wkKills > kills or wkPoints > points or batchKills < 1
       or batchKills > kills or batchPoints > batchKills * (ns.ORIGINAL_POINTS or 5)
       or (week == 0 and (complete ~= 0 or wkKills ~= 0 or wkPoints ~= 0))
       or type(f[17]) ~= "string" or #f[17] > 12 or not f[17]:match("^[%w%.%-]+$")
       or not validProtocolScope(f[18]) or (f[19] ~= "Horde" and f[19] ~= "Alliance")
       or (f[22] ~= "" and not victimName) or (victimClass and not CLASSES[victimClass]) then return nil end
    return { op=op, gen=gen, seq=seq, made=made, week=week, complete=complete, class=f[8],
      kills=kills, points=points, kb=kb, orig=orig, kings=kings, rung=rung, wkKills=wkKills,
      wkPoints=wkPoints, version=f[17], scope=f[18], faction=f[19], batchKills=batchKills,
      batchPoints=batchPoints, victimName=victimName, victimClass=victimClass }
  end
end
Hunters.Parse = parseMessage

local function fingerprint(r)
  return table.concat({ r.class, r.kills, r.points, r.kb, r.orig, r.kings, r.rung,
    r.week, r.complete, r.wkKills, r.wkPoints, r.version }, ":")
end

local function notePartner(key, name)
  local s, at = runtime.scope, serverNow()
  local p = s.partners[key]
  if not p then
    if countTable(s.partners) >= PARTNER_CAP then
      local oldestKey, oldest = nil, math.huge
      for k, row in pairs(s.partners) do if (row.heard or 0) < oldest then oldestKey, oldest = k, row.heard or 0 end end
      if oldestKey then s.partners[oldestKey] = nil end
    end
    p = {}; s.partners[key] = p
  end
  p.name, p.heard, p.verified = name, at, true
  if fanoutLatest then fanoutLatest() end
end

function Hunters.NoteCandidate(name, source, guid)
  if not runtime.scope then ensureScope() end
  local canon = canonicalName(name); if not canon then return false end
  local key, s = rowKey(canon), runtime.scope
  if not key or not s or key == rowKey(ns.myName) then return false end
  local c = s.candidates[key]
  if not c then
    if s.meta.candidateCount >= CANDIDATE_CAP and not evictFromHeap("candidate") then return false end
    c = {}; s.candidates[key], s.meta.candidateCount = c, s.meta.candidateCount + 1
  end
  local guidChanged = type(guid) == "string" and guid ~= "" and c.guid and c.guid ~= guid
  if guidChanged then
    if s.rows[key] then removeRecord("row", key) end
    -- The server has tied this spelling to a different character. It is a candidate again, not a
    -- verified peer, so an unsolicited owner push cannot recreate the stale row.
    s.partners[key] = nil
    c.nextTry, c.fail, c.lastConfirmed, c.retired, c.foreign = 0, 0, nil, nil, nil
  end
  if c.retired and source ~= "direct" then return false end
  if source == "direct" then c.fail, c.retired, c.foreign = 0, nil, nil end
  c.name, c.source, c.t = canon, source or c.source, serverNow()
  if type(guid) == "string" and guid ~= "" then c.guid = guid end
  touch("candidate", key, c, serverNow() + CANDIDATE_TTL)
  return true
end

local function mergeRow(key, name, incoming)
  local s, old = runtime.scope, runtime.scope.rows[key]
  local fp = fingerprint(incoming)
  if old then
    if incoming.gen < old.gen or (incoming.gen == old.gen and incoming.seq < old.seq) then return false end
    if incoming.gen == old.gen and incoming.seq == old.seq then
      if fp ~= old.fp then return false end
      old.confirmed, old.made = serverNow(), incoming.made
      touch("row", key, old, serverNow() + ROW_TTL)
      markBoard(key)
      return true
    end
    if incoming.gen == old.gen and (incoming.kills < old.kills or incoming.points < old.points or incoming.kb < old.kb
       or incoming.orig < old.orig or incoming.kings < old.kings) then return false end
  elseif s.meta.rowCount >= ROW_CAP and not evictFromHeap("row", rowKey(ns.myName)) then
    return false
  end
  local row = old or {}
  for k, v in pairs(incoming) do
    if k ~= "op" and k ~= "nonce" and k ~= "faction" and k ~= "batchKills" and k ~= "batchPoints"
       and k ~= "victimName" and k ~= "victimClass" then row[k] = v end
  end
  row.name, row.confirmed, row.fp = name, serverNow(), fp
  if not old then s.rows[key], s.meta.rowCount = row, s.meta.rowCount + 1 end
  touch("row", key, row, serverNow() + ROW_TTL)
  markBoard(key)
  if fanoutLatest then fanoutLatest() end
  return true
end
Hunters.MergeRow = mergeRow

local function inboundAllowed(senderKey)
  local at = now()
  trimWindow(runtime.inboundMinute, 60, at)
  if #runtime.inboundMinute >= 60 then return false end
  local list = runtime.inboundBySender[senderKey] or {}
  runtime.inboundBySender[senderKey] = list
  trimWindow(list, 60, at)
  if #list >= 12 then return false end
  list[#list + 1], runtime.inboundMinute[#runtime.inboundMinute + 1] = at, at
  return true
end

local function introductionPayload(nonce)
  local s, names, seen = runtime.scope, {}, {}
  local function add(name)
    local canon = canonicalName(name)
    local folded = canon and lowercaseName(canon)
    if #names >= 8 or not canon or rowKey(canon) == rowKey(ns.myName) or seen[folded] then return end
    local candidate = table.concat({ "I", PROTO, nonce, table.concat(names, "|") .. (#names > 0 and "|" or "") .. canon }, ";")
    if #candidate <= MAX_INTRO then names[#names + 1], seen[folded] = canon, true end
  end
  for _, p in ipairs(currentPartners()) do add(p.row.name) end
  for _, row in pairs(s.rows) do add(row.name); if #names >= 8 then break end end
  if #names == 0 then return nil end
  return table.concat({ "I", PROTO, nonce, table.concat(names, "|") }, ";")
end

local function noteExchange()
  if runtime.scope then runtime.scope.meta.lastExchange = serverNow() end
  if ns.OnHuntersChanged then pcall(ns.OnHuntersChanged) end
end

local function handleR(sender, key, message)
  local s, pending = runtime.scope, message.nonce ~= "0" and runtime.scope.pending[message.nonce] or nil
  if message.nonce == "0" then
    local p = s.partners[key]
    if not (p and p.verified and serverNow() - (tonumber(p.heard) or 0) <= PARTNER_TTL) then return end
  else
    if not pending or pending.kind ~= "Q" or pending.key ~= key or s.completedNonces["out:" .. message.nonce] then return end
  end
  local old = s.rows[key]
  local base
  if not runtime.newsBase[key] then
    if old then base = { gen=old.gen, kills=old.kills, points=old.points }
    else base = { gen=message.gen, kills=0, points=0 } end
  end
  if not mergeRow(key, sender, message) then return end
  if base then runtime.newsBase[key] = base end
  notePartner(key, sender); Hunters.NoteCandidate(sender, "direct")
  if message.nonce ~= "0" then finishPending(message.nonce, true) end
  noteExchange()
end

local function rowRank(key)
  local s, wanted = runtime.scope, runtime.scope and runtime.scope.rows[key]
  if not wanted then return nil end
  local rank = 1
  local function ahead(row, name)
    if row.points ~= wanted.points then return row.points > wanted.points end
    if row.kills ~= wanted.kills then return row.kills > wanted.kills end
    return lowercaseName(name) < lowercaseName(wanted.name)
  end
  for otherKey, row in pairs(s.rows) do
    if otherKey ~= key and ahead(row, row.name) then rank = rank + 1 end
  end
  local stats = ownStats()
  if stats and ahead(stats, ns.myName or "") then rank = rank + 1 end
  return rank
end

local function pruneGuildNews()
  local at = now()
  for id, rec in pairs(runtime.guildNews) do if at - rec.at > 120 then runtime.guildNews[id] = nil end end
end

local function pruneFeedLast()
  local map, at = runtime.feedLast or {}, now()
  runtime.feedLast = map
  local count, oldestKey, oldest = 0, nil, math.huge
  for key, when in pairs(map) do
    if at - when >= 30 then map[key] = nil
    else
      count = count + 1
      if when < oldest then oldestKey, oldest = key, when end
    end
  end
  while count > FEED_LAST_CAP and oldestKey do
    map[oldestKey], count, oldestKey, oldest = nil, count - 1, nil, math.huge
    for key, when in pairs(map) do if when < oldest then oldestKey, oldest = key, when end end
  end
end

local function guildNewsKey(name, kills)
  local canon = canonicalName(name)
  return canon and (lowercaseName(canon) .. "\031" .. tostring(math.floor(tonumber(kills) or -1))) or nil
end

function Hunters.GuildDuplicate(name, kills)
  pruneGuildNews()
  local id = guildNewsKey(name, kills); if not id then return false end
  return runtime.guildNews[id] ~= nil
end

function Hunters.MarkPresented(name, kills, source)
  pruneGuildNews()
  local id = guildNewsKey(name, kills); if not id then return false end
  runtime.guildNews[id] = { at=now(), source=source }
  return true
end

local function classLabel(token)
  token = tostring(token or "")
  return token:sub(1, 1) .. token:sub(2):lower()
end

local function feedLine(event)
  local victim
  if event.kills == 1 and event.victimName and event.victimClass then
    victim = " took down " .. event.victimName .. " (" .. classLabel(event.victimClass) .. ")"
  elseif event.kills == 1 then
    victim = " scored a kill"
  else
    victim = " took down " .. tostring(event.kills) .. " players"
  end
  local rank = event.rank and (", #" .. event.rank .. " on Slayers") or ""
  return ("%s (%s)%s, +%d. %d kills%s."):format(event.sender, classLabel(event.class), victim,
    event.points, event.totalKills, rank)
end

local function showFeed(event)
  local h = root(); local feed = h and h.feed
  if not feed or feed.mode == "off" or (feed.mode == "top10" and (not event.rank or event.rank > 10)) then return false end
  local at = now()
  trimWindow(runtime.feedMinute, 60, at)
  if #runtime.feedMinute >= 6 then
    runtime.feedSummary = (runtime.feedSummary or 0) + 1
    if not runtime.feedSummaryScheduled then
      runtime.feedSummaryScheduled = true
      C_Timer.After(60, function()
        runtime.feedSummaryScheduled = nil
        local n = runtime.feedSummary or 0; runtime.feedSummary = 0
        local current = root()
        if n > 0 and current and current.feed and current.feed.mode ~= "off" then
          ns.Print(("%d more Slayers scored in the last minute."):format(n))
        end
      end)
    end
    return false
  end
  runtime.feedMinute[#runtime.feedMinute + 1] = at
  runtime.feedLast = runtime.feedLast or {}
  runtime.feedLast[event.key] = at
  pruneFeedLast()
  ns.Print(feedLine(event))
  Hunters.MarkPresented(event.sender, event.totalKills, "news")
  if feed.banner and ns.Stage and ns.Stage.Banner then
    pcall(ns.Stage.Banner, "SLAYERS", { 1, 0.82, 0 }, feedLine(event), { size=1, hold=1.8 })
  end
  if feed.voice and event.topEntry and at - (runtime.feedVoiceAt or -1e9) >= 45
     and ns.Hype and ns.Hype.SlayerVoice then
    local ok, played = pcall(ns.Hype.SlayerVoice)
    if ok and played then runtime.feedVoiceAt = at end
  end
  return true
end

local function notifyNews(sender, key, message, rank, topEntry)
  local event = { sender=sender, key=key, class=message.class, kills=message.batchKills,
    points=message.batchPoints, totalKills=message.kills, victimName=message.victimName,
    victimClass=message.victimClass, rank=rank, topEntry=topEntry }
  runtime.feedLast = runtime.feedLast or {}
  pruneFeedLast()
  local last = runtime.feedLast[key]
  if last and now() - last < 30 then
    local pending = runtime.feedPending[key]
    if pending then
      pending.kills, pending.points = pending.kills + event.kills, pending.points + event.points
      pending.totalKills, pending.class, pending.rank = event.totalKills, event.class, event.rank
      pending.victimName, pending.victimClass = event.victimName, event.victimClass
      pending.topEntry = pending.topEntry or topEntry
    else
      runtime.feedPending[key] = event
      C_Timer.After(math.max(0.1, 30 - (now() - last)), function()
        local ready = runtime.feedPending[key]
        runtime.feedPending[key] = nil
        if ready and not Hunters.GuildDuplicate(ready.sender, ready.totalKills) then
          ready.rank = rowRank(key); showFeed(ready)
        end
      end)
    end
    return true
  end
  return showFeed(event)
end

local function handleN(sender, key, message)
  local s, old = runtime.scope, runtime.scope.rows[key]
  if message.scope ~= runtime.wireScope or message.faction ~= runtime.faction then return end
  if not old then
    Hunters.NoteCandidate(sender, "inbound")
    reciprocalQuery(sender)
    return
  end
  local dedupe = "news:" .. key .. ":" .. tostring(message.gen) .. ":" .. tostring(message.seq)
  local notification = tostring(message.gen) .. ":" .. tostring(message.seq)
  if s.completedNonces[dedupe] then return end
  if message.gen < old.gen or (message.gen == old.gen and message.seq < old.seq) then return end
  local base = runtime.newsBase[key] or { gen=old.gen, kills=old.kills, points=old.points }
  local shownKills, shownPoints = message.batchKills, message.batchPoints
  if message.gen == base.gen then
    if message.kills < old.kills or message.points < old.points then return end
    shownKills = math.min(shownKills, message.kills - base.kills)
    shownPoints = math.min(shownPoints, message.points - base.points,
      shownKills * (ns.ORIGINAL_POINTS or 5))
  end
  local before = rowRank(key)
  if not mergeRow(key, sender, message) then return end
  completeNonce(dedupe)
  notePartner(key, sender); Hunters.NoteCandidate(sender, "direct"); noteExchange()
  runtime.newsBase[key] = { gen=message.gen, kills=message.kills, points=message.points }
  if shownKills <= 0 or serverNow() - message.made > NEWS_FRESH then return end
  if runtime.notifiedRows[key] == notification then return end
  message.batchKills, message.batchPoints = shownKills, shownPoints
  pruneGuildNews()
  local duplicate = guildNewsKey(sender, message.kills)
  if duplicate and runtime.guildNews[duplicate] then runtime.notifiedRows[key] = notification; return end
  local rank = rowRank(key)
  local topEntry = (rank == 1 and before ~= 1) or (rank and rank <= 3 and (not before or before > 3))
  if notifyNews(sender, key, message, rank, topEntry) then runtime.notifiedRows[key] = notification end
end

local function retireForeignResponse(key, message)
  if message.nonce == "0" then return end
  local s, pending = runtime.scope, runtime.scope.pending[message.nonce]
  if not pending or pending.kind ~= "Q" or pending.key ~= key
     or s.completedNonces["out:" .. message.nonce] then return end
  removeRecord("pending", message.nonce)
  completeNonce("out:" .. message.nonce)
  local candidate = s.candidates[key]
  if candidate then
    local at = serverNow()
    candidate.retired, candidate.foreign, candidate.nextTry, candidate.t = true, true, nil, at
    touch("candidate", key, candidate, at + CANDIDATE_TTL)
  end
end

local function handleI(sender, key, message)
  local s, pending = runtime.scope, runtime.scope.pending[message.nonce]
  local partner = s.partners[key]
  if not partner or not partner.verified or not pending or pending.kind ~= "D" or pending.key ~= key
     or s.completedNonces["out:" .. message.nonce] then return end
  for _, name in ipairs(message.names) do Hunters.NoteCandidate(name, "introduction") end
  finishPending(message.nonce, true)
  noteExchange()
end

local function scheduleResponse(sender, message)
  local s, key = runtime.scope, rowKey(sender)
  local dedupe = "in:" .. key .. ":" .. message.nonce
  local outstanding = runtime.responseScheduled
  for _, item in ipairs(runtime.queue) do if item.kind == "response" then outstanding = outstanding + 1 end end
  runtime.owedResponses = runtime.owedResponses or {}
  if s.completedNonces[dedupe] or runtime.owedResponses[dedupe] or outstanding >= 8 then return end
  local owed = { accepted=now() }
  runtime.owedResponses[dedupe] = owed
  runtime.responseScheduled = runtime.responseScheduled + 1
  C_Timer.After(0.5 + math.random() * 2, function()
    runtime.responseScheduled = math.max(0, runtime.responseScheduled - 1)
    if runtime.owedResponses[dedupe] ~= owed then return end
    if not enabled() then runtime.owedResponses[dedupe] = nil; return end
    local payload = ownMessage(message.nonce)
    if payload and enqueue(1, sender, payload, "response", nil, 60, nil, dedupe) then
      owed.due = now()
    else
      runtime.owedResponses[dedupe] = nil
    end
  end)
end

local function queryCandidate(name)
  local key, s = rowKey(name), runtime.scope
  local c = key and s and s.candidates[key]
  local at = serverNow()
  if not c or c.retired or (c.nextTry and c.nextTry > at) then return false end
  for _, pending in pairs(s.pending) do if pending.kind == "Q" and pending.key == key then return false end end
  local nonce = makeNonce()
  if not nonce or not addPending("Q", c.name, key, nonce) then return false end
  c.lastQuery, c.nextTry = at, at + PENDING_TTL + 1
  touch("candidate", key, c, at + CANDIDATE_TTL)
  local payload = runtime.wireScope and ("Q;" .. PROTO .. ";" .. nonce .. ";" .. runtime.wireScope) or nil
  if not payload or not enqueue(3, c.name, payload, "Q", nonce, 60) then
    finishPending(nonce, nil)
    return false
  end
  return true
end

reciprocalQuery = function(name)
  C_Timer.After(2 + math.random() * 3, function()
    if enabled() and not inCombat() and not inInstance() then queryCandidate(name) end
  end)
end

local function handleD(sender, key, message)
  local s, p = runtime.scope, runtime.scope.partners[key]
  if not (p and p.verified and serverNow() - (tonumber(p.heard) or 0) <= PARTNER_TTL) then return end
  local at = rateNow()
  p.introReplies = p.introReplies or {}
  trimWindow(p.introReplies, 600, at)
  trimWindow(runtime.introMinute, 60, at)
  if #p.introReplies >= 1 or #runtime.introMinute >= 4 then return end
  local dedupe = "in:" .. key .. ":" .. message.nonce
  if s.completedNonces[dedupe] then return end
  local payload = introductionPayload(message.nonce)
  if not payload then return end
  completeNonce(dedupe)
  p.introReplies[#p.introReplies + 1], runtime.introMinute[#runtime.introMinute + 1] = at, at
  enqueue(4, sender, payload, "introduction-response", nil, 60)
end

function Hunters.handlers.CHAT_MSG_ADDON(prefix, text, channel, sender)
  prefix, channel, sender = plain(prefix), plain(channel), plain(sender)
  if prefix ~= PREFIX or channel ~= "WHISPER" or not enabled() then return end
  local canon = canonicalName(sender)
  if not canon then return end
  local key = rowKey(canon); if not key then return end
  if key == rowKey(ns.myName) then return end
  -- Once the global sixty-message window is full, do not even split attacker-controlled input.
  trimWindow(runtime.inboundMinute, 60, now())
  if #runtime.inboundMinute >= 60 then return end
  local message = parseMessage(text)
  if not message or not inboundAllowed(key) then return end
  if message.op == "R" then
    if message.scope ~= runtime.wireScope then retireForeignResponse(key, message); return end
    handleR(canon, key, message)
  elseif message.op == "N" then handleN(canon, key, message)
  elseif message.op == "I" then handleI(canon, key, message)
  elseif message.op == "Q" then
    if message.scope == runtime.wireScope then
      Hunters.NoteCandidate(canon, "inbound")
      scheduleResponse(canon, message)
      reciprocalQuery(canon)
    end
  elseif message.op == "D" then handleD(canon, key, message) end
end

local function pruneOfflineTargets(at)
  local order, targets = runtime.offlineOrder, runtime.offlineTargets
  local first = 1
  while order[first] do
    local item, rec = order[first], targets[order[first].key]
    if rec and rec.at == item.at and at - rec.at <= 120 then break end
    if rec and rec.at == item.at then targets[item.key] = nil end
    first = first + 1
  end
  if first > 1 then
    local n = 1
    for i = first, #order do order[n], n = order[i], n + 1 end
    for i = n, #order do order[i] = nil end
  end
end

local function rememberWhisper(target, kind)
  local canon = canonicalName(target); if not canon then return end
  local at, key = now(), lowercaseName(canon)
  pruneOfflineTargets(at)
  -- Every attempt gets a fresh correlation record. A prior Q result cannot consume the later news
  -- result for the same exact name.
  local rec = { signaled=false }
  runtime.offlineTargets[key] = rec
  rec.target, rec.at, rec.kind = canon, at, kind
  -- First names repeat on Forever. Only exact full-name spellings may correlate an offline line.
  local hyphen = (canon:gsub(" ", "-", 1))
  rec.aliases = { canon, hyphen }
  for _, fn in ipairs({ GetRealmName, GetNormalizedRealmName }) do
    if type(fn) == "function" then
      local realm = plain(try(fn))
      if type(realm) == "string" and realm ~= "" then
        rec.aliases[#rec.aliases + 1] = canon .. "-" .. realm
        rec.aliases[#rec.aliases + 1] = hyphen .. "-" .. realm
      end
    end
  end
  runtime.offlineOrder[#runtime.offlineOrder + 1] = { key=key, at=at }
  while countTable(runtime.offlineTargets) > 64 do
    local oldest = table.remove(runtime.offlineOrder, 1)
    if not oldest then break end
    local old = runtime.offlineTargets[oldest.key]
    if old and old.at == oldest.at then runtime.offlineTargets[oldest.key] = nil end
  end
  return rec
end

local function offlineLineFor(text, rec)
  text = plain(text)
  if type(text) ~= "string" then return false end
  local formatText = plain(_G and _G.ERR_CHAT_PLAYER_NOT_FOUND_S)
  local lower = text:lower()
  for _, alias in ipairs(rec.aliases or {}) do
    if type(formatText) == "string" then
      local ok, localized = pcall(string.format, formatText, alias)
      if ok and text == localized then return true end
    end
    local quoted = lower:find("'" .. alias:lower() .. "'", 1, true)
      or lower:find('"' .. alias:lower() .. '"', 1, true)
    if quoted and lower:find("no player named", 1, true) and lower:find("currently playing", 1, true) then return true end
  end
  return false
end

local function signalOffline(rec)
  local sending = runtime.sending
  if sending and lowercaseName(sending.target) == lowercaseName(rec.target) then sending.offline = true end
  if rec.signaled then return end
  rec.signaled = true
  local s, key = runtime.scope, rowKey(rec.target)
  if not (s and key) then return end
  if rec.kind == "Q" then
    for nonce, pending in pairs(s.pending) do
      if pending.kind == "Q" and pending.key == key then
        removeRecord("pending", nonce)
        completeNonce("out:" .. nonce)
      end
    end
    candidateFailure(key)
  else
    runtime.newsOffline = runtime.newsOffline or {}
    local count, oldestKey = pruneNewsOffline()
    if count >= NEWS_OFFLINE_CAP and oldestKey then runtime.newsOffline[oldestKey] = nil end
    runtime.newsOffline[key] = serverNow() + OFFLINE_COOLDOWN
    for id, item in pairs(runtime.snapshots) do if item.key == key then runtime.snapshots[id] = nil end end
  end
end

local function matchOfflineLine(text)
  if inInstance() then return false end
  local at = now(); pruneOfflineTargets(at)
  for _, rec in pairs(runtime.offlineTargets) do
    if at - rec.at <= 120 and offlineLineFor(text, rec) then signalOffline(rec); return true end
  end
  return false
end

local function systemOffline(text)
  matchOfflineLine(text)
end
Hunters.handlers.CHAT_MSG_SYSTEM = systemOffline

local function systemMessageFilter(_, _, text)
  return matchOfflineLine(text) and true or false
end

local function channelNoticeFilter(_, _, message, ...)
  local function ours(value)
    value = plain(value)
    if type(value) == "string" then
      value = value:gsub("^%d+%.%s*", "")
      return value:lower() == CHANNEL:lower()
    end
    return false
  end
  if ours(message) then return true end
  for i = 1, select("#", ...) do
    if ours(select(i, ...)) then return true end
  end
  return false
end

local function installChatFilters()
  if runtime.chatFiltersInstalled then return true end
  local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
  if type(add) ~= "function" then return false end
  local ok1 = pcall(add, "CHAT_MSG_SYSTEM", systemMessageFilter)
  local ok2 = pcall(add, "CHAT_MSG_CHANNEL_NOTICE", channelNoticeFilter)
  local ok3 = pcall(add, "CHAT_MSG_CHANNEL_NOTICE_USER", channelNoticeFilter)
  runtime.chatFiltersInstalled = ok1 and ok2 and ok3
  return runtime.chatFiltersInstalled
end

local function dropLowPriority()
  for i = #runtime.queue, 1, -1 do
    if runtime.queue[i].p > 2 then
      local item = table.remove(runtime.queue, i)
      if item.nonce then finishPending(item.nonce, nil) end
      if item.responseKey and runtime.owedResponses then runtime.owedResponses[item.responseKey] = nil end
    end
  end
end

local function queueItem()
  local best, at = nil, now()
  for i = #runtime.queue, 1, -1 do
    local item = runtime.queue[i]
    local staleRequest = item.nonce and (item.kind == "Q" or item.kind == "D")
      and not runtime.scope.pending[item.nonce]
    if staleRequest or at - item.created >= item.ttl then
      table.remove(runtime.queue, i)
      if item.nonce then finishPending(item.nonce, nil) end
      if item.responseKey and runtime.owedResponses then runtime.owedResponses[item.responseKey] = nil end
    end
  end
  for i, item in ipairs(runtime.queue) do
    local eligible = true
    if eligible and item.due <= at and (not best or item.p < runtime.queue[best].p
     or (item.p == runtime.queue[best].p and item.created < runtime.queue[best].created)) then best = i end
  end
  return best
end

local function snapshotItem()
  local best
  for _, item in pairs(runtime.snapshots) do
    if item.due <= now() and (not best or item.created < best.created
       or (item.created == best.created and item.id < best.id)) then best = item end
  end
  return best
end

local function snapshotPayload(item)
  local batch = item.batch
  if not batch.newsPayload and not currentPartner(item.key) then return nil end
  local row = runtime.scope and runtime.scope.rows[item.key]
  local version = row and row.version or item.version
  local news = batch.newsPayload and versionAtLeast(version, 3, 1)
  return news and batch.newsPayload or batch.rowPayload, news and "news" or "push"
end

local function removeSendItem(item, index, useSnapshot, pendingResult)
  if useSnapshot then
    if runtime.snapshots[item.id] == item then runtime.snapshots[item.id] = nil end
  else
    table.remove(runtime.queue, index)
    if item.nonce then finishPending(item.nonce, pendingResult) end
    if item.responseKey and runtime.owedResponses then runtime.owedResponses[item.responseKey] = nil end
  end
end

local function sendTick()
  if not enabled() or not runtime.world or inInstance() or inCombat() then return end
  local at = now()
  if at < (runtime.sendAfter or 0) then return end
  if lockedDown() then return end
  local rateAt = rateNow()
  if at < runtime.pauseUntil or rateAt - runtime.lastSend < 2 then return end
  trimWindow(runtime.sentMinute, 60, rateAt); trimWindow(runtime.sentBurst, 10, rateAt)
  trimWindow(runtime.nonResponseBurst, 10, rateAt)
  trimWindow(runtime.snapshotMinute, 60, rateAt); trimWindow(runtime.nonResponseMinute, 60, rateAt)
  if #runtime.sentMinute >= 10 or #runtime.sentBurst >= 3 then return end
  local index = queueItem()
  local reserveFull = #runtime.nonResponseMinute >= NON_RESPONSE_PER_MINUTE
  if index and runtime.queue[index].kind ~= "response" and reserveFull then index = nil end
  local nonResponseFull = #runtime.nonResponseBurst >= 2
  if index and runtime.queue[index].kind ~= "response" and nonResponseFull then index = nil end
  local snapshot = not reserveFull and not nonResponseFull and #runtime.snapshotMinute < NEWS_PER_MINUTE and snapshotItem() or nil
  local useSnapshot = snapshot and (not index or runtime.queue[index].p > 2)
  if not index and not useSnapshot then return end
  local item = useSnapshot and snapshot or runtime.queue[index]
  local payload, snapshotKind
  if useSnapshot then payload, snapshotKind = snapshotPayload(item); item.kind = snapshotKind
  else payload = item.payload end
  if type(payload) == "function" then payload = payload() end
  if type(payload) ~= "string" or #payload > MAX_PAYLOAD then
    removeSendItem(item, index, useSnapshot, nil)
    return
  end
  if not (C_ChatInfo and type(C_ChatInfo.SendAddonMessage) == "function") then return end
  -- The hard bucket counts API attempts, not only accepted sends. A throttled or locked client
  -- must not turn retries into a second, unmetered stream.
  runtime.lastSend = rateAt
  runtime.scope.meta.lastSend = rateAt
  runtime.sentMinute[#runtime.sentMinute + 1], runtime.sentBurst[#runtime.sentBurst + 1] = rateAt, rateAt
  if useSnapshot then runtime.snapshotMinute[#runtime.snapshotMinute + 1] = rateAt end
  if item.kind ~= "response" then
    runtime.nonResponseMinute[#runtime.nonResponseMinute + 1] = rateAt
    runtime.nonResponseBurst[#runtime.nonResponseBurst + 1] = rateAt
  end
  runtime.sending = { target=item.target, kind=item.kind, offline=false }
  local remembered = rememberWhisper(item.target, item.kind)
  local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, "WHISPER", item.target)
  result = plain(result)
  local offline = runtime.sending.offline
  runtime.sending = nil
  if offline then result = 12 end
  local success = ok and (result == nil or result == true or result == 0)
  runtime.scope.meta.lastResult = tostring(result == nil and 0 or result)
  if success then
    if useSnapshot then
      if runtime.snapshots[item.id] == item then runtime.snapshots[item.id] = nil end
      item.batch.delivered[item.key] = true
    else table.remove(runtime.queue, index) end
    noteExchange()
    runtime.throttleSuccess = runtime.throttleSuccess + 1
    if runtime.throttleSuccess >= 5 then runtime.throttleStep, runtime.throttleSuccess = 0, 0 end
    if item.kind == "response" then
      if item.responseKey then
        completeNonce(item.responseKey)
        if runtime.owedResponses then runtime.owedResponses[item.responseKey] = nil end
      end
      trimWindow(runtime.responseMinute, 60, rateAt)
      runtime.responseMinute[#runtime.responseMinute + 1] = rateAt
    end
  elseif result == 3 then
    runtime.throttleStep = math.min(#THROTTLE, runtime.throttleStep + 1)
    runtime.throttleSuccess = 0
    runtime.pauseUntil = at + THROTTLE[runtime.throttleStep]
  elseif result == 11 then
    runtime.pauseUntil = at + 2
  elseif not ok or type(result) ~= "number" then
    -- A local/API exception is transport-neutral. Drop this item without retiring a candidate.
    runtime.scope.meta.lastResult = "local error"
    removeSendItem(item, index, useSnapshot, nil)
  else
    if result == 12 then
      if remembered then signalOffline(remembered) end
    end
    removeSendItem(item, index, useSnapshot, result ~= 0 and false or nil)
  end
end
Hunters.SendTick = sendTick

local function maintenance()
  local s = runtime.scope; if not s then return end
  local mono = now()
  trimWindow(runtime.inboundMinute, 60, mono)
  for sender, list in pairs(runtime.inboundBySender) do
    trimWindow(list, 60, mono)
    if #list == 0 then runtime.inboundBySender[sender] = nil end
  end
  local wall = serverNow()
  for key, partner in pairs(s.partners) do
    if type(partner) ~= "table" or wall - (tonumber(partner.heard) or 0) > PARTNER_TTL then
      s.partners[key] = nil
    end
  end
  compactHeapIfNeeded("expiry")
  compactHeapIfNeeded("rowExpiry")
  compactHeapIfNeeded("candidateExpiry")
  local expiry = runtime.heaps and runtime.heaps.expiry
  if not expiry then return end
  local started, handled, at = profileMS(), 0, wall
  while handled < 50 do
    if started and profileMS() - started >= 0.5 then break end
    local e = expiry[1]
    if not e or e.x > at then break end
    heapPop(expiry); handled = handled + 1
    local map = e.k == "row" and s.rows or e.k == "candidate" and s.candidates
      or e.k == "pending" and s.pending or e.k == "nonce" and s.completedNonces
    local rec = map and map[e.id]
    if rec and rec.rev == e.r and rec.expires <= at then
      if e.k == "pending" then
        local kind, key = rec.kind, rec.key
        removeRecord(e.k, e.id)
        completeNonce("out:" .. e.id)
        -- Expiry is not a negative transport result. Combat, instances, or lockdown can consume
        -- the whole TTL without ever attempting the request, so it must not retire a candidate.
      else removeRecord(e.k, e.id) end
    end
  end
  runtime.lastMaintenanceCount = handled
end
Hunters.Maintenance = maintenance

local function pickCandidate()
  local s, at, best, bestScore = runtime.scope, serverNow()
  for key, c in pairs(s.candidates) do
    if not c.retired and (not c.nextTry or c.nextTry <= at) and key ~= rowKey(ns.myName) then
      local score = c.lastQuery and (1000000000000 + (c.lastConfirmed or c.lastQuery or 0)) or (c.t or 0)
      if not best or score < bestScore or (score == bestScore and key < best) then best, bestScore = key, score end
    end
  end
  return best, best and s.candidates[best] or nil
end

local function chainActive(generation)
  return generation == runtime.chainGeneration and enabled() and runtime.world
end

local function discoveryStep(generation)
  if not chainActive(generation) then return end
  runtime.discoveryRuns = (runtime.discoveryRuns or 0) + 1
  if not inCombat() and not inInstance() then
    local key, c = pickCandidate()
    if c then queryCandidate(c.name) end
  end
  local confirmed = runtime.scope.meta.rowCount or 0
  local elapsed = now() - (runtime.discoveryStarted or now())
  local delay = confirmed < 100 and elapsed < 2700 and (15 + math.random() * 10) or (45 + math.random() * 30)
  C_Timer.After(delay, function() discoveryStep(generation) end)
end

local function introductionStep(generation)
  if not chainActive(generation) then return end
  runtime.introductionRuns = (runtime.introductionRuns or 0) + 1
  if not inCombat() and not inInstance() then
    local partners = currentPartners()
    if #partners > 0 then
      runtime.introTurn = ((runtime.introTurn or 0) % #partners) + 1
      local p = partners[runtime.introTurn]
      local nonce = makeNonce()
      if nonce and addPending("D", p.row.name, p.key, nonce) then
        if not enqueue(4, p.row.name, "D;" .. PROTO .. ";" .. nonce, "D", nonce, 60) then finishPending(nonce, nil) end
      end
    end
  end
  C_Timer.After(480 + math.random() * 240, function() introductionStep(generation) end)
end

local function channelMembership()
  if type(GetChannelList) ~= "function" then return nil, false end
  local values = { pcall(GetChannelList) }
  if not values[1] then return nil, false end
  for i = 2, #values, 3 do
    local id, name, suspended = plain(values[i]), plain(values[i + 1]), plain(values[i + 2])
    if type(name) == "string" and name:lower() == CHANNEL:lower() then
      return type(id) == "number" and id > 0 and id or nil, suspended == true
    end
  end
  return nil, false
end

local function setDirectory(state)
  if runtime.directory == state then return end
  runtime.directory = state
  if ns.OnHuntersChanged then pcall(ns.OnHuntersChanged) end
end

local function secureChannelCall(fn, ...)
  if type(fn) ~= "function" then return false, nil end
  local ok, result
  if type(securecall) == "function" then ok, result = pcall(securecall, fn, ...)
  else ok, result = pcall(fn, ...) end
  return ok, plain(result)
end

local function leaveDirectory()
  -- Only a member leaves: the game answers a leave for a channel we are not in with a notice.
  if channelMembership() then secureChannelCall(LeaveChannelByName, CHANNEL) end
end

local wakeDirectory, runDirectoryWake, displayChannels
local function joinAttempt(generation)
  if generation ~= nil and not chainActive(generation) then return end
  if not enabled() or not runtime.world then return end
  runtime.joinRuns = (runtime.joinRuns or 0) + 1
  local id, suspended = channelMembership()
  if suspended then setDirectory("suspended"); return end
  if id then
    runtime.joinFailedGeneration = nil
    if runtime.directory ~= "working" then setDirectory("waiting for roster") end
    return
  end
  local fn = JoinChannelByName or JoinPermanentChannel
  if type(fn) ~= "function" then
    runtime.joinFailedGeneration = generation or runtime.chainGeneration
    setDirectory("not joined")
    return
  end
  local ok, result
  if fn == JoinChannelByName then ok, result = secureChannelCall(fn, CHANNEL, nil, 0, 0)
  else ok, result = secureChannelCall(fn, CHANNEL) end
  if not ok or result == false then
    runtime.joinFailedGeneration = generation or runtime.chainGeneration
    setDirectory("not joined")
  else
    runtime.joinFailedGeneration = nil
    setDirectory("waiting for roster")
    displayChannels()
    if wakeDirectory then wakeDirectory("join") end
  end
end

displayChannels = function()
  local max = 60
  if type(GetNumDisplayChannels) == "function" then max = math.min(60, tonumber(plain(try(GetNumDisplayChannels))) or max) end
  local ours, members, other
  if type(GetChannelDisplayInfo) ~= "function" then return nil end
  for i = 1, max do
    local ok, name, header, _, _, count = pcall(GetChannelDisplayInfo, i)
    name, header, count = plain(name), plain(header), plain(count)
    if ok and type(name) == "string" and not header then
      name = name:gsub("^%d+%.%s*", "")
      if name:lower() == CHANNEL:lower() then ours, members = i, tonumber(count)
      elseif not other then other = i end
    end
  end
  runtime.displayIndex = ours
  return ours, members, other
end

local function channelWindowOpen()
  local f = _G and _G.ChannelFrame
  if type(f) ~= "table" or type(f.IsShown) ~= "function" then return false end
  local ok, shown = pcall(f.IsShown, f)
  return not ok or shown == true
end

local refreshDirectory, scheduleDirectory, armDirectoryCycle
local function rosterSlice(scan)
  if runtime.rosterScan ~= scan or scan.generation ~= runtime.chainGeneration
     or not enabled() then runtime.rosterScan = nil; return end
  if inCombat() or inInstance() then
    runtime.rosterScan, runtime.directoryInterrupted = nil, true
    setDirectory("waiting for roster")
    return
  end
  local started, calls = profileMS(), 0
  while scan.at <= scan.total and calls < 40 do
    if started and profileMS() - started >= 0.5 then break end
    local values = { pcall(C_ChatInfo.GetChannelRosterInfo, scan.index, scan.at) }
    scan.at, calls = scan.at + 1, calls + 1
    local raw = values[1] and values[2] or nil
    local name = values[1] and plain(raw) or nil
    local canon = canonicalName(name)
    local folded = canon and lowercaseName(canon)
    if not name then
      scan.rejected.secret = scan.rejected.secret + 1
    elseif not canon then
      scan.rejected.canonical = scan.rejected.canonical + 1
    elseif rowKey(canon) == rowKey(ns.myName) then
      scan.namesRead, scan.rejected.self = scan.namesRead + 1, scan.rejected.self + 1
    elseif scan.seen[folded] then
      scan.namesRead, scan.rejected.duplicate = scan.namesRead + 1, scan.rejected.duplicate + 1
    else
      scan.namesRead = scan.namesRead + 1
      scan.seen[folded] = true
      scan.found = scan.found + 1
      local guid
      for i = 3, #values do
        local value = plain(values[i])
        if type(value) == "string" and value:match("^Player%-") then guid = value break end
      end
      local row = { name=canon, guid=guid }
      if #scan.reservoir < CANDIDATE_CAP then scan.reservoir[#scan.reservoir + 1] = row
      else
        local pick = math.random(scan.found)
        if pick <= CANDIDATE_CAP then scan.reservoir[pick] = row end
      end
    end
  end
  runtime.lastRosterSlice = calls
  if scan.at <= scan.total then C_Timer.After(0, function() rosterSlice(scan) end); return end
  runtime.rosterScan = nil
  local names = scan.seen
  for _, row in ipairs(scan.reservoir) do
    Hunters.NoteCandidate(row.name, "directory", row.guid)
  end
  runtime.directoryNames = names
  local result
  if scan.found > 0 then result = "working"
  elseif scan.total == 1 and scan.rejected.self == 1 then result = "only you"
  elseif scan.total > 1 and scan.poll < 2 and not channelWindowOpen()
     and not inCombat() and not inInstance() and type(SetSelectedDisplayChannel) == "function" then
    runtime.ownSelectionAt = now()
    if scan.other then pcall(SetSelectedDisplayChannel, scan.other) end
    pcall(SetSelectedDisplayChannel, scan.index)
    setDirectory("waiting for roster")
    scheduleDirectory(scan.poll == 0 and 3 or 5, scan.generation, scan.poll + 1)
    result = "waiting for roster"
  elseif scan.total > 1 then result = "unreadable"
  else result = "waiting for roster" end
  local summary = { at=serverNow(), reported=scan.total, namesRead=scan.namesRead, found=scan.found,
    rejected=scan.rejected, result=result }
  runtime.lastScan, runtime.scope.meta.lastScan = summary, summary
  runtime.scope.meta.directoryAt = summary.at
  setDirectory(result)
  if result == "working" or result == "only you" then fanoutLatest() end
end

scheduleDirectory = function(delay, generation, poll)
  C_Timer.After(delay, function() refreshDirectory(generation, poll) end)
end

armDirectoryCycle = function(generation)
  runtime.directoryCycle = (runtime.directoryCycle or 0) + 1
  local ticket = runtime.directoryCycle
  C_Timer.After(600, function()
    if ticket == runtime.directoryCycle then refreshDirectory(generation, 0) end
  end)
end

refreshDirectory = function(generation, poll)
  generation = generation or runtime.chainGeneration
  poll = poll or 0
  if not chainActive(generation) then return end
  runtime.refreshRuns = (runtime.refreshRuns or 0) + 1
  local sinceZone = now() - (runtime.zoneChangedAt or -1e9)
  if sinceZone < 10 then scheduleDirectory(10 - sinceZone, generation, poll); return end
  if inCombat() or inInstance() then runtime.directoryInterrupted = true; setDirectory("waiting for roster"); return end
  local id, suspended = channelMembership()
  if id then runtime.joinFailedGeneration = nil end
  if suspended then setDirectory("suspended"); armDirectoryCycle(generation); return end
  local index, members, other = displayChannels()
  if not id or not index then
    local failed = not id and runtime.joinFailedGeneration == generation
    if not failed then
      setDirectory("waiting for roster")
      if poll < 1 then scheduleDirectory(15, generation, poll + 1)
      else armDirectoryCycle(generation) end
    else
      setDirectory("not joined")
      armDirectoryCycle(generation)
    end
    return
  end
  if (not members or members <= 0) and not channelWindowOpen() and not inCombat()
     and type(SetSelectedDisplayChannel) == "function" then
    if poll < 2 then
      runtime.ownSelectionAt = now()
      if other then pcall(SetSelectedDisplayChannel, other) end
      pcall(SetSelectedDisplayChannel, index)
      setDirectory("waiting for roster")
      scheduleDirectory(poll == 0 and 3 or 5, generation, poll + 1)
    else
      setDirectory("waiting for roster")
      armDirectoryCycle(generation)
    end
    return
  end
  if not members or members <= 0 or not (C_ChatInfo and type(C_ChatInfo.GetChannelRosterInfo) == "function") then
    setDirectory((members and members > 1) and "unreadable" or "waiting for roster")
    armDirectoryCycle(generation); return
  end
  local scan = { index=index, other=other, total=math.min(6000, math.floor(members)), at=1, found=0,
    namesRead=0, reservoir={}, seen={}, rejected={ secret=0, canonical=0, self=0, duplicate=0 },
    generation=generation, poll=poll }
  runtime.rosterScan = scan
  rosterSlice(scan)
  armDirectoryCycle(generation)
end
Hunters.RefreshDirectory = function() refreshDirectory(runtime.chainGeneration, 0) end

wakeDirectory = function(reason)
  if not enabled() or not runtime.world then return end
  local channelEvent = reason == "channel" or reason == "channel-ui"
  if channelEvent and now() - (runtime.ownSelectionAt or -1e9) < 10 then return end
  local explicit = reason == "join" or reason == "notice" or reason == "resume" or reason == "world"
  if not explicit and now() - (runtime.lastDirectoryWake or -1e9) < 60 then return end
  if explicit then runtime.directoryWakeBypass = true end
  if runtime.directoryWakePending then return end
  runtime.directoryWakePending = true
  C_Timer.After(5, runDirectoryWake)
end

runDirectoryWake = function()
  runtime.directoryWakePending = nil
  if not chainActive(runtime.chainGeneration) then runtime.directoryWakeBypass = nil; return end
  if inCombat() or inInstance() then runtime.directoryInterrupted = true; runtime.directoryWakeBypass = nil; return end
  local at = now()
  if not runtime.directoryWakeBypass and at - (runtime.lastDirectoryWake or -1e9) < 60 then return end
  runtime.directoryWakeBypass, runtime.lastDirectoryWake, runtime.directoryInterrupted = nil, at, nil
  refreshDirectory(runtime.chainGeneration, 0)
  fanoutLatest()
end

local function indexedChannelWake(displayIndex)
  if tonumber(plain(displayIndex)) == runtime.displayIndex then wakeDirectory("channel") end
end
Hunters.handlers.CHANNEL_ROSTER_UPDATE = indexedChannelWake
Hunters.handlers.CHANNEL_UI_UPDATE = function()
  displayChannels()
  wakeDirectory("channel-ui")
end
Hunters.handlers.CHANNEL_COUNT_UPDATE = indexedChannelWake
Hunters.handlers.PLAYER_REGEN_ENABLED = function()
  if runtime.directoryInterrupted or runtime.rosterScan then wakeDirectory("resume") end
  fanoutLatest()
end
Hunters.handlers.CHAT_MSG_CHANNEL_NOTICE = function(message, ...)
  if plain(message) ~= "YOU_JOINED" then return end
  for i = 1, select("#", ...) do
    local value = plain(select(i, ...))
    if type(value) == "string" and value:gsub("^%d+%.%s*", ""):lower() == CHANNEL:lower() then
      wakeDirectory("notice")
      return
    end
  end
end

local function scanGroup()
  if not enabled() or inInstance() or type(GetNumGroupMembers) ~= "function" then return end
  local at = now()
  if runtime.lastGroupScan and at - runtime.lastGroupScan < 10 then return end
  runtime.lastGroupScan = at
  local total = math.min(40, math.max(0, math.floor(tonumber(plain(try(GetNumGroupMembers))) or 0)))
  local raid = type(IsInRaid) == "function" and plain(try(IsInRaid)) == true
  if not raid then total = math.max(0, total - 1) end -- party count includes the local player
  for i = 1, total do
    local unit = (raid and "raid" or "party") .. i
    local name = type(GetUnitName) == "function" and plain(try(GetUnitName, unit, true)) or nil
    if type(name) ~= "string" and type(UnitName) == "function" then
      local values = { pcall(UnitName, unit) }
      local first, last = values[1] and plain(values[2]) or nil, values[1] and plain(values[3]) or nil
      if type(first) == "string" then name = type(last) == "string" and last ~= "" and (first .. " " .. last) or first end
    end
    local guid = type(UnitGUID) == "function" and plain(try(UnitGUID, unit)) or nil
    Hunters.NoteCandidate(name, "group", guid)
  end
end
Hunters.handlers.GROUP_ROSTER_UPDATE = scanGroup

local function startChains(delay)
  runtime.chainGeneration = (runtime.chainGeneration or 0) + 1
  local generation = runtime.chainGeneration
  runtime.joinFailedGeneration = nil
  runtime.chainStarts = (runtime.chainStarts or 0) + 1
  runtime.discoveryStarted = now()
  delay = math.max(0, tonumber(delay) or 0)
  runtime.sendAfter = now() + delay
  C_Timer.After(delay, function()
    if not chainActive(generation) then return end
    joinAttempt(generation)
    C_Timer.After(120, function() joinAttempt(generation) end)
    local function joinLoop()
      if not chainActive(generation) then return end
      joinAttempt(generation)
      C_Timer.After(900, joinLoop)
    end
    C_Timer.After(900, joinLoop)
    scheduleDirectory(8, generation, 0)
    discoveryStep(generation)
  end)
  C_Timer.After(480 + math.random() * 240, function() introductionStep(generation) end)
end

local function startWorld()
  local inside = inInstance()
  if runtime.world then
    local leaving = runtime.wasInInstance and not inside
    runtime.wasInInstance = inside
    if runtime.directoryInterrupted then wakeDirectory("resume")
    elseif leaving then wakeDirectory("world")
    else wakeDirectory("entering-world") end
    fanoutLatest()
    return
  end
  runtime.wasInInstance = inside
  runtime.world, runtime.zoneChangedAt = true, now()
  scanGroup()
  if enabled() then startChains(45 + math.random() * 75)
  else
    -- Sharing is account-wide, channel membership is per character: a character that joined the
    -- directory before sharing was turned off on another one is still listed there. The game
    -- re-joins saved channels a little after login, so look once a minute in.
    C_Timer.After(60, function()
      local h = root()
      if h and h.enabled ~= true then leaveDirectory() end
    end)
  end
end
Hunters.handlers.PLAYER_ENTERING_WORLD = startWorld
Hunters.handlers.ZONE_CHANGED_NEW_AREA = function()
  runtime.zoneChangedAt = now()
  if runtime.directoryInterrupted then wakeDirectory("resume") end
  fanoutLatest()
end

local function boardComparator(period)
  if period == "week" then
    return function(a,b)
      if a.partial ~= b.partial then return not a.partial end
      if a.wkPoints ~= b.wkPoints then return a.wkPoints > b.wkPoints end
      if a.wkKills ~= b.wkKills then return a.wkKills > b.wkKills end
      return lowercaseName(a.name) < lowercaseName(b.name)
    end
  end
  return function(a,b)
    if a.points ~= b.points then return a.points > b.points end
    if a.kills ~= b.kills then return a.kills > b.kills end
    return lowercaseName(a.name) < lowercaseName(b.name)
  end
end

local function ownRow()
  local c = ensureCharacter(); if not c then return nil end
  local stats = ownStats(); if not stats then return nil end
  return { name=ns.myName, class=c.class, kills=stats.kills, points=stats.points, kb=stats.kb,
    orig=stats.orig, kings=stats.kings, rung=ns.Rank and tonumber(ns.Rank.Level and ns.Rank.Level()) or 0,
    week=c.weekStart or 0, complete=c.weekComplete or 0, wkKills=stats.wkKills, wkPoints=stats.wkPoints,
    confirmed=serverNow(), me=true }
end

local function boardStep(build)
  if not build.building then return end
  local started, comparisons, work = profileMS(), 0, 0
  local function budget()
    if comparisons >= 500 or work >= 500 then return false end
    if not started then return true end
    local current = profileMS()
    return not current or current - started < 0.75
  end
  if build.phase == "collect" then
    local n = 0
    while n < 200 and budget() do
      local ok, key, row = pcall(next, runtime.scope.rows, build.cursor)
      if not ok then
        -- A row may expire or arrive between cooperative frames. Lua 5.1 rejects next(t, key)
        -- after that cursor key is removed and a rehash occurs, so restart this bounded snapshot.
        local mine = ownRow()
        build.list, build.cursor = {}, nil
        if mine and (build.period ~= "week" or mine.week == build.week) then
          mine.partial = build.period == "week" and mine.complete ~= 1 or false
          build.list[1] = mine
        end
        build.collectRestarts = (build.collectRestarts or 0) + 1
        n, work = n + 1, work + 1
      else
      build.cursor = key
      if not key then
        build.phase, build.width, build.cursor, build.mergeAt, build.output, build.merge = "sort", 1, nil, 1, {}, nil
        break
      end
      if serverNow() - (row.confirmed or 0) <= ROW_TTL then
        if build.period ~= "week" or row.week == build.week then
          local copy = {}; for k,v in pairs(row) do copy[k] = v end
          copy.partial = build.period == "week" and row.complete ~= 1 or false
          build.list[#build.list + 1] = copy
        end
      end
      n, work = n + 1, work + 1
      end
    end
  elseif build.phase == "sort" then
    local list, width, cmp = build.list, build.width, build.cmp
    if width >= #list then
      build.phase, build.publishAt, build.rank = "publish", 1, 0
    else
      build.output = build.output or {}
      while budget() and work < 500 do
        local m = build.merge
        if not m then
          local left = build.mergeAt or 1
          if left > #list then
            build.list, build.output, build.width, build.mergeAt = build.output, {}, width * 2, 1
            build.merge = nil
            break
          end
          local mid, right = math.min(left + width - 1, #list), math.min(left + 2 * width - 1, #list)
          m = { a=left, b=mid+1, mid=mid, right=right, out=left }
          build.merge = m
        end
        if m.a <= m.mid and m.b <= m.right then
          comparisons, work = comparisons + 1, work + 1
          if cmp(list[m.a], list[m.b]) then build.output[m.out], m.a = list[m.a], m.a + 1
          else build.output[m.out], m.b = list[m.b], m.b + 1 end
          m.out = m.out + 1
        elseif m.a <= m.mid then
          build.output[m.out], m.a, m.out, work = list[m.a], m.a + 1, m.out + 1, work + 1
        elseif m.b <= m.right then
          build.output[m.out], m.b, m.out, work = list[m.b], m.b + 1, m.out + 1, work + 1
        else
          build.mergeAt, build.merge = m.right + 1, nil
        end
      end
    end
  elseif build.phase == "publish" then
    if next(build.journal) then
      local mine = ownRow()
      build.list, build.cursor, build.phase, build.journal = {}, nil, "collect", {}
      build.publishAt, build.rank = nil, nil
      if mine and (build.period ~= "week" or mine.week == build.week) then
        mine.partial = build.period == "week" and mine.complete ~= 1 or false
        build.list[1] = mine
      end
    else
      while build.publishAt <= #build.list and budget() do
        local row = build.list[build.publishAt]
        if not row.partial then build.rank = build.rank + 1; row.rank = build.rank else row.rank = nil end
        build.publishAt, work = build.publishAt + 1, work + 1
      end
      if build.publishAt > #build.list then
        build.snapshot, build.building, build.dirty = build.list, false, false
        build.confirmed = build.rank
        if ns.OnHuntersChanged then pcall(ns.OnHuntersChanged) end
      end
    end
  end
  runtime.lastSortComparisons = comparisons
  runtime.lastSortWork = work
  runtime.maxSortComparisons = math.max(runtime.maxSortComparisons or 0, comparisons)
  runtime.maxSortWork = math.max(runtime.maxSortWork or 0, work)
  if build.building then C_Timer.After(0, function() boardStep(build) end) end
end

function Hunters.Board(period)
  period = period == "week" and "week" or "lifetime"
  local build = runtime.board[period]
  if not build then build = { dirty=true }; runtime.board[period] = build end
  if (build.dirty or not build.snapshot) and not build.building and runtime.scope then
    build.period, build.week, build.list, build.cursor = period, localWeekStart(), {}, nil
    local mine = ownRow()
    if mine and (period ~= "week" or (build.week and mine.week == build.week)) then
      mine.partial = period == "week" and mine.complete ~= 1 or false
      build.list[1] = mine
    end
    build.phase, build.width, build.mergeAt, build.output = "collect", 1, 1, {}
    build.cmp, build.journal, build.building = boardComparator(period), {}, true
    C_Timer.After(0, function() boardStep(build) end)
  end
  return build.snapshot, build.building, build.confirmed or 0
end

function Hunters.Status()
  local h, s = root(), runtime.scope
  local partners = s and #currentPartners() or 0
  local channelID = channelMembership()
  local _, reported = displayChannels()
  local scan = s and (runtime.lastScan or s.meta.lastScan) or nil
  local queueDepth = #runtime.queue + countTable(runtime.snapshots)
  local backoff, wall = 0, serverNow()
  for _, c in pairs(s and s.candidates or {}) do
    local left = math.max(0, (tonumber(c.nextTry) or 0) - wall)
    if left > 0 and (backoff == 0 or left < backoff) then backoff = left end
  end
  return {
    enabled = h and h.enabled == true, reason = runtime.disabledReason,
    candidates = s and (s.meta.candidateCount or 0) or 0,
    confirmed = s and (s.meta.rowCount or 0) or 0,
    partners = partners, directory = runtime.directory,
    lastExchange = s and s.meta.lastExchange or nil,
    notice = h and h.enabled == true and h.boardNoticeDismissed ~= true,
    channelID = channelID, reported = reported or (scan and scan.reported) or 0,
    namesRead = scan and scan.namesRead or 0, rejected = scan and scan.rejected or {},
    lastScan = scan and scan.at or nil, scanResult = scan and scan.result or "none",
    queueDepth = queueDepth, lastResult = s and s.meta.lastResult or "none",
    lastScanAgo = scan and math.max(0, serverNow() - (scan.at or serverNow())) or nil,
    pause = math.max(0, math.ceil((runtime.pauseUntil or 0) - now())), backoff = math.ceil(backoff),
    lockdown = lockedDown(), wireScope = runtime.wireScope, version = ns.VERSION,
    feed = h and h.feed,
  }
end

-- The board notice stays until the player dismisses it, and a dismissal is remembered: it is a
-- disclosure, not a nag. Turning sharing back on after turning it off shows it once more.
function Hunters.AcknowledgeBoardNotice()
  local h = root(); if h then h.boardNoticeDismissed = true end
end

function Hunters.SetEnabled(on)
  local h = root(); if not h then return false end
  local wasEnabled = h.enabled == true
  h.enabled = on == true
  if not h.enabled then
    runtime.chainGeneration = (runtime.chainGeneration or 0) + 1
    for _, item in ipairs(runtime.queue) do
      if item.responseKey and runtime.owedResponses then runtime.owedResponses[item.responseKey] = nil end
    end
    runtime.queue, runtime.snapshots, runtime.coalesce, runtime.responseScheduled = {}, {}, nil, 0
    runtime.owedResponses = {}
    local s = runtime.scope
    if s then for nonce in pairs(s.pending) do removeRecord("pending", nonce) end end
    leaveDirectory()
    setDirectory("not joined")
  else
    if not wasEnabled then h.boardNoticeDismissed = nil end
    ensureScope()
    if not wasEnabled then setDirectory("starting") end
    if runtime.world and not wasEnabled then startChains(0) end
  end
  markBoard("enabled")
  return h.enabled
end

function Hunters.Command(text)
  text = tostring(text or ""):lower():match("^%s*(.-)%s*$")
  if text == "on" then
    Hunters.SetEnabled(true)
    if runtime.disabledReason then ns.Print(runtime.disabledReason) else ns.Print("Slayers sharing on. " .. NOTICE) end
  elseif text == "off" then Hunters.SetEnabled(false); ns.Print("Slayers sharing off. No Slayers traffic will be sent or accepted; copies already received cannot be erased.")
  elseif text:match("^feed%s+") then
    local rest = text:match("^feed%s+(.+)$")
    local h = root(); local part, value = rest:match("^(%S+)%s+(%S+)$")
    if rest == "off" or rest == "top10" or rest == "everyone" then
      h.feed.mode = rest; ns.Print("Slayers feed: " .. rest .. ".")
    elseif (part == "voice" or part == "banner") and (value == "on" or value == "off") then
      h.feed[part] = value == "on"; ns.Print(("Slayers feed %s: %s."):format(part, value))
    else ns.Print("Use /godslayer slayers feed off, top10, everyone, voice on|off, or banner on|off.") end
  elseif text == "" or text == "status" then
    local st = Hunters.Status()
    if not st.enabled then ns.Print("Slayers sharing is off.")
    elseif st.reason then ns.Print(st.reason)
    else
      local r = st.rejected
      ns.Print(table.concat({
        ("Slayers on | directory %s | channel %s | reported %d | read %d"):format(st.directory, st.channelID or "not joined", st.reported, st.namesRead),
        ("rejected secret/nil %d, canonicalization %d, self %d, duplicate %d | scan %s %s"):format(r.secret or 0, r.canonical or 0, r.self or 0, r.duplicate or 0, st.scanResult, st.lastScanAgo and (st.lastScanAgo .. "s ago") or "never"),
        ("candidates %d | confirmed %d | partners %d | queue %d | send %s"):format(st.candidates, st.confirmed, st.partners, st.queueDepth, st.lastResult),
        ("pause %ds | backoff %ds | lockdown %s | scope %s | version %s"):format(st.pause, st.backoff, st.lockdown and "yes" or "no", st.wireScope or "none", st.version),
      }, "\n"))
    end
  else ns.Print("Use /godslayer slayers on, off, status, or feed.") end
end

local RULESET_LABELS = { pvp = "PvP", rp = "RP", rppvp = "RP-PvP", hardcore = "Hardcore", standard = "Standard" }
-- "us/horde/pvp" -> "US, Horde, PvP" for the options page.
local function scopeLabel(id)
  local region, faction, ruleset = tostring(id or ""):match("^([^/]+)/([^/]+)/(.+)$")
  if not region then return "starting" end
  return ("%s, %s, %s"):format(region:upper(), faction:sub(1, 1):upper() .. faction:sub(2),
    RULESET_LABELS[ruleset] or (ruleset:sub(1, 1):upper() .. ruleset:sub(2)))
end
Hunters.ScopeLabel = scopeLabel

function Hunters.RegisterSettings(S, category, layout)
  if not (S and category and type(S.RegisterProxySetting) == "function" and type(S.CreateCheckbox) == "function") then return end
  if layout and type(layout.AddInitializer) == "function" and type(CreateSettingsListSectionHeaderInitializer) == "function" then
    -- The header is drawn once, so it names the board's scope and leaves on/off to the checkbox,
    -- which follows every change. A board that cannot run says why instead.
    local header = runtime.disabledReason or ("Slayers board: " .. scopeLabel(runtime.scopeID))
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(header))
  end
  local setting = S.RegisterProxySetting(category, "GODSLAYER_HUNTERS_SHARE", S.VarType.Boolean,
    "Share on the Slayers board", true, function() local h=root(); return h and h.enabled == true end,
    function(value) Hunters.SetEnabled(value == true) end)
  S.CreateCheckbox(category, setting,
    "Shares name, class, kill counts, Olympus kills, rung, and your kills as they happen, including the victim's name and class when known, by addon whisper with your faction and ruleset. Other clients may retain the row for seven days; turning this off cannot erase their copies. Status is shown on Slayers.")
  if type(S.CreateDropdown) == "function" and type(S.CreateControlTextContainer) == "function" then
    local feed = S.RegisterProxySetting(category, "GODSLAYER_SLAYERS_FEED", S.VarType.String,
      "Slayers feed", "everyone", function() return root().feed.mode end,
      function(value) if value == "off" or value == "top10" or value == "everyone" then root().feed.mode = value end end)
    S.CreateDropdown(category, feed, function()
      local c = S.CreateControlTextContainer(); c:Add("everyone", "Everyone"); c:Add("top10", "Top 10"); c:Add("off", "Off")
      return c:GetData()
    end, "Show direct live kill news from confirmed Slayers. Chat is on by default.")
  end
  for _, part in ipairs({ "voice", "banner" }) do
    local key = part
    local setting = S.RegisterProxySetting(category, "GODSLAYER_SLAYERS_" .. key:upper(), S.VarType.Boolean,
      "Slayers feed " .. key, false, function() return root().feed[key] end,
      function(value) root().feed[key] = value == true end)
    S.CreateCheckbox(category, setting, "Optional " .. key .. " for qualifying live Slayers news.")
  end
end

function Hunters.Init()
  local h = root(); if not h then return end
  h.boardNoticeShown = nil -- an unreleased 3.0 build's name for boardNoticeDismissed
  ensureScope(); ensureCharacter()
  if C_ChatInfo and type(C_ChatInfo.RegisterAddonMessagePrefix) == "function" then pcall(C_ChatInfo.RegisterAddonMessagePrefix, PREFIX) end
  if not installChatFilters() then
    for _, delay in ipairs({ 1, 3, 8 }) do C_Timer.After(delay, installChatFilters) end
  end
  if h.enabled and not h.noticeShown then
    if runtime.scope then ns.Print(NOTICE); h.noticeShown = true
    elseif runtime.disabledReason then ns.Print(runtime.disabledReason) end
  end
  if runtime.scope then
    -- Pending requests belong to the process that issued their nonce and cannot survive reload.
    for nonce in pairs(runtime.scope.pending) do runtime.scope.pending[nonce] = nil end
    runtime.scope.meta.pendingCount = 0
  end
  C_Timer.NewTicker(0.5, sendTick)
  C_Timer.NewTicker(5, maintenance)
end

function Hunters.Debug()
  return runtime
end

