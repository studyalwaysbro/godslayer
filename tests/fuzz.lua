-- Randomised soak test: lua tests/fuzz.lua [runs] [events per run]
-- Throws random event storms (including secret values and garbage addon messages) at a
-- fresh copy of the addon and checks the books still balance afterwards.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local RUNS, EVENTS = tonumber(arg[1]) or 1000, tonumber(arg[2]) or 250
local FILES = { "Data.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Comm.lua", "UI.lua" }
local ME, MATE, STRANGER = "Player-1-0000AAAA", "Player-1-0000BBBB", "Player-1-0000CCCC"
local GUILDS = { "OLYMPUS", "OLYMPUS", "Olympus Kitchen", "OLYMPUS BETZ", "OLYMPUS XIlI", "HOELYMPUS", "The Enclave",
                 "0lympus", "Method", "The True Torchmen", "Olympic Swim Team", "", "x|cffff0000y|r", "Olympus;S;1", false }
local TOKENS = { "target", "mouseover", "focus", "softenemy", "nameplate1", "nameplate2", "nameplate3", "nameplate17", "nameplate40" }
local GARBAGE = { "", ";", "S", "S;1", "S;1;;;;;;", "S;1;1;1;1;1;1;MAGE;1.0.0", "S;1;5;25;5;5;5;MAGE;1.0.0;5", "S;1;-1;0;0;0;0",
                  "S;1;1e99;1;1;1;1", "S;1;3;3;3;3;0;mage;v", "H;1", "H;2", "H", "S;1;2;10;2;0;2;|cff;|r;2", ("S;1;"):rep(60),
                  "S;1;1.5;2;1;0;0", "S;1;2;2;3;0;0", "S;1;2;2;1;3;0", "S;1;nan;inf;1;1;1" }
local ZONES = { "Stranglethorn Vale", "Hillsbrad Foothills", "Ashenvale", "", "Zone|cffff0000 Red|r", ("Long Zone Name "):rep(8),
                "Sen\195\177ora's Rest", "A\nB", "Elsewhere" }
local RACES = { "Human", "Dwarf", "Night Elf", "Gnome", "", "R|ace", ("Race"):rep(30) }
local RANKS = { "Guild Master", "Lord", "Captain", "Member", "", "Rank|cff", ("Rank "):rep(20), "Sen\195\177or" }
local SLASHES = { "hype", "hype test", "hype test olympus", "hype test king", "hype stop", "hype pack herald", "hype pack titan", "hype pack zz", "hype voice off", "hype voice on",
                  "hype guild off", "hype guild on", "hype pack mix", "hype pack frost", "hype pack naturalist", "hype mix sable off", "hype mix sable on", "hype mix", "hype sfx off", "hype sfx on",
                  "hype spot off", "hype spot on", "hype multi off", "hype multi on", "hype asides off", "hype asides on", "hype theme off", "hype theme on", "hype audition", "hype audition valkyrie",
                  "hype say rampage", "hype say nothing", "hype test spot", "hype test king spot", "hype window 20", "hype blows", "hype all", "hype off", "hype on", "", "stats", "share", "top", "guilds", "log", "demo", "help", "sound", "toast", "chat", "tooltip", "minimap",
                  "add Method", "ignore OLYMPUS BETZ", "unignore OLYMPUS BETZ", "remove Method", "ignore Olympus", "unignore Olympus",
                  "add", "ignore   ", "reset", "reset roster", "bogus |cff", "add %s%d", "ignore ;;;",
                  "dossier Enemy", "dossier Enemy3 Last3", "dossier", "dossier %s|cff", "who asmon", "nemesis", "hitlist" }
local failures, totalKills, totalEvents, migrated, dossiers = 0, 0, 0, 0, 0

