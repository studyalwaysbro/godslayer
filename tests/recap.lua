-- Offline tests for the recap: lua tests/recap.lua   (from the project root, Lua 5.1)
-- The engine's own damage meter, read after the fight, because in combat it answers in secrets.
package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local passed, failed = 0, 0
local function check(cond, label)
  if cond then passed = passed + 1 else failed = failed + 1; M.realPrint("FAIL: " .. label) end
end
local function eq(a, b, label) check(a == b, label .. " (got " .. tostring(a) .. ", want " .. tostring(b) .. ")") end
local function near(a, b, label) check(type(a) == "number" and math.abs(a - b) < 0.01, label .. " (got " .. tostring(a) .. ", want ~" .. tostring(b) .. ")") end

local ME, FOE = "Player-1-0000AAAA", "Player-1-0000BBBB"
M.addUnit("player", { name = "Vesh Torchman", guid = ME, guild = "The True Torchmen", class = "MAGE",
                      race = "Scourge", sex = 2, faction = "Horde", isMe = true })
M.spells = { [11366] = "Pyroblast", [133] = "Fireball", [2948] = "Scorch", [348] = "Immolate" }
local FILES = { "Data.lua", "Pvp.lua", "Core.lua", "Voice.lua", "Stage.lua", "Clip.lua", "Hype.lua",
                "Fight.lua", "Aura.lua", "Ledger.lua", "Rank.lua", "Recap.lua", "Field.lua", "Control.lua", "Death.lua", "Comm.lua",
                "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")

local R, H = ns.Recap, ns.Hype
check(R ~= nil, "the recap part loaded")
H.Opts().pack = "titan"

local CURRENT = Enum.DamageMeterSessionType.Current
local DONE, HEAL = Enum.DamageMeterType.DamageDone, Enum.DamageMeterType.HealingDone
local TAKEN, AVOID = Enum.DamageMeterType.DamageTaken, Enum.DamageMeterType.AvoidableDamageTaken

local function title() return GodslayerHypeBanner and GodslayerHypeBanner.title.__text end
local function clearBanner() if GodslayerHypeBanner then GodslayerHypeBanner.title.__text = nil end end

-- One fight, laid out the way the engine lays it out: a session per kind of number, a row per
-- unit, and the spells hanging off one unit's row.
local function layOutAFight()
  M.clearMeter()
  M.session(CURRENT, DONE, {
    { guid = ME,  name = "Vesh Torchman", class = "MAGE",    amount = 18420, ps = 612, mine = true,
      side = Enum.DamageMeterSourceDisplayType.Ally },
    { guid = FOE, name = "Gnomechomsky",  class = "WARLOCK", amount = 12100, ps = 403,
      side = Enum.DamageMeterSourceDisplayType.Enemy, faction = "Alliance" },
  }, 30)
  M.session(CURRENT, TAKEN, { { guid = ME, mine = true, amount = 9600, ps = 320,
      side = Enum.DamageMeterSourceDisplayType.Ally } })
  M.session(CURRENT, HEAL, { { guid = ME, mine = true, amount = 3200,
      side = Enum.DamageMeterSourceDisplayType.Ally } })
  M.session(CURRENT, AVOID, { { guid = ME, mine = true, amount = 1400,
      side = Enum.DamageMeterSourceDisplayType.Ally } })
  M.meterSpells(CURRENT, DONE, ME, {
    { id = 11366, amount = 7000, ps = 233, overkill = 900 },
    { id = 133,   amount = 6000 },
    { id = 2948,  amount = 5420 },
  })
  M.meterSpells(CURRENT, TAKEN, ME, {
    { id = 686,   amount = 5200, by = "Gnomechomsky", deadly = true },
    { id = 348,   amount = 2400, by = "Gnomechomsky", avoidable = true },
    { id = 999999, amount = 2000, by = "Someone Else" },
  })
end
layOutAFight()

-- 1. is there anything to read at all --------------------------------------------
check(R.Available(), "the meter reports itself available")
M.meter.available, M.meter.reason = false, "no meter in this instance"
local ok, why = R.Available()
eq(ok, false, "and says when it is not")
eq(why, "no meter in this instance", "with the engine's own reason, not one of ours")
eq(R.Session(DONE), nil, "and reading it gives nothing")
M.meter.available, M.meter.reason = true, ""

