**Every class, every guild, together on Slayers.**

**Hunters is now Slayers.** Open the leaderboard and choose **Slayers** to see Godslayer players on
your faction and ruleset ranked #1, #2, #3, and onward. The board includes every class and every
guild. The old `/godslayer hunters` command still works, but `/godslayer slayers` is the new name.

**Live kill news.** When a confirmed player scores, Godslayer can print the result locally, naming
the victim and their class for a single kill when the game provides them. Nothing is posted to a chat channel.
Five quick kills become one line instead of five. Choose everyone, top 10 only, or off with
`/godslayer slayers feed everyone|top10|off`. Two extras stay off unless you turn them on:
`/godslayer slayers feed banner on` also shows each line as a banner, and `/godslayer slayers feed voice on`
adds an announcer line when someone enters the top three.
If you score again before your last kills reached everyone, the next line counts them together.
Live kill news needs both players on 3.1. Players still on 3.0 see your new totals on the board, but
not the live line.

Kills inside battlegrounds and dungeons are shared after you leave because the game blocks addon
whispers there. A batch older than five minutes still updates the board without a chat line.

Sharing now includes your kills as they happen and the victim's name and class when known. Scores are
self-reported, and your client accepts a row only from that row's own authenticated addon-message
sender. This is attribution, not proof that the kill happened. Other clients may keep a received row
for up to seven days. Use `/godslayer slayers off` to stop sending and accepting Slayers traffic.
Copies already received by other players cannot be erased.

**Discovery recovers sooner.** Slayers now retries a stale channel roster, wakes after channel changes,
resumes after combat or an instance, and responds in both directions when another Godslayer user finds
you. `/godslayer slayers status` prints compact diagnostics for discovery and delivery problems. A
directory containing only you is now reported as healthy instead of as an error.

**Four volume controls.** Options now has Master, Music, Voice, and Effects levels from 0 to 100.
At 100, Godslayer plays at full game volume as before. Below 100, voice briefly borrows the Dialog
slider and effects borrow the Ambience slider while a line plays; songs follow your Music slider.
Godslayer restores a borrowed slider only if you did not move it while a sound was playing.
`/godslayer volume` prints all four levels. `/godslayer volume 50` sets Master, while
`/godslayer volume music|voice|effects 50` sets one part. If game Music is disabled, the existing
Master-channel hunt-song fallback remains available, but the Music slider cannot change that fallback
because the game provides no per-file volume control.

Horde and Alliance cannot exchange addon messages, and Godslayer keeps each ruleset on its own board.

**Not proven in game yet.** Slayers discovery, live news, mixed 3.0 and 3.1 compatibility, fan-out, and
the volume lease rules have automated and simulated coverage. The 3.1 cross-guild live feed and its
new audio routing have not yet been proven on the live game client. On boards larger than 20 users,
traffic limits mean not every kill reaches every client live; normal row refreshes still converge the
board over time.

Your kills, titles, guild board, saved Slayers rows, and 3.0 wire compatibility are preserved.
