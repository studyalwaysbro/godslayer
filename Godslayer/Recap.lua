-- Godslayer recap: what actually happened, through the one door the combat log left open.
--
-- Every other file in this addon is built around the fact that `COMBAT_LOG_EVENT_UNFILTERED` is
-- gone for addons on this client. No addon here can watch damage fly, which is why Forever has no
-- Recount, no Skada, no Details, and why every number this addon has ever shown has been a kill
-- count rather than a damage figure.
--
-- The engine kept the numbers anyway, and it hands them over. `C_DamageMeter` is a public,
-- documented namespace -- the client ships Blizzard_DamageMeter and the generated documentation
-- for it -- and it gives the aggregate per source and per spell: damage, DPS, healing, absorbs,
-- interrupts, dispels, damage taken, avoidable damage taken, deaths. The combat log was closed;
-- this was opened in its place, and nothing on this realm is reading it.
--
-- WHY THIS IS A RECAP AND NOT A METER. Every session getter in that namespace is marked
-- `SecretWhenInCombat` in the client's own documentation. In combat the numbers come back as
-- secret values, and a secret value cannot be compared, concatenated or added -- `plain()` turns
-- it into nil, which is the honest answer. So the numbers are read when the fight is over. That
-- is the API's rule rather than a choice, and anything claiming a live damage readout on this
-- client is either reading nothing or about to throw.
--
-- The other half of the honesty: if a session comes back with nothing in it, this says the engine
-- had nothing, and does not report a quiet fight. `C_DamageMeter.IsDamageMeterAvailable` returns
-- its own failure reason, and Blizzard's own window additionally wants the `damageMeterEnabled`
-- CVar, so there are states where there is genuinely no data to have.
--
--   /godslayer recap        the last fight, and what it cost each side
--   /godslayer recap <n>    one of the fights before it

local _, ns = ...
local plain, try = ns.plain, ns.try

local Recap = { handlers = {} }
ns.Recap = Recap

local KEEP = 25            -- fights kept in the book
local HURT_CAP = 300       -- players whose damage to you is remembered
local CALL_GAP = 4
local SHARE_WORTH = 0.25   -- a spell has to be at least this much of the total to be worth saying
local AMBER, RED, BLUE = { 1, 0.8, 0.2 }, { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }

-- The enum values, read from the client when it has them. Hardcoded fallbacks are the documented
-- numbers for this build, so a missing Enum table degrades to the right integers instead of nil.
local function E(group, name, fallback)
  local t = Enum and Enum[group]
  local v = t and t[name]
  return (type(v) == "number") and v or fallback
end
local function TYPE(name, fallback) return E("DamageMeterType", name, fallback) end
local function SESSION(name, fallback) return E("DamageMeterSessionType", name, fallback) end

local TYPE_FALLBACK = { DamageDone = 0, Dps = 1, HealingDone = 2, Hps = 3, Absorbs = 4,
  Interrupts = 5, Dispels = 6, DamageTaken = 7, AvoidableDamageTaken = 8, Deaths = 9,
  EnemyDamageTaken = 10 }
local SESSION_FALLBACK = { Overall = 0, Current = 1, Expired = 2 }

-- Looked up once each and then kept: the answer cannot change inside a session, and these are
-- read on every fight.
local function lazy(group, fallback)
  return setmetatable({}, { __index = function(t, k)
    local v = E(group, k, fallback[k])
    rawset(t, k, v)
    return v
  end })
end
Recap.TYPES = lazy("DamageMeterType", TYPE_FALLBACK)
Recap.SESSIONS = lazy("DamageMeterSessionType", SESSION_FALLBACK)

local function ENEMY() return E("DamageMeterSourceDisplayType", "Enemy", 2) end
local function ALLY() return E("DamageMeterSourceDisplayType", "Ally", 1) end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

-- A number the client was willing to give us, or nil. A secret value is nil here, and nil is
-- never silently turned into zero: "we were not told" and "it was nothing" are different answers.
local function num(v)
  v = plain(v)
  return (type(v) == "number") and v or nil
end

local function str(v)
  v = plain(v)
  return (type(v) == "string" and v ~= "") and v or nil
end

function Recap.Available()
  if not C_DamageMeter then return false, "this client has no damage meter" end
  local ok, why = try(C_DamageMeter.IsDamageMeterAvailable)
  ok, why = plain(ok), str(why)
  if ok == nil then return false, "the client would not say whether the meter is available" end
  if ok == false then return false, why or "the meter is not available here" end
  return true
end

-- Whether a read is even worth attempting. In combat every one of these getters returns secret
-- values, so asking is pointless rather than merely unreliable.
function Recap.Sealed()
  if plain(try(InCombatLockdown)) == true then return true end
  if plain(try(UnitAffectingCombat, "player")) == true then return true end
  return false
