# Godslayer 3.0.0 engineering record (Hunters board)

Date: 2026-11-14

## What changed and why

Godslayer now has a Hunters leaderboard built only from score records received directly from each
row's owner. A fixed custom channel supplies names for discovery, while every addon payload uses a
rate-limited whisper. The board is scoped by region, faction, and ruleset; stores weekly counters
natively; retains confirmed rows for seven days; and labels the result as a local, self-reported
sample rather than a server-authoritative global rank.

The existing guild stats message keeps its original twelve fields and appends a schema-3 ordering
and weekly tail. Legacy twelve-field guild rows still rank, while `(generation, sequence)` prevents
an older saved character from replacing a newer schema-3 row.

The required fuzz gate exposed one retained Phase 1 announcer edge case: the global Hype off switch
cancelled future calls but did not discard lines already in its queue. It now clears that queue, so
an old line cannot play later under a temporarily borrowed sound-channel volume.

## Defaults, guards, and limits

- Sharing defaults on. The first-run chat and board notices disclose the fields, cross-realm addon
  whispers, seven-day remote caching, and the fact that opting out cannot erase existing copies.
- `/godslayer hunters off` and the Settings checkbox immediately clear queued Hunters work and make
  inbound Hunters messages inert. `GodslayerDB.hunters.enabled` is the persistent rollback guard.
- Networking remains inert if region, faction, or ruleset cannot be established, and the UI reports
  the reason. Instances, combat, and chat lockdown apply the protocol's traffic gates.
- The directory is `GodslayerHunters`; it is never an addon-data transport. Refusal or suspension
  produces the visible limited-coverage state while saved candidates remain usable.
- Hard caps are 6,000 rows, 300 candidates, 6 partners, 32 pending requests, 256 completed
  nonces, and 24 queued messages. Expiry and UI ordering are sliced to bounded per-frame work.

## Verification

Run from the repository root with the requested Lua 5.1 binary:

```text
lua tests/run.lua
lua tests/fuzz.lua
lua tests/fuzz.lua 1000 250 7001
lua tests/fuzz.lua 1000 250 9001
lua tests/flag_soak.lua
lua tests/hunters_sim.lua
```

The focused Hunters cases are registered by `tests/run.lua` from `tests/hunters.lua`; the isolated
multi-client transport and convergence model is `tests/hunters_sim.lua`.

## Rollback

Set Hunters sharing off for an immediate, data-preserving rollback. A code rollback removes
`Hunters.lua` from the TOC and the guarded `ns.Hunters` hooks in Core, Rank, Comm, Sound, and UI;
the `GodslayerDB.hunters` and per-character weekly/order fields can remain because older code does
not read them. Remote clients may retain rows already received until their seven-day expiry.

## Review hardening (2026-11-14)

The rival review reproduced and fixed all fourteen phase-2 findings. Hunters now accepts the three
live cross-backend sender spellings, derives rulesets from the documented hardcore API and live
realm-label suffix, clamps recounted exports to peer invariants, and keeps expiry heaps as bounded
runtime indexes rebuilt from durable records. Chat filters hide only correlated 120-second offline
errors and this addon's own directory notices; offline targets are capped at 64 and filters neither
inspect secret values nor hide system lines in instances.

Directory and discovery work now runs under one enable-generation guard. Opt-out securely leaves
the channel; opt-in securely rejoins it with chat frame ID zero and restarts join, refresh,
discovery, and introduction chains once. Directory reads avoid the first ten seconds after a zone
change and stop after polls at three and eight seconds. Group scans skip instances and are
throttled, while introductions contain only confirmed row owners and current verified partners.

The Hunters/Guild board shows eleven rows, uses a width-bounded one-line footer, and presents its
full disclosure in a dedicated wrapped panel until the player dismisses it for that session. Its
cooperative collector recovers if a row-table mutation invalidates Lua 5.1's `next` cursor.

These are default-on correctness and privacy fixes under the existing
`GodslayerDB.hunters.enabled` guard; there is no version change. Regression tests fail against the
saved phase-2 snapshot and pass against this tree. Rollback is a source revert of `Hunters.lua`,
`Comm.lua`, `UI.lua`, and their focused tests. Removed saved heap arrays are derived indexes only;
rows, candidates, settings, and score history remain intact and rebuild their indexes on the next
load.

## Round 3 hardening (2026-11-14)

Hunters Q/R traffic now carries a validated region/ruleset scope, and a foreign response retires
the queried candidate without merging it. Write-only routes are removed from every saved scope;
partners expire after 30 minutes without contact. Session nonce issuance relies on the durable
serial, and idle inbound-sender windows are pruned. Guild-rule recounts now adjust this week's
exact per-victim counts and points, including victims with more kills than retained history. Flag
widgets treat both dynamic-icon states, 2 and 3, as carried.

These changes keep the existing default-on sharing switch, traffic limits, seven-day row/candidate
retention, and partial-week marker. Verification covers the pre-fix round-3 snapshot, focused
regressions, seeded fuzz runs, flag soak, and a two-ruleset multi-client simulation. Rollback is a
source revert of `Hunters.lua`, `Core.lua`, `Flag.lua`, the round-3 tests, and this section; removed
route data was write-only and is not recoverable after login.

## Known limits

- Guild-rule recounts cannot reclassify kills after their victim dossiers have been compacted into
  archived aggregates. This is deferred because compaction begins only beyond 10,000 unique
  victims, while the most active observed character had 138 after ten days. The intended fix is to
  recount archived guild aggregates by guild.
- Victim compaction currently scans and sorts synchronously in the kill handler. It has the same
  beyond-10,000-victims threshold and is deferred on the same observed-volume evidence. The
  intended fix is to run compaction out of combat in budgeted slices.
