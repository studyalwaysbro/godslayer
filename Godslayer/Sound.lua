-- Godslayer sound: absolute Voice/Effects leases and a relative Music controller.
--
-- PlaySoundFile has no volume argument. Below full volume a file briefly borrows Dialog or Ambience,
-- writes its absolute Godslayer level, and restores it only if nobody moved that slider meanwhile.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Sound = { handlers = {} }
ns.Sound = Sound

local POLL, GRACE, EPSILON, DUCK = 0.25, 0.5, 0.005, 0.60
local CVARS = {
  Sound_DialogVolume = "Dialog",
  Sound_AmbienceVolume = "Ambience",
  Sound_MusicVolume = "Music",
}
local leases, occupancy, pendingRecovery, ticker, serial, music = {}, {}, {}, nil, 0, nil

local function clamp(value, fallback)
  value = tonumber(value)
  return value and math.max(0, math.min(100, math.floor(value + 0.5))) or fallback
end

local function opts()
  local db = GodslayerDB
  if not db then return { master=100, music=100, voice=100, effects=100, flag={} } end
  db.opts = type(db.opts) == "table" and db.opts or {}
  local o = db.opts
  o.master, o.music = clamp(o.master, 100), clamp(o.music, 100)
  o.voice, o.effects = clamp(o.voice, 100), clamp(o.effects, 100)
  o.volume, o.flag = o.master, type(o.flag) == "table" and o.flag or {}
  return o
end

local function numberCVar(name)
  return tonumber(plain(try(GetCVar, name)))
end

local function same(a, b)
  return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= EPSILON
end

local function savedMap()
  if not GodslayerDB then return nil end
  local saved = GodslayerDB.volumeSwap
  if type(saved) ~= "table" or saved.cvar then
    local map = {}
    if type(saved) == "table" and CVARS[saved.cvar] then
      map[saved.cvar] = { original=tonumber(saved.original), ours=tonumber(saved.ours) }
    end
    GodslayerDB.volumeSwap = map
  end
  return GodslayerDB.volumeSwap
end

local function saveSwap(cvar, original, ours)
  local map = savedMap(); if map then map[cvar] = { original=original, ours=ours } end
end

local function clearSaved(cvar)
  local map = GodslayerDB and GodslayerDB.volumeSwap
  if type(map) ~= "table" then return end
  map[cvar] = nil
  if not next(map) then GodslayerDB.volumeSwap = nil end
end

local function savedRecord(cvar)
  local map = GodslayerDB and GodslayerDB.volumeSwap
  local rec = type(map) == "table" and map[cvar] or nil
  if type(rec) ~= "table" then return nil end
  local original, ours = tonumber(rec.original), tonumber(rec.ours)
  if original == nil or ours == nil then return nil end
  return { original=original, ours=ours }
end

-- A recovery entry is owned only while the live value is still ours. Unknown reads and failed
-- writes keep the entry for another tick or login; a numeric value changed by the player wins.
local function finishRestore(cvar, original, ours)
  local live = numberCVar(cvar)
  if live == nil then return false end
  if not same(live, ours) then clearSaved(cvar); return true end
  if type(SetCVar) ~= "function" then return false end
  local ok = pcall(SetCVar, cvar, original)
  local after = numberCVar(cvar)
  if ok and same(after, original) then clearSaved(cvar); return true end
  if after ~= nil and not same(after, ours) then clearSaved(cvar); return true end
  return false
end

local function restoreLease(cvar)
  local rec = leases[cvar]
  if not rec then return true end
  if finishRestore(cvar, rec.original, rec.ours) then leases[cvar] = nil; return true end
  return false
end

local function abandonLease(cvar, protectAt)
  local rec = leases[cvar]
  if rec and protectAt ~= nil then
    local list
    for id, sound in pairs(rec.sounds) do
      local playing = protectAt < sound.ends
      if playing and sound.handle and C_Sound and type(C_Sound.IsPlaying) == "function" then
        playing = plain(try(C_Sound.IsPlaying, sound.handle)) ~= false
      end
      if playing and sound.part == "Voice" then
        if not list then
          list = occupancy[rec.channel]
          if not list then list = {}; occupancy[rec.channel] = list end
        end
        list[id] = sound
      end
    end
  end
  leases[cvar] = nil
  pendingRecovery[cvar] = nil
  clearSaved(cvar)
end

