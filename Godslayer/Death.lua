-- Godslayer death: the combat log, handed back after you die.
--
-- This addon exists in the shape it does because `COMBAT_LOG_EVENT_UNFILTERED` is shut to addons
-- on this client. Every other file here works around that. This one does not have to.
--
-- `C_DeathRecap` is declared `Environment = "All"` and **not one of its four functions carries a
-- secrecy annotation of any kind**. `GetRecapEvents` hands back the last several seconds of your
-- life as combat-log-shaped rows: the event name, the spell, who cast it, how much it did, which
-- school it was, how much of it you absorbed or resisted, your health at that moment, whether it
-- was avoidable, and which one killed you.
--
-- FOREVER DOES HAVE A WINDOW FOR IT, which an earlier version of this header denied:
--
--     Blizzard_DeathRecap/Blizzard_DeathRecap.toc:4
--       [Family]\Blizzard_DeathRecap.lua [AllowLoadGameType mainline]
--     Blizzard_DamageMeter/DamageMeterSessionWindow.lua:969
--       OpenDeathRecapUI(source.deathRecapID);               -- the damage meter's way in
--
-- `mainline` there is a family and camelot is a member of it, so both of those load. The window
-- is real and it is reachable. It is also a window: you open it afterwards, read it, and close
-- it, and it keeps nothing. What follows is the same rows said out loud as you hit the floor,
-- written down across sessions, and pooled with the guild -- which is the part no window does.
--
-- THE ORDER IS BACKWARDS, AND THAT IS THE TRAP. The rows come newest first. The client's own
-- builder is unambiguous about it -- `elementData.causedDeath = i == 1` -- so row one is the
-- killing blow and the last row is the oldest thing still remembered. A reader that assumes
-- chronological order tells you a story about your death that runs the wrong way and names the
-- wrong spell as the one that finished you.
--
-- FOUR MORE THINGS THE DOCUMENTATION WILL NOT TELL YOU. `DeathRecapEventInfo` is in the generated
-- documentation with an **empty field list**, so the names below are not from the API docs at
-- all: they are read off `Blizzard_DeathRecap.lua`, which is the only written record of them.
--
--   * `maxHealth` is not a field. It is a separate call, `GetRecapMaxHealth`, for the whole
--     recap rather than per row.
--   * `timeBeforeDeath` is not a field either. The client computes it as the newest timestamp in
--     the set minus this row's, so it has to be derived here the same way.
--   * `amount` is the gross figure. `overkill`, `absorbed`, `resisted` and `blocked` each come
--     off it, and the client subtracts every one of them in turn to get what actually landed.
--   * a melee swing has no `spellId`. The client substitutes
--     `Constants.DeathRecapConsts.SWING_DAMAGE_SPELL_ID` and the word `ACTION_SWING`, and
--     environmental damage is named from `ACTION_ENVIRONMENTAL_DAMAGE_<TYPE>`.
--
-- `GetRecapLink` is deliberately unused. It makes a chat link that opens a death recap frame, and
-- nobody on this realm has one, so sharing it would be sending guildmates a link that does
-- nothing.
--
--   /godslayer death        the last one, oldest hit first, with the seconds before you died
--   /godslayer death <n>    an earlier one
--   /godslayer death who    what has been killing you, and how much of it was avoidable

local _, ns = ...
local plain, try = ns.plain, ns.try

local Death = { handlers = {} }
ns.Death = Death

local KEEP = 8             -- deaths kept in full
local ROWS = 30            -- rows kept per death
local SHOW = 8             -- rows printed by default
local SWING_ID = 88163     -- the client's stand-in id for a melee swing
local RED, AMBER, BLUE = { 1, 0.19, 0.19 }, { 1, 0.8, 0.2 }, { 0.4, 0.8, 1 }

local function num(v)
  v = plain(v)
  return (type(v) == "number") and v or nil
end

local function str(v)
  v = plain(v)
  return (type(v) == "string" and v ~= "") and v or nil
end

local function swingID()
  local c = _G.Constants
  local v = c and c.DeathRecapConsts and c.DeathRecapConsts.SWING_DAMAGE_SPELL_ID
  return num(v) or SWING_ID
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

function Death.Available()
  if not C_DeathRecap then return false, "this client has no death recap" end
  if type(C_DeathRecap.GetRecapEvents) ~= "function" then return false, "the death recap has no events call" end
  return true
end

function Death.Has(id)
  local ok = Death.Available()
  if not ok then return false end
  return plain(try(C_DeathRecap.HasRecapEvents, id)) == true
end

