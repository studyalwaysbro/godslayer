-- Godslayer field: the battleground, read the only way this client allows.
--
-- WHAT EVERY PORTED ADDON GETS WRONG HERE. The call a Classic battleground addon reaches for is
-- `GetBattlefieldScore`, and on Forever it does not exist. It is defined in exactly one place --
-- `Blizzard_Deprecated/Mainline/Deprecated_12_0_1.lua` -- and the toc gates that file
-- `[AllowLoadGameType mainline]`. Forever's game type is camelot, so the file is never loaded,
-- and the `loadDeprecationFallbacks` CVar at the top of it never gets a chance to matter. A
-- scoreboard addon carried over from Classic calls a nil global on this realm.
--
-- The real call is `C_PvP.GetScoreInfo(index)`, walked from 1 to `GetNumBattlefieldScores()` and
-- refreshed with `RequestBattlefieldScoreData()`. That is what Forever's own scoreboard does:
-- Blizzard_PVPMatch loads on camelot and PVPMatchUtil.lua drives the table from exactly those
-- three.
--
-- THE SEAL, AND WHAT SURVIVES IT. `GetScoreInfo` carries `SecretInActivePvPMatch = true`. That is
-- not the `SecretWhenInCombat` that Recap.lua works around; it is stricter and it lasts the whole
-- match. Every number on the scoreboard -- killing blows, honorable kills, deaths, honor, damage,
-- healing, every objective value -- comes back as a secret value from the moment the gates open
-- until the match is over. There is no trick that gets around it, and an addon advertising a live
-- battleground damage column on this client is reading nothing.
--
-- Seven fields in `PVPScoreInfo` are marked `NeverSecret` and come through intact:
--
--     name   faction   raceName   gender   className   classToken   honorLevel
--
-- And `honorLevel` is the interesting one, because in Camelot it is not the modern honor level at
-- all. It is the player's PvP rank. Forever's own scoreboard says so and reads it with the same
-- `PVP_RANK_<enum>_<faction>` formula this addon's Rank.lua uses:
--
--     Blizzard_PVPMatch/Camelot/PVPMatchTableOverrides.lua:1
--       -- In Camelot the honorLevel in the score data is the player's PvP rank.
--       GetText("PVP_RANK_" .. (Enum.PvPRanks.Rank_1 + rowData.honorLevel - 1) .. factionAffix, ...)
--
-- So the thing that is readable live is the only thing worth reading live: who is in here, what
-- they are, and how far up the ladder they have climbed. Forty names with a rank against each of
-- them, while the match is still running. Then the match ends, the seal lifts, and the numbers
-- arrive all at once.
--
-- `guid` is NOT on the NeverSecret list, so during the match the rows cannot be keyed by it --
-- only by name. The client's own code agrees: PVPMatchUtil touches `scoreInfo.guid` only inside
-- its `isMatchComplete` branch. Keying a live roster by guid gets a table with one entry in it.
--
-- Two honest limits. The scoreboard carries no guild name, so nothing here can feed Rival.lua's
-- feud; names are cross-referenced against the dossier instead. And `talentSpec` is not
-- NeverSecret either, so live there is no way to tell a healer from a shadow priest -- this counts
-- classes that *can* heal and says so in those words.
--
--   /godslayer field          both sides, and what their ladder looks like
--   /godslayer field them     the enemy roster in full, highest rank first
--   /godslayer field us       your own side
--   /godslayer field last     the last finished match, with the numbers

local _, ns = ...
local plain, try = ns.plain, ns.try

local Field = { handlers = {} }
ns.Field = Field

local RANKS = 14           -- the ladder's top rung; a honorLevel past it is not a Camelot rank
local KEEP = 10            -- finished matches kept
local POLL = 10            -- seconds between score requests while a match is on
local GAP = 5              -- the floor between two requests, deliberately under POLL: a throttle
                           -- set to the tick period beats against it and halves the real refresh
                           -- rate, because a tick landing a second early is a tick thrown away
local SCOUT_AT = 12        -- seconds after joining before the scouting report
local ALLIANCE = 1         -- the faction index the client's own scoreboard treats as Alliance
local GOLD, RED, BLUE = { 1, 0.82, 0 }, { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }

-- Classes with a healing tree. Deliberately not split by faction: which classes each side can
-- field is a realm rule, and the scoreboard already tells us the answer for the players actually
-- standing here.
local CAN_HEAL = { PRIEST = true, DRUID = true, PALADIN = true, SHAMAN = true }

