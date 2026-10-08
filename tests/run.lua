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
local asmon = enemy("target", "Asmongold Asmongler", "OLYMPUS")
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
check(sawStats and sawStats:match("^S;1;7;15;6;4;2;MAGE;1%.0%.0;2;%x%x%x%x%x%x$"), "stats payload: " .. tostring(sawStats))
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
check(checkPhrases("8 kills") >= 50, "all 50+ lines reachable with kills, original kills and a regicide")
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
-- fallback window when the frame template is missing
M.failTemplate = true; ns2.UI.Toggle()
check(GodslayerWindow and GodslayerWindow:IsShown(), "window falls back without the template")
eq(ns2.errors, nil, "no errors after reload")

for _, line in ipairs(GodslayerDB.log) do if line:find(" error: ", 1, true) then check(false, "logged error: " .. line) end end
M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
