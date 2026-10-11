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
-- IN A ROW. Kills that land within a few seconds of each other are also counted on their own:
-- DOUBLE KILL, TRIPLE KILL, QUAD KILL, RAMPAGE, called before the rung.
--
-- THE VOICES. Several announcers, each a character with a script of their own. Set to mix (the
-- default) a different one takes each hunt. /godslayer hype pack picks one for good.
--
-- THE GUILD. When a guildmate's score goes up, you hear about it.
--
-- THE SPOTTER. A living Olympian comes into view: a horn, and the announcer says so.
--
-- The song is yours to supply: a file named kill.mp3 (or kill.ogg) in a folder called
--   Interface\AddOns\GodslayerMusic
-- That folder is never touched by an update. With no file there the hunt theme that comes with
-- the addon plays instead.
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
local MULTI_WINDOW = 12    -- kills this close together count as one run: double, triple, rampage
local FADING = 10          -- the warning comes this long before a hunt runs out
local CROWD_GAP = 8        -- the crowd does not roar more often than this
local SPOT_GAP, SPOT_AGAIN, SPOT_KING_GAP = 120, 900, 30
local RECORD_FROM = 3      -- a best hunt shorter than this is not worth calling a record
local STALE_REMARK, STALE = 9, 14 -- a line that has waited this long is about a fight that has moved on

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

-- kills in quick succession, counted apart from the rungs; the last one repeats
local MULTI = {
  { 2, "DOUBLE KILL", "double_kill" }, { 3, "TRIPLE KILL", "triple_kill" }, { 4, "QUAD KILL", "quad_kill" }, { 5, "RAMPAGE", "rampage" },
}
Hype.MULTI = MULTI

-- Olympus kills in a row without dying: the clip, and the words on the banner
local SACRILEGE = {
  { 2, "double_sacrilege", "DOUBLE SACRILEGE" }, { 3, "triple_heresy", "TRIPLE HERESY" }, { 4, "quad_blasphemy", "QUAD BLASPHEMY" },
  { 5, "titanomachy", "TITANOMACHY" }, { 7, "twilight", "TWILIGHT OF THE GODS" }, { 10, "hill", "OLYMPUS IS A HILL NOW" },
  { 15, "zeus_left", "ZEUS HAS LEFT THE CHAT" },
}
local GOLD, GODRED, GREY = { 1, 0.82, 0.2 }, { 1, 0.3, 0.12 }, { 0.75, 0.75, 0.75 }

local function issecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function plain(v) if issecret(v) then return nil end return v end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

local hunt          -- { kills, music = "music" | handle | nil, turn, run, bestRun, points, gods, started }
local songPath      -- the song found this session; false once we know there is none
local banner
local voiceNow      -- the announcer speaking: the chosen one, or in the mix the one this hunt drew

local function opts()
  local o = GodslayerDB.opts
  if type(o.hype) ~= "table" then o.hype = {} end
  local h = o.hype
  if h.on == nil then h.on = true end
  if h.voice == nil then h.voice = true end
  if h.music == nil then h.music = true end
  if h.guild == nil then h.guild = true end
  if h.sfx == nil then h.sfx = true end
  if h.spot == nil then h.spot = true end
  if h.theme == nil then h.theme = true end
  if h.multi == nil then h.multi = true end
  if h.asides == nil then h.asides = true end
  if h.mode ~= "blows" then h.mode = "all" end -- all = any kill you get credit for; blows = only your own killing blows
  -- the mix arrived with the new announcers: everyone starts on it once, and may then pin one
  -- (titan was what 1.3 saved for everybody; any other saved announcer was a choice, and is kept)
  if not h.mixed then
    h.mixed = true
    if h.pack == nil or h.pack == "titan" then h.pack = "mix" end
  end
  if h.pack ~= "mix" and not (ns.VOICE and ns.VOICE[h.pack]) then h.pack = "mix" end
  if type(h.out) ~= "table" then h.out = {} end -- announcers left out of the mix
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

local function multiFor(run)
  local best
  for _, m in ipairs(MULTI) do
    if run >= m[1] then best = m end
  end
  return best
end
Hype.MultiFor = multiFor

