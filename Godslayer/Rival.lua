-- Godslayer without Olympus, and the gnome problem.
--
-- Olympus is Asmongold's guild: Alliance, PvP ruleset, past ten thousand members in the beta.
-- Horde Olympus guilds exist and run the same addon. None of that is a promise about the realm
-- we actually get on 11-04. Before this file, `Classify` answered nil for every guild that was
-- not Olympus, and nil means unscored, so a realm without them left the addon inert: no points,
-- no title ever moving, an empty leaderboard and a kill banner that never fired.
--
-- Three widening rings now, and the addon finds its own target if it has to:
--
--   original / network   Olympus, exactly as before, 5 and 1 points
--   rival                one guild, nominated by you or by the addon, 3 points
--   any                  every other player kill, one point, tracked, voiced, dossiered
--
-- Since 2.7.0 the rings are open from the first login. Olympus took the PvE ruleset at launch
-- (2026-11-04) and rulesets are separate megaservers, so the sighting the old three-session
-- wait was waiting for can never come. The Olympus tiers stay wired and still pay first if a
-- name ever matches; they are a bonus now, not a gate.
--
--   /godslayer rival              what the addon is hunting, and why
--   /godslayer rival <guild>      nominate one by hand; shared with the guild
--   /godslayer rival off          no rival, and no nominating; the one-point baseline stays
--   /godslayer gnomes             the gnome count and what it has made you
--
-- Races come from the dossier, which reads `GetPlayerInfoByGUID`. That function carries no
-- secrecy annotation in the Forever API, unlike `UnitRace` and `UnitClass` which go secret when
-- unit identity is restricted, so the victim's race survives where a unit token would not.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Rival = {}
ns.Rival = Rival

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.wide = d.wide or {}
  local w = d.wide
  w.feud = w.feud or {}        -- [guild] = { mine = kills you landed, theirs = deaths you owe them }
  w.race = w.race or {}        -- [raceToken] = kills, for the gnome counter and the race callouts
  w.quiet = w.quiet or 0       -- consecutive sessions with no Olympus guild seen
  return w
end

-- ---------------------------------------------------------------------------
-- Which ring a guild sits in
-- ---------------------------------------------------------------------------

-- Olympus always answers first and is never overridden: if the real thing is on the realm, it is
-- the hunt. Past that comes the nominated rival, and then the open ring, which since 2.7.0 is
-- unconditional: Olympus took the PvE ruleset at launch, so on this megaserver the open ring IS
-- the game, and a mode where most kills score nothing starved the titles and broke the board.
-- The one way a guild scores nothing now is the ignore list, which stays the player's to use.
function ns.ClassifyWide(guild)
  local tier = ns.Classify(guild)
  if tier then return tier end
  if type(guild) ~= "string" then return nil end
  if guild == "" then return "any" end -- a victim seen with no guild at all
  local norm = ns.NormGuild(guild)
  if norm == "" then return "any" end
  if GodslayerDB.ignore[norm] then return nil end
  local w = db()
  if w and w.rival and norm == w.rival then return "rival" end
  return "any"
end

-- ---------------------------------------------------------------------------
-- Keeping score of who the realm's actual problem is
-- ---------------------------------------------------------------------------

local function feudOf(guild)
  local w = db()
  if not w then return nil end
  local norm = ns.NormGuild(guild or "")
  if norm == "" then return nil end
  local f = w.feud[norm]
  if not f then f = { mine = 0, theirs = 0, name = guild } w.feud[norm] = f end
  f.name = guild or f.name
  return f, norm
end

-- Blood either way counts, but a death to them counts double: the guild that keeps killing you
-- is the one you have a problem with, whatever your own kill count says.
local function heat(f)
  return (f.mine or 0) + (f.theirs or 0) * (ns.RIVAL.theirKillWeight or 2)
end