-- What to call a row. A spell names itself; a swing and a drowning do not, and the client has a
-- word for each of those which is read rather than written out here.
local function label(row)
  local event = str(row.event)
  local spell = str(row.spellName)
  if event == "SWING_DAMAGE" then
    return str(_G.ACTION_SWING) or "Melee", swingID()
  end
  if event == "ENVIRONMENTAL_DAMAGE" then
    local kind = str(row.environmentalType)
    local key = kind and ("ACTION_ENVIRONMENTAL_DAMAGE_" .. kind:upper()) or nil
    return (key and str(_G[key])) or kind or "the world", nil
  end
  local id = num(row.spellId)
  if not spell and id and ns.PVP_BY_ID then spell = ns.PVP_BY_ID[id] end
  if not spell and id then spell = str(plain(try(C_Spell and C_Spell.GetSpellName, id))) end
  return spell or event or "something", id
end

-- One row, reduced. `landed` is what actually got through: the client takes overkill, absorb,
-- resist and block off the gross figure in that order, and so does this.
local function one(row, maxHealth)
  if type(row) ~= "table" then return nil end
  local name, id = label(row)
  local gross = num(row.amount)
  local over, absorbed, resisted, blocked =
    num(row.overkill) or 0, num(row.absorbed) or 0, num(row.resisted) or 0, num(row.blocked) or 0
  local landed = gross
  if landed then landed = landed - over - absorbed - resisted - blocked end
  if landed and landed < 0 then landed = 0 end
  local hp = num(row.currentHP)
  return {
    event = str(row.event),
    spell = name,
    id = id,
    by = str(row.caster),
    amount = gross,
    landed = landed,
    over = (over > 0) and over or nil,
    absorbed = (absorbed > 0) and absorbed or nil,
    resisted = (resisted > 0) and resisted or nil,
    blocked = (blocked > 0) and blocked or nil,
    school = num(row.school),
    at = num(row.timestamp),
    hp = hp,
    pct = (hp and maxHealth and maxHealth > 0) and math.floor(hp / maxHealth * 100) or nil,
    avoidable = plain(row.avoidable) == true or nil,
    deadly = plain(row.deadly) == true or nil,
  }
end

