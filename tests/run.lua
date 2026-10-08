-- Offline tests: lua tests/run.lua   (from the project root, Lua 5.1)
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE", faction = "Horde" })

local ns = M.load("Godslayer", { "Data.lua", "Core.lua", "Comm.lua", "UI.lua" })
M.fire("ADDON_LOADED", "SomethingElse")
check(GodslayerDB == nil, "ignores other addons loading")
M.fire("PARTY_KILL", ME, "Player-1-00000001") -- before init: must not error
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local c = ns.char
check(c ~= nil and ns.myName == "Vesh Torchman", "character initialised with full name")

-- 1. guild matching -----------------------------------------------------------
local cases = {
  { "OLYMPUS", "original" }, { "Olympus", "original" }, { "olympus", "original" },
  { "Olympus Kitchen", "network" }, { "OLYMPUS BETZ", "network" }, { "OLYMPUS LXX", "network" },
  { "OLYMPUS XIlI", "network" }, { "DARK OLYMPUS", "network" }, { "Olympus Royal Guard", "network" },
  { "AMERICAN OLYMPUS", "network" }, { "OLYMPIAN", "network" }, { "OLYMPIANS", "network" },
  { "HOELYMPUS", "network" }, { "HOLYPMUS", "network" }, { "Special Olmpus", "network" },
  { "Special Olmpus II", "network" }, { "The Enclave", "network" }, { "0LYMPUS II", "network" },
  { "OLYMPVS", "network" }, { "Olympuss", "network" }, { "Oly mpus", "network" }, { " OLYMPUS ", "original" }, { "O L Y M P U S", "network" },
  { "The True Torchmen", nil }, { "Olympic Swim Team", nil }, { "Olympia", nil }, { "Mudhutters", nil },
  { "Method", nil }, { "", nil }, { "Enclave", nil }, { "Polyps", nil }, { "Lympus", "network" },
}
for _, case in ipairs(cases) do eq(ns.Classify(case[1]), case[2], "classify <" .. case[1] .. ">") end
eq(ns.Classify(nil), nil, "classify nil")
eq(ns.Classify(M.secret()), nil, "classify secret")

-- 2. honor line patterns ------------------------------------------------------
local pat, cap = ns.formatToPattern("%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)")
local got = { ("Bob Smith dies, honorable kill Rank: Private (Estimated Honor Points: 12)"):match(pat) }
eq(got[cap], "Bob Smith", "honor pattern captures victim")
pat, cap = ns.formatToPattern("%2$s hat %1$s get\195\182tet (+%3$d)")
got = { ("Private hat Hans get\195\182tet (+5)"):match(pat) }
eq(got[cap], "Hans", "positional honor pattern")
eq(ns.parseHonorLine("You have been awarded 12 honor points."), nil, "nameless honor line ignored")
eq(ns.parseHonorLine("Zed dies, honorable kill (Estimated Honor Points: 3)"), "Zed", "fallback honor pattern")

-- helpers ---------------------------------------------------------------------
local n = 0
local function enemy(token, name, guild, extra)
  n = n + 1
  local u = { name = name, guid = ("Player-1-%08X"):format(n), guild = guild, class = "WARRIOR", faction = "Alliance" }
  for k, v in pairs(extra or {}) do u[k] = v end
  return M.addUnit(token, u)
end
local function clearUnits()
  for token in pairs(M.units) do if token ~= "player" then M.units[token] = nil end end
end
local function hkCredit() M.hk = M.hk + 1; M.fire("PLAYER_PVP_KILLS_CHANGED", "player"); M.fire("PLAYER_PVP_KILLS_CHANGED", "player") end

-- 3. my killing blow on the original guild -------------------------------------
local asmon = enemy("target", "Asmongold Asmongler", "OLYMPUS", { level = 60, race = "Human", sex = 2, rank = "Guild Master",
                                                                pvpName = "Grand Marshal Asmongold Asmongler" })
M.fire("PLAYER_TARGET_CHANGED")
M.fire("PARTY_KILL", ME, asmon.guid)
eq(c.kills, 1, "kb: kills"); eq(c.points, 5, "kb: 5 points for OLYMPUS"); eq(c.kb, 1, "kb: killing blow")
eq(c.orig, 1, "kb: original count"); eq(c.uniques, 1, "kb: unique")
eq(c.victims[asmon.guid].name, "Asmongold Asmongler", "victim stored under full name")

-- 4. the same death reported by every signal counts once -----------------------
M.fire("UNIT_DIED", asmon.guid)
hkCredit()
M.advance(5)
eq(c.kills, 1, "dedupe: still one kill"); eq(c.points, 5, "dedupe: still five points")

-- 5. assist: honorable kill credit + witnessed death, no killing blow ----------
M.advance(20)
local cook = enemy("nameplate3", "Gordon Ramsey", "Olympus Kitchen")
M.fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
M.fire("UNIT_DIED", cook.guid)
hkCredit()
M.advance(1)
eq(c.kills, 2, "assist: counted"); eq(c.points, 6, "assist: 1 point for network guild"); eq(c.kb, 1, "assist: no killing blow")
-- killing blow event arriving late upgrades it rather than double counting
M.fire("PARTY_KILL", ME, cook.guid)
eq(c.kills, 2, "late kb: no double count"); eq(c.kb, 2, "late kb: upgraded")
eq(c.victims[cook.guid].kb, 1, "late kb: on the victim")

-- 6. a kill on somebody outside the network scores nothing ---------------------
M.advance(20)
local rando = enemy("target", "Random Gnome", "Method")
M.fire("PLAYER_TARGET_CHANGED")
M.fire("PARTY_KILL", ME, rando.guid)
M.advance(10)
eq(c.kills, 2, "non-network kill ignored")