local function nominate()
  local w = db()
  if not w or w.rivalLocked then return nil end
  local best, bestNorm, bestHeat = nil, nil, 0
  local total = 0
  for norm, f in pairs(w.feud) do
    local h = heat(f)
    total = total + (f.mine or 0) + (f.theirs or 0)
    if h > bestHeat then best, bestNorm, bestHeat = f, norm, h end
  end
  if not best or total < (ns.RIVAL.minEncounters or 8) then return nil end
  return bestNorm, best, bestHeat
end

-- ---------------------------------------------------------------------------
-- What the addon was told
-- ---------------------------------------------------------------------------

-- Called for every kill Core registers, scored or not, so the open ring can keep its own counts
-- without Score having to know this file exists.
function Rival.NoteKill(id, guild, tier)
  local w = db()
  if not w then return end
  if tier == "original" or tier == "network" then w.seenOlympus = true w.quiet = 0 end
  -- Race is counted by the client's TOKEN, which is the fourth return of GetPlayerInfoByGUID and
  -- not the third. The third is the localised name, and the two are different strings: in
  -- ChrRaces the Undead are id 5, name "Undead", token "Scourge", and a Night Elf is "Night Elf"
  -- against "NightElf". Keying on the localised name counts a Horde player's own race under a
  -- name no table here knows, and counts nothing at all on a client that is not in English.
  -- The dossier only ever learns the localised name, so it is no use for this and is not asked.
  local race = nil
  if type(id) == "string" and id:sub(1, 7) == "Player-" then
    local _, _, _, token = try(GetPlayerInfoByGUID, id)
    token = plain(token)
    if type(token) == "string" and token ~= "" and ns.RACE_TOKENS[token] then race = token end
  end
  if guild and guild ~= "" then
    local f = feudOf(guild)
    if f then f.mine = (f.mine or 0) + 1 end
  end
  if race then
    local token = race
    w.race[token] = (w.race[token] or 0) + 1
    if token == "Gnome" then
      local before = w.gnomeRank
      local rank = Rival.GnomeRank(w.race.Gnome)
      if rank and rank ~= before then
        w.gnomeRank = rank
        if ns.Hype and ns.Hype.GnomeRank then ns.Hype.GnomeRank(rank, w.race.Gnome) end
      end
    end
  end
  -- Re-check the nomination every so often rather than on every kill: a rival should be a
  -- standing fact about the realm, not something that flickers between two guilds all evening.
  local reviewAfter = ns.RIVAL.reviewAfter or 200
  w.since = (w.since or 0) + 1
  if w.on and w.since >= reviewAfter then
    w.since = 0
    local norm, f = nominate()
    if norm and norm ~= w.rival then
      w.rival = norm
      ns.Print(("New rival: %s. They have the most blood between you."):format(f.name or norm))
    end
  end
end

-- A death only matters here for picking a rival, and it is deliberately the heavier signal.
function Rival.NoteDeath(guild)
  local w = db()
  if not w or not guild or guild == "" then return end
  local f = feudOf(guild)
  if f then f.theirs = (f.theirs or 0) + 1 end
end

-- A kill scored with no tag turned out to have a guild. The race was already counted when the
-- kill scored, so this feeds only the feud, and the Olympus sighting if that is what it was.
function Rival.NoteUpgrade(guild, tier)
  local w = db()
  if not w or not guild or guild == "" then return end
  if tier == "original" or tier == "network" then w.seenOlympus = true w.quiet = 0 end
  local f = feudOf(guild)
  if f then f.mine = (f.mine or 0) + 1 end
end

function Rival.GnomeRank(n)
  if type(n) ~= "number" then return nil end
  local title
  for _, row in ipairs(ns.GNOME_RANKS) do
    if n >= row[1] then title = row[2] else break end
  end
  return title
end

-- ---------------------------------------------------------------------------
-- Opening the rings
-- ---------------------------------------------------------------------------