end

-- One session, flattened into rows we are allowed to hold. Returns nil and a reason rather than
-- an empty table, so a caller can tell "no data" from "nobody did anything".
function Recap.Session(kind, which)
  local ok, why = Recap.Available()
  if not ok then return nil, why end
  if Recap.Sealed() then return nil, "the numbers are secret while you are in combat" end
  local get = C_DamageMeter.GetCombatSessionFromType
  local s = plain(try(get, which or Recap.SESSIONS.Current, kind))
  if type(s) ~= "table" then return nil, "the engine has no session of that kind" end

  local out = { total = num(s.totalAmount) or 0, max = num(s.maxAmount) or 0,
                duration = num(s.durationSeconds), rows = {} }
  local sources = s.combatSources
  if type(sources) ~= "table" then return out end
  for i = 1, #sources do
    local src = sources[i]
    if type(src) == "table" then
      local amount = num(src.totalAmount)
      if amount then
        out.rows[#out.rows + 1] = {
          guid = str(src.sourceGUID),
          name = str(src.name),
          class = str(src.classFilename),
          amount = amount,
          ps = num(src.amountPerSecond) or 0,
          mine = plain(src.isLocalPlayer) == true,
          side = num(src.sourceDisplayType),
          faction = str(src.factionGroup),
          died = (num(src.deathTimeSeconds) or 0) > 0 or nil,
          classification = str(src.classification),
        }
      end
    end
  end
  table.sort(out.rows, function(a, b) return a.amount > b.amount end)
  return out
end

-- The spells behind one row. `creatureName` on a spell is the client's own attribution of who
-- cast it, which is the only attacker name available once the combat log is shut.
function Recap.Spells(kind, guid, which)
  local ok, why = Recap.Available()
  if not ok then return nil, why end
  if Recap.Sealed() then return nil, "the numbers are secret while you are in combat" end
  local get = C_DamageMeter.GetCombatSessionSourceFromType
  local s = plain(try(get, which or Recap.SESSIONS.Current, kind, guid))
  if type(s) ~= "table" then return nil, "the engine has nothing for that unit" end
  local out = { total = num(s.totalAmount) or 0, max = num(s.maxAmount) or 0, rows = {} }
  local spells = s.combatSpells
  if type(spells) ~= "table" then return out end
  for i = 1, #spells do
    local sp = spells[i]
    if type(sp) == "table" then
      local amount = num(sp.totalAmount)
      local id = num(sp.spellID)
      if amount then
        out.rows[#out.rows + 1] = {
          id = id,
          spell = (id and ns.PVP_BY_ID and ns.PVP_BY_ID[id])
                  or str(plain(try(C_Spell and C_Spell.GetSpellName, id)))
                  or (id and ("spell " .. id)) or "something",
          amount = amount,
          ps = num(sp.amountPerSecond) or 0,
          overkill = num(sp.overkillAmount) or 0,
          avoidable = plain(sp.isAvoidable) == true,
          deadly = plain(sp.isDeadly) == true,
          by = str(sp.creatureName),
        }
      end
    end
  end
  table.sort(out.rows, function(a, b) return a.amount > b.amount end)
  return out
end

function Recap.Mine(kind, which)
  local s = Recap.Session(kind, which)
  if not s then return nil end
  for _, row in ipairs(s.rows) do if row.mine then return row, s end end
  return nil, s
end

--------------------------------------------------------------------------------
-- Numbers people can read
--------------------------------------------------------------------------------

function Recap.Short(n)
  n = tonumber(n)
  if not n then return "?" end
  if n < 0 then n = 0 end
  if n >= 1000000 then return ("%.1fm"):format(n / 1000000) end
  if n >= 10000 then return ("%dk"):format(math.floor(n / 1000 + 0.5)) end
  if n >= 1000 then return ("%.1fk"):format(n / 1000) end
  return tostring(math.floor(n + 0.5))
end

-- Thousands separators, done by hand because the client's own formatter is not guaranteed here.
function Recap.Comma(n)
  n = math.floor((tonumber(n) or 0) + 0.5)
  local s = tostring(n)
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  return (out:gsub("^,", ""))
end

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.recap = type(d.recap) == "table" and d.recap or {}
  local r = d.recap
  r.log = type(r.log) == "table" and r.log or {}
  r.hurt = type(r.hurt) == "table" and r.hurt or {}
  return r
end
Recap.DB = db

-- How much this player has ever done to you, across every fight the engine would talk about.
function Recap.Hurt(guid)
  local r = db()
  if not r or type(guid) ~= "string" then return nil end
  local row = r.hurt[guid]
  if not row then return nil end
  return row.d or 0, row.n or 0, row.name
end