local function stopLease(cvar)
  local rec = leases[cvar]
  if rec then
    for _, sound in pairs(rec.sounds) do
      if sound.handle and type(StopSound) == "function" then pcall(StopSound, sound.handle) end
    end
    rec.sounds, rec.voice = {}, false
  end
  return restoreLease(cvar)
end

local function spokenPlaying()
  local spoken = _G.Spoken
  if type(spoken) ~= "table" or type(spoken.IsPlaying) ~= "function" then return false end
  return plain(try(spoken.IsPlaying, spoken)) == true
end

local function cvarEnabled(name)
  local value = plain(try(GetCVar, name))
  return value == nil or value ~= "0"
end

local function route(part)
  local dialog = cvarEnabled("Sound_EnableDialog")
  local ambience = cvarEnabled("Sound_EnableAmbience")
  if part == "Voice" then
    if spokenPlaying() then return dialog and "Dialog" or "Master", nil, true end
    if dialog then return "Dialog", "Sound_DialogVolume" end
    if ambience then return "Ambience", "Sound_AmbienceVolume" end
    return nil
  end
  if ambience then return "Ambience", "Sound_AmbienceVolume" end
  if dialog and not spokenPlaying() then return "Dialog", "Sound_DialogVolume" end
  return nil
end

local function desired(part)
  local o = opts()
  local level = part == "Voice" and o.voice or o.effects
  return o.master / 100 * level / 100
end

local function occupied(channel)
  local list = occupancy[channel]
  if not list then return false end
  return next(list) ~= nil
end

-- Returns the fixed channel, a lease when one was acquired, and whether playback is allowed.
local function prepare(part)
  local level = desired(part)
  if level <= 0 then return nil, nil, false end
  -- This is the exact 3.0 full-volume path: Master, no CVar write, no Spoken check.
  if level >= 1 then return "Master", nil, true end

  local channel, cvar, spoken = route(part)
  if not channel then return nil, nil, false end
  if spoken or not cvar then
    if part == "Voice" and channel == "Dialog" then
      local rec = leases.Sound_DialogVolume
      if rec and rec.voice and same(rec.ours, level) then
        local live = numberCVar("Sound_DialogVolume")
        if live == nil then return channel, rec, true end
        if same(live, rec.ours) then return channel, rec, true end
        abandonLease("Sound_DialogVolume", plain(try(GetTime)) or 0)
      elseif rec and not rec.voice and not stopLease("Sound_DialogVolume") then
        return nil, nil, false
      end
    end
    return channel, nil, true
  end

  if part == "Effects" and occupied(channel) then return nil, nil, false end

  local rec = leases[cvar]
  if part == "Effects" and channel == "Dialog" and rec and rec.voice then
    return nil, nil, false
  end
  if rec then
    local live = numberCVar(cvar)
    if live == nil then return nil, nil, false end
    if not same(live, rec.ours) then
      -- A player or another addon moved this channel. Their choice wins for this clip.
      abandonLease(cvar, plain(try(GetTime)) or 0)
      return channel, nil, true
    end
  end

  local live = rec and rec.ours or numberCVar(cvar)
  local saved = not rec and savedRecord(cvar) or nil
  local original = rec and rec.original or live
  if not rec and saved then
    if live == nil then return nil, nil, false end
    if same(live, saved.ours) then original = saved.original
    else
      pendingRecovery[cvar] = nil
      clearSaved(cvar)
      saved = nil
    end
  end
  if rec and not same(rec.ours, level) then
    if part == "Effects" and rec.voice then return nil, nil, false end
    if part == "Voice" then
      if not stopLease(cvar) then return nil, nil, false end
    else
      return nil, nil, false
    end
    rec, original = nil, numberCVar(cvar)
  end
  if not rec then
    if original == nil or type(SetCVar) ~= "function" then return nil, nil, false end
    if saved and same(live, saved.ours) and same(live, level) then
      rec = { cvar=cvar, channel=channel, original=original, ours=level, sounds={}, voice=false }
      leases[cvar], pendingRecovery[cvar] = rec, nil
    else
      local previous = saved and saved.ours or nil
      saveSwap(cvar, original, level) -- written before SetCVar for reload/crash recovery
      local ok = pcall(SetCVar, cvar, level)
      local after = numberCVar(cvar)
      if after == nil then
        rec = { cvar=cvar, channel=channel, original=original, ours=level, sounds={}, voice=false, unknown=true }
        leases[cvar], pendingRecovery[cvar] = rec, nil
        return nil, nil, false
      end
      if not same(after, level) then
        if previous and same(after, previous) then
          saveSwap(cvar, original, previous)
          pendingRecovery[cvar] = true
        else
          clearSaved(cvar)
        end
        return nil, nil, false
      end
      rec = { cvar=cvar, channel=channel, original=original, ours=level, sounds={}, voice=false }
      leases[cvar], pendingRecovery[cvar] = rec, nil
      if not ok then return nil, nil, false end
    end
    if not rec then
      return nil, nil, false
    end
  end
  if part == "Voice" then rec.voice = true end
  return channel, rec, true
