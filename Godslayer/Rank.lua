-- Godslayer rank: the fourteen rungs, and the one place this build does not keep them.
--
-- Forever has the vanilla ladder. Scout to High Warlord for the Horde, Private to Grand Marshal
-- for the Alliance, fourteen rungs, and the client carries every title string for both. What it
-- does not carry is any of the functions an addon would reach for. There is no `UnitPVPRank` on
-- this client -- the name appears nowhere in the entire interface -- and nothing called
-- GetPVPRankProgress either.
--
-- The ladder is a MAJOR FACTION. Rank is renown on faction 2800, which is how Forever's own
-- character sheet reads it:
--
--   Blizzard_UIPanels_Game/Camelot/PVPRankFrame.lua:1   local PVP_RANK_POINTS_FACTION_ID = 2800
--   ...:91   local progressionInfo = C_MajorFactions.GetMajorFactionProgressionInfo(FACTION)
--
-- `renownLevel` is the rank, 0 meaning Civilian. `renownReputationEarned` and
-- `renownLevelThreshold` are the points inside the rung. Nothing else in the game answers it.
--
-- TWO TRAPS, both of which look right until you read the numbers.
--
-- 1. The title strings are two unrelated families. `PVP_RANK_<n>_<faction>` is this ladder, with
--    faction 0 for Horde and 1 for Alliance, and n is the PvPRanks **enum** rather than the rank:
--    rank 1 is PVP_RANK_5_0, because Enum.PvPRanks.Rank_1 is 5. `PVP_RANK_<n>_NAME` is the modern
--    rated ladder -- Combatant I, Challenger I, Rival I -- and has nothing to do with this one.
--    PVP_RANK_0_NAME is "Civilian" and belongs to both, so the wrong family is correct at rank 0
--    and then calls a Scout "Combatant I".
--
-- 2. `GetPVPLifetimeStats` returns its best rank as a PvPRanks enum value, 5 through 18, while
--    `renownLevel` is a plain 1 through 14. One system, one concept, two scales, four apart.
--
-- Dishonorable kills are live on this build: COMBATLOG_DISHONORGAIN exists, and the client's own
-- tooltip says each one "immediately reduces your overall ranking". They arrive on the same event
-- as honor and they are the only thing here that can take a rung away, so they are called out.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Rank = { handlers = {} }
ns.Rank = Rank

local FACTION = 2800        -- the major faction the ladder lives on, per the client's own frame
local RANKS = 14
local DAY_CAP = 30          -- days of honor kept
local GOLD, RED, BLUE = { 1, 0.82, 0 }, { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }

-- Enum.PvPRanks.Rank_1 is 5 on this build. Read rather than assumed, because every rank number
-- in this file is an offset from it, and a wrong one is wrong by exactly four everywhere.
local function rank1()
  local e = Enum and Enum.PvPRanks and Enum.PvPRanks.Rank_1
  return (type(e) == "number" and e) or 5
end
Rank.FACTION, Rank.RANKS = FACTION, RANKS

--------------------------------------------------------------------------------
-- Reading the ladder
--------------------------------------------------------------------------------

-- The ladder's own title. Deliberately not PVP_RANK_<n>_NAME: see the note at the top.
function Rank.Title(level, factionGroup, sex)
  level = tonumber(level) or 0
  if level <= 0 then return _G.PVP_RANK_0_NAME or "Civilian" end
  if level > RANKS then level = RANKS end
  local key = "PVP_RANK_" .. (rank1() + level - 1) .. "_" .. ((factionGroup == "Alliance") and 1 or 0)
  -- GetText picks the gendered form; the bare global is the masculine one and the fallback.
  local text = plain(try(GetText, key, sex))
  if type(text) ~= "string" or text == "" then text = _G[key] end
  return (type(text) == "string" and text ~= "") and text or ("Rank " .. level)
end