-- 7. guild unknown at kill time, seen a moment later ---------------------------
M.advance(20)
clearUnits()
local ghost = enemy("hidden", "Late Tag", "OLYMPUS XLI")
M.units.hidden = nil
M.fire("PARTY_KILL", ME, ghost.guid)
eq(c.kills, 2, "pending: not scored yet")
M.units.mouseover = ghost
M.fire("UPDATE_MOUSEOVER_UNIT")
eq(c.kills, 3, "pending: scored once the tag is seen"); eq(c.points, 7, "pending: points")
eq(c.victims[ghost.guid].name, "Late Tag", "pending: name filled from the sighting")
-- and a kill whose guild never shows expires quietly
M.advance(20); clearUnits()
local nobody = enemy("hidden", "No Tag", nil); M.units.hidden = nil
M.fire("PARTY_KILL", ME, nobody.guid)
M.advance(16 * 60)
M.units.mouseover = nobody; nobody.guild = "OLYMPUS"; M.fire("UPDATE_MOUSEOVER_UNIT")
eq(c.kills, 3, "pending: expired kill is not credited later")

-- 8. secret values never error and never score ---------------------------------
M.advance(20); clearUnits()
M.fire("PARTY_KILL", M.secret(), M.secret())
M.fire("UNIT_DIED", M.secret())
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", M.secret())
M.fire("NAME_PLATE_UNIT_ADDED", M.secret())
M.fire("CHAT_MSG_ADDON", M.secret(), M.secret(), M.secret(), M.secret())
enemy("target", "Secret Guy", "OLYMPUS", { secretGUID = true, secretGuild = true, secretName = true })
M.fire("PLAYER_TARGET_CHANGED")
eq(c.kills, 3, "secrets: nothing scored"); eq(ns.errors, nil, "secrets: no handler errors")

-- 9. a group member's killing blow counts as a kill, not as my killing blow -----
M.advance(20); clearUnits()
local mate = "Player-1-0000BBBB"; M.group[mate] = true
local v9 = enemy("nameplate1", "Party Victim", "OLYMPUS BETZ")
M.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.fire("PARTY_KILL", mate, v9.guid)
eq(c.kills, 4, "group kb: counted"); eq(c.kb, 3, "group kb: not mine")

-- 10. a stranger's killing blow is not ours, and a death nobody credits is not either
M.advance(20)
local v10 = enemy("nameplate2", "Not Mine", "OLYMPUS")
M.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.fire("PARTY_KILL", "Player-1-0000CCCC", v10.guid)
M.fire("UNIT_DIED", v10.guid)
M.advance(10)
eq(c.kills, 4, "stranger kill ignored")

-- 11. two deaths, one credit: exactly one kill ---------------------------------
M.advance(20); clearUnits()
local a = enemy("nameplate1", "Twin A", "OLYMPUS II"); local b = enemy("nameplate2", "Twin B", "OLYMPUS II")
M.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); M.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
M.fire("UNIT_DIED", a.guid); M.advance(1); M.fire("UNIT_DIED", b.guid)
hkCredit(); M.advance(6)
eq(c.kills, 5, "two deaths one credit")
check(c.victims[b.guid] ~= nil and c.victims[a.guid] == nil, "credit goes to the closest death")

-- 12. killing the same player again later counts again -------------------------
M.advance(60)
M.units.target = asmon; M.fire("PLAYER_TARGET_CHANGED")
M.fire("PARTY_KILL", ME, asmon.guid)
eq(c.victims[asmon.guid].kills, 2, "rekill counts"); eq(c.uniques, 5, "uniques unchanged by rekill")
eq(c.kills, 6, "total kills"); eq(c.points, 5 + 1 + 1 + 1 + 1 + 5, "total points"); eq(c.kb, 4, "total killing blows")

-- 13. friendly-faction deaths are never matched to a credit --------------------
M.advance(20); clearUnits()
local friend = enemy("nameplate1", "Horde Olympian", "Olympus Horde Branch", { faction = "Horde" })
M.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
M.fire("UNIT_DIED", friend.guid); hkCredit(); M.advance(6)
eq(c.kills, 6, "friendly death not counted")

-- 14. named honor line (rare) --------------------------------------------------
M.advance(20); clearUnits()
local named = enemy("target", "Honor Line", "OLYMPUS GOD"); M.fire("PLAYER_TARGET_CHANGED")
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "Honor Line dies, honorable kill (Estimated Honor Points: 9)")
eq(c.kills, 7, "named honor line counts"); check(c.victims[named.guid] ~= nil, "honor line resolved to the guid")
M.fire("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 9 honor points.")
eq(c.kills, 7, "nameless honor line does nothing")

