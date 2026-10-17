-- Godslayer hype: your kill song, and an announcer who takes Olympus personally.
--
-- THE FIGHT. The moment a fight with an enemy player starts, your song starts with it: war drums,
-- and now and then a word from the announcer. It plays through the fight and on into the hunt,
-- and fades a little while after the last fight ends if nobody died.
--
-- THE HUNT. The first player you kill starts it: FIRST BLOOD is called, over the song already playing.
-- Every kill is heard at once, a blade that rings a note higher each time. The rungs are spaced
-- out so the top ones stay rare: MEGA KILL at two, ULTRA KILL at three, GODLIKE at five,
-- UNSTOPPABLE at seven, BEYOND GODLIKE at ten, GODSLAYER at fifteen, and a call every five or
-- ten after that. Between rungs the announcer mostly holds their tongue, which is why the next
-- call lands. Each kill keeps the hunt alive for another stretch (90 seconds unless you change
-- it), and a fuse under the banner burns it down. It ends when that runs out with nobody dead,
-- or when you die: SHUT DOWN, the music fades, and the hunt is graded.
--
-- MOMENTS. Some kills are more than a number, and the announcer knows: REVENGE on the player
-- who killed you, DOMINATION over one you keep killing, a GIANT SLAYER, a kill made
-- OUTNUMBERED, a COMEBACK, a word about the victim's class, and a dry one about a victim far
-- below you. A spell you interrupt is DENIED. A duel is called when it ends.
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

local Hype = { handlers = {} }
ns.Hype = Hype

local SOUNDS = "Interface\\AddOns\\Godslayer\\Sounds\\"
local OWN = "Interface\\AddOns\\GodslayerMusic\\"
local SONGS = { OWN .. "kill.mp3", OWN .. "kill.ogg" }
local FADE_MS = 2500
local CALL_DELAY = 0.45    -- kills landing together get one call, for where the count ended up
local OVERLAP = 0.5        -- the next line starts this long before the last one's hall has died away
local BANNER_SECONDS = 3.6
local ASIDE_CHANCE = 0.25  -- how often a dry remark follows the points
local RARE_CHANCE = 0.05   -- and how often, instead, one of the lines you will hear a handful of times ever
local ALLY_GAP = 45        -- seconds between spoken guild kills; the chat line is never held back
local QUEUE_MAX = 7
local MULTI_WINDOW = 12    -- kills this close together count as one run: double, triple, rampage
local FADING = 10          -- the warning comes this long before a hunt runs out
local CROWD_GAP = 8        -- the crowd does not roar more often than this
local SPOT_GAP, SPOT_AGAIN, SPOT_KING_GAP = 120, 900, 30
local RECORD_FROM = 3      -- a best hunt shorter than this is not worth calling a record
local STALE_REMARK, STALE = 9, 14 -- a line that has waited this long is about a fight that has moved on
local BARK_CHANCE = 0.35   -- how often a kill between rungs gets a word at all, and never two kills running
local QUIP_CHANCE = 0.3    -- how often a victim's class is remarked on, once per class per hunt
local GRUDGE = 600         -- seconds a death is remembered for revenge
local DOMINATE = 4         -- kills on one player, with none back, that make it domination
local SHAME_LEVELS, GIANT_LEVELS = 8, 3
local ODDS_ENEMIES, ODDS_GAP = 3, 90 -- alone with this many enemies on screen is outnumbered; said this often at most
local DENY_WINDOW, DENY_VOICE_GAP = 0.6, 25
local DUCK, CARD_FROM, FLAWLESS_FROM = 0.6, 3, 10
local PHASE_TWO = 5        -- kills at which the hunt theme moves to its second, bigger half
local KILL_NOTES = 8       -- the kill sound climbs this many steps and stays on the last
local GRACE = 15           -- seconds out of combat before a fight with no kill in it lets the music go
local GRACE_BG = 60        -- in a battleground, long enough to run back from the graveyard
local ENGAGE_VOICE_GAP, ENGAGE_GOD_GAP = 180, 60 -- how often a fight starting gets a word, and one against an Olympian
local ENGAGE_SHOW_GAP = 20 -- the banner for a fight starting, at most this often

-- rung reached by this many kills in one hunt; each is called once, at the kill that reaches it
-- { kills, banner, clip, colour, how big the moment is on screen (1 to 5) }
local LADDER = {
  { 1, "FIRST BLOOD", "first_blood", { 1, 0.82, 0.2 }, 2 },
  { 2, "MEGA KILL", "mega_kill", { 1, 0.6, 0.1 }, 2 },
  { 3, "ULTRA KILL", "ultra_kill", { 1, 0.42, 0.05 }, 2 },
  { 5, "GODLIKE", "godlike", { 1, 0.25, 0.1 }, 3 },
  { 7, "UNSTOPPABLE", "unstoppable", { 1, 0.15, 0.25 }, 3 },
  { 10, "BEYOND GODLIKE", "beyond_godlike", { 0.95, 0.2, 0.75 }, 4 },
  { 15, "GODSLAYER", "godslayer", { 0.7, 0.35, 1 }, 5 },
  { 20, "TWENTY KILLS", "twenty", { 0.6, 0.5, 1 }, 4 },
  { 25, "TWENTY FIVE", "twentyfive", { 0.5, 0.65, 1 }, 4 },
  { 30, "THIRTY", "thirty", { 0.45, 0.8, 1 }, 4 },
  { 40, "FORTY", "forty", { 0.6, 0.95, 1 }, 5 },
  { 50, "FIFTY", "fifty", { 1, 1, 1 }, 5 },
}
Hype.LADDER = LADDER

-- kills in quick succession, counted apart from the rungs; a run past the last is shown and not said again
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

local hunt          -- { kills, turn, run, bestRun, points, gods, started }
local fight         -- a fight with a player is on, or was a moment ago: { started, turn, god }
local track         -- the music this addon started: { music = "music" | handle, theme, phase }; a fight or a hunt holds it
local engageGen = 0 -- moves on whenever a fight ends, so a word still waiting to be said about it is not
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
  if h.fx == nil then h.fx = true end
  if h.fuse == nil then h.fuse = true end
  if h.moments == nil then h.moments = true end
  if h.barks == nil then h.barks = true end
  if h.duck == nil then h.duck = true end
  if h.deny == nil then h.deny = true end
  if h.duels == nil then h.duels = true end
  if h.photo == nil then h.photo = false end
  if h.clip == nil then h.clip = false end
  if h.engage == nil then h.engage = true end
  if h.class == nil then h.class = true end
  if h.finishers == nil then h.finishers = true end
  if h.wheel == nil then h.wheel = true end
  if h.streaks == nil then h.streaks = true end
  if h.channel ~= "Dialog" and h.channel ~= "SFX" then h.channel = "Master" end
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

-- the rung a hunt of this many kills stands on, and the one above it
local function rungFor(kills)
  local rung, nextRung = LADDER[1], nil
  for i, r in ipairs(LADDER) do
    if kills >= r[1] then rung, nextRung = r, LADDER[i + 1] end
  end
  return rung, nextRung
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
-- Drawn by Stage.lua. more = { size, claws, grade, gradeColor, onStamp }.
local function showBanner(title, color, line, more)
  if ns.Stage then pcall(ns.Stage.Banner, title, color, line, more) end
end

