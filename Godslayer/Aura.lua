-- Godslayer auras: what is on you, what is on them, and what this server actually does to a
-- second stun.
--
-- The combat log is shut to addons on this client, so an addon cannot watch spells fly. It can
-- read auras, and almost everything that decides a duel is an aura: the sheep on you, the bubble
-- on them, the Recklessness that means you have four seconds to live. Nothing in Godslayer read
-- them before this file, and `UNIT_AURA` was not even registered.
--
-- THREE CALLS. Crowd control landing on you, named with who cast it and how long you are gone.
-- Their defence going up, so you stop throwing a Pyroblast at a bubble. Their offence going up,
-- which is the one worth knowing first, because it is the only one with a countdown on your life.
--
-- DIMINISHING RETURNS, FROM THE CLIENT AND THEN MEASURED. The groups are not guessed and not
-- copied from vanilla: `SpellCategories.DiminishType` in this build says which spells diminish
-- together, and tools/build_pvp_data.mjs reads it into Pvp.lua. Four of the groups a person would
-- assume are wrong here. Kidney Shot is its own group, so it does not share with Cheap Shot.
-- Seduction diminishes with fears, not with Mind Control. Scatter Shot diminishes with Polymorph.
-- Blind does not diminish at all.
--
-- What the client does not say is the curve: how much the second one keeps and how long the game
-- forgets in. So that half is measured. When you land a crowd control the game is asked how long
-- it gave you, and the number goes down against its group and the gap since the last one.
-- `/godslayer dr` then prints what this server really does. A spell the client puts in no group
-- is watched too, because an observed shortening there would mean the client's own table is
-- wrong, and that is worth knowing before anybody builds a strategy on it.

local _, ns = ...
local plain, try, scrub = ns.plain, ns.try, ns.scrub

local Aura = { handlers = {} }
ns.Aura = Aura

local SCAN_GAP = 0.15        -- one unit is re-read at most this often
local CALL_GAP = 2.0         -- any two aura calls at least this far apart
local SAME_GAP = 6.0         -- the same aura on the same unit is not called twice inside this
local DR_WINDOW = 25         -- the longest gap still worth recording as a possible DR pair
local DR_KEEP = 400          -- observations kept per category before the oldest go
local GONE_AFTER = 90        -- a target not seen for this long is dropped from the live table

-- CROWD CONTROL. Category is what the game might diminish together; nothing here assumes it does.
-- Ids are the first rank from the client's own spell data, used only to learn the local name.
local CC = {
  -- stuns
  ["Hammer of Justice"] = { cat = "stun", id = 853 },
  ["Cheap Shot"]        = { cat = "stun", id = 1833 },
  ["Kidney Shot"]       = { cat = "stun", id = 408 },
  ["War Stomp"]         = { cat = "stun", id = 20549 },
  Shockwave             = { cat = "stun", id = 440488 },
  -- fears
  Fear                  = { cat = "fear", id = 5782 },
  ["Howl of Terror"]    = { cat = "fear", id = 5484 },
  ["Psychic Scream"]    = { cat = "fear", id = 8122 },
  ["Intimidating Shout"] = { cat = "fear", id = 5246 },
  ["Death Coil"]        = { cat = "horror", id = 6789 },
  ["Scare Beast"]       = { cat = "fear", id = 1513 },
  -- incapacitates
  Polymorph             = { cat = "incap", id = 118 },
  Sap                   = { cat = "incap", id = 2070 },
  Gouge                 = { cat = "incap", id = 1776 },
  ["Freezing Trap"]     = { cat = "incap", id = 1499 },
  Hibernate             = { cat = "incap", id = 2637 },
  Repentance            = { cat = "incap", id = 20066 },
  ["Wyvern Sting"]      = { cat = "incap", id = 24335 },
  ["Shackle Undead"]    = { cat = "incap", id = 1425 },
  Banish                = { cat = "banish", id = 710 },
  -- roots
  ["Frost Nova"]        = { cat = "root", id = 122 },
  ["Entangling Roots"]  = { cat = "root", id = 339 },
  -- disorients
  Blind                 = { cat = "disorient", id = 2094 },
  ["Scatter Shot"]      = { cat = "disorient", id = 19503 },
  -- silences
  Silence               = { cat = "silence", id = 15487 },
  ["Counterspell - Silenced"] = { cat = "silence", id = 18469 },
  -- charms
  ["Mind Control"]      = { cat = "charm", id = 605 },
  Seduction             = { cat = "charm", id = 6358 },
  -- snares, which are not CC but are the reason you died
  Hamstring             = { cat = "snare", id = 1715 },
  ["Concussive Shot"]   = { cat = "snare", id = 5116 },
  ["Frost Shock"]       = { cat = "snare", id = 8056 },
}
Aura.CC = CC