-- Rank, points inside the rung, and what the rung costs. nil when the client will not say.
function Rank.Read()
  local get = C_MajorFactions and C_MajorFactions.GetMajorFactionProgressionInfo
  local info = plain(try(get, FACTION))
  if type(info) ~= "table" then return nil end
  local level = tonumber(plain(info.renownLevel))
  if not level then return nil end
  local points = tonumber(plain(info.renownReputationEarned)) or 0
  local threshold = tonumber(plain(info.renownLevelThreshold)) or 0
  return {
    level = level,
    points = points,
    threshold = threshold,
    left = (threshold > points) and (threshold - points) or 0,
    pct = (threshold > 0) and (points / threshold) or 0,
  }
end

-- Just the rung, for the places that want a number and nothing else. nil when the faction has
-- not answered yet, which it does not for the first moments after login.
function Rank.Level()
  local r = Rank.Read()
  return r and r.level or nil
end

-- Lifetime honorable kills, and the best rank ever held -- converted off the enum scale.
function Rank.Lifetime()
  local hk, best = try(GetPVPLifetimeStats)
  hk, best = tonumber(plain(hk)), tonumber(plain(best))
  local level
  if best then level = (best >= rank1()) and (best - rank1() + 1) or 0 end
  return { hk = hk, best = level }
end

function Rank.Today()
  local hk, dk = try(GetPVPSessionStats)
  return tonumber(plain(hk)) or 0, tonumber(plain(dk)) or 0
end

function Rank.Yesterday()
  local hk, dk = try(GetPVPYesterdayStats)
  return tonumber(plain(hk)) or 0, tonumber(plain(dk)) or 0
end

function Rank.Season()
  local n = tonumber(plain(try(GetCurrentArenaSeason))) or 0
  local ends = tonumber(plain(try(C_SeasonInfo and C_SeasonInfo.GetTimeUntilCurrentPVPSeasonEnd))) or 0
  return n, ends
end

--------------------------------------------------------------------------------
-- Honor off the wire
--------------------------------------------------------------------------------

