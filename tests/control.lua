-- Godslayer and what has hold of you: lua tests/control.lua
--
-- The thing being tested is the school lockout, and the reason it is worth a file of its own is
-- that a school is a bit mask and two spells in this build sit in two schools at once. A
-- Counterspell landing on Frostfire Bolt locks Fire and Frost together, so a mage treating a
-- lockout as one school thinks Fireball is still up when it is not.
--
-- The Lua this client runs has no bitwise operators, so every one of those tests is arithmetic on
-- remainders, which is exactly the kind of code that is right for the cases somebody tried and
-- wrong for the one they did not.
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
local C = ns.Control
local function say(text) SlashCmdList["GODSLAYER"](text) end
local function printed() return table.concat(M.printed, "\n") end

local PHYS, HOLY, FIRE, NATURE, FROST, SHADOW, ARCANE = 1, 2, 4, 8, 16, 32, 64

-- ---------------------------------------------------------------------------
-- 1. The client's own data, which the rest of this rests on
-- ---------------------------------------------------------------------------
-- If a regeneration ever drops the school column these four assertions go first, before any of
-- the logic built on top starts quietly agreeing with itself.
eq(ns.PVP.Frostbolt.school, FROST, "Frostbolt is Frost")
eq(ns.PVP.Fireball.school, FIRE, "Fireball is Fire")
eq(ns.PVP["Frostfire Bolt"].school, FIRE + FROST, "Frostfire Bolt is Fire and Frost at once")
eq(ns.PVP["Chaos Bolt"].school, FIRE + NATURE + FROST + SHADOW + ARCANE, "Chaos Bolt is five schools")
check(type(ns.SCHOOL_BITS) == "table" and ns.SCHOOL_BITS[FROST] ~= nil, "the school bits are generated")
eq(ns.SCHOOL_BITS[FROST].key, "SPELL_SCHOOL4_CAP",
  "and are keyed on the index, which is a step below the mask: Frost is index 4 and mask 16")