-- The words for each category when it lands on you.
local CC_WORDS = {
  stun = "STUNNED", fear = "FEARED", horror = "HORRIFIED", incap = "INCAPACITATED",
  banish = "BANISHED", root = "ROOTED", disorient = "BLINDED", silence = "SILENCED",
  charm = "NOT YOURS", snare = "SLOWED",
}

-- THEIR DEFENCE. `immune` means stop casting; `soak` means it will cost you more than it should.
local DEFENCE = {
  ["Ice Block"]              = { kind = "immune", words = "ICE BLOCK", id = 11958 },
  ["Divine Shield"]          = { kind = "immune", words = "BUBBLE", id = 642 },
  ["Divine Protection"]      = { kind = "immune", words = "BUBBLE", id = 498 },
  ["Blessing of Protection"] = { kind = "immune", words = "HAND OF PROTECTION", id = 1022, note = "physical only" },
  ["Grounding Totem Effect"] = { kind = "immune", words = "GROUNDED", id = 8177, note = "one spell" },
  ["Will of the Forsaken"]   = { kind = "immune", words = "WILL OF THE FORSAKEN", id = 7744, note = "no fear, no charm" },
  ["Berserker Rage"]         = { kind = "immune", words = "BERSERKER RAGE", id = 18499, note = "no fear" },
  ["Fear Ward"]              = { kind = "immune", words = "FEAR WARD", id = 6346, note = "one fear" },
  ["Blessing of Freedom"]    = { kind = "immune", words = "FREEDOM", id = 1044, note = "no snare" },
  ["Shield Wall"]            = { kind = "soak", words = "SHIELD WALL", id = 871 },
  ["Last Stand"]             = { kind = "soak", words = "LAST STAND", id = 12975 },
  Barkskin                   = { kind = "soak", words = "BARKSKIN", id = 22812 },
  ["Ice Barrier"]            = { kind = "soak", words = "ICE BARRIER", id = 11426 },
  ["Power Word: Shield"]     = { kind = "soak", words = "SHIELDED", id = 17 },
  ["Pain Suppression"]       = { kind = "soak", words = "PAIN SUPPRESSION", id = 402004 },
  Dispersion                 = { kind = "soak", words = "DISPERSION", id = 425294 },
  ["Feign Death"]            = { kind = "gone", words = "FEIGNED", id = 5384 },
  Vanish                     = { kind = "gone", words = "VANISHED", id = 1856 },
  Stealth                    = { kind = "gone", words = "STEALTHED", id = 1784 },
  Shadowmeld                 = { kind = "gone", words = "SHADOWMELD", id = 20580 },
}
Aura.DEFENCE = DEFENCE

-- THEIR OFFENCE. The only aura class with a countdown on your life, so it is called loudest.
local OFFENCE = {
  Recklessness        = { words = "RECKLESS", id = 1719 },
  ["Death Wish"]      = { words = "DEATH WISH", id = 12328 },
  ["Avenging Wrath"]  = { words = "WINGS", id = 407788 },
  ["Arcane Power"]    = { words = "ARCANE POWER", id = 12042 },
  ["Icy Veins"]       = { words = "ICY VEINS", id = 425121 },
  Combustion          = { words = "COMBUSTION", id = 11129 },
  ["Bestial Wrath"]   = { words = "BESTIAL WRATH", id = 19574 },
  ["Adrenaline Rush"] = { words = "ADRENALINE RUSH", id = 13750 },
  ["Elemental Mastery"] = { words = "ELEMENTAL MASTERY", id = 16166 },
  ["Power Infusion"]  = { words = "POWER INFUSION", id = 10060 },
  Metamorphosis       = { words = "METAMORPHOSIS", id = 403789 },
  Berserk             = { words = "BERSERK", id = 417141 },
  ["Nature's Swiftness"] = { words = "NATURE'S SWIFTNESS", id = 16188, note = "the next heal is instant" },
  ["Presence of Mind"] = { words = "PRESENCE OF MIND", id = 12043, note = "the next cast is instant" },
}
Aura.OFFENCE = OFFENCE