end

local function track(rec, handle, length, part)
  if not rec then return end
  serial = serial + 1
  rec.sounds[serial] = {
    handle = type(handle) == "number" and handle or nil,
    ends = (plain(try(GetTime)) or 0) + math.max(0, tonumber(length) or 0) + GRACE,
    part = part,
  }
end

local function trackOccupancy(channel, handle, length)
  if channel ~= "Dialog" and channel ~= "Ambience" then return end
  local list = occupancy[channel]
  if not list then list = {}; occupancy[channel] = list end
  serial = serial + 1
  list[serial] = {
    handle = type(handle) == "number" and handle or nil,
    ends = (plain(try(GetTime)) or 0) + math.max(0, tonumber(length) or 0) + GRACE,
  }
end

local function applyMusic()
  local rec = music
  if not rec or rec.lost or rec.original == nil or type(SetCVar) ~= "function" then return false end
  if rec.unknown then
    local live = numberCVar("Sound_MusicVolume")
    if live == nil then return false end
    local unknown = rec.unknown
    rec.unknown = nil
    if same(live, unknown.wanted) then
      rec.ours = unknown.wanted
      if rec.stopping then return true end
    elseif unknown.previous and same(live, unknown.previous) then
      rec.ours = unknown.previous
      saveSwap("Sound_MusicVolume", rec.original, unknown.previous)
      return false
    elseif not unknown.previous and same(live, rec.original) then
      rec.ours = nil
      clearSaved("Sound_MusicVolume")
      return false
    else
      rec.lost, rec.ours = true, nil
      clearSaved("Sound_MusicVolume")
      return false
    end
  end
  if rec.ours then
    local live = numberCVar("Sound_MusicVolume")
    if live == nil then return false end
    if not same(live, rec.ours) then
      rec.lost, rec.ours = true, nil
      clearSaved("Sound_MusicVolume")
      return false
    end
  end
  local o = opts()
  local wanted = rec.original * o.master / 100 * o.music / 100 * (rec.duck and DUCK or 1)
  if rec.ours and same(wanted, rec.ours) then return true end
  if same(wanted, rec.original) then
    if rec.ours then
      if not finishRestore("Sound_MusicVolume", rec.original, rec.ours) then return false end
      rec.ours = nil
    end
    return true
  end
  local previous = rec.ours
  saveSwap("Sound_MusicVolume", rec.original, wanted)
  local ok = pcall(SetCVar, "Sound_MusicVolume", wanted)
  local live = numberCVar("Sound_MusicVolume")
  if live == nil then
    rec.unknown = { wanted=wanted, previous=previous }
    return false
  end
  if same(live, wanted) then rec.ours = wanted; return ok end
  if previous and same(live, previous) then
    rec.ours = previous
    saveSwap("Sound_MusicVolume", rec.original, previous)
    return false
  end
  if not previous and same(live, rec.original) then
    rec.ours = nil
    clearSaved("Sound_MusicVolume")
    return false
  end
  rec.lost, rec.ours = true, nil
  clearSaved("Sound_MusicVolume")
  return false
end

function Sound.MusicStart()
  if not music then
    local live = numberCVar("Sound_MusicVolume")
    local saved = savedRecord("Sound_MusicVolume")
    if saved and live == nil then return false end
    if saved and live ~= nil and same(live, saved.ours) then
      music = { original=saved.original, ours=saved.ours, duck=false }
      pendingRecovery.Sound_MusicVolume = nil
    else
      if saved and live ~= nil then clearSaved("Sound_MusicVolume") end
      music = { original=live, duck=false }
    end
  end
  music.stopping = nil
  return applyMusic()
end

function Sound.MusicDuck(on)
  if not music then return false end
  music.duck = on == true
  return applyMusic()
end

function Sound.MusicStop()
  local rec = music
  if not rec then return true end
  if rec.unknown then rec.stopping = true; return false end
  if rec.ours and not finishRestore("Sound_MusicVolume", rec.original, rec.ours) then
    rec.stopping = true
    return false
  end
  music = nil
  return true
