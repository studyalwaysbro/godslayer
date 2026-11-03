-- Godslayer and the death recap: lua tests/death.lua
--
-- Two things make this worth a file. The engine hands the rows back **newest first**, which is
-- the opposite of how anybody reads a story, and the only statement of that fact anywhere is one
-- line in a client UI that does not load in this game. And `DeathRecapEventInfo` is in the
-- generated API documentation with an empty field list, so every field name used here was read
-- off that same gated-out UI rather than from the docs.
--
-- The mock therefore models the order rather than smoothing it over. A reader that assumed
-- chronological order would pass a friendly mock and, in game, name the wrong spell as the one
-- that killed you while telling the story backwards.
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
                "Control.lua", "Death.lua", "Comm.lua", "Rival.lua", "Wheel.lua", "UI.lua" }
local ns = M.load("Godslayer", FILES)
M.fire("ADDON_LOADED", "Godslayer")
M.fire("PLAYER_LOGIN")
local D = ns.Death
local function say(text) SlashCmdList["GODSLAYER"](text) end
local function printed() return table.concat(M.printed, "\n") end

-- A death, in the engine's own order: newest first. Row one killed him. The oldest row, a
-- Frostbolt eight seconds back, is last. Timestamps run the other way for the same reason.
local T = 1791400000
local ROWS = {
  { event = "SPELL_DAMAGE",  spellId = 11366, spellName = "Pyroblast", caster = "Sir Problem",
    amount = 1400, overkill = 300, school = 4, timestamp = T,       currentHP = 1100, avoidable = false, deadly = true },
  { event = "SWING_DAMAGE",                   caster = "Sir Problem",
    amount = 420,  timestamp = T - 1.2, currentHP = 1520 },
  { event = "SPELL_DAMAGE",  spellId = 686,  spellName = "Shadow Bolt", caster = "Grimnight",
    amount = 900,  absorbed = 400, school = 32, timestamp = T - 2.5, currentHP = 1940, avoidable = true },
  { event = "SPELL_PERIODIC_DAMAGE", spellId = 980, spellName = "Curse of Agony", caster = "Grimnight",
    amount = 120,  timestamp = T - 4.0, currentHP = 2440 },
  { event = "SPELL_DAMAGE",  spellId = 116,  spellName = "Frostbolt", caster = "Sir Problem",
    amount = 760,  resisted = 60, school = 16, timestamp = T - 8.0, currentHP = 3000 },
}

-- ---------------------------------------------------------------------------
-- 1. Nothing to read
-- ---------------------------------------------------------------------------
M.clearDeaths()
eq(D.Available(), true, "the client has a death recap")
eq(D.Has(), false, "but nothing in it yet")
local card, why = D.Read()
eq(card, nil, "so there is no card")
eq(why, "the engine has no recap of that death", "and it says so rather than inventing one")

M.printed = {}
say("death")
check(printed():find("Nothing in the book", 1, true), "the command says so: " .. printed())

