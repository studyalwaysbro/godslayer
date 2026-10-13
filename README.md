# Godslayer

**A World of Warcraft: Forever addon for people who looked at a 30-guild pantheon and thought "that's a lot of honor."**

Prometheus stole fire from Olympus. We kept the torch and came back for the rest.

Godslayer counts every kill you land on `OLYMPUS` and the whole Olympus guild network, scores it, hands you increasingly unhinged titles, and ranks you against your guildmates. Then it gives you a button that brags about it in guild chat.

Made by **The True Torchmen**. For the Horde.

## What it does

- **Counts your Olympus kills.** Every unique player, which guild they wore, how many times, how many were your killing blow.
- **Scores them.** 5 points for a member of the original `OLYMPUS`. 1 point for any other guild in the network (Olympus Kitchen, OLYMPUS BETZ, OLYMPUS LXX, all hundred-and-something of them).
- **Guild leaderboard.** Every guildmate running Godslayer shows up, ranked by points. No setup.
- **65+ brag lines.** One click posts your numbers to guild chat in a new way each time. Some of them now name your nemesis. There is also a button that posts one victim's whole record.
  > Zeus called. He wants his 14 guildies back. They're still running from the graveyard.
- **Titles.** Start as an Unlit Torch. Work up through Heretic, Temple Robber, Thief of Fire and Pantheon Problem to Godslayer. There is one title above Godslayer. You will have to earn it to read it.
- **Kill streaks.** Double Sacrilege. Triple Heresy. Titanomachy.
- **Regicide.** Kill the King of Olympus himself and the addon makes sure you never forget it. Neither will the leaderboard.
- **A dossier on everyone you kill.** Click a name in the kill log. Level, race, class, guild, their rank inside it, PvP title, where you killed them, what time of day they usually die, your best day on them, and the last dozen kills one by one.
- **They get titles too.** One kill makes someone a Fresh Sacrifice. Five makes them a Loyalty Card Holder. Keep going and you can claim them as a dependent.
- **Hit list.** Every Olympian you have seen and not killed yet, with where you saw them last. Homework.
- **Stats.** Kills by class, by zone, by guild rank and by hour of the day, plus your nemesis, your biggest upset and the highest level you have dropped.
- **A louder kill banner.** "Level 34 Dwarf Paladin, Captain. Stranglethorn Vale. Third time today."
- **Tooltip tags.** Mouse over an Olympian and see what they're worth, how often you've already collected, and whether they are still on the hit list.
- **Your kill song, and an announcer who takes Olympus personally.** The first player you kill starts a hunt: your own song begins and FIRST BLOOD is called. Every kill is heard the instant it lands, a blade that rings one note higher each time. The rungs are spaced so the top ones stay rare: MEGA KILL at two, ULTRA KILL at three, GODLIKE at five, UNSTOPPABLE at seven, BEYOND GODLIKE at ten, GODSLAYER at fifteen, and a call every five or ten kills after that, up to fifty. Between rungs the announcer mostly keeps quiet, which is why the next call lands. Each kill keeps the hunt going another 90 seconds. Die and you get SHUT DOWN.
- **Moments.** Some kills are more than a number. REVENGE on the player you were fighting when you died. DOMINATION over one you keep killing. GIANT SLAYER for a victim well above your level, and a sad trombone for one far below it. OUTNUMBERED when you were alone against a crowd. COMEBACK after a bad run. A dry word about the victim's class, now and then ("The bubble was on cooldown.").
- **DENIED.** Interrupt an enemy player's spell and you hear it, see it, and now and then get told about it.
- **Duels.** Won or lost, the announcer has an opinion.
- **A banner that moves.** The words slam in and throw light: a streak, a glow, a shockwave. Bigger moments add turning rays, claw marks for kills in a row, and a flash at the edges of the screen. Nothing covers the middle, where the fight is.
- **The fuse.** A thin bar under the banner burns down the time you have left to kill again. It refills on every kill and beats red in the last ten seconds.
- **The hunt card.** When a hunt of three kills or more ends, you get the sum of it and a grade stamped on: C, B, A, S, and one above S.
- **The mix.** While the announcer speaks over the hunt's music, the music steps back, then returns. The hunt theme has a second, bigger half that takes over at five kills.
- **Olympus kills get their own script.** A GOD BLEEDS. DOUBLE SACRILEGE. TITANOMACHY. Then the points, out loud: one for the network, five for the King's own guild. Then, now and then, a dry remark ("Zeus felt that one."). Earn a new title and the announcer says it. Kill the King and everybody within earshot of your speakers will know.
- **Kills in a row.** Two kills within twelve seconds is a DOUBLE KILL. Then TRIPLE KILL, QUAD KILL and RAMPAGE, called before the rung, with a crowd under the big ones.
- **Six announcers, each a character with a script of their own.** Titan, deep and huge. Herald, fierce and sharp. Valkyrie, a shield-maiden who chooses the slain and keeps choosing yours. Frostbite, an ice witch having a lovely time ("Olympus is a hill now! Great for sledding!"). The Naturalist, calm and British, filming a documentary about you ("A rampage. The camera crew has asked to leave."). Sable, who is only here because the stream was boring. By default a different one takes each hunt. `/godslayer hype pack` pins one, `/godslayer hype audition frost` plays every line of one.
- **The spotter.** A living Olympian comes into view: a horn, their name and guild on screen, and the announcer says so. The King gets his own call.
- **The end of a hunt.** A heartbeat and a word with ten seconds left, so you can do something about it. Then the card, and the sum of it in chat: kills, points, best run. Ten kills without dying is a FLAWLESS HUNT. Beat your best hunt and you hear about it at the kill that does it.
- **A hunt theme.** No song of your own? The addon comes with one, so the first kill starts music for everybody.
- **The guild feed.** When a guildmate's score goes up, you get a line in chat and, now and then, the announcer mentions it.

