-- Godslayer sound: one volume boundary around every file the addon owns.
--
-- PlaySoundFile has no volume argument. Below 100, a clip therefore borrows Dialog (or Ambience
-- when Dialog is disabled), restores it after every overlapping Godslayer handle is finished, and
-- never overwrites a channel value somebody changed while the clip was in the air.

local _, ns = ...
local plain, try = ns.plain, ns.try

local Sound = { handlers = {} }
ns.Sound = Sound

local POLL, GRACE, EPSILON = 0.25, 0.5, 0.005
local CVARS = { Sound_DialogVolume = true, Sound_AmbienceVolume = true }
local active, ticker, serial

local function opts()
  local db = GodslayerDB
  if not db then return {} end
  db.opts = type(db.opts) == "table" and db.opts or {}
  local n = tonumber(db.opts.volume)
  if not n then n = 100 end
  db.opts.volume = math.max(0, math.min(100, math.floor(n + 0.5)))
  return db.opts
end

local function numberCVar(name)
  return tonumber(plain(try(GetCVar, name)))
end

local function clearSaved()
  if GodslayerDB then GodslayerDB.volumeSwap = nil end
end

local function same(a, b)
  return type(a) == "number" and type(b) == "number" and math.abs(a - b) <= EPSILON
end

local function restore()
  local a = active
  active = nil
  clearSaved()
  if not a then return end
  local now = numberCVar(a.cvar)
  if same(now, a.ours) then pcall(SetCVar, a.cvar, a.original) end
end
Sound.End = restore

local function spokenPlaying()
  local spoken = _G.Spoken
  if type(spoken) ~= "table" or type(spoken.IsPlaying) ~= "function" then return false end
  return plain(try(spoken.IsPlaying, spoken)) == true
end

local function desiredChannel(requested)
  if plain(try(GetCVar, "Sound_EnableDialog")) == "0" then
    return "Ambience", "Sound_AmbienceVolume"
  end
  return "Dialog", "Sound_DialogVolume"
end

-- Returns the channel on which this file must be played and whether a swap is active for it.
local function prepare(requested, volume)
  if active then
    -- Treat an outside change as the player's. Drop the backup before doing anything else and do
    -- not immediately write over the value they just chose.
    if not same(numberCVar(active.cvar), active.ours) then
      active = nil
      clearSaved()
      return requested or "Master", false
    end
    return active.channel, true
  end

  local channel, cvar = desiredChannel(requested)
  if spokenPlaying() then
    -- Spoken owns Dialog while it speaks. With Dialog disabled it deliberately routes elsewhere,
    -- so Godslayer uses Master and leaves every channel CVar alone.
    return channel == "Dialog" and "Dialog" or "Master", false
  end

  local original = numberCVar(cvar)
  local ours = volume / 100
  if type(SetCVar) ~= "function" or original == nil then return requested or "Master", false end
  if not pcall(SetCVar, cvar, ours) or not same(numberCVar(cvar), ours) then
    clearSaved()
    return requested or "Master", false
  end
  active = { cvar = cvar, channel = channel, original = original, ours = ours, sounds = {} }
  GodslayerDB.volumeSwap = { cvar = cvar, original = original, ours = ours }
  return channel, true
end

local function track(handle, length)
  if not active then return end
  serial = (serial or 0) + 1
  active.sounds[serial] = {
    handle = type(handle) == "number" and handle or nil,
    ends = (plain(try(GetTime)) or 0) + math.max(0, tonumber(length) or 0) + GRACE,
  }
end

function Sound.Tick()
  if not active then return end
  if not same(numberCVar(active.cvar), active.ours) then
    active = nil
    clearSaved()
    return
  end
  local now, any = plain(try(GetTime)) or 0, false
  for id, rec in pairs(active.sounds) do
    local done = now >= rec.ends
    if not done and rec.handle and C_Sound and type(C_Sound.IsPlaying) == "function" then
      local playing = plain(try(C_Sound.IsPlaying, rec.handle))
      if playing == false then done = true end
    end
    if done then active.sounds[id] = nil else any = true end
  end
  if not any then restore() end
end

-- The only path for Godslayer-owned voice, SFX and wheel files. Music probes and the kill song are
-- intentionally outside it: they remain governed by the Music slider and Hype's existing duck.
function Sound.PlayFile(path, requested, length)
  local volume = opts().volume or 100
  if volume <= 0 then return false end
  if volume >= 100 then
    local will, handle = try(PlaySoundFile, path, requested or "Master")
    return plain(will), plain(handle)
  end

  local channel, swapped = prepare(requested, volume)
  local will, handle = try(PlaySoundFile, path, channel)
  will, handle = plain(will), plain(handle)
  if will then
    if swapped then track(handle, length) end
  elseif swapped and active and not next(active.sounds) then
    restore()
  end
  return will, handle
end

function Sound.PlayKit(id)
  local volume = opts().volume or 100
  if volume <= 0 then return false end
  if volume < 100 and C_Sound and type(C_Sound.PlaySoundWithOptions) == "function" then
    local ok = plain(try(C_Sound.PlaySoundWithOptions, { soundKitID = id, volumeOverride = volume / 100 }))
    return ok == true
  end
  return pcall(PlaySound, id)
end

function Sound.SetVolume(value)
  value = tonumber(value)
  if not value or value < 0 or value > 100 then return false end
  restore()
  opts().volume = math.floor(value + 0.5)
  return true
end

function Sound.Login()
  local saved = GodslayerDB and GodslayerDB.volumeSwap
  if type(saved) == "table" and CVARS[saved.cvar] then
    local original, ours = tonumber(saved.original), tonumber(saved.ours)
    if original and ours and same(numberCVar(saved.cvar), ours) then
      pcall(SetCVar, saved.cvar, original)
    end
  end
  clearSaved()
  active = nil
  if not ticker and C_Timer and type(C_Timer.NewTicker) == "function" then
    ticker = true -- some compatible clients return no ticker object even though registration worked
    try(C_Timer.NewTicker, POLL, function() Sound.Tick() end)
  end
end

function Sound.Active() return active end

local h = Sound.handlers
h.PLAYER_LEAVING_WORLD = restore
h.LOADING_SCREEN_ENABLED = restore
h.PLAYER_LOGOUT = restore

-- The settings panel is deliberately feature-detected as a unit. A partial or older Settings API
-- gets no category rather than a login error or a half-working control.
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
    local volume = S.RegisterProxySetting(category, "GODSLAYER_VOLUME", S.VarType.Number,
      "Godslayer volume", 100, function() return opts().volume end,
      function(value) Sound.SetVolume(value) end)
    local volumeOptions = S.CreateSliderOptions(0, 100, 1)
    S.CreateSlider(category, volume, volumeOptions,
      "Godslayer briefly sets the Dialog (or Ambience) volume while its own lines play, so an NPC line at that exact moment plays at Godslayer's level.")

    local calls = S.RegisterProxySetting(category, "GODSLAYER_FLAG_CALLS", S.VarType.String,
      "Flag calls", "important", function() return opts().flag.calls end, function(value)
        if value == "important" or value == "all" or value == "off" then opts().flag.calls = value end
      end)
    S.CreateDropdown(category, calls, function()
      local c = S.CreateControlTextContainer()
      c:Add("important", "Important")
      c:Add("all", "All")
      c:Add("off", "Off")
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
