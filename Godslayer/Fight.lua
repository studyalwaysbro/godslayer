-- Godslayer fight: knowing that a fight with a player has started before anyone has died, and
-- the sound of your own class.
--
-- ENGAGED. You are in combat, and the one you are fighting is an enemy player: your target, the
-- enemy your abilities would land on, or your focus, they are in combat too, and something has
-- passed between you a moment ago (a spell or a swing of yours, a hit on you, or them targeting
-- you where the client says). Or an enemy player on screen has you targeted. Or something has
-- just hit you while an enemy player in combat is on screen and nothing you could attack is in
-- your sights.
-- The combat log is closed to addons, so this is a reading of the room, and it is checked again
-- whenever the room changes: combat starting, a new target, a spell of yours, a hit taken.
--
-- YOUR CLASS. Your own big spells, cast in a fight with a player, make a sound: the sheep when
-- you Polymorph, the choir when you bubble, chains breaking on Blessing of Freedom, a smoke puff
-- on Vanish, a body hitting the floor on Feign Death. Nine classes and the racials that matter.
--
-- FINISHERS. A player who dies to you a moment after one of your spells landed is named by it:
-- EXECUTED, PYROBLASTED, IN THE BACK, DEATH BY WAND. The announcer says it after the kill call.

local _, ns = ...
local plain, try = ns.plain, ns.try
local issecret = issecretvalue or function() return false end

local Fight = { handlers = {} }
ns.Fight = Fight

local HIT_WINDOW = 2.5     -- a hit taken this recently, with an enemy player about, is a fight
local CHECK_GAP = 0.2      -- the room is read at most this often
local ACT_WINDOW = 3       -- a spell or a swing of yours this recently counts as having started something
local SIG_GAP, SIG_GLOBAL = 8, 1.0 -- one spell's sound at most this often, and any two this far apart
local SIG_OFTEN_GAP = 45   -- spells cast all fight long are heard once in a while, not every time
local SIG_AFTER_DRUMS = 1.2 -- the war drums of a fight starting are not talked over by a spell's sound
local FINISH_KB, FINISH_CREDIT = 2.5, 2.0 -- how long after the spell a kill still belongs to it: your killing blow, or a credit while alone

-- spell -> sound (Sounds/sfx/sig_<name>.ogg). The names are the client's own, checked against its game data.
local SIGNATURES = {
  -- mage
  Polymorph = "sheep", ["Ice Block"] = "iceblock", Blink = "blink", ["Frost Nova"] = "nova", Pyroblast = "pyro",
  Combustion = "combust", ["Arcane Power"] = "surge", ["Presence of Mind"] = "surge", ["Icy Veins"] = "surge", ["Cold Snap"] = "reset",
  -- paladin
  ["Divine Shield"] = "bubble", ["Divine Protection"] = "bubble", ["Hammer of Justice"] = "bonk", ["Lay on Hands"] = "angel",
  ["Blessing of Protection"] = "shield", ["Blessing of Freedom"] = "freedom", ["Avenging Wrath"] = "wings", Repentance = "repent",
  -- warrior
  Charge = "charge", Intercept = "charge", Recklessness = "roar", ["Death Wish"] = "roar", ["Shield Wall"] = "wall",
  ["Last Stand"] = "wall", ["Intimidating Shout"] = "shout", Shockwave = "quake",
  -- rogue
  Vanish = "vanish", Blind = "blind", ["Kidney Shot"] = "kidney", ["Cheap Shot"] = "kidney", Sap = "sap", Sprint = "sprint",
  ["Adrenaline Rush"] = "rush", Preparation = "reset",
  -- hunter
  ["Feign Death"] = "feign", ["Freezing Trap"] = "trap", ["Scatter Shot"] = "scatter", ["Bestial Wrath"] = "roar",
  ["Aimed Shot"] = "aimed", Readiness = "reset", Disengage = "leap",
  -- priest
  ["Psychic Scream"] = "scream", ["Power Word: Shield"] = "shield", ["Mind Control"] = "mc", Shadowform = "shadow", Silence = "hush",
  Dispersion = "shadow", ["Power Infusion"] = "surge", ["Pain Suppression"] = "shield",
  -- warlock
  Fear = "fear", ["Death Coil"] = "coil", ["Howl of Terror"] = "howl", ["Chaos Bolt"] = "chaos", Metamorphosis = "meta",
  -- shaman
  ["Chain Lightning"] = "chain", ["Lava Burst"] = "lava", ["Ghost Wolf"] = "wolf", ["Grounding Totem"] = "ground",
  ["Nature's Swiftness"] = "swift", ["Elemental Mastery"] = "surge",
  -- druid
  ["Bear Form"] = "bear", ["Dire Bear Form"] = "bear", ["Cat Form"] = "cat", ["Moonkin Form"] = "owl", Innervate = "innervate",
  ["Entangling Roots"] = "roots", Barkskin = "bark", Starfall = "starfall", Berserk = "roar",
  -- racials
  ["War Stomp"] = "stomp", ["Will of the Forsaken"] = "forsaken", Shadowmeld = "vanish", Stoneform = "wall",
}
Fight.SIGNATURES = SIGNATURES

