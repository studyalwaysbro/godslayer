# Godslayer PvP data, build 1.60.1.70790

164 spells read from the client.

## Diminishing groups

The client's own numbers. A spell with no group is one the game does not diminish, which
is worth reading twice before you trust a table from another expansion.

| group | label | members |
|---|---|---|
| 1 | Entangling Roots | Entangling Roots, Frost Nova |
| 4 | Hammer of Justice | Cheap Shot, Hammer of Justice, Shockwave, War Stomp |
| 8 | Mind Control | Mind Control |
| 16 | Polymorph | Banish, Chastise, Confounding Flash, Gouge, Hibernate, Polymorph, Repentance, Sap, Scatter Shot, Wyvern Sting |
| 32 | Fear | Fear, Howl of Terror, Intimidating Shout, Psychic Scream, Scare Beast, Seduction |
| 64 | Counterspell - Silenced | Counterspell - Silenced, Silence |
| 128 | Kidney Shot | Kidney Shot |

Spells with a mechanic but **no** diminishing group (9): Blessing of Protection, Blind, Concussive Shot, Divine Protection, Divine Shield, Ice Block, Lacerate, Power Word: Shield, Rip

## Shared cooldown groups

The lock is the **casting** spell's own category cooldown applied to the whole group, not
one number per group: in category 56, Power Word: Shield locks the group for 4s and Lay on
Hands locks the same group for 1200s. Each member is listed with what casting it costs.

| id | name | casting this | locks the group for |
|---|---|---|---|
| 2 | Direct Damage - Spell | Aimed Shot | 6s |
| 2 | Direct Damage - Spell | Multi-Shot | 6s |
| 19 | Quick Damage - Spell | Earth Shock | 6s |
| 19 | Quick Damage - Spell | Exorcism | 15s |
| 19 | Quick Damage - Spell | Fire Blast | 8s |
| 19 | Quick Damage - Spell | Flame Shock | 6s |
| 19 | Quick Damage - Spell | Frost Shock | 6s |
| 19 | Quick Damage - Spell | Ice Lance | 8s |
| 19 | Quick Damage - Spell | Mind Blast | 8s |
| 33 | Mez | Gouge | 10s |
| 33 | Mez | Scare Beast | 30s |
| 35 | Direct Damage (AE) - Spell | Fire Nova | 10s |
| 35 | Direct Damage (AE) - Spell | Frost Nova | 25s |
| 37 | Invulnerability | Divine Protection | 300s |
| 37 | Invulnerability | Divine Shield | 300s |
| 37 | Invulnerability | Ice Block | 300s |
| 39 | Shapeshift | Shadowform | 1.5s |
| 39 | Shapeshift | Vanish | 300s |
| 44 | Speed | Blink | 15s |
| 44 | Speed | Charge | 15s |
| 44 | Speed | Sprint | 300s |
| 56 | Instant Heal - Spell | Lay on Hands | 1200s |
| 56 | Instant Heal - Spell | Power Word: Shield | 4s |
| 230 | Totem (Grounding) | Grounding Totem | 15s |
| 230 | Totem (Grounding) | Grounding Totem Effect | 15s |
| 1151 | Talent - DPS | Combustion | 180s |
| 1151 | Talent - DPS | Presence of Mind | 180s |
| 2404 | Crusader Strike | Hammer of the Righteous | 6s |
| 2404 | Crusader Strike | Holy Strike | 10s |

## Where the PvP duration differs from the normal one

Nothing in this set. Every tracked spell lasts the same against a player.

## Schools, and what an interrupt locks

A Counterspell or a Kick locks the **school** of the spell it hit, not the spell. These are
the masks the client gives each spell, so a lockout can be turned into a list of what is
still castable instead of a bare "interrupted".