local match, scouted, nextPoll = nil, false, 0

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

-- A number the client was willing to give us, or nil. A secret value is nil here, and nil is
-- never turned into zero: inside an active match almost every number is secret, and reporting a
-- sealed scoreboard as a row of zeroes would be the one genuinely dishonest thing this file
-- could do.
local function num(v)
  v = plain(v)
  return (type(v) == "number") and v or nil
end

local function str(v)
  v = plain(v)
  return (type(v) == "string" and v ~= "") and v or nil
end

local STATE_FALLBACK = { Inactive = 0, Waiting = 1, StartUp = 2, Engaged = 3, PostRound = 4, Complete = 5 }
local STATES = setmetatable({}, { __index = function(t, k)
  local e = Enum and Enum.PvPMatchState
  local v = e and e[k]
  v = (type(v) == "number") and v or STATE_FALLBACK[k]
  rawset(t, k, v)
  return v
end })
Field.STATES = STATES

function Field.State()
  local get = C_PvP and C_PvP.GetActiveMatchState
  return num(try(get))
end

-- In a match at all: the gates may still be shut, which is the best moment to read the roster
-- because everyone is standing in it and nobody has left yet.
function Field.In()
  local s = Field.State()
  if not s then return false end
  return s > STATES.Inactive
end

function Field.Complete()
  if plain(try(C_PvP and C_PvP.IsMatchComplete)) == true then return true end
  local s = Field.State()
  return s ~= nil and s >= STATES.Complete
end

-- Whether the numbers are sealed. The annotation is on the function, so this is a property of the
-- match and not of what the player happens to be doing.
function Field.Sealed()
  return Field.In() and not Field.Complete()
end

-- My side as a faction index, from my own faction rather than from the scoreboard: in a factional
-- battleground the two agree, and `IsMatchFactional` says when that holds.
local function mySide()
  local g = str(try(UnitFactionGroup, "player"))
  if g == "Alliance" then return ALLIANCE end
  if g == "Horde" then return 1 - ALLIANCE end
  return nil
end

local function myNames()
  local full = ns.FullName and plain(try(ns.FullName, "player")) or nil
  local short = plain(try(UnitName, "player"))
  local out = {}
  if type(full) == "string" and full ~= "" then out[full:lower()] = true end
  if type(short) == "string" and short ~= "" then out[short:lower()] = true end
  return out
end