-- 15. guild sync ---------------------------------------------------------------
M.advance(40)
check(M.prefix == "Godslayer", "prefix registered")
local sawHello, sawStats = false, false
for _, m in ipairs(M.sentAddon) do
  if m[2]:match("^H;1") then sawHello = true end
  if m[2]:match("^S;1;") then sawStats = m[2] end
  eq(m[3], "GUILD", "addon message goes to guild only")
  check(#m[2] <= 255, "addon message fits")
end
check(sawHello, "hello sent after login"); check(sawStats, "stats broadcast after kills")
check(sawStats and sawStats:match("^S;1;7;15;6;4;2;MAGE;1%.1%.0;2;%x%x%x%x%x%x$"), "stats payload: " .. tostring(sawStats))
local myTag = sawStats:match(";(%x+)$")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;400;400;400;0;0;MAGE;1.0.0;0;" .. myTag, "GUILD", "Vesh")  -- own echo under a shorter name
M.fire("CHAT_MSG_ADDON", "Godslayer", "H;1;" .. myTag, "GUILD", "Vesh")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;10;22;8;4;3;WARRIOR;1.0.0", "GUILD", "Brakka Ashmane")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;3;3;2;1;0;MAGE;1.0.0", "GUILD", "Zul Embertusk")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;2;99;1;0;0;MAGE;1.0.0", "GUILD", "Cheater Mc")     -- impossible points
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;x;1;1;0;0;MAGE;1.0.0", "GUILD", "Garbage In")      -- not a number
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;2;1;1;1;0;0;MAGE;9.9.9", "GUILD", "Future Proto")    -- other protocol
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;1;1;1;0;0;MAGE;1.0.0", "WHISPER", "Whisper Guy")   -- wrong channel
M.fire("CHAT_MSG_ADDON", "OtherAddon", "S;1;1;1;1;0;0;MAGE;1.0.0", "GUILD", "Other Addon")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;500;500;500;0;0;MAGE;1.0.0", "GUILD", "Vesh Torchman") -- own echo
local board, guild = ns.Comm.Leaderboard()
eq(guild, "The True Torchmen", "leaderboard guild"); eq(#board, 3, "leaderboard rows")
eq(board[1].name, "Brakka Ashmane", "leader"); eq(board[2].name, "Vesh Torchman", "me second"); check(board[2].me, "me flagged")
eq(board[3].name, "Zul Embertusk", "third")
local before = #M.sentAddon
M.fire("CHAT_MSG_ADDON", "Godslayer", "H;1", "GUILD", "Brakka Ashmane"); M.advance(8)
check(#M.sentAddon == before + 1, "hello answered once with stats")
-- lockdown holds the broadcast and it goes out afterwards
M.lockdown = true; before = #M.sentAddon
M.units.target = asmon; M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, asmon.guid); M.advance(40)
eq(#M.sentAddon, before, "nothing sent during lockdown")
M.lockdown = false; M.advance(40)
check(#M.sentAddon > before and M.sentAddon[#M.sentAddon][2]:match("^S;1;8;20;"), "held broadcast sent after lockdown")
-- throttle result code also retries
M.addonResult = 3; before = #M.sentAddon
ns.Comm.MarkDirty(); M.advance(20); eq(#M.sentAddon, before, "throttled send not counted as sent")
M.addonResult = 0; M.advance(40); check(#M.sentAddon == before + 1, "retried after throttle")

-- 16. window, tabs, phrases, sharing -------------------------------------------
ns.UI.Toggle()
check(GodslayerFrame and GodslayerFrame:IsShown(), "window opens")
for tab = 1, 3 do GodslayerFrame.tabs[tab].__scripts.OnClick(); end
GodslayerFrame.list.__scripts.OnMouseWheel(nil, -1)
check(GodslayerFrame.rows[1].cells[2].__text:find("Brakka Ashmane", 1, true), "leaderboard row rendered")
GodslayerFrame.tabs[1].__scripts.OnClick()
check(GodslayerFrame.rows[1].cells[2].__text:find("Asmongold Asmongler", 1, true), "kill log sorted by points")
check(GodslayerFrame.summary.__text:find("Kills", 1, true), "summary rendered")

local function checkPhrases(label)
  local seenLines = {}
  for i = 1, 400 do
    GodslayerFrame.__scripts.OnShow(GodslayerFrame)
    local line = ns.UI.CurrentPhrase()
    seenLines[line] = true
    check(not line:find("[{}|]"), label .. ": no stray tokens: " .. line)
    check(#line <= 255, label .. ": fits in chat: " .. line)
    check(not line:find("[\128-\255]"), label .. ": plain ASCII: " .. line)
    check(not line:find("%f[%d]1 Olympus kills") and not line:find("%f[%d]1 points"), label .. ": plural ok: " .. line)
    local rerollButton
    for _, f in ipairs(M.frames) do if f.__text == "Another line" then rerollButton = f end end
    rerollButton.__scripts.OnClick()
  end
  local count = 0
  for _ in pairs(seenLines) do count = count + 1 end
  return count
end
eq(checkPhrases("8 kills"), #ns.PHRASES, "every line is reachable with kills, original kills, a regicide and dossier data")
check(#ns.PHRASES >= 65, "at least 65 lines shipped (" .. #ns.PHRASES .. ")")
check(#ns.PHRASES >= 30, "at least 30 lines shipped (" .. #ns.PHRASES .. ")")
for _, template in ipairs(ns.PHRASES) do check(#template <= 200, "template short enough: " .. template) end

M.sentChat = {}
ns.UI.Share()
eq(#M.sentChat, 1, "share posts one line"); eq(M.sentChat[1][2], "GUILD", "share goes to guild chat only")
ns.UI.Share()
eq(#M.sentChat, 1, "share is rate limited")
M.advance(20); ns.UI.ShareTop()
eq(#M.sentChat, 2, "top 3 posted")
check(M.sentChat[2][1]:find("1. Brakka Ashmane 22 pts (10 kills), 2. Vesh Torchman 20 pts (8 kills), 3. Zul Embertusk 3 pts (3 kills)", 1, true), "top 3 text: " .. M.sentChat[2][1])
M.advance(20); M.lockdown = true; ns.UI.Share(); eq(#M.sentChat, 2, "no chat during lockdown"); M.lockdown = false
M.inGuild = false; ns.UI.Share(); eq(#M.sentChat, 2, "no chat without a guild"); M.inGuild = true

-- 17. slash commands -----------------------------------------------------------
local slash = SlashCmdList["GODSLAYER"]
check(SLASH_GODSLAYER1 == "/godslayer", "slash registered")
for _, cmd in ipairs({ "help", "stats", "guilds", "demo", "log", "sound", "sound", "toast", "toast", "minimap", "minimap", "reset", "nonsense", "add", "" , "" }) do slash(cmd) end
eq(ns.errors, nil, "no handler errors so far")
for _, line in ipairs(M.printed) do check(not line:find("command failed", 1, true), "slash ok: " .. line) end
slash("ignore OLYMPUS BETZ")
eq(c.kills, 7, "ignore removes that guild's kills"); eq(ns.Classify("OLYMPUS BETZ"), nil, "ignored guild no longer matches")
slash("unignore OLYMPUS BETZ")
eq(c.kills, 8, "unignore restores them"); eq(c.points, 20, "points restored")
slash("add Method")
eq(ns.Classify("Method"), "network", "custom guild counts")
M.advance(20); M.units.target = rando; M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, rando.guid)
eq(c.kills, 9, "kill on a custom guild counts")
slash("remove Method"); eq(c.kills, 8, "removing the custom guild recounts")

-- 18. tooltip ------------------------------------------------------------------
local snapshot = {}
local function deep(t) local o = {} for k, v in pairs(t) do o[k] = type(v) == "table" and deep(v) or v end return o end

GameTooltip.__unit = "target"; GameTooltip.__lines = {}
M.units.target = asmon; M.tooltipHook(GameTooltip)
check(GameTooltip.__lines[1] and GameTooltip.__lines[1]:find("OLYMPUS, 5 points", 1, true), "tooltip tags the original guild")
check(GameTooltip.__lines[2] and GameTooltip.__lines[2]:find("killed them 3 times", 1, true), "tooltip shows kill count")
GameTooltip.__lines = {}; M.units.target = rando; M.tooltipHook(GameTooltip)
eq(#GameTooltip.__lines, 0, "tooltip silent on others")

snapshot = deep(c)
local sessionBefore = deep(ns.session)
-- 18a. deaths seen through health instead of UNIT_DIED, feign death, late deaths ---
M.advance(30); clearUnits()
do
  local k0 = c.kills
  local h1 = enemy("nameplate5", "Health Watch", "OLYMPUS WOW")
  M.fire("NAME_PLATE_UNIT_ADDED", "nameplate5")
  h1.dead = true; M.fire("UNIT_HEALTH", "nameplate5"); M.fire("UNIT_HEALTH", "nameplate5")
  hkCredit(); M.advance(10)
  eq(c.kills, k0 + 1, "death seen through health counts once")
  -- the death arrives several seconds after the credit
  M.advance(30)
  local h2 = enemy("nameplate6", "Slow Death", "OLYMPUS WOW"); M.fire("NAME_PLATE_UNIT_ADDED", "nameplate6")
  hkCredit(); M.advance(6); M.fire("UNIT_DIED", h2.guid); M.fire("UNIT_DIED", h2.guid); M.advance(10)
  eq(c.kills, k0 + 2, "late death still matched, duplicate event ignored")
  -- a corpse that was already dead when first seen is not a kill
  M.advance(30)
  local h3 = enemy("nameplate7", "Old Corpse", "OLYMPUS WOW", { dead = true }); M.fire("NAME_PLATE_UNIT_ADDED", "nameplate7")
  M.fire("UNIT_HEALTH", "nameplate7"); hkCredit(); M.advance(10)
  eq(c.kills, k0 + 2, "old corpse not counted")
  -- feign death is not a death
  M.advance(30)
  local h4 = enemy("nameplate8", "Feign Hunter", "OLYMPUS WOW"); M.fire("NAME_PLATE_UNIT_ADDED", "nameplate8")
  h4.dead, h4.feign = true, true; M.fire("UNIT_HEALTH", "nameplate8"); hkCredit(); M.advance(10)
  eq(c.kills, k0 + 2, "feign death not counted")
  -- with one credit and two deaths, the network member wins over a stranger
  M.advance(30); clearUnits()
  local s1 = enemy("nameplate1", "Some Stranger", "Method"); local s2 = enemy("nameplate2", "Net Member", "OLYMPUS WOW")
  M.fire("NAME_PLATE_UNIT_ADDED", "nameplate1"); M.fire("NAME_PLATE_UNIT_ADDED", "nameplate2")
  M.fire("UNIT_DIED", s2.guid); M.advance(1); M.fire("UNIT_DIED", s1.guid); hkCredit(); M.advance(10)
  eq(c.kills, k0 + 3, "network member preferred over a closer stranger")
  ns.ResetCharacter(); for k, v in pairs(snapshot) do c[k] = v end
  for k, v in pairs(sessionBefore) do ns.session[k] = v end
end

-- 18b. titles, streaks, regicide ------------------------------------------------
eq((ns.RankFor(0)), "Unlit Torch", "title at zero"); eq((ns.RankFor(1)), "Spark", "title at one")
eq((ns.RankFor(60)), "Thief of Fire", "title at 60"); eq((ns.RankFor(59)), "Temple Robber", "title just below 60")
eq((ns.RankFor(999999)), "Reason For The Mute Addon", "top title"); eq(select(3, ns.RankFor(999999)), nil, "no title after the top one")
eq(c.kings, 3, "regicides counted for the King in the original guild")
check(ns.IsKing("Asmongold Asmongler", "original") and not ns.IsKing("Asmongold Asmongler", "network") and not ns.IsKing("Asmongold Fake", "original"), "king needs the exact name and the original guild")
check(c.bestStreak >= 2, "best streak tracked (" .. tostring(c.bestStreak) .. ")")
check(ns.session.streak > 0, "streak running"); M.fire("PLAYER_DEAD"); eq(ns.session.streak, 0, "dying resets the streak")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;10;22;8;4;3;WARRIOR;1.0.0;2", "GUILD", "Brakka Ashmane")
M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;4;4;2;1;0;MAGE;|cffff0000x|r;9", "GUILD", "Pipe|cffff0000 Guy|r")
local board2 = ns.Comm.Leaderboard()
eq(board2[1].kings, 2, "regicides arrive over sync")
for _, r in ipairs(board2) do
  check(not r.name:find("|", 1, true), "no escape codes in roster names: " .. r.name)
  if r.name:find("Pipe", 1, true) then eq(r.kings, 0, "regicides cannot exceed original-guild kills") end
end
GodslayerFrame.tabs[3].__scripts.OnClick()
check(GodslayerFrame.rows[1].cells[2].__text:find("Kingslayer", 1, true), "kingslayer tag on the leaderboard")
check(GodslayerFrame.rows[1].cells[3].__text == "Blasphemer", "title column on the leaderboard: " .. tostring(GodslayerFrame.rows[1].cells[3].__text))
check(GodslayerFrame.status.__text:find("Title", 1, true) and GodslayerFrame.status.__text:find("Regicides", 1, true), "status line rendered")
ns.Comm.ForgetRoster()

-- 18c. the dossier: who they were, where, when ---------------------------------
do
  local A = c.victims[asmon.guid]
  eq(A.level, 60, "dossier: level"); eq(A.race, "Human", "dossier: race"); eq(A.sex, 2, "dossier: sex")
  eq(A.rank, "Guild Master", "dossier: guild rank"); eq(A.title, "Grand Marshal", "dossier: PvP title split from the name")
  eq(A.up, 30, "dossier: level gap"); eq(#A.hist, A.kills, "dossier: one history entry per kill")
  eq(A.hist[1][2], "Stranglethorn Vale", "history: zone"); eq(A.hist[1][3], "Nesingwary's Expedition", "history: subzone")
  eq(A.hist[1][4], 1, "history: killing blow flag"); eq(A.hist[1][5], 60, "history: their level"); eq(A.hist[1][6], 30, "history: our level")
  eq(A.zones["Stranglethorn Vale"], A.kills, "dossier: zone count"); eq(A.today, A.kills, "dossier: kills today")
  eq(A.dayBest, A.kills, "dossier: best day")
  local hourKills = 0
  for hour, n in pairs(A.hours) do check(hour >= 0 and hour <= 23, "hour in range"); hourKills = hourKills + n end
  eq(hourKills, A.kills, "dossier: every kill has an hour")
  -- the cook was an assist first and the killing blow arrived late: the history entry is upgraded too
  eq(c.victims[cook.guid].hist[1][4], 1, "late killing blow marks the history entry")
  eq(c.victims[cook.guid].level, nil, "a level the client reports as -1 is not kept")

  -- text helpers
  eq(ns.clean("  a|cffff0000b|r\n "), "acffff0000br", "clean strips pipes and control characters")
  eq(ns.clean(("x"):rep(39) .. "\195\177\195\177"), ("x"):rep(39), "clean never cuts a UTF-8 character in half")
  eq(ns.clean(M.secret()), nil, "clean on a secret"); eq(ns.clean(""), nil, "clean on nothing"); eq(ns.clean(5), nil, "clean on a number")

  -- a fresh victim: zone, day, run and guild changes
  local k0 = c.kills
  M.advance(30); clearUnits()
  M.zone, M.subzone, M.myLevel = "Hillsbrad Foothills", "Tarren Mill", 31
  local t1 = enemy("target", "Dossier Dummy", "OLYMPUS BETZ", { level = 29, race = "Dwarf", sex = 3, rank = "Captain", class = "PALADIN",
                                                              pvpName = "Dossier Dummy, Hand of the King" })
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", mate, t1.guid)
  local D = c.victims[t1.guid]
  eq(c.kills, k0 + 1, "dossier dummy scored"); eq(D.title, "Hand of the King", "title behind the name")
  eq(D.up, -2, "level gap can be negative"); eq(D.hist[1][4], 0, "an assist is recorded as one")
  eq(D.bestRun, 1, "run starts at one"); eq(D.sex, 3, "sex kept")
  local facts = table.concat(ns.UI.KillFacts(D, { first = true, zone = "Hillsbrad Foothills" }), " / ")
  eq(facts, "Level 29 Dwarf Paladin, Captain / Hillsbrad Foothills / First blood on this one", "first-kill facts")
  M.advance(30); M.zone = "Arathi Highlands"
  M.fire("PARTY_KILL", ME, t1.guid)
  eq(D.kills, 2, "second kill"); eq(D.today, 2, "second today"); eq(D.bestRun, 2, "two in one life")
  eq(D.zones["Arathi Highlands"], 1, "second zone counted"); eq(#D.hist, 2, "two history entries")
  check(table.concat(ns.UI.KillFacts(D, { zone = "Arathi Highlands" }), " / "):find("Second time today / Returning Customer", 1, true), "repeat facts")
  M.fire("PLAYER_DEAD"); M.advance(30)
  t1.guild, t1.rank = "OLYMPUS LXX", nil; t1.secretRank = true
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, t1.guid)
  eq(D.kills, 3, "third kill"); eq(D.bestRun, 2, "dying restarts the run, the record stays")
  eq(D.rank, nil, "a rank from the old guild is dropped when the new one is hidden"); eq(D.guild, "OLYMPUS LXX", "guild follows them")
  t1.secretRank = nil
  -- the next day
  M.advance(30); M.wall = M.wall + 86400
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, t1.guid)
  eq(D.today, 1, "a new day starts the daily count again"); eq(D.dayBest, 3, "best day kept")
  eq(ns.KillsToday(), 1, "kills today counts only today")

  -- every detail hidden by the client: the kill still counts and nothing is stored as garbage
  M.advance(30); clearUnits(); M.secretZone, M.secretMyLevel = true, true
  local t2 = enemy("target", "Hidden Details", "OLYMPUS", { level = 40, race = "Gnome", sex = 3, rank = "Lord", pvpName = "Knight Hidden Details",
    secretLevel = true, secretRace = true, secretSex = true, secretTitle = true, secretRank = true })
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, t2.guid)
  local Hd = c.victims[t2.guid]
  check(Hd and Hd.kills == 1, "kill with every detail secret still counts")
  check(Hd.level == nil and Hd.race == nil and Hd.sex == nil and Hd.rank == nil and Hd.title == nil and Hd.up == nil, "no secret detail is stored")
  eq(Hd.zones, nil, "no zone stored when the zone is hidden"); eq(Hd.hist[1][2], "", "history entry has an empty zone")
  eq(Hd.hist[1][5], 0, "history entry has no level"); eq(ns.errors, nil, "secret details raise no errors")
  M.secretZone, M.secretMyLevel = nil, nil
  check(#ns.UI.DossierLines(t2.guid) >= 6, "a dossier with gaps still renders")
  for _, line in ipairs(ns.UI.DossierLines(t2.guid)) do check(type(line[1]) == "string" and type(line[2]) == "string", "dossier lines are text") end

  -- a victim who was never on screen: race, sex and level come from the client's cache
  M.advance(30); clearUnits()
  local t3 = enemy("hidden", "Cache Only", nil, { level = 44, race = "Night Elf", sex = 3 }); M.units.hidden = nil
  GodslayerDB.known[t3.guid] = { n = "Cache Only", g = "OLYMPUS", c = "DRUID", t = time() } -- as 1.0.0 stored it
  M.fire("PARTY_KILL", ME, t3.guid)
  local Cv = c.victims[t3.guid]
  check(Cv and Cv.race == "Night Elf" and Cv.sex == 3 and Cv.level == 44, "details filled from the GUID cache")

  -- caps: history and zones stay bounded however long the feud runs
  M.advance(30); M.units.target = t1; M.fire("PLAYER_TARGET_CHANGED")
  local startKills = D.kills
  for i = 1, 40 do
    M.advance(20); M.zone = "Zone Number " .. i
    M.fire("PARTY_KILL", ME, t1.guid)
  end
  eq(D.kills, startKills + 40, "forty more kills"); eq(#D.hist, ns.HIST_CAP, "history capped")
  local zoneKeys, zoneKills = 0, 0
  for _, n in pairs(D.zones) do zoneKeys, zoneKills = zoneKeys + 1, zoneKills + n end
  check(zoneKeys <= ns.ZONE_CAP + 1, "zones capped (" .. zoneKeys .. ")"); eq(zoneKills, D.kills, "no kill lost to the zone cap")
  check(D.zones[ns.ELSEWHERE] and D.zones[ns.ELSEWHERE] > 0, "overflow zones are lumped together")
  eq(D.hist[#D.hist][2], "Zone Number 40", "newest kill is last in the history")
  M.zone = "Stranglethorn Vale"

  -- titles for repeat victims
  eq((ns.VictimTier(1)), "Fresh Sacrifice", "victim tier 1"); eq((ns.VictimTier(2)), "Returning Customer", "victim tier 2")
  eq((ns.VictimTier(7)), "Loyalty Card Holder", "victim tier 7"); eq(select(2, ns.VictimTier(7)), 8, "next victim tier")
  eq((ns.VictimTier(9999)), "Basically My Alt", "top victim tier"); eq(select(2, ns.VictimTier(9999)), nil, "nothing above the top")

  -- nemesis, aggregates, hit list
  local nem, nemId = ns.Nemesis()
  check(nem == D and nemId == t1.guid, "nemesis is the most killed")
  local a = ns.Aggregates()
  eq(a.kills, c.kills, "aggregate kills match the total")
  local byClass, byHour, byZone = 0, 0, 0
  for _, n in pairs(a.class) do byClass = byClass + n end
  for hour, n in pairs(a.hour) do byHour = byHour + n end
  for _, n in pairs(a.zone) do byZone = byZone + n end
  eq(byClass, c.kills, "every kill has a class here"); eq(byHour, a.timed, "hours add up"); eq(byZone, a.zoned, "zones add up")
  check(a.highest and a.highest.level == 60, "highest level kill"); check(a.upset and a.upset.up == 30, "biggest upset")
  check(a.rank["Guild Master"] == A.kills, "kills by guild rank")
  clearUnits()
  local h1 = enemy("nameplate1", "Still Breathing", "OLYMPUS", { level = 52, rank = "Lord" })
  local h2 = enemy("nameplate2", "Overflow Guy", "Olympus Kitchen", { level = 12 })
  M.fire("NAME_PLATE_UNIT_ADDED", "nameplate2"); M.advance(5); M.fire("NAME_PLATE_UNIT_ADDED", "nameplate1")
  local hit = ns.HitList()
  eq(hit[1].name, "Still Breathing", "hit list: original guild first"); eq(hit[1].level, 52, "hit list: level"); eq(hit[1].rank, "Lord", "hit list: rank")
  eq(hit[1].zone, "Stranglethorn Vale", "hit list: where they were seen")
  local onList = {}
  for _, k in ipairs(hit) do onList[k.name] = true end
  check(onList["Overflow Guy"] and not onList["Dossier Dummy"] and not onList["Asmongold Asmongler"], "hit list holds the unkilled only")
  check(ns.FindVictim("dossier dummy") == D and ns.FindVictim("Doss") == D and ns.FindVictim("") == nil and ns.FindVictim("zzz") == nil, "find a victim by name")

  -- window: click a kill log row, read the dossier, brag, go back
  GodslayerFrame.tabs[1].__scripts.OnClick()
  local row1 = GodslayerFrame.rows[1]
  check(row1.id ~= nil, "kill log rows carry the victim")
  local clicked = row1.id
  row1.__scripts.OnMouseUp(row1)
  check(GodslayerFrame.rows[1].cells[1].__text:find("Target", 1, true), "dossier opens on a click")
  check(GodslayerFrame.rows[1].cells[2].__text:find(c.victims[clicked].name, 1, true), "dossier is for the clicked player")
  eq(GodslayerFrame.rows[1].id, nil, "dossier rows are not clickable")
  GodslayerFrame.list.__scripts.OnMouseWheel(nil, -1); GodslayerFrame.list.__scripts.OnMouseWheel(nil, 1)
  local text = {}
  for _, line in ipairs(ns.UI.DossierLines(t1.guid)) do text[#text + 1] = line[1] .. " " .. line[2] end
  text = table.concat(text, "\n")
  for _, want in ipairs({ "Level 29 Dwarf Paladin", "Hand of the King", "OLYMPUS LXX", "Claimed As A Dependent", "killing blow", "Killing grounds",
                          "in one day", "in a row without you dying", "below you at best", "Usually dies around", "Zone Number 40", "your killing blow" }) do
    check(text:find(want, 1, true), "dossier mentions: " .. want)
  end
  M.advance(20); M.sentChat = {}
  check(ns.UI.ShareVictim(t1.guid), "dossier brag posts")
  eq(#M.sentChat, 1, "one line"); eq(M.sentChat[1][2], "GUILD", "to guild chat only")
  check(M.sentChat[1][1]:find("Dossier: Dossier Dummy <OLYMPUS LXX>, Level 29 Dwarf Paladin. Killed 44 times", 1, true), "dossier brag text: " .. M.sentChat[1][1])
  check(#M.sentChat[1][1] <= 255 and not M.sentChat[1][1]:find("[|{}]"), "dossier brag is chat safe")
  check(not ns.UI.ShareVictim(t1.guid), "dossier brag is rate limited with the others")
  check(not ns.UI.ShareVictim("Player-1-FFFFFFFF"), "no brag about a stranger")
  local back
  for _, f in ipairs(M.frames) do if f.__text == "Back" then back = f end end
  back.__scripts.OnClick()
  check(GodslayerFrame.rows[1].id ~= nil, "back returns to the kill log")
  check(not ns.UI.OpenDossier("Player-1-FFFFFFFF"), "no dossier for someone never killed")
  for tab = 4, 5 do GodslayerFrame.tabs[tab].__scripts.OnClick() end
  GodslayerFrame.tabs[4].__scripts.OnClick()
  check(GodslayerFrame.rows[1].cells[2].__text:find("Still Breathing", 1, true), "hit list tab rendered")
  GodslayerFrame.tabs[5].__scripts.OnClick()
  check(GodslayerFrame.rows[1].cells[1].__text:find("Records", 1, true) and GodslayerFrame.rows[2].cells[2].__text:find("Dossier Dummy", 1, true), "stats tab rendered with the nemesis")
  for _ = 1, 12 do GodslayerFrame.list.__scripts.OnMouseWheel(nil, -1) end
  GodslayerFrame.tabs[1].__scripts.OnClick()

  -- tooltip and slash commands with the new data
  GameTooltip.__unit = "target"; GameTooltip.__lines = {}; M.units.target = t1; M.tooltipHook(GameTooltip)
  check(GameTooltip.__lines[3] and GameTooltip.__lines[3]:find("Claimed As A Dependent. Last: now ago in Zone Number 40", 1, true), "tooltip title and last kill: " .. tostring(GameTooltip.__lines[3]))
  GameTooltip.__lines = {}; M.units.target = h1; M.tooltipHook(GameTooltip)
  check(GameTooltip.__lines[2] and GameTooltip.__lines[2]:find("hit list", 1, true), "tooltip marks the hit list")
  M.printed = {}
  for _, cmd in ipairs({ "dossier Dossier Dummy", "dossier doss", "dossier", "dossier nobody at all", "who Asmongold", "nemesis", "hitlist", "help", "demo" }) do slash(cmd) end
  local printed = table.concat(M.printed, "\n")
  check(printed:find("Claimed As A Dependent", 1, true) and printed:find("Still Breathing", 1, true) and printed:find("No kill on record", 1, true), "slash output")
  check(not printed:find("command failed", 1, true), "new slash commands do not fail")
  eq(ns.errors, nil, "no handler errors after the dossier tests")

  -- promotions: each kill keeps the rank they held when it happened
  M.advance(30); clearUnits()
  local climber = enemy("target", "Career Climber", "OLYMPUS", { level = 30, rank = "Recruit" })
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, climber.guid)
  M.advance(30); climber.rank = "Officer"
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, climber.guid)
  local ranks = ns.Aggregates().rank
  eq(ranks["Recruit"], 1, "the kill as a recruit stays a recruit kill"); eq(ranks["Officer"], 1, "the kill as an officer is an officer kill")
  eq(c.victims[climber.guid].rank, "Officer", "the dossier shows the latest rank")
  local rankLine
  for _, line in ipairs(ns.UI.DossierLines(climber.guid)) do if line[1]:find("Rank in that guild", 1, true) then rankLine = line[2] end end
  check(rankLine and rankLine:find("Officer", 1, true) and rankLine:find("also killed as Recruit", 1, true), "dossier lists earlier ranks: " .. tostring(rankLine))
  for i = 1, 12 do
    M.advance(20); climber.rank = "Rank " .. i
    M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, climber.guid)
  end
  local rankKeys, rankKills = 0, 0
  for _, n in pairs(c.victims[climber.guid].ranks) do rankKeys, rankKills = rankKeys + 1, rankKills + n end
  check(rankKeys <= ns.RANK_CAP + 1, "ranks per victim capped (" .. rankKeys .. ")"); eq(rankKills, 14, "no kill lost to the rank cap")

  -- a kill scored only after we died belongs to the life it happened in
  M.advance(30); clearUnits(); M.fire("PLAYER_DEAD")
  local late = enemy("hidden", "Tagged Late", "OLYMPUS"); M.units.hidden = nil
  local bestBefore = c.bestStreak
  M.fire("PARTY_KILL", ME, late.guid)              -- guild unknown: waits
  M.fire("PLAYER_DEAD")                             -- we die
  M.units.mouseover = late; M.fire("UPDATE_MOUSEOVER_UNIT") -- the tag shows on the corpse run: scored now
  eq(c.victims[late.guid].kills, 1, "late kill scored"); eq(ns.session.streak, 0, "it does not start a streak in the new life")
  M.advance(30); M.units.target = late; M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, late.guid)
  eq(c.victims[late.guid].kills, 2, "second kill after resurrecting")
  eq(c.victims[late.guid].bestRun, 1, "two kills split by our death are not a run of two"); eq(ns.session.streak, 1, "streak counts the new life only")
  eq(c.bestStreak, bestBefore, "best streak not inflated by the late kill")

  -- the sighting list holds its cap inside one long session
  M.advance(30); clearUnits()
  for i = 1, ns.KNOWN_CAP + 450 do
    M.wall = M.wall + 1
    M.units.nameplate9 = { name = "Raid Member" .. i, guid = ("Player-9-%08X"):format(i), guild = "OLYMPUS RAID", class = "WARRIOR", faction = "Alliance" }
    M.fire("NAME_PLATE_UNIT_ADDED", "nameplate9")
  end
  local knownNow = 0
  for _ in pairs(GodslayerDB.known) do knownNow = knownNow + 1 end
  check(knownNow <= ns.KNOWN_CAP, "sightings capped mid-session (" .. knownNow .. ")")
  check(GodslayerDB.known[("Player-9-%08X"):format(ns.KNOWN_CAP + 450)] and not GodslayerDB.known[("Player-9-%08X"):format(1)], "the oldest sightings go first")
  for id in pairs(GodslayerDB.known) do if id:sub(1, 9) == "Player-9-" then GodslayerDB.known[id] = nil end end
  M.units.nameplate9 = nil

  -- a broken clock costs the time-of-day detail, not the kill
  M.advance(30); M.dateError = true
  local before = c.kills
  M.units.target = t1; M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, t1.guid)
  eq(c.kills, before + 1, "kill counts without a working date()")
  M.dateError = nil
end

-- 19. zero state and reset ------------------------------------------------------
slash("reset confirm")
eq(c.kills, 0, "reset wipes kills"); eq(next(c.victims), nil, "reset wipes victims")
check(ns.UI.CurrentPhrase():find("0") or ns.UI.CurrentPhrase():find("No Olympus") or ns.UI.CurrentPhrase():find("Zero"), "zero-kill line used")
M.advance(20); M.units.target = cook; M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, cook.guid)
eq(c.kills, 1, "counting resumes after reset")
checkPhrases("1 kill")

-- 20. saved data survives a reload ----------------------------------------------
local saved = GodslayerDB
M.frames, M.timers = { UIParent, Minimap, GameTooltip }, {}
GodslayerFrame, GodslayerMinimapButton = nil, nil
local ns2 = M.load("Godslayer", { "Data.lua", "Core.lua", "Comm.lua", "UI.lua" })
M.fire("ADDON_LOADED", "Godslayer"); M.fire("PLAYER_LOGIN")
check(GodslayerDB == saved and ns2.char.kills == 1, "totals reload from saved variables")
eq(GodslayerDB.version, 2, "data version")

-- 21. a database written by 1.0.0 loads unchanged and gains details from then on ---
do
  GodslayerDB = {
    version = 1, log = { "10-07 23:33:03 login: Old Timer v1.0.0 build 1.60.1" }, roster = {}, ignore = {}, custom = {},
    opts = { minimapAngle = -173.67, minimap = true, toast = true, tooltip = true, sound = true, chat = true },
    known = { ["Player-1-0000F001"] = { c = "SHAMAN", t = time() - 3600, g = "OLYMPUS EVICTION NOTICE", n = "Old Sighting" } },
    chars = { ["Vesh Torchman"] = { uniques = 1, kb = 1, class = "MAGE", orig = 2, kills = 2, points = 10, kings = 0, bestStreak = 2,
      guilds = { OLYMPUS = { kills = 2, points = 10, tier = "original" } },
      victims = { ["Player-1-0000F002"] = { kills = 2, points = 10, kb = 1, ok = 2, first = time() - 9000, last = time() - 600,
                                            guild = "OLYMPUS", tier = "original", name = "Old Victim", class = "ROGUE" } } } },
  }
  M.frames, M.timers = { UIParent, Minimap, GameTooltip }, {}
  GodslayerFrame, GodslayerWindow, GodslayerMinimapButton, M.failTemplate = nil, nil, nil, nil
  local ns3 = M.load("Godslayer", { "Data.lua", "Core.lua", "Comm.lua", "UI.lua" })
  M.fire("ADDON_LOADED", "Godslayer"); M.fire("PLAYER_LOGIN")
  local c3 = ns3.char
  eq(GodslayerDB.version, 2, "old data is marked as migrated"); eq(c3.kills, 2, "old kills kept"); eq(c3.points, 10, "old points kept")
  local old = c3.victims["Player-1-0000F002"]
  check(old.kills == 2 and old.name == "Old Victim" and old.hist == nil, "old victim untouched")
  local lines = ns3.UI.DossierLines("Player-1-0000F002")
  local joined = ""
  for _, line in ipairs(lines) do joined = joined .. line[1] .. " " .. line[2] .. "\n" end
  check(joined:find("from before version 1.1", 1, true) and joined:find("Returning Customer", 1, true), "old victim has a dossier that says what is missing")
  eq(#ns3.HitList(), 1, "old sightings feed the hit list"); eq(ns3.HitList()[1].level, nil, "with no level yet")
  ns3.UI.Toggle()
  for tab = 1, 5 do GodslayerFrame.tabs[tab].__scripts.OnClick() end
  ns3.UI.OpenDossier("Player-1-0000F002")
  local a3 = ns3.Aggregates()
  eq(a3.kills, 2, "aggregates work on old records"); eq(a3.zoned, 0, "old kills have no zone")
  for i = 1, 60 do ns3.UI.CurrentPhrase(); for _, f in ipairs(M.frames) do if f.__text == "Another line" then f.__scripts.OnClick() end end end
  M.advance(30)
  M.addUnit("target", { name = "Old Victim", guid = "Player-1-0000F002", guild = "OLYMPUS", class = "ROGUE", faction = "Alliance", level = 33, race = "Gnome" })
  M.fire("PLAYER_TARGET_CHANGED"); M.fire("PARTY_KILL", ME, "Player-1-0000F002")
  eq(old.kills, 3, "an old victim can be killed again"); eq(#old.hist, 1, "and starts a history"); eq(old.level, 33, "and gains a level")
  eq(old.zones["Stranglethorn Vale"], 1, "and a zone"); eq(c3.points, 15, "points carry on from the old total")
  eq(ns3.errors, nil, "no errors on migrated data")
  -- an old client's stats message is still understood, and ours still fits its parser
  M.fire("CHAT_MSG_ADDON", "Godslayer", "S;1;3;7;2;1;1;ROGUE;1.0.0;0;abc123", "GUILD", "Brakka Ashmane")
  eq(ns3.Comm.Leaderboard()[1].points, 15, "we lead"); eq(ns3.Comm.Leaderboard()[2].name, "Brakka Ashmane", "a 1.0.0 guildmate still shows on the board")
  M.advance(60)
  local mine
  for _, m in ipairs(M.sentAddon) do if m[2]:match("^S;1;") then mine = m[2] end end
  local fields = { strsplit(";", mine) }
  eq(#fields, 11, "our stats message keeps the 1.0.0 field count")

  -- thousands of victims: only the newest feuds keep kill-by-kill history, every total stays
  local victims, extra = c3.victims, ns3.DETAIL_CAP + 120
  for i = 1, extra do
    victims["Player-7-" .. i] = { kills = 1, points = 1, kb = 0, first = 1791000000 + i, last = 1791000000 + i, guild = "Olympus Kitchen",
                                  tier = "network", name = "Crowd " .. i, hist = { { 1791000000 + i, "Zone", "", 0, 0, 0 } }, zones = { Zone = 1 } }
  end
  ns3.Recount()
  local killsBefore = c3.kills
  M.fire("PLAYER_LOGIN")
  local withHistory = 0
  for _, v in pairs(victims) do if v.hist then withHistory = withHistory + 1 end end
  eq(withHistory, ns3.DETAIL_CAP, "kill-by-kill history kept for the newest feuds only")
  check(victims["Player-7-1"].hist == nil and victims["Player-7-1"].kills == 1 and victims["Player-7-1"].zones.Zone == 1, "the oldest keep totals and zones")
  check(victims["Player-7-" .. extra].hist ~= nil and old.hist ~= nil, "the newest keep their history")
  eq(c3.kills, killsBefore, "no kill lost to compaction")
end
-- fallback window when the frame template is missing
M.failTemplate = true; ns2.UI.Toggle()
check(GodslayerWindow and GodslayerWindow:IsShown(), "window falls back without the template")
eq(ns2.errors, nil, "no errors after reload")

for _, line in ipairs(GodslayerDB.log) do if line:find(" error: ", 1, true) then check(false, "logged error: " .. line) end end
M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