| mask | school | spells here |
|---|---|---|
| 1 | Physical | Adrenaline Rush, Aimed Shot, Ambush, Backstab, Bear Form, Berserk, Berserker Rage, Bestial Wrath, Cannibalize, Cat Form, Charge, Cheap Shot, Cold Snap, Death Wish, Dire Bear Form, Disengage, Dispersion, Divine Storm, Eviscerate, Execute, Feign Death, Feral Charge, Ferocious Bite, Gouge, Hamstring, Intercept, Intimidating Shout, Kidney Shot, Lacerate, Last Stand, Maul, Metamorphosis, Moonkin Form, Multi-Shot, Mutilate, Nature's Swiftness, Preparation, Presence of Mind, Primal Bite, Rage of the Farseer, Readiness, Recklessness, Rip, Sap, Scatter Shot, Shackle Undead, Shadowmeld, Shield Wall, Shockwave, Shoot, Shred, Sniper Shot, Sprint, Stealth, Stoneform, Stormstrike, Vanish, Victory Rush, War Stomp, Will of the Forsaken |
| 2 | Holy | Avenging Wrath, Blessing of Freedom, Blessing of Protection, Chastise, Confounding Flash, Contingency Plan, Divine Grace, Divine Protection, Divine Shield, Exorcism, Fear Ward, Hammer of Justice, Hammer of Wrath, Hammer of the Righteous, Holy Fire, Holy Nova, Holy Shock, Holy Strike, Judgement, Lay on Hands, Pain Suppression, Penance, Power Infusion, Power Word: Shield, Repentance, Smite, Swift Judgement, Templar's Bulwark |
| 4 | Fire | Blast Wave, Combustion, Conflagrate, Fire Blast, Fire Nova, Fireball, Flame Shock, Flamestrike, Incinerate, Lava Burst, Living Bomb, Pyroblast, Scorch, Soul Fire |
| 8 | Nature | Barkskin, Blind, Chain Lightning, Chimera Shot, Earth Shock, Elemental Mastery, Entangling Roots, Ghost Wolf, Grounding Totem, Grounding Totem Effect, Hibernate, Innervate, Lightning Bolt, Scare Beast, Water Shield, Wrath, Wyvern Sting |
| 16 | Frost | Blizzard, Cone of Cold, Freezing Trap, Frost Blast, Frost Nova, Frost Shock, Frostbolt, Ice Barrier, Ice Block, Ice Lance, Icy Veins |
| 32 | Shadow | Banish, Dark Sacrifice, Death Coil, Fear, Howl of Terror, Mind Blast, Mind Control, Mind Flay, Psychic Scream, Seduction, Shadow Bolt, Shadow Word: Death, Shadowburn, Shadowform, Silence, Wrack |
| 64 | Arcane | Arcane Barrage, Arcane Blast, Arcane Explosion, Arcane Missiles, Arcane Power, Arcane Shot, Arcane Wrath, Blink, Concussive Shot, Counterspell - Silenced, Evocation, Moonfire, Polymorph, Starfall, Starfire, Starsurge |

Spells in more than one school (2): Chaos Bolt (124), Frostfire Bolt (20)

Spells the client gives no school (0): none

## Longest cooldowns

| spell | cooldown |
|---|---|
| Recklessness | 1800s |
| Shield Wall | 900s |
| Cold Snap | 600s |
| Preparation | 600s |
| Evocation | 480s |
| Innervate | 360s |
| Adrenaline Rush | 300s |
| Blind | 300s |
| Readiness | 300s |
| Templar's Bulwark | 300s |
| Arcane Power | 180s |
| Avenging Wrath | 180s |
| Berserk | 180s |
| Death Wish | 180s |
| Elemental Mastery | 180s |
| Fear Ward | 180s |
| Icy Veins | 180s |
| Intimidating Shout | 180s |
| Last Stand | 180s |
| Nature's Swiftness | 180s |
| Pain Suppression | 180s |
| Power Infusion | 180s |
| Rage of the Farseer | 180s |
| Stoneform | 180s |
| Bestial Wrath | 120s |