-- A database the way 1.0.0 wrote it: totals that add up, victims with none of the new fields.
local function oldDatabase(R)
  local c = { uniques = 0, kb = 0, class = "MAGE", orig = 0, kills = 0, points = 0, kings = 0, bestStreak = R(0, 5), guilds = {}, victims = {} }
  local known = {}
  for i = 1, R(0, 8) do
    local original = R(2) == 1
    local guild = original and "OLYMPUS" or "Olympus Kitchen"
    local kills = R(1, 6)
    local kb = R(0, kills)
    local points = kills * (original and 5 or 1)
    local id = ("Player-1-%08X"):format(R(1, 16)) -- some of these are the players of this run
    if not c.victims[id] then
      c.victims[id] = { kills = kills, points = points, kb = kb, ok = original and kills or nil, first = 1791000000, last = 1791300000,
                        guild = guild, tier = original and "original" or "network", name = "Old Victim" .. i, class = "ROGUE" }
      c.kills, c.points, c.uniques, c.kb, c.orig = c.kills + kills, c.points + points, c.uniques + 1, c.kb + kb, c.orig + (original and kills or 0)
      local g = c.guilds[guild] or { kills = 0, points = 0, tier = original and "original" or "network" }
      g.kills, g.points = g.kills + kills, g.points + points
      c.guilds[guild] = g
    end
    known[("Player-1-%08X"):format(R(1, 30))] = { n = "Old Sighting" .. i, g = "OLYMPUS XII", c = "SHAMAN", t = 1791399000 }
  end
  return { version = 1, log = {}, roster = {}, ignore = {}, custom = {}, known = known,
           opts = { minimap = true, toast = true, tooltip = true, sound = true, chat = true },
           chars = { ["Vesh Torchman"] = c } }, c.kills
end