-- THE VOICE -------------------------------------------------------------------
-- Lines are spoken one after another, never over each other. Each is { clip, weight }: a kill
-- call outranks the points, the points outrank a dry remark, and when a new call arrives the
-- remarks still waiting from the last kill are dropped so the voice never falls behind the fight.
local queue, busyUntil, pumping = {}, 0, false
local cuttable              -- the line in the air may be cut short by a kill call: { its sound handle, the busyUntil it set }
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
  if not name or not opts().sfx or not soundOn() or not (ns.SFX and ns.SFX[name]) then return false end
  return plain(try(PlaySoundFile, SOUNDS .. "sfx\\" .. name .. ".ogg", opts().channel)) and true or false
end
Hype.Sfx = sfx

-- One of clip_1, clip_2 ... that this pack has. They are dealt like cards: every take is heard
-- once before any is heard again, and a new deal never opens with the take the last one closed on.
local bags = {}
local function pick(group)
  local count = 0
  while clipLength(group .. "_" .. (count + 1)) do count = count + 1 end
  if count == 0 then return clipLength(group) and group or nil end
  local key = (voiceNow or "?") .. "/" .. group
  local bag = bags[key]
  if not bag or #bag == 0 or bag.count ~= count then
    bag = { count = count }
    for i = 1, count do bag[i] = i end
    bags[key] = bag
  end
  local at = math.random(#bag)
  if #bag > 1 and bag[at] == lastPick[key] then at = at % #bag + 1 end
  local n = table.remove(bag, at)
  lastPick[key] = n
  return group .. "_" .. n
end
Hype.Pick = pick

local function playNow(clip, pack)
  local channel = opts().channel
  -- lines re-pitched to your own song (tools/tune_announcer.py writes them) come first
  local own, handle = try(PlaySoundFile, OWN .. "voice\\" .. pack .. "\\" .. clip .. ".ogg", channel)
  if not plain(own) then own, handle = try(PlaySoundFile, SOUNDS .. pack .. "\\" .. clip .. ".ogg", channel) end
  return plain(handle)
end

-- THE MIX. While the announcer speaks over the hunt's music, the music steps back, and comes
-- forward again when they are done. Only music this addon started, only through the game's own
-- music volume, and the volume you had is written down first so it always comes back.
local ducked, duckTurn, duckBroken = nil, 0, false
local function musicVolume() return tonumber(plain(try(GetCVar, "Sound_MusicVolume"))) end

local function unduck()
  if not ducked then return end
  local was, low = ducked[1], ducked[2]
  ducked = nil
  local o = GodslayerDB and GodslayerDB.opts and GodslayerDB.opts.hype
  if o then o.duckFrom = nil end
  local now = musicVolume()
  -- you moved the slider yourself while it was down: yours stands
  if now and math.abs(now - low) > 0.02 then return end
  pcall(SetCVar, "Sound_MusicVolume", was)
end
Hype.Unduck = unduck

local function duck(seconds)
  if duckBroken or type(SetCVar) ~= "function" or not opts().duck then return end
  if not (track and track.music == "music") then return end
  if not ducked then
    local was = musicVolume()
    if not was or was < 0.08 then return end
    local low = math.floor(was * DUCK * 100 + 0.5) / 100
    opts().duckFrom = was
    if not pcall(SetCVar, "Sound_MusicVolume", low) or math.abs((musicVolume() or was) - low) > 0.02 then
      -- this client will not let an addon move the slider: never try again
      duckBroken, opts().duckFrom = true, nil
      return
    end
    ducked = { was, low }
  end
  duckTurn = duckTurn + 1
  local mine = duckTurn
  C_Timer.After(seconds + 0.2, function() if mine == duckTurn then unduck() end end)
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
  if item[2] >= 3 then duck(length) end -- for a call, not for every line after it
  local handle = playNow(item[1], item[3])
  busyUntil = GetTime() + math.max(0.4, length - OVERLAP)
  cuttable = item[6] and handle and { handle, busyUntil } or nil
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
    -- a word about a fight starting gives way the moment someone dies in it, and so does a groupmate's chat wheel
    -- (only the very line that said it may be cut: anything played since has moved busyUntil on)
    if cuttable and cuttable[2] == busyUntil and GetTime() < busyUntil then
      try(StopSound, cuttable[1], 150)
      busyUntil = GetTime()
    end
    cuttable = nil
    if ns.Wheel and ns.Wheel.Hush then pcall(ns.Wheel.Hush) end
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
  unduck()
  if how == "music" then try(StopMusic) else try(StopSound, how, FADE_MS) end
end

-- The music is started once, by whichever comes first, the fight or the kill, and is held by both:
-- it stops only when neither a hunt nor a fight is left.
local function inBattleground()
  local _, kind = try(IsInInstance)
  return plain(kind) == "pvp"
end

-- Written down while it plays, so a reload or a crash mid-fight cannot leave your song on forever.
local function holdMusic()
  if track then return track end
  local music, theme = startMusic()
  if music then
    track = { music = music, theme = theme, phase = 1 }
    if music == "music" then opts().playing = true end
  end
  return track
end

local function dropMusic()
  opts().playing = nil
  if not track then return end
  local t = track
  track = nil
  stopMusic(t.music)
end

local function settle()
  if not fight then engageGen = engageGen + 1 end
  if not hunt and not fight then dropMusic() end
end

-- The hunt theme has a second, bigger half. A hunt that gets far enough moves into it; the game
-- crossfades one piece of music into the next by itself. Your own song is left alone.
local function phaseTwo()
  local t = track
  if not t or t.phase == 2 or not (t.theme and t.music == "music" and ns.MUSIC and ns.MUSIC.hunt2) then return end
  local ok, will = pcall(PlayMusic, SOUNDS .. "music\\hunt2.ogg")
  if ok and plain(will) ~= false then t.phase = 2 end
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
  if (h.denies or 0) > 0 then parts[#parts + 1] = h.denies .. (h.denies == 1 and " spell denied" or " spells denied") end
  local seconds = math.max(0, math.floor((h.last or GetTime()) - (h.started or GetTime())))
  parts[#parts + 1] = ("%d:%02d from first kill to last"):format(math.floor(seconds / 60), seconds % 60)
  ns.Print("Hunt over: " .. table.concat(parts, ", ") .. ".")
end

-- the kills of the hunt that just ended: one of them may still be waiting for its name
local lastIds, lastEnd = {}, -1000

-- The grade stamped on a hunt: kills, what they were worth, and the best run in it.
local GRADES = { { 30, "S+", { 1, 0.95, 0.6 } }, { 18, "S", { 1, 0.82, 0.2 } }, { 11, "A", { 1, 0.5, 0.1 } }, { 6, "B", { 0.45, 0.7, 1 } }, { 3, "C", { 0.75, 0.75, 0.75 } } }
local function gradeFor(h)
  local score = h.kills + (h.points or 0) * 0.5 + ((h.bestRun or 1) >= 3 and h.bestRun or 0)
  for _, g in ipairs(GRADES) do
    if score >= g[1] then return g[2], g[3] end
  end
end
Hype.GradeFor = gradeFor

local function cardLine(h)
  local parts = { ("%d kills"):format(h.kills) }
  local run = multiFor(h.bestRun or 1)
  if run then parts[#parts + 1] = "|cffff7d0a" .. run[2] .. "|r" end
  if (h.points or 0) > 0 then parts[#parts + 1] = ("|cffffd100+%d|r off Olympus"):format(h.points) end
  local seconds = math.max(0, math.floor((h.last or GetTime()) - (h.started or GetTime())))
  parts[#parts + 1] = ("%d:%02d"):format(math.floor(seconds / 60), seconds % 60)
  return table.concat(parts, "    ")
end

local function photo(delay)
  if not opts().photo or type(Screenshot) ~= "function" then return end
  C_Timer.After(delay or 1.2, function() pcall(Screenshot) end)
end

-- For a recorder: the hunt, written into a screenshot once its card has had its time on screen.
local GRADE_INDEX = { C = 1, B = 2, A = 3, S = 4, ["S+"] = 5 }
local function clipMark(h, reason, grade, wait)
  if not (opts().clip and ns.Clip) then return end
  C_Timer.After(wait, function()
    local now, rung = GetTime(), 0
    for i, r in ipairs(LADDER) do if h.kills >= r[1] then rung = i end end
    local F = ns.Clip.FLAG
    pcall(ns.Clip.Mark, ns.Clip.KIND[reason], {
      kills = h.kills, seconds = now - h.started, since = now - (h.last or now), rung = rung, run = h.bestRun,
      grade = GRADE_INDEX[grade] or 0, points = h.points, peak = now - (h.peak or h.last or now),
      flags = (h.pretend and F.pretend or 0) + (h.record and F.record or 0) + (h.king and F.king or 0)
        + ((reason == "quiet" and h.kills >= FLAWLESS_FROM) and F.flawless or 0),
    })
  end)
end

-- reason: died, quiet (the fuse ran out), or off/stop. payback = the name of someone you had
-- killed who was there when you died.
local function endHunt(reason, payback)
  local h = hunt
  if not h then
    -- stopped by hand with no hunt on: a fight's music stops too
    if reason ~= "quiet" and reason ~= "died" then fight = nil settle() end
    return
  end
  hunt = nil
  lastIds, lastEnd = h.ids, GetTime()
  -- a hunt that runs out while you are still fighting leaves the music to the fight; any other end takes it
  -- (a death in a battleground leaves it too: you are back in a minute)
  if reason ~= "quiet" and not (reason == "died" and fight and inBattleground()) then fight = nil end
  settle()
  if ns.Stage then pcall(ns.Stage.FuseOut) end
  local grade, gradeColor
  if h.kills >= CARD_FROM then grade, gradeColor = gradeFor(h) end
  local stamp = grade and { grade = grade, gradeColor = gradeColor, size = h.kills >= 10 and 4 or 3, hold = 5.5, onStamp = function() sfx("stamp") end } or nil
  if reason == "died" and h.kills >= 2 then
    hush()
    local lines = { { pick("shut_down"), 3, nil, "powerdown" } }
    if payback and opts().moments then lines[2] = { pick("payback"), 1 } end
    speak(lines)
    showBanner("SHUT DOWN", GREY, (stamp and cardLine(h) or ("Your hunt ended at %d kills."):format(h.kills)) .. (payback and ("    |cffbbbbbb" .. payback .. " got even|r") or ""),
      stamp or { size = 2 })
  elseif reason == "quiet" then
    local flawless = h.kills >= FLAWLESS_FROM
    if h.kills >= 2 and not Hype.Speaking() then
      speak({ { flawless and pick("flawless") or pick("hunt_over"), flawless and 2 or 1, nil, "gong" } })
    end
    if stamp then
      -- a breath in before the stamp comes down
      stamp.stampAfter = 1.1
      sfx("riser")
      showBanner(flawless and "FLAWLESS HUNT" or "HUNT OVER", flawless and GOLD or gradeColor, cardLine(h), stamp)
    end
  else
    hush()
  end
  if h.kills >= 2 and (reason == "died" or reason == "quiet") then recap(h) end
  if grade and (grade == "S" or grade == "S+") and (reason == "died" or reason == "quiet") then photo(1.6) end
  if reason == "died" or reason == "quiet" then clipMark(h, reason, grade, stamp and 7.5 or 3) end
  local best = GodslayerDB.opts.hype.best or 0
  if h.kills > best and not h.pretend then GodslayerDB.opts.hype.best = h.kills end
end
Hype.End = endHunt

local function arm(h)
  h.turn = (h.turn or 0) + 1
  local turn, window = h.turn, opts().window
  local rung = rungFor(h.kills)
  if ns.Stage and opts().fuse then pcall(ns.Stage.Fuse, window, h.kills, rung[2], rung[4]) end
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
local tellGuild            -- below, with the guild's side of things
-- the announcer has something to say, or is about to
function Hype.Busy() return Hype.Speaking() or next(waiting) ~= nil end
local barked = false       -- the last kill between rungs got a word

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

-- MOMENTS -------------------------------------------------------------------------
-- A kill that is more than a number. One per kill at most, the most particular one that fits:
-- the words on the banner, the line said after the call, and a sound under it.
local MOMENTS = {
  revenge = { tag = "REVENGE", clip = "revenge", sfx = "sting", size = 3 },
  dominate = { tag = "DOMINATION", clip = "dominate", sfx = "sting", size = 3 },
  shame = { clip = "shame", sfx = "trombone" },
  giant = { tag = "GIANT SLAYER", clip = "giant", size = 3 },
  clutch = { tag = "CLOSE CALL", clip = "clutch" },
  outnumbered = { tag = "OUTNUMBERED", clip = "outnumbered", size = 3 },
  comeback = { tag = "COMEBACK", clip = "comeback" },
}
Hype.MOMENTS = MOMENTS
local faced = {}           -- id -> { kills = on them since they last got you, t = when }
local facedCount = 0
local grudges = {}         -- id -> when they (as far as anyone can tell) killed you
local deathsSinceKill, lastOdds, forced = 0, -1000, nil

local function probe(what, result)
  GodslayerDB.probe = GodslayerDB.probe or {}
  GodslayerDB.probe[what] = result
end

-- id is nil for a kill nobody saw die and a test id for a pretend one: those have no history.
-- identityOnly: the kill was already called and has only now got its name, so only what
-- depends on who it was is looked at.
local function momentFor(id, h, identityOnly)
  if forced then
    local m = forced
    forced = nil
    return m
  end
  local o = opts()
  local now = GetTime()
  -- a pretend kill is a preview: it finds nothing and uses nothing up
  if type(id) == "string" and id:sub(1, 5) == "test#" then return nil end
  local real = type(id) == "string" and id:sub(1, 5) ~= "anon:"
  local found
  -- the spell that ended it belongs to this kill whatever else it was, so it cannot spill onto the next
  local finisher
  if not identityOnly and ns.Fight and ns.Fight.Finisher then
    local key, tag = ns.Fight.Finisher(h.kb, id)
    if key and o.finishers then finisher = { tag = tag, clip = "fin_" .. key, size = 3, finisher = key } end
  end
  if real then
    local f = faced[id]
    if not f then
      if facedCount > 600 then faced, facedCount = {}, 0 end
      f = { kills = 0 }
      faced[id], facedCount = f, facedCount + 1
    end
    f.kills, f.t = f.kills + 1, now
    if grudges[id] then
      if now - grudges[id] <= GRUDGE then found = MOMENTS.revenge end
      grudges[id] = nil
    end
    if not found and f.kills == DOMINATE then found = MOMENTS.dominate end
    local info = ns.VictimInfo and ns.VictimInfo(id) or {}
    if not found and info.level and info.myLevel then
      if info.myLevel - info.level >= SHAME_LEVELS then found = MOMENTS.shame
      elseif info.level - info.myLevel >= GIANT_LEVELS then found = MOMENTS.giant end
    end
    h.victimClass = info.class
  end
  if identityOnly then return o.moments and found or nil end
  if not found then
    -- by a thread: only where the client lets an addon read your own health
    local hp, max = try(UnitHealth, "player"), try(UnitHealthMax, "player")
    if issecret(hp) or issecret(max) then
      probe("health", "hidden")
    elseif type(hp) == "number" and type(max) == "number" and max > 0 then
      probe("health", "readable")
      if hp > 0 and hp / max < 0.2 then found = MOMENTS.clutch end
    end
  end
  if not found and ns.Odds and now - lastOdds >= ODDS_GAP then
    local enemies, alone = ns.Odds()
    -- the one just killed may still be standing on the screen: more than that many besides
    if alone and enemies >= ODDS_ENEMIES then found, lastOdds = MOMENTS.outnumbered, now end
  end
  if not found and deathsSinceKill >= 2 then found = MOMENTS.comeback end
  deathsSinceKill = 0
  -- the spell that ended it: EXECUTED, PYROBLASTED, DEATH BY WAND; above a word about their class
  if not found then found = finisher end
  if not found and real and h.victimClass and not h.quipped[h.victimClass] and math.random() < QUIP_CHANCE then
    local clip = "class_" .. h.victimClass:lower()
    if clipLength(clip) then
      h.quipped[h.victimClass] = true
      found = { clip = clip }
    end
  end
  -- the history above is kept either way; finishers have a switch of their own
  if not o.moments then return finisher end
  return found
end

-- the line a moment adds after the call, or nil when this announcer has no such line
local function momentLine(m)
  if not m then return nil end
  local clip = pick(m.clip)
  if not clip then return nil end
  return { clip, m.tag and 2 or 1, nil, m.sfx }
end

-- The lines for one Olympus kill, in the order they are spoken.
local function olympusLines(o)
  local lines = {}
  local info, v = o.info or {}, o.v or {}
  local ladder = sacrilege(info.streak or 1)
  if info.king then lines[1] = { pick("regicide"), 3, nil, "drop" }
  elseif ladder then lines[1] = { pick(ladder[2]), 3, nil, ladder[1] >= 5 and "drop" or nil }
  else lines[1] = { pick(o.tier == "original" and "olympus" or "god_down"), 3 } end
  lines[2] = { pick(o.pts >= 5 and "plus_five" or "plus_one"), 2 }
  local roll = math.random()
  local moment = momentLine(o.moment)
  local titled = info.rankUp and o.rankIndex and clipLength("title_" .. o.rankIndex)
  if titled and not (moment and o.moment.tag) then
    -- a new title is the remark: the call, the points, the title, and no more than that
  elseif moment then
    -- a kill that means something more: that is the remark
    lines[#lines + 1] = moment
  elseif not opts().asides then
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
  if multi and multi[1] >= 3 and (run or 1) <= MULTI[#MULTI][1] then
    for i = #lines, 1, -1 do if lines[i][2] < 2 then table.remove(lines, i) end end
    table.insert(lines, 1, { pick(multi[3]), 3 })
  else
    multi = multi and multi[1] >= 3 and multi or nil
  end
  if record then lines[#lines + 1] = { pick("record"), 2 } end
  speak(lines)
  if top.info.king or (multi and multi[1] >= 3) or (ladder and ladder[1] >= 5) or record then roar() end
  local title = top.info.king and "REGICIDE" or (ladder and ladder[3]) or (top.tier == "original" and "OLYMPUS BLEEDS" or "OLYMPIAN DOWN")
  local name = top.v and top.v.name
  local parts = { (name or "An Olympian") .. (#gods > 1 and (" and " .. (#gods - 1) .. " more") or ""), "|cffffd100+" .. points .. "|r" }
  local progress = progressLine()
  if top.moment and top.moment.tag then parts[#parts + 1] = "|cffff4040" .. top.moment.tag .. "|r" end
  if promoted then parts[#parts + 1] = "|cffff7d0aNew title: " .. promoted.info.rankUp .. "|r"
  elseif progress then parts[#parts + 1] = "|cffbbbbbb" .. progress .. "|r" end
  if multi and huntKills then parts[#parts + 1] = "|cffff7d0a" .. multi[2] .. "|r" end
  if huntKills and huntKills > 1 then parts[#parts + 1] = "|cffffd100x" .. huntKills .. "|r" end
  local size = top.info.king and 5 or ((ladder and ladder[1] >= 5) and 4 or ((ladder or top.tier == "original" or promoted) and 3 or 2))
  showBanner(title, top.tier == "original" and GOLD or GODRED, table.concat(parts, "    "), { size = size, claws = huntKills and run or nil })
  if top.info.king then photo() tellGuild("regicide", hunt or {}) end
  if top.info.king and hunt then hunt.king = true end
end

local function flush()
  flushQueued = false
  local batch = waiting
  waiting = {}
  -- switched off while a kill was waiting to be called; a preview is heard even when it is off
  if not opts().on and not (hunt and hunt.pretend) then return end
  local generic, gods, run, record, reached, multiNew, moment = nil, {}, 1, false, nil, nil, nil
  for _, w in pairs(batch) do
    if w.olympus then
      w.olympus.moment = w.moment
      gods[#gods + 1] = w.olympus
    elseif not generic or w.kills > generic.kills then
      generic = w
    end
    if (w.run or 1) > run then run = w.run end
    record = record or w.record
    -- several kills in one breath: the highest rung any of them reached is the one to call
    if w.reached and (not reached or w.reached[1] > reached[1]) then reached = w.reached end
    if w.multiNew and (not multiNew or w.multiNew[1] > multiNew[1]) then multiNew = w.multiNew end
    if w.moment and (not moment or (w.moment.tag and not moment.tag)) then moment = w.moment end
  end
  if #gods > 0 then
    announceGods(gods, hunt and hunt.kills, run, record)
  elseif generic then
    -- DOUBLE KILL, then the rung; the rung gives way if the next kill arrives before it is said
    local lines = {}
    if multiNew then lines[#lines + 1] = { pick(multiNew[3]), 3, nil, multiNew[1] >= 5 and "drop" or nil } end
    -- a small rung reached in the same breath as a run is on the banner and left unsaid: one call, not two.
    -- From GODLIKE up the rung is worth hearing as well.
    if reached and (not multiNew or reached[5] >= 3) then
      lines[#lines + 1] = { pick(reached[3]), multiNew and 1.5 or 3, nil, (not multiNew and reached[5] >= 4) and "drop" or nil }
    end
    local said = momentLine(moment)
    if said then
      lines[#lines + 1] = said
    elseif #lines == 0 and opts().barks and not barked and math.random() < BARK_CHANCE then
      -- between rungs: a word now and then, never two kills running, and silence the rest of the time
      lines[1] = { pick("more"), 1.2 }
      barked = true
    else
      barked = false
    end
    if record then lines[#lines + 1] = { pick("record"), 2 } end
    if #lines > 0 then speak(lines) end
    if (multiNew and multiNew[1] >= 3) or record or (reached and reached[5] >= 3) then roar() end
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
    hunt = { kills = 0, run = 0, bestRun = 1, points = 0, started = now, ids = {}, quipped = {} }
    -- already playing when the fight started: the song carries on and is not begun again
    holdMusic()
  end
  local h = hunt
  if pretend then h.pretend = true end -- a hunt with a test kill in it is never a record
  h.kills = h.kills + 1
  h.run = (o.multi and h.last and now - h.last <= MULTI_WINDOW) and h.run + 1 or 1
  h.last = now
  if h.run > h.bestRun then h.bestRun = h.run end
  -- heard the instant it happens: the same blade, a note higher every kill
  sfx("kill_" .. math.min(h.kills, KILL_NOTES))
  arm(h)
  if h.kills >= PHASE_TWO then phaseTwo() end
  local rung, nextRung = rungFor(h.kills)
  local reached = rung[1] == h.kills and rung or nil
  -- a run is called as it grows, up to RAMPAGE; a longer one is on the banner and not in your ear again
  local multi = multiFor(h.run)
  local multiNew = multi and h.run <= MULTI[#MULTI][1] and multi or nil
  h.kb = killingBlow
  local moment = momentFor(id, h)
  local name = type(who) == "string" and who ~= "" and who or nil
  local parts = { name and (name .. " is dead") or "A kill" }
  if moment and moment.tag then parts[#parts + 1] = "|cffff4040" .. moment.tag .. "|r" end
  local big = multiNew and multiNew[1] >= 4 -- a quad kill or a rampage takes the banner from the rung
  local title, size
  if big then
    title, size = multiNew[2], multiNew[1] >= 5 and 4 or 3
    parts[#parts + 1] = "|cffff7d0a" .. rung[2] .. "|r"
  elseif reached then
    title, size = rung[2], rung[5]
    if multi then parts[#parts + 1] = "|cffff7d0a" .. multi[2] .. "|r" end
  elseif multiNew then
    title, size = multiNew[2], multiNew[1] >= 3 and 3 or 2
  else
    -- between rungs: the count, and how far the next rung is
    title, size = h.kills .. " KILLS", 1
    if multi then parts[#parts + 1] = "|cffff7d0a" .. multi[2] .. "|r" end
  end
  if h.kills > 1 and (reached or big or multiNew) then parts[#parts + 1] = "|cffffd100x" .. h.kills .. "|r" end
  if nextRung and not reached then
    parts[#parts + 1] = ("|cffbbbbbb%d more: %s|r"):format(nextRung[1] - h.kills, nextRung[2])
  end
  if moment and moment.size and moment.size > size then size = moment.size end
  showBanner(title, rung[4], table.concat(parts, "    "), { size = size, claws = h.run })
  if reached and reached[1] == 15 then photo() end
  -- the guild hears about the big ones, once a hunt, and the biggest when two land on one kill
  if reached and reached[1] == 15 then tellGuild("godslayer", h)
  elseif multiNew and multiNew[1] == MULTI[#MULTI][1] then tellGuild("rampage", h)
  elseif reached and reached[1] == 5 then tellGuild("godlike", h) end
  -- the moment a recorder should cut to: the kill that topped the best run, or with no run the last rung
  if (h.run >= 2 and h.run == h.bestRun) or (h.bestRun == 1 and reached) then h.peak = now end
  local key = id or (name or "?") .. "#" .. h.kills
  h.ids[key], h.lastKey = true, key
  local w = waiting[key] or {}
  w.kills, w.who, w.run, w.reached, w.multiNew, w.moment = h.kills, name, h.run, reached, multiNew, moment
  -- past your best hunt: said once, at the kill that does it
  local best = o.best or 0
  if not h.pretend and not h.record and best >= RECORD_FROM and h.kills > best then h.record, w.record = true, true end
  waiting[key] = w
  queueFlush()
end

-- A kill that was called before anyone knew whose it was now has a name: the hunt remembers it
-- under that name, so its Olympus points and its history land where they belong. True when the
-- kill was one of ours.
function Hype.Named(calledAs, id, name)
  if not GodslayerDB or type(calledAs) ~= "string" or type(id) ~= "string" then return false end
  local h = hunt
  if not (h and h.ids[calledAs]) then
    -- called in a hunt that has since ended (you died, or it was stopped): still that kill, and not a new one
    if lastIds[calledAs] and GetTime() - lastEnd <= 10 then
      lastIds[calledAs] = nil
      return true
    end
    return false
  end
  h.ids[calledAs], h.ids[id] = nil, true
  -- the banner may still be showing this kill without a name
  if h.lastKey == calledAs then
    h.lastKey = id
    if type(name) == "string" and name ~= "" and ns.Stage and ns.Stage.Reline then pcall(ns.Stage.Reline, "A kill", name .. " is dead") end
  end
  local w = waiting[calledAs]
  if w then
    waiting[calledAs] = nil
    w.who = type(name) == "string" and name or w.who
    waiting[id] = w
  end
  -- the history is kept; a moment found this late is said on its own, if the call has gone out
  local hadForced = forced
  forced = nil
  local moment = momentFor(id, h, true)
  forced = hadForced
  if moment and moment.tag then
    if w then
      w.moment = w.moment or moment
    elseif not Hype.Speaking() and h.lastKey == id then
      local said = momentLine(moment)
      if said then speak({ said }) end
      showBanner(moment.tag, GODRED, (type(name) == "string" and name or "They") .. " had it coming", { size = 2 })
    end
  end
  return true
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
  deathsSinceKill = deathsSinceKill + 1
  -- who did it, as far as anyone can tell: they are owed, and whatever you had over them is gone
  local payback
  local now = GetTime()
  for id, when in pairs(grudges) do
    if now - when > GRUDGE then grudges[id] = nil end
  end
  for _, s in ipairs(ns.Suspects and ns.Suspects() or {}) do
    grudges[s.id] = now
    local f = faced[s.id]
    if f then
      if f.kills > 0 and f.t and now - f.t <= 180 then payback = payback or s.name end
      f.kills = 0
    end
  end
  -- in a battleground you are back in a minute: the song waits for you, the hunt does not
  if not inBattleground() then fight = nil end
  endHunt("died", payback)
  if fight then Hype.Disengage() end
  settle() -- a fight lost with no kill in it: the music goes with you
end

-- THE FIGHT -------------------------------------------------------------------------
-- Fight.lua says when a fight with a player has started. The song starts there and then, so the
-- first kill lands on music that is already going. info = { name, guild, tier, king } as far as
-- the client lets anyone know who it is.
local lastEngageVoice, lastEngageGod, lastEngageShow, lastDrums = -1000, -1000, -1000, -1000
local ENGAGE_VOICE_DELAY = 0.7
function Hype.DrumsAgo() return GetTime() - lastDrums end
local hushed = false -- stopped by hand mid-combat: no fight music again until combat is over
function Hype.Engage(info, pretend)
  if not GodslayerDB then return false end
  local o = opts()
  if not (o.on and o.engage) and not pretend then return false end
  if hushed and not pretend then return false end
  info = type(info) == "table" and info or {}
  local now = GetTime()
  local fresh = not fight
  fight = fight or { started = now, turn = 0 }
  fight.turn = fight.turn + 1 -- whatever was counting down to letting the music go is called off
  local god = info.tier ~= nil and not fight.god
  -- the fight goes on: only an Olympian joining it is news
  if not fresh and not god then return true end
  if god then fight.god = true end
  if hunt and not hunt.pretend and not pretend then return true end -- a hunt is on: it has the music and the voice already
  local before = track
  holdMusic()
  if (not before and track) or pretend then
    sfx("engage")
    lastDrums = now
  end
  local line
  if god and (now - lastEngageGod >= ENGAGE_GOD_GAP or pretend) then
    lastEngageGod, lastEngageVoice = now, now
    line = info.king and "king_spot" or "engage_god"
  elseif not god and fresh and (now - lastEngageVoice >= ENGAGE_VOICE_GAP or pretend) then
    lastEngageVoice = now
    line = "engage"
  end
  if line then
    -- a breath after the drums, and not at all if a kill got there first or the fight is already gone
    local gen, f = engageGen, fight
    C_Timer.After(ENGAGE_VOICE_DELAY, function()
      if gen ~= engageGen or (not pretend and fight ~= f) then return end
      -- an Olympian's line waits for the one in the air; a plain fight's word is let go
      if (hunt and not hunt.pretend and not pretend) or next(waiting) or (line == "engage" and Hype.Speaking()) then return end
      if not voiceNow and ns.VOICE then currentPack() end
      local king = line == "king_spot"
      speak({ { pick(line), king and 3 or 1.3, nil, nil, nil, not king } })
    end)
  end
  if (fresh or god) and (now - lastEngageShow >= ENGAGE_SHOW_GAP or god or pretend) then
    lastEngageShow = now
    local who = type(info.name) == "string" and info.name or nil
    local line = (who or "An enemy player") .. (type(info.guild) == "string" and ("    |cffbbbbbb<" .. info.guild .. ">|r") or "")
    showBanner(info.king and "THE KING" or (god and "OLYMPIAN ENGAGED" or "ENGAGED"), god and GODRED or { 1, 0.55, 0.15 }, line, { size = god and 2 or 1, hold = 1.8 })
  end
  return true
end

-- Out of combat. The music waits a little in case the fight is not over, then goes, unless a
-- hunt is holding it.
function Hype.Disengage()
  hushed = false
  local f = fight
  if not f then return end
  local turn = f.turn
  C_Timer.After(inBattleground() and GRACE_BG or GRACE, function()
    if fight ~= f or f.turn ~= turn then return end
    if ns.Fight and ns.Fight.InCombat and ns.Fight.InCombat() then
      -- still in combat, but no longer with a player as far as anyone can see: check again later
      Hype.Disengage()
      return
    end
    fight = nil
    settle()
  end)
end

function Hype.Fighting() return fight ~= nil end

-- A new zone. A fight kept alive through a battleground death does not follow you out of it.
function Hype.handlers.PLAYER_ENTERING_WORLD()
  if fight and not hunt and not inBattleground() and not (ns.Fight and ns.Fight.InCombat and ns.Fight.InCombat()) then
    fight = nil
    settle()
  end
end
function Hype.InPvP() return fight ~= nil or hunt ~= nil end
function Hype.Playing() return track ~= nil end

-- A guildmate somewhere else just reached a big moment of their own: Dota's word for the whole
-- server. A line in chat, and the announcer says it when you are not busy with your own fight.
local STREAKS = {
  godlike = { "is |cffff4019GODLIKE|r", "ally_godlike" }, rampage = { "is on a |cffff7d0aRAMPAGE|r", "ally_rampage" },
  godslayer = { "has become a |cffb35aff GODSLAYER|r", "ally_godslayer" }, regicide = { "has |cffff3010killed the King of Olympus|r", "ally_regicide" },
}
Hype.STREAKS = STREAKS
local streakLog, lastStreakVoice, streakHeard = {}, -1000, {}
local STREAK_SENDER_GAP, STREAK_SENDER_HOURLY, STREAK_VOICE_GAP, STREAK_KINGS_HOURLY, STREAK_PER_MINUTE = 60, 10, 30, 3, 6
function Hype.AllyStreak(who, kind, pretend)
  if not GodslayerDB or type(who) ~= "string" or not STREAKS[kind] then return false end
  local o = opts()
  if not (o.on and o.guild and o.streaks) and not pretend then return false end
  local now, log = GetTime(), streakLog[who]
  if not log then log = {} streakLog[who] = log end
  while log[1] and now - log[1].t > 3600 do table.remove(log, 1) end
  -- the King is news even right after another call, a few times an hour at most; anything else from one guildmate is rationed
  if kind == "regicide" then
    local kings = 0
    for _, entry in ipairs(log) do if entry.king then kings = kings + 1 end end
    if kings >= STREAK_KINGS_HOURLY then return false end
  elseif #log >= STREAK_SENDER_HOURLY or (log[#log] and now - log[#log].t < STREAK_SENDER_GAP) then
    return false
  end
  -- and the whole guild together is held to a handful a minute
  while streakHeard[1] and now - streakHeard[1] > 60 do table.remove(streakHeard, 1) end
  if #streakHeard >= STREAK_PER_MINUTE then return false end
  streakHeard[#streakHeard + 1] = now
  log[#log + 1] = { t = now, king = kind == "regicide" or nil }
  ns.Print(("|cffffd100%s|r %s."):format(who, STREAKS[kind][1]))
  if not pretend then
    -- your own fight first; the King waits for a line in progress, anything else is let go
    if (hunt and not hunt.pretend) or fight or next(waiting) then return true end
    if kind ~= "regicide" and (Hype.Speaking() or now - lastStreakVoice < STREAK_VOICE_GAP) then return true end
  end
  lastStreakVoice = now
  if not voiceNow and ns.VOICE then currentPack() end
  speak({ { pick(STREAKS[kind][2]), kind == "regicide" and 2 or 1.2, nil, "ally", nil, true } })
  return true
end

-- Our own big moment, told to the guild once. Never a test, never from a preview.
tellGuild = function(kind, h)
  if not h or h.pretend or not (opts().streaks and ns.Comm and ns.Comm.Streak) then return end
  h.told = h.told or {}
  if h.told[kind] then return end
  h.told[kind] = true
  pcall(ns.Comm.Streak, kind)
end

-- DENIED. Your interrupt went out and their cast stopped in the same breath.
local INTERRUPTS = { Counterspell = true, Kick = true, Pummel = true, ["Shield Bash"] = true, ["Earth Shock"] = true, ["Spell Lock"] = true, Silence = true }
local lastKick, lastDeny, lastDenyVoice = -1000, -1000, -1000

function Hype.Denied(who)
  local o = opts()
  if not (o.on and o.deny) then return false end
  local now = GetTime()
  if now - lastDeny < 1 then return false end -- one cast, seen through several unit names
  lastDeny = now
  if hunt then hunt.denies = (hunt.denies or 0) + 1 end
  sfx("deny")
  -- never over a kill's banner, and the word only now and then
  if not (hunt and hunt.last and now - hunt.last < 2.5) then
    showBanner("DENIED", { 0.45, 0.8, 1 }, type(who) == "string" and (who .. " was saying something") or "Spell interrupted", { size = 1, hold = 1.6 })
  end
  if not Hype.Speaking() and not next(waiting) and now - lastDenyVoice >= DENY_VOICE_GAP then
    lastDenyVoice = now
    if not voiceNow and ns.VOICE then currentPack() end
    speak({ { pick("denied"), 1.2 } })
  end
  return true
end

function Hype.handlers.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if plain(unit) ~= "player" then return end
  local name = plain(try(C_Spell and C_Spell.GetSpellName, plain(spellID)))
  if type(name) == "string" and INTERRUPTS[name] then lastKick = GetTime() end
end

function Hype.handlers.UNIT_SPELLCAST_INTERRUPTED(unit)
  unit = plain(unit)
  -- the one you interrupted is the one you were aiming at: a stranger's cast stopping nearby is not yours
  if (unit ~= "target" and unit ~= "focus") or GetTime() - lastKick > DENY_WINDOW then return end
  if not (plain(try(UnitIsPlayer, unit)) and plain(try(UnitCanAttack, "player", unit)) == true) then return end
  Hype.Denied(ns.FullName and ns.FullName(unit) or nil)
end

-- DUELS. The game says who beat whom in a line of yellow text; its own wording says where the
-- names are.
local duelPatterns
local function duelPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local order = {}
  local body = fmt:gsub("%%(%d?)%$?s", function(n)
    order[#order + 1] = tonumber(n) or (#order + 1)
    return "\1"
  end)
  if #order ~= 2 then return nil end
  body = body:gsub("[%^%$%(%)%.%[%]%*%+%-%?%%]", "%%%0"):gsub("\1", "(.-)")
  return { "^" .. body .. "$", order[1] == 1 and 1 or 2 } -- which capture is the winner (the first argument)
end

function Hype.Duel(won, other)
  local o = opts()
  if not (o.on and o.duels) then return end
  if not voiceNow and ns.VOICE then currentPack() end
  local name = type(other) == "string" and other ~= "" and other or "your opponent"
  if won then
    speak({ { pick("duel_win"), 2, nil, "fanfare" } })
    showBanner("DUEL WON", GOLD, name .. " yields", { size = 2 })
  else
    speak({ { pick("duel_loss"), 1 } })
    showBanner("DUEL LOST", GREY, name .. " takes it", { size = 1 })
  end
end

function Hype.handlers.CHAT_MSG_SYSTEM(text)
  text = plain(text)
  if type(text) ~= "string" or not text:find("duel", 1, true) then return end
  if not duelPatterns then
    duelPatterns = {}
    for _, global in ipairs({ "DUEL_WINNER_KNOCKOUT", "DUEL_WINNER_RETREAT" }) do
      duelPatterns[#duelPatterns + 1] = duelPattern(_G[global])
    end
    if #duelPatterns == 0 then duelPatterns = { { "^(.-) has defeated (.-) in a duel%.?$", 1 }, { "^(.-) has fled from (.-) in a duel%.?$", 2 } } end
  end
  local me = ns.FullName and ns.FullName("player")
  if type(me) ~= "string" then return end
  local first = me:match("^(%S+)")
  local function mine(n) return n == me or n == first end
  for _, p in ipairs(duelPatterns) do
    local a, b = text:match(p[1])
    if a and b then
      local winner, loser = a, b
      if p[2] == 2 then winner, loser = b, a end
      if mine(winner) then Hype.Duel(true, loser) elseif mine(loser) then Hype.Duel(false, winner) end
      return
    end
  end
end

-- Logging in: if the game was closed while the music was stepped back, put it where it was.
function Hype.Login()
  local o = opts()
  if o.duckFrom then
    pcall(SetCVar, "Sound_MusicVolume", o.duckFrom)
    o.duckFrom = nil
  end
  -- the interface was reloaded with our song playing: nothing holds it now, so the zone gets its music back
  if o.playing then
    o.playing = nil
    try(StopMusic)
  end
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
  -- never over a kill being called, not in the seconds after one, and not in a fight: that has its own call
  if fight or Hype.Speaking() or next(waiting) or (hunt and hunt.last and now - hunt.last < 10) then return false end
  if spottedCount > 400 then spotted, spottedCount = {}, 0 end
  if not spotted[id] then spottedCount = spottedCount + 1 end
  spotted[id], lastSpot = now, now
  sfx("horn")
  speak({ { pick(king and "king_spot" or "spot"), king and 3 or 1 } })
  showBanner(king and "THE KING IS HERE" or "OLYMPIAN SIGHTED", king and GODRED or GOLD,
    (type(name) == "string" and name or "An Olympian") .. (type(guild) == "string" and ("    |cffbbbbbb<" .. guild .. ">|r") or ""), { size = king and 4 or 2 })
  return true
end

-- COMMANDS ------------------------------------------------------------------------
local function say(msg) ns.Print(msg) end

local SWITCHES = {
  voice = "Announcer", music = "Kill song", guild = "Guild kill calls", sfx = "Sound effects", spot = "Olympian spotter",
  theme = "Hunt theme when you have no song of your own", multi = "Double, triple and rampage calls", asides = "Remarks after an Olympus kill",
  fx = "Banner light and motion", fuse = "The fuse under the banner", moments = "Revenge, domination and the other moments",
  barks = "A word on kills between rungs", duck = "Music steps back while the announcer speaks", deny = "DENIED on a spell you interrupt",
  duels = "Duel results", photo = "A screenshot of your biggest moments", clip = "A mark for your recorder when a hunt ends",
  engage = "Your song starts the moment a fight with a player does", class = "Sounds for your own class's big spells in a fight",
  finishers = "EXECUTED, PYROBLASTED and the other finishers", wheel = "Hearing your group's chat wheel lines",
  streaks = "Telling the guild your big moments, and hearing theirs",
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
    if not o.on then waiting = {} auditionTurn = auditionTurn + 1 fight = nil endHunt("off") settle() end
    hushed = false
    say("Kill song and announcer " .. (o.on and "on." or "off."))
  elseif SWITCHES[word] then
    if value == "on" or value == "off" then o[word] = value == "on" end
    if track and ((word == "music" and not o.music) or (word == "theme" and not o.theme and track.theme)) then dropMusic() end
    -- no music for fights any more: one with no hunt in it gives the music up now
    if word == "engage" and not o.engage then fight = nil settle() end
    if word == "voice" and not o.voice then hush() end
    if word == "duck" and not o.duck then unduck() end
    if (word == "fuse" or word == "fx") and not (o.fuse and o.fx) and ns.Stage then pcall(ns.Stage.FuseOut) end
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
  elseif word == "probe" then
    -- what this client lets an addon see, for anyone wondering why a moment never comes up
    local function state(v) if issecret(v) then return "hidden" end return v == nil and "nothing" or "readable" end
    local p = GodslayerDB.probe or {}
    say("What the game lets the announcer see right now:")
    print("  Your health: " .. state((try(UnitHealth, "player"))) .. " (CLOSE CALL needs it readable). Last seen in a fight: " .. tostring(p.health or "not yet") .. ".")
    print("  Who had you targeted when you died: " .. tostring(p.targeting or "not seen yet") .. " (hidden means REVENGE goes by who you were fighting).")
    local restricted = try(C_CombatLog and C_CombatLog.IsCombatLogRestricted)
    print("  Combat log: " .. (plain(restricted) == false and "open" or "closed to addons") .. ". Kills come from honor credit and killing blows.")
    print("  Music stepping back: " .. (duckBroken and "the game refused, so it is left alone" or (o.duck and "on" or "off")) .. ".")
    print("  Banner light: " .. ((ns.Stage and ns.Stage.Ready and ns.Stage.Ready()) and "working" or "plain words (the game refused the animations or the art)") .. ".")
  elseif word == "channel" then
    local channels = { master = "Master", dialog = "Dialog", sfx = "SFX" }
    if channels[value] then
      o.channel = channels[value]
      say("The announcer and its sounds now play on the " .. o.channel .. " channel, and follow that volume slider.")
    else
      say("Channel is " .. o.channel .. ". /godslayer hype channel master | dialog | sfx")
    end
  elseif word == "test" and (value:match("^sig") or value:match("^streak")) then
    -- previews that touch nothing: a sound of your class, a guildmate's big moment
    local what = value:match("^%S+%s+(.+)$")
    if value:match("^sig") then
      local spells = {}
      for spell in pairs(ns.Fight and ns.Fight.SIGNATURES or {}) do spells[#spells + 1] = spell end
      table.sort(spells)
      local found
      for _, spell in ipairs(spells) do if spell:lower() == what then found = spell end end
      if found then
        say(found .. (ns.Fight.Signature(found, true) and "." or ": the sound did not play (sound effects off, or the file is missing)."))
      else
        say("/godslayer hype test sig <spell>, one of: " .. table.concat(spells, ", "))
      end
    else
      local kinds = {}
      for kind in pairs(STREAKS) do kinds[#kinds + 1] = kind end
      table.sort(kinds)
      if STREAKS[what or ""] then
        local voice, heard = lastStreakVoice, streakHeard
        streakLog["Test Torchman"], streakHeard = nil, {}
        Hype.AllyStreak("Test Torchman", what, true)
        streakLog["Test Torchman"], lastStreakVoice, streakHeard = nil, voice, heard
      else
        say("/godslayer hype test streak " .. table.concat(kinds, " | "))
      end
    end
  elseif word == "test" and hunt and not hunt.pretend and value ~= "duel" and value ~= "duel lost" and value ~= "spot" and value ~= "king spot" then
    say("You are in a real hunt. Previews wait until it is over, so they cannot add to it or end it.")
  elseif word == "test" and value:match("^engage") then
    -- the fight starting, heard and seen; nothing is held afterwards
    if fight then say("You are in a fight. Previews wait until it is over.") return end
    local olympian = value:match("god") or value:match("olymp")
    local show, voice, god = lastEngageShow, lastEngageVoice, lastEngageGod
    Hype.Engage(olympian and { name = "Test Olympian", guild = "OLYMPUS", tier = "original" } or { name = "Test Dummy" }, true)
    lastEngageShow, lastEngageVoice, lastEngageGod = show, voice, god
    -- the song plays on as it would after a real fight, then lets go
    Hype.Disengage()
    say(("A fight starting. The song plays until %d seconds after it, as it would out of combat. /godslayer hype stop ends it now."):format(GRACE))
  elseif word == "test" and value:match("^finisher") then
    local key = value:match("^finisher%s+(%S+)$")
    local tag = key and ns.Fight and ns.Fight.TAGS[key]
    if tag then
      local before, mode = o.on, o.mode
      o.on, o.mode = true, "all"
      -- a pretend kill finds no history, so the finisher is handed to it
      forced = { tag = tag, clip = "fin_" .. key, size = 3, finisher = key }
      testKills = testKills + 1
      Hype.Kill("Test Dummy", true, "test#" .. testKills, true)
      o.on, o.mode = before, mode
    else
      local keys = {}
      for k in pairs(ns.Fight and ns.Fight.TAGS or {}) do keys[#keys + 1] = k end
      table.sort(keys)
      say("/godslayer hype test finisher " .. table.concat(keys, " | "))
    end
  elseif word == "test" and (value:match("^moment") or value == "duel" or value == "duel lost" or value == "denied" or value == "card") then
    -- previews: nothing is scored and nothing is remembered
    local before = o.on
    o.on = true
    local which = value:match("^moment%s+(%S+)$")
    if value == "duel" or value == "duel lost" then
      Hype.Duel(value == "duel", "Test Dummy")
    elseif value == "denied" then
      local deny, voice, count = lastDeny, lastDenyVoice, hunt and hunt.denies
      lastDeny, lastDenyVoice = -1000, -1000
      Hype.Denied("Test Dummy")
      lastDeny, lastDenyVoice = deny, voice
      if hunt then hunt.denies = count end
    elseif value == "card" then
      if hunt then endHunt("quiet") else say("Start a hunt first: /godslayer hype test a few times, then this ends it and grades it.") end
    elseif which and (MOMENTS[which] or which == "class") then
      forced = MOMENTS[which] or { clip = "class_mage" }
      testKills = testKills + 1
      Hype.Kill("Test Dummy", true, "test#" .. testKills, true)
    else
      local names = {}
      for name in pairs(MOMENTS) do names[#names + 1] = name end
      table.sort(names)
      say("/godslayer hype test moment " .. table.concat(names, " | ") .. " | class")
    end
    o.on = before
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
    if hunt and not track and o.music then
      print("  No song found. Put kill.mp3 in Interface\\AddOns\\GodslayerMusic and restart the game.")
    elseif hunt and track and track.theme then
      print("  That is the hunt theme. For a song of your own, put kill.mp3 in Interface\\AddOns\\GodslayerMusic and restart the game.")
    end
  elseif word == "stop" then
    waiting = {}
    auditionTurn = auditionTurn + 1
    -- still in combat, the fight would be found again a second later: it stays off until combat ends
    hushed = (ns.Fight and ns.Fight.InCombat and ns.Fight.InCombat()) and true or false
    fight = nil
    endHunt("stop")
    settle()
    say("Hunt ended.")
  else
    local pack = ns.VOICE and ns.VOICE[o.pack]
    local onOff = function(v) return v and "on" or "off" end
    say(("Kill song and announcer: %s. Song %s, announcer %s (%s), guild kill calls %s. A hunt lasts %d seconds past your last kill, counting %s. Best hunt: %d."):format(
      onOff(o.on), onOff(o.music), onOff(o.voice), o.pack == "mix" and "the mix" or (pack and pack.label or "none"), onOff(o.guild), o.window,
      o.mode == "blows" and "your killing blows only" or "every kill you get credit for", o.best or 0))
    print("  Rungs: " .. (function() local t = {} for _, r in ipairs(LADDER) do t[#t + 1] = r[1] .. " " .. r[2] end return table.concat(t, ", ") end)() .. ".")
    print(("  Moments %s (revenge, domination, giant slayer, outnumbered, comeback, class remarks), a word between rungs %s, DENIED on interrupts %s, duels %s."):format(
      onOff(o.moments), onOff(o.barks), onOff(o.deny), onOff(o.duels)))
    print(("  Banner light %s, fuse %s, music steps back under the voice %s, screenshots of big moments %s, channel %s."):format(
      onOff(o.fx), onOff(o.fuse), onOff(o.duck), onOff(o.photo), o.channel))
    print(("  Clip mark for a recorder %s. /godslayer clip marks one by hand."):format(onOff(o.clip)))
    print(("  Song starts with the fight %s, your class's sounds %s, finishers %s, guild big moments %s, groupmates' chat wheel %s."):format(
      onOff(o.engage), onOff(o.class), onOff(o.finishers), onOff(o.streaks), onOff(o.wheel)))
    print(("  Kills within %d seconds of each other: DOUBLE KILL, TRIPLE KILL, QUAD KILL, RAMPAGE (%s)."):format(MULTI_WINDOW, onOff(o.multi)))
    print("  Olympus kills have their own calls, and the points are read out. /godslayer hype test olympus plays one.")
    print(("  Sound effects %s, Olympian spotter %s, remarks %s, hunt theme %s."):format(onOff(o.sfx), onOff(o.spot), onOff(o.asides), onOff(o.theme)))
    print("  Your song: a file named kill.mp3 or kill.ogg in Interface\\AddOns\\GodslayerMusic. Restart the game after adding it.")
    print("  /godslayer hype pack | mix | audition [name] | say <line> | stop | on | off | window <seconds> | blows | all | channel <name> | probe")
    print("  /godslayer hype test [olympus | king | spot | king spot | moment <name> | duel | duel lost | denied | card | engage | engage god | finisher <kind> | sig <spell> | streak <kind>]")
    print("  /godslayer hype music | voice | guild | sfx | spot | multi | asides | theme | fx | fuse | moments | barks | duck | deny | duels | photo | clip | engage | class | finishers | streaks | wheel  on|off")
    print("  /godslayer wheel: the chat wheel. Bind a key to it in Key Bindings, AddOns, Godslayer.")
  end
end