-- the ones a player casts over and over in one fight
local OFTEN = {
  Polymorph = true, Fear = true, ["Power Word: Shield"] = true, ["Entangling Roots"] = true, ["Chain Lightning"] = true,
  ["Lava Burst"] = true, ["Aimed Shot"] = true, ["Bear Form"] = true, ["Dire Bear Form"] = true, ["Cat Form"] = true,
  ["Moonkin Form"] = true, ["Ghost Wolf"] = true, Charge = true, Intercept = true, Blink = true, ["Frost Nova"] = true,
  ["Hammer of Justice"] = true, ["Kidney Shot"] = true, ["Cheap Shot"] = true, Sap = true, Blind = true, Silence = true,
}

-- spell -> the kind of death it deals, and the words for it on the banner
local FINISHERS = {
  Execute = "execute", Pyroblast = "pyro",
  Fireball = "fire", ["Fire Blast"] = "fire", ["Living Bomb"] = "fire", ["Blast Wave"] = "fire",
  Frostbolt = "shatter", ["Ice Lance"] = "shatter", ["Cone of Cold"] = "shatter",
  ["Arcane Missiles"] = "arcane", ["Arcane Barrage"] = "arcane", ["Arcane Explosion"] = "arcane",
  Eviscerate = "evisc", Backstab = "back", Ambush = "back", Mutilate = "back", Shoot = "wand",
  ["Hammer of Wrath"] = "judged", Judgement = "judged", Exorcism = "judged", ["Divine Storm"] = "judged", ["Hammer of the Righteous"] = "judged",
  Smite = "smite", ["Holy Fire"] = "smite", ["Holy Shock"] = "smite", ["Holy Nova"] = "smite", Penance = "smite",
  ["Mind Blast"] = "mind", ["Shadow Word: Death"] = "mind", ["Mind Flay"] = "mind",
  Shadowburn = "soul", ["Death Coil"] = "soul", ["Chaos Bolt"] = "soul", ["Shadow Bolt"] = "soul", ["Soul Fire"] = "soul", Conflagrate = "soul",
  ["Lightning Bolt"] = "thunder", ["Chain Lightning"] = "thunder", ["Lava Burst"] = "thunder", Stormstrike = "thunder",
  ["Earth Shock"] = "shock", ["Frost Shock"] = "shock", ["Flame Shock"] = "shock",
  ["Aimed Shot"] = "sniped", ["Arcane Shot"] = "sniped", ["Chimera Shot"] = "sniped", ["Multi-Shot"] = "sniped",
  Starfire = "moon", Starsurge = "moon", Moonfire = "moon", Wrath = "moon", Starfall = "moon",
  ["Ferocious Bite"] = "mauled", Maul = "mauled", Rip = "mauled", Shred = "mauled",
}
local TAGS = {
  execute = "EXECUTED", pyro = "PYROBLASTED", fire = "INCINERATED", shatter = "SHATTERED", arcane = "ERASED", evisc = "EVISCERATED",
  back = "IN THE BACK", wand = "DEATH BY WAND", judged = "JUDGED", smite = "SMITED", mind = "MIND BLOWN", soul = "SOUL TAKEN",
  thunder = "THUNDERSTRUCK", shock = "SHOCKED", sniped = "SNIPED", moon = "MOONSTRUCK", mauled = "MAULED",
}
Fight.FINISHERS, Fight.TAGS = FINISHERS, TAGS