-- A client in another language names these differently. The English name stays the key and the
-- local one is learned from the id at login, exactly as Fight.lua does it.
local alias = {}

local function english(name)
  if type(name) ~= "string" then return nil end
  return alias[name] or name
end

-- The diminishing group this build puts a spell in. 0 is the client saying it never diminishes.
local function drGroup(name)
  local row = ns.PVP and ns.PVP[name]
  return (row and tonumber(row.dr)) or 0
end
Aura.DRGroup = drGroup

-- A group's name, taken from a member people recognise rather than from an enum nobody published.
local function groupLabel(group)
  if group == 0 then return "no group" end
  local g = ns.DR_GROUPS and ns.DR_GROUPS[group]
  return (g and g.label) or ("group " .. tostring(group))
end
Aura.GroupLabel = groupLabel

local function opts()
  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.aura == nil then o.aura = true end
  return o
end

-- Stage.Banner wants the colour as three numbers, not as a chat escape. Passing a string makes
-- it set the words and then die on the arithmetic, which shows up as a banner with a title and
-- no line under it and nothing in the error log, because showBanner swallows the error.
local RED, BLUE, GREY, AMBER = { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }, { 0.73, 0.73, 0.73 }, { 1, 0.8, 0.2 }

local function colour(kind)
  if kind == "offence" then return RED end
  if kind == "immune" then return BLUE end
  if kind == "gone" then return GREY end
  return AMBER
end

--------------------------------------------------------------------------------
-- Reading auras
--------------------------------------------------------------------------------

-- Aura fields can come back as secret values on this client, so each one is unwrapped before use
-- and a secret stops the row rather than poisoning a comparison later.
local function auraAt(unit, i, filter, into)
  local get = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
  if type(get) ~= "function" then return nil end
  local ok, a = pcall(get, unit, i, filter)
  if not ok or type(a) ~= "table" then return nil end
  -- One crossing for the whole row. This used to be six plain() calls with a type check beside
  -- each, which made a single aura the most expensive thing the addon did: the profiler put one
  -- unthrottled scan of one enemy at 210 trips into the client, 174 of them from here. scrub
  -- does both halves at once -- a secret value becomes nil, and so does anything that is not a
  -- string, number or boolean -- so the guards below are about range now and not about type.
  local name, id, duration, expires, source, stacks =
    scrub(a.name, a.spellId, a.duration, a.expirationTime, a.sourceUnit, a.applications)
  if type(name) ~= "string" or type(id) ~= "number" then return nil end
  -- `into` is the scanners' scratch row. They look at one aura at a time and keep nothing from
  -- it but a few numbers, so handing them the same table forty times is the same answer with
  -- none of the litter: a unit with ten buffs used to cost eleven tables per scan, and a scan
  -- happens up to six times a second per unit. Callers that keep what they are given -- the
  -- public Aura.Read below, and the tests through it -- pass nothing and get a fresh row.
  local row = into or {}
  row.name = name
  row.id = id
  row.duration = tonumber(duration) or 0
  row.expires = tonumber(expires) or 0
  row.source = source
  row.stacks = tonumber(stacks) or 0
  return row
end

-- Every aura on a unit, as a list. Stops at the first row the game will not give up whole, which
-- is the same rule the roster scan uses: a partial list proves nothing.
local function readAuras(unit, filter)
  local out = {}
  for i = 1, 40 do
    local a = auraAt(unit, i, filter)
    if not a then break end
    out[#out + 1] = a
  end
  return out
end
Aura.Read = readAuras

local function secondsLeft(a)
  if not a or a.expires == nil or a.expires <= 0 then return nil end
  local left = a.expires - GetTime()
  if left < 0 then return 0 end
  return left
end

--------------------------------------------------------------------------------
-- Calling it
--------------------------------------------------------------------------------

local lastCall, saidAt = 0, {}

-- Could a call come out of a scan started right now? announce() asks the same two questions
-- again before it says anything, which is where lastCall is set and where the authority lives;
-- this is only here so that a scan with no possible outcome can be skipped before it costs
-- forty trips into the client.
local function canCall()
  local o = opts()
  if not (o.on and o.aura) then return false end
  return GetTime() - lastCall >= CALL_GAP
end
Aura.CanCall = canCall

local function announce(kind, words, line, clip, weight)
  local o = opts()
  if not (o.on and o.aura) then return false end
  local now = GetTime()
  if now - lastCall < CALL_GAP then return false end
  lastCall = now

  if ns.Hype and ns.Hype.Sfx then
    pcall(ns.Hype.Sfx, kind == "offence" and "heartbeat" or (kind == "cc" and "powerdown" or "gong"))
  end
  if ns.Stage and ns.Stage.Banner then
    pcall(ns.Stage.Banner, words, colour(kind), line, { size = kind == "offence" and 3 or 2 })
  end
  -- The voice is optional: a pack that has no clip for this is simply silent, and the banner
  -- carries the moment on its own until the clip is built.
  if clip and ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, clip, weight or 2) end
  return true
