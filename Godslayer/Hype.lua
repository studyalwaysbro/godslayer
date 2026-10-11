-- Godslayer hype: your kill song, and an announcer who takes Olympus personally.
--
-- THE HUNT. The first player you kill starts it: your song begins and FIRST BLOOD is called.
-- Every kill after that, while the hunt is on, climbs a rung: MEGA KILL, ULTRA KILL, GODLIKE
-- and on up. Each kill keeps the hunt alive for another stretch (90 seconds unless you change
-- it). It ends when that runs out with nobody dead, or when you die: SHUT DOWN, the music
-- fades, and the zone's own music comes back.
--
-- OLYMPUS. A kill on the Olympus network gets its own script. The call (A GOD BLEEDS, DOUBLE
-- SACRILEGE, TITANOMACHY, REGICIDE), then the points out loud (one for the network, five for
-- the King's own guild), then now and then a dry remark, and your new title when you earn one.
--
-- THE GUILD. When a guildmate's score goes up, you hear about it.
--
-- The song is yours to supply: a file named kill.mp3 (or kill.ogg) in a folder called
--   Interface\AddOns\GodslayerMusic
-- That folder is never touched by an update. With no file there the announcer still works.
-- The song plays as game music, so it replaces the zone music, follows your music volume and
-- fades the way the game's own tracks do. The voice plays on the master channel so it cuts
-- through. Only you hear any of it. Nothing here sends anything to anyone.

local ADDON, ns = ...

local Hype = {}
ns.Hype = Hype

local SOUNDS = "Interface\\AddOns\\Godslayer\\Sounds\\"
local OWN = "Interface\\AddOns\\GodslayerMusic\\"
local SONGS = { OWN .. "kill.mp3", OWN .. "kill.ogg" }
local FADE_MS = 2500
local CALL_DELAY = 0.45    -- kills landing together get one call, for where the count ended up
local OVERLAP = 0.5        -- the next line starts this long before the last one's hall has died away
local BANNER_SECONDS = 3.6
local ASIDE_CHANCE = 0.4   -- how often a dry remark follows the points
local RARE_CHANCE = 0.05   -- and how often, instead, one of the lines you will hear a handful of times ever
local ALLY_GAP = 45        -- seconds between spoken guild kills; the chat line is never held back
local QUEUE_MAX = 7

-- rung reached by this many kills in one hunt; the last one repeats from there on
local LADDER = {
  { 1, "FIRST BLOOD", "first_blood", { 1, 0.82, 0.2 } },
  { 2, "MEGA KILL", "mega_kill", { 1, 0.6, 0.1 } },
  { 3, "ULTRA KILL", "ultra_kill", { 1, 0.42, 0.05 } },
  { 4, "GODLIKE", "godlike", { 1, 0.25, 0.1 } },
  { 5, "UNSTOPPABLE", "unstoppable", { 1, 0.15, 0.25 } },
  { 6, "BEYOND GODLIKE", "beyond_godlike", { 0.95, 0.2, 0.75 } },
  { 7, "GODSLAYER", "godslayer", { 0.7, 0.35, 1 } },
}
Hype.LADDER = LADDER

-- Olympus kills in a row without dying: the clip, and the words on the banner
local SACRILEGE = {
  { 2, "double_sacrilege", "DOUBLE SACRILEGE" }, { 3, "triple_heresy", "TRIPLE HERESY" }, { 4, "quad_blasphemy", "QUAD BLASPHEMY" },
  { 5, "titanomachy", "TITANOMACHY" }, { 7, "twilight", "TWILIGHT OF THE GODS" }, { 10, "hill", "OLYMPUS IS A HILL NOW" },
  { 15, "zeus_left", "ZEUS HAS LEFT THE CHAT" },
}
local GOLD, GODRED = { 1, 0.82, 0.2 }, { 1, 0.3, 0.12 }

local function issecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function plain(v) if issecret(v) then return nil end return v end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

local hunt          -- { kills, music = "music" | handle | nil, turn }
local songPath      -- the song found this session; false once we know there is none
local banner

local function opts()
  local o = GodslayerDB.opts
  if type(o.hype) ~= "table" then o.hype = {} end
  local h = o.hype
  if h.on == nil then h.on = true end
  if h.voice == nil then h.voice = true end
  if h.music == nil then h.music = true end
  if h.guild == nil then h.guild = true end
  if h.mode ~= "blows" then h.mode = "all" end -- all = any kill you get credit for; blows = only your own killing blows
  if not (ns.VOICE and ns.VOICE[h.pack]) then h.pack = "titan" end
  h.window = math.max(20, math.min(600, tonumber(h.window) or 90))
  return h
end
Hype.Opts = opts

local function rungFor(kills)
  local rung = LADDER[1]
  for _, r in ipairs(LADDER) do
    if kills >= r[1] then rung = r end
  end
  return rung
end
Hype.RungFor = rungFor

-- THE BANNER --------------------------------------------------------------------
local function buildBanner()
  local f = CreateFrame("Frame", "GodslayerHypeBanner", UIParent)
  f:SetSize(760, 100)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("HIGH")
  local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  f.title = f:CreateFontString(nil, "OVERLAY")
  f.title:SetFont(font, 44, "THICKOUTLINE")
  f.title:SetPoint("TOP", 0, 0)
  f.line = f:CreateFontString(nil, "OVERLAY")
  f.line:SetFont(font, 17, "OUTLINE")
  f.line:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
  f.line:SetTextColor(1, 1, 1)
  f:Hide()
  return f
end

local bannerTurn = 0
local function showBanner(title, color, line)
  if not banner then
    local ok, made = pcall(buildBanner)
    if not ok or not made then return end
    banner = made
  end
  banner.title:SetText(title)
  banner.title:SetTextColor(color[1], color[2], color[3])
  banner.line:SetText(line or "")
  if type(UIFrameFadeRemoveFrame) == "function" then pcall(UIFrameFadeRemoveFrame, banner) end
  banner:SetAlpha(1)
  banner:Show()
  bannerTurn = bannerTurn + 1
  local mine = bannerTurn
  C_Timer.After(BANNER_SECONDS, function()
    if mine ~= bannerTurn or not banner then return end
    if type(UIFrameFadeOut) == "function" and pcall(UIFrameFadeOut, banner, 0.8, 1, 0) then
      C_Timer.After(0.85, function() if mine == bannerTurn then banner:Hide() end end)
    else
      banner:Hide()
    end
  end)
end

-- THE VOICE -------------------------------------------------------------------
-- Lines are spoken one after another, never over each other. Each is { clip, weight }: a kill
-- call outranks the points, the points outrank a dry remark, and when a new call arrives the
-- remarks still waiting from the last kill are dropped so the voice never falls behind the fight.
local queue, busyUntil, pumping = {}, 0, false
local lastPick = {}

local function soundOn()
  return plain(try(GetCVar, "Sound_EnableAllSound")) ~= "0"
end

local function clipLength(clip)
  local pack = ns.VOICE and ns.VOICE[opts().pack]
  return pack and pack.clips[clip]
end
Hype.ClipLength = clipLength

-- One of clip_1, clip_2 ... that this pack has, and never the same one twice running.
local function pick(group)
  local count = 0
  while clipLength(group .. "_" .. (count + 1)) do count = count + 1 end
  if count == 0 then return clipLength(group) and group or nil end
  local n = math.random(count)
  if count > 1 and n == lastPick[group] then n = n % count + 1 end
  lastPick[group] = n
  return group .. "_" .. n
end
Hype.Pick = pick

local function playNow(clip)
  local pack = opts().pack
  -- lines re-pitched to your own song (tools/tune_announcer.py writes them) come first
  local own = try(PlaySoundFile, OWN .. "voice\\" .. pack .. "\\" .. clip .. ".ogg", "Master")
  if not plain(own) then try(PlaySoundFile, SOUNDS .. pack .. "\\" .. clip .. ".ogg", "Master") end
end

local pump
pump = function()
  pumping = false
  local wait = busyUntil - GetTime()
  if wait > 0.01 then
    pumping = true
    C_Timer.After(wait, pump)
    return
  end
  local item = table.remove(queue, 1)
  if not item then return end
  local length = clipLength(item[1]) or 1.5
  playNow(item[1])
  busyUntil = GetTime() + math.max(0.4, length - OVERLAP)
  if queue[1] then
    pumping = true
    C_Timer.After(busyUntil - GetTime(), pump)
  end
end

-- weight: 3 = a kill call, 2 = points and titles, 1 = a remark
local function speak(lines)
  if not GodslayerDB or not opts().voice or not soundOn() then return end
  local hasCall = false
  for _, line in ipairs(lines) do if line[2] >= 3 then hasCall = true end end
  if hasCall then
    for i = #queue, 1, -1 do
      if queue[i][2] <= 1 then table.remove(queue, i) end
    end
  end
  for _, line in ipairs(lines) do
    if line[1] and clipLength(line[1]) then
      if #queue >= QUEUE_MAX then
        -- full: the newest line that matters less than this one gives up its place
        for i = #queue, 1, -1 do
          if queue[i][2] < line[2] then table.remove(queue, i) break end
        end
      end
      if #queue < QUEUE_MAX then queue[#queue + 1] = line end
    end
  end
  if not pumping then pump() end
end

function Hype.Speaking() return #queue > 0 or GetTime() < busyUntil end
function Hype.Queued()
  local names = {}
  for i, line in ipairs(queue) do names[i] = line[1] end
  return names
end

local function hush()
  queue = {}
end

-- THE SONG ----------------------------------------------------------------------
-- Finds the player's own song the first time it is needed. A file that is not there simply
-- does not play, which is how we know.
local function findSong()
  if songPath ~= nil then return songPath end
  songPath = false
  for _, path in ipairs(SONGS) do
    local willPlay, handle = try(PlaySoundFile, path, "Master")
    if plain(willPlay) then
      if plain(handle) then try(StopSound, handle, 0) end
      songPath = path
      break
    end
  end
  return songPath
end

local function startMusic()
  if not opts().music or not soundOn() then return nil end
  local path = findSong()
  if not path then return nil end
  -- as game music it loops, replaces the zone music and fades out by itself when stopped
  if plain(try(GetCVar, "Sound_EnableMusic")) ~= "0" and type(PlayMusic) == "function" and pcall(PlayMusic, path) then
    return "music"
  end
  -- music is switched off in the options: play it as an ordinary sound instead
  local willPlay, handle = try(PlaySoundFile, path, "Master")
  if plain(willPlay) and plain(handle) then return handle end
  return nil
end

local function stopMusic(how)
  if not how then return end
  if how == "music" then try(StopMusic) else try(StopSound, how, FADE_MS) end
end

-- THE HUNT ----------------------------------------------------------------------
function Hype.Active() return hunt ~= nil end
function Hype.Kills() return hunt and hunt.kills or 0 end

local function endHunt(reason)
  local h = hunt
  if not h then return end
  hunt = nil
  stopMusic(h.music)
  if reason == "died" and h.kills >= 2 then
    hush()
    speak({ { "shut_down", 3 } })
    showBanner("SHUT DOWN", { 0.75, 0.75, 0.75 }, ("Your hunt ended at %d kills."):format(h.kills))
  elseif reason ~= "quiet" then
    hush()
  end
  local best = GodslayerDB.opts.hype.best or 0
  if h.kills > best and not h.pretend then GodslayerDB.opts.hype.best = h.kills end
end
Hype.End = endHunt

local function arm(h)
  h.turn = (h.turn or 0) + 1
  local turn, window = h.turn, opts().window
  C_Timer.After(window, function()
    if hunt == h and h.turn == turn then endHunt("quiet") end
  end)
end

-- Kills waiting out CALL_DELAY: by victim, so an Olympus score arriving in that moment can
-- take the call over instead of following a generic one.
local waiting, flushQueued = {}, false

local function progressLine()
  local c = ns.char
  if not (c and ns.RANKS) then return nil end
  for _, rank in ipairs(ns.RANKS) do
    if rank[1] > (c.points or 0) then
      return ("%d to %s"):format(rank[1] - c.points, rank[2])
    end
  end
end

local function sacrilege(streak)
  local best
  for _, s in ipairs(SACRILEGE) do
    if streak >= s[1] then best = s end
  end
  return best
end

-- The lines for one Olympus kill, in the order they are spoken.
local function olympusLines(o)
  local lines = {}
  local info, v = o.info or {}, o.v or {}
  local ladder = sacrilege(info.streak or 1)
  if info.king then lines[1] = { "regicide", 3 }
  elseif ladder then lines[1] = { ladder[2], 3 }
  else lines[1] = { pick(o.tier == "original" and "olympus" or "god_down"), 3 } end
  lines[2] = { pick(o.pts >= 5 and "plus_five" or "plus_one"), 2 }
  local roll = math.random()
  if o.firstToday then
    lines[#lines + 1] = { "first_today", 1 }
  elseif roll < RARE_CHANCE then
    lines[#lines + 1] = { pick("rare"), 1 }
  elseif (v.kills or 0) >= 3 and roll < 0.6 then
    lines[#lines + 1] = { pick("repeat"), 1 }
  elseif roll < RARE_CHANCE + ASIDE_CHANCE then
    lines[#lines + 1] = { pick("tail"), 1 }
  end
  if info.rankUp and o.rankIndex and clipLength("title_" .. o.rankIndex) then
    lines[#lines + 1] = { "new_title", 2 }
    lines[#lines + 1] = { "title_" .. o.rankIndex, 2 }
  end
  return lines, ladder
end
Hype.OlympusLines = olympusLines

-- Calls and shows a batch of Olympus kills that were scored together. huntKills is the count
-- to show beside them, or nil when they are not part of what is happening right now.
local function announceGods(gods, huntKills)
  -- the King first, then a kill that earned a title, then the longest streak
  local function rank(o) return (o.info.king and 2000 or 0) + (o.info.rankUp and 1000 or 0) + (o.info.streak or 1) end
  table.sort(gods, function(a, b) return rank(a) > rank(b) end)
  local top = gods[1]
  local lines, ladder = olympusLines(top)
  local points, promoted = 0, top.info.rankUp and top or nil
  for _, g in ipairs(gods) do
    points = points + g.pts
    promoted = promoted or (g.info.rankUp and g)
  end
  if #gods > 1 then lines[2] = { "plus_many", 2 } end
  if promoted and promoted ~= top and promoted.rankIndex and clipLength("title_" .. promoted.rankIndex) then
    lines[#lines + 1] = { "new_title", 2 }
    lines[#lines + 1] = { "title_" .. promoted.rankIndex, 2 }
  end
  speak(lines)
  local title = top.info.king and "REGICIDE" or (ladder and ladder[3]) or (top.tier == "original" and "OLYMPUS BLEEDS" or "OLYMPIAN DOWN")
  local name = top.v and top.v.name
  local parts = { (name or "An Olympian") .. (#gods > 1 and (" and " .. (#gods - 1) .. " more") or ""), "|cffffd100+" .. points .. "|r" }
  local progress = progressLine()
  if promoted then parts[#parts + 1] = "|cffff7d0aNew title: " .. promoted.info.rankUp .. "|r"
  elseif progress then parts[#parts + 1] = "|cffbbbbbb" .. progress .. "|r" end
  if huntKills and huntKills > 1 then parts[#parts + 1] = "|cffffd100x" .. huntKills .. "|r" end
  showBanner(title, top.tier == "original" and GOLD or GODRED, table.concat(parts, "    "))
end

local function flush()
  flushQueued = false
  local batch = waiting
  waiting = {}
  if not opts().on then return end -- switched off while a kill was waiting to be called
  local generic, gods = nil, {}
  for _, w in pairs(batch) do
    if w.olympus then gods[#gods + 1] = w.olympus elseif not generic or w.kills > generic.kills then generic = w end
  end
  if #gods > 0 then
    announceGods(gods, hunt and hunt.kills)
  elseif generic then
    speak({ { pick(rungFor(generic.kills)[3]), 3 } })
  end
end

local function queueFlush()
  if flushQueued then return end
  flushQueued = true
  C_Timer.After(CALL_DELAY, flush)
end

-- One kill. who = the victim's name if known, id = what the core calls them. Called by the
-- core for every player kill you get credit for, once per victim.
function Hype.Kill(who, killingBlow, id, pretend)
  if not GodslayerDB then return end
  local o = opts()
  if not o.on then return end
  if o.mode == "blows" and not killingBlow then return end
  if not hunt then
    hunt = { kills = 0 }
    hunt.music = startMusic()
  end
  local h = hunt
  if pretend then h.pretend = true end -- a hunt with a test kill in it is never a record
  h.kills = h.kills + 1
  arm(h)
  local rung = rungFor(h.kills)
  local name = type(who) == "string" and who ~= "" and who or nil
  showBanner(rung[2], rung[4], (name and (name .. " is dead") or "A kill") .. (h.kills > 1 and ("    |cffffd100x" .. h.kills .. "|r") or ""))
  local key = id or (name or "?") .. "#" .. h.kills
  local w = waiting[key] or {}
  w.kills, w.who = h.kills, name
  waiting[key] = w
  queueFlush()
end

-- The core has scored a kill on the Olympus network. If the kill is still waiting to be
-- called, this takes the call over; if the generic call already went out (the guild tag
-- arrived late), the Olympus lines follow it.
function Hype.Olympus(id, v, tier, pts, info, rankIndex)
  if not GodslayerDB then return false end
  local o = opts()
  if not o.on then return false end
  info = info or {}
  -- "my killing blows only" covers the Olympus lines too
  if o.mode == "blows" and not info.kb then return false end
  local olympus = { v = v, tier = tier, pts = tonumber(pts) or 1, info = info, rankIndex = rankIndex,
                    firstToday = ns.KillsToday and ns.KillsToday() == 1 }
  local w = id and waiting[id]
  if w then
    w.olympus = olympus
    queueFlush()
  else
    -- the guild tag arrived after this kill was called. It is announced on its own, at once,
    -- and never borrows the count or the call of whatever kill is waiting now.
    announceGods({ olympus }, nil)
  end
  return o.voice and soundOn()
end

function Hype.Died()
  waiting = {}
  endHunt("died")
end

-- A guildmate's score went up. A line in chat, and a spoken one now and then, never over your
-- own fight. The numbers come from another player's client, so they are rationed per sender:
-- nobody can make your announcer talk all evening by sending made-up scores.
local lastAlly, allyLog = -1000, {}
local ALLY_SENDER_GAP, ALLY_SENDER_HOURLY = 20, 20
function Hype.Ally(who, points)
  if not GodslayerDB then return end
  local o = opts()
  if not (o.on and o.guild) or type(who) ~= "string" or type(points) ~= "number" or points < 1 then return end
  local now, log = GetTime(), allyLog[who]
  if not log then log = {} allyLog[who] = log end
  while log[1] and now - log[1] > 3600 do table.remove(log, 1) end
  if #log >= ALLY_SENDER_HOURLY or (log[#log] and now - log[#log] < ALLY_SENDER_GAP) then return end
  log[#log + 1] = now
  ns.Print(("|cffffd100%s|r just took |cffffd100+%d|r off Olympus."):format(who, points))
  if hunt or Hype.Speaking() or now - lastAlly < ALLY_GAP then return end
  lastAlly = now
  speak({ { pick("ally"), 1 } })
end

-- COMMANDS ------------------------------------------------------------------------
local function say(msg) ns.Print(msg) end

local testKills = 0
function Hype.Command(rest)
  local o = opts()
  local word, value = (rest or ""):match("^(%S*)%s*(.-)$")
  word, value = word:lower(), value:lower()
  if word == "on" or word == "off" then
    o.on = word == "on"
    if not o.on then waiting = {} endHunt("off") end
    say("Kill song and announcer " .. (o.on and "on." or "off."))
  elseif word == "voice" or word == "music" or word == "guild" then
    if value == "on" or value == "off" then o[word] = value == "on" end
    if word == "music" and not o.music and hunt then stopMusic(hunt.music) hunt.music = nil end
    if word == "voice" and not o.voice then hush() end
    say(({ voice = "Announcer ", music = "Kill song ", guild = "Guild kill calls " })[word] .. (o[word] and "on." or "off."))
  elseif word == "pack" then
    if ns.VOICE and ns.VOICE[value] then
      o.pack = value
      hush()
      say("Announcer: " .. ns.VOICE[value].label .. ", " .. ns.VOICE[value].about .. ".")
      speak({ { pick("first_blood"), 3 }, { pick("plus_five"), 2 } })
    else
      say("Announcers:")
      for id, pack in pairs(ns.VOICE or {}) do
        print(("  |cffffd100/godslayer hype pack %s|r  %s: %s%s"):format(id, pack.label, pack.about, id == o.pack and "  (yours)" or ""))
      end
    end
  elseif word == "window" then
    local n = tonumber(value)
    if n and n >= 20 and n <= 600 then
      o.window = math.floor(n)
      say(("A hunt now lasts %d seconds past your last kill."):format(o.window))
    else
      say(("Give a number of seconds from 20 to 600. It is %d now."):format(o.window))
    end
  elseif word == "blows" or word == "all" then
    o.mode = word
    say(word == "blows" and "Only your own killing blows count toward a hunt." or "Every player kill you get credit for counts toward a hunt.")
  elseif word == "test" then
    -- a pretend kill: nothing is scored and nothing is saved
    local before, mode = o.on, o.mode
    o.on, o.mode = true, "all"
    testKills = testKills + 1
    local id = "test#" .. testKills
    Hype.Kill("Test Dummy", true, id, true)
    if value == "olympus" or value == "king" then
      local streak = Hype.Kills()
      local original = value == "king" or streak % 2 == 0
      Hype.Olympus(id, { name = value == "king" and "The King" or "Test Olympian", kills = streak }, original and "original" or "network",
        original and 5 or 1, { streak = streak, kb = true, king = value == "king", rankUp = streak == 3 and "Temple Robber" or nil }, 5)
    end
    o.on, o.mode = before, mode
    say(("Test kill %d. Again inside %d seconds to climb. Try /godslayer hype test olympus, and test king. /godslayer hype stop ends it."):format(Hype.Kills(), o.window))
    if hunt and not hunt.music and o.music then
      print("  No song found. Put kill.mp3 in Interface\\AddOns\\GodslayerMusic and restart the game.")
    end
  elseif word == "stop" then
    waiting = {}
    endHunt("stop")
    say("Hunt ended.")
  else
    local pack = ns.VOICE and ns.VOICE[o.pack]
    say(("Kill song and announcer: %s. Song %s, announcer %s (%s), guild kill calls %s. A hunt lasts %d seconds past your last kill, counting %s. Best hunt: %d."):format(
      o.on and "on" or "off", o.music and "on" or "off", o.voice and "on" or "off", pack and pack.label or "none", o.guild and "on" or "off", o.window,
      o.mode == "blows" and "your killing blows only" or "every kill you get credit for", o.best or 0))
    print("  Rungs: " .. (function() local t = {} for _, r in ipairs(LADDER) do t[#t + 1] = r[1] .. " " .. r[2] end return table.concat(t, ", ") end)() .. ".")
    print("  Olympus kills have their own calls, and the points are read out. /godslayer hype test olympus plays one.")
    print("  Your song: a file named kill.mp3 or kill.ogg in Interface\\AddOns\\GodslayerMusic. Restart the game after adding it.")
    print("  /godslayer hype test [olympus|king] | stop | on | off | pack | music on|off | voice on|off | guild on|off | window <seconds> | blows | all")
  end
end