-- The honor lines are read from the client's own format strings rather than written out here, so
-- this still finds the number on a localised client. Every magic character is escaped first, and
-- only then do %s and %d become captures; doing it the other way round escapes the captures too.
local function compile(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local which, n = nil, 0
  for tok in fmt:gmatch("%%([sd])") do
    n = n + 1
    if tok == "d" and not which then which = n end
  end
  if not which then return nil end
  local p = fmt:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
  p = p:gsub("%%%%d", "(%%d+)"):gsub("%%%%s", "(.-)")
  return { p = "^" .. p, which = which }
end

local honorPats, dishonorPat
local function patterns()
  if honorPats then return honorPats end
  honorPats = {}
  -- The exhaustion lines are the plain ones with a bonus clause on the end, so they are tried
  -- first: a pattern that is a prefix of another must never get the first look.
  for _, name in ipairs({
    "COMBATLOG_HONORGAIN_EXHAUSTION1", "COMBATLOG_HONORGAIN_NO_RANK_EXHAUSTION1",
    "COMBATLOG_HONORGAIN", "COMBATLOG_HONORGAIN_NO_RANK", "COMBATLOG_HONORAWARD",
  }) do
    local c = compile(_G[name])
    if c then c.name = name honorPats[#honorPats + 1] = c end
  end
  local d = _G.COMBATLOG_DISHONORGAIN
  if type(d) == "string" and d ~= "" then
    dishonorPat = "^" .. d:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1"):gsub("%%%%s", "(.-)")
  end
  return honorPats
end

-- The honor in an honor-gain line, and whether it named a victim (an award from an objective
-- does not, and should not count as a kill).
function Rank.ParseHonor(text)
  if type(text) ~= "string" then return nil end
  for _, c in ipairs(patterns()) do
    local caps = { text:match(c.p) }
    if caps[1] ~= nil then
      local honor = tonumber(caps[c.which])
      if honor then return honor, (c.which > 1) and caps[1] or nil, c.name end
    end
  end
end

function Rank.ParseDishonor(text)
  if type(text) ~= "string" then return nil end
  patterns()
  if not dishonorPat then return nil end
  local who = text:match(dishonorPat)
  if who then return who end
end

--------------------------------------------------------------------------------
-- Storage
--------------------------------------------------------------------------------

local session = { honor = 0, kills = 0, dk = 0, since = nil }
Rank.session = session

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.rank = type(d.rank) == "table" and d.rank or {}
  local r = d.rank
  r.honor = tonumber(r.honor) or 0
  r.kills = tonumber(r.kills) or 0
  r.days = type(r.days) == "table" and r.days or {}
  return r
end
Rank.DB = db

local function today()
  local s = plain(try(date, "%Y-%m-%d"))
  return (type(s) == "string" and s) or "?"
end

local function noteDay(honor, kills, dks)
  local r = db()
  if not r then return end
  local key = today()
  local row = r.days[key]
  if not row then row = { honor = 0, kills = 0, dk = 0 } r.days[key] = row end
  row.honor = row.honor + (honor or 0)
  row.kills = row.kills + (kills or 0)
  row.dk = (row.dk or 0) + (dks or 0)
  -- Oldest days go first, so a long-running character does not carry a year of them.
  local keys = {}
  for k in pairs(r.days) do keys[#keys + 1] = k end
  if #keys > DAY_CAP then
    table.sort(keys)
    for i = 1, #keys - DAY_CAP do r.days[keys[i]] = nil end
  end
end

--------------------------------------------------------------------------------
-- Moving between rungs
--------------------------------------------------------------------------------

-- A rung gained or lost. Called when the game says the rank changed and once at login, which is
-- also the only place the first value is ever recorded: a fresh install must not announce the
-- rank the character already had.
function Rank.Check(announce)
  local r, now = db(), Rank.Read()
  if not r or not now then return nil end
  local was = tonumber(r.level)
  r.level = now.level
  r.points, r.threshold = now.points, now.threshold
  if (now.level or 0) > (r.best or 0) then r.best = now.level end
  if was == nil or was == now.level then return nil end

  local up = now.level > was
  local faction = plain(try(UnitFactionGroup, "player"))
  local sex = plain(try(UnitSex, "player"))
  local title = Rank.Title(now.level, faction, sex)
  if announce ~= false then
    local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
    if o.on ~= false then
      if ns.Stage and ns.Stage.Banner then
        pcall(ns.Stage.Banner,
          up and title:upper() or "RANK LOST",
          up and GOLD or RED,
          up and ("Rank " .. now.level .. " of " .. RANKS) or (title .. "    was rank " .. was),
          { size = up and 3 or 2 })
      end
      if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, up and "fanfare" or "powerdown") end
      if up and ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, "rankup", 3) end
    end
    ns.Print(up
      and ("Rank %d: %s."):format(now.level, title)
      or ("Rank lost: %s, down from rank %d. Dishonorable kills do that."):format(title, was))
  end
  if ns.Log then ns.Log("rank", (up and "up to " or "down to ") .. now.level .. " (" .. title .. ")") end
  return up and "up" or "down", now.level, was, title
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Rank.handlers

function h.CHAT_MSG_COMBAT_HONOR_GAIN(text)
  text = plain(text)
  if type(text) ~= "string" then return end
  local r = db()
  if not r then return end

  local honor, victim = Rank.ParseHonor(text)
  if honor then
    local kill = victim and 1 or 0
    r.honor, r.kills = r.honor + honor, r.kills + kill
    session.honor, session.kills = session.honor + honor, session.kills + kill
    noteDay(honor, kill, 0)
    if ns.Log then ns.Log("honor", honor .. (victim and (" from " .. victim) or " awarded")) end
    return
  end

  local who = Rank.ParseDishonor(text)
  if who then
    r.dks = (tonumber(r.dks) or 0) + 1
    session.dk = session.dk + 1
    noteDay(0, 0, 1)
    local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
    if o.on ~= false then
      if ns.Stage and ns.Stage.Banner then
        pcall(ns.Stage.Banner, "DISHONORABLE", RED, who .. "    that costs you rank", { size = 2 })
      end
      if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, "trombone") end
    end
    ns.Print(("Dishonorable kill on %s. That takes rank points off, and they stack if you keep going."):format(who))
    if ns.Log then ns.Log("honor", "dishonorable kill on " .. who) end
  end