end

-- Has this exact aura on this exact unit already been called recently?
local function fresh(key)
  local now = GetTime()
  if saidAt[key] and now - saidAt[key] < SAME_GAP then return false end
  saidAt[key] = now
  -- the table is small by nature (what is on two units) but a long session in a battleground
  -- can still fill it, so it is swept rather than grown
  local n = 0
  for _ in pairs(saidAt) do n = n + 1 end
  if n > 200 then
    for k, t in pairs(saidAt) do if now - t > GONE_AFTER then saidAt[k] = nil end end
  end
  return true
end

local function casterName(a)
  local unit = a.source
  if type(unit) ~= "string" then return nil end
  local name = ns.FullName and ns.FullName(unit)
  if type(name) ~= "string" or name == "" then return nil end
  return name
end

--------------------------------------------------------------------------------
-- Diminishing returns, by measurement
--------------------------------------------------------------------------------

-- What you cast last, waiting for its aura to appear so the duration can be read.
local pendingCast          -- { name, cat, at, guid }
local liveCC = {}          -- [guid] = { [cat] = { at = , duration = , n = } }

local function drStore()
  local db = GodslayerDB
  if type(db) ~= "table" then return nil end
  db.dr = type(db.dr) == "table" and db.dr or {}
  return db.dr
end

-- Record one landing: how long the game gave it, and how long since the last one of its category
-- on the same target. Both halves matter, because the window is as unknown as the steps.
function Aura.NoteLanding(guid, group, duration, spell)
  if type(guid) ~= "string" or type(group) ~= "number" then return false end
  local cat = group
  duration = tonumber(duration)
  if not duration or duration <= 0 then return false end

  local now = GetTime()
  liveCC[guid] = liveCC[guid] or {}
  local prev = liveCC[guid][cat]
  local gap, n = nil, 1
  if prev and now - prev.at <= DR_WINDOW then
    gap = now - prev.at
    n = (prev.n or 1) + 1
  end
  liveCC[guid][cat] = { at = now, duration = duration, n = n, full = (n == 1) and duration or (prev and prev.full or duration) }

  local store = drStore()
  if not store then return false end
  store[cat] = type(store[cat]) == "table" and store[cat] or {}
  local rows = store[cat]
  rows[#rows + 1] = {
    d = math.floor(duration * 100 + 0.5) / 100,
    n = n,
    g = gap and (math.floor(gap * 10 + 0.5) / 10) or nil,
    f = (n > 1) and liveCC[guid][cat].full or nil,
    s = spell,
    t = time(),
  }
  while #rows > DR_KEEP do table.remove(rows, 1) end

  -- Second and later applications are the interesting ones: say what actually happened.
  if n > 1 then
    local full = liveCC[guid][cat].full
    local share = full and full > 0 and (duration / full) or nil
    if share and share < 0.95 then
      announce("cc", "DIMINISHED",
        ("%s only lasted %.1fs, %d%% of the first"):format(spell or groupLabel(group), duration, math.floor(share * 100 + 0.5)))
    elseif group == 0 and ns.Log then
      -- The client said this one never diminishes and it did not. Worth nothing on its own, but
      -- the opposite result would mean the client's table is wrong.
      ns.Log("dr", (spell or "?") .. " held full length, as the client's table says it should")
    end
    if ns.Log then ns.Log("dr", ("%s #%d %.1fs of %.1fs after %.1fs"):format(groupLabel(group), n, duration, full or 0, gap or 0)) end
  end
  return true
end