-- One id for each spell above, from the client's game data, so a game in another language finds
-- the same spells: the name the client gives each id is read at login and mapped to the English one.
local SPELL_IDS = {
  ["Adrenaline Rush"] = 13750, ["Aimed Shot"] = 19434, Ambush = 8676, ["Arcane Barrage"] = 400610,
  ["Arcane Explosion"] = 1449, ["Arcane Missiles"] = 5143, ["Arcane Power"] = 12042, ["Arcane Shot"] = 3044,
  ["Avenging Wrath"] = 407788, Backstab = 53, Barkskin = 22812, ["Bear Form"] = 5487, Berserk = 417141,
  ["Bestial Wrath"] = 19574, ["Blast Wave"] = 11113, ["Blessing of Freedom"] = 1044,
  ["Blessing of Protection"] = 1022, Blind = 2094, Blink = 1953, ["Cat Form"] = 768, ["Chain Lightning"] = 421,
  ["Chaos Bolt"] = 403629, Charge = 100, ["Cheap Shot"] = 1833, ["Chimera Shot"] = 409433, ["Cold Snap"] = 12472,
  Combustion = 11129, ["Cone of Cold"] = 120, Conflagrate = 17962, ["Death Coil"] = 6789, ["Death Wish"] = 12328,
  ["Dire Bear Form"] = 9634, Disengage = 781, Dispersion = 425294, ["Divine Protection"] = 498,
  ["Divine Shield"] = 642, ["Divine Storm"] = 407778, ["Earth Shock"] = 8042, ["Elemental Mastery"] = 16166,
  ["Entangling Roots"] = 339, Eviscerate = 2098, Execute = 5308, Exorcism = 879, Fear = 5782, ["Feign Death"] = 5384,
  ["Ferocious Bite"] = 22568, ["Fire Blast"] = 2136, Fireball = 133, ["Flame Shock"] = 8050,
  ["Freezing Trap"] = 1499, ["Frost Nova"] = 122, ["Frost Shock"] = 8056, Frostbolt = 116, ["Ghost Wolf"] = 2645,
  ["Grounding Totem"] = 8177, ["Hammer of Justice"] = 853, ["Hammer of Wrath"] = 24239,
  ["Hammer of the Righteous"] = 407632, ["Holy Fire"] = 14914, ["Holy Nova"] = 15237, ["Holy Shock"] = 20473,
  ["Howl of Terror"] = 5484, ["Ice Block"] = 11958, ["Ice Lance"] = 400640, ["Icy Veins"] = 425121,
  Innervate = 29166, Intercept = 20252, ["Intimidating Shout"] = 5246, Judgement = 20271, ["Kidney Shot"] = 408,
  ["Last Stand"] = 12975, ["Lava Burst"] = 408490, ["Lay on Hands"] = 633, ["Lightning Bolt"] = 403,
  ["Living Bomb"] = 400613, Maul = 6807, Metamorphosis = 403789, ["Mind Blast"] = 8092, ["Mind Control"] = 605,
  ["Mind Flay"] = 15407, Moonfire = 8921, ["Moonkin Form"] = 24858, ["Multi-Shot"] = 2643, Mutilate = 399956,
  ["Nature's Swiftness"] = 16188, ["Pain Suppression"] = 402004, Penance = 402174, Polymorph = 118,
  ["Power Infusion"] = 10060, ["Power Word: Shield"] = 17, Preparation = 14185, ["Presence of Mind"] = 12043,
  ["Psychic Scream"] = 8122, Pyroblast = 11366, Readiness = 23989, Recklessness = 1719, Repentance = 20066,
  Rip = 1079, Sap = 2070, ["Scatter Shot"] = 19503, ["Shadow Bolt"] = 686, ["Shadow Word: Death"] = 401955,
  Shadowburn = 17877, Shadowform = 15473, Shadowmeld = 20580, ["Shield Wall"] = 871, Shockwave = 440488,
  Shoot = 5019, Shred = 5221, Silence = 15487, Smite = 585, ["Soul Fire"] = 6353, Sprint = 2983, Starfall = 439748,
  Starfire = 2912, Starsurge = 417157, Stoneform = 20594, Stormstrike = 17364, Vanish = 1856, ["War Stomp"] = 20549,
  ["Will of the Forsaken"] = 7744, Wrath = 5176,
}
Fight.SPELL_IDS = SPELL_IDS
local alias = {}

