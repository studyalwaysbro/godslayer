-- Godslayer 2.9: a Forever PARTY_KILL may keep the source GUID and seal the victim GUID.
-- The source attributes the blow; PvP credit proves that the sealed victim was a player.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
local MATE = "Player-1-0000BBBB"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE",
                      race = "Scourge", sex = 2, faction = "Horde" })
M.group[MATE] = true

local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua", "Fight.lua",
                "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua",
                "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local H, c = ns.Hype, ns.char

local function credit()
  M.hk = M.hk + 1
  M.fire("PLAYER_PVP_KILLS_CHANGED", "player")
end

local function hiddenKill(source, victim)
  M.fire("PARTY_KILL", source, victim == nil and M.secret() or victim)
  credit()
  M.advance(9) -- past identity matching, but inside the twenty-second hunt window
end

-- Full information remains the exact path used before 2.9.0.
local known = M.addUnit("target", { name = "Visible Victim", guid = "Player-1-0000C001", guild = "OLYMPUS",
                                   class = "WARRIOR", faction = "Alliance", level = 30 })
M.fire("PLAYER_TARGET_CHANGED")
M.fire("PARTY_KILL", ME, known.guid)
eq(c.kills, 1, "full payload scores immediately")
eq(c.points, 5, "full payload keeps its guild value")
eq(c.victims[known.guid].name, "Visible Victim", "full payload keeps the real identity")
eq(c.victims[known.guid].kb, 1, "full payload keeps the killing blow")
H.End("test")
M.advance(30)

-- A sealed victim with no PvP credit can be the creature shape seen in the live raw log.
local beforeKills, beforeShots = c.kills, M.shots
M.fire("PARTY_KILL", ME, M.secret())
M.advance(11)
eq(c.kills, beforeKills, "hidden creature-shaped event does not score by itself")
check(not H.Active(), "hidden creature-shaped event does not start a hunt")
eq(M.shots, beforeShots, "hidden creature-shaped event takes no screenshot")

-- In blows-only mode the readable source still establishes that these were our killing blows.
H.Opts().mode, H.Opts().photo, H.Opts().clip, H.Opts().window = "blows", true, true, 20
for _ = 1, 15 do hiddenKill(ME) end
local unknown = c.victims[ns.UNKNOWN_VICTIM_ID]
check(unknown ~= nil, "hidden player kills have an explicit victim bucket")
eq(unknown and unknown.name, "Unknown victim", "unknown bucket does not invent a name")
eq(unknown and unknown.guild, "Unknown", "unknown bucket does not invent a guild")
eq(unknown and unknown.kills, 15, "every hidden player kill reaches the victim bucket")
eq(unknown and unknown.kb, 15, "readable player source reaches the killing-blow bucket")
eq(c.guilds.Unknown and c.guilds.Unknown.kills, 15, "per-guild totals expose an unknown bucket")
eq(c.uniques, 2, "all hidden identities consume one explicit unique bucket")
eq(c.kills, 16, "hidden kills advance the durable total")
eq(c.kb, 16, "hidden own blows advance the durable killing-blow total")
eq(ns.session.streak, 16, "hidden kills advance the score streak")
eq(H.Kills(), 15, "hidden kills advance the live hunt")
eq(GodslayerHypeBanner.title.__text, "GODSLAYER", "hidden kills reach the announcer ladder")
check(M.shots > beforeShots, "the GODSLAYER rung takes its configured screenshot")

-- The same hidden hunt reaches the recorder barcode and its Screenshot() call when it ends.
local rungShots = M.shots
H.End("quiet")
M.advance(8)
check(ns.Clip.last ~= nil and ns.Clip.last[3] == 15, "hidden hunt writes fifteen kills into the clip barcode")
check(M.shots >= rungShots + 1, "hidden hunt barcode is carried by a screenshot")

-- A party member's hidden blow is a credited kill, but not our killing blow.
H.Opts().mode = "all"
hiddenKill(MATE)
unknown = c.victims[ns.UNKNOWN_VICTIM_ID]
eq(unknown.kills, 16, "party hidden kill reaches the same honest bucket")
eq(unknown.kb, 15, "party hidden kill is not put on our killing-blow list")
eq(c.kills, 17, "party hidden kill advances the total")
eq(c.kb, 16, "party hidden kill leaves our killing-blow total alone")
eq(H.Kills(), 1, "party hidden kill starts the next hunt in all-kills mode")

-- A scrubbed nil/empty victim has the same resilient path as a secret victim.
H.End("test")
M.fire("PARTY_KILL", ME, "")
credit()
M.advance(9)
eq(c.victims[ns.UNKNOWN_VICTIM_ID].kills, 17, "empty hidden victim is counted after PvP proof")

-- Detection is per event: a readable victim after hidden ones goes straight back to full detail.
local visibleAgain = M.addUnit("target", { name = "Visible Again", guid = "Player-1-0000C002", guild = "Ordinary Guild",
                                          class = "WARRIOR", faction = "Alliance", level = 31 })
M.fire("PLAYER_TARGET_CHANGED")
M.fire("PARTY_KILL", ME, visibleAgain.guid)
eq(c.victims[visibleAgain.guid].name, "Visible Again", "readable event after hidden events keeps its identity")
eq(c.victims[visibleAgain.guid].guild, "Ordinary Guild", "readable event after hidden events keeps its guild")
eq(c.victims[ns.UNKNOWN_VICTIM_ID].kills, 17, "readable event is not folded into unknown")

local hiddenLogs = 0
for _, line in ipairs(GodslayerDB.log) do
  if line:find("victim hidden by the client", 1, true) then hiddenLogs = hiddenLogs + 1 end
end
eq(hiddenLogs, 1, "live hidden-victim diagnostic remains once per session")
eq(ns.errors, nil, "both payload shapes run without handler errors")

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
