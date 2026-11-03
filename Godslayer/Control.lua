-- Godslayer control: what has you, how long it has you, and what you can still cast.
--
-- THE DOOR NOBODY TRIED. Almost everything interesting on this client is behind a secrecy
-- annotation, and the last two files in this addon are built around working within one.
-- `C_LossOfControl` is not. It is declared `Environment = "All"`, and
-- `GetActiveLossOfControlData` carries no annotation on its returns at all -- only
-- `SecretArguments`, which is about what may be passed in. The engine will simply tell you what
-- has hold of you, which spell did it, and how many seconds are left.
--
-- AND FOREVER SHOWS ONE OF THEM AT A TIME. An earlier version of this header said the client's
-- own display was gated away. It is not: `mainline` is a family and camelot is in it.
--
--     Blizzard_FrameXML/Blizzard_FrameXML.toc:135
--       LossOfControlFrame.lua [AllowLoadGameType mists, mainline]
--     Blizzard_FrameXML/LossOfControlFrame.lua:66
--       -- only display an alert type if there's nothing up or it has higher priority.
--       -- If same priority, it needs to have longer time remaining
--
-- So there is a frame, behind the `lossOfControl` CVar, and it shows exactly one effect: the
-- highest priority, longest remaining. A stun landing on top of a Counterspell takes the
-- Counterspell off the screen. This reads all of them.
--
-- THE SCHOOL LOCKOUT, WHICH IS THE PART WORTH THE FILE. When a cast of yours is interrupted the
-- game does not lock that spell. It locks the spell's **school**, and the entry says which:
-- `lockoutSchool`, a bit mask. The client's own frame proves it is a mask rather than a school by
-- handing it whole to `C_Spell.GetSchoolString`, which can name more than one.
--
-- That matters more here than it looks, because two spells in this build are in two schools at
-- once. `Frostfire Bolt` is mask 20, Fire and Frost together, so a Counterspell landing on it
-- locks **both** -- and for a mage that leaves only Arcane. `Chaos Bolt` is 124, which is five
-- schools. A lockout treated as one school is wrong for those two and misleading for the rest,
-- because the useful question was never "what was interrupted" but "what can I still cast".
--
-- So this answers that one. `Pvp.lua` now carries each spell's school mask straight from the
-- client's `SpellMisc.SchoolMask`, and `C_SpellBook.IsSpellKnown` narrows it to spells you
-- actually have. A Counterspell on your Frostbolt gets you the seconds, the locked school, and
-- the names of your own spells that are still live.
--
-- The one thing this does not invent is a list of control types. The client itself special-cases
-- exactly one, `SCHOOL_INTERRUPT`, and renders everything else from the entry's own
-- `displayText`. This does the same, so a kind of control this build has and nobody here has
-- heard of is still announced with the right words.
--
--   /godslayer control        what has you now, or what has had you tonight
--   /godslayer control open   your spells by school, and which are locked right now

local _, ns = ...
local plain, try = ns.plain, ns.try

local Control = { handlers = {} }
ns.Control = Control

local NAME_CAP = 4           -- spells named as still castable
local CALL_GAP = 1.5         -- two announcements at least this far apart
local KEEP = 12              -- lockouts remembered in detail
local RED, BLUE, AMBER = { 1, 0.19, 0.19 }, { 0.4, 0.8, 1 }, { 1, 0.8, 0.2 }

-- The client's own display types, from LossOfControlFrame.lua. NONE means the engine has decided
-- this one is not worth showing, and that judgement is taken rather than second-guessed.
local SHOW_NONE, SHOW_ALERT, SHOW_FULL = 0, 1, 2

local lastCall, controlSince = 0, nil
local session = { locked = 0, controlled = 0, byType = {}, bySchool = {}, worst = nil }
Control.session = session

local function num(v)
  v = plain(v)
  return (type(v) == "number") and v or nil
end