-- What has been learned so far, as rows ready to print: category, how many landings, and the
-- median length of the first, second and third in a row.
function Aura.DRTable()
  local store = drStore()
  local out = {}
  if not store then return out end
  for cat, rows in pairs(store) do
    local byN, total = {}, 0
    for _, r in ipairs(rows) do
      local n = math.min(tonumber(r.n) or 1, 4)
      byN[n] = byN[n] or {}
      byN[n][#byN[n] + 1] = r.d
      total = total + 1
    end
    local row = { group = tonumber(cat) or 0, label = groupLabel(tonumber(cat) or 0), total = total, steps = {} }
    for n = 1, 4 do
      local list = byN[n]
      if list and #list > 0 then
        table.sort(list)
        local mid = list[math.ceil(#list / 2)]
        row.steps[n] = { median = mid, count = #list }
      end
    end
    -- The share each step kept of the first, which is the DR curve this server actually has.
    local first = row.steps[1] and row.steps[1].median
    if first and first > 0 then
      for n = 2, 4 do
        if row.steps[n] then row.steps[n].share = row.steps[n].median / first end
      end
    end
    out[#out + 1] = row
  end
  table.sort(out, function(a, b) return a.total > b.total end)
  return out
end

-- The gap after which this server appears to forget, taken from the longest gap that still
-- produced a shortened aura. Returns nil until there is something to go on.
function Aura.DRWindow()
  local store = drStore()
  if not store then return nil end
  local widest, narrowestFull = 0, nil
  for _, rows in pairs(store) do
    for _, r in ipairs(rows) do
      local gap, full, d = tonumber(r.g), tonumber(r.f), tonumber(r.d)
      if gap and full and d then
        if d < full * 0.95 then
          if gap > widest then widest = gap end
        elseif not narrowestFull or gap < narrowestFull then
          narrowestFull = gap
        end
      end
    end
  end
  if widest <= 0 then return nil end
  return widest, narrowestFull
end

--------------------------------------------------------------------------------
-- The scan
--------------------------------------------------------------------------------

local lastScan = {}

-- One row, reused. Nothing here outlives the iteration that reads it.
local row = {}

local function scanPlayer()
  for i = 1, 40 do
    local a = auraAt("player", i, "HARMFUL", row)
    if not a then break end
    local info = CC[english(a.name)]
    if info and fresh("p/" .. a.id) then
      local who = casterName(a)
      local left = secondsLeft(a)
      local line = (who or "Something") .. (left and (" for %.0fs"):format(left) or "")
      announce("cc", CC_WORDS[info.cat] or "CONTROLLED", line, "cc_" .. info.cat, 2)
      -- Time spent unable to act is worth counting: it is the real cost of a bad position.
      local c = ns.char
      if c and left and left > 0 then
        c.ccSeconds = (c.ccSeconds or 0) + left
        c.ccCount = (c.ccCount or 0) + 1
      end
    end
  end
end

-- Which of two things worth saying about an enemy wins. A constant, and it used to be built
-- fresh inside the scan below -- one table per aura event, for four fixed numbers.
local RANK = { offence = 4, immune = 3, gone = 2, soak = 1 }

-- An enemy unit: their defence, their offence, and the aura a cast of yours just produced.
local function scanEnemy(unit)
  local guid = plain(try(UnitGUID, unit))
  if type(guid) ~= "string" then return end
  if not plain(try(UnitIsPlayer, unit)) then return end
  if not plain(try(UnitCanAttack, "player", unit)) then return end

  -- Reading forty aura slots to decide what to say is pointless while nothing may be said. Two
  -- calls ago is the whole of it: announce() refuses inside CALL_GAP and the scan would have
  -- thrown the answer away. This is the one throttle in the file that saves real work rather
  -- than real noise -- the profiler had this scan at twenty-six trips into the client per aura
  -- event, and the window it skips is two full seconds wide.
  --
  -- The landing check below is deliberately outside it. That one feeds the diminishing-returns
  -- table and never says anything, so a quiet announcer must not blind it.
  if canCall() then
    local name = ns.FullName and ns.FullName(unit) or nil

    -- Everything they have is read first and then one thing is said, because the calls are
    -- throttled: announcing whichever aura the game happened to list first meant a Shield Wall
    -- could talk over the Recklessness that was about to kill you.
    local bestKind, bestWords, bestNote, bestId, bestLeft
    for i = 1, 40 do
      local a = auraAt(unit, i, "HELPFUL", row)
      if not a then break end
      local key = english(a.name)
      local def, off = DEFENCE[key], OFFENCE[key]
      local kind, words, note
      if off then kind, words, note = "offence", off.words, off.note
      elseif def then kind, words, note = def.kind, def.words, def.note end
      if kind and (not bestKind or RANK[kind] > RANK[bestKind]) then
        bestKind, bestWords, bestNote, bestId, bestLeft = kind, words, note, a.id, secondsLeft(a)
      end
    end
    if bestKind and fresh(guid .. "/" .. bestKind .. "/" .. bestId) then
      local digits = (bestKind == "offence") and "%.0f" or "%.1f"
      announce(bestKind, bestWords,
        (name or "They") .. (bestLeft and (" for " .. digits .. "s"):format(bestLeft) or "") ..
          (bestNote and ("    " .. bestNote) or ""),
        bestKind == "offence" and "offence" or (bestKind == "immune" and "immune" or nil),
        bestKind == "offence" and 3 or 2)
    end
  end

  -- Did the crowd control you just cast land on this unit? If so the game will say how long for.
  if pendingCast and pendingCast.guid == guid and GetTime() - pendingCast.at < 3 then
    for i = 1, 40 do
      local a = auraAt(unit, i, "HARMFUL", row)
      if not a then break end
      if english(a.name) == pendingCast.name and a.duration > 0 then
        Aura.NoteLanding(guid, pendingCast.group, a.duration, pendingCast.name)
        pendingCast = nil
        break
      end
    end
  end
end

-- Is this unit worth reading again yet?
local function due(unit)
  local now = GetTime()
  if lastScan[unit] and now - lastScan[unit] < SCAN_GAP then return false end
  lastScan[unit] = now
  return true
end

function Aura.Scan(unit)
  if type(unit) ~= "string" or not due(unit) then return end
  if unit == "player" then return scanPlayer() end
  if plain(try(UnitExists, unit)) then scanEnemy(unit) end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Aura.handlers

function h.UNIT_AURA(unit)
  unit = plain(unit)
  if type(unit) ~= "string" then return end
  if unit == "player" then return Aura.Scan("player") end
  if unit == "target" or unit == "focus" or unit:sub(1, 9) == "nameplate" then Aura.Scan(unit) end
end

function h.PLAYER_TARGET_CHANGED()
  lastScan.target = nil
  Aura.Scan("target")
end

function h.PLAYER_FOCUS_CHANGED()
  lastScan.focus = nil
  Aura.Scan("focus")
end

-- Your own crowd control, remembered so its duration can be read the moment it appears.
function h.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if plain(unit) ~= "player" then return end
  local id = plain(spellID)
  local name
  if type(id) == "number" then
    name = plain(try(C_Spell and C_Spell.GetSpellName, id))
    if type(name) ~= "string" and type(GetSpellInfo) == "function" then name = plain((try(GetSpellInfo, id))) end
  end
  name = english(name)
  local info = name and CC[name]
  if not info then return end
  local guid = plain(try(UnitGUID, "target"))
  if type(guid) ~= "string" then return end
  pendingCast = { name = name, group = drGroup(name), at = GetTime(), guid = guid }
end

function h.PLAYER_ENTERING_WORLD()
  liveCC, saidAt, lastScan = {}, {}, {}
  pendingCast = nil
end

-- Nothing about a target you walked away from is worth keeping in memory.
function Aura.Sweep()
  local now, dropped = GetTime(), 0
  for guid, cats in pairs(liveCC) do
    local newest = 0
    for _, v in pairs(cats) do if v.at > newest then newest = v.at end end
    if now - newest > GONE_AFTER then liveCC[guid] = nil; dropped = dropped + 1 end
  end
  return dropped
end

function Aura.Init()
  for name, info in pairs(CC) do
    local here = plain(try(C_Spell and C_Spell.GetSpellName, info.id))
    if type(here) == "string" and here ~= name and not CC[here] then alias[here] = name end
  end
  for _, tbl in ipairs({ DEFENCE, OFFENCE }) do
    for name, info in pairs(tbl) do
      local here = plain(try(C_Spell and C_Spell.GetSpellName, info.id))
      if type(here) == "string" and here ~= name and not tbl[here] then alias[here] = name end
    end
  end
  if C_Timer and C_Timer.NewTicker then try(C_Timer.NewTicker, 30, Aura.Sweep) end
end

Aura.alias = alias
