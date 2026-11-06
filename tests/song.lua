-- Godslayer and the kill song rotation: lua tests/song.lua
--
-- Since 2.8.0 every file named kill, kill2 ... kill9 in GodslayerMusic joins a rotation,
-- .mp3 looked for before .ogg, and a fight never opens with the song the last one opened
-- with when there is a choice. The names are a roster, not a pattern: kill10 is not on it.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", race = "Scourge", sex = 2, faction = "Horde" })

-- The songs exist before the addon ever looks for one. kill2 only as .ogg (the fallback
-- has to find it), kill3 in both forms (.mp3 must win), kill10 as the decoy off the roster.
local OWN = "Interface\\AddOns\\GodslayerMusic\\"
M.audio.files[OWN .. "kill.mp3"] = true
M.audio.files[OWN .. "kill2.ogg"] = true
M.audio.files[OWN .. "kill3.mp3"] = true
M.audio.files[OWN .. "kill3.ogg"] = true
M.audio.files[OWN .. "kill10.mp3"] = true

local ns = M.load("Godslayer", { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" })
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local function say(text) SlashCmdList["GODSLAYER"](text) end

local seen, last, repeats, rounds = {}, nil, 0, 40
for i = 1, rounds do
  say("hype test")
  M.advance(1)
  local now = M.audio.music
  check(now ~= nil, "a song plays for test hunt " .. i)
  if now then
    seen[now] = (seen[now] or 0) + 1
    if last and now == last then repeats = repeats + 1 end
    last = now
  end
  say("hype stop")
  M.advance(3)
end

check(seen[OWN .. "kill.mp3"], "kill.mp3 is in the rotation")
check(seen[OWN .. "kill2.ogg"], "kill2.ogg joined through the .ogg fallback")
check(seen[OWN .. "kill3.mp3"], "kill3 plays as .mp3")
check(not seen[OWN .. "kill3.ogg"], "and never as .ogg, because .mp3 was found first")
check(not seen[OWN .. "kill10.mp3"], "kill10 is off the roster and never plays")
eq(repeats, 0, "no song opens two fights in a row while there is a choice")
local distinct = 0
for _ in pairs(seen) do distinct = distinct + 1 end
eq(distinct, 3, "the rotation holds exactly the three roster songs")

-- An Olympian opens with the signature song, kill.mp3, whatever the rotation last played.
say("hype engage on")
say("hype test engage god")
M.advance(1)
eq(M.audio.music, OWN .. "kill.mp3", "an Olympian engage opens with the signature song")
say("hype stop")
M.advance(3)

-- The announcer follows the song: with kill2 the only song, its tuned lines come first.
M.audio.files, M.audio.played, M.audio.music = {}, {}, nil
local S = "Interface\\AddOns\\Godslayer\\Sounds\\"
ns = M.load("Godslayer", { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" })
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
for pack, v in pairs(ns.VOICE) do
  for clip in pairs(v.clips) do
    M.audio.files[S .. pack .. "\\" .. clip .. ".ogg"] = true
    M.audio.files[OWN .. "voice\\kill2\\" .. pack .. "\\" .. clip .. ".ogg"] = true
  end
end
for name in pairs(ns.SFX) do M.audio.files[S .. "sfx\\" .. name .. ".ogg"] = true end
for name in pairs(ns.MUSIC) do M.audio.files[S .. "music\\" .. name .. ".ogg"] = true end
M.audio.files[OWN .. "kill2.ogg"] = true
say("hype test")
M.advance(3)
eq(M.audio.music, OWN .. "kill2.ogg", "the only rotation song plays")
local fromSong = 0
for _, p in ipairs(M.audio.played) do
  if p.path:find("voice\\kill2\\", 1, true) then fromSong = fromSong + 1 end
end
check(fromSong > 0, "announcer lines come from the playing song's own tuned set")
say("hype stop")

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