local function str(v)
  v = plain(v)
  return (type(v) == "string" and v ~= "") and v or nil
end

--------------------------------------------------------------------------------
-- Schools
--------------------------------------------------------------------------------

-- There are no bitwise operators in the Lua this client runs, so a bit is tested with the
-- remainder: a mask contains `bit` exactly when `mask % (bit * 2) >= bit`. Mask 20 is Fire and
-- Frost by that test and nothing else, which is the case the rest of this file turns on.
local BITS = { 1, 2, 4, 8, 16, 32, 64 }

local function has(mask, bit)
  return (mask % (bit * 2)) >= bit
end

-- A mask split into its schools, in a fixed order. The names are the client's own globals, so a
-- localised client says Frost in its own language; the generated table is the fallback and also
-- what fixes the order, because pairs() over the bits would answer differently each time.
function Control.Schools(mask)
  mask = tonumber(mask)
  if not mask or mask <= 0 then return {} end
  local out = {}
  local bits = ns.SCHOOL_BITS
  if type(bits) ~= "table" then return out end
  for i = 1, #BITS do
    local bit = BITS[i]
    local row = bits[bit]
    if row and has(mask, bit) then
      out[#out + 1] = str(_G[row.key]) or row.name
    end
  end
  return out
end

-- One string for a whole mask. The client has its own call for this and it is the phrasing the
-- game itself would use, so it is asked first and the joined list is the fallback.
function Control.SchoolText(mask)
  local get = C_Spell and C_Spell.GetSchoolString
  local text = str(try(get, tonumber(mask) or 0))
  if text then return text end
  local names = Control.Schools(mask)
  if #names == 0 then return nil end
  return table.concat(names, " and ")
end

-- Whether a spell's own mask is touched by a lockout mask. A spell in two schools is locked when
-- either of them is, which is the whole reason Frostfire Bolt is in this file's header.
local function locked(spellMask, lockMask)
  spellMask, lockMask = tonumber(spellMask) or 0, tonumber(lockMask) or 0
  if spellMask <= 0 or lockMask <= 0 then return false end
  for i = 1, #BITS do
    if has(spellMask, BITS[i]) and has(lockMask, BITS[i]) then return true end
  end
  return false
end
Control.Locked = locked

local known = nil   -- spells from ns.PVP the player actually has, built once and kept

-- Your own spells, from the client's table narrowed to the ones you know. Built on demand rather
-- than at login: at login the spellbook is not reliably populated yet, and a list built then is
-- a list that is wrong for the rest of the session.
function Control.Known(rebuild)
  if known and not rebuild then return known end
  known = {}
  if type(ns.PVP) ~= "table" then return known end
  local is = C_SpellBook and C_SpellBook.IsSpellKnown
  if type(is) ~= "function" then return known end
  local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
  for name, s in pairs(ns.PVP) do
    if s.school and s.school > 0 and s.id then
      local yes = plain(try(is, s.id, bank))
      if yes == nil then yes = plain(try(is, s.id)) end
      if yes == true then known[#known + 1] = { name = name, id = s.id, school = s.school } end
    end
  end
  table.sort(known, function(a, b)
    if a.school ~= b.school then return a.school < b.school end
    return a.name < b.name
  end)
  return known
end

-- Your spells that the lockout does not touch. Ordered so the schools you have most of come
-- first: that is your main school, and in a fight it is the answer you wanted.
function Control.Open(lockMask)
  local mine, byMask, order = Control.Known(), {}, {}
  for i = 1, #mine do
    local s = mine[i]
    if not locked(s.school, lockMask) then
      if not byMask[s.school] then byMask[s.school] = {} order[#order + 1] = s.school end
      local bucket = byMask[s.school]
      bucket[#bucket + 1] = s.name
    end
  end
  table.sort(order, function(a, b)
    local na, nb = #byMask[a], #byMask[b]
    if na ~= nb then return na > nb end
    return a < b
  end)
  local out = {}
  for i = 1, #order do out[#out + 1] = { school = order[i], spells = byMask[order[i]] } end
  return out
end

--------------------------------------------------------------------------------
-- Reading
--------------------------------------------------------------------------------

local function activeIndex()
  local c = _G.Constants
  local v = c and c.LossOfControlConsts and c.LossOfControlConsts.LOSS_OF_CONTROL_ACTIVE_INDEX
  return (type(v) == "number") and v or 1
end

local function entry(data)
  if type(data) ~= "table" then return nil end
  local kind = str(data.locType)
  if not kind then return nil end
  local id = num(data.spellID)
  return {
    kind = kind,
    id = id,
    spell = str(data.displayText) or (id and ns.PVP_BY_ID and ns.PVP_BY_ID[id]) or nil,
    start = num(data.startTime),
    left = num(data.timeRemaining),
    duration = num(data.duration),
    school = num(data.lockoutSchool),
    priority = num(data.priority),
    show = num(data.displayType) or SHOW_FULL,
  }
end

function Control.Count()
  local get = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlDataCount
  return num(try(get)) or 0
end

-- The one the engine itself would be showing, which is the highest priority rather than the
-- first to land. Nil when nothing has you.
function Control.Top()
  local get = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData
  if type(get) ~= "function" then return nil end
  return entry(plain(try(get, activeIndex())))
end

function Control.Active()
  local get = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData
  if type(get) ~= "function" then return {} end
  local out = {}
  for i = 1, Control.Count() do
    local e = entry(plain(try(get, i)))
    if e then out[#out + 1] = e end
  end
  return out
end

--------------------------------------------------------------------------------
-- Saying it
--------------------------------------------------------------------------------

local function seconds(n)
  if type(n) ~= "number" or n <= 0 then return nil end
  if n >= 10 then return ("%ds"):format(math.floor(n + 0.5)) end
  return ("%.1fs"):format(n)
end

-- One line for a lockout: the schools that are shut and the spells that are not. Returns nil
-- when the player knows nothing in any open school, because "nothing is open" is worth saying
-- but an empty list dressed up as advice is not.
function Control.OpenLine(mask)
  local open = Control.Open(mask)
  if #open == 0 then return nil end
  local names, n = {}, 0
  for i = 1, #open do
    for j = 1, #open[i].spells do
      n = n + 1
      if n <= NAME_CAP then names[#names + 1] = open[i].spells[j] end
    end
    if n >= NAME_CAP then break end
  end
  if #names == 0 then return nil end
  return table.concat(names, ", ")
end

function Control.Line(e)
  if type(e) ~= "table" then return nil end
  local left = seconds(e.left) or seconds(e.duration)
  if e.kind == "SCHOOL_INTERRUPT" then
    local which = Control.SchoolText(e.school) or "That school"
    local line = ("%s locked%s."):format(which, left and (" for " .. left) or "")
    local open = Control.OpenLine(e.school)
    if open then line = line .. " Still up: " .. open .. "." end
    return line
  end
  return ("%s%s."):format(e.spell or e.kind, left and (" for " .. left) or "")
end

local function announce(e)
  local o = ns.Hype and ns.Hype.Opts and ns.Hype.Opts() or {}
  if o.on == false then return end
  local now = plain(try(GetTime)) or 0
  if now - lastCall < CALL_GAP then return end
  lastCall = now

  local interrupt = (e.kind == "SCHOOL_INTERRUPT")
  local schools = interrupt and Control.Schools(e.school) or nil
  local title = interrupt
    and (((#schools > 0) and table.concat(schools, "+"):upper() or "SCHOOL") .. " LOCKED")
    or (e.spell or e.kind):upper()
  if ns.Stage and ns.Stage.Banner then
    pcall(ns.Stage.Banner, title, interrupt and AMBER or RED, Control.Line(e) or "", { size = 2 })
  end
  if ns.Hype and ns.Hype.Sfx then pcall(ns.Hype.Sfx, interrupt and "sig_hush" or "sig_bonk") end
  if ns.Hype and ns.Hype.Say then pcall(ns.Hype.Say, interrupt and "locked" or "controlled", 2) end
end

--------------------------------------------------------------------------------
-- Keeping score
--------------------------------------------------------------------------------

local function db()
  local d = GodslayerDB
  if type(d) ~= "table" then return nil end
  d.control = d.control or {}
  d.control.log = d.control.log or {}
  d.control.byType = d.control.byType or {}
  d.control.bySchool = d.control.bySchool or {}
  return d.control
end

local function record(e)
  local c = db()
  local secs = e.duration or e.left or 0
  session.byType[e.kind] = (session.byType[e.kind] or 0) + 1
  if e.kind == "SCHOOL_INTERRUPT" then
    session.locked = session.locked + secs
    for _, name in ipairs(Control.Schools(e.school)) do
      session.bySchool[name] = (session.bySchool[name] or 0) + 1
      if c then c.bySchool[name] = (c.bySchool[name] or 0) + 1 end
    end
  else
    session.controlled = session.controlled + secs
  end
  if secs > 0 and (not session.worst or secs > session.worst.seconds) then
    session.worst = { seconds = secs, kind = e.kind, spell = e.spell }
  end
  if not c then return end
  c.byType[e.kind] = (c.byType[e.kind] or 0) + 1
  c.log[#c.log + 1] = { kind = e.kind, spell = e.spell, d = secs, school = e.school, t = plain(try(time)) }
  while #c.log > KEEP do table.remove(c.log, 1) end
end

-- The engine's own duration for crowd control that landed on *you*, handed to the part of the
-- addon that is already measuring what this server does to a second one. This is a better number
-- than the one an aura read gives, because it is the figure the engine itself is counting down.
local function feedDR(e)
  if e.kind == "SCHOOL_INTERRUPT" then return end
  if not (ns.Aura and ns.Aura.NoteLanding and ns.PVP) then return end
  local name = e.id and ns.PVP_BY_ID and ns.PVP_BY_ID[e.id] or nil
  local s = name and ns.PVP[name] or nil
  if not s then return end
  local me = plain(try(UnitGUID, "player"))
  if type(me) ~= "string" then return end
  pcall(ns.Aura.NoteLanding, me, s.dr or 0, e.duration or e.left, name or e.spell)
end

--------------------------------------------------------------------------------
-- Events
--------------------------------------------------------------------------------

local h = Control.handlers

-- The payload on this build is (unitTarget, effectIndex). Older builds sent nothing, so an
-- absent unit is treated as the player rather than thrown away.
function h.LOSS_OF_CONTROL_ADDED(unit, index)
  unit = str(unit)
  if unit and unit ~= "player" then return end
  local get = C_LossOfControl and C_LossOfControl.GetActiveLossOfControlData
  local e = entry(plain(try(get, num(index) or activeIndex())))
  if not e then e = Control.Top() end
  if not e or e.show == SHOW_NONE then return end
  record(e)
  feedDR(e)
  announce(e)
  if ns.Log then
    ns.Log("control", ("%s %s for %s"):format(e.kind, e.spell or "?",
      seconds(e.duration or e.left) or "an unknown time"))
  end
end

function h.PLAYER_CONTROL_LOST()
  controlSince = plain(try(GetTime))
end

function h.PLAYER_CONTROL_GAINED()
  if not controlSince then return end
  local now = plain(try(GetTime)) or controlSince
  local held = now - controlSince
  controlSince = nil
  if held <= 0 then return end
  -- Only the measured half goes here: the entry's own duration was already counted when it
  -- landed, and adding this on top would double every stun in the tally.
  session.held = (session.held or 0) + held
end

--------------------------------------------------------------------------------
-- Command
--------------------------------------------------------------------------------

local function schoolName(mask)
  return Control.SchoolText(mask) or ("school " .. tostring(mask))
end

function Control.Command(rest)
  rest = (rest or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()

  if not C_LossOfControl then
    ns.Print("This client has no loss-of-control data to read.")
    return
  end

  if rest == "open" then
    local mine = Control.Known()
    if #mine == 0 then
      ns.Print("I could not read your spellbook for anything in the PvP table.")
      return
    end
    local top = Control.Top()
    local mask = (top and top.kind == "SCHOOL_INTERRUPT") and top.school or 0
    local groups, order = {}, {}
    for i = 1, #mine do
      local s = mine[i]
      if not groups[s.school] then groups[s.school] = {} order[#order + 1] = s.school end
      local g = groups[s.school]
      g[#g + 1] = s.name
    end
    table.sort(order, function(a, b) return #groups[a] > #groups[b] end)
    ns.Print(("%d of your spells are in the client's PvP table, by school:"):format(#mine))
    for i = 1, #order do
      local m = order[i]
      ns.Print(("  %-18s %s%s"):format(schoolName(m), table.concat(groups[m], ", "),
        locked(m, mask) and "   LOCKED" or ""))
    end
    if mask > 0 then ns.Print(("%s is locked right now."):format(schoolName(mask))) end
    return
  end

  local active = Control.Active()
  if #active > 0 then
    ns.Print(("%d thing%s on you:"):format(#active, #active == 1 and "" or "s"))
    for i = 1, #active do ns.Print("  " .. (Control.Line(active[i]) or active[i].kind)) end
    return
  end

  ns.Print("Nothing has you right now.")
  local c = db()
  local rows = {}
  for kind, n in pairs(session.byType) do rows[#rows + 1] = { kind, n } end
  table.sort(rows, function(a, b) return a[2] > b[2] end)
  if #rows > 0 then
    local parts = {}
    for i = 1, math.min(#rows, 5) do parts[#parts + 1] = rows[i][1]:lower():gsub("_", " ") .. " " .. rows[i][2] end
    ns.Print("This session: " .. table.concat(parts, ", ") .. ".")
  end
  -- Two different numbers and only one of them is a measurement. `controlled` is the sum of what
  -- each effect said it would last, which double-counts two stuns that overlapped; `held` is the
  -- gap the engine itself left between losing control and getting it back. The measured one is
  -- the one worth saying out loud.
  if (session.held or 0) > 0 then
    ns.Print(("%.0f seconds of this session you could not act at all."):format(session.held))
  elseif session.controlled > 0 then
    ns.Print(("%.0f seconds of control landed on you, by what each one claimed."):format(session.controlled))
  end
  if session.worst then
    ns.Print(("The worst single one was %s, %s."):format(session.worst.spell or session.worst.kind,
      seconds(session.worst.seconds) or "?"))
  end
  local schools = {}
  for name, n in pairs((c and c.bySchool) or {}) do schools[#schools + 1] = { name, n } end
  table.sort(schools, function(a, b) return a[2] > b[2] end)
  if #schools > 0 then
    local parts = {}
    for i = 1, math.min(#schools, 4) do parts[#parts + 1] = schools[i][1] .. " " .. schools[i][2] end
    ns.Print("Schools locked on you, all time: " .. table.concat(parts, ", ") .. ".")
  end
  if #rows == 0 and #schools == 0 then
    ns.Print("Nothing has had you yet either. /godslayer control open shows your spells by school.")
  end
end

function Control.Init()
  if not C_LossOfControl then
    if ns.Log then ns.Log("control", "no C_LossOfControl on this client") end
    return
  end
  -- The spellbook is rebuilt once a little after login, when it is actually populated.
  local after = C_Timer and C_Timer.After
  if type(after) == "function" then try(after, 6, function() Control.Known(true) end) end
end