local function opts() return ns.Hype and ns.Hype.Opts() or {} end

local function inCombat()
  return plain(try(UnitAffectingCombat, "player")) == true or plain(try(InCombatLockdown)) == true
end
Fight.InCombat = inCombat

-- an enemy player you could hit, alive
local function enemyPlayer(unit)
  if not plain(try(UnitExists, unit)) or plain(try(UnitIsPlayer, unit)) ~= true then return false end
  if plain(try(UnitCanAttack, "player", unit)) ~= true then return false end
  return plain(try(UnitIsDeadOrGhost, unit)) ~= true
end

-- in combat themselves: true, false, or nil when the client keeps the answer to itself
local function busy(unit)
  local c = try(UnitAffectingCombat, unit)
  if issecret(c) then return nil end
  return c == true
end

local lastHit, lastAct = -1000, -1000 -- lastAct: a spell or a swing of yours while an enemy player was in your sights

-- they have you targeted, where the client will say so
local function onMe(unit)
  local yes = try(UnitIsUnit, unit .. "target", "player")
  return not issecret(yes) and yes == true
end

-- The unit you are fighting, if it is a player. nil when it is not, or nobody can tell.
function Fight.Engaged()
  if not inCombat() then return nil end
  local now = GetTime()
  local hit, acted = now - lastHit <= HIT_WINDOW, now - lastAct <= ACT_WINDOW
  for _, unit in ipairs({ "target", "softenemy" }) do
    -- in your sights and fighting is not enough on its own: they may be busy with a boar of their own.
    -- A fight the client will not confirm needs you to have acted on them.
    if enemyPlayer(unit) then
      local fighting = busy(unit)
      if (fighting == true and (onMe(unit) or acted or hit)) or (fighting == nil and (acted or onMe(unit))) then return unit end
    end
  end
  -- a focus set long ago proves nothing by itself: only them having you targeted does
  if enemyPlayer("focus") and busy("focus") ~= false and onMe("focus") then return "focus" end
  -- hit with nothing at all in your sights: an enemy player fighting on screen is the likeliest one
  local sighted = plain(try(UnitExists, "target")) or plain(try(UnitExists, "softenemy"))
  for i = 1, 40 do
    local unit = "nameplate" .. i
    if enemyPlayer(unit) and busy(unit) == true then
      if onMe(unit) then return unit end
      if hit and not sighted then return unit end
    end
  end
end

-- who it is, as far as the screen says
local function describe(unit)
  local info = { name = ns.FullName and ns.FullName(unit) or nil }
  if ns.UnitTier then
    -- the fight starting is the call; the spotter does not get to say it first
    local was = ns.sweeping
    ns.sweeping = true
    local ok, tier, guild, id = pcall(ns.UnitTier, unit)
    ns.sweeping = was
    if not ok then tier, guild, id = nil, nil, nil end
    info.tier, info.guild = tier, guild
    if tier and ns.IsKing then info.king = ns.IsKing(info.name, tier) or nil end
    info.id = id
  end
  if not info.guild then
    local guild = plain((try(GetGuildInfo, unit)))
    if type(guild) == "string" and guild ~= "" then info.guild = guild end
  end
  return info
end

local lastCheck = -1000
local function check(force)
  if not (ns.Hype and GodslayerDB) then return end
  local now = GetTime()
  if not force and now - lastCheck < CHECK_GAP then return end
  lastCheck = now
  local unit = Fight.Engaged()
  if unit then ns.Hype.Engage(describe(unit)) end
end
Fight.Check = check

-- YOUR CLASS ------------------------------------------------------------------
local sigLast, sigAny = {}, -1000
function Fight.Signature(spell, pretend)
  local name = SIGNATURES[spell]
  if not name or not ns.Hype then return false end
  local o = opts()
  if not pretend then
    if not (o.on and o.class) then return false end
    -- a sheep on a boar in the woods is nobody's business: only in a fight with a player
    if not (ns.Hype.Fighting() or enemyPlayer("target")) then return false end
  end
  local now = GetTime()
  if not pretend then
    local gap = OFTEN[spell] and SIG_OFTEN_GAP or SIG_GAP
    if now - sigAny < SIG_GLOBAL or (sigLast[name] and now - sigLast[name] < gap) then return false end
    if ns.Hype.DrumsAgo and ns.Hype.DrumsAgo() < SIG_AFTER_DRUMS then return false end
  end
  if not ns.Hype.Sfx("sig_" .. name) then return false end
  if not pretend then sigLast[name], sigAny = now, now end -- a preview leaves the real rationing as it was
  return true
