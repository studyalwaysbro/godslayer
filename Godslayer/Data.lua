-- Godslayer data: which guilds count, and the brag lines.
-- Edit this file freely; nothing here touches game state.

local _, ns = ...

-- A guild whose name is exactly this (any capitalisation) is the original guild
-- and is worth ORIGINAL_POINTS per kill.
ns.ORIGINAL = "olympus"
ns.ORIGINAL_POINTS = 5
ns.NETWORK_POINTS = 1

-- Any guild whose name contains one of these counts as part of the network.
ns.KEYWORDS = { "olympus" }

-- Network guilds whose names do NOT contain the keyword. Compared after the same
-- lowercase / strip-punctuation pass, so "Special Olmpus II" is "specialolmpusii".
-- Sources (2026-10-07): the Olympus Guild addon's approved list and the Asmute seed list.
ns.AFFILIATES = {
  olympian = true,
  olympians = true,
  hoelympus = true,
  holypmus = true,
  specialolmpus = true,
  specialolmpusii = true,
  theenclave = true,
}

-- The King of Olympus. Killing this character in the original guild is a regicide.
ns.KING = "Asmongold Asmongler"

-- Titles earned by points. The Torchmen stole fire from Olympus once already.
ns.RANKS = {
  { 0, "Unlit Torch" },
  { 1, "Spark" },
  { 5, "Heretic" },
  { 15, "Blasphemer" },
  { 30, "Temple Robber" },
  { 60, "Thief of Fire" },
  { 100, "Titan's Apprentice" },
  { 175, "Bane of Lords" },
  { 275, "Pantheon Problem" },
  { 400, "Prometheus Unbound" },
  { 600, "Godslayer" },
  { 1000, "Reason For The Mute Addon" },
}

-- Kills in a row without dying. Shown on the kill banner only.
ns.STREAKS = {
  [2] = "Double Sacrilege", [3] = "Triple Heresy", [4] = "Quad Blasphemy", [5] = "Titanomachy",
  [7] = "Twilight of the Gods", [10] = "Olympus Is A Hill Now", [15] = "Zeus Has Left The Chat",
}

-- Tokens: {kills} "7 Olympus kills"   {points} "19 points"   {uniques} "5 different Olympians"
--         {orig} "3 from the original OLYMPUS"   {n} {p} {u} {o} are the bare numbers.
--         {rank} your title   {king} "the King himself 2 times"
-- Lines with {n} are only picked at 2+ kills, lines with {orig} or {o} only when you have one,
-- lines with {king} only after a regicide.
-- Keep every line plain ASCII and under about 200 characters; chat cuts off at 255.
ns.PHRASES = {
  "Mount Olympus update: {kills}, {points}. The gods bleed, and they drop nothing.",
  "{kills} and counting. Turns out you can gank a pantheon.",
  "Olympus has 30+ full guilds. I have {kills}. Somebody has to do the census.",
  "Two kinds of players in Forever: people in Olympus, and people farming Olympus. {kills}, {points}.",
  "Dude. DUDE. {kills}. That's actually crazy.",
  "{uniques} sent to the spirit healer. Hope the King issues a decree about it.",
  "Zeus called. He wants his {n} guildies back. They're still running from the graveyard.",
  "{kills}. At this point I should get a rep bar for it.",
  "Personally responsible for {n} Olympus repair bills. You're welcome, Stormwind blacksmiths.",
  "They brought 30 guilds. I brought a keyboard. {kills}, {points}.",
  "Olympus News Network, breaking: local Horde player now at {kills}. More at 11.",
  "{kills}. They needed the whole raid. I needed two globals.",
  "Scoreboard check: {points} off {kills}. The Lords and Captains have been notified.",
  "Another one for the untabarded list. {kills} total.",
  "{orig}. Five points each. The King's own guild pays best.",
  "I don't always PvP, but when I do, the nameplate says OLYMPUS. {kills}.",
  "{kills}. Somewhere a mute addon just got another download.",
  "Asmon said he'd go Hardcore if we got Classic Plus. Good thing he didn't: {kills}.",
  "{uniques} personally introduced to the Alliance graveyard system.",
  "Corpse run speedrun category: any% Olympus. I've started {n} of them.",
  "Lok'tar ogar. {kills}, {points}. The transmog competition is over, I'm wearing their tears.",
  "{kills}. Not a single one of them remembered to salute.",
  "Hunting report: {kills}, {uniques}, {points}. Season stays open.",
  "They march 2,000 deep into Grim Batol. I wait at the flight path. {kills}.",
  "Olympus invited everyone on the server. I'm the one guy who RSVP'd with a crit. {kills}.",
  "{kills}. Every layer, same result.",
  "Icarus flew too close to the sun. {n} Olympians flew too close to me.",
  "The gods of Olympus are immortal. Their guild members have had {n} exceptions so far.",
  "{points} on the board. Achilles had one weak spot. Olympus has about 30,000.",
  "Sisyphus had the boulder. Olympus has the corpse run. {kills}.",
  "Opened Pandora's box. It was just {kills} and a hearthstone on cooldown.",
  "{kills}. If Olympus is Mount Olympus, call me a landslide.",
  "Realm first Sulfuras was cool. Realm first {points} points of Olympus is cooler.",
  "That's {kills}. Is this what the main tank of the Alliance looks like?",
  "For the Horde. {kills}, {points}. The King can dock it from the guild treasury.",
  "Added to the kill-on-sight list of {uniques}. It's mutual.",
  "A 10fps Stormwind can't save them out here. {kills}.",
  "Just doing my part. {kills}, {points}. Would you like to know more?",
  "Res sickness is temporary. Being one of my {kills} is forever.",
  "Olympus guild cap is 1,000. My kill count is working on it: {n} so far.",
  "{kills}. They keep making more guilds. I keep making more room on the scoreboard.",
  "Titans beat the old gods. Torchmen beat Olympus. {kills}, {points}.",
  "Prometheus stole fire from Olympus. We're just here for the rest of it. {kills}.",
  "New title unlocked: {rank}. {kills}, {points}. Olympus HR has been informed.",
  "They call me {rank} now. {kills}. My mother is proud. Zeus is not.",
  "Rank: {rank}. Hobby: {kills}. Employer: the Horde.",
  "{rank} reporting in. {points} of pure, ethically sourced Olympian tears.",
  "The torch is not for warmth. It's for finding them in the dark. {kills}.",
  "Azeroth cleansing report: {kills} scrubbed, {uniques} rinsed, zero remorse.",
  "They pass around invites. We pass the torch. {kills}, {points}.",
  "REGICIDE. I have slain {king}. He said 'dude' on the way down.",
  "Killed {king}. The King is dead. Long live whoever is next in the 30-guild line of succession.",
  "Slew {king}. Somewhere, 30,000 guildmates felt a disturbance in the layer.",
}

-- Used when the counter is still at zero.
ns.PHRASES_ZERO = {
  "Zero Olympus kills so far. The pantheon sleeps safely tonight. For now.",
  "Godslayer installed, counter at 0. Olympus, I am inside your layer.",
  "No Olympus kills yet. Consider this a formal decree of intent.",
}