-- At login. The quiet-session count stays as the record of what this realm has shown, but the
-- hunt no longer waits on it: Olympus launched on the PvE ruleset (2026-11-04), a different
-- megaserver, so the wait for a sighting that can never come was retired in 2.7.0. The rings
-- are open from the first login, and only /godslayer rival off stops the nominating.
function Rival.OnLogin()
  local w = db()
  if not w then return end
  if w.seenOlympus then
    w.quiet = 0
  else
    w.quiet = (w.quiet or 0) + 1
  end
  w.seenOlympus = false
  if w.opened or w.off then return end
  w.on, w.opened = true, 1
  ns.Print("Every player kill counts now, one point each, and I will name you a rival worth three "
      .. "once there is enough blood to pick one. /godslayer rival to see where that stands.")
end

-- ---------------------------------------------------------------------------
-- Command
-- ---------------------------------------------------------------------------

function Rival.Command(rest)
  local w = db()
  if not w then return end
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", "")

  if rest == "off" then
    w.on, w.off, w.rival, w.rivalLocked = nil, true, nil, nil
    ns.Print("Rival cleared, and I will not pick another. Every kill still counts one point; the Olympus tiers still pay if they ever show.")
    return
  end
  if rest == "on" then
    w.on, w.off = true, nil
    ns.Print("I will name you a rival again once there is enough blood to pick one. Rival kills count three.")
    return
  end
  if rest == "clear" then
    w.rival, w.rivalLocked = nil, nil
    ns.Print("Rival cleared. I will pick one again from whoever bleeds most.")
    return
  end

  if rest ~= "" then
    local norm = ns.NormGuild(rest)
    if norm == "" then ns.Print("That is not a guild name I can use.") return end
    w.on, w.off = true, nil
    w.rival, w.rivalLocked = norm, true
    local f = feudOf(rest)
    ns.Print(("Rival set: %s. Worth %d points a kill, and it will not change on its own."):format(rest, ns.RIVAL_POINTS))
    if f and (f.mine or 0) + (f.theirs or 0) > 0 then
      ns.Print(("So far: %d of theirs down, %d of yours owed."):format(f.mine or 0, f.theirs or 0))
    end
    if ns.Comm and ns.Comm.ShareRival then ns.Comm.ShareRival(rest) end
    return
  end

  -- Bare command: say where the hunt stands and why.
  if not w.on then
    ns.Print("Every kill counts one point. You turned the rival hunt off; /godslayer rival on brings it back.")
    return
  end
  if w.rival then
    local f = w.feud[w.rival]
    ns.Print(("Rival: %s, %d points a kill%s."):format((f and f.name) or w.rival, ns.RIVAL_POINTS,
        w.rivalLocked and ", set by you" or ", picked from the blood between you"))
    if f then ns.Print(("%d of theirs down, %d of yours owed."):format(f.mine or 0, f.theirs or 0)) end
  else
    local norm, f, h = nominate()
    if norm then
      ns.Print(("No rival named yet. The strongest case is %s (%d of theirs, %d of yours)."):format(f.name or norm, f.mine or 0, f.theirs or 0))
    else
      ns.Print(("The hunt is open but nobody has bled enough yet: it needs %d encounters with one guild."):format(ns.RIVAL.minEncounters or 8))
    end
  end
end

function Rival.GnomeCommand()
  local w = db()
  if not w then return end
  local n = w.race and w.race.Gnome or 0
  if n == 0 then
    ns.Print("No gnomes yet. They are down there somewhere.")
    return
  end
  local title = Rival.GnomeRank(n) or "Gnome Starter Kit"
  ns.Print(("Gnomes: %d. That makes you %s."):format(n, title))
  local nextRow
  for _, row in ipairs(ns.GNOME_RANKS) do if row[1] > n then nextRow = row break end end
  if nextRow then ns.Print(("%d more for %s."):format(nextRow[1] - n, nextRow[2])) end
  -- Everything else you have killed, biggest first, so the gnome number has company.
  local rows = {}
  for token, count in pairs(w.race) do if token ~= "Gnome" then rows[#rows + 1] = { token, count } end end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  if #rows > 0 then
    local parts = {}
    for i = 1, math.min(#rows, 5) do parts[#parts + 1] = rows[i][1] .. " " .. rows[i][2] end
    ns.Print("Also: " .. table.concat(parts, ", ") .. ".")
  end
end
