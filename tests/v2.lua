-- Offline tests for what 2.0 added: lua tests/v2.lua   (from the project root, Lua 5.1)
-- The spaced ladder, the kill notes, moments, kills nobody saw die, DENIED, duels, the hunt
-- card, the fuse, the music stepping back, and the stage when the client refuses to animate.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", faction = "Horde" })
local FILES = { "Data.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Comm.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local H, A = ns.Hype, M.audio
local S = "Interface\\AddOns\\Godslayer\\Sounds\\"
for pack, v in pairs(ns.VOICE) do for clip in pairs(v.clips) do A.files[S .. pack .. "\\" .. clip .. ".ogg"] = true end end
for name in pairs(ns.SFX) do A.files[S .. "sfx\\" .. name .. ".ogg"] = true end
for name in pairs(ns.MUSIC) do A.files[S .. "music\\" .. name .. ".ogg"] = true end
local function say(text) SlashCmdList["GODSLAYER"](text) end
H.Opts().pack = "titan"

local function spoken()
  local names = {}
  for _, p in ipairs(A.played) do
    local clip = p.path:match("\\([%w_]+)%.ogg$")
    if clip and not p.path:find("\\sfx\\", 1, true) and not p.path:find("\\music\\", 1, true) and p.path:find("Sounds", 1, true) then names[#names + 1] = (clip:gsub("_%d+$", "")) end
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
local function reset()
  H.End("test") M.advance(30)
  A.played, A.stopped, A.music, A.musicStops = {}, {}, nil, 0
end
local kid = 0
local function kill(name, id) kid = kid + 1 id = id or ("k" .. kid) H.Kill(name or ("Victim " .. kid), true, id) return id end
local realRandom = math.random
local function quiet() math.random = function(n) if n then return 1 end return 0.99 end end   -- no barks, no quips, no remarks
local function chatty() math.random = function(n) if n then return 1 end return 0.01 end end  -- every bark and quip

-- 1. the ladder and the notes -------------------------------------------------------------
quiet()
reset()
for _ = 1, 20 do kill() M.advance(13) end
eq(spoken(), "first_blood,mega_kill,ultra_kill,godlike,unstoppable,beyond_godlike,godslayer,twenty", "twenty kills: eight calls, the rest is the blade")
eq(title(), "TWENTY KILLS", "the twentieth has its own banner")
local notes = {}
for name in effects():gmatch("kill_(%d+)") do notes[#notes + 1] = name end
eq(#notes, 20, "every kill is heard at once")
eq(table.concat(notes, ""):sub(1, 10), "1234567888", "a note higher each kill, and the eighth note holds")
check(effects():find("drop", 1, true), "the top rungs get the sub drop")
eq(H.RungFor(4)[2], "ULTRA KILL", "four kills stand on the third rung") eq(select(2, H.RungFor(4))[2], "GODLIKE", "with GODLIKE next")
eq(select(2, H.RungFor(60)), nil, "nothing is above the last rung")
reset()
kill() M.advance(13) kill() M.advance(13) kill() M.advance(13)
A.played = {}
kill() M.advance(0.1)
eq(effects(), "kill_4", "the blade is not delayed") eq(spoken(), "", "and with no rung reached nothing is said")
eq(title(), "4 KILLS", "the banner is the count") check(line():find("1 more: GODLIKE", 1, true), "and the distance to the next rung: " .. line())
eq(ns.Stage.size, 1, "a kill between rungs is the smallest banner")
chatty()
reset()
for _ = 1, 4 do kill() M.advance(13) end
check(spoken():find("ultra_kill,more$"), "between rungs the announcer may say one short word: " .. spoken())
say("hype barks off")
kill() M.advance(13) kill() M.advance(13)
check(not spoken():find("more,godlike,more", 1, true) and spoken():find("godlike$"), "and with barks off never does: " .. spoken())
say("hype barks on")

-- 2. the stage ----------------------------------------------------------------------------
quiet()
reset()
kill() M.advance(1)
local b = GodslayerHypeBanner
check(b.anim.slam.__plays >= 1 and b.anim.flare.__plays >= 1 and b.anim.glow.__plays >= 1, "the words slam in with a streak and a glow")
eq(ns.Stage.size, 2, "FIRST BLOOD is a size two moment")
local rays = b.anim.raysIn.__plays
for _ = 1, 4 do kill() M.advance(13) end
eq(title(), "GODLIKE", "five kills") eq(ns.Stage.size, 3, "is a size three moment")
check(b.anim.raysIn.__plays > rays, "with rays behind the words") check((ns.Stage.pulses or 0) >= 1, "and the edges of the screen flash")
check(GodslayerHuntFuse:IsShown(), "the fuse is lit while the hunt is on")
eq(GodslayerHuntFuse.count.__text, "x5", "and carries the count")
check(math.abs(ns.Stage.FuseLeft() - 77) < 0.5, "it has burned for thirteen seconds: " .. tostring(ns.Stage.FuseLeft()))
M.advance(70) ns.Stage.FuseTick()
check(GodslayerHuntFuse.fill.__color[1] == 1 and GodslayerHuntFuse.fill.__color[2] < 0.2, "under ten seconds it turns red")
M.advance(30)
check(not H.Active() and not GodslayerHuntFuse:IsShown(), "and goes out with the hunt")
-- claws for kills in a row
reset()
H.Opts().multi = true
kill() M.advance(2) kill() M.advance(2) kill() M.advance(1)
eq(ns.Stage.claws, 3, "three in a row leaves three claw marks") check(b.anim.slash.__plays >= 1, "drawn behind the words")
-- fx off: plain words
say("hype fx off")
reset()
local slams = b.anim.slam.__plays
kill() M.advance(1)
eq(b.anim.slam.__plays, slams, "with fx off nothing is animated") eq(title(), "FIRST BLOOD", "the words still show")
check(not GodslayerHuntFuse:IsShown(), "and there is no fuse")
say("hype fx on")

-- 3. the hunt card ---------------------------------------------------------------------------
quiet()
reset()
for _ = 1, 6 do kill() M.advance(13) end
A.played = {}
M.advance(100)
eq(title(), "HUNT OVER", "a hunt of six ends with a card") eq(ns.Stage.grade, "B", "graded")
check(line():find("6 kills", 1, true) and line():find("1:05", 1, true), "with what it came to: " .. line())
check(effects():find("stamp", 1, true), "and the stamp is heard")
eq(H.GradeFor({ kills = 3 }), "C", "three kills is a C") eq(H.GradeFor({ kills = 2 }), nil, "two is not graded")
eq(H.GradeFor({ kills = 10, points = 6, bestRun = 3 }), "A", "points and a run lift the grade")
eq(H.GradeFor({ kills = 23, points = 14 }), "S+", "a hunt like the best one on record is an S plus")
reset()
for _ = 1, 10 do kill() M.advance(13) end
A.played = {}
M.advance(100)
eq(title(), "FLAWLESS HUNT", "ten kills and no death is a flawless hunt") check(spoken():find("flawless", 1, true), "and is called one: " .. spoken())
reset()
for _ = 1, 4 do kill() M.advance(13) end
A.played = {}
M.fire("PLAYER_DEAD") M.advance(6)
eq(title(), "SHUT DOWN", "dying mid hunt") eq(ns.Stage.grade, "C", "is graded too") check(spoken():find("^shut_down"), "after SHUT DOWN: " .. spoken())
reset()
kill() M.advance(100)
check(title() ~= "HUNT OVER", "one kill is not a hunt worth a card")

-- 4. moments ----------------------------------------------------------------------------------
local n = 0
local function enemy(token, name, extra)
  n = n + 1
  local u = { name = name, guid = ("Player-1-%08X"):format(n), class = "WARRIOR", faction = "Alliance", level = 30 }
  for k, v in pairs(extra or {}) do u[k] = v end
  return M.addUnit(token, u)
end
local function clearUnits() for token in pairs(M.units) do if token ~= "player" then M.units[token] = nil end end end
local function realKill(u)
  u.dead = true
  M.fire("PARTY_KILL", ME, u.guid)
  M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player")
  M.advance(13)
  u.dead = false
end
quiet()
reset() clearUnits()
local bob = enemy("target", "Bob Brute")
ns.ObserveUnit("target")
-- revenge: he was your target when you died
M.fire("PLAYER_DEAD") M.advance(5)
A.played = {}
realKill(bob)
check(spoken():find("first_blood,revenge", 1, true), "killing the one you were fighting when you died is REVENGE: " .. spoken())
check(line():find("REVENGE", 1, true), "on the banner too: " .. line()) check(effects():find("sting", 1, true), "with a sting under it")
eq(H.Kills(), 1, "a killing blow and its honor credit are one kill")
A.played = {}
realKill(bob)
check(not spoken():find("revenge", 1, true), "revenge is taken once: " .. spoken())
realKill(bob) A.played = {} realKill(bob)
check(spoken():find("dominate", 1, true) and line():find("DOMINATION", 1, true), "the fourth kill with none back is DOMINATION: " .. spoken())
-- he gets you back: payback, and the count starts over
realKill(bob) M.advance(20)
A.played = {}
M.fire("PLAYER_DEAD") M.advance(8)
check(spoken():find("shut_down,payback", 1, true) and line():find("Bob Brute got even", 1, true), "killed by someone you just killed: " .. spoken() .. " / " .. line())
reset()
A.played = {}
realKill(bob)
check(spoken():find("revenge", 1, true), "and that is a grudge of its own")
A.played = {} realKill(bob) realKill(bob)
check(not spoken():find("dominate", 1, true), "domination starts counting again after he got you")
A.played = {} realKill(bob)
check(spoken():find("dominate", 1, true), "and is reached again at the fourth")
-- a grudge runs out
reset() clearUnits()
local tim = enemy("target", "Tim Late") ns.ObserveUnit("target")
M.fire("PLAYER_DEAD") M.advance(700)
A.played = {} realKill(tim)
check(not spoken():find("revenge", 1, true), "ten minutes later it is not revenge any more")
-- levels
reset() clearUnits()
local kid2 = enemy("target", "Wee Lad", { level = 20 }) ns.ObserveUnit("target")
A.played = {} realKill(kid2)
check(spoken():find("first_blood,shame", 1, true) and effects():find("trombone", 1, true), "ten levels below you: a dry word and a sad trombone: " .. spoken())
reset() clearUnits()
local big = enemy("target", "Big Lad", { level = 34 }) ns.ObserveUnit("target")
A.played = {} realKill(big)
check(spoken():find("giant", 1, true) and line():find("GIANT SLAYER", 1, true), "four levels above you: GIANT SLAYER")
-- outnumbered: alone, three of them on screen
reset() clearUnits()
local one = enemy("nameplate1", "One Foe") enemy("nameplate2", "Two Foe") enemy("nameplate3", "Three Foe") enemy("nameplate4", "Four Foe")
for i = 1, 4 do ns.ObserveUnit("nameplate" .. i) end
A.played = {} realKill(one)
check(spoken():find("outnumbered", 1, true) and line():find("OUTNUMBERED", 1, true), "alone against a crowd: " .. spoken())
A.played = {} realKill(M.units.nameplate2)
check(not spoken():find("outnumbered", 1, true), "said once in a while, not every kill")
M.groupSize = 5
reset() M.advance(100)
A.played = {} realKill(M.units.nameplate3)
check(not spoken():find("outnumbered", 1, true), "in a group it is not outnumbered")
M.groupSize = 0
-- comeback
reset() clearUnits()
local foe = enemy("nameplate1", "Some Foe") ns.ObserveUnit("nameplate1")
M.fire("PLAYER_DEAD") M.advance(5) M.fire("PLAYER_DEAD") M.advance(5)
A.played = {} realKill(foe)
check(spoken():find("comeback", 1, true), "first kill after two deaths in a row: " .. spoken())
-- close call, only where health can be read
reset() clearUnits()
local foe2 = enemy("nameplate1", "Near Miss") ns.ObserveUnit("nameplate1")
M.myHealth = 12
A.played = {} realKill(foe2)
check(spoken():find("clutch", 1, true) and line():find("CLOSE CALL", 1, true), "a kill at twelve percent health: " .. spoken())
eq(GodslayerDB.probe.health, "readable", "what the client allowed is written down")
M.secretHealth = true
reset() A.played = {} realKill(foe2)
check(not spoken():find("clutch", 1, true), "hidden health: no close call, and no error") eq(GodslayerDB.probe.health, "hidden", "and that is written down")
M.secretHealth, M.myHealth = nil, nil
-- class remarks: now and then, once per class per hunt
chatty()
reset() clearUnits()
local mage = enemy("nameplate1", "Blinky Mage", { class = "MAGE" }) ns.ObserveUnit("nameplate1")
local mage2 = enemy("nameplate2", "Other Mage", { class = "MAGE" }) ns.ObserveUnit("nameplate2")
A.played = {} realKill(mage)
check(spoken():find("class_mage", 1, true), "a word about the victim's class: " .. spoken())
A.played = {} realKill(mage2)
check(not spoken():find("class_mage", 1, true), "once per class per hunt: " .. spoken())
quiet()
say("hype moments off")
reset() clearUnits()
local bob2 = enemy("target", "Bob Again") ns.ObserveUnit("target")
M.fire("PLAYER_DEAD") M.advance(5)
A.played = {} realKill(bob2)
check(not spoken():find("revenge", 1, true) and not line():find("REVENGE", 1, true), "moments off: just the kill")
say("hype moments on")
-- previews
reset()
A.played = {}
say("hype test moment revenge") M.advance(8)
check(spoken():find("revenge", 1, true), "a moment can be previewed") eq(GodslayerDB.opts.hype.best, 20, "and a preview is never a record")

-- 5. a kill nobody saw die -----------------------------------------------------------------------
quiet()
reset() clearUnits()
A.played = {}
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player")
M.advance(1)
eq(H.Kills(), 0, "credit waits a moment for its death")
M.advance(1)
eq(H.Kills(), 1, "then it is a kill all the same") eq(spoken(), "first_blood", "and it is called") check(line():find("A kill", 1, true), "without a name")
local late = enemy("nameplate1", "Late Corpse", { guild = "OLYMPUS" })
ns.ObserveUnit("nameplate1")
late.dead = true M.fire("UNIT_DIED", late.guid)
M.advance(4)
eq(H.Kills(), 1, "the death turning up afterwards is the same kill, not a second one")
check(spoken():find("olympus", 1, true), "and its Olympus score is still announced: " .. spoken())
eq(ns.char.kills, 1, "and scored once")
-- the killing blow arriving after the credit was called
reset() clearUnits()
local slow = enemy("nameplate1", "Slow Event")
ns.ObserveUnit("nameplate1")
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player")
M.advance(2)
eq(H.Kills(), 1, "called without a name")
M.fire("PARTY_KILL", ME, slow.guid) M.advance(10)
eq(H.Kills(), 1, "a late killing blow is still that one kill")
-- two credits, nobody seen: two kills
reset()
M.hk = M.hk + 2 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.advance(3)
eq(H.Kills(), 2, "two credits are two kills")
-- the review round: every route a kill can arrive by, in the orders that used to count wrong
reset() clearUnits()
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Zed Far dies, honorable kill (Estimated Honor Points: 3)")
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.advance(10)
eq(H.Kills(), 1, "an honor line and its credit, victim never seen: one kill")
reset()
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.advance(2)
local seenY = enemy("nameplate1", "Seen Why") ns.ObserveUnit("nameplate1")
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.fire("PARTY_KILL", ME, seenY.guid) M.advance(10)
eq(H.Kills(), 2, "an unseen kill, then a seen one: two kills, neither eaten by the other")
reset() clearUnits()
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.advance(2)
local corpse = enemy("nameplate1", "Too Late") ns.ObserveUnit("nameplate1")
A.played = {}
M.fire("PLAYER_DEAD") M.advance(1)
corpse.dead = true M.fire("UNIT_DIED", corpse.guid) M.advance(6)
check(not H.Active(), "a kill named after you died does not start a new hunt") check(not spoken():find("first_blood", 1, true), "or call FIRST BLOOD over your corpse: " .. spoken())
M.fire("PLAYER_PVP_KILLS_CHANGED", M.secret()) M.advance(3)
check(not H.Active(), "a credit event with a hidden unit is not known to be yours")
-- previews leave a real hunt alone
reset() clearUnits()
kill() M.advance(13) kill() M.advance(13)
say("hype test") say("hype test moment revenge") say("hype test card") M.advance(2)
eq(H.Kills(), 2, "a preview cannot add to a real hunt") check(H.Active(), "or end it")
reset()
say("hype off") A.played = {}
say("hype test") M.advance(3)
eq(spoken(), "first_blood", "a preview is heard even with the announcer off")
reset() say("hype on")
-- DENIED is for the one you were aiming at
clearUnits()
M.spells = { [2139] = "Counterspell" }
enemy("target", "My Target") enemy("nameplate5", "Far Caster")
A.played = {}
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "c", 2139) M.fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate5", "c2", 1) M.advance(3)
eq(effects(), "", "a stranger's cast stopping nearby is not DENIED")
M.advance(30)

-- a kill called without a name gets it on the banner when the death turns up
reset() clearUnits()
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.advance(2)
local named = enemy("nameplate1", "Found Later") ns.ObserveUnit("nameplate1")
named.dead = true M.fire("UNIT_DIED", named.guid) M.advance(1.5)
check(line():find("Found Later is dead", 1, true) and not line():find("A kill", 1, true), "the banner is corrected while it is still up: " .. line())
-- a run and a small rung in one breath is one call; from GODLIKE up it is both
reset() H.Opts().multi = true quiet()
kill() M.advance(2) A.played = {} kill() M.advance(8)
eq(spoken(), "double_kill", "DOUBLE KILL at the second kill, and MEGA KILL only on the banner") eq(title(), "MEGA KILL", "which still carries the rung")
kill() M.advance(2) kill() M.advance(2) A.played = {} kill() M.advance(10)
eq(spoken(), "rampage,godlike", "RAMPAGE and GODLIKE together are both worth hearing")
-- barks never come two kills running
reset() chatty() H.Opts().multi = false
for _ = 1, 3 do kill() M.advance(13) end
A.played = {} kill() M.advance(13) kill() M.advance(13) kill() M.advance(13)
eq(spoken(), "more,godlike,more", "a word at four, the rung at five, a word at six")
kill() M.advance(13) A.played = {} kill() M.advance(13) kill() M.advance(13)
eq(spoken(), "more", "eight gets a word, so nine does not: never two kills running")
quiet() H.Opts().multi = true

-- only my killing blows: an unseen credit is not one
say("hype blows")
reset()
M.hk = M.hk + 1 M.fire("PLAYER_PVP_KILLS_CHANGED", "player") M.advance(3)
eq(H.Kills(), 0, "in killing-blows mode credit alone starts nothing")
say("hype all")

-- 6. DENIED ------------------------------------------------------------------------------------------
quiet()
reset() clearUnits()
M.spells = { [2139] = "Counterspell", [116] = "Frostbolt" }
local caster = enemy("target", "Chatty Priest", { class = "PRIEST" })
A.played = {}
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-1", 2139)
M.advance(0.2)
M.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "cast-2", 2060)
M.fire("UNIT_SPELLCAST_INTERRUPTED", "nameplate3", "cast-2", 2060)
M.advance(4)
eq(title(), "DENIED", "your interrupt and their cast stopping is DENIED") eq(effects(), "deny", "heard once for one cast") eq(spoken(), "denied", "and said")
check(line():find("Chatty Priest", 1, true), "with their name: " .. line())
A.played = {}
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-3", 2139) M.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "cast-4", 2060) M.advance(4)
eq(effects(), "deny", "the sound every time") eq(spoken(), "", "the word only now and then")
A.played = {}
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-5", 116) M.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "cast-6", 2060) M.advance(4)
eq(effects(), "", "a Frostbolt is not an interrupt")
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-7", 2139) M.advance(2) M.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "cast-8", 2060) M.advance(4)
eq(effects(), "", "a cast that stops two seconds later was not yours")
caster.faction = "Horde"
M.fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast-9", 2139) M.fire("UNIT_SPELLCAST_INTERRUPTED", "target", "cast-10", 2060) M.advance(4)
eq(effects(), "", "a friend's cast stopping is nothing")
M.fire("UNIT_SPELLCAST_SUCCEEDED", M.secret(), "x", M.secret()) M.fire("UNIT_SPELLCAST_INTERRUPTED", M.secret())
eq(ns.errors, nil, "hidden cast events raise nothing")

-- 7. duels ----------------------------------------------------------------------------------------------
DUEL_WINNER_KNOCKOUT, DUEL_WINNER_RETREAT = "%1$s has defeated %2$s in a duel", "%2$s has fled from %1$s in a duel"
reset() A.played = {}
M.fire("CHAT_MSG_SYSTEM", "Vesh Torchman has defeated Rival Mage in a duel") M.advance(5)
eq(title(), "DUEL WON", "a duel you win") eq(spoken(), "duel_win", "is called") check(line():find("Rival Mage", 1, true), "by name")
A.played = {}
M.fire("CHAT_MSG_SYSTEM", "Vesh has fled from Rival Mage in a duel") M.advance(5)
eq(title(), "DUEL LOST", "running away is losing") eq(spoken(), "duel_loss", "and is called")
A.played = {}
M.fire("CHAT_MSG_SYSTEM", "Someone Else has defeated Rival Mage in a duel") M.advance(5)
eq(spoken(), "", "other people's duels are nothing")
M.fire("CHAT_MSG_SYSTEM", M.secret()) M.fire("CHAT_MSG_SYSTEM", "You have been awarded a duel of wits")
eq(spoken(), "", "nor is other yellow text") eq(H.Kills(), 0, "a duel is not a kill")

-- 8. the music steps back -------------------------------------------------------------------------------
quiet()
reset()
A.cvars.Sound_MusicVolume = "0.8"
kill() M.advance(0.6)
eq(A.music, S .. "music\\hunt.ogg", "the hunt theme is playing")
eq(A.cvars.Sound_MusicVolume, "0.48", "while the call is spoken the music steps back")
eq(GodslayerDB.opts.hype.duckFrom, 0.8, "and where it was is written down")
M.advance(6)
eq(A.cvars.Sound_MusicVolume, "0.8", "afterwards it is back") eq(GodslayerDB.opts.hype.duckFrom, nil, "and the note is gone")
kill() M.advance(0.6)
A.cvars.Sound_MusicVolume = "0.5" -- you moved the slider while it was down
M.advance(6)
eq(A.cvars.Sound_MusicVolume, "0.5", "a slider you moved yourself is left where you put it")
-- a hunt ending mid-call puts it back at once
A.cvars.Sound_MusicVolume = "0.8"
kill() M.advance(0.6)
H.End("stop")
eq(A.cvars.Sound_MusicVolume, "0.8", "a hunt ending mid-call restores the music at once")
-- the game was closed while it was down
GodslayerDB.opts.hype.duckFrom = 0.7
A.cvars.Sound_MusicVolume = "0.3"
H.Login()
eq(A.cvars.Sound_MusicVolume, "0.7", "logging in after a crash mid-call puts the music back")
-- a client that refuses
A.cvars.Sound_MusicVolume = "0.8"
say("hype duck off")
reset() kill() M.advance(0.6)
eq(A.cvars.Sound_MusicVolume, "0.8", "duck off: the slider is never touched")
say("hype duck on")
-- the second half of the theme
reset()
for _ = 1, 4 do kill() M.advance(13) end
eq(A.music, S .. "music\\hunt.ogg", "four kills: still the first half")
kill() M.advance(13)
eq(A.music, S .. "music\\hunt2.ogg", "at five the theme moves to its second half")
reset()
-- channel
say("hype channel dialog")
kill() M.advance(1)
eq(A.channel, "Dialog", "the announcer can be moved to the dialog channel")
say("hype channel master")
say("hype channel nonsense") eq(GodslayerDB.opts.hype.channel, "Master", "an unknown channel changes nothing")
-- screenshots are opt-in
reset()
for _ = 1, 15 do kill() M.advance(13) end
eq(M.shots, 0, "no screenshots unless asked")
say("hype photo on")
reset()
for _ = 1, 15 do kill() M.advance(13) end
eq(M.shots, 1, "with photo on GODSLAYER is photographed")
say("hype photo off")

-- 9. takes are dealt, not rolled --------------------------------------------------------------------------
math.random = realRandom
do
  H.Opts().pack = "frost"
  H.Pack()
  local seen, order = {}, {}
  for i = 1, 3 do local clip = H.Pick("first_blood") seen[clip] = (seen[clip] or 0) + 1 order[i] = clip end
  check(seen.first_blood_1 == 1 and seen.first_blood_2 == 1 and seen.first_blood_3 == 1, "three takes are each heard once before any repeats: " .. table.concat(order, ","))
  local fourth = H.Pick("first_blood")
  check(fourth ~= order[3], "and a new deal does not open with the take the last one closed on")
  eq(H.Pick("godlike"), "godlike", "a line with one take is that take") eq(H.Pick("no_such_line"), nil, "a line nobody recorded is nothing")
  H.Opts().pack = "titan"
end

-- 10. every announcer has every new line, and none runs long ---------------------------------------------
for id, pack in pairs(ns.VOICE) do
  for _, clip in ipairs({ "twenty", "twentyfive", "thirty", "forty", "fifty", "more_1", "more_4", "revenge_1", "revenge_2", "dominate_1", "giant", "clutch_1",
                          "outnumbered_1", "comeback", "shame_1", "flawless", "payback", "class_warrior", "class_druid", "duel_win", "duel_loss", "denied_1" }) do
    check(pack.clips[clip], id .. " has " .. clip)
  end
  for clip, seconds in pairs(pack.clips) do
    if clip:find("^more_") then check(seconds <= 2.6, id .. "/" .. clip .. " is short: " .. seconds) end
  end
end
for i = 1, 8 do check(ns.SFX["kill_" .. i], "kill note " .. i .. " exists") end
for _, name in ipairs({ "stamp", "sting", "drop", "trombone", "deny" }) do check(ns.SFX[name], "sound " .. name .. " exists") end
check(ns.MUSIC.hunt2, "the theme has a second half")

for _, l in ipairs(GodslayerDB.log) do if l:find(" error: ", 1, true) then check(false, "logged error: " .. l) end end

-- 11. a client that will not animate, or has no art ---------------------------------------------------------
do
  M.noAnimations = true
  GodslayerHypeBanner, GodslayerHuntFuse = nil, nil
  local ns2 = M.load("Godslayer", FILES)
  M.fire("PLAYER_LOGIN")
  ns2.Hype.Opts().pack = "titan"
  check(pcall(ns2.Hype.Kill, "Zeus", true, "z1"), "no animation groups: a kill raises nothing")
  eq(GodslayerHypeBanner.title.__text, "FIRST BLOOD", "and the words still show")
  M.advance(100)
  M.noAnimations = nil
  M.failTexture = true
  GodslayerHypeBanner = nil
  local ns3 = M.load("Godslayer", FILES)
  M.fire("PLAYER_LOGIN")
  ns3.Hype.Opts().pack = "titan"
  check(pcall(ns3.Hype.Kill, "Zeus", true, "z2"), "textures refused: a kill raises nothing")
  eq(GodslayerHypeBanner and GodslayerHypeBanner.title.__text, "FIRST BLOOD", "and the plain banner takes over")
  M.failTexture = nil
  local noted = false
  for _, l in ipairs(GodslayerDB.log) do if l:find("error: stage:", 1, true) then noted = true end end
  check(noted, "the refusal is written to the log")
  ns3.Hype.Kill("Hera", true, "z3")
  eq(GodslayerHypeBanner.title.__text, "MEGA KILL", "and the plain banner keeps working")
  eq(ns2.errors, nil, "no errors without animations")
end

-- the clip mark: a hunt written into a screenshot for a recorder
do
  -- the slash command belongs to the last copy loaded above, so this copy is driven directly
  local C = ns.Clip
  local function say(text) if text == "clip" then C.Command() else H.Command((text:gsub("^hype ", ""))) end end
  M.advance(700)
  local shots = M.shots
  H.Kill("Ares", true, "c1") H.Kill("Hera", true, "c2")
  M.advance(100)
  eq(M.shots, shots, "no clip mark unless asked")
  check(C.last == nil, "and nothing drawn")
  say("hype clip on")
  H.Kill("Ares", true, "c3") M.advance(30) H.Kill("Hera", true, "c4") M.advance(2) H.Kill("Zeus", true, "c5")
  M.advance(90.5)
  eq(M.shots, shots, "the mark waits for the card")
  M.advance(8)
  eq(M.shots, shots + 1, "a hunt that ran out is marked once")
  local b = C.last
  eq(#b, 16, "sixteen bytes")
  eq(b[1], 0xAC, "the mark opens with its magic byte")
  eq(b[2], 16 + C.KIND.quiet, "version one, a hunt that ran out")
  eq(b[3], 3, "three kills")
  eq(b[4] * 256 + b[5], 129, "seconds since the first kill")
  eq(b[6] * 256 + b[7], 97, "seconds since the last kill")
  eq(b[8], 3, "ULTRA KILL is the third rung")
  eq(b[9], 2, "best run of two")
  eq(b[10], 1, "three kills and a run under three grade C")
  eq(b[12], 0, "no flags on a plain hunt")
  eq(b[13] * 256 + b[14], 97, "the best moment was the kill that made the run")
  eq(b[16], C.Crc({ b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15] }), "the last byte checks the rest")
  check(C.Showing(), "the squares are up for the screenshot")
  M.advance(2)
  check(not C.Showing(), "and gone again")
  -- the same bytes the recorder's own tests read (clipper/test_clipper.py)
  eq(C.Crc({ 0xAC, 0x11, 7, 0, 200, 0, 98, 5, 3, 3, 5, 2, 0, 120, 9 }), 0x03, "CRC agrees with the recorder")
  H.Kill("Ares", true, "c6")
  M.advance(1)
  M.units.player.dead = true
  H.Died()
  M.units.player.dead = nil
  M.advance(4)
  eq(M.shots, shots + 2, "a hunt you died in is marked too")
  eq(C.last[2], 16 + C.KIND.died, "as a death")
  eq(C.last[3], 1, "with its one kill")
  check(C.last[15] ~= b[15], "every mark has its own count")
  say("hype test")
  say("hype stop")
  M.advance(20)
  eq(M.shots, shots + 2, "a hunt stopped by hand is not marked")
  say("hype test")
  M.advance(100)
  eq(M.shots, shots + 3, "a pretend hunt is marked")
  eq(C.last[12] % 2, 1, "and flagged as pretend")
  say("clip")
  M.advance(1)
  eq(M.shots, shots + 4, "/godslayer clip marks by hand")
  eq(C.last[2], 16 + C.KIND.manual, "as a manual mark")
  check(C.Showing(), "the squares show until the screenshot lands")
  M.fire("SCREENSHOT_SUCCEEDED")
  check(not C.Showing(), "and go when it does")
  local real = Screenshot
  Screenshot = nil
  M.printed = {}
  check(pcall(say, "clip") and table.concat(M.printed, " "):find("would not take the screenshot", 1, true), "a client with no screenshots says so")
  Screenshot = real
  say("hype clip off")
  M.advance(200)
end

M.printed = {}
check(pcall(say, "hype probe") and table.concat(M.printed, "\n"):find("Your health: readable", 1, true), "the probe says what the client allows: " .. table.concat(M.printed, " | "))
M.secretHealth = true M.printed = {}
check(pcall(say, "hype probe") and table.concat(M.printed, "\n"):find("Your health: hidden", 1, true), "and when it does not")
M.secretHealth = nil
check(pcall(say, "hype"), "the settings print")
eq(ns.errors, nil, "no handler errors in the 2.0 tests")
M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