-- One row, reduced to what we are allowed to hold. Returns nil for a row with no name, because a
-- row we cannot even name is a row we can do nothing with.
local function readRow(i)
  local info = plain(try(C_PvP.GetScoreInfo, i))
  if type(info) ~= "table" then return nil end
  local name = str(info.name)
  if not name then return nil end

  local rank = num(info.honorLevel)
  -- Past the fourteenth rung this is not a Camelot rank, whatever it is, and must not be titled.
  if rank and (rank < 0 or rank > RANKS) then rank = nil end

  local row = {
    name = name,
    faction = num(info.faction),
    race = str(info.raceName),
    gender = num(info.gender),
    class = str(info.className),
    token = str(info.classToken),
    rank = rank,
    -- these five are sealed until the match is over, and nil is the truthful answer until then
    guid = str(info.guid),
    kb = num(info.killingBlows),
    hk = num(info.honorableKills),
    deaths = num(info.deaths),
    honor = num(info.honorGained),
    damage = num(info.damageDone),
    healing = num(info.healingDone),
  }
  if row.rank and row.rank > 0 then
    row.title = ns.Rank and ns.Rank.Title
      and plain(try(ns.Rank.Title, row.rank, (row.faction == ALLIANCE) and "Alliance" or "Horde", row.gender))
      or nil
  end

  -- The objective columns. Their names and order are NeverSecret, their values are not, so the
  -- shape of the scoreboard is knowable live and the contents are not.
  local stats = info.stats
  if type(stats) == "table" then
    local out = {}
    for j = 1, #stats do
      local s = stats[j]
      if type(s) == "table" then
        local label = str(s.name)
        if label then out[#out + 1] = { name = label, value = num(s.pvpStatValue), order = num(s.orderIndex) or j } end
      end
    end
    if #out > 0 then row.stats = out end
  end
  return row
end

-- The whole scoreboard, split by faction. Never returns a half-built board: the count and the
-- rows are read in one pass, and a board with nobody in it comes back nil with a reason.
function Field.Board()
  if not (C_PvP and C_PvP.GetScoreInfo) then return nil, "this client has no battleground scoreboard" end
  if not Field.In() then return nil, "you are not in a battleground" end
  local n = num(try(GetNumBattlefieldScores)) or 0
  if n <= 0 then return nil, "the scoreboard has not arrived yet" end

  local side = mySide()
  local board = { us = {}, them = {}, unknown = {}, mine = side, sealed = Field.Sealed(),
                  factional = plain(try(C_PvP.IsMatchFactional)) == true,
                  cols = match and match.cols or nil }
  local me = myNames()
  for i = 1, n do
    local row = readRow(i)
    if row then
      if me[row.name:lower()] or (row.name:match("^[^-]+") and me[(row.name:match("^[^-]+")):lower()]) then
        row.me = true
        board.me = row
      end
      local bucket = board.unknown
      if side and row.faction then bucket = (row.faction == side) and board.us or board.them end
      bucket[#bucket + 1] = row
    end
  end
  -- A board that could not be split is worse than no board: it would report the enemy's ladder
  -- using your own team's ranks. Say so instead.
  if #board.us == 0 and #board.them == 0 then
    if #board.unknown == 0 then return nil, "the scoreboard has not arrived yet" end
    return nil, "the client would not say which side anyone is on"
  end
  return board
end

-- What a side amounts to. Ranks are averaged over the players who have one, not over the side:
-- a rank 0 recruit and a player the client declined to rank are different facts.
function Field.Shape(rows)
  if type(rows) ~= "table" then return nil end
  local shape = { n = #rows, classes = {}, healers = 0, ranked = 0, sum = 0, top = nil, ladder = {} }
  for i = 1, #rows do
    local r = rows[i]
    if r.token then
      shape.classes[r.token] = (shape.classes[r.token] or 0) + 1
      if CAN_HEAL[r.token] then shape.healers = shape.healers + 1 end
    end
    if r.rank and r.rank > 0 then
      shape.ranked = shape.ranked + 1
      shape.sum = shape.sum + r.rank
      shape.ladder[#shape.ladder + 1] = r
      if not shape.top or r.rank > shape.top.rank then shape.top = r end
    end
  end
  if shape.ranked > 0 then shape.avg = shape.sum / shape.ranked end
  table.sort(shape.ladder, function(a, b)
    if a.rank ~= b.rank then return a.rank > b.rank end
    return a.name < b.name
  end)
  return shape
end

-- Names on this scoreboard the dossier already knows. The scoreboard has no guild column, so this
-- is the only cross-reference available, and it is by name.
-- Names on that side the guild has died to. Separate from Field.Known on purpose: one is what you
-- have done to them and the other is what they have done to us, and the second is the half that
-- tells you who not to open on.
function Field.Feared(rows)
  if type(rows) ~= "table" or not (ns.Threat and ns.Threat.Of) then return {} end
  local out = {}
  for i = 1, #rows do
    local name = rows[i].name:match("^[^-]+") or rows[i].name
    local r, key = plain(try(ns.Threat.Of, name))
    if type(r) == "table" and (r.n or 0) > 0 then
      local spread = 0
      for _ in pairs(r.who or {}) do spread = spread + 1 end
      out[#out + 1] = { name = key or name, deaths = r.n, spread = spread, row = rows[i] }
    end
  end
  table.sort(out, function(a, b)
    if a.spread ~= b.spread then return a.spread > b.spread end
    return a.deaths > b.deaths
  end)
  return out
end

function Field.Known(rows)
  if type(rows) ~= "table" or not (ns.char and ns.char.victims) then return {} end
  local out = {}
  for i = 1, #rows do
    local short = rows[i].name:match("^[^-]+") or rows[i].name
    local v = ns.FindVictim and plain(try(ns.FindVictim, short)) or nil
    if type(v) == "table" and type(v.name) == "string" and v.name:lower() == short:lower() and (v.kills or 0) > 0 then
      out[#out + 1] = { name = short, kills = v.kills, row = rows[i] }
    end
  end
  table.sort(out, function(a, b) return a.kills > b.kills end)
  return out
end

--------------------------------------------------------------------------------
-- Saying it
--------------------------------------------------------------------------------

local function plural(n, one, many) return (n == 1) and one or many end

local function classLine(shape)
  local rows = {}
  for token, count in pairs(shape.classes) do rows[#rows + 1] = { token, count } end
  table.sort(rows, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[1] < b[1]
  end)
  local parts = {}
  for i = 1, math.min(#rows, 5) do
    local token = rows[i][1]
    parts[#parts + 1] = rows[i][2] .. " " .. token:sub(1, 1) .. token:sub(2):lower()
  end
  return table.concat(parts, ", ")
end

local function ladderLine(shape, how)
  if not shape.avg then return nil end
  local parts = {}
  for i = 1, math.min(#shape.ladder, how or 3) do
    local r = shape.ladder[i]
    parts[#parts + 1] = ("%s rank %d%s"):format(r.name:match("^[^-]+") or r.name, r.rank,
      r.token and (" " .. r.token:sub(1, 1) .. r.token:sub(2):lower()) or "")
  end
  return table.concat(parts, ", ")
end

function Field.Lines(board)
  if type(board) ~= "table" then return nil end
  local out = {}
  local us, them = Field.Shape(board.us), Field.Shape(board.them)

  if board.sealed then
    out[#out + 1] = "The match is on, so every number on that scoreboard is sealed. Here is what is not."
  end
  for _, pair in ipairs({ { "Yours", us }, { "Theirs", them } }) do
    local label, shape = pair[1], pair[2]
    if shape and shape.n > 0 then
      out[#out + 1] = ("%s: %d %s, %s."):format(label, shape.n, plural(shape.n, "player", "players"), classLine(shape))
      if shape.avg then
        out[#out + 1] = ("  Ladder: average rank %.1f over %d of them, highest %d (%s)."):format(
          shape.avg, shape.ranked, shape.top.rank, shape.top.name:match("^[^-]+") or shape.top.name)
      else
        out[#out + 1] = "  Ladder: nobody on that side is ranked yet."
      end
      if shape.healers > 0 then
        out[#out + 1] = ("  %d of them can heal."):format(shape.healers)
      end
    end
  end
  if us and them and us.avg and them.avg then
    local gap = them.avg - us.avg
    if math.abs(gap) >= 0.5 then
      out[#out + 1] = (gap > 0)
        and ("They are %.1f rungs above you on average. Expect them to know the map."):format(gap)
        or ("You are %.1f rungs above them on average."):format(-gap)
    else
      out[#out + 1] = "Both sides are about level on the ladder."
    end
  end
  local known = Field.Known(board.them)
  if #known > 0 then
    local parts = {}
    for i = 1, math.min(#known, 3) do
      parts[#parts + 1] = ("%s (%d)"):format(known[i].name, known[i].kills)
    end
    out[#out + 1] = ("You have killed %d of them before: %s."):format(#known, table.concat(parts, ", "))
  end
  local feared = Field.Feared(board.them)
  if #feared > 0 then
    local parts = {}
    for i = 1, math.min(#feared, 3) do
      parts[#parts + 1] = ("%s (%d of us, %d times)"):format(feared[i].name, feared[i].spread, feared[i].deaths)
    end
    out[#out + 1] = ("The guild has died to %d of them: %s."):format(#feared, table.concat(parts, ", "))
  end
  if board.cols and #board.cols > 0 then
    out[#out + 1] = "This one scores: " .. table.concat(board.cols, ", ") .. "."
  end
  -- Where the flag is, if this battleground has one. Last, because it is the only line here that
  -- will be different in ten seconds.
  local flag = ns.Flag and ns.Flag.Clause and plain(try(ns.Flag.Clause)) or nil
  if type(flag) == "string" then out[#out + 1] = flag end
  return out
end

-- The side in full, highest rung first, which is the order that matters: the top of this list is
-- who you should not open on alone.
function Field.Roster(rows, label)
  local shape = Field.Shape(rows)
  if not shape or shape.n == 0 then return { "Nobody on that side yet." } end
  local out = { ("%s, %d %s:"):format(label, shape.n, plural(shape.n, "player", "players")) }
  local seen = {}
  for i = 1, #shape.ladder do
    local r = shape.ladder[i]
    seen[r] = true
    out[#out + 1] = ("  %-2d %s%s%s"):format(r.rank, r.name:match("^[^-]+") or r.name,
      r.title and ("  " .. r.title) or "",
      r.token and ("  " .. r.token:sub(1, 1) .. r.token:sub(2):lower()) or "")
  end
  local rest = {}
  for i = 1, #rows do if not seen[rows[i]] then rest[#rest + 1] = rows[i].name:match("^[^-]+") or rows[i].name end end
  if #rest > 0 then
    table.sort(rest)
    out[#out + 1] = "  unranked: " .. table.concat(rest, ", ")
  end
  return out
end

--------------------------------------------------------------------------------
-- The scouting report
--------------------------------------------------------------------------------

-- Said once per match, and only when there is something in it worth saying. The roster fills in
-- over the first few seconds, so this waits rather than reporting half a team.
function Field.Scout(force)
  if scouted and not force then return nil end
  local board, why = Field.Board()
  if not board then return nil, why end
  local them = Field.Shape(board.them)
  if not them or them.n == 0 then return nil, "the other side has not been read yet" end
  scouted = true

  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.on ~= false and them.avg then
    local us = Field.Shape(board.us)
    local harder = us and us.avg and them.avg > us.avg + 0.5
    if ns.Stage and ns.Stage.Banner then
      pcall(ns.Stage.Banner,
        harder and "THEY OUTRANK YOU" or "SCOUTED",
        harder and RED or BLUE,
        ("%d of them, average rank %.1f, highest %d"):format(them.n, them.avg, them.top.rank),
        { size = 2 })
    end
    if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, harder and "heartbeat" or "horn") end
    if ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, harder and "fieldhard" or "field", 2) end
  end
  for _, line in ipairs(Field.Lines(board) or {}) do ns.Print(line) end
  if ns.Log then
    ns.Log("field", ("scouted: %d v %d, their average rank %s"):format(
      #board.us, #board.them, them.avg and ("%.1f"):format(them.avg) or "unknown"))
  end
  return board
end

--------------------------------------------------------------------------------
-- The finished match
--------------------------------------------------------------------------------

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.field = d.field or {}
  d.field.log = d.field.log or {}
  return d.field
end

-- Where a row placed on one measure, counting only the rows the client gave a number for. Returns
-- nil when the measure was never unsealed, which is not the same as placing last.
local function place(rows, key, row)
  local mine = row and row[key]
  if type(mine) ~= "number" then return nil end
  local above, counted = 0, 0
  for i = 1, #rows do
    local v = rows[i][key]
    if type(v) == "number" then
      counted = counted + 1
      if v > mine then above = above + 1 end
    end
  end
  if counted == 0 then return nil end
  return above + 1, counted
end

-- Read once the seal has lifted. Everything here is nil until PVP_MATCH_COMPLETE, so this is the
-- only place in the file that reports numbers.
function Field.Finish()
  local board, why = Field.Board()
  if not board then return nil, why end
  if board.sealed then return nil, "the match is not over, so the numbers are still sealed" end

  local all = {}
  for _, side in ipairs({ board.us, board.them }) do
    for i = 1, #side do all[#all + 1] = side[i] end
  end
  local card = {
    at = plain(try(time)), zone = str(try(GetRealZoneText)),
    us = #board.us, them = #board.them,
    winner = num(try(C_PvP.GetActiveMatchWinner)),
    duration = num(try(C_PvP.GetActiveMatchDuration)),
  }
  if card.winner and board.mine then card.won = (card.winner == board.mine) end

  local me = board.me
  if me then
    card.me = { name = me.name, kb = me.kb, hk = me.hk, deaths = me.deaths,
                honor = me.honor, damage = me.damage, healing = me.healing, rank = me.rank }
    card.me.kbPlace, card.me.kbOf = place(all, "kb", me)
    card.me.dmgPlace, card.me.dmgOf = place(all, "damage", me)
    card.me.healPlace, card.me.healOf = place(all, "healing", me)
    if type(me.stats) == "table" then
      local objectives = {}
      for i = 1, #me.stats do
        if (me.stats[i].value or 0) > 0 then objectives[#objectives + 1] = me.stats[i] end
      end
      if #objectives > 0 then card.me.objectives = objectives end
    end
  end

  -- Their best killer, by name. The scoreboard has no guild column so this cannot reach Rival's
  -- feud; it is here because knowing who did the damage is worth knowing on its own.
  local best
  for i = 1, #board.them do
    local r = board.them[i]
    if type(r.kb) == "number" and (not best or r.kb > best.kb) then best = r end
  end
  if best then card.theirBest = { name = best.name, kb = best.kb, token = best.token, rank = best.rank } end

  local r = db()
  if r then
    r.last = card
    r.log[#r.log + 1] = card
    while #r.log > KEEP do table.remove(r.log, 1) end
  end
  if ns.Log then
    ns.Log("field", ("match over: %s, %s killing blows"):format(
      (card.won == true and "won") or (card.won == false and "lost") or "no winner given",
      (card.me and card.me.kb) and tostring(card.me.kb) or "unknown"))
  end
  return card
end

function Field.Card(card)
  if type(card) ~= "table" then return nil end
  local out = {}
  local when = plain(try(date, "%H:%M", card.at))
  out[#out + 1] = ("%s%s%s:"):format(
    (card.won == true and "Won") or (card.won == false and "Lost") or "Match",
    card.zone and (" in " .. card.zone) or "",
    (type(when) == "string") and (" at " .. when) or "")
  if card.duration and card.duration > 0 then
    out[#out + 1] = ("  %d minutes, %d against %d."):format(math.floor(card.duration / 60 + 0.5), card.us or 0, card.them or 0)
  end
  local m = card.me
  if m then
    local bits = {}
    if m.kb then bits[#bits + 1] = m.kb .. " " .. plural(m.kb, "killing blow", "killing blows") end
    if m.hk then bits[#bits + 1] = m.hk .. " honorable" end
    if m.deaths then bits[#bits + 1] = m.deaths .. " " .. plural(m.deaths, "death", "deaths") end
    if m.honor then bits[#bits + 1] = m.honor .. " honor" end
    if #bits > 0 then out[#out + 1] = "  You: " .. table.concat(bits, ", ") .. "." end
    if m.damage or m.healing then
      out[#out + 1] = ("  %s%s."):format(
        m.damage and (ns.Recap and ns.Recap.Comma and ns.Recap.Comma(m.damage) or tostring(m.damage)) .. " damage" or "",
        m.healing and ((m.damage and ", " or "") ..
          (ns.Recap and ns.Recap.Comma and ns.Recap.Comma(m.healing) or tostring(m.healing)) .. " healing") or "")
    end
    local ranks = {}
    if m.kbPlace then ranks[#ranks + 1] = ("%d of %d on killing blows"):format(m.kbPlace, m.kbOf) end
    if m.dmgPlace then ranks[#ranks + 1] = ("%d of %d on damage"):format(m.dmgPlace, m.dmgOf) end
    if m.healPlace and (m.healing or 0) > 0 then ranks[#ranks + 1] = ("%d of %d on healing"):format(m.healPlace, m.healOf) end
    if #ranks > 0 then out[#out + 1] = "  Placed " .. table.concat(ranks, ", ") .. "." end
    if m.objectives then
      local parts = {}
      for i = 1, #m.objectives do parts[#parts + 1] = m.objectives[i].name .. " " .. m.objectives[i].value end
      out[#out + 1] = "  Objectives: " .. table.concat(parts, ", ") .. "."
    end
  else
    out[#out + 1] = "  Your own row was not on the scoreboard the client handed over."
  end
  if card.theirBest then
    out[#out + 1] = ("  Their best was %s%s, %d %s."):format(
      card.theirBest.name:match("^[^-]+") or card.theirBest.name,
      card.theirBest.rank and (" at rank " .. card.theirBest.rank) or "",
      card.theirBest.kb, plural(card.theirBest.kb, "killing blow", "killing blows"))
  end
  return out
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Field.handlers

local function startMatch()
  if match then return end
  match = { at = plain(try(GetTime)) or 0 }
  scouted, nextPoll = false, 0
  local get = C_PvP and C_PvP.GetMatchPVPStatColumns
  local cols = plain(try(get))
  if type(cols) == "table" then
    local names = {}
    for i = 1, #cols do
      local n = str(cols[i] and cols[i].name)
      if n then names[#names + 1] = n end
    end
    if #names > 0 then match.cols = names end
  end
  -- Ask at once rather than waiting for the first tick: the roster is at its fullest before the
  -- gates open, and that is also the only window where nobody has left yet.
  nextPoll = (plain(try(GetTime)) or 0) + GAP
  try(RequestBattlefieldScoreData)
  local after = C_Timer and C_Timer.After
  if type(after) == "function" then try(after, SCOUT_AT, function() Field.Scout() end) end
end

local function endMatch()
  match, scouted, nextPoll = nil, false, 0
end

function h.PLAYER_JOINED_PVP_MATCH()
  startMatch()
end

function h.PVP_MATCH_ACTIVE()
  startMatch()
end

function h.PVP_MATCH_COMPLETE()
  -- Read on the next frame. The seal lifts on this event, and the client's own results frame
  -- rebuilds its table from the same one, so reading inside the handler can still catch the
  -- match marked active and hand back a board full of secrets.
  local after = C_Timer and C_Timer.After
  local function read()
    try(RequestBattlefieldScoreData)
    local card, why = Field.Finish()
    if not card then
      if ns.Log then ns.Log("field", "no final board: " .. tostring(why)) end
      endMatch()
      return
    end
    local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
    if o.on ~= false and card.won ~= nil then
      if ns.Stage and ns.Stage.Banner then
        pcall(ns.Stage.Banner, card.won and "VICTORY" or "DEFEAT", card.won and GOLD or RED,
          (card.me and card.me.kb) and (card.me.kb .. " killing blows") or "", { size = 3 })
      end
      if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, card.won and "fanfare" or "powerdown") end
      if ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, card.won and "fieldwon" or "fieldlost", 3) end
    end
    for _, line in ipairs(Field.Card(card) or {}) do ns.Print(line) end
    endMatch()
  end
  if type(after) == "function" then try(after, 1, read) else read() end
end

function h.UPDATE_BATTLEFIELD_SCORE()
  if not match then return end
  -- The roster is read when the client says it has changed, and the first read that finds both
  -- sides populated is allowed to bring the scouting report forward.
  if not scouted then
    local board = Field.Board()
    if board and #board.them > 0 and #board.us > 0 then Field.Scout() end
  end
end

-- A world change means this is a different battleground, so the old one is dropped whether or not
-- it ever reported itself complete. Leaving a match early never fires PVP_MATCH_COMPLETE, and
-- without this the next battleground inherits the last one's `scouted` flag and the report that
-- tells you what you have walked into never comes.
function h.PLAYER_ENTERING_WORLD()
  endMatch()
  if Field.In() then startMatch() end
end

-- The poll. The client's own scoreboard calls RequestBattlefieldScoreData every frame while it is
-- open; once every ten seconds is enough to catch people joining and leaving, and the roster is
-- the only thing that can change while the numbers are sealed.
function Field.Tick(now)
  if not match then return end
  now = now or plain(try(GetTime)) or 0
  if now < nextPoll then return end
  nextPoll = now + GAP
  try(RequestBattlefieldScoreData)
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

function Field.Command(rest)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()

  if rest == "last" then
    local r = db()
    local card = r and r.last
    if not card then
      ns.Print("No finished match in the book yet.")
      return
    end
    for _, line in ipairs(Field.Card(card) or {}) do ns.Print(line) end
    if r and #r.log > 1 then ns.Print(("%d matches kept."):format(#r.log)) end
    return
  end

  local board, why = Field.Board()
  if not board then
    ns.Print("No scoreboard: " .. tostring(why) .. ".")
    if not (C_PvP and C_PvP.GetScoreInfo) then
      ns.Print("GetBattlefieldScore here is only a deprecation shim over this same call, behind the loadDeprecationFallbacks CVar, so there is nothing else to fall back to.")
    end
    return
  end
  if rest == "them" or rest == "enemy" then
    for _, line in ipairs(Field.Roster(board.them, "Theirs")) do ns.Print(line) end
    return
  end
  if rest == "us" or rest == "mine" then
    for _, line in ipairs(Field.Roster(board.us, "Yours")) do ns.Print(line) end
    return
  end

  for _, line in ipairs(Field.Lines(board) or {}) do ns.Print(line) end
  ns.Print("/godslayer field them for their roster by rung.")
end

function Field.Init()
  if not (C_PvP and C_PvP.GetScoreInfo) then
    if ns.Log then ns.Log("field", "no C_PvP.GetScoreInfo on this client") end
    return
  end
  if Field.In() then startMatch() end
  local ticker = C_Timer and C_Timer.NewTicker
  if type(ticker) == "function" then try(ticker, POLL, function() Field.Tick() end) end
end