local function text(v) return v == nil or (type(v) == "string" and #v <= 40 and #v > 0 and not v:find("[|%c]")) end

local function fail(seed, msg)
  failures = failures + 1
  if failures <= 20 then M.realPrint(("FAIL seed %d: %s"):format(seed, msg)) end
end

for seed = 1, RUNS do
  math.randomseed(seed)
  local R = math.random
  -- fresh client
  M.now, M.wall, M.timers, M.units, M.guids, M.group = 1000, 1791400000, {}, {}, {}, { [MATE] = true }
  M.sentAddon, M.sentChat, M.printed, M.lockdown, M.inGuild, M.hk, M.addonResult = {}, {}, {}, false, true, R(0, 40), 0
  M.frames = { UIParent, Minimap, GameTooltip }
  M.zone, M.subzone, M.myLevel, M.secretZone, M.secretMyLevel, M.dateError = "Stranglethorn Vale", "Booty Bay", R(1, 60), nil, nil, nil
  GodslayerDB, GodslayerFrame, GodslayerWindow, GodslayerMinimapButton, M.failTemplate = nil, nil, nil, nil, R(10) == 1
  local inherited = 0
  if R(3) == 1 then GodslayerDB, inherited = oldDatabase(R); migrated = migrated + 1 end
  M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", faction = "Horde" })
  local ns = M.load("Godslayer", FILES)
  M.fire("ADDON_LOADED", "Godslayer"); M.fire("PLAYER_LOGIN")
  -- every announcer line exists on disk, so the voice really queues and plays in this soak
  M.audio.files, M.audio.played, M.audio.music = {}, {}, nil
  for id, pack in pairs(ns.VOICE) do
    for clip in pairs(pack.clips) do M.audio.files["Interface\\AddOns\\Godslayer\\Sounds\\" .. id .. "\\" .. clip .. ".ogg"] = true end
  end
  if R(2) == 1 then M.audio.files["Interface\\AddOns\\GodslayerMusic\\kill.mp3"] = true end
  local c = ns.char
  local players, opportunities = {}, inherited
  for i = 1, 12 do
    local g = GUILDS[R(#GUILDS)]
    players[i] = { name = (R(8) == 1 and "Asmongold Asmongler" or ("Enemy" .. i .. " Last" .. i)), guid = ("Player-1-%08X"):format(i),
                   guild = g or nil, class = R(2) == 1 and "WARRIOR" or "MAGE", faction = R(6) == 1 and "Horde" or "Alliance",
                   secretGUID = R(25) == 1, secretGuild = R(25) == 1, secretName = R(25) == 1,
                   level = ({ R(1, 60), R(1, 60), -1, nil, 0, 250, 12.5 })[R(7)], race = RACES[R(#RACES)], sex = ({ 1, 2, 3, nil, 9 })[R(5)],
                   rank = RANKS[R(#RANKS)], secretLevel = R(12) == 1, secretRace = R(12) == 1, secretSex = R(12) == 1,
                   secretRank = R(12) == 1, secretTitle = R(12) == 1 }
    players[i].pvpName = ({ nil, "Sergeant " .. players[i].name, players[i].name .. ", the Unyielding", "Unrelated Title", "|cffKnight|r " .. players[i].name,
                            ("Marshal "):rep(20) .. players[i].name, players[i].name:match("^%S+") })[R(7)]
    M.guids[players[i].guid] = players[i]
  end
  local slash = SlashCmdList["GODSLAYER"]
  local function anyGUID()
    local r = R(10)
    if r == 1 then return M.secret() elseif r == 2 then return "Creature-0-1-2-3-4-0000000001" elseif r == 3 then return nil end
    return players[R(#players)].guid
  end
  for _ = 1, EVENTS do
    local e = R(27)
    if e <= 4 then
      local token = TOKENS[R(#TOKENS)]
      M.units[token] = (R(4) == 1) and nil or players[R(#players)]
      M.fire(({ "PLAYER_TARGET_CHANGED", "UPDATE_MOUSEOVER_UNIT", "PLAYER_FOCUS_CHANGED", "NAME_PLATE_UNIT_ADDED" })[R(4)], R(9) == 1 and M.secret() or token)
    elseif e <= 8 then
      local attacker = ({ ME, ME, ME, MATE, STRANGER, M.secret(), nil })[R(7)]
      local victim = anyGUID()
      if (attacker == ME or attacker == MATE) and type(victim) == "string" then opportunities = opportunities + 1 end
      M.fire("PARTY_KILL", attacker, victim)
    elseif e <= 10 then
      if R(2) == 1 then M.fire("UNIT_DIED", anyGUID()) else
        local p = players[R(#players)]; p.dead = R(2) == 1; p.feign = R(9) == 1
        M.fire("UNIT_HEALTH", R(9) == 1 and M.secret() or TOKENS[R(#TOKENS)])
      end
    elseif e <= 12 then
      M.hk = M.hk + R(0, 2); opportunities = opportunities + 5
      for _ = 1, R(1, 2) do M.fire("PLAYER_PVP_KILLS_CHANGED", "player") end
    elseif e == 13 then
      local p = players[R(#players)]
      local line = ({ p.name .. " dies, honorable kill (Estimated Honor Points: 3)", "You have been awarded 3 honor points.",
                      (p.name:match("^%S+")) .. " dies, honorable kill Rank: Private (Estimated Honor Points: 1)", "", "%s%d%%", M.secret() })[R(6)]
      if type(line) == "string" and line:find("dies") then opportunities = opportunities + 1 end
      M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", line)
    elseif e <= 15 then
      local sender = ({ "Brakka Ashmane", "Zul Embertusk", "Vesh Torchman", "A|cffB", "", M.secret() })[R(6)]
      M.fire("CHAT_MSG_ADDON", R(8) == 1 and M.secret() or "Godslayer", R(12) == 1 and M.secret() or GARBAGE[R(#GARBAGE)], R(6) == 1 and "PARTY" or "GUILD", sender)
    elseif e == 16 then
      M.advance(({ 0.2, 1, 3, 7, 12, 45, 1000 })[R(7)])
    elseif e == 17 then
      M.fire("PLAYER_DEAD")
    elseif e == 18 then
      M.lockdown = R(3) == 1; M.inGuild = R(8) ~= 1; M.addonResult = ({ 0, 0, 0, 3, 8, 9, 10, 11 })[R(8)]
      local p = players[R(#players)]; p.guild = GUILDS[R(#GUILDS)] or nil -- people change guilds
    elseif e == 19 then
      slash(SLASHES[R(#SLASHES)])
    elseif e == 20 then
      local f = GodslayerFrame or GodslayerWindow
      if f and f.tabs then
        f.tabs[R(5)].__scripts.OnClick()
        f.list.__scripts.OnMouseWheel(nil, R(2) == 1 and 1 or -1)
        -- click a row (a dossier opens on the kill log), scroll it, brag, maybe go back
        local row = f.rows[R(#f.rows)]
        row.__scripts.OnMouseUp(row); row.__scripts.OnEnter(row); row.__scripts.OnLeave(row)
        row.__scripts.OnMouseWheel(row, R(2) == 1 and 1 or -1)
        if R(2) == 1 then f.bragVictim.__scripts.OnClick() end
        if R(2) == 1 then f.back.__scripts.OnClick() end
      end
    elseif e == 23 then
      -- we move, level up, or the client hides where we are
      M.zone, M.subzone = ZONES[R(#ZONES)], ZONES[R(#ZONES)]
      M.myLevel = ({ R(1, 60), R(1, 60), -1, 0 })[R(4)]
      M.secretZone, M.secretMyLevel, M.dateError = R(8) == 1 or nil, R(8) == 1 or nil, R(30) == 1 or nil
    elseif e == 24 then
      -- a player changes how they look to us
      local p = players[R(#players)]
      p.level, p.rank, p.race = ({ R(1, 60), -1, nil })[R(3)], RANKS[R(#RANKS)], RACES[R(#RACES)]
      p.secretLevel, p.secretRank, p.secretRace, p.secretSex, p.secretTitle = R(6) == 1, R(6) == 1, R(6) == 1, R(6) == 1, R(6) == 1
    elseif e == 25 then
      M.wall = M.wall + ({ 3600, 86400, 3 * 86400 })[R(3)] -- the feud runs for days (wall clock only: no need to tick every timer)
    elseif e == 26 then
      -- farm one player hard: the per-victim lists must stay bounded
      local p = players[R(#players)]
      M.units.target = p; M.fire("PLAYER_TARGET_CHANGED")
      for i = 1, R(5, 30) do
        M.advance(11); M.zone = "Farm Zone " .. R(40)
        opportunities = opportunities + 1
        M.fire("PARTY_KILL", ME, p.guid)
      end
    elseif e == 21 then
      if M.tooltipHook then GameTooltip.__unit = R(3) == 1 and M.secret() or TOKENS[R(#TOKENS)]; GameTooltip.__lines = {}; M.tooltipHook(GameTooltip) end
    else
      M.fire("PLAYER_ENTERING_WORLD"); M.fire("PLAYER_GUILD_UPDATE", "player")
    end
  end
  M.advance(30)
  totalEvents = totalEvents + EVENTS

  -- the books must balance
  if ns.errors then fail(seed, "handler errors: " .. tostring(ns.errors)) end
  if #ns.Hype.Queued() > 7 then fail(seed, "the announcer queue grew past its cap: " .. #ns.Hype.Queued()) end
  -- no two lines start closer together than the first one's length allows
  local prev
  for _, p in ipairs(M.audio.played) do
    local pack, clip = p.path:match("Sounds\\(%a+)\\([%w_]+)%.ogg$")
    if clip then
      if prev and p.at - prev.at < prev.length - 0.5 - 0.02 then fail(seed, "two announcer lines overlapped: " .. prev.clip .. " then " .. clip) end
      prev = { at = p.at, clip = clip, length = ns.VOICE[pack].clips[clip] }
    end
  end
  for _, line in ipairs(GodslayerDB.log) do if line:find(" error: ", 1, true) then fail(seed, line) end end
  for _, line in ipairs(M.printed) do if line:find("command failed", 1, true) or line:find("Could not build", 1, true) then fail(seed, line) end end
  local kills, points, uniques, kb, orig = 0, 0, 0, 0, 0
  for id, v in pairs(c.victims) do
    if v.tier then
      if ns.Classify(v.guild) ~= v.tier then fail(seed, "victim tier out of date: " .. tostring(v.guild)) end
      local ok = v.ok or 0
      if ok > v.kills or v.points ~= ok * 5 + (v.kills - ok) then fail(seed, "victim points wrong for " .. id) end
      kills, points, uniques, kb, orig = kills + v.kills, points + v.points, uniques + 1, kb + (v.kb or 0), orig + ok
    end
    if (v.kb or 0) > v.kills then fail(seed, "more killing blows than kills on " .. id) end
    if type(v.name) ~= "string" then fail(seed, "victim without a name") end
    -- the dossier fields: bounded, plain, and consistent with the kill count
    if not (text(v.race) and text(v.rank) and text(v.title)) then fail(seed, "bad dossier text on " .. id) end
    if v.level ~= nil and not (type(v.level) == "number" and v.level >= 1 and v.level <= 200 and v.level == math.floor(v.level)) then fail(seed, "bad level " .. tostring(v.level)) end
    if v.sex ~= nil and v.sex ~= 2 and v.sex ~= 3 then fail(seed, "bad sex " .. tostring(v.sex)) end
    if v.up ~= nil and type(v.up) ~= "number" then fail(seed, "bad level gap") end
    local hist = v.hist or {}
    if #hist > ns.HIST_CAP or #hist > v.kills then fail(seed, "history too long: " .. #hist .. " for " .. v.kills .. " kills") end
    local blows = 0
    for i, h in ipairs(hist) do
      if #h ~= 6 or type(h[1]) ~= "number" or type(h[2]) ~= "string" or type(h[3]) ~= "string" or (h[4] ~= 0 and h[4] ~= 1)
         or type(h[5]) ~= "number" or type(h[6]) ~= "number" or #h[2] > 40 or #h[3] > 40 or h[2]:find("[|%c]") or h[3]:find("[|%c]") then
        fail(seed, "malformed history entry on " .. id)
      end
      if i > 1 and h[1] < hist[i - 1][1] then fail(seed, "history out of order") end
      blows = blows + h[4]
    end
    if blows > (v.kb or 0) then fail(seed, "history has more killing blows than the victim") end
    local zoneKeys, zoneKills, hourKills = 0, 0, 0
    for zone, n in pairs(v.zones or {}) do
      zoneKeys, zoneKills = zoneKeys + 1, zoneKills + n
      if not text(zone) then fail(seed, "bad zone name") end
    end
    for hour, n in pairs(v.hours or {}) do
      hourKills = hourKills + n
      if type(hour) ~= "number" or hour < 0 or hour > 23 or hour ~= math.floor(hour) then fail(seed, "bad hour " .. tostring(hour)) end
    end
    if zoneKeys > ns.ZONE_CAP + 1 or zoneKills > v.kills or hourKills > v.kills then fail(seed, "zone or hour counts exceed the kills") end
    local rankKeys, rankKills = 0, 0
    for rank, n in pairs(v.ranks or {}) do
      rankKeys, rankKills = rankKeys + 1, rankKills + n
      if not text(rank) then fail(seed, "bad rank name") end
    end
    if rankKeys > ns.RANK_CAP + 1 or rankKills > v.kills then fail(seed, "rank counts exceed the kills") end
    if (v.today or 0) > v.kills or (v.dayBest or 0) > v.kills or (v.bestRun or 0) > v.kills or (v.today or 0) > (v.dayBest or 0) then fail(seed, "daily or run record exceeds the kills") end
    for _, line in ipairs(ns.UI.DossierLines(id)) do
      if type(line[1]) ~= "string" or type(line[2]) ~= "string" then fail(seed, "dossier line is not text") end
    end
    dossiers = dossiers + 1
  end
  for id, k in pairs(GodslayerDB.known) do
    if not (text(k.r) and text(k.k) and text(k.p) and text(k.z)) or (k.l ~= nil and (type(k.l) ~= "number" or k.l < 1 or k.l > 200))
       or (k.s ~= nil and k.s ~= 2 and k.s ~= 3) or type(k.n) ~= "string" or type(k.g) ~= "string" then
      fail(seed, "bad sighting record " .. id)
    end
  end
  if GodslayerDB.version ~= 2 then fail(seed, "data version not set") end
  local agg = ns.Aggregates()
  if agg.kills ~= c.kills then fail(seed, "aggregates disagree with the total") end
  local sums = { class = 0, zone = 0, rank = 0, hour = 0 }
  for name, total in pairs(sums) do for _, n in pairs(agg[name]) do sums[name] = sums[name] + n end end
  if sums.class > c.kills or sums.zone > c.kills or sums.rank > c.kills or sums.hour > c.kills or sums.zone ~= agg.zoned or sums.hour ~= agg.timed then fail(seed, "aggregate split exceeds the total") end
  if ns.KillsToday() > c.kills then fail(seed, "more kills today than ever") end
  local nemesis = ns.Nemesis()
  for _, v in pairs(c.victims) do if v.tier and v.kills >= 2 and (not nemesis or v.kills > nemesis.kills) then fail(seed, "nemesis is not the most killed") end end
  for _, k in ipairs(ns.HitList()) do
    local v = c.victims[k.id]
    if (v and v.tier) or not ns.Classify(k.guild) then fail(seed, "hit list holds a killed or outside player") end
  end
  -- the running totals must already equal what a recount from the victims gives
  local before = { c.kills, c.points, c.uniques, c.kb, c.orig }
  ns.Recount()
  if before[1] ~= c.kills or before[2] ~= c.points or before[3] ~= c.uniques or before[4] ~= c.kb or before[5] ~= c.orig then
    fail(seed, ("running totals drifted: %d->%d kills, %d->%d points, %d->%d unique, %d->%d kb, %d->%d orig")
      :format(before[1], c.kills, before[2], c.points, before[3], c.uniques, before[4], c.kb, before[5], c.orig))
  end
  if c.kills ~= kills or c.points ~= points or c.uniques ~= uniques or c.kb ~= kb or c.orig ~= orig then
    fail(seed, ("recount mismatch: %d/%d kills %d/%d points"):format(c.kills, kills, c.points, points))
  end
  if c.kills > opportunities then fail(seed, ("%d kills from %d possible"):format(c.kills, opportunities)) end
  if c.points < c.kills or c.points > c.kills * 5 or c.kb > c.kills or (c.kings or 0) < 0 then fail(seed, "totals out of range") end
  local board = ns.Comm.Leaderboard()
  for i = 2, #board do
    if board[i - 1].points < board[i].points then fail(seed, "leaderboard not sorted") end
  end
  for _, r in ipairs(board) do
    if r.name:find("|", 1, true) or r.points > r.kills * 5 or r.points < r.kills then fail(seed, "bad roster row: " .. r.name) end
  end
  for _, m in ipairs(M.sentChat) do
    if m[2] ~= "GUILD" then fail(seed, "chat left the guild channel: " .. tostring(m[2])) end
    if #m[1] > 255 or m[1]:find("[{}|\n]") then fail(seed, "bad chat line: " .. m[1]) end
  end
  for i = 2, #M.sentChat do end
  for _, m in ipairs(M.sentAddon) do
    if m[3] ~= "GUILD" or #m[2] > 255 or m[1] ~= "Godslayer" then fail(seed, "bad addon message: " .. m[2]) end
  end
  -- our totals go out at most once every five seconds, however long or busy the session
  local lastStats
  for _, m in ipairs(M.sentAddon) do
    if m[2]:sub(1, 2) == "S;" then
      if lastStats and m[4] - lastStats < 4.99 then fail(seed, ("stats broadcast %.2fs after the last one"):format(m[4] - lastStats)) end
      lastStats = m[4]
    end
  end
  if #M.sentAddon > 8 + (M.now - 1000) / 5 then fail(seed, "addon channel spam: " .. #M.sentAddon .. " in " .. (M.now - 1000) .. "s") end
  totalKills = totalKills + c.kills
end
M.realPrint(("%d runs (%d starting from a 1.0.0 database), %d events, %d kills scored, %d dossiers checked, %d failures")
  :format(RUNS, migrated, totalEvents, totalKills, dossiers, failures))
os.exit(failures == 0 and 0 or 1)
