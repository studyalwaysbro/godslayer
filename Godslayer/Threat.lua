-- Godslayer threat pool: the guild's shared answer to "who on this realm is the actual problem".
--
-- Your dossier is yours. Every Torchman learns the realm's dangerous players one death at a time,
-- alone, and the seventh of us to walk into a Warsong against the same arcane mage learns it the
-- same way the first did. Nothing in the game pools that. The guild roster, the honor ladder and
-- the scoreboard all describe your own side.
--
-- So each copy of the addon tells the others, on the hidden addon channel, the name of the player
-- who just killed it. Every copy folds those into one table keyed on the killer, and the result
-- is a read no single dossier can give: how many of us a name has taken, how many separate
-- Torchmen, in which guild, and where it happens. It pays off at the one moment it matters -- the
-- name turning up on a battleground scoreboard, or under your cursor.
--
-- WHO KILLED YOU IS A HEURISTIC ON THIS CLIENT, AND IS TREATED AS ONE.
--
-- `COMBAT_LOG_EVENT_UNFILTERED` is closed to addons, so nothing reports a killer directly. Two
-- sources, in this order:
--
--   1. `C_DeathRecap` names the caster of every hit in your last seconds. Death.lua reads it and
--      hands over whoever did the most damage. This is the good source and it is usually there.
--   2. Failing that, the hostile player you had targeted when you died, which is the same guess
--      Core.lua has always made for the feud counter, with the same caveat.
--
-- Either way the answer is a bare NAME, and a name alone is not enough to broadcast: the recap
-- happily names a Venomtail Scorpid. So a name is only recorded once something else vouches that
-- it belongs to an enemy player -- `seen` had them hostile, your dossier has them, or a guildmate
-- has already reported them. A name nothing vouches for is dropped, counted, and the count is
-- printed in the report, because a silent drop is a bug you never find.
--
--   /godslayer threat             who the guild keeps dying to
--   /godslayer threat <name>      one of them in full, and whether you have paid them back
--   /godslayer threat guilds      which enemy guild is actually beating us
--   /godslayer threat forget      empty the pool

local _, ns = ...
local plain, try = ns.plain, ns.try

local Threat = { handlers = {} }
ns.Threat = Threat

local KEEP = 21 * 86400     -- a terror who transferred off three weeks ago is not a threat
local NAMES = 200           -- killers kept per guild
local WHO = 24              -- separate Torchmen remembered per killer
local NAME_MAX = 32         -- what a field may carry onto the wire, and off it
local GUILD_MAX = 32
local ZONE_MAX = 40
local SAY_GAP = 600         -- seconds before the same name is called out under your cursor again

local GOLD, RED, GREY = { 1, 0.82, 0 }, { 1, 0.19, 0.19 }, { 0.6, 0.6, 0.6 }

-- Deaths whose killer nothing could vouch for. Session-only and deliberately visible.
local unvouched = 0
local said = {}
local lastLife = nil

--------------------------------------------------------------------------------
-- The pool
--------------------------------------------------------------------------------

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.threat = d.threat or {}
  local guild = ns.MyGuild and ns.MyGuild() or nil
  if not guild then return nil end
  d.threat[guild] = d.threat[guild] or {}
  return d.threat[guild], guild
end
Threat.Pool = db

-- A field off the wire. Anything a player name, guild or zone cannot contain is removed rather
-- than rejected, so one odd character does not throw away a real report.
local function clean(v, cap)
  if type(v) ~= "string" then return nil end
  v = v:gsub("[|;%c]", ""):sub(1, cap)
  if v == "" then return nil end
  return v
end

local function classToken(v)
  v = clean(v, 16)
  return (v and v:match("^%u+$")) and v or nil
end

local function short(name)
  if type(name) ~= "string" then return nil end
  return name:match("^[^-]+") or name
end

