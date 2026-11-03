-- Godslayer ledger: what they have left.
--
-- The question that decides whether you commit is never "how much health do they have". It is
-- "is the bubble up". Nothing in the game tells you, and with the combat log shut an addon cannot
-- watch spells fly. But `UNIT_SPELLCAST_SUCCEEDED` fires for any unit you can see, nameplates
-- included, and Core already listens for it unfiltered: every cooldown an enemy spends in front of
-- you is observable, and nobody was writing it down.
--
-- So this writes it down, per player, for good. Target someone you fought ten minutes ago and the
-- ledger knows their Ice Block has two minutes left on it.
--
-- SHARED GROUPS ARE THE PART EVERYONE GETS WRONG. The client sorts spells into cooldown
-- categories, and casting any spell in a category locks the whole category. Divine Shield, Divine
-- Protection and Ice Block are all category 37, so a paladin who bubbles has spent Divine
-- Protection too. The three shocks are category 19 at six seconds, which is the shaman lockout
-- people have known about for twenty years and no addon on this client reads from the data. The
-- lock is the casting spell's own category cooldown, not one number per group: Power Word: Shield
-- locks category 56 for four seconds and Lay on Hands locks the same group for twenty minutes.
--
-- Every number comes from Pvp.lua, which is generated from this build. None of it is vanilla's.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Ledger = { handlers = {} }
ns.Ledger = Ledger

local NOTABLE = 30          -- a cooldown shorter than this is not worth a line on the card
local MAJOR = 120           -- at or above this it decides the fight, and gets called out loud
local KEEP_PLAYERS = 300    -- players remembered before the least recently seen are dropped
local FORGET_AFTER = 30 * 86400
local CALL_GAP = 3

-- Seconds a cast of this spell is unavailable for, and the category it locks on the way.
-- `cd` is the spell's own, `catCd` is what casting it does to its whole group; a spell can have
-- one, the other, or both, and the longer of the two is what you actually wait.
local function spellInfo(name)
  local row = ns.PVP and ns.PVP[name]
  if not row then return nil end
  local own = tonumber(row.cd) or 0
  local cat = tonumber(row.cat) or 0
  local catCd = tonumber(row.catCd) or 0
  local wait = own > catCd and own or catCd
  if wait <= 0 then return nil end
  return { wait = wait, cat = cat, catCd = catCd, own = own, catName = row.catName }
end
Ledger.SpellInfo = spellInfo