local function noteHurt(guid, name, amount)
  local r = db()
  if not r or type(guid) ~= "string" or not amount or amount <= 0 then return end
  local row = r.hurt[guid]
  if not row then row = { d = 0, n = 0 } r.hurt[guid] = row end
  row.d, row.n, row.t = row.d + amount, row.n + 1, time()
  if name then row.name = name end

  local count = 0
  for _ in pairs(r.hurt) do count = count + 1 end
  if count > HURT_CAP then
    local keys = {}
    for k, v in pairs(r.hurt) do keys[#keys + 1] = { k, v.t or 0 } end
    table.sort(keys, function(a, b) return a[2] < b[2] end)
    for i = 1, count - HURT_CAP do r.hurt[keys[i][1]] = nil end
  end
end

--------------------------------------------------------------------------------
-- The fight that just ended
--------------------------------------------------------------------------------

-- Everything worth keeping about one fight, read once, out of combat.
function Recap.Build(which)
  local ok, why = Recap.Available()
  if not ok then return nil, why end
  which = which or Recap.SESSIONS.Current

  local T = Recap.TYPES
  local done, doneWhy = Recap.Session(T.DamageDone, which)
  if not done then return nil, doneWhy end

  local card = { at = time(), zone = ns.clean and ns.clean(plain(try(GetRealZoneText)), 40) or nil }
  card.duration = done.duration
  local mine = nil
  for _, row in ipairs(done.rows) do if row.mine then mine = row break end end
  card.damage = mine and mine.amount or 0
  card.dps = mine and mine.ps or 0
  card.myGuid = mine and mine.guid or nil

  -- Who on the other side did what, and who it was done to you by.
  card.enemies = {}
  for _, row in ipairs(done.rows) do
    if not row.mine and row.side == ENEMY() then
      card.enemies[#card.enemies + 1] = { name = row.name, class = row.class, amount = row.amount }
    end
  end

  local taken = Recap.Session(T.DamageTaken, which)
  if taken then
    for _, row in ipairs(taken.rows) do
      if row.mine then card.taken = row.amount break end
    end
  end
  local healed = Recap.Session(T.HealingDone, which)
  if healed then
    for _, row in ipairs(healed.rows) do
      if row.mine then card.healed = row.amount break end
    end
  end
  local avoidable = Recap.Session(T.AvoidableDamageTaken, which)
  if avoidable then
    for _, row in ipairs(avoidable.rows) do
      if row.mine then card.avoidable = row.amount break end
    end
  end

  -- Your own best spell, and its share of everything you did.
  local guid = card.myGuid or plain(try(UnitGUID, "player"))
  local hits
  if guid then
    local spells = Recap.Spells(T.DamageDone, guid, which)
    if spells and spells.rows[1] then
      local top = spells.rows[1]
      card.top = { spell = top.spell, amount = top.amount, overkill = top.overkill,
                   share = (card.damage > 0) and (top.amount / card.damage) or nil }
    end
    -- What hit you, and what finished the job if anything did. Read once: this is the
    -- expensive call, and the per-attacker totals below come out of the same rows.
    hits = Recap.Spells(T.DamageTaken, guid, which)
    if hits then
      card.hits = {}
      for i = 1, math.min(#hits.rows, 5) do
        local row = hits.rows[i]
        card.hits[i] = { spell = row.spell, amount = row.amount, by = row.by, avoidable = row.avoidable or nil }
        if row.deadly and not card.killer then
          card.killer = { spell = row.spell, by = row.by, amount = row.amount }
        end
      end
      if not card.killer then
        for _, row in ipairs(hits.rows) do
          if row.deadly then card.killer = { spell = row.spell, by = row.by, amount = row.amount } break end
        end
      end
    end
  end

  -- What each of them personally put into you. Their own `totalAmount` is everything they did
  -- to everyone, so it is the damage-taken rows that get attributed, never their total.
  if hits then
    local byWho = {}
    for _, row in ipairs(hits.rows) do
      if row.by then byWho[row.by] = (byWho[row.by] or 0) + row.amount end
    end
    for _, row in ipairs(done.rows) do
      if not row.mine and row.side == ENEMY() and row.guid and row.name and byWho[row.name] then
        noteHurt(row.guid, row.name, byWho[row.name])
      end
    end
    card.byWho = byWho
  end

  return card
end

local lastCall = 0

-- One line, after a fight, about the thing that decided it. Never two.
local function call(card)
  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.on == false or o.recap == false then return false end
  if GetTime() - lastCall < CALL_GAP then return false end

  local title, color, line
  if card.killer then
    title = card.killer.spell:upper()
    color = RED
    line = (card.killer.by and (card.killer.by .. "    ") or "")
         .. Recap.Comma(card.killer.amount) .. " and that was the one"
  elseif card.top and card.top.share and card.top.share >= SHARE_WORTH and card.damage > 0 then
    title = card.top.spell:upper()
    color = AMBER
    line = ("%s    %d%% of everything you did"):format(Recap.Comma(card.top.amount),
      math.floor(card.top.share * 100 + 0.5))
  else
    return false
  end

  lastCall = GetTime()
  if ns.Stage and ns.Stage.Banner then pcall(ns.Stage.Banner, title, color, line, { size = 2 }) end
  if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, card.killer and "powerdown" or "stamp") end
  return true
end

-- Combat ended, so now the numbers are readable.
local handlers = Recap.handlers

function handlers.PLAYER_REGEN_ENABLED()
  local wasPvP = (ns.Hype and ns.Hype.InPvP and ns.Hype.InPvP()) or false
  -- Read on the next frame: the engine closes the session on the same event, and reading inside
  -- the handler can catch it still marked in combat and hand back secrets.
  local after = C_Timer and C_Timer.After
  local function read()
    local card, why = Recap.Build()
    if not card then
      if ns.Log then ns.Log("recap", "no session: " .. tostring(why)) end
      return
    end
    if (card.damage or 0) <= 0 and (card.taken or 0) <= 0 then return end
    local r = db()
    if r then
      card.pvp = wasPvP or nil
      r.last = card
      r.log[#r.log + 1] = card
      while #r.log > KEEP do table.remove(r.log, 1) end
    end
    if wasPvP then call(card) end
  end
  if type(after) == "function" then try(after, 0.5, read) else read() end
end

--------------------------------------------------------------------------------
-- Showing it
--------------------------------------------------------------------------------

function Recap.Lines(card)
  if type(card) ~= "table" then return nil end
  local out = {}
  local when = plain(try(date, "%H:%M", card.at))
  out[#out + 1] = ("Last fight%s%s:"):format(
    card.zone and (" in " .. card.zone) or "",
    (type(when) == "string") and (" at " .. when) or "")
  out[#out + 1] = ("  You dealt %s%s, took %s%s."):format(
    Recap.Comma(card.damage or 0),
    (card.dps and card.dps > 0) and (" at " .. Recap.Comma(card.dps) .. " dps") or "",
    Recap.Comma(card.taken or 0),
    (card.healed and card.healed > 0) and (", healed " .. Recap.Comma(card.healed)) or "")
  if card.top then
    out[#out + 1] = ("  Most of it was %s: %s%s."):format(card.top.spell, Recap.Comma(card.top.amount),
      card.top.share and (", " .. math.floor(card.top.share * 100 + 0.5) .. "% of your damage") or "")
  end
  if card.avoidable and card.avoidable > 0 then
    out[#out + 1] = ("  %s of what hit you was avoidable."):format(Recap.Comma(card.avoidable))
  end
  if card.killer then
    out[#out + 1] = ("  What killed you: %s%s, for %s."):format(card.killer.spell,
      card.killer.by and (" from " .. card.killer.by) or "", Recap.Comma(card.killer.amount))
  end
  if card.hits and #card.hits > 0 then
    local parts = {}
    for i = 1, math.min(#card.hits, 3) do
      parts[#parts + 1] = card.hits[i].spell .. " " .. Recap.Short(card.hits[i].amount)
    end
    out[#out + 1] = "  Hit hardest by: " .. table.concat(parts, ", ") .. "."
  end
  if card.enemies and #card.enemies > 0 then
    local parts = {}
    table.sort(card.enemies, function(a, b) return a.amount > b.amount end)
    for i = 1, math.min(#card.enemies, 3) do
      parts[#parts + 1] = (card.enemies[i].name or "someone") .. " " .. Recap.Short(card.enemies[i].amount)
    end
    out[#out + 1] = "  They dealt: " .. table.concat(parts, ", ") .. "."
  end
  return out
end

function Recap.Command(rest)
  local ok, why = Recap.Available()
  if not ok then
    ns.Print("No recap: " .. tostring(why) .. ".")
    ns.Print("The damage meter is the engine's own. If it is off, /console damageMeterEnabled 1 turns it on.")
    return
  end
  local r = db()
  local n = tonumber((rest or ""):match("%d+"))
  local card = r and r.last
  if n and r then
    card = r.log[#r.log - n + 1]
    if not card then
      ns.Print(("I only have %d fight%s in the book."):format(#r.log, #r.log == 1 and "" or "s"))
      return
    end
  end
  if not card then
    ns.Print("Nothing in the book yet. Finish a fight and ask again.")
    return
  end
  for _, line in ipairs(Recap.Lines(card) or {}) do ns.Print(line) end
  if r and #r.log > 1 and not n then
    ns.Print(("%d fights kept. /godslayer recap 2 for the one before this."):format(#r.log))
  end
end

function Recap.Init()
  local ok, why = Recap.Available()
  if not ok and ns.Log then ns.Log("recap", "unavailable: " .. tostring(why)) end
end