-- 2. in combat the numbers are secret, so the read is not attempted --------------
-- Every session getter is SecretWhenInCombat in the client's documentation. This is the whole
-- reason the feature is a recap: asking during the fight cannot work, not merely works badly.
M.inCombat = true
check(R.Sealed(), "in combat the meter is sealed")
local sealed, sealWhy = R.Session(DONE)
eq(sealed, nil, "so no session comes back")
check(sealWhy and sealWhy:find("secret"), "and it says why: " .. tostring(sealWhy))
eq(R.Build(), nil, "and no card is built")
M.inCombat = false

-- 3. a session, flattened ---------------------------------------------------------
local s = R.Session(DONE)
check(s ~= nil, "out of combat the session reads")
eq(#s.rows, 2, "both units are there")
eq(s.rows[1].amount, 18420, "biggest first")
eq(s.rows[1].mine, true, "and that one is you")
eq(s.rows[2].name, "Gnomechomsky", "the other is them")
eq(s.rows[2].side, Enum.DamageMeterSourceDisplayType.Enemy, "on the enemy side")
eq(s.duration, 30, "the session knows how long it ran")

-- A row the client will not give a number for is left out rather than counted as zero.
M.session(CURRENT, DONE, {
  { guid = ME, name = "Vesh Torchman", amount = 18420, mine = true, side = 1 },
  { guid = FOE, name = "Gnomechomsky", amount = 12100, side = 2, secret = true },
})
local partial = R.Session(DONE)
eq(#partial.rows, 1, "a secret row is dropped, not read as nothing")
layOutAFight()

-- 4. the spells behind a row ------------------------------------------------------
local mine = R.Spells(DONE, ME)
eq(#mine.rows, 3, "three spells did the damage")
eq(mine.rows[1].spell, "Pyroblast", "named from the client")
eq(mine.rows[1].amount, 7000, "with its total")
eq(mine.rows[1].overkill, 900, "and its overkill")

local hits = R.Spells(TAKEN, ME)
eq(hits.rows[1].spell, "Shadow Bolt", "a spell in the generated table is named without asking the client")
eq(ns.PVP_BY_ID[686], "Shadow Bolt", "which is where that name came from")
eq(hits.rows[1].deadly, true, "and it is flagged as the one that did it")
eq(hits.rows[1].by, "Gnomechomsky", "and who cast it")
eq(hits.rows[2].avoidable, true, "an avoidable hit is flagged")
eq(hits.rows[3].spell, "spell 999999", "a spell nothing can name still gets a row")

-- 5. the card ---------------------------------------------------------------------
local card = R.Build()
check(card ~= nil, "the card builds")
eq(card.damage, 18420, "what you dealt")
eq(card.dps, 612, "at what rate")
eq(card.taken, 9600, "what you took")
eq(card.healed, 3200, "what you healed")
eq(card.avoidable, 1400, "and what of it you need not have taken")
eq(card.duration, 30, "and how long the fight was")

eq(card.top.spell, "Pyroblast", "your best spell")
eq(card.top.amount, 7000, "its total")
near(card.top.share, 7000 / 18420, "and its share of everything you did")

eq(card.killer.spell, "Shadow Bolt", "what killed you")
eq(card.killer.by, "Gnomechomsky", "and who sent it")
eq(card.killer.amount, 5200, "and for how much")

eq(#card.enemies, 1, "one enemy was in the fight")
eq(card.enemies[1].name, "Gnomechomsky", "by name")
eq(card.enemies[1].amount, 12100, "with everything they dealt to everyone")

-- Their own total is everything they did to anybody. What they put into YOU is the taken side,
-- added up by caster, which is the only figure worth keeping against their name.
eq(card.byWho["Gnomechomsky"], 7600, "they personally put 7600 into you, not their 12100 total")
local hurt, times, name = R.Hurt(FOE)
eq(hurt, 7600, "which is what goes against them in the book")
eq(times, 1, "after one fight")
eq(name, "Gnomechomsky", "under their name")
eq(R.Hurt("Player-1-NOBODY"), nil, "a stranger has no record")

-- 6. a fight ending is when all of this happens ----------------------------------
clearBanner()
H.Engage({ name = "Gnomechomsky" }, true)
check(H.InPvP(), "a fight with a player is on")
M.fire("PLAYER_REGEN_ENABLED")
-- The read is deliberately one tick late: the engine closes the session on this same event, and
-- reading inside the handler can still catch the player marked as in combat.
eq(GodslayerDB.recap and GodslayerDB.recap.last, nil, "nothing is read in the same frame")
M.advance(1)
check(GodslayerDB.recap.last ~= nil, "a tick later the fight is in the book")
eq(GodslayerDB.recap.last.damage, 18420, "with the numbers")
eq(GodslayerDB.recap.last.pvp, true, "marked as a fight with a player")
eq(title(), "SHADOW BOLT", "and the thing that killed you is named out loud")
eq(#GodslayerDB.recap.log, 1, "one fight kept")

-- With no death, the loudest thing is your own best spell instead.
clearBanner()
M.meterSpells(CURRENT, TAKEN, ME, { { id = 348, amount = 2400, by = "Gnomechomsky" } })
M.session(CURRENT, TAKEN, { { guid = ME, mine = true, amount = 2400, side = 1 } })
M.advance(10)
H.Engage({ name = "Gnomechomsky" }, true)
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
eq(title(), "PYROBLAST", "a fight you lived through names your own best spell")
eq(GodslayerDB.recap.last.killer, nil, "and nothing killed you")
eq(#GodslayerDB.recap.log, 2, "two fights kept")

-- A fight with nothing in it is not a fight.
clearBanner()
M.clearMeter()
M.advance(10)
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
eq(#GodslayerDB.recap.log, 2, "an empty session adds nothing to the book")
eq(title(), nil, "and says nothing")
layOutAFight()

-- 7. numbers people can read ------------------------------------------------------
eq(R.Short(0), "0", "zero")
eq(R.Short(940), "940", "under a thousand is itself")
eq(R.Short(1500), "1.5k", "then one decimal")
eq(R.Short(18420), "18k", "past ten thousand the decimal is noise")
eq(R.Short(2400000), "2.4m", "and millions read as millions")
eq(R.Comma(18420), "18,420", "chat gets the full number")
eq(R.Comma(612), "612", "with no stray comma on a short one")
eq(R.Comma(1000000), "1,000,000", "and one every three digits")

-- 8. the written recap -------------------------------------------------------------
local lines = R.Lines(R.Build())
check(lines and #lines >= 4, "the recap has something to say")
local joined = table.concat(lines, "\n")
check(joined:find("18,420"), "it gives the damage in full")
check(joined:find("Pyroblast"), "names your best spell")
check(joined:find("38%% of your damage") or joined:find("38% of your damage"), "with its share as a percentage, not a literal %%")
check(joined:find("What killed you"), "says what killed you")
check(joined:find("Shadow Bolt"), "by name")
check(joined:find("avoidable"), "and calls out the avoidable damage")

-- 9. the command --------------------------------------------------------------------
-- The fight left in the book above was one you lived through, so a fresh fatal one goes in
-- first: the command shows the last fight, and that is the card being asserted on.
M.advance(10)
H.Engage({ name = "Gnomechomsky" }, true)
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
eq(GodslayerDB.recap.last.killer.spell, "Shadow Bolt", "the newest fight in the book is the fatal one")

local said = {}
local realPrint = print
print = function(...) local b = {} for i = 1, select("#", ...) do b[#b+1] = tostring((select(i, ...))) end said[#said+1] = table.concat(b, " ") end
local function spoke(fragment)
  for _, l in ipairs(said) do if l:find(fragment, 1, true) then return l end end
end
local function say(text) said = {}; SlashCmdList["GODSLAYER"](text) end

say("recap")
check(spoke("18,420"), "/godslayer recap prints the last fight")
check(spoke("Shadow Bolt"), "and what killed you")
check(spoke("fights kept"), "and offers the ones before it")

say("recap 2")
check(spoke("You dealt"), "an older fight can be asked for")
say("recap 99")
check(spoke("only have"), "and asking past the end says how many there are")

M.meter.available, M.meter.reason = false, "the meter is off"
say("recap")
check(spoke("the meter is off"), "with no meter it gives the engine's reason")
check(spoke("damageMeterEnabled"), "and the one console line that turns it back on")
M.meter.available, M.meter.reason = true, ""

print = realPrint

-- 10. the book is capped -------------------------------------------------------------
for i = 1, 40 do GodslayerDB.recap.log[#GodslayerDB.recap.log + 1] = { at = i, damage = i } end
M.advance(10)
M.fire("PLAYER_REGEN_ENABLED")
M.advance(1)
check(#GodslayerDB.recap.log <= 25, "the book holds twenty-five fights (got " .. #GodslayerDB.recap.log .. ")")

eq(ns.errors, nil, "no handler errors in the recap tests")

M.realPrint(("%d passed, %d failed"):format(passed, failed))
os.exit(failed == 0 and 0 or 1)