end

function h.MAJOR_FACTION_RENOWN_LEVEL_CHANGED(factionID)
  if tonumber(plain(factionID)) ~= FACTION then return end
  Rank.Check(true)
end

function h.PLAYER_PVP_RANK_CHANGED()
  Rank.Check(true)
end

function h.PLAYER_LOGIN()
  session.since = GetTime()
end

--------------------------------------------------------------------------------
-- The card
--------------------------------------------------------------------------------

-- Honor per hour this session, and what that makes the wait for the next rung. Honest about not
-- knowing: with nothing earned yet there is no rate, and so no estimate.
function Rank.Pace(now)
  local since = session.since
  if not since then return nil end
  local hours = ((now or GetTime()) - since) / 3600
  if hours <= 0 or session.honor <= 0 then return nil end
  return session.honor / hours, hours
end

function Rank.Card()
  local now = Rank.Read()
  local r = db() or {}
  local faction = plain(try(UnitFactionGroup, "player"))
  local sex = plain(try(UnitSex, "player"))
  local card = {
    level = now and now.level or nil,
    points = now and now.points or nil,
    threshold = now and now.threshold or nil,
    left = now and now.left or nil,
    pct = now and now.pct or nil,
    title = now and Rank.Title(now.level, faction, sex) or nil,
    next = (now and now.level and now.level < RANKS) and Rank.Title(now.level + 1, faction, sex) or nil,
    lifetime = Rank.Lifetime(),
    dks = tonumber(r.dks) or 0,
    honor = r.honor or 0,
    session = { honor = session.honor, kills = session.kills, dk = session.dk },
  }
  card.today = { Rank.Today() }
  card.yesterday = { Rank.Yesterday() }
  local rate = Rank.Pace()
  if rate and card.left and card.left > 0 then
    card.rate = rate
    card.hours = card.left / rate
    if session.kills > 0 and session.honor > 0 then
      card.perKill = session.honor / session.kills
      card.killsLeft = math.ceil(card.left / card.perKill)
    end
  end
  local season, ends = Rank.Season()
  card.season, card.seasonEnds = season, ends
  return card
end

function Rank.Command()
  local c = Rank.Card()
  if not c.level then
    ns.Print("The client will not tell me your rank. Open the character sheet's PvP tab once and try again.")
    return
  end
  ns.Print(("Rank %d of %d: %s."):format(c.level, RANKS, c.title))
  if c.threshold and c.threshold > 0 then
    ns.Print(("Rank points: %d / %d, %d to go%s."):format(c.points, c.threshold, c.left,
      c.next and (" for " .. c.next) or ""))
  end
  if c.killsLeft then
    ns.Print(("At tonight's rate -- %d honor over %d kills -- that is about %d more kills."):format(
      c.session.honor, c.session.kills, c.killsLeft))
  elseif c.rate then
    ns.Print(("At tonight's rate that is about %.1f hours."):format(c.hours))
  end
  local lt = c.lifetime
  if lt.hk then
    ns.Print(("Lifetime: %d honorable kills%s."):format(lt.hk,
      (lt.best and lt.best > 0) and (", best rank " .. lt.best .. " (" .. Rank.Title(lt.best,
        plain(try(UnitFactionGroup, "player")), plain(try(UnitSex, "player"))) .. ")") or ""))
  end
  ns.Print(("Today: %d honorable, %d dishonorable. Yesterday: %d and %d."):format(
    c.today[1] or 0, c.today[2] or 0, c.yesterday[1] or 0, c.yesterday[2] or 0))
  if c.dks > 0 then
    ns.Print(("I have seen %d dishonorable kill%s since you installed me. Each one costs rank points."):format(
      c.dks, c.dks == 1 and "" or "s"))
  end
  if c.seasonEnds and c.seasonEnds > 0 then
    ns.Print(("Season %d ends in %d days."):format(c.season, math.floor(c.seasonEnds / 86400)))
  end
end

function Rank.Init()
  patterns()
  session.since = session.since or GetTime()
  -- The first read only records; it never announces a rank the character already had.
  Rank.Check(false)
end