-- The whole recap, turned the right way round. The engine hands these back newest first, so the
-- killing blow is row one on the way in and the last row on the way out.
function Death.Read(id)
  local ok, why = Death.Available()
  if not ok then return nil, why end
  local raw = plain(try(C_DeathRecap.GetRecapEvents, id))
  if type(raw) ~= "table" or #raw == 0 then return nil, "the engine has no recap of that death" end
  local maxHealth = num(try(C_DeathRecap.GetRecapMaxHealth, id))

  -- The newest timestamp in the set is the moment of death, which is how the client gets the
  -- seconds-before-death it shows against each row.
  local died = nil
  for i = 1, #raw do
    local t = num(raw[i] and raw[i].timestamp)
    if t and (not died or t > died) then died = t end
  end

  local rows, worst = {}, nil
  for i = #raw, 1, -1 do        -- backwards, because the engine's order is backwards
    local r = one(raw[i], maxHealth)
    if r then
      r.before = (died and r.at) and (died - r.at) or nil
      r.killed = (i == 1) or nil
      rows[#rows + 1] = r
      -- The client picks its biggest hit by the gross figure. This picks it by what landed,
      -- because a 9000 hit that was 8000 absorbed is not the thing that killed you, and the
      -- question being answered here is what to do differently.
      if (r.landed or 0) > ((worst and worst.landed) or 0) then worst = r end
    end
  end
  if #rows == 0 then return nil, "nothing in that recap could be read" end
  while #rows > ROWS do table.remove(rows, 1) end   -- the oldest go, not the newest

  local card = { at = plain(try(time)), zone = str(try(GetRealZoneText)), maxHealth = maxHealth,
                 rows = rows, worst = worst, fatal = rows[#rows], span = died and rows[1].before or nil }

  -- Who and what, counted across the rows rather than taken from the last one: the spell that
  -- finished you is often not the one that did the work.
  local total, avoidable, byWho = 0, 0, {}
  for i = 1, #rows do
    local r = rows[i]
    total = total + (r.landed or 0)
    if r.avoidable then avoidable = avoidable + (r.landed or 0) end
    if r.by then byWho[r.by] = (byWho[r.by] or 0) + (r.landed or 0) end
  end
  card.total, card.avoidable, card.byWho = total, avoidable, byWho
  local top, topAmount = nil, 0
  for who, amount in pairs(byWho) do
    if amount > topAmount then top, topAmount = who, amount end
  end
  if top then card.killer = { name = top, amount = topAmount } end
  return card
end

--------------------------------------------------------------------------------
-- Keeping it
--------------------------------------------------------------------------------

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.deaths = d.deaths or {}
  d.deaths.log = d.deaths.log or {}
  d.deaths.bySpell = d.deaths.bySpell or {}
  d.deaths.byWho = d.deaths.byWho or {}
  return d.deaths
end

local function record(card)
  local r = db()
  if not r then return end
  r.last = card
  r.log[#r.log + 1] = card
  while #r.log > KEEP do table.remove(r.log, 1) end
  if card.fatal and card.fatal.spell then
    r.bySpell[card.fatal.spell] = (r.bySpell[card.fatal.spell] or 0) + 1
  end
  if card.killer then
    r.byWho[card.killer.name] = (r.byWho[card.killer.name] or 0) + 1
  end
  r.avoidable = (r.avoidable or 0) + (card.avoidable or 0)
  r.taken = (r.taken or 0) + (card.total or 0)
  r.n = (r.n or 0) + 1
end

--------------------------------------------------------------------------------
-- Saying it
--------------------------------------------------------------------------------

local function comma(n)
  if type(n) ~= "number" then return "?" end
  if ns.Recap and ns.Recap.Comma then return ns.Recap.Comma(n) end
  return tostring(math.floor(n + 0.5))
end

local function extras(r)
  local bits = {}
  if r.over then bits[#bits + 1] = comma(r.over) .. " overkill" end
  if r.absorbed then bits[#bits + 1] = comma(r.absorbed) .. " absorbed" end
  if r.resisted then bits[#bits + 1] = comma(r.resisted) .. " resisted" end
  if r.blocked then bits[#bits + 1] = comma(r.blocked) .. " blocked" end
  if #bits == 0 then return nil end
  return table.concat(bits, ", ")
end

function Death.Lines(card, how)
  if type(card) ~= "table" then return nil end
  local out = {}
  local when = plain(try(date, "%H:%M", card.at))
  out[#out + 1] = ("Your death%s%s, %d %s over %s:"):format(
    card.zone and (" in " .. card.zone) or "",
    (type(when) == "string") and (" at " .. when) or "",
    #card.rows, (#card.rows == 1) and "hit" or "hits",
    card.span and (("%.1f seconds"):format(card.span)) or "an unknown time")

  local first = math.max(1, #card.rows - (how or SHOW) + 1)
  if first > 1 then out[#out + 1] = ("  ... %d earlier hits"):format(first - 1) end
  for i = first, #card.rows do
    local r = card.rows[i]
    local more = extras(r)
    out[#out + 1] = ("  %5s  %-22s %8s%s%s%s"):format(
      r.before and (("-%.1fs"):format(r.before)) or "",
      r.spell .. (r.by and (" (" .. r.by .. ")") or ""),
      comma(r.landed or r.amount or 0),
      r.pct and ("  " .. r.pct .. "% left") or "",
      r.avoidable and "  avoidable" or "",
      r.killed and "  <- killed you" or "")
    if more then out[#out + 1] = ("         %s"):format(more) end
  end
  if card.worst and card.fatal and card.worst ~= card.fatal then
    out[#out + 1] = ("  The biggest hit was %s for %s, not the one that finished you."):format(
      card.worst.spell, comma(card.worst.landed or 0))
  end
  if (card.avoidable or 0) > 0 and (card.total or 0) > 0 then
    out[#out + 1] = ("  %s of the %s you took was avoidable, %d%% of it."):format(
      comma(card.avoidable), comma(card.total), math.floor(card.avoidable / card.total * 100 + 0.5))
  end
  if card.killer then
    -- What the rest of the guild knows about them, which is usually more than you do.
    local clause = ns.Threat and ns.Threat.Clause and plain(try(ns.Threat.Clause, card.killer.name)) or nil
    if clause then out[#out + 1] = ("  %s %s."):format(card.killer.name, clause) end
    local v = ns.FindVictim and plain(try(ns.FindVictim, card.killer.name)) or nil
    if type(v) == "table" and type(v.name) == "string" and v.name:lower() == card.killer.name:lower() and (v.kills or 0) > 0 then
      out[#out + 1] = ("  You have killed %s %d time%s."):format(card.killer.name, v.kills, (v.kills == 1) and "" or "s")
    end
  end
  return out
end

local function announce(card)
  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.on == false then return end
  local fatal = card.fatal
  if not fatal then return end
  local by = (card.killer and card.killer.name) or fatal.by
  if ns.Stage and ns.Stage.Banner then
    pcall(ns.Stage.Banner, fatal.spell:upper(), RED,
      ("%s%s"):format(by and (by .. "    ") or "",
        card.span and (("%d hits in %.1fs"):format(#card.rows, card.span)) or (#card.rows .. " hits")),
      { size = 2 })
  end
  if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, "drop") end
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Death.handlers

-- The engine fills the recap as the death resolves, so this reads on the next tick rather than
-- inside the handler. Hype.Died() already speaks for the death itself; this is the post-mortem
-- and deliberately comes after it.
function h.PLAYER_DEAD()
  local after = C_Timer and C_Timer.After
  local function read()
    local card, why = Death.Read()
    if not card then
      if ns.Log then ns.Log("death", "no recap: " .. tostring(why)) end
      return
    end
    record(card)
    announce(card)
    -- The guild's threat pool, from the best source there is: the recap names the caster of every
    -- hit, and whoever did the most of the damage is who killed you. It does its own vouching --
    -- the recap names mobs too -- so a bad name is dropped there rather than filtered here.
    if ns.Threat and card.killer then
      pcall(ns.Threat.Note, card.killer.name, nil, nil, card.zone)
    end
    for _, line in ipairs(Death.Lines(card, 5) or {}) do ns.Print(line) end
    if ns.Log then
      ns.Log("death", ("%s%s, %d hits, %s taken"):format(card.fatal.spell,
        card.killer and (" from " .. card.killer.name) or "", #card.rows, comma(card.total or 0)))
    end
    -- The other two readers of the same death. C_DamageMeter flags its own fatal spell and this
    -- names one too; when they disagree it is worth knowing, because one of them is wrong about
    -- a thing both of them are sure of.
    if ns.Recap then
      local r = GodslayerDB and GodslayerDB.recap and GodslayerDB.recap.last
      local theirs = r and r.killer and r.killer.spell
      if theirs and theirs ~= card.fatal.spell and ns.Log then
        ns.Log("death", ("the meter says %s killed you and the recap says %s"):format(theirs, card.fatal.spell))
      end
    end
  end
  if type(after) == "function" then try(after, 0.75, read) else read() end
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

function Death.Command(rest)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
  local ok, why = Death.Available()
  if not ok then
    ns.Print("No death recap: " .. tostring(why) .. ".")
    return
  end
  local r = db()

  if rest == "who" then
    if not r or (r.n or 0) == 0 then
      ns.Print("Nothing has killed you yet, which will not last.")
      return
    end
    ns.Print(("%d deaths recorded."):format(r.n))
    local spells = {}
    for spell, n in pairs(r.bySpell) do spells[#spells + 1] = { spell, n } end
    table.sort(spells, function(a, b) return a[2] > b[2] end)
    if #spells > 0 then
      local parts = {}
      for i = 1, math.min(#spells, 5) do parts[#parts + 1] = spells[i][1] .. " " .. spells[i][2] end
      ns.Print("Finished you off: " .. table.concat(parts, ", ") .. ".")
    end
    local who = {}
    for name, n in pairs(r.byWho) do who[#who + 1] = { name, n } end
    table.sort(who, function(a, b) return a[2] > b[2] end)
    if #who > 0 then
      local parts = {}
      for i = 1, math.min(#who, 5) do parts[#parts + 1] = who[i][1] .. " " .. who[i][2] end
      ns.Print("Did most of the work: " .. table.concat(parts, ", ") .. ".")
    end
    if (r.taken or 0) > 0 then
      ns.Print(("%s taken across those deaths, %s of it avoidable, %d%%."):format(
        comma(r.taken), comma(r.avoidable or 0),
        math.floor((r.avoidable or 0) / r.taken * 100 + 0.5)))
    end
    return
  end

  local n = tonumber(rest:match("%d+"))
  local card = r and r.last
  if n and r then
    card = r.log[#r.log - n + 1]
    if not card then
      ns.Print(("I only have %d death%s in the book."):format(#r.log, (#r.log == 1) and "" or "s"))
      return
    end
  end
  if not card then
    -- The engine may still be holding one from before this addon was watching.
    card = Death.Read()
    if not card then
      ns.Print("Nothing in the book, and the engine is not holding a recap either.")
      return
    end
  end
  for _, line in ipairs(Death.Lines(card, ROWS) or {}) do ns.Print(line) end
  if r and #r.log > 1 and not n then
    ns.Print(("%d deaths kept. /godslayer death 2 for the one before, death who for the tally."):format(#r.log))
  end
end

function Death.Init()
  local ok, why = Death.Available()
  if not ok and ns.Log then ns.Log("death", "unavailable: " .. tostring(why)) end
end
