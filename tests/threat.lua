-- Godslayer's shared threat pool: lua tests/threat.lua
--
-- The thing under test here is a trust boundary. Everything in this pool arrives over the addon
-- channel from another copy of the addon, which means the only thing guaranteeing a field is a
-- name and not a chat escape code is this file's own sanitising. So the suite feeds it the shapes
-- a hostile sender would: semicolons, pipes, control characters, a name longer than the cap,
-- counts for players who do not exist, and its own token echoed back.
--
-- The other thing under test is the vouching. `C_DeathRecap` names the caster of every hit and it
-- names mobs as happily as players, so a bare name off the recap is not enough to put in a pool
-- the whole guild reads. A death nothing can confirm has to be dropped, counted, and the count
-- has to be visible -- a silent drop is the bug you never find.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end

local ME = "Player-1-0000AAAA"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen",
                      class = "MAGE", race = "Scourge", sex = 2, faction = "Horde", isMe = true })
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua",
                "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua",
                "Control.lua", "Death.lua", "Threat.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local T = ns.Threat
local GUILD = "The True Torchmen"
local function say(text) SlashCmdList["GODSLAYER"](text) end
local function printed() return table.concat(M.printed, "\n") end
local function wipe() M.printed = {} end
local function lines(rest) return table.concat(T.Lines(rest), "\n") end

-- Pull the proto and token straight off a real stats message rather than hard-coding them: the
-- token is random per session and a hard-coded proto would stop testing anything the day it moves.
M.sentAddon = {}
ns.Comm.MarkDirty()
M.advance(10)
local PROTO, TOKEN
for _, m in ipairs(M.sentAddon) do
  local kind, proto, _, _, _, _, _, _, _, _, tag = strsplit(";", m[2])
  if kind == "S" then PROTO, TOKEN = proto, tag end