-- ---------------------------------------------------------------------------
-- 2. Splitting a mask
-- ---------------------------------------------------------------------------
local function names(mask) return table.concat(C.Schools(mask), ",") end
eq(names(0), "", "nothing is no schools")
eq(names(FROST), "Frost", "one bit is one school")
eq(names(FIRE), "Fire", "and the right one")
eq(names(FIRE + FROST), "Fire,Frost", "two bits are two schools, in the engine's order")
eq(names(PHYS), "Physical", "the lowest bit is Physical")
eq(names(ARCANE), "Arcane", "and the highest is Arcane")
eq(names(127), "Physical,Holy,Fire,Nature,Frost,Shadow,Arcane", "every bit at once")
eq(names(FIRE + NATURE + FROST + SHADOW + ARCANE), "Fire,Nature,Frost,Shadow,Arcane", "and Chaos Bolt's five")
eq(#C.Schools(128), 0, "a bit past Arcane names nothing rather than guessing")

-- The client has its own joiner and it is the phrasing the game would use, so it is preferred.
eq(C.SchoolText(FROST), "Frost", "one school reads as itself")
eq(C.SchoolText(FIRE + FROST), "Fire and Frost", "and two read the way the client words them")
eq(C.SchoolText(0), nil, "no mask is no text")

-- ---------------------------------------------------------------------------
-- 3. Whether a spell is caught by a lockout
-- ---------------------------------------------------------------------------
eq(C.Locked(FROST, FROST), true, "a Frost spell is locked by a Frost lockout")
eq(C.Locked(FIRE, FROST), false, "and a Fire spell is not")
eq(C.Locked(FIRE + FROST, FROST), true, "a two-school spell is locked when either of them is")
eq(C.Locked(FIRE + FROST, FIRE), true, "either way round")
eq(C.Locked(FIRE + FROST, ARCANE), false, "and not by a school it is not in")
eq(C.Locked(FROST, FIRE + FROST), true, "a two-school lockout catches a spell in one of them")
eq(C.Locked(FIRE, FIRE + FROST), true, "both of them, in fact")
eq(C.Locked(ARCANE, FIRE + FROST), false, "but not a third")
eq(C.Locked(0, FROST), false, "a spell with no school is never locked")
eq(C.Locked(FROST, 0), false, "and no lockout locks nothing")

-- ---------------------------------------------------------------------------
-- 4. Your own spellbook
-- ---------------------------------------------------------------------------
M.forgetAll()
M.know(116, 133, 11366, 2948, 122, 118, 1953, 400574, 401502, 11958)
C.Known(true)
local mine = C.Known()
local have = {}
for _, s in ipairs(mine) do have[s.name] = s.school end
eq(have.Frostbolt, FROST, "a spell you know is in the list")
eq(have.Fireball, FIRE, "with its school")
eq(have["Frostfire Bolt"], FIRE + FROST, "two schools and all")
eq(have["Ice Lance"], nil, "a spell you do not know is not")
eq(have["Shadow Bolt"], nil, "and neither is another class's")
eq(#mine, 10, "ten known spells in the client's table")

-- ---------------------------------------------------------------------------
-- 5. The case this file exists for
-- ---------------------------------------------------------------------------
-- A Counterspell on a Frostbolt locks Frost. Fire is still yours.
local openFrost = {}
for _, g in ipairs(C.Open(FROST)) do for _, n in ipairs(g.spells) do openFrost[n] = true end end
eq(openFrost.Fireball, true, "a Frost lockout leaves Fireball")
eq(openFrost.Pyroblast, true, "and Pyroblast")
eq(openFrost.Polymorph, true, "and the Arcane half of your book")
eq(openFrost.Frostbolt, nil, "and not Frostbolt")
eq(openFrost["Frost Nova"], nil, "nor Frost Nova")
eq(openFrost["Frostfire Bolt"], nil, "and not Frostfire Bolt either, because half of it is Frost")

-- A Counterspell on a Frostfire Bolt locks both, and that is the one that catches people out.
local openBoth = {}
for _, g in ipairs(C.Open(FIRE + FROST)) do for _, n in ipairs(g.spells) do openBoth[n] = true end end
eq(openBoth.Fireball, nil, "a Frostfire lockout takes Fireball with it")
eq(openBoth.Pyroblast, nil, "and Pyroblast")
eq(openBoth.Scorch, nil, "and Scorch")
eq(openBoth.Frostbolt, nil, "and the whole Frost side")
eq(openBoth.Polymorph, true, "leaving only Arcane")
eq(openBoth["Arcane Blast"], true, "all of it")
eq(openBoth.Blink, true, "and Blink, which is the way out")

-- The open schools are ordered biggest first, because that is your main school and in a fight it
-- is the answer you were actually asking for.
local order = C.Open(ARCANE)
check(#order >= 2, "more than one school survives an Arcane lockout")
check(#order[1].spells >= #order[2].spells, "and the one you have most of is named first")

-- ---------------------------------------------------------------------------
-- 6. What it says
-- ---------------------------------------------------------------------------
local line = C.Line({ kind = "SCHOOL_INTERRUPT", school = FROST, duration = 8, left = 6.2 })
check(line:find("Frost locked for 6.2s", 1, true), "a lockout says the school and the seconds: " .. tostring(line))
check(line:find("Still up:", 1, true), "and what is left")
check(line:find("Fireball", 1, true) or line:find("Pyroblast", 1, true) or line:find("Polymorph", 1, true),
  "by name: " .. tostring(line))

line = C.Line({ kind = "SCHOOL_INTERRUPT", school = FIRE + FROST, duration = 8, left = 8 })
check(line:find("Fire and Frost locked", 1, true), "two schools are both named: " .. tostring(line))
check(not line:find("Fireball", 1, true), "and Fireball is not offered as still up")

-- Something that is not an interrupt reads as itself, from the entry's own words, because the
-- client special-cases exactly one locType and renders the rest the same way.
line = C.Line({ kind = "STUN", spell = "Hammer of Justice", duration = 6, left = 4 })
eq(line, "Hammer of Justice for 4.0s.", "a stun says what it is and how long is left")
line = C.Line({ kind = "SOMETHING_NEW", duration = 3 })
eq(line, "SOMETHING_NEW for 3.0s.", "and a kind nobody here has heard of is still said")

-- Ten seconds and over drop the decimal: nobody needs a tenth of a second on a twenty second fear.
line = C.Line({ kind = "FEAR", spell = "Howl of Terror", left = 20 })
eq(line, "Howl of Terror for 20s.", "a long one is said in whole seconds")

-- ---------------------------------------------------------------------------
-- 7. Reading the engine
-- ---------------------------------------------------------------------------
M.control({})
eq(C.Count(), 0, "nothing on you is nothing")
eq(C.Top(), nil, "and no top entry")
eq(#C.Active(), 0, "and an empty list")

M.control({
  { kind = "STUN", id = 853, spell = "Hammer of Justice", duration = 6, left = 5.5, priority = 9 },
  { kind = "SCHOOL_INTERRUPT", id = 18469, spell = "Counterspell", duration = 8, left = 7, school = FROST, priority = 4 },
})
eq(C.Count(), 2, "two things on you")
local top = C.Top()
eq(top.kind, "STUN", "the top entry is the one at the active index")
eq(top.spell, "Hammer of Justice", "named from the entry's own text")
eq(top.duration, 6, "with its duration")
eq(top.left, 5.5, "and what is left of it")
local all = C.Active()
eq(#all, 2, "both come back from the list")
eq(all[2].kind, "SCHOOL_INTERRUPT", "in the engine's order")
eq(all[2].school, FROST, "with the lockout mask")

-- ---------------------------------------------------------------------------
-- 8. Landing
-- ---------------------------------------------------------------------------
M.printed = {}
M.control({ { kind = "SCHOOL_INTERRUPT", id = 18469, spell = "Counterspell", duration = 8, left = 8, school = FROST } })
M.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
-- The landing speaks through the banner and the announcer rather than chat, so chat staying
-- quiet is the assertion. The words themselves are checked against Control.Line above.
eq(printed(), "", "a landing does not write to chat")
eq(C.session.byType.SCHOOL_INTERRUPT, 1, "the lockout is counted")
eq(GodslayerDB.control.bySchool.Frost, 1, "and the school is counted by name")
check(C.session.locked >= 8, "and its seconds go against the lockout total")

-- A two-school lockout counts against both schools, which is the tally equivalent of the bug
-- the whole file is about.
M.control({ { kind = "SCHOOL_INTERRUPT", id = 18469, spell = "Counterspell", duration = 8, left = 8, school = FIRE + FROST } })
M.advance(2)
M.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
eq(GodslayerDB.control.bySchool.Frost, 2, "a Fire-and-Frost lockout counts for Frost")
eq(GodslayerDB.control.bySchool.Fire, 1, "and for Fire")

-- An entry the engine itself marks as not worth showing is not shown, and is not counted.
local before = C.session.byType.STUN
M.control({ { kind = "STUN", id = 853, spell = "Quiet One", duration = 4, left = 4, show = 0 } })
M.advance(2)
M.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
eq(C.session.byType.STUN, before, "a displayType of none is left alone")

-- An event about somebody else is not about you.
M.control({ { kind = "FEAR", id = 5782, spell = "Fear", duration = 8, left = 8 } })
M.advance(2)
M.fire("LOSS_OF_CONTROL_ADDED", "target", 1)
eq(C.session.byType.FEAR, nil, "control on another unit is ignored")
M.fire("LOSS_OF_CONTROL_ADDED", nil, 1)
eq(C.session.byType.FEAR, 1, "but an event with no unit on it is taken as yours, the way older builds sent it")

-- ---------------------------------------------------------------------------
-- 9. Feeding the diminishing-returns measurement
-- ---------------------------------------------------------------------------
-- The engine's own duration is a better number than an aura read, so crowd control that lands on
-- you is handed to the part of the addon already measuring what this server does to a second one.
GodslayerDB.dr = nil
M.control({ { kind = "STUN", id = 122, spell = "Frost Nova", duration = 8, left = 8 } })
M.advance(2)
M.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
local group = ns.PVP["Frost Nova"].dr
check(type(group) == "number" and group > 0, "Frost Nova has a diminishing group in this build")
local rows = GodslayerDB.dr and GodslayerDB.dr[group]
check(type(rows) == "table" and #rows == 1, "a stun on you is recorded against its group")
eq(rows[1].d, 8, "with the engine's own duration")

M.control({ { kind = "STUN", id = 122, spell = "Frost Nova", duration = 4, left = 4 } })
M.advance(3)
M.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
rows = GodslayerDB.dr[group]
eq(#rows, 2, "a second one inside the window is a second observation")
eq(rows[2].n, 2, "known to be the second")
eq(rows[2].d, 4, "at half the length, which is what diminishing means")
eq(rows[2].f, 8, "against the full length it remembers")

-- An interrupt is not crowd control and must not land in the diminishing table.
local was = #GodslayerDB.dr[group]
M.control({ { kind = "SCHOOL_INTERRUPT", id = 18469, duration = 8, left = 8, school = ARCANE } })
M.advance(2)
M.fire("LOSS_OF_CONTROL_ADDED", "player", 1)
eq(#GodslayerDB.dr[group], was, "a school lockout is not a diminishing observation")

-- ---------------------------------------------------------------------------
-- 10. The measured time, which is not the declared time
-- ---------------------------------------------------------------------------
M.fire("PLAYER_CONTROL_LOST")
M.advance(4.5)
M.fire("PLAYER_CONTROL_GAINED")
check(C.session.held and C.session.held >= 4.4 and C.session.held <= 4.6,
  "the gap between losing and regaining control is measured (got " .. tostring(C.session.held) .. ")")
local held = C.session.held
M.fire("PLAYER_CONTROL_GAINED")
eq(C.session.held, held, "a second regain with no loss in between adds nothing")

-- ---------------------------------------------------------------------------
-- 11. The command
-- ---------------------------------------------------------------------------
M.control({ { kind = "STUN", id = 853, spell = "Hammer of Justice", duration = 6, left = 3.5 },
            { kind = "SCHOOL_INTERRUPT", id = 18469, duration = 8, left = 7, school = FROST } })
M.printed = {}
say("control")
local out = printed()
check(out:find("2 things on you", 1, true), "it counts what has you: " .. out)
check(out:find("Hammer of Justice for 3.5s", 1, true), "and names each one")
check(out:find("Frost locked for 7.0s", 1, true), "including the lockout")

M.control({})
M.printed = {}
say("control")
out = printed()
check(out:find("Nothing has you right now", 1, true), "with nothing on you it says so: " .. out)
check(out:find("This session:", 1, true), "and gives the tally")
check(out:find("school interrupt", 1, true), "with the kinds spelled out as words")
check(out:find("seconds of this session you could not act at all", 1, true), "and the measured time, not the declared one")
check(out:find("Schools locked on you, all time", 1, true), "and which schools get locked")

M.printed = {}
say("control open")
out = printed()
check(out:find("10 of your spells", 1, true), "open lists your book by school: " .. out)
check(out:find("Frost", 1, true), "naming the schools")
check(out:find("Frostbolt", 1, true), "and the spells in them")
check(not out:find("LOCKED", 1, true), "with nothing marked locked while nothing is")

M.control({ { kind = "SCHOOL_INTERRUPT", id = 18469, duration = 8, left = 6, school = FROST } })
M.printed = {}
say("control open")
out = printed()
check(out:find("LOCKED", 1, true), "and the locked school marked while it is: " .. out)
check(out:find("Frost is locked right now", 1, true), "and said plainly underneath")

-- ---------------------------------------------------------------------------
-- 12. A client without it
-- ---------------------------------------------------------------------------
local saved = C_LossOfControl
C_LossOfControl = nil
eq(C.Count(), 0, "with no namespace there is nothing on you")
eq(C.Top(), nil, "and no top entry")
eq(#C.Active(), 0, "and an empty list rather than an error")
M.printed = {}
say("control")
check(printed():find("no loss-of-control data", 1, true), "and the command says so: " .. printed())
C_LossOfControl = saved

-- And with no spellbook call at all, the open list is empty rather than wrong.
local savedBook = C_SpellBook
C_SpellBook = nil
eq(#C.Known(true), 0, "no spellbook call means no claims about your spells")
eq(C.OpenLine(FROST), nil, "and nothing offered as still up")
C_SpellBook = savedBook
C.Known(true)

eq(ns.errors, nil, "no errors anywhere in this suite")
for _, l in ipairs(GodslayerDB.log) do
  if l:find(" error: ", 1, true) then check(false, "logged error: " .. l) end
end

M.realPrint(passed .. " passed, " .. failed .. " failed")
if failed > 0 then os.exit(1) end