## Install

1. Download **Godslayer-x.y.z.zip** from the [latest release](../../releases/latest).
2. Unzip it. You get a folder called `Godslayer`.
3. Move that folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`
   (after launch the folder may have a different name than `_classic_beta_`; use whichever one has your Forever `Interface` folder).
4. Fully restart the game. On the character screen click **AddOns** and make sure **Godslayer** is ticked.
5. In game, type `/godslayer`.

Turn on **enemy nameplates** (default key: V). The addon learns who is in which guild from nameplates, your target and your mouseover.

## Your kill song

Godslayer comes with a hunt theme. To hunt to your own song instead:

1. Make a folder called `GodslayerMusic` next to the `Godslayer` folder, in `Interface/AddOns/`.
2. Put your song in it, named `kill.mp3` or `kill.ogg`.
3. Fully restart the game.

Updates never touch that folder. The song plays as game music, so it replaces the zone music, follows your music volume slider and fades the way the game's own tracks do.

Try it without killing anyone:

| Command | What it plays |
|---|---|
| `/godslayer hype test` | An ordinary kill. Again inside 12 seconds for a double kill, inside 90 to climb the rungs |
| `/godslayer hype test olympus` | An Olympus kill, with the points |
| `/godslayer hype test king` | Regicide |
| `/godslayer hype test spot` | An Olympian coming into view. `test king spot` for the King |
| `/godslayer hype test moment revenge` | A moment. Also `dominate`, `giant`, `shame`, `outnumbered`, `comeback`, `clutch`, `class` |
| `/godslayer hype test denied` | A spell interrupted |
| `/godslayer hype test duel` | A duel won. `test duel lost` for the other kind |
| `/godslayer hype test card` | Ends the test hunt and grades it |
| `/godslayer hype audition <name>` | Every line of one announcer, with the words in chat |
| `/godslayer hype say <line>` | One line, by name |
| `/godslayer hype stop` | Ends the hunt and fades the music |

`/godslayer hype` shows the settings. `pack <name>` pins an announcer and `pack mix` goes back to a different one each hunt; `mix <name> off` leaves one out of the mix. On or off: `music`, `voice`, `guild`, `sfx` (every sound under the voice), `spot`, `multi` (double kill and up), `asides` (the remarks), `theme`, `moments`, `barks` (the short word between rungs), `deny`, `duels`, `fx` (banner light and motion; off gives plain words), `fuse`, `duck` (the music stepping back), `photo` (a screenshot of your biggest moments, off unless you ask). `channel master`, `dialog` or `sfx` picks which volume slider the announcer follows. `window <seconds>` sets how long a hunt lasts, `blows` counts only your own killing blows, `all` counts every kill you get credit for. Pretend kills score nothing.

## How the voice was made

Every line is in `tools/voice_script.json`: six packs, five scripts. `tools/build_voice.py` asks a voice service for a take of each line, has the take transcribed back and throws it away if the words are wrong or it runs long. A kill call gets three good takes and the fiercest is kept (the most even one, for the Naturalist). The kept take gets the arena treatment with ffmpeg, with the pack's own impact under it: a boom for Titan, a war drum and a sword for Valkyrie, breaking ice for Frostbite. The same script builds the sound effects and the hunt theme. The light the banners are made of is drawn by `tools/build_art.py`.

`tools/voice_report.md` lists every clip, the take that was kept and what the transcription heard. `tools/audition.html` is a page with a button for every clip; open it in a browser to listen through a pack in a minute.

`tools/tune_announcer.py /path/to/GodslayerMusic/kill.mp3` re-pitches every line toward the key of your song and writes the result to `GodslayerMusic/voice`, which the addon uses first. It is optional.

## Commands

| Command | What it does |
|---|---|
| `/godslayer` or `/slay` | Open the window |
| `/godslayer stats` | Your totals, only you see it |
| `/godslayer dossier <name>` | Everything on someone you killed, only you see it |
| `/godslayer nemesis` | The dossier of whoever you have killed most |
| `/godslayer hitlist` | Olympians seen and not killed yet |
| `/godslayer share` | Post a brag line to guild chat |
| `/godslayer top` | Post the top 3 to guild chat |
| `/godslayer demo` | Preview the kill banner |
| `/godslayer add <guild>` | Count a guild with no "olympus" in its name |
| `/godslayer ignore <guild>` | Stop counting a guild |
| `/godslayer help` | Everything else |

## How a kill counts

You get credit when you land the killing blow, when someone in your group does, or when you earn honorable-kill credit for an enemy who dies next to you. The same death never counts twice. A kill scores once the addon has seen the victim's guild tag, so if you one-shot someone from stealth it may take a mouseover of the corpse to register.

The dossier is built from what the game shows about a player you can see: their nameplate, your target, your mouseover. The game is allowed to hide any of it, and then that line of the dossier is simply missing. Kills made before version 1.1 keep their counts but have no per-kill details.

Battleground kills mostly will not count. The game hides enemy identities from addons in instanced PvP. This is a world PvP addon. Go outside.

## Which guilds count

Any guild with "olympus" in the name, however they capitalise or disguise it (`0LYMPUS`, `OLYMPVS`, we see you). Plus a short list of network guilds that dodge the word, which lives in [`Godslayer/Data.lua`](Godslayer/Data.lua) next to the brag lines. Edit either list freely.

## Is this allowed?

Yes. Godslayer only reads what the game gives every addon. It does not automate anything, does not touch the combat log, and does not play the game for you. It only ever talks in **your own guild chat**, and only when **you** click the button. It never whispers, emotes at or messages the people you kill. The dossiers are built only from what the game already shows you about a player on screen, and they stay on your machine: guildmates receive your totals, never your notes on anyone.

Killing the other faction on a PvP realm is the game. Be a menace with a sword, not with a keyboard: keep it in guild chat and leave people alone in whispers.

## For tinkerers

    lua tests/run.lua          # scenario tests, Lua 5.1
    lua tests/fuzz.lua 3000    # 3,000 random sessions against a fake client

`tests/mock.lua` is a small stand-in for the game API, including the "secret values" the Forever client uses. Bug reports and new brag lines are welcome in Issues. If a kill does not register, `/godslayer log` shows what the addon saw.

## Legal-ish

Not affiliated with or endorsed by Blizzard Entertainment or by anyone mentioned in a brag line. World of Warcraft is a trademark of Blizzard Entertainment. It's a joke addon with a real scoreboard. MIT licensed.
