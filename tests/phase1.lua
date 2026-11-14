-- Focused phase-1 rules: battleground flag truth and Godslayer's temporary-channel volume.
return function(M, check, eq, ME)
  local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Sound.lua", "Stage.lua", "Clip.lua", "Hype.lua",
    "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Flag.lua", "Control.lua",
    "Death.lua", "Threat.lua", "Comm.lua", "Hunters.lua", "Rival.lua", "Wheel.lua", "UI.lua" }
  local PATH = "Interface\\AddOns\\Godslayer\\Sounds\\titan\\flagtaken.ogg"

  local function resetAudio()
    M.audio.files, M.audio.lengths = {}, {}
    M.audio.played, M.audio.stopped, M.audio.kits = {}, {}, {}
    M.audio.music, M.audio.musicStops, M.audio.next = nil, 0, 0
    M.audio.sets, M.audio.cvarWrites, M.audio.lockCVars = 0, {}, nil
    M.audio.cvars = { Sound_EnableAllSound = "1", Sound_EnableMusic = "1", Sound_EnableDialog = "1",
      Sound_DialogVolume = "0.8", Sound_AmbienceVolume = "0.7", Sound_MusicVolume = "0.8" }
  end

  local function fresh(withWidgets, db, beforeLogin)
    M.now, M.wall, M.timers, M.units, M.guids, M.group = 1000, 1791400000, {}, {}, {}, {}
    M.frames, M.sentAddon, M.sentChat, M.printed = { UIParent, Minimap, GameTooltip }, {}, {}, {}
    M.inGuild, M.lockdown, M.inCombat, M.hk, M.dk, M.renown = true, false, false, 0, 0, nil
    M.zone, M.subzone, M.myLevel = "Warsong Gulch", "", 60
    M.map = { id = 1339, north = 1000, west = 1000, tall = 1000, wide = 1000 }
    M.flags, M.widgets, M.settings = {}, {}, { categories = {}, controls = {} }
    M.bg = { state = Enum.PvPMatchState.Engaged, rows = {}, factional = true, cols = { "Flag Captures" } }
    M.arenaFaction, M.secretArenaFaction = 0, nil
    M.setSpoken(nil)
    resetAudio()
    if withWidgets then
      M.widget(1891, 1, "0") -- Alliance score/carrier: truth for the Horde flag
      M.widget(1892, 1, "0") -- Horde score/carrier: truth for the Alliance flag
    end
    GodslayerDB = db
    GodslayerFrame, GodslayerWindow, GodslayerMinimapButton, GodslayerHypeBanner = nil, nil, nil, nil
    M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE",
      race = "Scourge", sex = 2, faction = "Horde", isMe = true })
    local copy = M.load("Godslayer", FILES)
    M.fire("ADDON_LOADED", "Godslayer")
    if beforeLogin then beforeLogin() end
    M.fire("PLAYER_LOGIN")
    return copy
  end

  local function observe(copy)
    local seen = { voices = {}, banners = {} }
    copy.Hype.Say = function(clip) seen.voices[#seen.voices + 1] = clip return true end
    copy.Stage.FlagBanner = function(flag, title, color, line)
      seen.banners[#seen.banners + 1] = { flag = flag, title = title, line = line }
    end
    return seen
  end

  local function clear(seen) seen.voices, seen.banners = {}, {} end
  local function chat(line) M.fire("CHAT_MSG_BG_SYSTEM_NEUTRAL", line) end
  local function widget(id, state, text)
    M.widget(id, state, text)
    M.fire("UPDATE_UI_WIDGET", { widgetID = id, widgetSetID = 1, widgetType = 0 })
  end

  -- No transition out of unknown is announced, whether the first readable truth is chat or a
  -- widget. Widget initialization happens silently after entering the battleground.
  do
    local copy = fresh(false)
    local seen = observe(copy)
    M.advance(1.1)
    chat("The Horde flag was picked up by Sneak!")
    eq(copy.Flag.State("Horde"), "carried", "flag unknown: first chat truth initializes state")
    eq(#seen.voices, 0, "flag unknown: no voice out of unknown")
    eq(#seen.banners, 0, "flag unknown: no banner out of unknown")
  end

  -- A drop that is picked back up inside 2.5 seconds is a fumble and produces nothing.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    chat("The Horde flag was picked up by Sneak!")
    eq(#seen.voices, 1, "flag important: your flag taken is voiced")
    eq(#seen.banners, 1, "flag important: your flag taken is bannered")
    clear(seen)
    chat("The Horde flag was dropped by Sneak!")
    M.advance(1)
    chat("The Horde flag was picked up by Sneak!")
    M.advance(2)
    eq(copy.Flag.State("Horde"), "carried", "flag fumble: remains carried")
    eq(#seen.voices, 0, "flag fumble: no voice")
    eq(#seen.banners, 0, "flag fumble: no banner")
  end

  -- Forever's own wording is not readable offline: a capitalised "Flag", a missing "!" and trailing
  -- spaces must drive the same state machine, and a flag line that matches nothing is logged once.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    chat("The Horde Flag was picked up by Sneak!")
    eq(copy.Flag.State("Horde"), "carried", "flag wording: capital Flag recognised")
    eq(#seen.voices, 1, "flag wording: capital Flag voiced like the lower-case line")
    chat("The Horde Flag was dropped by Sneak ")
    M.advance(2.6)
    eq(copy.Flag.State("Horde"), "down", "flag wording: no closing punctuation recognised")
    chat("The Alliance Flag Was Picked Up By Zed!")
    eq(copy.Flag.State("Alliance"), "carried", "flag wording: any capitalisation recognised")
    local before = #GodslayerDB.log
    chat("A flag-shaped line nobody expected!")
    chat("A flag-shaped line nobody expected!")
    eq(#GodslayerDB.log, before + 1, "flag wording: an unrecognised flag line is logged once")
    check(GodslayerDB.log[#GodslayerDB.log]:find("unparsed", 1, true), "flag wording: the log says it was not parsed")
  end

  -- Important voices the first confirmed drop in a carry, not its re-pick or later drops; the
  -- per-flag cooldown also covers defender returns.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    chat("The Horde flag was picked up by Sneak!")
    clear(seen)
    chat("The Horde flag was dropped by Sneak!")
    M.advance(2.6)
    eq(#seen.voices, 1, "flag important: first confirmed drop voiced")
    eq(copy.Flag.State("Horde"), "down", "flag important: confirmed drop state")
    chat("The Horde flag was picked up by Sneak!")
    chat("The Horde flag was dropped by Sneak!")
    M.advance(2.6)
    eq(#seen.voices, 1, "flag important: re-pick and later drop not voiced")
    eq(#seen.banners, 3, "flag important: first drop, re-pick and later drop banner")
    chat("The Horde flag was returned to its base by Guard!")
    eq(#seen.voices, 1, "flag cooldown: immediate teammate return voice suppressed")
    chat("The Horde flag was picked up by Sneak!")
    eq(#seen.voices, 2, "flag cooldown: taken from home is exempt")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    chat("The Horde flag was picked up by Sneak!")
    clear(seen)
    M.advance(31)
    chat("The Horde flag was returned to its base by Guard!")
    eq(#seen.voices, 1, "flag important: teammate return of your flag voiced")
  end

  -- All voices every confirmed event, still honoring the cooldown; off changes state but emits
  -- nothing, and the voice switch keeps banners.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    copy.Flag.Options().calls, copy.Flag.Options().repeatGap = "all", 10
    chat("The Alliance flag was picked up by Runner!")
    clear(seen)
    chat("The Alliance flag was dropped by Runner!")
    M.advance(2.6)
    M.advance(10.1)
    chat("The Alliance flag was picked up by Runner!")
    eq(#seen.voices, 2, "flag all: confirmed drop and later re-pick voiced")
    M.advance(10.1)
    chat("The Alliance flag is now placed at its base.")
    eq(#seen.voices, 3, "flag all: automatic return voiced after cooldown")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    copy.Flag.Options().calls = "off"
    chat("The Horde flag was picked up by Sneak!")
    eq(copy.Flag.State("Horde"), "carried", "flag off: truth still advances")
    eq(#seen.voices + #seen.banners, 0, "flag off: no output")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    copy.Flag.Options().voice = false
    chat("The Horde flag was picked up by Sneak!")
    eq(#seen.voices, 0, "flag voice off: no voice")
    eq(#seen.banners, 1, "flag voice off: banner remains")
  end

  -- Chat and widget copies inside one second describe one event, not two.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    widget(1891, 2, "0")
    chat("The Horde flag was picked up by Sneak!")
    eq(#seen.voices, 1, "flag duplicate: widget then chat has one voice")
    eq(#seen.banners, 1, "flag duplicate: widget then chat has one banner")
  end

  -- Arena faction is authoritative for "your" side, with UnitFactionGroup as the fallback.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    M.arenaFaction = nil
    chat("The Horde flag was picked up by Sneak!")
    check(seen.banners[1].title:find("YOUR", 1, true) == 1, "flag side: unit faction fallback")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    M.arenaFaction = 1
    chat("The Alliance flag was picked up by Runner!")
    check(seen.banners[1].title:find("YOUR", 1, true) == 1, "flag side: arena faction wins")
  end

  -- Widget-only fallback: take, drop after the fumble window, silent home after twelve seconds,
  -- and a capture-count increment winning over the simultaneous not-carried state.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    widget(1891, 2, "0")
    clear(seen)
    widget(1891, 1, "0")
    M.advance(2.6)
    eq(copy.Flag.State("Horde"), "down", "flag widget: no carrier confirms down")
    eq(#seen.voices, 1, "flag widget: first confirmed drop voiced")
    M.advance(12.5)
    eq(copy.Flag.State("Horde"), "home", "flag widget: down times out home silently")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    widget(1891, 3, "0")
    eq(copy.Flag.State("Horde"), "carried",
      "flag R6: dynamic-icon nonflashing state 3 is carried")
    clear(seen)
    widget(1891, 1, "0")
    M.advance(2.6)
    eq(copy.Flag.State("Horde"), "down", "flag R6: state 3 followed by state 1 confirms a drop")
    eq(#seen.banners, 1, "flag R6: state 3 followed by state 1 calls the drop exactly once")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    widget(1891, 2, "0")
    clear(seen)
    widget(1891, 1, "1")
    eq(copy.Flag.State("Horde"), "respawning", "flag widget: capture count increment means captured")
    eq(#seen.voices, 1, "flag widget: capture voiced")
    M.advance(3)
    eq(#seen.banners, 1, "flag widget: capture did not become a delayed drop")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    M.widget(1640, 2, "0", { widgetTag = "alliance-flag-carrier" })
    M.fire("UPDATE_UI_WIDGET", { widgetID = 1640, widgetSetID = 1, widgetType = 0 })
    eq(copy.Flag.State("Horde"), "carried", "flag widget 1640: identifiable Alliance carrier maps to Horde flag")
    eq(#seen.voices, 1, "flag widget 1640: identifiable state participates in fallback")
  end

  -- Explicit and automatic returns have distinct policy; a capture cancels a chat drop; reset
  -- text silently homes both flags.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    chat("The Alliance flag was picked up by Runner!")
    eq(#seen.voices, 1, "flag important: their flag taken by your side is voiced")
    eq(#seen.banners, 1, "flag important: their flag taken by your side is bannered")
    clear(seen)
    chat("The Alliance flag is now placed at its base.")
    eq(copy.Flag.State("Alliance"), "home", "flag auto-return: home")
    eq(#seen.banners, 1, "flag auto-return: banner")
    eq(#seen.voices, 0, "flag auto-return: important is banner only")
    chat("The Alliance flag was picked up by Runner!")
    clear(seen)
    chat("The Alliance flag was returned to its base by Guard!")
    eq(#seen.banners, 1, "flag return: their flag returned has a banner")
    eq(#seen.voices, 0, "flag return: their flag returned is not voiced on important")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    chat("The Alliance flag was picked up by Runner!")
    clear(seen)
    chat("The Alliance flag was dropped by Runner!")
    chat("Vesh captured the Alliance flag!")
    M.advance(3)
    eq(copy.Flag.State("Alliance"), "respawning", "flag capture: pending drop cancelled")
    eq(#seen.voices, 1, "flag capture: one capture voice")
    eq(#seen.banners, 1, "flag capture: no delayed drop banner")
    clear(seen)
    chat("The flags are now placed at their bases.")
    eq(copy.Flag.State("Alliance"), "home", "flag reset: Alliance home")
    eq(copy.Flag.State("Horde"), "home", "flag reset: Horde home")
    eq(#seen.voices + #seen.banners, 0, "flag reset: silent")

    copy = fresh(true)
    seen = observe(copy)
    M.advance(1.1)
    chat("The Alliance flag was picked up by Runner!")
    clear(seen)
    chat("The Alliance flag was dropped by Runner!")
    M.advance(2.6)
    chat("Vesh captured the Alliance flag!")
    eq(#seen.voices, 2, "flag cooldown: capture is exempt after a drop voice")
  end

  -- Each faction owns one banner frame: another event rewrites that frame, while the other
  -- faction has an independent frame.
  do
    local copy = fresh(true)
    copy.Stage.FlagBanner("Horde", "FIRST", { 1, 0, 0 }, "one")
    local horde = copy.Stage.flagBanners.Horde
    copy.Stage.FlagBanner("Horde", "SECOND", { 1, 1, 0 }, "two")
    eq(copy.Stage.flagBanners.Horde, horde, "flag banner: same flag updates one frame")
    eq(horde.title:GetText(), "SECOND", "flag banner: latest title replaces the old title")
    copy.Stage.FlagBanner("Alliance", "OTHER", { 0, 0, 1 }, "three")
    check(copy.Stage.flagBanners.Alliance ~= horde, "flag banner: each flag has an independent frame")
  end

  -- Secret and unrecognised locale text are ignored without an escaped event error. A delayed
  -- callback older than four seconds updates truth but is not announced.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    chat(M.secret())
    chat("Die Flagge der Horde wurde von Sneak aufgenommen!")
    eq(copy.Flag.State("Horde"), "home", "flag parsing: secret and unknown locale ignored")
    check(copy.errors == nil, "flag parsing: no handler error")
    chat("The Horde flag was picked up by Sneak!")
    clear(seen)
    chat("The Horde flag was dropped by Sneak!")
    M.now = M.now + 5
    copy.Flag.Tick(M.now)
    eq(copy.Flag.State("Horde"), "down", "flag stale: truth still becomes down")
    eq(#seen.voices + #seen.banners, 0, "flag stale: line older than four seconds discarded")
  end

  -- The four-second age also follows the line into Hype's queue; a flag call waiting behind a
  -- long existing line is discarded instead of narrating old play.
  do
    local copy = fresh(true)
    M.advance(1.1)
    GodslayerDB.opts.hype.pack, GodslayerDB.opts.hype.mixed = "titan", true
    local fading = "Interface\\AddOns\\Godslayer\\Sounds\\titan\\fading.ogg"
    M.audio.files[fading], M.audio.lengths[fading] = true, copy.Hype.ClipLength("fading", "titan")
    M.audio.files[PATH], M.audio.lengths[PATH] = true, copy.Hype.ClipLength("flagtaken", "titan")
    copy.Stage.FlagBanner = function() end
    copy.Hype.Say("fading", 2)
    chat("The Horde flag was picked up by Sneak!")
    M.advance(5)
    eq(#M.audio.played, 1, "flag stale queue: call waiting over four seconds discarded")
  end

  -- Verification logging is one bounded line per recognised chat line and widget change.
  do
    local copy = fresh(true)
    observe(copy)
    M.advance(1.1)
    local before = #GodslayerDB.log
    chat("The Horde flag was picked up by Sneak!")
    widget(1891, 2, "0")
    local added = 0
    for i = before + 1, #GodslayerDB.log do if GodslayerDB.log[i]:find(" flag: ", 1, true) then added = added + 1 end end
    eq(added, 2, "flag verification log: chat and widget each write once")
  end

  -- Positions identify by texture even if engine indexes reorder, and motion never generates a
  -- callout or a claim about home/down.
  do
    local copy = fresh(true)
    local seen = observe(copy)
    M.advance(1.1)
    M.playerAt(500, 500)
    M.flagsAt({ { north = 600, west = 500, texture = 137200 }, { north = 400, west = 500, texture = 137218 } })
    copy.Flag.Tick(M.now + 1)
    local rows = copy.Flag.Read()
    check(rows and rows[1] and rows[2], "flag positions: two texture-identified rows")
    local names = { [rows[1].name] = true, [rows[2].name] = true }
    check(names["Alliance flag"] and names["Horde flag"], "flag positions: faction comes from texture")
    M.flagsAt({ { north = 410, west = 500, texture = 137218 }, { north = 590, west = 500, texture = 137200 } })
    copy.Flag.Tick(M.now + 2)
    eq(#seen.voices + #seen.banners, 0, "flag positions: movement and index reorder never call out")
  end

  -- Slash settings persist in opts and watch remains the on/off shortcut.
  do
    local copy = fresh(true)
    copy.Flag.Command("calls all")
    copy.Flag.Command("voice off")
    copy.Flag.Command("repeat 45")
    eq(GodslayerDB.opts.flag.calls, "all", "flag command: calls persisted")
    eq(GodslayerDB.opts.flag.voice, false, "flag command: voice persisted")
    eq(GodslayerDB.opts.flag.repeatGap, 45, "flag command: repeat persisted")
    copy.Flag.Command("watch")
    eq(GodslayerDB.opts.flag.calls, "off", "flag command: watch turns calls off")
    copy.Flag.Command("watch")
    eq(GodslayerDB.opts.flag.calls, "important", "flag command: watch restores important")
  end

  -- Volume 100 is byte-for-byte the old path: no CVar writes.
  do
    local copy = fresh(true)
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    local writes = #M.audio.cvarWrites
    copy.Sound.PlayFile(PATH, "Master", 2)
    eq(#M.audio.cvarWrites, writes, "volume 100: no CVar writes")
    eq(M.audio.played[#M.audio.played].channel, nil, "volume 100: played record remains ordinary")
    eq(M.audio.channel, "Master", "volume 100: requested channel unchanged")
  end

  -- A sub-100 clip swaps Dialog, persists crash recovery, and restores after the handle ends.
  do
    local copy = fresh(true)
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    copy.Sound.SetVolume(50)
    copy.Sound.PlayFile(PATH, "Master", 2)
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.5, "volume swap: Dialog set to Godslayer level")
    check(type(GodslayerDB.volumeSwap) == "table", "volume swap: crash recovery persisted")
    M.advance(2.1)
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.8, "volume swap: original restored")
    eq(GodslayerDB.volumeSwap, nil, "volume swap: crash recovery cleared")
  end

  -- Voice, SFX, and the chat wheel all enter through the same wrapper.
  do
    local copy = fresh(true)
    GodslayerDB.opts.hype.pack, GodslayerDB.opts.hype.mixed = "titan", true
    local sfx = "Interface\\AddOns\\Godslayer\\Sounds\\sfx\\horn.ogg"
    local wheel = "Interface\\AddOns\\Godslayer\\Sounds\\wheel\\wheel_1.ogg"
    M.audio.files[PATH], M.audio.lengths[PATH] = true, copy.Hype.ClipLength("flagtaken", "titan")
    M.audio.files[sfx], M.audio.lengths[sfx] = true, copy.SFX.horn
    M.audio.files[wheel], M.audio.lengths[wheel] = true, copy.WHEEL.clips.wheel_1
    copy.Sound.SetVolume(55)
    copy.Hype.Sfx("horn")
    eq(M.audio.channel, "Dialog", "volume wrapper: Hype SFX uses swap channel")
    M.fire("LOADING_SCREEN_ENABLED")
    copy.Hype.Say("flagtaken", 2)
    eq(M.audio.channel, "Dialog", "volume wrapper: announcer voice uses swap channel")
    M.advance(3)
    copy.Wheel.Say(1)
    eq(M.audio.channel, "Dialog", "volume wrapper: chat wheel uses swap channel")
  end

  -- An outside slider move wins; overlapping clips share one swap and restore after the last.
  do
    local copy = fresh(true)
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    copy.Sound.SetVolume(40)
    copy.Sound.PlayFile(PATH, "Master", 2)
    SetCVar("Sound_DialogVolume", 0.33)
    M.advance(3)
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.33, "volume swap: player change is not restored over")
    eq(GodslayerDB.volumeSwap, nil, "volume swap: player change drops backup")

    copy = fresh(true)
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    copy.Sound.SetVolume(60)
    copy.Sound.PlayFile(PATH, "Master", 2)
    M.advance(0.5)
    copy.Sound.PlayFile(PATH, "Master", 2)
    local dialogWrites = 0
    for _, w in ipairs(M.audio.cvarWrites) do if w[1] == "Sound_DialogVolume" then dialogWrites = dialogWrites + 1 end end
    eq(dialogWrites, 1, "volume overlap: clips share one initial swap")
    M.advance(1.6)
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.6, "volume overlap: first ending does not restore")
    M.advance(0.5)
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.8, "volume overlap: last ending restores")
  end

  -- Login recovers a stranded swap; loading screens and leaving world end a live one.
  do
    local db = { opts = { volume = 50 }, volumeSwap = { cvar = "Sound_DialogVolume", original = 0.8, ours = 0.5 } }
    local copy = fresh(true, db, function() M.audio.cvars.Sound_DialogVolume = "0.5" end)
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.8, "volume crash: login restores stranded channel")
    eq(GodslayerDB.volumeSwap, nil, "volume crash: login always clears recovery")
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    copy.Sound.PlayFile(PATH, "Master", 2)
    M.fire("LOADING_SCREEN_ENABLED")
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.8, "volume loading: loading screen restores")
    copy.Sound.PlayFile(PATH, "Master", 2)
    M.fire("PLAYER_LEAVING_WORLD")
    eq(tonumber(M.audio.cvars.Sound_DialogVolume), 0.8, "volume loading: leaving world restores")
  end

  -- Spoken owns Dialog while speaking. Godslayer does no swap and uses Master when Dialog is off.
  do
    local copy = fresh(true)
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    copy.Sound.SetVolume(50)
    M.setSpoken(true)
    copy.Sound.PlayFile(PATH, "Master", 2)
    eq(#M.audio.cvarWrites, 0, "volume Spoken: no swap while Spoken speaks")
    eq(M.audio.channel, "Dialog", "volume Spoken: enabled Dialog stays Dialog without swap")
    M.audio.cvars.Sound_EnableDialog = "0"
    copy.Sound.PlayFile(PATH, "Master", 2)
    eq(M.audio.channel, "Master", "volume Spoken: disabled Dialog falls back to Master")
    M.setSpoken(nil)
  end

  -- Dialog-disabled swaps Ambience; zero is silence for files and soundkits; supported soundkits
  -- receive the override while kill music remains on the Music path and volume.
  do
    local copy = fresh(true)
    M.audio.files[PATH], M.audio.lengths[PATH] = true, 2
    copy.Sound.SetVolume(25)
    M.audio.cvars.Sound_EnableDialog = "0"
    copy.Sound.PlayFile(PATH, "SFX", 2)
    eq(M.audio.channel, "Ambience", "volume fallback: Dialog-disabled file uses Ambience")
    eq(tonumber(M.audio.cvars.Sound_AmbienceVolume), 0.25, "volume fallback: Ambience swapped")
    M.fire("PLAYER_LOGOUT")
    eq(tonumber(M.audio.cvars.Sound_AmbienceVolume), 0.7, "volume fallback: Ambience restored at logout")

    copy.Sound.SetVolume(0)
    local played, kits = #M.audio.played, #M.audio.kits
    copy.Sound.PlayFile(PATH, "Master", 2)
    copy.Sound.PlayKit(8959)
    eq(#M.audio.played, played, "volume zero: file silence")
    eq(#M.audio.kits, kits, "volume zero: soundkit silence")

    copy.Sound.SetVolume(35)
    copy.Sound.PlayKit(8959)
    eq(M.audio.kits[#M.audio.kits].volume, 0.35, "volume soundkit: volumeOverride used")

    local playWithOptions = C_Sound.PlaySoundWithOptions
    C_Sound.PlaySoundWithOptions = nil
    copy.Sound.PlayKit(8959)
    eq(M.audio.kits[#M.audio.kits].legacy, true, "volume soundkit: unsupported override keeps legacy playback")
    C_Sound.PlaySoundWithOptions = playWithOptions

    local own = "Interface\\AddOns\\GodslayerMusic\\kill.mp3"
    M.audio.files[own] = true
    local musicBefore = M.audio.cvars.Sound_MusicVolume
    copy.Hype.Engage({ name = "Music Target" })
    eq(M.audio.music, own, "volume music: kill song still uses PlayMusic")
    eq(M.audio.cvars.Sound_MusicVolume, musicBefore, "volume music: wrapper does not change Music volume")
  end

  -- Options page and slash command expose the persisted volume and all flag controls.
  do
    local copy = fresh(true)
    local category = M.settings.categories[#M.settings.categories]
    check(category and category.name == "Godslayer" and category.registered, "settings: Godslayer add-on category registered")
    local found = {}
    for _, setting in ipairs(category.settings or {}) do found[setting.variable] = setting end
    check(found.GODSLAYER_VOLUME and found.GODSLAYER_FLAG_CALLS and found.GODSLAYER_FLAG_VOICE and found.GODSLAYER_FLAG_REPEAT,
      "settings: volume and flag controls registered")
    found.GODSLAYER_VOLUME.set(42)
    eq(GodslayerDB.opts.volume, 42, "settings: volume slider persists")
    local slash = SlashCmdList.GODSLAYER
    slash("volume 17")
    eq(GodslayerDB.opts.volume, 17, "volume command: value persists")
    slash("volume")
    check(M.printed[#M.printed]:find("NPC line", 1, true) ~= nil, "volume command: collision behavior explained")
    local settings = Settings
    Settings = nil
    check(pcall(copy.Sound.RegisterSettings), "settings: absent API is skipped silently")
    Settings = settings
  end
end
