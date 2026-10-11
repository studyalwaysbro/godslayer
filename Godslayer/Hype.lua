-- Godslayer hype: your kill song, and an announcer for every kill that follows.
--
-- The first player you kill starts the hunt: your song begins and the banner goes up. Every
-- kill after that, while the hunt is still on, climbs a rung: MEGA KILL, ULTRA KILL, GODLIKE
-- and on up, called out by the announcer over the music. Each kill keeps the hunt alive for
-- another stretch (90 seconds unless you change it). It ends when that time runs out with
-- nobody dead, or when you die. The music fades out and the zone's own music comes back.
--
-- The song is yours to supply. Put a file named kill.mp3 (or kill.ogg) in a folder called
--   Interface\AddOns\GodslayerMusic
-- and restart the game. That folder is never touched by an update. With no file there the
-- announcer and the banner still work, on top of whatever the game is playing.
-- The song plays as game music, so it replaces the zone music, follows your music volume
-- and fades the way the game's own tracks do. Only you hear any of this.

local ADDON, ns = ...

local Hype = {}
ns.Hype = Hype

local SOUNDS = "Interface\\AddOns\\Godslayer\\Sounds\\"
local SONGS = { "Interface\\AddOns\\GodslayerMusic\\kill.mp3", "Interface\\AddOns\\GodslayerMusic\\kill.ogg" }
local FADE_MS = 2500
local CALL_DELAY = 0.45   -- kills landing together get one call, for the highest rung reached
local BANNER_SECONDS = 3.2

-- rung reached by this many kills in one hunt; the last one repeats from there on
local LADDER = {
  { 1, "FIRST BLOOD", nil, { 1, 0.82, 0.2 } },
  { 2, "MEGA KILL", "mega_kill", { 1, 0.6, 0.1 } },
  { 3, "ULTRA KILL", "ultra_kill", { 1, 0.42, 0.05 } },
  { 4, "GODLIKE", "godlike", { 1, 0.25, 0.1 } },
  { 5, "UNSTOPPABLE", "unstoppable", { 1, 0.15, 0.25 } },
  { 6, "BEYOND GODLIKE", "beyond_godlike", { 0.95, 0.2, 0.75 } },
  { 7, "GODSLAYER", "godslayer", { 0.7, 0.35, 1 } },
}
Hype.LADDER = LADDER

local function issecret(v) return issecretvalue ~= nil and issecretvalue(v) or false end
local function plain(v) if issecret(v) then return nil end return v end
local function try(f, ...)
  if type(f) ~= "function" then return nil end
  local ok, a, b = pcall(f, ...)
  if ok then return a, b end
end

local hunt          -- { kills, last = time of the last kill, music = "music" | handle | nil, turn }
local songPath      -- the song that was found this session; false once we know there is none
local pendingCall   -- a call waiting out CALL_DELAY
local banner

local function opts()
  local o = GodslayerDB.opts
  if type(o.hype) ~= "table" then o.hype = {} end
  local h = o.hype
  if h.on == nil then h.on = true end
  if h.voice == nil then h.voice = true end
  if h.music == nil then h.music = true end
  if h.mode ~= "blows" then h.mode = "all" end -- all = any kill you get credit for; blows = only your own killing blows
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
  f:SetSize(700, 90)
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

-- SOUND -----------------------------------------------------------------------
local function soundOn()
  return plain(try(GetCVar, "Sound_EnableAllSound")) ~= "0"
end

local function call(file)
  if not file or not opts().voice or not soundOn() then return end
  -- lines re-pitched to your own song (tools/tune_announcer.py writes them) come first
  local own = try(PlaySoundFile, "Interface\\AddOns\\GodslayerMusic\\voice\\" .. file .. ".ogg", "Master")
  if not plain(own) then try(PlaySoundFile, SOUNDS .. file .. ".ogg", "Master") end
end

