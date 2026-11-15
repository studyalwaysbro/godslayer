# Godslayer 3.1.0 engineering record

Date: 2026-11-14

## What changed and why

The public Hunters surface is now Slayers so the name matches a board for every class and every guild.
The saved-variable key, Lua module, directory channel, addon prefix, protocol version, and 3.0 row wire
format remain unchanged. A 3.0 client and a 3.1 client can still discover and rank each other. Live N
news requires 3.1 at both ends; nonce-zero 3.0 R pushes go only to current verified partners because a
3.0 client rejects that push from anyone else.

Directory discovery now begins in a starting state and changes to not joined only after a real join
failure. It also distinguishes suspended, waiting for roster, only you, working, and unreadable states.
The Slayers display index is cached after joins, UI changes, and full display reads, so unrelated
roster and count events compare their index without walking the channel list. The index-free UI event
refreshes the cache and remains a hint. A channel id with no visible display row stays in waiting for
roster and gets one 15-second retry before the normal cycle, even if an earlier join attempt was
refused. With no channel id, not joined is used only when the current join chain has actually failed;
otherwise the state remains waiting for roster. Every refresh that sees a channel id clears the
chain's refusal marker, including the id-and-row scan path. A refresh after combat that still has no
id reapplies not joined when the current chain was refused instead of merely arming the long cycle.
Event refreshes are
limited to one per 60 seconds and share one pending timer. Join, joined notice, interrupted-scan combat
exit, and instance exit can each bypass that limit through the same debounce. Other entering-world
events use the 60-second limit. Ordinary zone changes rescan only when a scan was interrupted.
Last-scan status is printed as an age rather than as a server timestamp.

Credited kills form a 12-second quiet batch with a 30-second hard deadline measured from its first
kill. A non-kill row change can open the coalescer but cannot shorten a later kill's deadline. Batch
points are lifetime points at freeze minus lifetime points immediately before the first kill, clamped
to the original-guild maximum, so a late Olympus upgrade inside the window is included.

Finalization captures the complete row once and prebuilds both the N payload and legacy R payload from
that frozen state. A newer batch removes every undelivered item from older batches, carries those
targets forward, and folds the older kill count and earliest point base into its own N only when both
batches have the same frozen generation. A reset-generation row supersedes the old queue without
folding its kills. An N is frozen only when its batch kills do not exceed its row kills. A batch with
no N payload sends its frozen row only to current verified partners; non-partners converge through
their normal Q refresh. The newest victim and row remain the frozen payload. Finalization
reads the row and stats before deleting anything. If either read is unavailable, the older snapshots
and coalescer remain intact and one quiet-period retry stays armed. Send-time code never calls
`ownFields()` for a snapshot.

Target selection takes eligible carried targets first. They are exempt from a smaller new limit only
during initial finalization because each replaces one deleted older item. The carried set is then
discarded, so later partner notes and wakes obey the frozen batch limit. Snapshot insertion also has an
independent hard cap of 20 pending items. Current partners and the rotating slice use only the room
that remains under the limit. Carried rows that were pruned, are in the news-offline cooldown, or are
3.0 non-partners are skipped. For a row-only batch, carried, rotating, and ordinary targets are all
skipped unless they are current verified partners. Only selected rotating targets move the cursor.
Later row merges, regen events, and zone wakes can add current partners within the limit. On boards
above 20, they cannot fill from the front of the remaining list or move the cursor; newly eligible
ordinary rows wait for the next finalization. A 3.1 target receives the frozen N whenever the batch has
news, even after five minutes, so it can merge the row and suppress only the live line. Current verified
3.0 partners receive the frozen R instead. At dispatch, a row-only item whose partner lease expired is
dropped before the send API and before any traffic budget is charged.

