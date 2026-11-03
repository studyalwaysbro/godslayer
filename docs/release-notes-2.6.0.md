**The battleground has an announcer now, and so do you.**

Six new readouts, every one of them spoken:

- **Your rank.** The fourteen-rung ladder is tracked as you climb it: a fanfare and a call when you take a rung, and you will hear about losing one too. Dishonorable kills get the trombone they deserve. `/godslayer rank` shows your rung, the points left, and what tonight's rate makes of it.
- **The battleground reads itself.** When you zone in, the other team is counted and scouted, and the announcer tells you whether they outrank you. When it ends: VICTORY or DEFEAT, with your killing blows on the banner. `/godslayer field`.
- **The flag.** Taken, down, home, called the moment it happens, with the map shut. `/godslayer flag`, and `flag watch` toggles the calls.
- **Crowd control, both ways.** Getting stunned, feared, rooted, silenced, charmed or slowed each gets its own call. An enemy popping an offensive cooldown gets you a warning, and an enemy going immune tells you to hold your spells before you waste them. School lockouts say which school is gone and what is still up: `/godslayer control`.
- **Your death, hit by hit.** The last seconds of your life, with the killing blow on a banner, newest wound first. `/godslayer death`, and `/godslayer recap` for the whole fight by the numbers.
- **Who the guild keeps dying to.** Pooled across guildmates running the addon, with a vouching rule so one bare name cannot fill the board. `/godslayer threat`.

All of it voiced in every pack: Titan, Herald, Valkyrie, Frostbite, Naturalist, Sable.

Underneath, this release went on a diet rather than gaining weight: a profiler now fails the build if the addon costs too many client calls or makes too much garbage per second of battleground, and the hot paths were cut down until it passed with room to spare.

**How to update:** on CurseForge, hit Update. By hand: download **Godslayer-2.6.0.zip** below, close the game fully, replace the `Godslayer` folder in `_forever_/Interface/AddOns/`, start the game. Your kills, titles and leaderboard are kept.