-- THE ANNOUNCERS ------------------------------------------------------------------
local function packOrder()
  if ns.VOICE_ORDER then return ns.VOICE_ORDER end
  local ids = {}
  for id in pairs(ns.VOICE or {}) do ids[#ids + 1] = id end
  table.sort(ids)
  return ids
end

-- Draws the announcer for a hunt in the mix: by weight, and not the one who had the last hunt.
local function draw()
  local o = opts()
  local pool, total = {}, 0
  for _, id in ipairs(packOrder()) do
    local pack = ns.VOICE[id]
    if pack and not o.out[id] and id ~= voiceNow then
      local weight = tonumber(pack.weight) or 10
      pool[#pool + 1] = { id, weight }
      total = total + weight
    end
  end
  if #pool == 0 then return (voiceNow and ns.VOICE[voiceNow]) and voiceNow or packOrder()[1] end
  local roll = math.random() * total
  for _, entry in ipairs(pool) do
    roll = roll - entry[2]
    if roll <= 0 then return entry[1] end
  end
  return pool[#pool][1]
end

local function currentPack()
  local o = opts()
  if o.pack ~= "mix" then voiceNow = o.pack return o.pack end
  -- an announcer left out of the mix mid-hunt still finishes the hunt: one hunt, one voice
  if not (voiceNow and ns.VOICE and ns.VOICE[voiceNow]) or (o.out[voiceNow] and not hunt) then voiceNow = draw() end
  return voiceNow
end
Hype.Pack = function() return ns.VOICE and currentPack() or nil end

-- THE BANNER --------------------------------------------------------------------
local function buildBanner()
  local f = CreateFrame("Frame", "GodslayerHypeBanner", UIParent)
  f:SetSize(760, 100)
  f:SetPoint("TOP", UIParent, "TOP", 0, -150)
  f:SetFrameStrata("HIGH")
  local font = STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
  f.title = f:CreateFontString(nil, "OVERLAY")
  -- the game says whether it took the font; if the heavy outline is refused, the plain one is not
  if f.title:SetFont(font, 44, "THICKOUTLINE") == false then f.title:SetFont(font, 44, "OUTLINE") end
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

local function clipLength(clip, id)
  local pack = ns.VOICE and ns.VOICE[id or currentPack()]
  return pack and pack.clips[clip]
end
Hype.ClipLength = clipLength

-- A sound under the voice: the crowd, a horn, a fanfare. Never needed, so never an error.
local function sfx(name)
  if not name or not opts().sfx or not soundOn() or not (ns.SFX and ns.SFX[name]) then return end
  try(PlaySoundFile, SOUNDS .. "sfx\\" .. name .. ".ogg", "Master")
end

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

local function playNow(clip, pack)
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
  -- said late is worse than not said: the voice never trails the fight
  while item and GetTime() - (item[5] or GetTime()) > (item[2] < 2 and STALE_REMARK or STALE) do item = table.remove(queue, 1) end
  if not item then return end
  local length = clipLength(item[1], item[3]) or 1.5
  sfx(item[4])
  playNow(item[1], item[3])
  busyUntil = GetTime() + math.max(0.4, length - OVERLAP)
  if queue[1] then
    pumping = true
    C_Timer.After(busyUntil - GetTime(), pump)
  end
end

-- weight: 3 = a kill call, 2 = points and titles, below 2 = a rung said after a multi-kill
-- (1.5) or a remark (1): the things a new call may talk over. A line may carry the name of a
-- sound to play under it as its fourth field.
local function speak(lines)
  if not GodslayerDB or not opts().voice or not soundOn() then return end
  local pack = currentPack()
  local hasCall = false
  for _, line in ipairs(lines) do if line[2] >= 3 then hasCall = true end end
  if hasCall then
    for i = #queue, 1, -1 do
      if queue[i][2] < 2 then table.remove(queue, i) end
    end
  end
  for _, line in ipairs(lines) do
    if line[1] and clipLength(line[1], pack) then
      line[3], line[5] = pack, GetTime()
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
  local path, theme = findSong(), false
  -- no song of your own: the hunt theme that comes with the addon
  if not path and opts().theme and ns.MUSIC and ns.MUSIC.hunt then path, theme = SOUNDS .. "music\\hunt.ogg", true end
  if not path then return nil end
  -- as game music it loops, replaces the zone music and fades out by itself when stopped
  if plain(try(GetCVar, "Sound_EnableMusic")) ~= "0" and type(PlayMusic) == "function" then
    -- a client that says no plays it as a sound instead, below
    local ok, will = pcall(PlayMusic, path)
    if ok and plain(will) ~= false then return "music", theme end
  end
  -- music is switched off in the options: play it as an ordinary sound instead
  local willPlay, handle = try(PlaySoundFile, path, "Master")
  if plain(willPlay) and plain(handle) then return handle, theme end
  return nil
end

local function stopMusic(how)
  if not how then return end
  if how == "music" then try(StopMusic) else try(StopSound, how, FADE_MS) end
end

-- THE HUNT ----------------------------------------------------------------------
function Hype.Active() return hunt ~= nil end
function Hype.Kills() return hunt and hunt.kills or 0 end

-- What the hunt came to, in chat, once it is over.
local function recap(h)
  local parts = { ("%d kills"):format(h.kills) }
  if (h.points or 0) > 0 then parts[#parts + 1] = ("|cffffd100+%d|r off Olympus"):format(h.points) end
  local run = multiFor(h.bestRun or 1)
  if run then parts[#parts + 1] = "best run " .. run[2] end
  local seconds = math.max(0, math.floor((h.last or GetTime()) - (h.started or GetTime())))
  parts[#parts + 1] = ("%d:%02d from first kill to last"):format(math.floor(seconds / 60), seconds % 60)
  ns.Print("Hunt over: " .. table.concat(parts, ", ") .. ".")
end

local function endHunt(reason)
  local h = hunt
  if not h then return end
  hunt = nil
  stopMusic(h.music)
  if reason == "died" and h.kills >= 2 then
    hush()
    speak({ { pick("shut_down"), 3, nil, "powerdown" } })
    showBanner("SHUT DOWN", GREY, ("Your hunt ended at %d kills."):format(h.kills))
  elseif reason == "quiet" then
    if h.kills >= 2 and not Hype.Speaking() then speak({ { pick("hunt_over"), 1, nil, "gong" } }) end
  else
    hush()
  end
  if h.kills >= 2 and (reason == "died" or reason == "quiet") then recap(h) end
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
  -- ten seconds left: a heartbeat, and a word, while there is still time to do something about it
  C_Timer.After(window - FADING, function()
    if hunt == h and h.turn == turn and h.kills >= 2 and not Hype.Speaking() then
      speak({ { pick("fading"), 1, nil, "heartbeat" } })
    end
  end)
end

local lastRoar = -1000
local function roar()
  local now = GetTime()
  if now - lastRoar < CROWD_GAP then return end
  lastRoar = now
  sfx("crowd")
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
  if info.king then lines[1] = { pick("regicide"), 3 }
  elseif ladder then lines[1] = { pick(ladder[2]), 3 }
  else lines[1] = { pick(o.tier == "original" and "olympus" or "god_down"), 3 } end
  lines[2] = { pick(o.pts >= 5 and "plus_five" or "plus_one"), 2 }
  local roll = math.random()
  if not opts().asides then
    -- remarks are switched off: the call, the points, and a title when there is one
  elseif o.firstToday then
    lines[#lines + 1] = { pick("first_today"), 1 }
  elseif roll < RARE_CHANCE then
    lines[#lines + 1] = { pick("rare"), 1 }
  elseif (v.kills or 0) >= 3 and roll < 0.6 then
    lines[#lines + 1] = { pick("repeat"), 1 }
  elseif roll < RARE_CHANCE + ASIDE_CHANCE then
    lines[#lines + 1] = { pick("tail"), 1 }
  end
  if info.rankUp and o.rankIndex and clipLength("title_" .. o.rankIndex) then
    lines[#lines + 1] = { pick("new_title"), 2, nil, "fanfare" }
    lines[#lines + 1] = { "title_" .. o.rankIndex, 2 }
  end
  return lines, ladder
end
Hype.OlympusLines = olympusLines

-- Calls and shows a batch of Olympus kills that were scored together. huntKills is the count
-- to show beside them, or nil when they are not part of what is happening right now.
local function announceGods(gods, huntKills, run, record)
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
  if #gods > 1 then lines[2] = { pick("plus_many"), 2 } end
  if promoted and promoted ~= top and promoted.rankIndex and clipLength("title_" .. promoted.rankIndex) then
    lines[#lines + 1] = { pick("new_title"), 2, nil, "fanfare" }
    lines[#lines + 1] = { "title_" .. promoted.rankIndex, 2 }
  end
  -- three or more in a few seconds is said first, and there is no time for a remark after it
  local multi = multiFor(run or 1)
  if multi and multi[1] >= 3 then
    for i = #lines, 1, -1 do if lines[i][2] < 2 then table.remove(lines, i) end end
    table.insert(lines, 1, { pick(multi[3]), 3 })
  end
  if record then lines[#lines + 1] = { pick("record"), 2 } end
  speak(lines)
  if top.info.king or (multi and multi[1] >= 3) or (ladder and ladder[1] >= 5) or record then roar() end
  local title = top.info.king and "REGICIDE" or (ladder and ladder[3]) or (top.tier == "original" and "OLYMPUS BLEEDS" or "OLYMPIAN DOWN")
  local name = top.v and top.v.name
  local parts = { (name or "An Olympian") .. (#gods > 1 and (" and " .. (#gods - 1) .. " more") or ""), "|cffffd100+" .. points .. "|r" }
  local progress = progressLine()
  if promoted then parts[#parts + 1] = "|cffff7d0aNew title: " .. promoted.info.rankUp .. "|r"
  elseif progress then parts[#parts + 1] = "|cffbbbbbb" .. progress .. "|r" end
  if multi and huntKills then parts[#parts + 1] = "|cffff7d0a" .. multi[2] .. "|r" end
  if huntKills and huntKills > 1 then parts[#parts + 1] = "|cffffd100x" .. huntKills .. "|r" end
  showBanner(title, top.tier == "original" and GOLD or GODRED, table.concat(parts, "    "))
end

local function flush()
  flushQueued = false
  local batch = waiting
  waiting = {}
  if not opts().on then return end -- switched off while a kill was waiting to be called
  local generic, gods, run, record = nil, {}, 1, false
  for _, w in pairs(batch) do
    if w.olympus then gods[#gods + 1] = w.olympus elseif not generic or w.kills > generic.kills then generic = w end
    if (w.run or 1) > run then run = w.run end
    record = record or w.record
  end
  if #gods > 0 then
    announceGods(gods, hunt and hunt.kills, run, record)
  elseif generic then
    -- DOUBLE KILL, then the rung; the rung gives way if the next kill arrives before it is said
    local multi, rung = multiFor(run), rungFor(generic.kills)
    local lines = { { pick(rung[3]), 3 } }
    if multi then
      lines[1][2] = 1.5
      table.insert(lines, 1, { pick(multi[3]), 3 })
    end
    if record then lines[#lines + 1] = { pick("record"), 2 } end
    speak(lines)
    if (multi and multi[1] >= 3) or record or (generic.kills >= 4 and generic.kills == rung[1]) then roar() end
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
  local now = GetTime()
  if not hunt then
    if o.pack == "mix" and ns.VOICE then voiceNow = draw() end -- a new hunt, a new voice
    hunt = { kills = 0, run = 0, bestRun = 1, points = 0, started = now, ids = {} }
    hunt.music, hunt.theme = startMusic()
  end
  local h = hunt
  if pretend then h.pretend = true end -- a hunt with a test kill in it is never a record
  h.kills = h.kills + 1
  h.run = (o.multi and h.last and now - h.last <= MULTI_WINDOW) and h.run + 1 or 1
  h.last = now
  if h.run > h.bestRun then h.bestRun = h.run end
  arm(h)
  local rung, multi = rungFor(h.kills), multiFor(h.run)
  local name = type(who) == "string" and who ~= "" and who or nil
  local parts = { name and (name .. " is dead") or "A kill" }
  local big = multi and multi[1] >= 4 -- a quad kill or a rampage takes the banner from the rung
  if multi then parts[#parts + 1] = "|cffff7d0a" .. (big and rung[2] or multi[2]) .. "|r" end
  if h.kills > 1 then parts[#parts + 1] = "|cffffd100x" .. h.kills .. "|r" end
  showBanner(big and multi[2] or rung[2], rung[4], table.concat(parts, "    "))
  local key = id or (name or "?") .. "#" .. h.kills
  h.ids[key] = true
  local w = waiting[key] or {}
  w.kills, w.who, w.run = h.kills, name, h.run
  -- past your best hunt: said once, at the kill that does it
  local best = o.best or 0
  if not h.pretend and not h.record and best >= RECORD_FROM and h.kills > best then h.record, w.record = true, true end
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
  -- points belong to the hunt the kill was made in, not to whichever hunt is on when the tag arrives
  if hunt and id and hunt.ids[id] then hunt.points = (hunt.points or 0) + olympus.pts end
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

-- A living Olympian has come into view. A horn, a banner with the name and guild, and a word
-- from the announcer; rationed, so a city full of them is one call and not forty.
local spotted, spottedCount, lastSpot = {}, 0, -1000
function Hype.Spot(id, name, guild, tier, king)
  if not GodslayerDB or type(id) ~= "string" or ns.sweeping then return false end
  local o = opts()
  if not (o.on and o.spot) then return false end
  local now = GetTime()
  if now - lastSpot < (king and SPOT_KING_GAP or SPOT_GAP) then return false end
  if spotted[id] and now - spotted[id] < SPOT_AGAIN then return false end
  -- never over a kill being called, and not in the seconds after one
  if Hype.Speaking() or next(waiting) or (hunt and hunt.last and now - hunt.last < 10) then return false end
  if spottedCount > 400 then spotted, spottedCount = {}, 0 end
  if not spotted[id] then spottedCount = spottedCount + 1 end
  spotted[id], lastSpot = now, now
  sfx("horn")
  speak({ { pick(king and "king_spot" or "spot"), king and 3 or 1 } })
  showBanner(king and "THE KING IS HERE" or "OLYMPIAN SIGHTED", king and GODRED or GOLD,
    (type(name) == "string" and name or "An Olympian") .. (type(guild) == "string" and ("    |cffbbbbbb<" .. guild .. ">|r") or ""))
  return true
end

-- COMMANDS ------------------------------------------------------------------------
local function say(msg) ns.Print(msg) end

local SWITCHES = {
  voice = "Announcer", music = "Kill song", guild = "Guild kill calls", sfx = "Sound effects", spot = "Olympian spotter",
  theme = "Hunt theme when you have no song of your own", multi = "Double, triple and rampage calls", asides = "Remarks after an Olympus kill",
}

local function listPacks(o)
  say("Announcers:")
  print(("  |cffffd100/godslayer hype pack mix|r  A different one each hunt%s"):format(o.pack == "mix" and "  (yours)" or ""))
  for _, id in ipairs(packOrder()) do
    local pack = ns.VOICE[id]
    print(("  |cffffd100/godslayer hype pack %s|r  %s: %s%s%s"):format(id, pack.label, pack.about, id == o.pack and "  (yours)" or "",
      o.out[id] and "  (left out of the mix)" or ""))
  end
  print("  Leave one out of the mix, or let it back in: /godslayer hype mix <name> off|on")
end

-- Every line of one announcer, in order, with the words in chat. For choosing, and for hearing
-- what a kill will sound like before there is one.
local auditionTurn = 0
local function audition(id)
  auditionTurn = auditionTurn + 1
  local turn, pack, names = auditionTurn, ns.VOICE[id], {}
  for clip in pairs(pack.clips) do names[#names + 1] = clip end
  table.sort(names)
  hush()
  local at = math.max(0, busyUntil - GetTime()) + 0.05 -- after whatever line is in the air now
  for _, clip in ipairs(names) do
    C_Timer.After(at, function()
      if turn ~= auditionTurn or not soundOn() then return end
      -- a real kill has something to say: the audition gives way and does not come back
      if #queue > 0 or GetTime() < busyUntil - 0.01 then auditionTurn = auditionTurn + 1 return end
      print(("  |cffffd100%s|r  %s"):format(clip, pack.text and pack.text[clip] or ""))
      playNow(clip, id)
      busyUntil = GetTime() + pack.clips[clip]
    end)
    at = at + pack.clips[clip] + 0.3
  end
  return #names, at
end

local testKills = 0
function Hype.Command(rest)
  local o = opts()
  local word, value = (rest or ""):match("^(%S*)%s*(.-)$")
  word, value = word:lower(), value:lower()
  if word == "on" or word == "off" then
    o.on = word == "on"
    if not o.on then waiting = {} auditionTurn = auditionTurn + 1 endHunt("off") end
    say("Kill song and announcer " .. (o.on and "on." or "off."))
  elseif SWITCHES[word] then
    if value == "on" or value == "off" then o[word] = value == "on" end
    if hunt and hunt.music and ((word == "music" and not o.music) or (word == "theme" and not o.theme and hunt.theme)) then
      stopMusic(hunt.music)
      hunt.music, hunt.theme = nil, nil
    end
    if word == "voice" and not o.voice then hush() end
    say(SWITCHES[word] .. (o[word] and ": on." or ": off."))
  elseif word == "pack" then
    if value == "mix" then
      o.pack = "mix"
      say("Announcer: the mix. A different voice takes each hunt.")
    elseif ns.VOICE and ns.VOICE[value] then
      o.pack, voiceNow = value, value
      hush()
      say("Announcer: " .. ns.VOICE[value].label .. ", " .. ns.VOICE[value].about .. ".")
      speak({ { pick("first_blood"), 3 }, { pick("plus_five"), 2 } })
    else
      listPacks(o)
    end
  elseif word == "mix" then
    local id, onOff = value:match("^(%S+)%s*(%S*)$")
    if id and ns.VOICE and ns.VOICE[id] and (onOff == "on" or onOff == "off") then
      o.out[id] = onOff == "off" or nil
      say(ns.VOICE[id].label .. (o.out[id] and " is left out of the mix." or " is back in the mix."))
    else
      o.pack = "mix"
      listPacks(o)
    end
  elseif word == "audition" then
    local id = ns.VOICE and ns.VOICE[value] and value or currentPack()
    if not id then say("No announcers found.") return end
    local count, seconds = audition(id)
    say(("%s, every line: %d of them, about %d minutes. /godslayer hype stop ends it."):format(ns.VOICE[id].label, count, math.ceil(seconds / 60)))
  elseif word == "say" then
    if clipLength(value) then
      print(("  |cffffd100%s|r  %s"):format(value, (ns.VOICE[currentPack()].text or {})[value] or ""))
      speak({ { value, 3 } })
    else
      say("No line called that. /godslayer hype audition plays them all with their names.")
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
  elseif word == "test" and value == "spot" or word == "test" and value == "king spot" then
    -- a preview: it leaves the real spotter's memory as it found it
    local before, spot, last, id = o.on, o.spot, lastSpot, "test#spot"
    o.on, o.spot, lastSpot = true, true, -1000
    if not Hype.Spot(id, value == "spot" and "Test Olympian" or ns.KING, "OLYMPUS", "original", value ~= "spot") then
      say("The announcer is busy with a kill. Try again in a few seconds.")
    end
    if spotted[id] then spotted[id], spottedCount = nil, spottedCount - 1 end
    o.on, o.spot, lastSpot = before, spot, last
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
    say(("Test kill %d, called by %s. Again inside %d seconds for a double kill, inside %d to climb. Try test olympus, test king, test spot. /godslayer hype stop ends it."):format(
      Hype.Kills(), ns.VOICE and ns.VOICE[currentPack()] and ns.VOICE[currentPack()].label or "nobody", MULTI_WINDOW, o.window))
    if hunt and not hunt.music and o.music then
      print("  No song found. Put kill.mp3 in Interface\\AddOns\\GodslayerMusic and restart the game.")
    elseif hunt and hunt.theme then
      print("  That is the hunt theme. For a song of your own, put kill.mp3 in Interface\\AddOns\\GodslayerMusic and restart the game.")
    end
  elseif word == "stop" then
    waiting = {}
    auditionTurn = auditionTurn + 1
    endHunt("stop")
    say("Hunt ended.")
  else
    local pack = ns.VOICE and ns.VOICE[o.pack]
    local onOff = function(v) return v and "on" or "off" end
    say(("Kill song and announcer: %s. Song %s, announcer %s (%s), guild kill calls %s. A hunt lasts %d seconds past your last kill, counting %s. Best hunt: %d."):format(
      onOff(o.on), onOff(o.music), onOff(o.voice), o.pack == "mix" and "the mix" or (pack and pack.label or "none"), onOff(o.guild), o.window,
      o.mode == "blows" and "your killing blows only" or "every kill you get credit for", o.best or 0))
    print("  Rungs: " .. (function() local t = {} for _, r in ipairs(LADDER) do t[#t + 1] = r[1] .. " " .. r[2] end return table.concat(t, ", ") end)() .. ".")
    print(("  Kills within %d seconds of each other: DOUBLE KILL, TRIPLE KILL, QUAD KILL, RAMPAGE (%s)."):format(MULTI_WINDOW, onOff(o.multi)))
    print("  Olympus kills have their own calls, and the points are read out. /godslayer hype test olympus plays one.")
    print(("  Sound effects %s, Olympian spotter %s, remarks %s, hunt theme %s."):format(onOff(o.sfx), onOff(o.spot), onOff(o.asides), onOff(o.theme)))
    print("  Your song: a file named kill.mp3 or kill.ogg in Interface\\AddOns\\GodslayerMusic. Restart the game after adding it.")
    print("  /godslayer hype pack | mix | audition [name] | say <line> | test [olympus|king|spot|king spot] | stop | on | off | window <seconds> | blows | all")
    print("  /godslayer hype music | voice | guild | sfx | spot | multi | asides | theme  on|off")
  end
end