On receipt, every monotone N row is merged. Each row keeps a session-only news base containing the
generation, kills, and points from the last N this client processed. If an R arrives before that first
N, the base is initialized from the row before the R merge and later R merges do not move it. Same-
generation presentation is clamped against this last-announced base, not the latest stored row, so an
R cannot hide news that was never announced. Processing an N advances the base even when presentation
is silent. When an R creates a row, its base starts at zero kills and points for that generation because
this client has not announced anything for that player. A new generation displays the validated batch
as sent. The news base and the independent generation-and-sequence replay guard are pruned with the row.
Single kills without a known victim say "scored a kill"; multi-kill batches say how many players were
taken down.

Guild and direct-news dedupe now separates checking from marking. A kill is marked only when that path
actually prints, banners, or speaks. Feed-off, top-10 filtering, and the global feed cap therefore do
not suppress the other presentation path. A news line delayed by the per-sender cooldown rechecks the
guild mark when its timer fires, closing the intervening-guild-line race. `Hype.Ally` reports whether
it presented anything. Session feed timestamps are pruned after 30 seconds and bounded; expired news-
offline cooldowns are pruned and the table is bounded.

The send scheduler reserves one of each three 10-second burst slots for responses by allowing at most
two non-response attempts in that window. The existing two-second spacing, ten attempts per minute,
eight non-response attempts per minute, and six news attempts per minute remain. An inbound Q is marked
complete only after its response is accepted by `SendAddonMessage`. Expiry or failure clears the owed
record so a repeated Q can recover. A thrown send API call is neutral and clears pending work without
penalizing a candidate. Each attempt gets a fresh exact-name offline correlation record, so a news
offline result still starts its 30-minute cooldown after an earlier Q for that name was signaled. A Q
offline applies one candidate failure whether result 12 or its system line arrives first, inside the
send call, or afterward. Turning sharing off clears every queued owed-response record, so the same Q
can be answered after sharing is enabled again. Row-only snapshots also recheck current partner status
before dispatch and a failed recheck spends no send slot.

Voice and Effects once again use absolute levels. Their level is Master times the part level. At 100
they use the exact 3.0 Master path with no CVar write and no Spoken check. Below 100, Voice borrows
Dialog or Ambience when Dialog is disabled; Effects borrow Ambience or idle Dialog when Ambience is
disabled. Both game channels being disabled makes sub-100 file playback silent. Spoken Voice uses
Dialog without a write, or Master when Dialog is disabled. Unleased Voice occupancy is tracked by
handle and declared length so Effects cannot change its channel underneath it.

Per-CVar leases share only when their absolute values match. Voice wins an unequal collision and may
stop Effects handles. Crash records are written before each SetCVar. A record is removed only after a
verified restore or after a numeric live value proves the player moved the slider. Failed writes and
nil reads retain the record. A failed login restore enters an in-session pending-recovery set retried
by the existing ticker. A later clip that still sees Godslayer's stranded value adopts the saved true
original; a different numeric value is treated as the player's move. A successful file-slider write
with unreadable verification keeps a silent unknown lease until a readable tick can restore it.

Music remains relative to the player's Music slider, Master, Music, and the 0.60 duck. An unreadable
Music verification keeps the controller and retries. A refused in-place rewrite restores the previous
owned record instead of discarding ownership, so stop can still restore the player original. When a
player move abandons a file lease, its still-playing Voice handles move to channel occupancy so Effects
cannot write under them. A Spoken-path Voice clip at the same level joins an active Voice lease and
therefore delays restoration until that clip ends, including when the matching CVar read is temporarily
nil. Any song handoff that ends on a Master sound handle, fails, or stops releases the Music controller
so the Music slider is restored.

## Defaults, guards, and compatibility

- Slayers sharing remains on by default. Feed mode defaults to everyone with chat lines only. Voice and
  banner feed notices are opt-in.
- `/godslayer hunters` remains an alias. `Hunters.lua`, `ns.Hunters`, `GodslayerDB.hunters`,
  `GodslayerG`, protocol `1`, and `GodslayerHunters` are unchanged.
- Region and ruleset remain in the protocol scope. Faction is additionally checked on N because the
  legacy wire scope omits it. Horde and Alliance cannot exchange addon messages, and Godslayer keeps
  each ruleset on its own board.