-- ---------------------------------------------------------------------------
-- 2. The order, which is the whole point
-- ---------------------------------------------------------------------------
M.death(ROWS, 3000)
eq(D.Has(), true, "the engine is holding a recap")
card = D.Read()
check(card ~= nil, "which reads")
eq(#card.rows, 5, "five hits")

-- Turned the right way round: oldest first on the way out.
eq(card.rows[1].spell, "Frostbolt", "the oldest hit is first out")
eq(card.rows[5].spell, "Pyroblast", "and the killing blow is last")
eq(card.rows[1].by, "Sir Problem", "with its caster")
eq(card.rows[2].spell, "Curse of Agony", "and the rest in between")
eq(card.rows[3].spell, "Shadow Bolt", "in order")
eq(card.rows[4].spell, "Melee", "a swing is named from the client's own word for one")
eq(card.rows[4].id, 88163, "and gets the stand-in id the client uses for a swing")

-- The killing blow is the engine's row one, not the newest timestamp or the biggest number.
eq(card.fatal.spell, "Pyroblast", "the fatal hit is the engine's first row")
eq(card.rows[5].killed, true, "flagged on the row")
eq(card.rows[1].killed, nil, "and on no other")

-- ---------------------------------------------------------------------------
-- 3. Seconds before death, which the engine does not give
-- ---------------------------------------------------------------------------
-- The client derives it as the newest timestamp in the set minus this row's, and so must this.
check(card.rows[1].before and math.abs(card.rows[1].before - 8.0) < 0.01,
  "the oldest hit was eight seconds before the end (got " .. tostring(card.rows[1].before) .. ")")
eq(card.rows[5].before, 0, "and the killing blow was at the end")
check(card.span and math.abs(card.span - 8.0) < 0.01, "the whole death took eight seconds")

-- ---------------------------------------------------------------------------
-- 4. What landed, which is not what was swung
-- ---------------------------------------------------------------------------
-- The client takes overkill, absorb, resist and block off the gross figure in turn. So does this.
local pyro, bolt, shadow, frost = card.rows[5], card.rows[4], card.rows[3], card.rows[1]
eq(pyro.amount, 1400, "the gross figure is kept")
eq(pyro.landed, 1100, "and 300 of overkill comes off it")
eq(pyro.over, 300, "with the overkill recorded")
eq(shadow.amount, 900, "an absorbed hit keeps its gross too")
eq(shadow.landed, 500, "and 400 absorbed comes off")
eq(shadow.absorbed, 400, "recorded")
eq(frost.landed, 700, "and a resist comes off the same way")
eq(frost.resisted, 60, "recorded")
eq(bolt.landed, 420, "a clean hit lands for all of it")
eq(bolt.over, nil, "with no extras invented for it")

-- Health as a share, from the separate call rather than a field on the row.
eq(card.maxHealth, 3000, "the max health comes from its own call")
eq(frost.pct, 100, "so the first hit found him full")
eq(pyro.pct, 36, "and the last found him at a third")

-- ---------------------------------------------------------------------------
-- 5. Who actually did it
-- ---------------------------------------------------------------------------
-- Counted across the rows rather than taken from the last one: the one who finishes you is often
-- not the one who did the work. Here Sir Problem landed 1100 + 420 + 700 and Grimnight 500 + 120.
eq(card.byWho["Sir Problem"], 2220, "the killer's total is summed over their rows")
eq(card.byWho.Grimnight, 620, "and so is the other one's")
eq(card.killer.name, "Sir Problem", "the one who did most of it is named")
eq(card.killer.amount, 2220, "with how much")
eq(card.total, 2840, "and the whole lot adds up")

-- The biggest hit is picked by what landed, not by the gross: an absorbed 900 is not the problem.
eq(card.worst.spell, "Pyroblast", "the biggest hit that landed is the Pyroblast at 1100")
eq(card.worst.landed, 1100, "for that much")
eq(card.avoidable, 500, "and only what was flagged avoidable is counted as avoidable")

-- ---------------------------------------------------------------------------
-- 6. What it says
-- ---------------------------------------------------------------------------
local lines = table.concat(D.Lines(card, 30), "\n")
check(lines:find("5 hits over 8.0 seconds", 1, true), "the header counts the hits and the time: " .. lines)
check(lines:find("Frostbolt (Sir Problem)", 1, true), "each row names the spell and the caster")
check(lines:find("-8.0s", 1, true), "with how long before the end it landed")
check(lines:find("killed you", 1, true), "and the fatal one is marked")
check(lines:find("100% left", 1, true), "health is a single percent sign, not a doubled one")
check(not lines:find("%%", 1, true), "nowhere in the output is a doubled percent sign")
check(lines:find("300 overkill", 1, true), "overkill is said")
check(lines:find("400 absorbed", 1, true), "and absorbs")
check(lines:find("60 resisted", 1, true), "and resists")
check(lines:find("avoidable", 1, true), "and the avoidable hit is flagged")
check(lines:find("500 of the 2,840 you took was avoidable, 18%", 1, true),
  "and the avoidable share is given as a percentage: " .. lines)

-- Long recaps are trimmed from the front, because the end is the part that killed you.
local short = table.concat(D.Lines(card, 2), "\n")
check(short:find("3 earlier hits", 1, true), "a short view says how many it left out: " .. short)
check(short:find("Pyroblast", 1, true), "and keeps the end")
check(not short:find("Frostbolt", 1, true), "not the beginning")

-- ---------------------------------------------------------------------------
-- 7. Dying
-- ---------------------------------------------------------------------------
M.printed = {}
M.fire("PLAYER_DEAD")
eq(printed(), "", "nothing is read inside the handler: the engine is still filling the recap")
M.advance(1)
local said = printed()
check(said:find("Your death", 1, true), "the recap lands a tick later: " .. said)
local book = GodslayerDB.deaths
check(book ~= nil and book.last ~= nil, "and goes in the book")
eq(book.n, 1, "counted")
eq(book.bySpell.Pyroblast, 1, "with what finished him")
eq(book.byWho["Sir Problem"], 1, "and who did the work")
eq(book.taken, 2840, "and what it cost")
eq(book.avoidable, 500, "and how much of that was avoidable")

-- ---------------------------------------------------------------------------
-- 8. A death with nobody in it
-- ---------------------------------------------------------------------------
M.death({
  { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "Falling", amount = 2400,
    timestamp = T + 100, currentHP = 0 },
  { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "Falling", amount = 600,
    timestamp = T + 99, currentHP = 2400 },
}, 3000)
card = D.Read()
eq(#card.rows, 2, "two hits from the world")
eq(card.rows[1].spell, "Falling", "named from the client's string for the kind")
eq(card.rows[2].killed, true, "and the newest one killed him")
eq(card.killer, nil, "with nobody to blame")
eq(card.rows[1].by, nil, "and no caster on the row")
local envLines = table.concat(D.Lines(card, 30), "\n")
check(envLines:find("Falling", 1, true), "which still reads: " .. envLines)

-- An environmental type the client has no string for is said as itself rather than as nothing.
M.death({ { event = "ENVIRONMENTAL_DAMAGE", environmentalType = "Slime", amount = 50, timestamp = T, currentHP = 0 } }, 100)
card = D.Read()
eq(card.rows[1].spell, "Slime", "an unknown kind of environmental damage keeps its own name")

-- ---------------------------------------------------------------------------
-- 9. A row the engine will not name
-- ---------------------------------------------------------------------------
-- A spell with an id and no name is looked up, first in the client's own PvP table and then
-- through the client. One with neither falls back to the event, and never to nothing.
M.death({
  { event = "SPELL_DAMAGE", spellId = 686, amount = 100, timestamp = T, currentHP = 0 },
  { event = "SPELL_DAMAGE", spellId = 999999, amount = 50, timestamp = T - 1, currentHP = 100 },
  { event = "SPELL_DAMAGE", amount = 10, timestamp = T - 2, currentHP = 150 },
}, 200)
card = D.Read()
eq(card.rows[3].spell, "Shadow Bolt", "an id with no name is named from the client's table")
eq(card.rows[2].spell, "SPELL_DAMAGE", "an id nothing knows falls back to the event")
eq(card.rows[1].spell, "SPELL_DAMAGE", "and so does a row with no id at all")

-- ---------------------------------------------------------------------------
-- 10. The command
-- ---------------------------------------------------------------------------
M.death(ROWS, 3000)
M.fire("PLAYER_DEAD") M.advance(1)
M.printed = {}
say("death")
local out = printed()
check(out:find("Your death", 1, true), "the command prints the last one: " .. out)
check(out:find("Frostbolt", 1, true), "in full, from the beginning")
check(out:find("deaths kept", 1, true), "and says the book has more")

M.printed = {}
say("death 99")
check(printed():find("I only have", 1, true), "asking past the end of the book says so: " .. printed())

M.printed = {}
say("death who")
out = printed()
check(out:find("deaths recorded", 1, true), "the tally counts them: " .. out)
check(out:find("Finished you off: Pyroblast", 1, true), "and says what keeps finishing you")
check(out:find("Did most of the work: Sir Problem", 1, true), "and who does the work")
check(out:find("avoidable", 1, true), "and how much was avoidable")

-- ---------------------------------------------------------------------------
-- 11. A client without it
-- ---------------------------------------------------------------------------
local saved = C_DeathRecap
C_DeathRecap = nil
eq(D.Available(), false, "with no namespace there is no recap")
eq(D.Has(), false, "and nothing to have")
eq(D.Read(), nil, "and nothing to read")
M.printed = {}
say("death")
check(printed():find("No death recap", 1, true), "and the command says so: " .. printed())
M.fire("PLAYER_DEAD") M.advance(1)
check(true, "and dying without one does not throw")
C_DeathRecap = saved

-- A recap that comes back as something other than a table is not a recap.
C_DeathRecap = { GetRecapEvents = function() return "nonsense" end,
                 GetRecapMaxHealth = function() return nil end,
                 HasRecapEvents = function() return true end }
eq(D.Read(), nil, "a recap that is not a list is refused")
C_DeathRecap = saved

eq(ns.errors, nil, "no errors anywhere in this suite")
for _, l in ipairs(GodslayerDB.log) do
  if l:find(" error: ", 1, true) then check(false, "logged error: " .. l) end
end

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
