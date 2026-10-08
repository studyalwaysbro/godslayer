# Godslayer

**A World of Warcraft: Forever addon for people who looked at a 30-guild pantheon and thought "that's a lot of honor."**

Prometheus stole fire from Olympus. We kept the torch and came back for the rest.

Godslayer counts every kill you land on `OLYMPUS` and the whole Olympus guild network, scores it, hands you increasingly unhinged titles, and ranks you against your guildmates. Then it gives you a button that brags about it in guild chat.

Made by **The True Torchmen**. For the Horde.

## What it does

- **Counts your Olympus kills.** Every unique player, which guild they wore, how many times, how many were your killing blow.
- **Scores them.** 5 points for a member of the original `OLYMPUS`. 1 point for any other guild in the network (Olympus Kitchen, OLYMPUS BETZ, OLYMPUS LXX, all hundred-and-something of them).
- **Guild leaderboard.** Every guildmate running Godslayer shows up, ranked by points. No setup.
- **50+ brag lines.** One click posts your numbers to guild chat in a new way each time.
  > Zeus called. He wants his 14 guildies back. They're still running from the graveyard.
- **Titles.** Start as an Unlit Torch. Work up through Heretic, Temple Robber, Thief of Fire and Pantheon Problem to Godslayer. There is one title above Godslayer. You will have to earn it to read it.
- **Kill streaks.** Double Sacrilege. Triple Heresy. Titanomachy.
- **Regicide.** Kill the King of Olympus himself and the addon makes sure you never forget it. Neither will the leaderboard.
- **Tooltip tags.** Mouse over an Olympian and see what they're worth and how often you've already collected.

## Install

1. Download **Godslayer-x.y.z.zip** from the [latest release](../../releases/latest).
2. Unzip it. You get a folder called `Godslayer`.
3. Move that folder into `World of Warcraft/_classic_beta_/Interface/AddOns/`
   (after launch the folder may have a different name than `_classic_beta_`; use whichever one has your Forever `Interface` folder).
4. Fully restart the game. On the character screen click **AddOns** and make sure **Godslayer** is ticked.
5. In game, type `/godslayer`.

Turn on **enemy nameplates** (default key: V). The addon learns who is in which guild from nameplates, your target and your mouseover.

## Commands

| Command | What it does |
|---|---|
| `/godslayer` or `/slay` | Open the window |
| `/godslayer stats` | Your totals, only you see it |
| `/godslayer share` | Post a brag line to guild chat |
| `/godslayer top` | Post the top 3 to guild chat |
| `/godslayer demo` | Preview the kill banner |
| `/godslayer add <guild>` | Count a guild with no "olympus" in its name |
| `/godslayer ignore <guild>` | Stop counting a guild |
| `/godslayer help` | Everything else |

## How a kill counts

You get credit when you land the killing blow, when someone in your group does, or when you earn honorable-kill credit for an enemy who dies next to you. The same death never counts twice. A kill scores once the addon has seen the victim's guild tag, so if you one-shot someone from stealth it may take a mouseover of the corpse to register.

Battleground kills mostly will not count. The game hides enemy identities from addons in instanced PvP. This is a world PvP addon. Go outside.

## Which guilds count

Any guild with "olympus" in the name, however they capitalise or disguise it (`0LYMPUS`, `OLYMPVS`, we see you). Plus a short list of network guilds that dodge the word, which lives in [`Godslayer/Data.lua`](Godslayer/Data.lua) next to the brag lines. Edit either list freely.

## Is this allowed?

Yes. Godslayer only reads what the game gives every addon. It does not automate anything, does not touch the combat log, and does not play the game for you. It only ever talks in **your own guild chat**, and only when **you** click the button. It never whispers, emotes at or messages the people you kill.

Killing the other faction on a PvP realm is the game. Be a menace with a sword, not with a keyboard: keep it in guild chat and leave people alone in whispers.

## For tinkerers

    lua tests/run.lua          # scenario tests, Lua 5.1
    lua tests/fuzz.lua 3000    # 3,000 random sessions against a fake client

`tests/mock.lua` is a small stand-in for the game API, including the "secret values" the Forever client uses. Bug reports and new brag lines are welcome in Issues. If a kill does not register, `/godslayer log` shows what the addon saw.

## Legal-ish

Not affiliated with or endorsed by Blizzard Entertainment or by anyone mentioned in a brag line. World of Warcraft is a trademark of Blizzard Entertainment. It's a joke addon with a real scoreboard. MIT licensed.