end

-- FINISHERS -------------------------------------------------------------------
local lastFinisher -- { key, t, at = the GUID it was aimed at when the client says }

-- The finisher for a kill being called now, used up by it. kb: it was your killing blow.
-- victim: the killed player's GUID when known; a spell aimed at someone else did not kill them.
function Fight.Finisher(kb, victim)
  local f = lastFinisher
  if not f then return nil end
  lastFinisher = nil
  local age = GetTime() - f.t
  local alone = (plain(try(GetNumGroupMembers)) or 0) <= 1
  if f.at and type(victim) == "string" and victim:sub(1, 7) == "Player-" and victim ~= f.at then return nil end
  if age <= FINISH_KB and (kb or (alone and age <= FINISH_CREDIT)) then return f.key, TAGS[f.key] end
end

-- EVENTS ----------------------------------------------------------------------
local function spellName(id)
  id = plain(id)
  if type(id) ~= "number" then return nil end
  local name = plain(try(C_Spell and C_Spell.GetSpellName, id))
  if type(name) ~= "string" and type(GetSpellInfo) == "function" then name = plain((try(GetSpellInfo, id))) end
  return type(name) == "string" and name or nil
end

local h = Fight.handlers

function h.UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  if plain(unit) ~= "player" then return end
  local name = spellName(spellID)
  if not name then return end
  name = alias[name] or name
  local aimed
  for _, u in ipairs({ "target", "softenemy" }) do
    if not aimed and enemyPlayer(u) then aimed = u end
  end
  if aimed then lastAct = GetTime() end
  -- a spell aimed at a player is a fight starting, if combat says so
  if inCombat() and not (ns.Hype and ns.Hype.Fighting()) then check(true) end
  if FINISHERS[name] then
    local at = aimed and plain(try(UnitGUID, aimed))
    lastFinisher = { key = FINISHERS[name], t = GetTime(), at = type(at) == "string" and at or nil }
  end
  Fight.Signature(name)
end

function h.PLAYER_REGEN_DISABLED()
  check(true)
  -- the target and the nameplates can settle a moment after combat starts
  for _, wait in ipairs({ 0.5, 1.5, 3 }) do
    C_Timer.After(wait, function() if inCombat() and not (ns.Hype and ns.Hype.Fighting()) then check() end end)
  end
end

function h.PLAYER_REGEN_ENABLED()
  if ns.Hype then ns.Hype.Disengage() end
end

-- a new face in your sights is looked at at once: the spotter hears the same event right after
local function retarget() if inCombat() then check(true) end end

-- you started swinging: that is doing something to someone
function h.PLAYER_ENTER_COMBAT()
  if not (enemyPlayer("target") or enemyPlayer("softenemy")) then return end
  lastAct = GetTime()
  if inCombat() then check(true) end
end
h.PLAYER_SOFT_ENEMY_CHANGED = retarget
h.PLAYER_TARGET_CHANGED = retarget
h.PLAYER_FOCUS_CHANGED = retarget

-- what UNIT_COMBAT calls an attack on you, landed or not; a heal or mana coming in is not one
local ATTACKS = { WOUND = true, MISS = true, DODGE = true, PARRY = true, BLOCK = true, RESIST = true, ABSORB = true,
                  IMMUNE = true, DEFLECT = true, REFLECT = true, EVADE = true }
function h.UNIT_COMBAT(unit, action)
  if plain(unit) ~= "player" then return end
  if not ATTACKS[plain(action)] then return end
  lastHit = GetTime()
  if inCombat() and not (ns.Hype and ns.Hype.Fighting()) then check() end
end

-- while in combat and not yet sure, look again every second: someone may have walked up
function Fight.Tick()
  if inCombat() and ns.Hype and not ns.Hype.Fighting() then check() end
end

function Fight.Init()
  for english, id in pairs(SPELL_IDS) do
    local here = plain(try(C_Spell and C_Spell.GetSpellName, id))
    if type(here) == "string" and here ~= english and not SIGNATURES[here] and not FINISHERS[here] then alias[here] = english end
  end
  C_Timer.NewTicker(1, Fight.Tick)
end