- Combat, instances, chat lockdown, payload validation, monotone generation and sequence checks,
  retention caps, and traffic budgets remain mandatory gates.
- Master, Music, Voice, and Effects default to 100. The 3.0 single volume migrates unchanged to Voice
  and Effects; Master and Music migrate to 100. Migration reads no CVar.
- A player's numeric mid-lease slider change wins. A nil CVar read is unknown and never counts as a
  player move.

## Known limits

- Above 20 eligible users, not every kill reaches every client live. Fair rotation spreads later
  batches while ordinary row exchanges continue to refresh the board.
- First-hand means the row came from the authenticated addon-message sender named by the game. It is
  attribution, not proof that the reported kill occurred.
- The game blocks addon whispers in battlegrounds and dungeons. Frozen batches drain after leaving; a
  3.1 batch older than five minutes updates the board through its frozen N without a live line. Only a
  current verified 3.0 partner receives the corresponding frozen R.
- Blizzard provides no per-file volume argument for `PlaySoundFile`. Sub-100 Voice and Effects need
  Dialog or Ambience enabled. If game Music is disabled, the retained Master song fallback cannot be
  adjusted by the Music slider.
- The cross-guild live feed and new volume routing are covered by automated tests and a mixed-version
  simulator but are not yet proven on the live 3.1 client.

## Verification

`sh tools/check.sh` parses every Lua file, checks generated client-derived artifacts, runs every suite,
runs the 220-client mixed 3.0/3.1 simulator with all nine classes, completes the 1,000-run and
250,000-event soak, and enforces unchanged client-call and garbage budgets.

Focused regressions cover the restored 3.0 full-volume, absolute Dialog/Ambience, crash, overlap,
Spoken, fallback, lifecycle, and soundkit behavior under per-part names. New cases cover stranded-
original adoption, player moves, unknown acquisition/login/Music reads, refused Music rewrites,
abandoned-Voice occupancy, Spoken-over-lease tracking, unequal and equal shared-CVar collisions, and
Hype's failed signature handoff. Slayers cases cover same-generation folded A/B replacement,
cross-generation reset replacement, failed-freeze retry, carried targets ahead of new partners, all
four sustained and lockdown backlog scenarios, last-announced and R-created news bases, stale N
merging, exact 200-row cursor windows under interleaved wakes, the first-kill deadline, in-window point
upgrades, legacy partner filtering,
timer-time presentation dedupe, replay eviction, disable-time response cleanup, all offline-result
orders, bounded session maps, response reservation, response expiry, local send exceptions, cached
channel filtering, short roster retry, refused-join enforcement across combat and manual membership,
entering-world limits, row-only partner selection and dispatch, carried-partner expiry and return,
multi-batch eligibility churn, and scan-age text. The mid-batch R case
requires both a fresh print count and the correct sender in the new line. The simulator makes
all ten response probes obligations, reports maximum owed-response delay, and counts any delay beyond
one spacing slot or any unsent response as starvation. Its news headline classifies an N as live only
when its frozen `made` age is at most five minutes, but retains kill-to-send latency measured from the
sender's latest credited kill. It reports older N sends separately as stale. Response-probe window
ages use the scheduler's wall-plus-fraction rate clock, so the reserved-slot fixture cannot admit a
nearly expired non-response burst through a mixed-clock comparison.

## Rollback

For an immediate data-preserving operational rollback, use `/godslayer slayers off`; this stops new
Slayers sends and receives without deleting saved rows. Feed display can be independently disabled with
`/godslayer slayers feed off`, and each audio part can be set to zero.

A source rollback reverts the 3.1 changes under `Godslayer/`, the new tests and checker entries, and
these documents. The retained 3.0 names and wire schema make saved Slayers state safe for older code to
ignore or reuse. On the next login, any persisted CVar recovery entry restores only when the live value
still equals Godslayer's recorded write, so rollback does not overwrite a player's later slider change.
