-- Offline tests for what 2.2 added: lua tests/v22.lua   (from the project root, Lua 5.1)
-- The song starting with the fight, who holds the music, your class's sounds, finishers, the
-- guild hearing your big moments, and the chat wheel.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", faction = "Horde", isMe = true })
local FILES = { "Data.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Fight.lua", "Comm.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local H, F, W, A = ns.Hype, ns.Fight, ns.Wheel, M.audio
local S = "Interface\\AddOns\\Godslayer\\Sounds\\"
for pack, v in pairs(ns.VOICE) do for clip in pairs(v.clips) do A.files[S .. pack .. "\\" .. clip .. ".ogg"] = true end end
for name in pairs(ns.SFX) do A.files[S .. "sfx\\" .. name .. ".ogg"] = true end
for name in pairs(ns.MUSIC) do A.files[S .. "music\\" .. name .. ".ogg"] = true end
for clip in pairs(ns.WHEEL and ns.WHEEL.clips or {}) do A.files[S .. "wheel\\" .. clip .. ".ogg"] = true end
local THEME = S .. "music\\hunt.ogg"
local function say(text) SlashCmdList["GODSLAYER"](text) end
H.Opts().pack = "titan"

local musicStarts = 0
local realPlayMusic = PlayMusic
PlayMusic = function(path) musicStarts = musicStarts + 1 return realPlayMusic(path) end

local function spoken()
  local names = {}
  for _, p in ipairs(A.played) do
    local clip = p.path:match("\\([%w_]+)%.ogg$")
    if clip and p.path:find("\\titan\\", 1, true) then names[#names + 1] = (clip:gsub("_%d+$", "")) end
  end
  return table.concat(names, ",")
end
local function effects()
  local names = {}
  for _, p in ipairs(A.played) do
    local name = p.path:match("\\sfx\\([%w_]+)%.ogg$")
    if name then names[#names + 1] = name end
  end
  return table.concat(names, ",")
end
local function title() return GodslayerHypeBanner and GodslayerHypeBanner.title.__text end
local function line() return GodslayerHypeBanner and GodslayerHypeBanner.line.__text or "" end
local function clearUnits()
  for token in pairs(M.units) do if token ~= "player" then M.units[token] = nil end end
end
local function reset()
  M.inCombat = false
  M.fire("PLAYER_REGEN_ENABLED") -- out of combat, as between real fights
  clearUnits()
  H.End("test") M.advance(200)
  A.played, A.stopped, A.music, A.musicStops = {}, {}, nil, 0
  musicStarts = 0
  M.groupSize = 0
  M.sentAddon = {}
end
local realRandom = math.random
local function quiet() math.random = function(n) if n then return 1 end return 0.99 end end
quiet()

-- an enemy player you are fighting
local function foe(token, extra)
  local u = { name = "Bad Guy", guid = "Player-1-0000BB01", class = "ROGUE", faction = "Alliance", combat = true }
  for k, v in pairs(extra or {}) do u[k] = v end
  return M.addUnit(token or "target", u)
end
local function hit() M.fire("UNIT_COMBAT", "player", "WOUND", "", 120, 1) end
local function engage(extra)
  foe("target", extra)
  M.inCombat = true
  hit()
  M.fire("PLAYER_REGEN_DISABLED")
end
local function leaveCombat()
  M.inCombat = false
  M.fire("PLAYER_REGEN_ENABLED")
end
local kid = 0
local function kill() kid = kid + 1 H.Kill("Victim " .. kid, true, "k" .. kid) M.advance(1) end
local function hear() M.advance(12) end -- every queued line said

-- 1. the song starts with the fight ------------------------------------------------------------
reset()
engage()
eq(A.music, THEME, "a fight with a player starts the song before anyone has died")
check(H.Fighting(), "and the fight is known")
check(effects():find("engage", 1, true), "war drums as it starts: " .. effects())
eq(title(), "ENGAGED", "a small banner says so") check(line():find("Bad Guy", 1, true), "with who it is: " .. line())
M.advance(2)
eq(spoken(), "engage", "the announcer says a word as the first fight starts")
kill()
eq(musicStarts, 1, "the first kill does not start the song again")
eq(A.music, THEME, "it carries on")
check(spoken():find("first_blood", 1, true), "FIRST BLOOD over the song already playing: " .. spoken())

-- 2. who holds the music --------------------------------------------------------------------
leaveCombat()
M.advance(20)
check(not H.Fighting() and H.Active(), "out of combat the fight is over, the hunt goes on")
eq(A.music, THEME, "and the hunt keeps the song")
M.advance(100)
check(not H.Active(), "the hunt runs out")
eq(A.music, nil, "and with no fight left the song stops") eq(A.musicStops, 1, "once")

reset()
engage()
leaveCombat()
M.advance(10)
eq(A.music, THEME, "a little while out of combat the song waits")
M.advance(6)
eq(A.music, nil, "a fight with no kill in it lets the song go after the grace") check(not H.Fighting(), "and is over")

reset()
engage()
leaveCombat()
M.advance(10)
M.inCombat = true
M.fire("PLAYER_REGEN_DISABLED")
M.advance(10)
eq(A.music, THEME, "back in the fight inside the grace: the song never stopped") eq(A.musicStops, 0, "not even for a moment")
eq(musicStarts, 1, "and was not begun again")

reset()
engage()
M.advance(3)
M.fire("PLAYER_DEAD")
eq(A.music, nil, "dying in a fight with no kill: the song goes with you") check(not H.Fighting(), "the fight is over")

reset()
engage()
kill()
M.advance(95)
check(not H.Active(), "a hunt that runs out while you are still fighting ends")
eq(A.music, THEME, "and leaves the song to the fight") eq(A.musicStops, 0, "never stopped")
leaveCombat()
M.advance(16)
eq(A.music, nil, "the fight ending takes it")

reset()
engage()
kill()
M.advance(2)
M.fire("PLAYER_DEAD")
eq(A.music, nil, "dying in a hunt stops the song even with the fight on") check(not H.Fighting(), "and ends the fight")

reset()
engage()
say("hype stop")
eq(A.music, nil, "hype stop with only a fight on stops the song") check(not H.Fighting(), "and the fight")
M.advance(5)
check(not H.Fighting() and A.music == nil, "and it stays stopped while you are still in combat")
leaveCombat()
M.advance(2)
engage()
check(H.Fighting() and A.music == THEME, "the next fight after combat ends has its song again")

reset()
engage()
say("hype engage off")
eq(A.music, nil, "switching fight music off lets a fight's song go at once")
leaveCombat() M.advance(20)
engage()
eq(A.music, nil, "and no fight starts it again") check(not H.Fighting(), "or is counted")
kill()
eq(A.music, THEME, "a kill still starts the song the old way")
say("hype engage on")

-- 3. what is and is not a fight ---------------------------------------------------------------
reset()
foe("target")
M.fire("PLAYER_TARGET_CHANGED")
check(not H.Fighting(), "targeting an enemy player out of combat is not a fight")
M.inCombat = true
M.units.target.combat = false
M.fire("PLAYER_REGEN_DISABLED")
M.advance(4)
check(not H.Fighting(), "in combat with an enemy player targeted who is not in combat themselves: not a fight")
M.units.target.combat = true
F.Check(true)
check(not H.Fighting(), "both in combat, but nothing has passed between you: they may be busy with a boar of their own")
M.units.target.combat = "secret"
hit()
F.Check(true)
check(not H.Fighting(), "a hit on you, and the client will not say whether they are in combat: not enough")
M.fire("PLAYER_ENTER_COMBAT")
check(H.Fighting(), "you swinging at them as well: a fight")
reset()
M.inCombat = true
M.addUnit("focus", { name = "Old Focus", guid = "Player-1-0000BB0F", faction = "Alliance", combat = true })
hit()
F.Check(true)
check(not H.Fighting(), "a focus set long ago, busy elsewhere, and a hit from something: not a fight")
reset()
M.inCombat = true
foe("target")
F.handlers.UNIT_COMBAT("player", "HEAL", "", 500, 1)
F.handlers.UNIT_COMBAT("player", "ENERGIZE", "", 50, 1)
F.handlers.UNIT_COMBAT("player", "SOMETHING_NEW", "", 50, 1)
F.Check(true)
check(not H.Fighting(), "a heal coming in, or a word UNIT_COMBAT never used to say, is not an attack")
F.handlers.UNIT_COMBAT("player", "DODGE", "", 0, 1)
F.Check(true)
check(H.Fighting(), "a dodged attack is one")
reset()
M.inCombat = true
foe("target")
M.fire("PLAYER_REGEN_DISABLED")
M.fire("PLAYER_ENTER_COMBAT")
check(H.Fighting(), "you start swinging at an enemy player who is fighting: a fight")
reset()
M.inCombat = true
foe("target")
M.spells = { [118] = "Polymorph" }
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 118)
check(H.Fighting(), "a spell of yours with an enemy player in your sights who is fighting: a fight")

reset()
M.inCombat = true
M.addUnit("target", { name = "Angry Boar", player = false, faction = "Alliance", combat = true })
foe("nameplate1")
M.secretTargets = true
M.fire("PLAYER_REGEN_DISABLED")
M.advance(4)
check(not H.Fighting(), "fighting a boar with an enemy player in view: not a fight")
F.handlers.UNIT_COMBAT("player", "WOUND", "", 120, 1)
M.advance(1.1)
check(not H.Fighting(), "and a hit taken while the boar is your target is the boar's")
M.addUnit("target", { name = "Friendly Pal", faction = "Horde", combat = true })
F.handlers.UNIT_COMBAT("player", "WOUND", "", 120, 1)
M.advance(1.1)
check(not H.Fighting(), "with a friend in your sights, a hit could be anything: not a fight")
M.units.target = nil
M.addUnit("softenemy", { name = "Soft Boar", player = false, faction = "Alliance", combat = true })
F.handlers.UNIT_COMBAT("player", "WOUND", "", 120, 1)
M.advance(1.1)
check(not H.Fighting(), "nor with a creature under your soft target")
M.units.softenemy = nil
M.units.target = nil
reset()
M.inCombat = true
foe("nameplate1")
M.secretTargets = true
F.handlers.UNIT_COMBAT("player", "WOUND", "", 120, 1)
M.advance(1.1)
check(H.Fighting(), "a hit with nothing targeted and an enemy player fighting in view: a fight")
M.secretTargets = false

reset()
M.inCombat = true
foe("nameplate3")
M.units["nameplate3target"] = M.units.player
M.fire("PLAYER_REGEN_DISABLED")
check(H.Fighting(), "an enemy player in view with you targeted, where the client says so: a fight")

reset()
M.inCombat = true
foe("softenemy")
hit()
M.fire("PLAYER_SOFT_ENEMY_CHANGED")
check(H.Fighting(), "the enemy your abilities would land on counts like a target")

reset()
M.inCombat = true
M.fire("PLAYER_REGEN_DISABLED")
M.advance(2)
foe("nameplate2")
M.units["nameplate2target"] = M.units.player
M.advance(1.1)
check(H.Fighting(), "someone walking up mid-combat is caught by the once-a-second look")

reset()
M.inCombat = true
foe("target", { dead = true })
M.fire("PLAYER_REGEN_DISABLED")
check(not H.Fighting(), "a dead enemy player is not a fight")

-- spells at a boar with an enemy player fighting somewhere in your focus: not a fight
reset()
M.inCombat = true
M.addUnit("focus", { name = "Busy Elsewhere", guid = "Player-1-0000BB10", faction = "Alliance", combat = true })
M.addUnit("target", { name = "Angry Boar", player = false, faction = "Alliance", combat = true })
M.spells = { [116] = "Frostbolt" }
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 116)
M.fire("PLAYER_ENTER_COMBAT")
hit()
M.advance(2)
check(not H.Fighting(), "spells and swings at a boar, a stale focus fighting elsewhere: not a fight")

-- 4. the announcer at the start of a fight -----------------------------------------------------
reset()
engage()
M.advance(2)
leaveCombat() M.advance(20)
A.played = {}
engage()
M.advance(2)
eq(spoken(), "", "a second fight soon after: the drums, no word") check(effects():find("engage", 1, true), "drums: " .. effects())
leaveCombat() M.advance(200)
A.played = {}
engage()
M.advance(2)
eq(spoken(), "engage", "three minutes on, a word again")

reset()
M.advance(70)
engage({ name = "Zeus Wannabe", guid = "Player-1-0000BB77", guild = "OLYMPUS XV" })
M.advance(2)
eq(title(), "OLYMPIAN ENGAGED", "an Olympian has a banner of their own")
check(line():find("OLYMPUS XV", 1, true), "with the guild: " .. line())
eq(spoken(), "engage_god", "and a word of their own")

reset()
M.advance(70)
engage()
M.advance(2)
A.played = {}
M.addUnit("focus", { name = "Hera Late", guid = "Player-1-0000BB09", guild = "OLYMPUS", faction = "Alliance", combat = true })
M.units.target = nil
M.units.focustarget = M.units.player
F.Check(true)
M.advance(2)
eq(spoken(), "engage_god", "an Olympian joining a fight already on, with you in their sights, is news")
reset()
M.advance(70)
M.inCombat = true
hit()
M.addUnit("target", { name = "Apollo Pal", guid = "Player-1-0000BB0C", guild = "OLYMPUS LXX", faction = "Alliance", combat = true })
M.fire("PLAYER_TARGET_CHANGED")
M.advance(4)
eq(spoken(), "engage_god", "targeting an Olympian mid-combat: the fight's call, not the spotter's")

reset()
engage()
kill()
A.played = {}
M.addUnit("target", { name = "Olympus Guy", guid = "Player-1-0000BB0A", guild = "OLYMPUS", faction = "Alliance", combat = true })
F.Check(true)
M.advance(1)
eq(spoken(), "", "during a hunt the fight starting says nothing: the hunt has the voice")

-- stopped, or dead, before the word came: it is not said
reset()
M.advance(400)
engage()
say("hype stop")
M.advance(2)
eq(spoken(), "", "hype stop right after a fight starts: no word about it afterwards")
reset()
M.advance(400)
engage()
M.fire("PLAYER_DEAD")
M.advance(2)
eq(spoken(), "", "nor after dying in that instant")
-- a battleground: the song waits through a death, and does not follow you out
reset()
local realInstance = IsInInstance
IsInInstance = function() return true, "pvp" end
engage()
kill()
M.fire("PLAYER_DEAD")
M.inCombat = false
M.advance(30)
eq(A.music, THEME, "in a battleground the song waits for you to run back")
M.advance(31)
eq(A.music, nil, "but not forever")
engage()
M.fire("PLAYER_DEAD")
M.inCombat = false
IsInInstance = function() return false, "none" end
M.fire("PLAYER_ENTERING_WORLD")
eq(A.music, nil, "leaving the battleground takes it with you")
IsInInstance = realInstance
kill() H.End("test") -- the deaths above would make the next kill a COMEBACK

-- 5. your class -------------------------------------------------------------------------------
M.spells = { [118] = "Polymorph", [642] = "Divine Shield", [1953] = "Blink", [5308] = "Execute", [11366] = "Pyroblast", [5019] = "Shoot", [116] = "Frostbolt" }
local function cast(id) M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-" .. id, id) end
reset()
cast(118)
eq(effects(), "", "a sheep out of a fight makes no sound")
M.addUnit("target", { name = "Angry Boar", player = false, faction = "Alliance", combat = true })
cast(118)
eq(effects(), "", "nor on a boar")
reset()
engage()
A.played = {}
cast(118)
eq(effects(), "", "the spell that started the fight does not talk over the war drums")
M.advance(2)
cast(118)
eq(effects(), "sig_sheep", "Polymorph in a fight with a player: the sheep")
M.advance(1.2)
cast(642)
eq(effects(), "sig_sheep,sig_bubble", "another spell has its own sound")
cast(1953)
eq(effects(), "sig_sheep,sig_bubble", "but not in the same second as the last")
M.advance(9)
cast(642)
eq(effects(), "sig_sheep,sig_bubble,sig_bubble", "a big cooldown again after a while")
M.advance(10)
cast(118)
eq(effects(), "sig_sheep,sig_bubble,sig_bubble", "a sheep cast all fight long is not heard every time")
M.advance(40)
cast(118)
eq(effects(), "sig_sheep,sig_bubble,sig_bubble,sig_sheep", "only once in a while")
say("hype class off")
A.played = {}
M.advance(10)
cast(642)
eq(effects(), "", "class sounds off: none")
say("hype class on")
reset()
foe("target")
cast(642)
eq(effects(), "sig_bubble", "targeting an enemy player counts as a fight for your class sounds")
local missing = {}
for spell, sound in pairs(F.SIGNATURES) do if not ns.SFX["sig_" .. sound] then missing[#missing + 1] = spell end end
eq(table.concat(missing, ","), "", "every class sound is in the build")
local noId = {}
for spell in pairs(F.SIGNATURES) do if not F.SPELL_IDS[spell] then noId[#noId + 1] = spell end end
for spell in pairs(F.FINISHERS) do if not F.SPELL_IDS[spell] then noId[#noId + 1] = spell end end
eq(table.concat(noId, ","), "", "every spell has an id for games in other languages")
-- a game in Portuguese
M.spells = { [118] = "Polimorfia", [642] = "Escudo Divino", [5308] = "Executar" }
F.Init()
reset()
foe("target")
cast(118)
eq(effects(), "sig_sheep", "Polimorfia is Polymorph")
M.spells = { [118] = "Polymorph", [642] = "Divine Shield", [1953] = "Blink", [5308] = "Execute", [11366] = "Pyroblast", [5019] = "Shoot", [116] = "Frostbolt" }

-- 6. finishers -----------------------------------------------------------------------------------
reset()
engage()
cast(5308)
M.advance(1)
kill()
hear()
eq(spoken(), "engage,first_blood,fin_execute", "Execute, then the kill: FIRST BLOOD, then EXECUTED")
check(line():find("EXECUTED", 1, true), "and it is on the banner: " .. line())
M.advance(13)
kill()
M.advance(3)
check(not spoken():find("fin_execute,.*fin_execute"), "a finisher is used up by the kill it named: " .. spoken())
-- a finisher aimed at one player does not name the death of another
reset()
engage()
cast(5308)
M.advance(0.5)
kid = kid + 1 H.Kill("Someone Else", true, "Player-1-0000CC01") hear()
check(not spoken():find("fin_execute", 1, true), "Execute on your target, someone else dies: not EXECUTED: " .. spoken())
reset()
engage()
cast(5308)
M.advance(0.5)
H.Kill("Bad Guy", true, "Player-1-0000BB01") hear()
check(spoken():find("fin_execute", 1, true), "the one you aimed it at: EXECUTED: " .. spoken())
reset()
say("hype moments off")
engage()
cast(5308) M.advance(0.5) kill() hear()
check(spoken():find("fin_execute", 1, true), "moments off leaves finishers to their own switch: " .. spoken())
say("hype moments on")
reset()
engage()
cast(11366)
M.advance(5)
kill()
M.advance(3)
check(not spoken():find("fin_", 1, true), "a spell long before the kill did not finish it: " .. spoken())
reset()
engage()
M.groupSize = 5
cast(5019)
M.advance(1)
kid = kid + 1 H.Kill("Victim " .. kid, false, "k" .. kid) M.advance(3)
check(not spoken():find("fin_", 1, true), "in a group, a credit that was not your blow is not your finisher: " .. spoken())
reset()
engage()
cast(5019)
M.advance(1)
kid = kid + 1 H.Kill("Victim " .. kid, false, "k" .. kid) hear()
check(spoken():find("fin_wand", 1, true), "alone, the credit right after your wand is your wand's: " .. spoken())
reset()
say("hype finishers off")
engage()
cast(5308) M.advance(1) kill() M.advance(3)
check(not spoken():find("fin_", 1, true), "finishers off: none")
say("hype finishers on")
for spell, key in pairs(F.FINISHERS) do
  check(ns.VOICE.titan.clips["fin_" .. key] or ns.VOICE.titan.clips["fin_" .. key .. "_1"], "titan has a line for " .. spell)
  check(F.TAGS[key], "and a tag for it")
end
reset()
local bestBefore = GodslayerDB.opts.hype.best
for _ = 1, 3 do say("hype test finisher pyro") M.advance(1) end
hear()
check(spoken():find("first_blood,fin_pyro", 1, true), "the finisher preview: " .. spoken())
H.End("test")
eq(GodslayerDB.opts.hype.best, bestBefore, "a preview is not a record")
-- a finisher belongs to its own kill, even when something bigger is said about that kill
reset()
engage()
for _ = 1, 3 do H.Kill("Same Guy", true, "same-guy") M.advance(13) end
cast(5308)
M.advance(0.5)
H.Kill("Same Guy", true, "same-guy")
hear()
check(spoken():find("dominate", 1, true) and not spoken():find("fin_execute", 1, true), "DOMINATION outranks the finisher: " .. spoken())
A.played = {}
kill()
hear()
check(not spoken():find("fin_execute", 1, true), "and the next kill does not inherit it: " .. spoken())

-- 7. the guild hears the big ones ---------------------------------------------------------------
reset()
local function sentStreaks()
  local kinds = {}
  for _, m in ipairs(M.sentAddon) do
    local kind = m[2]:match("^R;1;(%a+);")
    if kind then kinds[#kinds + 1] = kind .. "@" .. m[3] end
  end
  return table.concat(kinds, ",")
end
for _ = 1, 5 do kill() M.advance(13) end
eq(sentStreaks(), "godlike@GUILD", "GODLIKE is told to the guild")
for _ = 1, 10 do kill() M.advance(13) end
eq(sentStreaks(), "godlike@GUILD,godslayer@GUILD", "and GODSLAYER")
reset()
for _ = 1, 5 do kill() M.advance(0.5) end
check(sentStreaks():find("rampage", 1, true), "a RAMPAGE too: " .. sentStreaks())
reset()
for i = 1, 6 do say("hype test") M.advance(1) end
eq(sentStreaks(), "", "previews are never told")
reset()
say("hype streaks off")
for _ = 1, 5 do kill() M.advance(13) end
eq(sentStreaks(), "", "streaks off: nothing told")
say("hype streaks on")

reset()
M.printed = {}
M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;godlike;abc123", "GUILD", "Hyde Torch")
M.advance(1)
eq(spoken(), "ally_godlike", "a guildmate's GODLIKE is said out loud")
check(table.concat(M.printed, "\n"):find("Hyde Torch", 1, true), "and named in chat")
M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;rampage;abc123", "GUILD", "Hyde Torch")
M.advance(1)
eq(spoken(), "ally_godlike", "the same guildmate again inside a minute is not")
M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;regicide;abc123", "GUILD", "Hyde Torch")
M.advance(1)
eq(spoken(), "ally_godlike,ally_regicide", "but the King is news every time")
M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;godlike;abc999", "PARTY", "Party Guy")
M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;nonsense;abc999", "GUILD", "Odd Guy")
M.advance(1)
eq(spoken(), "ally_godlike,ally_regicide", "from the party, or a kind nobody knows: nothing")
reset()
engage()
M.advance(5)
A.played = {}
M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;godlike;abc124", "GUILD", "Other Torch")
M.advance(1)
eq(spoken(), "", "never over your own fight")
reset()
M.advance(4000)
M.printed = {}
for _ = 1, 10 do M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;regicide;bad1", "GUILD", "Liar Torch") M.advance(1) end
local said = 0
for _, l in ipairs(M.printed) do if l:find("Liar Torch", 1, true) then said = said + 1 end end
eq(said, 3, "one guildmate claiming the King over and over is heard three times an hour, no more")
M.advance(4000)
M.printed = {}
for i = 1, 12 do M.fire("CHAT_MSG_ADDON", "Godslayer", "R;1;godlike;mob" .. i, "GUILD", "Torch " .. i) end
eq(#M.printed, 6, "a whole guild at once: a handful a minute")
-- told later when the game would not let it go at once
reset()
M.advance(100)
M.lockdown = true
for _ = 1, 5 do kill() M.advance(13) end
eq(sentStreaks(), "", "in an instance nothing can be sent")
M.lockdown = false
M.advance(31)
eq(sentStreaks(), "godlike@GUILD", "outside it, the GODLIKE goes out after all")

-- 8. the chat wheel ------------------------------------------------------------------------------
reset()
check(W.Count() >= 16, "the wheel has its lines: " .. W.Count())
M.printed = {}
check(W.Say(1), "a line of yours")
check(A.played[#A.played].path:find("wheel_1.ogg", 1, true), "is heard")
eq(#M.sentAddon, 0, "alone, nothing is sent")
check(table.concat(M.printed):find(ns.WHEEL.text.wheel_1, 1, true), "and the words are in your chat")
check(not W.Say(2), "not two inside a couple of seconds")
M.advance(3)
M.groupSize = 3
check(W.Say(9), "in a party")
eq(M.sentAddon[1] and M.sentAddon[1][3], "PARTY", "it goes to the party") check(M.sentAddon[1][2]:match("^W;1;9;"), "as line nine: " .. tostring(M.sentAddon[1][2]))
M.advance(3)
M.groupSize = 12
W.Say(10)
eq(M.sentAddon[2] and M.sentAddon[2][3], "RAID", "in a raid, the raid")
M.advance(3)
LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
IsInGroup = function(category) return category == 2 or category == 1 end
W.Say(11)
eq(M.sentAddon[3] and M.sentAddon[3][3], "INSTANCE_CHAT", "in a battleground group, the battleground's own channel")
IsInGroup, LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = nil, nil, nil
A.played = {}
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;6;bgpal", "INSTANCE_CHAT", "Bg Pal")
check(A.played[1] and A.played[1].path:find("wheel_6.ogg", 1, true), "and a line from it is heard")
M.advance(10)
check(#M.sentChat == 0, "and nothing is ever written in a chat channel")
A.played = {}
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;4;zzz1", "PARTY", "Pal One")
check(A.played[1] and A.played[1].path:find("wheel_4.ogg", 1, true), "a groupmate's line is heard")
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;5;zzz1", "PARTY", "Pal One")
eq(#A.played, 1, "not twice inside a few seconds")
for i = 1, 20 do M.advance(3.1) M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;5;zzz1", "PARTY", "Pal One") end
check(#A.played <= 9, "and no more than a handful a minute: " .. #A.played)
M.advance(70)
A.played = {}
for i = 1, 30 do M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;" .. (i % 16 + 1) .. ";r" .. i, "RAID", "Raider " .. i) end
eq(#A.played, 1, "a whole raid at once: one line, and the rest wait their turn or are dropped")
for i = 1, 14 do M.advance(4) M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;" .. (i % 16 + 1) .. ";s" .. i, "RAID", "Spammer " .. i) end
check(#A.played <= 10, "and a raid taking turns is held to ten a minute: " .. #A.played)
M.advance(70)
A.played = {}
kill()
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;1;q1", "PARTY", "Quiet Pal")
local wheelHeard = 0
for _, p in ipairs(A.played) do if p.path:find("\\wheel\\", 1, true) then wheelHeard = wheelHeard + 1 end end
eq(wheelHeard, 0, "never over your own kill being called")
H.End("test")
A.played = {}
M.advance(70)
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;5;zzz2", "GUILD", "Guild Guy")
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;5;zzz2", "WHISPER", "Whisper Guy")
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;99;zzz3", "PARTY", "Pal Two")
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;2.5;zzz3", "PARTY", "Pal Two")
eq(#A.played, 0, "from the guild channel, or a line that does not exist: nothing")
say("hype wheel off")
M.fire("CHAT_MSG_ADDON", "Godslayer", "W;1;3;zzz4", "PARTY", "Pal Three")
eq(#A.played, 0, "wheel off: groupmates are not heard")
say("hype wheel on")
-- the key: hold, point, let go
M.advance(5)
A.played = {}
Godslayer_Wheel("down")
check(W.Shown(), "holding the key opens the ring")
Godslayer_Wheel("up")
check(not W.Shown(), "letting go closes it")
eq(#A.played, 0, "pointing at nothing says nothing")
local realCursor = GetCursorPosition
GetCursorPosition = function() return 0, 100 end -- straight up from the middle
Godslayer_Wheel("down")
Godslayer_Wheel("up")
check(A.played[1] and A.played[1].path:find("wheel_1.ogg", 1, true), "pointing straight up and letting go says the top line")
M.advance(3)
GetCursorPosition = function() return 100, 0 end -- to the right
Godslayer_Wheel("down") Godslayer_Wheel("up")
check(A.played[2] and A.played[2].path:find("wheel_3.ogg", 1, true), "pointing right says the third")
GetCursorPosition = realCursor
say("wheel list")
say("wheel")
check(W.Shown(), "/godslayer wheel opens it for clicking") say("wheel") check(not W.Shown(), "and again closes it")

-- the interface reloaded with our song playing: nothing holds it any more, so it is stopped
reset()
engage()
eq(GodslayerDB.opts.hype.playing, true, "the song playing is written down")
leaveCombat() M.advance(16)
eq(GodslayerDB.opts.hype.playing, nil, "and crossed out when it stops")
engage()
local stops = A.musicStops
H.Login()
eq(A.musicStops, stops + 1, "after a reload mid-fight the orphaned song is stopped") eq(GodslayerDB.opts.hype.playing, nil, "once")
H.End("test")

-- 9. previews ------------------------------------------------------------------------------------
reset()
say("hype test engage")
eq(A.music, THEME, "the fight preview starts the song")
M.advance(16)
eq(A.music, nil, "and lets it go after the grace") check(not H.Fighting(), "with no fight left behind")
say("hype test engage god")
M.advance(2)
check(spoken():find("engage_god", 1, true), "the Olympian preview: " .. spoken())
say("hype test sig polymorph")
check(effects():find("sig_sheep", 1, true), "a class sound preview: " .. effects())
A.played = {}
foe("target")
cast(118)
eq(effects(), "sig_sheep", "and a real Polymorph right after is not held back by the preview")
M.units.target = nil
say("hype test streak godslayer")
hear()
check(spoken():find("ally_godslayer", 1, true), "a streak preview: " .. spoken())
reset()
engage()
M.printed = {}
say("hype test engage")
check(table.concat(M.printed):find("in a fight", 1, true), "no fight preview during a real fight")

-- 10. clips -------------------------------------------------------------------------------------
for _, pack in ipairs(ns.VOICE_ORDER) do
  for _, group in ipairs({ "engage", "engage_god", "ally_godlike", "ally_rampage", "ally_godslayer", "ally_regicide" }) do
    check(H.ClipLength(group, pack) or H.ClipLength(group .. "_1", pack), pack .. " has " .. group)
  end
end
check(ns.SFX.engage and ns.SFX.ally, "the drums and the distant horn are built")

math.random = realRandom
M.realPrint(("%d passed, %d failed"):format(passed, failed))
if failed > 0 then os.exit(1) end