end

function Sound.MusicState() return music end

function Sound.Tick()
  local at = plain(try(GetTime)) or 0
  for cvar in pairs(pendingRecovery) do
    local activeMusic = cvar == "Sound_MusicVolume" and music
    if not leases[cvar] and not activeMusic then
      local map = GodslayerDB and GodslayerDB.volumeSwap
      local saved = type(map) == "table" and map[cvar] or nil
      local original = type(saved) == "table" and tonumber(saved.original) or nil
      local ours = type(saved) == "table" and tonumber(saved.ours) or nil
      if original == nil or ours == nil or finishRestore(cvar, original, ours) then
        pendingRecovery[cvar] = nil
      end
    end
  end
  for cvar, rec in pairs(leases) do
    local live = numberCVar(cvar)
    if live == nil then
      -- Unknown is not a player move. Keep the lease and retry on the next tick.
    elseif not same(live, rec.ours) then
      abandonLease(cvar, at)
    else
      local any, voice = false, false
      for id, sound in pairs(rec.sounds) do
        local done = at >= sound.ends
        if not done and sound.handle and C_Sound and type(C_Sound.IsPlaying) == "function" then
          local playing = plain(try(C_Sound.IsPlaying, sound.handle))
          if playing == false then done = true end
        end
        if done then rec.sounds[id] = nil else any = true; voice = voice or sound.part == "Voice" end
      end
      rec.voice = voice
      if not any then restoreLease(cvar) end
    end
  end
  for channel, list in pairs(occupancy) do
    for id, sound in pairs(list) do
      local done = at >= sound.ends
      if not done and sound.handle and C_Sound and type(C_Sound.IsPlaying) == "function" then
        local playing = plain(try(C_Sound.IsPlaying, sound.handle))
        if playing == false then done = true end
      end
      if done then list[id] = nil end
    end
    if not next(list) then occupancy[channel] = nil end
  end
  if music and music.unknown then applyMusic() end
  if music and music.stopping then Sound.MusicStop() end
end

