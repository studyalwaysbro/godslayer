-- Randomised soak test: lua tests/fuzz.lua [runs] [events per run]
-- Throws random event storms (including secret values and garbage addon messages) at a
-- fresh copy of the addon and checks the books still balance afterwards.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local RUNS, EVENTS = tonumber(arg[1]) or 1000, tonumber(arg[2]) or 250
local FILES = { "Data.lua", "Core.lua", "Comm.lua", "UI.lua" }
local ME, MATE, STRANGER = "Player-1-0000AAAA", "Player-1-0000BBBB", "Player-1-0000CCCC"
local GUILDS = { "OLYMPUS", "OLYMPUS", "Olympus Kitchen", "OLYMPUS BETZ", "OLYMPUS XIlI", "HOELYMPUS", "The Enclave",
                 "0lympus", "Method", "The True Torchmen", "Olympic Swim Team", "", "x|cffff0000y|r", "Olympus;S;1", false }
local TOKENS = { "target", "mouseover", "focus", "softenemy", "nameplate1", "nameplate2", "nameplate3", "nameplate17", "nameplate40" }
local GARBAGE = { "", ";", "S", "S;1", "S;1;;;;;;", "S;1;1;1;1;1;1;MAGE;1.0.0", "S;1;5;25;5;5;5;MAGE;1.0.0;5", "S;1;-1;0;0;0;0",
                  "S;1;1e99;1;1;1;1", "S;1;3;3;3;3;0;mage;v", "H;1", "H;2", "H", "S;1;2;10;2;0;2;|cff;|r;2", ("S;1;"):rep(60),
                  "S;1;1.5;2;1;0;0", "S;1;2;2;3;0;0", "S;1;2;2;1;3;0", "S;1;nan;inf;1;1;1" }
local failures, totalKills, totalEvents = 0, 0, 0

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
  GodslayerDB, GodslayerFrame, GodslayerWindow, GodslayerMinimapButton, M.failTemplate = nil, nil, nil, nil, R(10) == 1
  M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", faction = "Horde" })
  local ns = M.load("Godslayer", FILES)
  M.fire("ADDON_LOADED", "Godslayer"); M.fire("PLAYER_LOGIN")
  local c = ns.char
  local players, opportunities = {}, 0
  for i = 1, 12 do
    local g = GUILDS[R(#GUILDS)]
    players[i] = { name = (R(8) == 1 and "Asmongold Asmongler" or ("Enemy" .. i .. " Last" .. i)), guid = ("Player-1-%08X"):format(i),
                   guild = g or nil, class = R(2) == 1 and "WARRIOR" or "MAGE", faction = R(6) == 1 and "Horde" or "Alliance",
                   secretGUID = R(25) == 1, secretGuild = R(25) == 1, secretName = R(25) == 1 }
    M.guids[players[i].guid] = players[i]
  end
  local slash = SlashCmdList["GODSLAYER"]
  local function anyGUID()
    local r = R(10)
    if r == 1 then return M.secret() elseif r == 2 then return "Creature-0-1-2-3-4-0000000001" elseif r == 3 then return nil end
    return players[R(#players)].guid
  end
  for _ = 1, EVENTS do
    local e = R(22)
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
      slash(({ "", "stats", "share", "top", "guilds", "log", "demo", "help", "sound", "toast", "chat", "tooltip", "minimap",
               "add Method", "ignore OLYMPUS BETZ", "unignore OLYMPUS BETZ", "remove Method", "ignore Olympus", "unignore Olympus",
               "add", "ignore   ", "reset", "reset roster", "bogus |cff", "add %s%d", "ignore ;;;" })[R(26)])
    elseif e == 20 then
      local f = GodslayerFrame or GodslayerWindow
      if f and f.tabs then
        f.tabs[R(3)].__scripts.OnClick()
        f.list.__scripts.OnMouseWheel(nil, R(2) == 1 and 1 or -1)
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
  if #M.sentAddon > 40 + EVENTS / 2 then fail(seed, "addon channel spam: " .. #M.sentAddon) end
  totalKills = totalKills + c.kills
end
M.realPrint(("%d runs, %d events, %d kills scored, %d failures"):format(RUNS, totalEvents, totalKills, failures))
os.exit(failures == 0 and 0 or 1)
