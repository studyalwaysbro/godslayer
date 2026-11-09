# Godslayer 2.9.0 engineering note

## Why

Forever build 1.60.1.70862 began sealing the victim argument delivered to addons on
`PARTY_KILL`. The raw combat-log file still held the victim, but addons received a secret value.
Godslayer scrubbed that value to `nil`, emitted `victim hidden by the client`, and returned before
kill detection, scoring or the hunt could run.

The standalone Forever event used here exposes two fields: attacker GUID and victim GUID. It does
not expose victim name, source/destination flags, or reaction/type flags. The live evidence and the
client's `SecretWhenUnitIdentityRestricted` contract establish that the victim GUID is the sealed
field; the attacker GUID remains readable for the player, pet and party sources Godslayer accepts.

## Change and default behavior

- A readable player/pet/party source with a secret, `nil` or empty victim is held briefly instead
  of discarded.
- `PLAYER_PVP_KILLS_CHANGED` supplies the missing player-versus-creature fact. A paired event runs
  the normal hunt, announcer, rung, streak, score, photo and clip paths. An unpaired hidden event
  expires, so ordinary creature kills do not become PvP kills.
- A readable player victim still takes the unchanged GUID/name/guild path on that individual
  event. There is no session-wide hidden mode.
- When identity never becomes readable, durable identity-dependent data aggregates under victim
  key `unknown:hidden-victim`, display name `Unknown victim`, and guild `Unknown`. Own killing
  blows and party killing blows remain distinguishable from the readable source GUID.
- No option or feature flag controls this: resilience is the default detection behavior in 2.9.0.
  Interface remains 16001. Saved-data schema and public archives are unchanged.

## Verification

`tests/hidden.lua` covers readable victims, secret victims, empty victims, PvE-shaped hidden events,
player and party sources, the unknown victim/guild/killing-blow buckets, hunt/streak/rung progress,
the configured tier screenshot, the clip barcode screenshot, and the return to full information on
the next readable event. The project test runner includes this suite. The installed 70862 client
produced byte-identical generated PvP data to 70790; only the generated build labels were refreshed
so the repository's client-data check records the build actually verified.

## Rollback

Revert the 2.9.0 Core/toc/test/documentation changes. No database migration is required; an existing
unknown bucket is an ordinary open-ring victim record and remains readable by older code. Rollback
restores the old behavior of dropping hidden-victim `PARTY_KILL` events.