local function endFileLeases()
  local list = {}
  for cvar in pairs(leases) do list[#list + 1] = cvar end
  for _, cvar in ipairs(list) do restoreLease(cvar) end
end

function Sound.End()
  endFileLeases()
  Sound.MusicStop()
end

-- The requested 3.0 channel is retained in the signature but routing is fixed by part.
function Sound.PlayFile(path, requested, length, part)
  part = part == "Effects" and "Effects" or "Voice"
  local channel, rec, allowed = prepare(part)
  if not allowed then return false end
  local will, handle = try(PlaySoundFile, path, channel)
  will, handle = plain(will), plain(handle)
  if will then
    track(rec, handle, length, part)
    if part == "Voice" and not rec then trackOccupancy(channel, handle, length) end
  elseif rec and not next(rec.sounds) then
    restoreLease(rec.cvar)
  end
  return will, handle
end

function Sound.PlayKit(id)
  local o = opts()
  local volume = o.master / 100 * o.effects / 100
  if volume <= 0 then return false end
  if volume < 1 and C_Sound and type(C_Sound.PlaySoundWithOptions) == "function" then
    local ok = plain(try(C_Sound.PlaySoundWithOptions, { soundKitID=id, volumeOverride=volume }))
    return ok == true
  end
  return pcall(PlaySound, id)
end

function Sound.SetVolume(part, value)
  if value == nil then value, part = part, "master" end
  part = tostring(part or ""):lower()
  if part ~= "master" and part ~= "music" and part ~= "voice" and part ~= "effects" then return false end
  value = tonumber(value)
  if not value or value < 0 or value > 100 then return false end
  endFileLeases()
  opts()[part] = math.floor(value + 0.5)
  opts().volume = opts().master
  if music then applyMusic() end
  return true
end

function Sound.Levels()
  local o = opts()
  return o.master, o.music, o.voice, o.effects
end

function Sound.Active(cvar)
  if cvar then return leases[cvar] end
  return leases.Sound_DialogVolume or leases.Sound_AmbienceVolume or music
end

function Sound.Login()
  local map = savedMap() or {}
  leases, occupancy, pendingRecovery, music = {}, {}, {}, nil
  local hype = GodslayerDB and GodslayerDB.opts and GodslayerDB.opts.hype
  if type(hype) == "table" and tonumber(hype.duckFrom) then
    local original = tonumber(hype.duckFrom)
    local ours = tonumber(hype.duckTo) or math.floor(original * DUCK * 100 + 0.5) / 100
    map.Sound_MusicVolume = map.Sound_MusicVolume or { original=original, ours=ours }
    hype.duckFrom, hype.duckTo = nil, nil
  end
  for cvar in pairs(CVARS) do
    local saved = map[cvar]
    if type(saved) == "table" then
      local original, ours = tonumber(saved.original), tonumber(saved.ours)
      if original and ours then
        if not finishRestore(cvar, original, ours) then pendingRecovery[cvar] = true end
      else
        clearSaved(cvar)
      end
    end
  end
  if type(GodslayerDB.volumeSwap) == "table" and not next(GodslayerDB.volumeSwap) then GodslayerDB.volumeSwap = nil end
  if not ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
    ticker = true
    try(C_Timer.NewTicker, POLL, function() Sound.Tick() end)
  end
end

local h = Sound.handlers
h.PLAYER_LEAVING_WORLD = Sound.End
h.LOADING_SCREEN_ENABLED = Sound.End
h.PLAYER_LOGOUT = Sound.End

function Sound.RegisterSettings()
  local S = _G.Settings
  if type(S) ~= "table" or type(S.RegisterVerticalLayoutCategory) ~= "function"
     or type(S.RegisterAddOnCategory) ~= "function" or type(S.RegisterProxySetting) ~= "function"
     or type(S.CreateSliderOptions) ~= "function" or type(S.CreateSlider) ~= "function"
     or type(S.CreateCheckbox) ~= "function" or type(S.CreateDropdown) ~= "function"
     or type(S.CreateControlTextContainer) ~= "function" or type(S.VarType) ~= "table" then return end

  local ok = pcall(function()
    local category, layout = S.RegisterVerticalLayoutCategory("Godslayer")
    if not category then return end
    local labels = { master="Master", music="Music", voice="Voice", effects="Effects" }
    local tips = {
      master="Logical level applied to Music, Voice, and Effects.",
      music="Hunt songs on the game's Music channel. When game Music is disabled, the Master-channel fallback cannot be adjusted per file.",
      voice="At 100, voice plays at full game volume on Master. Below 100, it briefly borrows Dialog, or Ambience when Dialog is disabled.",
      effects="At 100, effects play at full game volume on Master. Below 100, they briefly borrow Ambience, or idle Dialog when Ambience is disabled.",
    }
    for _, part in ipairs({ "master", "music", "voice", "effects" }) do
      local key = part
      local setting = S.RegisterProxySetting(category, "GODSLAYER_VOLUME_" .. part:upper(), S.VarType.Number,
        labels[key], 100, function() return opts()[key] end,
        function(value) Sound.SetVolume(key, value) end)
      S.CreateSlider(category, setting, S.CreateSliderOptions(0, 100, 1), tips[key])
    end

    local calls = S.RegisterProxySetting(category, "GODSLAYER_FLAG_CALLS", S.VarType.String,
      "Flag calls", "important", function() return opts().flag.calls end, function(value)
        if value == "important" or value == "all" or value == "off" then opts().flag.calls = value end
      end)
    S.CreateDropdown(category, calls, function()
      local c = S.CreateControlTextContainer()
      c:Add("important", "Important"); c:Add("all", "All"); c:Add("off", "Off")
      return c:GetData()
    end, "Important voices only the first drop, takes, captures, and a teammate returning your flag. All voices every confirmed event.")

    local voice = S.RegisterProxySetting(category, "GODSLAYER_FLAG_VOICE", S.VarType.Boolean,
      "Flag voice", true, function() return opts().flag.voice end,
      function(value) opts().flag.voice = value and true or false end)
    S.CreateCheckbox(category, voice, "Keep flag banners but turn their announcer lines on or off.")

    local repeatGap = S.RegisterProxySetting(category, "GODSLAYER_FLAG_REPEAT", S.VarType.Number,
      "Flag voice repeat", 30, function() return opts().flag.repeatGap end, function(value)
        value = tonumber(value)
        if value then opts().flag.repeatGap = math.max(10, math.min(120, math.floor(value + 0.5))) end
      end)
    S.CreateSlider(category, repeatGap, S.CreateSliderOptions(10, 120, 1),
      "Minimum seconds between drop, re-pick, and return voice lines for the same flag.")
    if ns.Hunters and ns.Hunters.RegisterSettings then ns.Hunters.RegisterSettings(S, category, layout) end
    S.RegisterAddOnCategory(category)
  end)
  return ok and true or nil
end