-- Finds the player's own song the first time it is needed. A file that is not there
-- simply does not play, which is how we know.
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
  hunt, pendingCall = nil, nil
  stopMusic(h.music)
  if reason == "died" and h.kills >= 2 then
    call("shut_down")
    showBanner("SHUT DOWN", { 0.75, 0.75, 0.75 }, ("Your hunt ended at %d kills."):format(h.kills))
  end
  local best = GodslayerDB.opts.hype.best or 0
  if h.kills > best then GodslayerDB.opts.hype.best = h.kills end
end
Hype.End = endHunt

local function arm(h)
  h.turn = (h.turn or 0) + 1
  local turn, window = h.turn, opts().window
  C_Timer.After(window, function()
    if hunt == h and h.turn == turn then endHunt("quiet") end
  end)
end

-- One kill. who = the victim's name if known. Called by the core for every player kill you
-- get credit for, once per victim.
function Hype.Kill(who, killingBlow)
  if not GodslayerDB then return end
  local o = opts()
  if not o.on then return end
  if o.mode == "blows" and not killingBlow then return end
  if not hunt then
    hunt = { kills = 0 }
    hunt.music = startMusic()
  end
  local h = hunt
  h.kills, h.last = h.kills + 1, GetTime()
  arm(h)
  local rung = rungFor(h.kills)
  local name = type(who) == "string" and who ~= "" and who or nil
  local line = (name and (name .. " is dead") or "A kill") .. (h.kills > 1 and ("   |cffffd100x" .. h.kills .. "|r") or "")
  showBanner(rung[2], rung[4], line)
  -- several deaths in the same moment: one call, for where the count ended up
  if rung[3] then
    pendingCall = rung[3]
    C_Timer.After(CALL_DELAY, function()
      if hunt == h and pendingCall then
        local file = pendingCall
        pendingCall = nil
        call(file)
      end
    end)
  end
end

function Hype.Died()
  endHunt("died")
end

-- COMMANDS ------------------------------------------------------------------------
local function say(msg) ns.Print(msg) end

function Hype.Command(rest)
  local o = opts()
  local word, value = (rest or ""):match("^(%S*)%s*(.-)$")
  word = word:lower()
  if word == "on" or word == "off" then
    o.on = word == "on"
    if not o.on then endHunt("off") end
    say("Kill song and announcer " .. (o.on and "on." or "off."))
  elseif word == "voice" or word == "music" then
    if value == "on" or value == "off" then o[word] = value == "on" end
    if word == "music" and not o.music and hunt then stopMusic(hunt.music) hunt.music = nil end
    say((word == "voice" and "Announcer " or "Kill song ") .. (o[word] and "on." or "off."))
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
    local before = o.on
    o.on = true
    Hype.Kill("Test Dummy", true)
    o.on = before
    say(("Test kill %d. Press it again inside %d seconds to climb. /godslayer hype stop ends it."):format(Hype.Kills(), o.window))
    if hunt and not hunt.music and o.music then
      print("  No song found. Put kill.mp3 in Interface\\AddOns\\GodslayerMusic and restart the game.")
    end
  elseif word == "stop" then
    endHunt("stop")
    say("Hunt ended.")
  else
    say(("Kill song and announcer: %s. Song %s, announcer %s, a hunt lasts %d seconds past your last kill, counting %s. Best hunt: %d."):format(
      o.on and "on" or "off", o.music and "on" or "off", o.voice and "on" or "off", o.window,
      o.mode == "blows" and "your killing blows only" or "every kill you get credit for", o.best or 0))
    print("  Rungs: " .. (function() local t = {} for _, r in ipairs(LADDER) do t[#t + 1] = r[1] .. " " .. r[2] end return table.concat(t, ", ") end)() .. ".")
    print("  Your song: a file named kill.mp3 or kill.ogg in Interface\\AddOns\\GodslayerMusic. Restart the game after adding it.")
    print("  /godslayer hype test | stop | on | off | music on|off | voice on|off | window <seconds> | blows | all")
  end
end