-- Every spell that shares `cat`, so a lock can be reported against the ones you care about.
local sharers
local function inCategory(cat)
  if not cat or cat == 0 then return {} end
  if not sharers then
    sharers = {}
    for name, row in pairs(ns.PVP or {}) do
      local c = tonumber(row.cat) or 0
      if c > 0 then
        sharers[c] = sharers[c] or {}
        sharers[c][#sharers[c] + 1] = name
      end
    end
    for _, list in pairs(sharers) do table.sort(list) end
  end
  return sharers[cat] or {}
end
Ledger.InCategory = inCategory

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

-- Unix time, not GetTime, because a cooldown has to survive a reload and a log out.
local function store()
  local db = GodslayerDB
  if type(db) ~= "table" then return nil end
  db.cds = type(db.cds) == "table" and db.cds or {}
  return db.cds
end

local function record(guid, create)
  local s = store()
  if not s or type(guid) ~= "string" then return nil end
  local r = s[guid]
  if not r and create then
    r = { spells = {}, cats = {} }
    s[guid] = r
  end
  return r
end

-- The ledger is a record of fights, so it is allowed to grow; it is not allowed to grow forever.
function Ledger.Prune(now)
  now = now or time()
  local s = store()
  if not s then return 0 end
  local dropped, names = 0, {}
  for guid, r in pairs(s) do
    if not r.t or now - r.t > FORGET_AFTER then
      s[guid] = nil
      dropped = dropped + 1
    else
      names[#names + 1] = { guid = guid, t = r.t }
    end
  end
  if #names > KEEP_PLAYERS then
    table.sort(names, function(a, b) return a.t < b.t end)
    for i = 1, #names - KEEP_PLAYERS do
      s[names[i].guid] = nil
      dropped = dropped + 1
    end
  end
  return dropped
end

--------------------------------------------------------------------------------
-- Writing it down
--------------------------------------------------------------------------------

local lastCall = 0

-- One cast by one enemy. Returns the info if it was worth recording.
function Ledger.Note(guid, who, spell, class, at)
  if type(guid) ~= "string" or type(spell) ~= "string" then return nil end
  local info = spellInfo(spell)
  if not info then return nil end

  at = at or time()
  local r = record(guid, true)
  if not r then return nil end
  r.t = at
  if type(who) == "string" and who ~= "" then r.n = who end
  if type(class) == "string" then r.c = class end
  r.spells[spell] = at
  -- The category lock carries the casting spell's own number, which is the whole subtlety.
  if info.cat > 0 and info.catCd > 0 then
    local cur = r.cats[info.cat]
    local until_ = at + info.catCd
    if not cur or cur.until_ < until_ then r.cats[info.cat] = { until_ = until_, by = spell } end
  end
  if ns.Log then ns.Log("ledger", (who or guid) .. " spent " .. spell .. " (" .. info.wait .. "s)") end
  return info
end

-- Seconds before they can do that again, 0 when it is ready. The second return says whether the
-- wait is their own cooldown or a group one, and the third names the spell that locked the group.
function Ledger.Left(guid, spell, now)
  now = now or time()
  local r = record(guid)
  local info = spellInfo(spell)
  if not r or not info then return 0 end

  local left, why, by = 0, nil, nil
  local castAt = r.spells[spell]
  if castAt and info.own > 0 then
    local own = info.own - (now - castAt)
    if own > left then left, why = own, "its own cooldown" end
  end
  -- Their own cast of this spell also locked its group, so a spell never cast can still be down.
  local lock = info.cat > 0 and r.cats[info.cat]
  if lock then
    local shared = lock.until_ - now
    if shared > left then left, why, by = shared, "the " .. (info.catName or "shared") .. " group", lock.by end
  end
  if left < 0 then left = 0 end
  return left, why, by
end

function Ledger.Ready(guid, spell, now)
  return Ledger.Left(guid, spell, now) <= 0
end

--------------------------------------------------------------------------------
-- The card
--------------------------------------------------------------------------------

-- What is worth saying about this player, longest wait first. Only spells they have actually been
-- seen to cast, or that a group lock covers: the ledger never guesses at a kit it has not watched.
function Ledger.Card(guid, now)
  now = now or time()
  local r = record(guid)
  local out = { name = r and r.n, class = r and r.c, rows = {} }
  if not r then return out end

  local seen = {}
  for spell in pairs(r.spells) do seen[spell] = true end
  for cat, lock in pairs(r.cats) do
    if lock.until_ > now then
      for _, spell in ipairs(inCategory(cat)) do seen[spell] = true end
    end
  end

  for spell in pairs(seen) do
    local info = spellInfo(spell)
    if info and info.wait >= NOTABLE then
      local left, why, by = Ledger.Left(guid, spell, now)
      out.rows[#out.rows + 1] = {
        spell = spell, left = left, why = why, by = by,
        major = info.wait >= MAJOR,
        ready = left <= 0,
      }
    end
  end
  table.sort(out.rows, function(a, b)
    if a.major ~= b.major then return a.major end
    if (a.left > 0) ~= (b.left > 0) then return a.left > 0 end
    if a.left ~= b.left then return a.left > b.left end
    return a.spell < b.spell
  end)
  return out
end

-- One line for chat or a tooltip: the majors that are down, or that they are all up.
function Ledger.Line(guid, now)
  local card = Ledger.Card(guid, now)
  local down, up = {}, 0
  for _, row in ipairs(card.rows) do
    if row.major then
      if row.ready then up = up + 1
      else down[#down + 1] = ("%s %s"):format(row.spell, Ledger.Short(row.left)) end
    end
  end
  if #down == 0 and up == 0 then return nil end
  if #down == 0 then return "everything they have shown you is up" end
  return table.concat(down, ", ")
end

function Ledger.Short(seconds)
  seconds = math.floor((seconds or 0) + 0.5)
  if seconds <= 0 then return "up" end
  if seconds < 60 then return seconds .. "s" end
  local m = math.floor(seconds / 60)
  local s = seconds % 60
  if m < 60 then return s > 0 and (m .. "m" .. s .. "s") or (m .. "m") end
  return math.floor(m / 60) .. "h" .. (m % 60) .. "m"
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Ledger.handlers

local function spellName(id)
  id = plain(id)
  if type(id) ~= "number" then return nil end
  -- The generated table answers without a round trip, and covers the ids we care about.
  local known = ns.PVP_BY_ID and ns.PVP_BY_ID[id]
  if known then return known end
  local name = plain(try(C_Spell and C_Spell.GetSpellName, id))
  if type(name) ~= "string" and type(GetSpellInfo) == "function" then name = plain((try(GetSpellInfo, id))) end
  return type(name) == "string" and name or nil
end

-- A major cooldown with no aura to see is the one worth calling: a Lay on Hands or a Blink leaves
-- nothing on them to read, so without this it happens in silence. Anything Aura already calls is
-- left to Aura, so nothing is said twice.
-- Is this a spell the ledger has a cooldown for? A pure table lookup, exposed so that the
-- handler below can ask before it spends anything on the unit that cast it.
function Ledger.Tracks(spell)
  return type(spell) == "string" and spellInfo(spell) ~= nil
end

local function worthCalling(spell, info)
  if info.wait < MAJOR then return false end
  if ns.Aura then
    if (ns.Aura.DEFENCE and ns.Aura.DEFENCE[spell]) or (ns.Aura.OFFENCE and ns.Aura.OFFENCE[spell]) then return false end
  end
  return true
end

function h.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  unit = plain(unit)
  if type(unit) ~= "string" or unit == "player" or unit == "pet" then return end

  -- The spell is identified before anything is asked about the unit, and that order is the whole
  -- economy of this handler. UNIT_SPELLCAST_SUCCEEDED is registered unfiltered, so in a
  -- battleground it fires for every cast anyone in view completes -- and almost none of them are
  -- spells this file has a cooldown for. Establishing that costs a table lookup. Establishing
  -- that the caster is a hostile player costs six trips into the client, and used to be spent
  -- first, on every Frostbolt and every wand shot on the screen.
  local spell = spellName(spellID)
  if not Ledger.Tracks(spell) then return end

  if not plain(try(UnitExists, unit)) then return end
  if not plain(try(UnitIsPlayer, unit)) then return end
  if not plain(try(UnitCanAttack, "player", unit)) then return end

  local guid = plain(try(UnitGUID, unit))
  if type(guid) ~= "string" then return end

  local _, class = try(UnitClass, unit)
  local info = Ledger.Note(guid, ns.FullName and ns.FullName(unit) or nil, spell, plain(class))
  if not info then return end

  if worthCalling(spell, info) and GetTime() - lastCall >= CALL_GAP then
    local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
    if o.on ~= false and o.aura ~= false then
      lastCall = GetTime()
      local who = (ns.FullName and ns.FullName(unit)) or "They"
      if ns.Stage and ns.Stage.Banner then
        pcall(ns.Stage.Banner, spell:upper(), { 1, 0.55, 0.1 },
          who .. "    back in " .. Ledger.Short(info.wait), { size = 2 })
      end
      if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, "gong") end
    end
  end
end

-- Targeting someone is when you want the answer, so that is when it is offered.
function h.PLAYER_TARGET_CHANGED()
  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.on == false or o.ledger == false then return end
  if not plain(try(UnitExists, "target")) then return end
  if not plain(try(UnitIsPlayer, "target")) then return end
  if not plain(try(UnitCanAttack, "player", "target")) then return end
  local guid = plain(try(UnitGUID, "target"))
  if type(guid) ~= "string" then return end
  local line = Ledger.Line(guid)
  if line and ns.Print then
    ns.Print(((ns.FullName and ns.FullName("target")) or "They") .. ": " .. line)
  end
end

function Ledger.Init()
  Ledger.Prune()
  if C_Timer and C_Timer.NewTicker then try(C_Timer.NewTicker, 600, function() Ledger.Prune() end) end
end