-- Trim the pool to the names last seen most recently. Called when it grows past the cap, not on a
-- timer: a pool under the cap is left exactly as it is.
local function trim(pool)
  local list = {}
  for name, r in pairs(pool) do list[#list + 1] = { name, r.t or 0 } end
  if #list <= NAMES then return end
  table.sort(list, function(a, b) return a[2] > b[2] end)
  for i = NAMES + 1, #list do pool[list[i][1]] = nil end
end

-- One report folded in, whoever it came from. `from` is the Torchman who died; nil means you.
function Threat.Fold(from, name, class, guild, zone)
  local pool = db()
  if not pool then return nil end
  name = clean(short(name), NAME_MAX)
  if not name then return nil end
  from = clean(short(from), NAME_MAX) or ns.myName
  if not from then return nil end

  local r = pool[name]
  if not r then
    r = { n = 0, who = {}, mine = 0 }
    pool[name] = r
  end
  r.n = r.n + 1
  r.t = time()
  -- A class or guild we already have is not replaced by an empty one: the first report of a kill
  -- often has them and a later one, from someone who never got a nameplate up, does not.
  r.class = classToken(class) or r.class
  r.g = clean(guild, GUILD_MAX) or r.g
  r.z = clean(zone, ZONE_MAX) or r.z
  if from == ns.myName then r.mine = (r.mine or 0) + 1 end

  local who = r.who
  if who[from] == nil and next(who) then
    -- Past the cap the least-bitten name goes, so the people it happens to most are the ones kept.
    local n, worst, worstCount = 0, nil, nil
    for other, count in pairs(who) do
      n = n + 1
      if not worstCount or count < worstCount then worst, worstCount = other, count end
    end
    if n >= WHO and worst then who[worst] = nil end
  end
  who[from] = (who[from] or 0) + 1
  trim(pool)
  return r
end

-- Does the pool know this name? The cross-reference the rest of the addon asks for.
function Threat.Of(name)
  local pool = db()
  name = short(name)
  if not (pool and name) then return nil end
  local r = pool[name]
  if r and (r.n or 0) > 0 then return r, name end
  -- names arrive from the wire already shortened, but a local caller may not have
  for key, rec in pairs(pool) do
    if key:lower() == name:lower() and (rec.n or 0) > 0 then return rec, key end
  end
  return nil
end

function Threat.Unvouched() return unvouched end

--------------------------------------------------------------------------------
-- Recording one of our own deaths
--------------------------------------------------------------------------------

-- Something other than the recap has to agree this name is an enemy player. In order of how much
-- it is worth: the pool (a guildmate watched them do it), your dossier (you have killed them), or
-- `seen` with the hostile flag set (they were on screen and attackable).
local function vouch(name)
  if Threat.Of(name) then return "pooled" end
  local v = ns.FindVictim and plain(try(ns.FindVictim, name)) or nil
  if type(v) == "table" and type(v.name) == "string" and v.name:lower() == name:lower() and (v.kills or 0) > 0 then
    return "dossier", nil, v.guild, v.class
  end
  local e = ns.SeenByName and ns.SeenByName(name) or nil
  if type(e) == "table" and e.hostile then return "seen", e.class, e.guild end
  return nil
end

-- One per life, from whichever source got there. Death.lua's recap is the good one and runs a
-- moment late; Core.lua's target guess only fires when there is no recap to wait for.
function Threat.Note(name, class, guild, zone)
  name = short(clean(name, NAME_MAX))
  if not name then return false, "no name" end
  if name == ns.myName then return false, "that is you" end
  local life = ns.session and ns.session.life
  if life and lastLife == life then return false, "already recorded this death" end

  local why, seenClass, seenGuild, dossierClass = vouch(name)
  if not why then
    unvouched = unvouched + 1
    ns.Log("threat", "nothing vouches for " .. name .. " being an enemy player; dropped")
    return false, "unvouched"
  end
  lastLife = life
  class = classToken(class) or classToken(seenClass) or classToken(dossierClass)
  guild = clean(guild, GUILD_MAX) or clean(seenGuild, GUILD_MAX)
  zone = clean(zone, ZONE_MAX) or clean(plain(try(GetRealZoneText)), ZONE_MAX)

  Threat.Fold(nil, name, class, guild, zone)
  ns.Log("threat", ("%s killed you (%s)"):format(name, why))
  if ns.Comm and ns.Comm.Threat then ns.Comm.Threat(name, class, guild, zone) end
  if ns.OnChanged then ns.OnChanged() end
  return true
end

-- A guildmate's report, routed here by Comm.
function Threat.Heard(from, name, class, guild, zone)
  if not Threat.Fold(from, name, class, guild, zone) then return false end
  if ns.OnChanged then ns.OnChanged() end
  return true
end

--------------------------------------------------------------------------------
-- Reading the pool
--------------------------------------------------------------------------------

local function countWho(r)
  local n = 0
  for _ in pairs(r.who or {}) do n = n + 1 end
  return n
end

-- Worst first, and worst means the most of us rather than the most deaths: a name that has taken
-- one Torchman nine times is a grudge, and one that has taken nine of us once each is a problem.
function Threat.List()
  local pool, guild = db()
  if not pool then return {}, nil end
  local rows, now, total, mine = {}, time(), 0, 0
  for name, r in pairs(pool) do
    if (r.n or 0) > 0 and now - (r.t or 0) <= KEEP then
      rows[#rows + 1] = { name = name, n = r.n, spread = countWho(r), mine = r.mine or 0,
                          class = r.class, guild = r.g, zone = r.z, t = r.t, who = r.who }
      total = total + r.n
      mine = mine + (r.mine or 0)
    end
  end
  table.sort(rows, function(a, b)
    if a.spread ~= b.spread then return a.spread > b.spread end
    if a.n ~= b.n then return a.n > b.n end
    return a.name < b.name
  end)
  return rows, guild, total, mine
end

-- Which enemy guild the deaths actually belong to. Players with no guild read on them are left
-- out rather than lumped together, because an unknown guild is not a guild.
function Threat.Guilds()
  local rows, named = Threat.List(), {}
  local out = {}
  for i = 1, #rows do
    local g = rows[i].guild
    if g then
      local e = named[g]
      if not e then e = { guild = g, n = 0, players = 0 } named[g] = e out[#out + 1] = e end
      e.n, e.players = e.n + rows[i].n, e.players + 1
    end
  end
  table.sort(out, function(a, b)
    if a.n ~= b.n then return a.n > b.n end
    return a.guild < b.guild
  end)
  return out
end

local function ago(t)
  if type(t) ~= "number" or t <= 0 then return "at some point" end
  local d = time() - t
  if d < 90 then return "just now" end
  if d < 5400 then return ("%dm ago"):format(math.floor(d / 60 + 0.5)) end
  if d < 36 * 3600 then return ("%dh ago"):format(math.floor(d / 3600 + 0.5)) end
  return ("%dd ago"):format(math.floor(d / 86400 + 0.5))
end
Threat.Ago = ago

local function plural(n, one, many) return (n == 1) and one or many end

local function pretty(token)
  if type(token) ~= "string" or token == "" then return nil end
  return token:sub(1, 1) .. token:sub(2):lower()
end

-- How many of ours a name has taken, in one clause, for another module's report to borrow.
function Threat.Clause(name)
  local r, key = Threat.Of(name)
  if not r then return nil end
  local spread = countWho(r)
  if spread <= 1 and (r.mine or 0) == r.n then
    return ("has killed you %d %s"):format(r.n, plural(r.n, "time", "times"))
  end
  return ("has killed %d of us %d %s"):format(spread, r.n, plural(r.n, "time", "times")), key
end

function Threat.Lines(rest)
  local pool, guild = db()
  if not guild then return { "You are not in a guild, so there is nobody to pool with." } end
  if not pool then return { "Nothing pooled yet." } end
  rest = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""

  if rest == "guilds" then
    local rows = Threat.Guilds()
    if #rows == 0 then return { "No guild has been read on anyone who has killed us." } end
    local out = { "Which guild is actually beating us:" }
    for i = 1, math.min(#rows, 12) do
      local r = rows[i]
      out[#out + 1] = ("  <%s>  %d %s from %d of them"):format(r.guild, r.n, plural(r.n, "death", "deaths"), r.players)
    end
    return out
  end

  if rest ~= "" then
    local r, key = Threat.Of(rest)
    if not r then return { ("Nobody called %s has killed any of us."):format(rest) } end
    local out = { ("%s%s%s"):format(key, r.class and (", " .. pretty(r.class)) or "", r.g and (", <" .. r.g .. ">") or "") }
    local spread = countWho(r)
    out[#out + 1] = ("  %d %s across %d of us, last %s%s."):format(
      r.n, plural(r.n, "death", "deaths"), spread, r.z and ("in " .. r.z .. " ") or "", ago(r.t))
    -- The paid-back half can only be your own: a dossier is not shared, and claiming otherwise
    -- would be inventing a number.
    local v = ns.FindVictim and plain(try(ns.FindVictim, key)) or nil
    local back = (type(v) == "table" and type(v.name) == "string" and v.name:lower() == key:lower()) and (v.kills or 0) or 0
    out[#out + 1] = ("  You: %d %s, and you have killed them %d %s."):format(
      r.mine or 0, plural(r.mine or 0, "death", "deaths"), back, plural(back, "time", "times"))
    local others = {}
    for who, n in pairs(r.who or {}) do
      if who ~= ns.myName then others[#others + 1] = { who, n } end
    end
    table.sort(others, function(a, b)
      if a[2] ~= b[2] then return a[2] > b[2] end
      return a[1] < b[1]
    end)
    if #others > 0 then
      local parts = {}
      for i = 1, math.min(#others, 8) do parts[#parts + 1] = ("%s %d"):format(others[i][1], others[i][2]) end
      out[#out + 1] = "  Also: " .. table.concat(parts, ", ")
    end
    return out
  end

  local rows, _, total, mine = Threat.List()
  if #rows == 0 then
    return { "Nothing pooled yet. Every Torchman running this tells the others who killed them." }
  end
  local out = { "Who the guild keeps dying to:" }
  for i = 1, math.min(#rows, 15) do
    local r = rows[i]
    out[#out + 1] = ("  %-18s %-9s %-16s %2d %s, %d of us   %s"):format(
      r.name:sub(1, 18), pretty(r.class) or "?", r.guild and ("<" .. r.guild:sub(1, 14) .. ">") or "",
      r.n, plural(r.n, "death", "deaths"), r.spread, ago(r.t))
  end
  local reporters = {}
  for i = 1, #rows do
    for who in pairs(rows[i].who or {}) do reporters[who] = true end
  end
  local n = 0
  for _ in pairs(reporters) do n = n + 1 end
  out[#out + 1] = ("%d %s, %d %s pooled from %d of us. Yours alone: %d."):format(
    #rows, plural(#rows, "name", "names"), total, plural(total, "death", "deaths"), n, mine)
  if unvouched > 0 then
    out[#out + 1] = ("%d %s this session had a killer nothing could confirm was an enemy player, and were dropped."):format(
      unvouched, plural(unvouched, "death", "deaths"))
  end
  return out
end

--------------------------------------------------------------------------------
-- Where it pays off
--------------------------------------------------------------------------------

-- Under your cursor. Once per name per ten minutes, because a name you are fighting is a name
-- you target over and over.
local function callOut(unit)
  local pool = db()
  if not pool then return end
  if not (plain(try(UnitExists, unit)) and plain(try(UnitIsPlayer, unit)) == true) then return end
  if plain(try(UnitCanAttack, "player", unit)) ~= true then return end
  -- ns.FullName, not UnitName: the addon keys everything on the name with its realm attached when
  -- there is one, and the pool has to be asked the same question the dossier was.
  local name = ns.FullName and ns.FullName(unit) or plain(try(UnitName, unit))
  local r, key = Threat.Of(name)
  if not r then return end
  local now = GetTime()
  if said[key] and now - said[key] < SAY_GAP then return end
  said[key] = now
  local clause = Threat.Clause(key)
  if not clause then return end
  if ns.Stage and ns.Stage.Banner then
    pcall(ns.Stage.Banner, key:upper(), RED, clause)
  end
  ns.Print(("%s %s."):format(key, clause))
end

function Threat.handlers.PLAYER_TARGET_CHANGED() callOut("target") end

--------------------------------------------------------------------------------
-- Commands
--------------------------------------------------------------------------------

function Threat.Command(rest)
  rest = type(rest) == "string" and rest:match("^%s*(.-)%s*$") or ""
  if rest == "forget" then
    local d = GodslayerDB
    local guild = ns.MyGuild and ns.MyGuild() or nil
    if d and d.threat and guild then d.threat[guild] = nil end
    said = {}
    ns.Print("Threat pool emptied. It fills again from the next death any of us takes.")
    if ns.OnChanged then ns.OnChanged() end
    return
  end
  for _, line in ipairs(Threat.Lines(rest)) do ns.Print(line) end
end

function Threat.Init()
  local pool = db()
  if not pool then return end
  local now = time()
  for name, r in pairs(pool) do
    if now - (r.t or 0) > KEEP then pool[name] = nil end
  end
  trim(pool)
end
