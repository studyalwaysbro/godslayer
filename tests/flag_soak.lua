-- Randomised WSG flag soak: lua tests/flag_soak.lua [runs] [events per run] [first seed]
-- Mixes chat, widgets, positions, reloads and zone changes. Cooldown-governed voices may not
-- repeat early, no banner may leave unknown, and no event/timer error may escape.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local RUNS, EVENTS, FIRST = tonumber(arg[1]) or 500, tonumber(arg[2]) or 250, tonumber(arg[3]) or 1
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Sound.lua", "Stage.lua", "Hype.lua", "Flag.lua" }
local ME = "Player-1-0000AAAA"
local failures, voices, totalEvents = 0, 0, 0

local function fail(seed, message)
  failures = failures + 1
  if failures <= 20 then M.realPrint(("FAIL seed %d: %s"):format(seed, message)) end
end

for seed = FIRST, FIRST + RUNS - 1 do
  math.randomseed(seed)
  local R = math.random
  M.now, M.wall, M.timers, M.units, M.guids, M.group = 1000, 1791400000, {}, {}, {}, {}
  M.frames, M.sentAddon, M.sentChat, M.printed = { UIParent, Minimap, GameTooltip }, {}, {}, {}
  M.inGuild, M.inCombat, M.hk, M.dk = true, false, 0, 0
  M.zone, M.subzone, M.myLevel = "Warsong Gulch", "", 60
  M.bg = { state = Enum.PvPMatchState.Engaged, rows = {}, factional = true, cols = { "Flag Captures" } }
  M.map = { id = 1339, north = 1000, west = 1000, tall = 1000, wide = 1000 }
  M.widgets, M.flags, M.arenaFaction, M.secretArenaFaction = {}, {}, R(0, 1), nil
  M.widget(1891, 1, "0")
  M.widget(1892, 1, "0")
  M.audio.files, M.audio.lengths, M.audio.played, M.audio.stopped, M.audio.kits = {}, {}, {}, {}, {}
  M.audio.cvars = { Sound_EnableAllSound = "1", Sound_EnableMusic = "1", Sound_EnableDialog = "1", Sound_EnableAmbience = "1",
    Sound_DialogVolume = "0.8", Sound_AmbienceVolume = "0.7", Sound_MusicVolume = "0.8" }
  M.audio.cvarWrites, M.audio.next = {}, 0
  M.setSpoken(nil)
  GodslayerDB = nil
  M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE",
    race = "Scourge", sex = 2, faction = "Horde", isMe = true })

  local ns, before, voiceContext, lastCooldownVoice
  local function instrument()
    before = { Alliance = ns.Flag.State("Alliance"), Horde = ns.Flag.State("Horde") }
    voiceContext, lastCooldownVoice = nil, lastCooldownVoice or { Alliance = -100000, Horde = -100000 }
    ns.Stage.FlagBanner = function(flag, title)
      if before[flag] == "unknown" then fail(seed, flag .. " banner escaped unknown on " .. tostring(title)) end
      voiceContext = { flag = flag, title = title }
    end
    ns.Hype.Say = function()
      voices = voices + 1
      local c = voiceContext
      if not c then fail(seed, "voice had no flag banner context") return true end
      if c.title:find("DOWN", 1, true) or c.title:find("RE-PICKED", 1, true) or c.title:find("RETURNED", 1, true) then
        local gap = GodslayerDB.opts.flag.repeatGap
        if M.now - lastCooldownVoice[c.flag] < gap - 0.001 then
          fail(seed, ("%s cooldown voice repeated after %.2fs (gap %d)"):format(c.flag, M.now - lastCooldownVoice[c.flag], gap))
        end
        lastCooldownVoice[c.flag] = M.now
      end
      voiceContext = nil
      return true
    end
  end

  local function loadCopy(reload)
    if reload then
      M.frames, M.timers = { UIParent, Minimap, GameTooltip }, {}
      GodslayerFrame, GodslayerHypeBanner = nil, nil
      lastCooldownVoice = nil
    end
    ns = M.load("Godslayer", FILES)
    M.fire("ADDON_LOADED", "Godslayer")
    M.fire("PLAYER_LOGIN")
    GodslayerDB.opts.flag.calls = ({ "important", "all", "off" })[R(3)]
    GodslayerDB.opts.flag.repeatGap = R(10, 30)
    instrument()
  end

  loadCopy(false)
  local ok, err = pcall(M.advance, 1.1)
  if not ok then fail(seed, "initial widget timer escaped: " .. tostring(err)) end

  local allianceCaps, hordeCaps = 0, 0
  local chatLines = {
    "The Horde flag was picked up by Sneak!", "The Alliance flag was picked up by Runner!",
    "The Horde flag was dropped by Sneak!", "The Alliance flag was dropped by Runner!",
    "The Horde flag was returned to its base by Guard!", "The Alliance flag was returned to its base by Guard!",
    "The Horde flag is now placed at its base.", "The Alliance flag is now placed at its base.",
    "Sneak captured the Horde flag!", "Runner captured the Alliance flag!",
    "The flags are now placed at their bases.", "Die Flagge wurde aufgenommen!",
  }

  for _ = 1, EVENTS do
    totalEvents = totalEvents + 1
    before = { Alliance = ns.Flag.State("Alliance"), Horde = ns.Flag.State("Horde") }
    voiceContext = nil
    local action = R(12)
    local success, problem = pcall(function()
      if action <= 4 then
        local line = chatLines[R(#chatLines)]
        if R(30) == 1 then line = M.secret() end
        M.fire(({ "CHAT_MSG_BG_SYSTEM_ALLIANCE", "CHAT_MSG_BG_SYSTEM_HORDE", "CHAT_MSG_BG_SYSTEM_NEUTRAL" })[R(3)], line)
      elseif action <= 7 then
        local id = R(2) == 1 and 1891 or 1892
        local row = M.widgets[id] or { state = 1, text = "0" }
        local state = R(3)
        if R(8) == 1 then
          if id == 1891 then allianceCaps = allianceCaps + 1 else hordeCaps = hordeCaps + 1 end
        end
        local count = id == 1891 and allianceCaps or hordeCaps
        M.widget(id, state, tostring(count))
        M.fire("UPDATE_UI_WIDGET", R(25) == 1 and M.secret() or { widgetID = id, widgetSetID = 1, widgetType = 0 })
      elseif action <= 9 then
        local rows = {
          { north = R(200, 800), west = R(200, 800), texture = 137200, onMap = R(5) ~= 1 },
          { north = R(200, 800), west = R(200, 800), texture = 137218, onMap = R(5) ~= 1 },
        }
        if R(2) == 1 then rows[1], rows[2] = rows[2], rows[1] end
        M.flagsAt(rows)
        M.playerAt(R(200, 800), R(200, 800))
        M.advance(R() * 3)
        ns.Flag.Tick()
      elseif action == 10 then
        M.fire(R(2) == 1 and "PLAYER_ENTERING_WORLD" or "ZONE_CHANGED_NEW_AREA")
        lastCooldownVoice = { Alliance = -100000, Horde = -100000 }
        if R(2) == 1 then M.advance(R() * 3) end
      elseif action == 11 then
        loadCopy(true)
        if R(2) == 1 then M.advance(R() * 3) end
      else
        M.advance(R() * 5)
      end
    end)
    if not success then fail(seed, "event/timer error escaped: " .. tostring(problem)) end
    if ns.errors then fail(seed, "handler errors: " .. tostring(ns.errors)); ns.errors = nil end
  end

  before = { Alliance = ns.Flag.State("Alliance"), Horde = ns.Flag.State("Horde") }
  local ended, endErr = pcall(M.advance, 20)
  if not ended then fail(seed, "final timers escaped: " .. tostring(endErr)) end
  for _, line in ipairs(GodslayerDB.log or {}) do
    if line:find(" error: ", 1, true) then fail(seed, line) end
  end
end

M.realPrint(("%d flag runs from seed %d, %d events, %d voices, %d failures")
  :format(RUNS, FIRST, totalEvents, voices, failures))
os.exit(failures == 0 and 0 or 1)