end
check(PROTO ~= nil, "a stats message went out so the proto is readable")
check(TOKEN ~= nil and #TOKEN == 6, "and it carries this session's token")

local function heard(from, body)
  M.fire("CHAT_MSG_ADDON", "Godslayer", body, "GUILD", from)
end
local function report(from, name, class, guild, zone)
  heard(from, table.concat({ "K", PROTO, name, class or "", guild or "", zone or "", "ffffff" }, ";"))
end

-- ---------------------------------------------------------------------------
-- 1. An empty pool says so
-- ---------------------------------------------------------------------------
eq(T.Of("Sir Problem"), nil, "nobody is in the pool yet")
eq(T.Clause("Sir Problem"), nil, "and there is no clause for a name that is not in it")
check(lines(""):find("Nothing pooled yet", 1, true), "the empty report says nothing is pooled")
check(lines("guilds"):find("No guild has been read", 1, true), "and so does the guild cut of it")

-- ---------------------------------------------------------------------------
-- 2. A death nothing can vouch for is dropped, counted and visible
-- ---------------------------------------------------------------------------
eq(T.Unvouched(), 0, "no drops yet")
local ok, why = T.Note("Venomtail Scorpid")
eq(ok, false, "a name nothing knows is not recorded")
eq(why, "unvouched", "and it says why")
eq(T.Unvouched(), 1, "the drop is counted")
eq(T.Of("Venomtail Scorpid"), nil, "it is not in the pool")
M.sentAddon = {}
M.advance(20)
local sentAny = false
for _, m in ipairs(M.sentAddon) do if m[2]:sub(1, 2) == "K;" then sentAny = true end end
eq(sentAny, false, "and nothing about it went to the guild")

-- ---------------------------------------------------------------------------
-- 3. A hostile player who has been on screen is vouched for, and `seen` fills the blanks
-- ---------------------------------------------------------------------------
M.addUnit("target", { name = "Sir Problem", guid = "Player-1-0000C001", guild = "Olympus",
                      class = "PALADIN", race = "Human", sex = 2, faction = "Alliance" })
M.fire("PLAYER_TARGET_CHANGED")
local e = ns.SeenByName("Sir Problem")
check(type(e) == "table", "the name bridge finds a unit we have looked at")
eq(e and e.class, "PALADIN", "with its class")
eq(e and e.guild, "Olympus", "and its guild")
eq(e and e.hostile, true, "and the hostile flag that does the vouching")

M.sentAddon = {}
eq(T.Note("Sir Problem", nil, nil, "Warsong Gulch"), true, "a death to them is recorded")
local r = T.Of("Sir Problem")
check(type(r) == "table", "and lands in the pool")
eq(r and r.n, 1, "one death")
eq(r and r.mine, 1, "it was yours")
eq(r and r.class, "PALADIN", "the class came off `seen`, not off the call")
eq(r and r.g, "Olympus", "and so did the guild")
eq(r and r.z, "Warsong Gulch", "the zone came off the call")
eq(r and r.who["Vesh Torchman"], 1, "and you are the one it happened to")

-- ---------------------------------------------------------------------------
-- 4. It goes out on the wire, in the documented shape
-- ---------------------------------------------------------------------------
M.advance(20)
local wire
for _, m in ipairs(M.sentAddon) do if m[2]:sub(1, 2) == "K;" then wire = m end end
check(wire ~= nil, "a threat message went to the guild")
eq(wire and wire[1], "Godslayer", "on the addon prefix")
eq(wire and wire[3], "GUILD", "on the guild channel, not the group's")
local kind, proto, a, b, c, d, tok = strsplit(";", wire and wire[2] or "")
eq(kind, "K", "kind K")
eq(proto, PROTO, "the current proto")
eq(a, "Sir Problem", "the killer")
eq(b, "PALADIN", "their class")
eq(c, "Olympus", "their guild")
eq(d, "Warsong Gulch", "and where")
eq(tok, TOKEN, "stamped with our token so our own echo is dropped")

-- ---------------------------------------------------------------------------
-- 5. One per life. A second death in the same life is not a second report.
-- ---------------------------------------------------------------------------
local before = T.Of("Sir Problem").n
eq(T.Note("Sir Problem"), false, "the same life does not record twice")
eq(T.Of("Sir Problem").n, before, "so the count holds")
ns.session.life = ns.session.life + 1
eq(T.Note("Sir Problem"), true, "the next life records again")
eq(T.Of("Sir Problem").n, before + 1, "and the count moves")

-- ---------------------------------------------------------------------------
-- 6. Our own echo is dropped
-- ---------------------------------------------------------------------------
local mine = T.Of("Sir Problem").n
heard("Someone Else", table.concat({ "K", PROTO, "Sir Problem", "PALADIN", "Olympus", "x", TOKEN }, ";"))
eq(T.Of("Sir Problem").n, mine, "a message carrying our own token is our own, and is ignored")

-- ---------------------------------------------------------------------------
-- 7. A guildmate's report folds in; the pool itself then vouches for the name
-- ---------------------------------------------------------------------------
report("Emberjack", "Grimnight", "WARLOCK", "Olympus", "Arathi Basin")
local g = T.Of("Grimnight")
check(type(g) == "table", "a guildmate's report lands")
eq(g and g.n, 1, "one death")
eq(g and g.mine, 0, "none of them yours")
eq(g and g.who["Emberjack"], 1, "credited to them")
-- Grimnight has never been on our screen and is not in our dossier. The pool is now the thing
-- that vouches, which is the whole point of pooling: the seventh of us does not start from zero.
eq(ns.SeenByName("Grimnight"), nil, "we have never seen them")
ns.session.life = ns.session.life + 1
eq(T.Note("Grimnight"), true, "and a death to them is still recorded, on the pool's word")
eq(T.Of("Grimnight").n, 2, "two now")
eq(T.Of("Grimnight").mine, 1, "one of them yours")

-- ---------------------------------------------------------------------------
-- 8. Spread beats raw count: nine of us once each is worse than one of us nine times
-- ---------------------------------------------------------------------------
for i = 1, 9 do report("Emberjack", "Grudge", "ROGUE", "Olympus", "Alterac Valley") end
for _, who in ipairs({ "Tallow", "Wickline", "Rushbrand", "Emberjack" }) do
  report(who, "Everyone", "HUNTER", "Olympus", "Alterac Valley")
end
local rows = T.List()
eq(rows[1] and rows[1].name, "Everyone", "the name that has taken the most of us is first")
eq(rows[1] and rows[1].spread, 4, "four separate Torchmen")
eq(rows[1] and rows[1].n, 4, "four deaths")
local grudge
for _, row in ipairs(rows) do if row.name == "Grudge" then grudge = row end end
eq(grudge and grudge.n, 9, "the grudge has nine deaths")
eq(grudge and grudge.spread, 1, "but only one of us")
check(rows[1].name ~= "Grudge", "and nine deaths to one person does not take the top")

-- ---------------------------------------------------------------------------
-- 9. The wire is sanitised: escape codes, field separators, control characters, over-long names
-- ---------------------------------------------------------------------------
report("Emberjack", "|cffff0000Fake|r", "ROGUE", "Olympus", "x")
eq(T.Of("|cffff0000Fake|r"), nil, "a name with escape codes in it is not stored as written")
local stripped = T.Of("cffff0000Faker")
check(type(stripped) == "table", "the codes are stripped and the rest kept")
report("Emberjack", "Bad\1Name", "ROGUE", "Olympus", "x")
check(T.Of("BadName") ~= nil, "control characters are removed")
local long = string.rep("N", 80)
report("Emberjack", long, "ROGUE", "Olympus", "x")
eq(T.Of(long), nil, "a name past the cap is not stored at its full length")
check(T.Of(string.rep("N", 32)) ~= nil, "it is stored truncated to the cap")
-- A class token is uppercase letters and nothing else; anything else is simply absent, so the
-- report prints "?" rather than whatever arrived.
report("Emberjack", "Mixedcase", "Rogue7", "Olympus", "x")
eq(T.Of("Mixedcase").class, nil, "a class that is not a plain class token is dropped")

-- ---------------------------------------------------------------------------
-- 10. A message on the wrong proto, or the wrong channel, is not ours
-- ---------------------------------------------------------------------------
local n = #T.List()
heard("Emberjack", table.concat({ "K", tonumber(PROTO) + 1, "Wrongproto", "", "", "", "ffffff" }, ";"))
eq(T.Of("Wrongproto"), nil, "a different proto is ignored")
M.fire("CHAT_MSG_ADDON", "Godslayer",
       table.concat({ "K", PROTO, "Wrongchannel", "", "", "", "ffffff" }, ";"), "PARTY", "Emberjack")
eq(T.Of("Wrongchannel"), nil, "and so is a threat report shouted at the party")
M.fire("CHAT_MSG_ADDON", "SomethingElse",
       table.concat({ "K", PROTO, "Wrongprefix", "", "", "", "ffffff" }, ";"), "GUILD", "Emberjack")
eq(T.Of("Wrongprefix"), nil, "and another addon's prefix")
eq(#T.List(), n, "none of the three got in")

-- ---------------------------------------------------------------------------
-- 11. Finding a name: short form, and any capitalisation
-- ---------------------------------------------------------------------------
check(T.Of("sir problem") ~= nil, "a name is found whatever the capitalisation")
check(T.Of("Sir Problem-Doomhowl") ~= nil, "and with a realm suffix on it")
eq((select(2, T.Of("sir problem"))), "Sir Problem", "the stored spelling comes back, not the one asked for")

-- ---------------------------------------------------------------------------
-- 12. The clause other modules borrow
-- ---------------------------------------------------------------------------
-- One name, only you: it says you, because "1 of us" when the one is you reads like a stranger.
report("Vesh Torchman", "Solo Act", "MAGE", "Olympus", "x")   -- echoes of our own name are dropped
ns.session.life = ns.session.life + 1
M.addUnit("target", { name = "Solo Act", guid = "Player-1-0000C009", guild = "Olympus",
                      class = "MAGE", faction = "Alliance" })
M.fire("PLAYER_TARGET_CHANGED")
T.Note("Solo Act")
local solo = T.Of("Solo Act")
eq(solo and solo.mine, solo and solo.n, "every death to them is yours")
check(T.Clause("Solo Act"):find("killed you", 1, true), "so the clause says you")
check(T.Clause("Everyone"):find("4 of us", 1, true), "and a shared one says how many of us")

-- ---------------------------------------------------------------------------
-- 13. The reports read
-- ---------------------------------------------------------------------------
local all = lines("")
check(all:find("Who the guild keeps dying to", 1, true), "the pool report has a heading")
check(all:find("Everyone", 1, true), "and names the worst")
check(all:find("Paladin", 1, true), "classes print pretty, not as tokens")
check(not all:find("%%"), "and nothing prints a stray percent sign")
check(all:find("had a killer nothing could confirm", 1, true), "the dropped death is reported, not hidden")

local one = lines("Sir Problem")
check(one:find("Paladin", 1, true), "one name carries its class")
check(one:find("<Olympus>", 1, true), "and its guild")
check(one:find("You:", 1, true), "and what it has cost you")
check(one:find("killed them 0 times", 1, true), "and that you have not paid them back")
check(lines("Nobody At All"):find("has killed any of us", 1, true), "a name not in the pool says so")

local guilds = lines("guilds")
check(guilds:find("Which guild is actually beating us", 1, true), "the guild cut has a heading")
check(guilds:find("<Olympus>", 1, true), "and names the guild")

-- ---------------------------------------------------------------------------
-- 14. Under your cursor, once
-- ---------------------------------------------------------------------------
wipe()
M.addUnit("target", { name = "Everyone", guid = "Player-1-0000C00E", guild = "Olympus",
                      class = "HUNTER", faction = "Alliance" })
M.fire("PLAYER_TARGET_CHANGED")
check(printed():find("Everyone", 1, true), "targeting someone the guild has died to says so")
check(printed():find("4 of us", 1, true), "with the count")
wipe()
M.fire("PLAYER_TARGET_CHANGED")
eq(printed(), "", "and does not say it again a second later")
wipe()
M.addUnit("target", { name = "Harmless", guid = "Player-1-0000C0FF", guild = "Olympus",
                      class = "HUNTER", faction = "Alliance" })
M.fire("PLAYER_TARGET_CHANGED")
eq(printed():find("has killed", 1, true), nil, "and says nothing about a name that is not pooled")

-- ---------------------------------------------------------------------------
-- 15. Where it pays off: the battleground scoreboard
-- ---------------------------------------------------------------------------
local them = { { name = "Everyone", rank = 9, class = "HUNTER" },
               { name = "Nobody Pooled", rank = 3, class = "MAGE" },
               { name = "Sir Problem", rank = 11, class = "PALADIN" } }
local feared = ns.Field.Feared(them)
eq(#feared, 2, "two names on that side are in the pool")
eq(feared[1] and feared[1].name, "Everyone", "the one that has taken the most of us first")
eq(feared[1] and feared[1].spread, 4, "with the spread")
eq(ns.Field.Feared({ { name = "Nobody Pooled", rank = 1 } })[1], nil, "and a clean side reads clean")

-- ---------------------------------------------------------------------------
-- 16. Where it pays off: the death card
-- ---------------------------------------------------------------------------
M.death({ { event = "SPELL_DAMAGE", spellName = "Judgement", caster = "Everyone", amount = 900,
            currentHP = 0, timestamp = M.now, deadly = true },
          { event = "SPELL_DAMAGE", spellName = "Crusader Strike", caster = "Everyone", amount = 400,
            currentHP = 900, timestamp = M.now - 2 } }, 1300)
local card = ns.Death.Read()
check(type(card) == "table", "the recap reads")
eq(card and card.killer and card.killer.name, "Everyone", "and names who did the damage")
local dl = table.concat(ns.Death.Lines(card, 5), "\n")
check(dl:find("Everyone has killed 4 of us", 1, true), "the death card says what the guild knows about them")

-- ---------------------------------------------------------------------------
-- 17. The recap feeds the pool, and vouches for nothing it should not
-- ---------------------------------------------------------------------------
ns.session.life = ns.session.life + 1
local was = T.Of("Everyone").n
M.fire("PLAYER_DEAD")
M.advance(1)
eq(T.Of("Everyone").n, was + 1, "dying to them through the recap adds to the pool")
-- Now a death to a mob. The recap is just as happy to name one, and the pool must not take it.
ns.session.life = ns.session.life + 1
M.death({ { event = "SPELL_DAMAGE", spellName = "Poison", caster = "Venomtail Scorpid", amount = 900,
            currentHP = 0, timestamp = M.now, deadly = true } }, 900)
local drops = T.Unvouched()
M.fire("PLAYER_DEAD")
M.advance(1)
eq(T.Of("Venomtail Scorpid"), nil, "dying to a mob does not put the mob in the guild's threat pool")
eq(T.Unvouched(), drops + 1, "it is counted as a drop instead")

-- ---------------------------------------------------------------------------
-- 18. Caps hold. A pool that grows without a ceiling is a corrupt saved variables file.
-- ---------------------------------------------------------------------------
for i = 1, 260 do report("Emberjack", "Filler" .. i, "ROGUE", "Olympus", "x") end
local pool = T.Pool()
local count = 0
for _ in pairs(pool) do count = count + 1 end
check(count <= 200, "the pool is capped (" .. count .. " names)")
for i = 1, 40 do report("Reporter" .. i, "Popular", "ROGUE", "Olympus", "x") end
local who = 0
for _ in pairs(T.Of("Popular").who) do who = who + 1 end
check(who <= 24, "and so is the list of who one name has taken (" .. who .. ")")
eq(T.Of("Popular").n, 40, "while the total count is still every one of them")

-- ---------------------------------------------------------------------------
-- 19. The rung rides on the stats message without breaking the old layout
-- ---------------------------------------------------------------------------
M.sentAddon = {}
ns.Comm.MarkDirty()
M.advance(40)
local stats
for _, m in ipairs(M.sentAddon) do if m[2]:sub(1, 2) == "S;" then stats = m[2] end end
check(stats ~= nil, "a stats message goes out")
local f = { strsplit(";", stats or "") }
eq(f[1], "S", "kind S")
eq(f[11], TOKEN, "the token is still the eleventh field, which is what an older copy reads")
check(f[12] ~= nil, "and the rung is appended after it")
-- Our own rung, read off the major faction the ladder lives on.
eq(tonumber(f[12]), ns.Rank.Level(), "and it is the rung the ladder reports")

-- A guildmate's rung lands on their roster row and on the leaderboard.
local other = table.concat({ "S", PROTO, 40, 120, 30, 10, 20, "WARLOCK", "2.6.0", 2, "ffffff", 9 }, ";")
heard("Emberjack", other)
eq(GodslayerDB.roster[GUILD] and GodslayerDB.roster[GUILD]["Emberjack"]
   and GodslayerDB.roster[GUILD]["Emberjack"].rung, 9, "their rung is kept")
local board = ns.Comm.Leaderboard()
local row
for _, b in ipairs(board) do if b.name == "Emberjack" then row = b end end
eq(row and row.rung, 9, "and reaches the leaderboard")
-- Fifteen is not a rung on this ladder, so it is not kept rather than shown as one.
heard("Tallow", table.concat({ "S", PROTO, 1, 5, 1, 0, 1, "PRIEST", "2.6.0", 0, "ffffff", 15 }, ";"))
eq(GodslayerDB.roster[GUILD]["Tallow"].rung, nil, "a rung outside the fourteen is dropped")
-- An older copy sends eleven fields and nothing breaks.
heard("Wickline", table.concat({ "S", PROTO, 3, 9, 2, 1, 1, "DRUID", "2.5.0", 0, "ffffff" }, ";"))
eq(GodslayerDB.roster[GUILD]["Wickline"].kills, 3, "a message with no rung on it still lands")
eq(GodslayerDB.roster[GUILD]["Wickline"].rung, nil, "with no rung")

-- ---------------------------------------------------------------------------
-- 20. Decay and forgetting
-- ---------------------------------------------------------------------------
-- Two fresh names rather than ones from earlier sections: the cap test above evicted by
-- last-seen, and asserting on a survivor of that would be asserting on the sort's tie-break.
report("Emberjack", "Ancient Terror", "ROGUE", "Olympus", "x")
report("Emberjack", "Current Terror", "ROGUE", "Olympus", "x")
T.Of("Ancient Terror").t = 0   -- as far back as the clock goes
T.Init()
eq(T.Of("Ancient Terror"), nil, "a name nobody has died to in three weeks is dropped on load")
check(T.Of("Current Terror") ~= nil, "a recent one is kept")
wipe()
say("threat forget")
check(printed():find("Threat pool emptied", 1, true), "forget says so")
eq(T.Of("Current Terror"), nil, "and the pool is gone")
check(lines(""):find("Nothing pooled yet", 1, true), "back to the empty report")

-- ---------------------------------------------------------------------------
-- 21. The command is wired up, and the help mentions it
-- ---------------------------------------------------------------------------
wipe()
say("threat")
check(printed():find("Nothing pooled yet", 1, true), "/godslayer threat runs")
wipe()
say("help")
check(printed():find("/godslayer threat", 1, true), "and the help lists it")

M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
