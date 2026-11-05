# What WoW: Forever will and will not tell an addon

Written by `tools/build_secrecy_map.lua` from the client's own generated API documentation.
Do not edit by hand.

Interface source: `eac30af 1.60.1 (70790)`. Newest client data in the cache: `1.60.1.70790`.
642 documentation tables loaded from 642 files.

The interface source lags the installed client. A function added since the commit above will
not appear here, and the way to find out is to call it and check the result rather than to
trust this file's silence.

## Why this file exists

Nearly every mistake in writing an addon for this client is a mistake about secrecy. A call
returns a number out of combat and a secret value in it. A structure goes secret except for the
four fields that do not. A function is in the documentation and is not loaded in this game at
all. Each of those has a different cause and they are easy to confuse for one another, because
all three look like "it stopped working".

The rules themselves are written down by the client, in a file with no functions in it that
therefore nobody opens: `SecretPredicatesDocumentation.lua`. What follows is that file's rules
joined to every call and event that carries them.

A secret value cannot be added, compared or concatenated. It is not nil and it is not zero, and
treating it as either is the bug. `ns.plain(v)` in this addon returns nil for one, which makes
"we were not told" a different answer from "it was nothing".

## The rules

`Secret*` rules hand back secret values. `Requires*` preconditions fail instead, and the
failure mode says how: `Error` throws, `ReturnWithError` returns nothing and logs, and
`ReturnNothing` returns nothing quietly. Anything behind an `Error` needs a `pcall`.

| rule | carriers | kind | fails by | what the client says it means |
|---|---|---|---|---|
| `SecretInChatMessagingLockdown` | 100 | Secret | - | Guarded APIs and events produce secret values when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the player is on a communication-restricted map such as a dungeon or raid. |
| `SecretReturnsForAspect` | 93 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresClubsInitialized` | 84 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenUnitStatsRestricted` | 63 | Secret | - | Guarded APIs and events produce secret values when access to unit stats would generally produce secret values. |
| `RequiresActiveCommentator` | 53 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenUnitIdentityRestricted` | 35 | Secret | - | Guarded APIs and events produce secret values when the unit isn't player-controlled or in the party/raid. For compound tokens (eg. 'boss1target'), results are secret if any unit in the chain fails this. |
| `RequiresFriendList` | 32 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidActionSlot` | 25 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresUnitAuraAccess` | 24 | Precondition | Error | Guarded APIs and events require that callers have access to unit aura data. |
| `SecretWhenAnchoringSecret` | 23 | Secret | - | Guarded APIs and events produce secret values when an object has secret anchoring information. |
| `SecretWhenUnitAuraRestricted` | 23 | Secret | - | Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions. |
| `SecretWhenUnitSpellCastRestricted` | 21 | Secret | - | Guarded APIs and events produce secret values if the unit being queried for cast information is not the player or their pet. Individual spells may be flagged as never or always secret, which takes priority. |
| `SecretReturns` | 19 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenCooldownsRestricted` | 15 | Secret | - | Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions. |
| `RequiresRecentAllies` | 12 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidTimelineEvent` | 12 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresCommentator` | 10 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresTimedSignalMapAccess` | 8 | Precondition | Error | Guarded APIs on a timed signal map raise an error when the map holds secret values and is accessed from a tainted execution context. |
| `RequiresValidUnitAuraInstance` | 8 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenCurveSecret` | 8 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretPayloads` | 7 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenUnitPowerRestricted` | 7 | Secret | - | Guarded APIs and events produce secret values for power types not explicitly flagged as being never secret, unless the subject unit does not have a power of this type. |
| `RequiresAssignableScript` | 6 | Precondition | Error | Requires that this object permit assignment of scripts of this type. May fail for reasons such as the script type not being supported, or secret aspects blocking assignments. |
| `RequiresLimitedInput` | 5 | Precondition | Error | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidAndPublicCVar` | 5 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidFontAsset` | 5 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidFontHeight` | 5 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresNonReadOnlyCVar` | 4 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresNonSecureCVar` | 4 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidInviteTarget` | 4 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenInCombat` | 4 | Secret | - | Guarded APIs and events produce secret values when combat addon restrictions are in effect. |
| `RequiresCanChangeHitTestPoints` | 3 | Precondition | Error | Guarded APIs require that the nameplate frame must allow changes to its hit test points. |
| `RequiresDeclassifiedUnitIdentity` | 3 | Precondition | ReturnWithError | Guarded APIs and events require that callers have access to the identity of a supplied unit token. |
| `RequiresNonSecretAura` | 3 | Precondition | - | Guarded APIs require that that the requested aura be non-secret at the time of the API call. This does not raise a blocked action error - instead, protected APIs will return no values. |
| `RequiresSpellDiminishUI` | 3 | Precondition | ReturnNothing | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresSupportedScript` | 3 | Precondition | ReturnNothing | Requires a valid script type supported by this object. If not supported, functions will return no values. |
| `SecretWhenEncounterEvent` | 3 | Secret | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretWhenLuaTableHasSecretKeys` | 3 | Secret | - | Guarded APIs produce secret values if the subject Lua table contains any secret keys. |
| `SecretWhenNumericFormatterSecret` | 3 | - | - | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresFontStringTextAccess` | 2 | Precondition | ReturnNothing | Guarded APIs reject access for tainted callers if the object has the secret Text aspect assigned. |
| `RequiresRestrictedAbbreviationBreakpoints` | 2 | Precondition | Error | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresValidAbbreviationBreakpoints` | 2 | Precondition | Error | _not documented in SecretPredicatesDocumentation.lua_ |
| `SecretInActivePvPMatch` | 2 | Secret | - | Guarded APIs and events produce secret values when PvP match addon restrictions are in effect. |
| `SecretWhenLossOfControlInfoRestricted` | 2 | Secret | - | Guarded APIs and events always produce secret values, unless the active player is an active spectator or commentator of a PvP match. |
| `SecretWhenLossOfControlRestricted` | 2 | Secret | - | Guarded APIs always produce secret values, unless the active player is an active spectator or commentator of a PvP match. |
| `SecretWhenTotemSlotSecret` | 2 | Secret | - | Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual totem spell auras may be flagged as never or always secret, which takes priority over restrictions. |
| `SecretWhenUnitPossessionRestricted` | 2 | Secret | - | Guarded APIs and events produce secret values based on aura secrecy, except for unit tokens under the player's direct control. |
| `SecretWhenUnitThreatStateRestricted` | 2 | Secret | - | Guarded APIs and events produce secret values based upon supplied unit tokens. Queries where only one unit token is specified, or where one unit token is the player, their pet, or an ally while the other is a nameplate, boss, target, etc., are generally not secret. |
| `SecretWhenUnitThreatValuesRestricted` | 2 | Secret | - | Guarded APIs and events produce secret values based upon supplied unit tokens. Queries where only one unit token is specified, or where one unit token is the player, their pet, or an ally while the other is a non-boss or nameplate target, are generally not secret. |
| `RequiresComparableUnitTokens` | 1 | Precondition | ReturnNothing | Guarded APIs only accept unit token pairs that can be compared with one another. For example, comparisons where either unit is 'player' or 'target' are permitted, but comparisons between 'nameplate3' and 'boss1' are not. |
| `RequiresIndexInRange` | 1 | Precondition | Error | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresScriptObjectAlphaAccess` | 1 | Precondition | ReturnWithError | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresScriptObjectDesaturationAccess` | 1 | Precondition | ReturnWithError | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresStatusBarDesaturationAccess` | 1 | Precondition | ReturnWithError | _not documented in SecretPredicatesDocumentation.lua_ |
| `RequiresUnitIdentityAccess` | 1 | Precondition | ReturnWithError | Guarded APIs and events require that callers have access to unit identity values. This does not raise a blocked action error - instead, protected APIs will return no values. |
| `SecretWhenAurasRestricted` | 1 | Secret | - | Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. |
| `SecretWhenUnitComparisonRestricted` | 1 | Secret | - | Guarded APIs and events produce secret values based upon supplied unit tokens. Comparisons involving compound unit tokens (eg. 'boss1target') are always secret. This restriction only applies when the player is on an addon-restricted map. |
| `SecretWhenUnitHealthMaxRestricted` | 1 | Secret | - | Guarded APIs and events produce secret values when the unit isn't player-controlled. |
| `SecretWhenUnitNameIdentityRestricted` | 1 | Secret | - | Guarded APIs and events produce secret values under regular unit identity secrecy rules, except in PvP when the queried unit is a player. |
| `SecretWhenUnitPowerMaxRestricted` | 1 | Secret | - | Guarded APIs and events produce secret values when the unit isn't player-controlled. Individual power types may be flagged as never or always secret, which takes priority. |

Three of the names above are flags rather than predicates and so have no entry in the client's
own rules file. Reading them from how they are used:

- `SecretReturns = true` with no conditional rule beside it means the returns are secret
  always, not under a condition. `UnitCastingDuration` carries it bare, while `UnitCastingInfo`
  next to it carries `SecretWhenUnitSpellCastRestricted` instead -- so the pair is the same
  subject with an unconditional rule and a conditional one, which is what fixes the reading.
- `SecretArguments` is excluded from this file entirely. It governs what may be passed **in**
  (`AllowedWhenTainted`, `AllowedWhenUntainted`) and sits on nearly four thousand calls, so it
  says nothing about whether an answer comes back usable.
- A `Requires*` precondition with no entry is almost always about state rather than secrecy
  (`RequiresClubsInitialized`, `RequiresFriendList`): the call needs something loaded, and an
  addon handles it by checking, not by unwrapping.

Rules the client documents but nothing in this interface source carries (8): `HasRestrictions`, `IsProtectedFunction`, `MouseFocusValidForLimitedInput`, `RequireNPERestricted`, `RequiresValidSpellIdentifier`, `RestrictedForMacroChatMessages`, `SecretOnRestrictedMaps`, `TransliteratorAllowed`.

## What each rule gates

### `SecretInChatMessagingLockdown` — 100

> Guarded APIs and events produce secret values when encounter, challenge mode, or PvP match addon restrictions are in effect, and when the player is on a communication-restricted map such as a dungeon or raid.

- `CANCEL_PLAYER_COUNTDOWN (event)`
- `CHAT_MSG_AFK (event)`
- `CHAT_MSG_BN (event)`
- `CHAT_MSG_BN_INLINE_TOAST_ALERT (event)`
- `CHAT_MSG_BN_INLINE_TOAST_BROADCAST (event)`
- `CHAT_MSG_BN_INLINE_TOAST_BROADCAST_INFORM (event)`
- `CHAT_MSG_BN_INLINE_TOAST_CONVERSATION (event)`
- `CHAT_MSG_BN_WHISPER (event)`
- `CHAT_MSG_BN_WHISPER_INFORM (event)`
- `CHAT_MSG_BN_WHISPER_PLAYER_OFFLINE (event)`
- `CHAT_MSG_CHANNEL (event)`
- `CHAT_MSG_CHANNEL_JOIN (event)`
- `CHAT_MSG_CHANNEL_LEAVE (event)`
- `CHAT_MSG_CHANNEL_LIST (event)`
- `CHAT_MSG_CHANNEL_NOTICE (event)`
- `CHAT_MSG_CHANNEL_NOTICE_USER (event)`
- `CHAT_MSG_COMMUNITIES_CHANNEL (event)`
- `CHAT_MSG_DND (event)`
- `CHAT_MSG_EMOTE (event)`
- `CHAT_MSG_GUILD (event)`
- `CHAT_MSG_IGNORED (event)`
- `CHAT_MSG_INSTANCE_CHAT (event)`
- `CHAT_MSG_INSTANCE_CHAT_LEADER (event)`
- `CHAT_MSG_MONSTER_EMOTE (event)`
- `CHAT_MSG_MONSTER_PARTY (event)`
- `CHAT_MSG_MONSTER_SAY (event)`
- `CHAT_MSG_MONSTER_WHISPER (event)`
- `CHAT_MSG_MONSTER_YELL (event)`
- `CHAT_MSG_OFFICER (event)`
- `CHAT_MSG_OPENING (event)`
- `CHAT_MSG_PARTY (event)`
- `CHAT_MSG_PARTY_LEADER (event)`
- `CHAT_MSG_PING (event)`
- `CHAT_MSG_RAID (event)`
- `CHAT_MSG_RAID_BOSS_EMOTE (event)`
- `CHAT_MSG_RAID_BOSS_WHISPER (event)`
- `CHAT_MSG_RAID_LEADER (event)`
- `CHAT_MSG_RAID_WARNING (event)`
- `CHAT_MSG_SAY (event)`
- `CHAT_MSG_SKILL (event)`
- _and 60 more_

### `SecretReturnsForAspect` — 93

- `CalculateScreenAreaFromCharacterSpan`
- `CanBeAccessedInContext`
- `CanChangeAttribute`
- `CanChangeProtectedState`
- `ClearAttribute`
- `ExecuteAttribute`
- `FindCharacterIndexAtCoordinate`
- `GetAccessRestrictions`
- `GetAlpha`
- `GetAlpha`
- `GetAlpha`
- `GetAttribute`
- `GetButtonState`
- `GetChildren`
- `GetCooldownDisplayDuration`
- `GetCooldownDuration`
- `GetCooldownTimes`
- `GetCursorPosition`
- `GetDesaturation`
- `GetDisplayText`
- `GetDrawBling`
- `GetDrawEdge`
- `GetDrawSwipe`
- `GetEffectiveAlpha`
- `GetEffectiveScale`
- `GetEffectiveScale`
- `GetForbiddenAspects`
- `GetFrameLevel`
- `GetFrameStrata`
- `GetFromAlpha`
- `GetHorizontalScroll`
- `GetHorizontalScrollRange`
- `GetID`
- `GetInheritableForbiddenAspects`
- `GetInterpolatedValue`
- `GetMaskTexture`
- `GetMinMaxValues`
- `GetMinimumWidth`
- `GetName`
- `GetNumChildren`
- _and 53 more_

### `RequiresClubsInitialized` — 84

- `C_Club.AcceptInvitation`
- `C_Club.AddClubStreamChatChannel`
- `C_Club.AdvanceStreamViewMarker`
- `C_Club.AreMembersReady`
- `C_Club.AssignMemberRole`
- `C_Club.CanResolvePlayerLocationFromClubMessageData`
- `C_Club.ClearAutoAdvanceStreamViewMarker`
- `C_Club.ClearClubPresenceSubscription`
- `C_Club.CompareBattleNetDisplayName`
- `C_Club.CreateClub`
- `C_Club.CreateStream`
- `C_Club.CreateTicket`
- `C_Club.DeclineInvitation`
- `C_Club.DestroyClub`
- `C_Club.DestroyMessage`
- `C_Club.DestroyStream`
- `C_Club.DestroyTicket`
- `C_Club.DoesAnyCommunityHaveUnreadMessages`
- `C_Club.DoesCommunityHaveMembersOfTheOppositeFaction`
- `C_Club.EditClub`
- `C_Club.EditMessage`
- `C_Club.EditStream`
- `C_Club.Flush`
- `C_Club.FocusCommunityStreams`
- `C_Club.FocusMembers`
- `C_Club.FocusStream`
- `C_Club.GetAssignableRoles`
- `C_Club.GetAvatarIdList`
- `C_Club.GetClubCapacity`
- `C_Club.GetClubInfo`
- `C_Club.GetClubLimits`
- `C_Club.GetClubMembers`
- `C_Club.GetClubPrivileges`
- `C_Club.GetClubStreamNotificationSettings`
- `C_Club.GetCommunityNameResultText`
- `C_Club.GetGuildClubId`
- `C_Club.GetInfoFromLastCommunityChatLine`
- `C_Club.GetInvitationCandidates`
- `C_Club.GetInvitationInfo`
- `C_Club.GetInvitationsForClub`
- _and 44 more_

### `SecretWhenUnitStatsRestricted` — 63

> Guarded APIs and events produce secret values when access to unit stats would generally produce secret values.

- `GetArmorPenetration`
- `GetAttackPowerForStat`
- `GetAvoidance`
- `GetBlockChance`
- `GetCombatRating`
- `GetCombatRatingBonus`
- `GetCritChance`
- `GetCritChanceFromStat`
- `GetDodgeChance`
- `GetDodgeChanceFromAttribute`
- `GetExpertise`
- `GetExpertisePercent`
- `GetGlancingBlowChance`
- `GetGlancingBlowPenalty`
- `GetHaste`
- `GetHitModifier`
- `GetLifesteal`
- `GetManaRegen`
- `GetMastery`
- `GetMasteryEffect`
- `GetMeleeHaste`
- `GetModResilienceDamageReduction`
- `GetOffhandHitModifier`
- `GetOverrideAPBySpellPower`
- `GetOverrideSpellPowerByAP`
- `GetParryChance`
- `GetParryChanceFromAttribute`
- `GetPetCritChance`
- `GetPetDodgeChance`
- `GetPetHitChanceModifier`
- `GetPetMeleeHaste`
- `GetPetSpellBonusDamage`
- `GetPetSpellHitChanceModifier`
- `GetPowerRegen`
- `GetPowerRegenForPowerType`
- `GetPvpPowerDamage`
- `GetPvpPowerHealing`
- `GetRangedAttackPowerForStat`
- `GetRangedCritChance`
- `GetRangedHaste`
- _and 23 more_

### `RequiresActiveCommentator` — 53

- `C_Commentator.AddTrackedDefensiveAuras`
- `C_Commentator.AddTrackedOffensiveAuras`
- `C_Commentator.ClearCameraTarget`
- `C_Commentator.ClearFollowTarget`
- `C_Commentator.ClearLookAtTarget`
- `C_Commentator.FindSpectatedUnit`
- `C_Commentator.FollowPlayer`
- `C_Commentator.FollowUnit`
- `C_Commentator.ForceFollowTransition`
- `C_Commentator.GetAdditionalCameraWeight`
- `C_Commentator.GetAdditionalCameraWeightByToken`
- `C_Commentator.GetAllPlayerOverrideNames`
- `C_Commentator.GetCamera`
- `C_Commentator.GetCameraPosition`
- `C_Commentator.GetCombatEventInfo`
- `C_Commentator.GetCommentatorMatchDataState`
- `C_Commentator.GetIndirectSpellID`
- `C_Commentator.GetNumPlayers`
- `C_Commentator.GetPlayerAuraInfo`
- `C_Commentator.GetPlayerAuraInfoByUnit`
- `C_Commentator.GetPlayerCooldownInfo`
- `C_Commentator.GetPlayerCooldownInfoByUnit`
- `C_Commentator.GetPlayerCrowdControlInfo`
- `C_Commentator.GetPlayerCrowdControlInfoByUnit`
- `C_Commentator.GetPlayerData`
- `C_Commentator.GetPlayerFlagInfo`
- `C_Commentator.GetPlayerFlagInfoByUnit`
- `C_Commentator.GetPlayerItemCooldownInfo`
- `C_Commentator.GetPlayerItemCooldownInfoByUnit`
- `C_Commentator.GetPlayerSpellCharges`
- `C_Commentator.GetPlayerSpellChargesByUnit`
- `C_Commentator.GetSmoothFollowTransitioning`
- `C_Commentator.GetTrackedSpellID`
- `C_Commentator.GetTrackedSpells`
- `C_Commentator.GetTrackedSpellsByUnit`
- `C_Commentator.GetUnitData`
- `C_Commentator.HasTrackedAuras`
- `C_Commentator.IsTrackedDefensiveAura`
- `C_Commentator.IsTrackedOffensiveAura`
- `C_Commentator.IsTrackedSpell`
- `C_Commentator.IsTrackedSpellByUnit`
- `C_Commentator.LookAtPlayer`
- `C_Commentator.RequestPlayerCooldownInfo`
- `C_Commentator.ResetTrackedAuras`
- `C_Commentator.SetAdditionalCameraWeight`
- `C_Commentator.SetAdditionalCameraWeightByToken`
- `C_Commentator.SetCamera`
- `C_Commentator.SetCameraCollision`
- `C_Commentator.SetCameraPosition`
- `C_Commentator.SetFollowCameraSpeeds`
- `C_Commentator.SetSmoothFollowTransitioning`
- `C_Commentator.SetTargetHeightOffset`
- `C_Commentator.SnapCameraLookAtPoint`

### `SecretWhenUnitIdentityRestricted` — 35

> Guarded APIs and events produce secret values when the unit isn't player-controlled or in the party/raid. For compound tokens (eg. 'boss1target'), results are secret if any unit in the chain fails this.

- `C_ScenarioInfo.GetUnitCriteriaProgressValues`
- `C_SpecializationInfo.GetInspectSpecialization`
- `C_Spell.IsActiveSpell`
- `PARTY_KILL (event)`
- `PLAYER_SOFT_INTERACT_CHANGED (event)`
- `UNIT_DIED (event)`
- `UnitClass`
- `UnitClassBase`
- `UnitCreatureFamily`
- `UnitCreatureID`
- `UnitCreatureType`
- `UnitFullName`
- `UnitGUID`
- `UnitGetAvailableRoles`
- `UnitGroupRolesAssigned`
- `UnitGroupRolesAssignedEnum`
- `UnitHasEffectivelyTankAura`
- `UnitHonorLevel`
- `UnitInRaid`
- `UnitIsGroupAssistant`
- `UnitIsGroupLeader`
- `UnitIsOwnerOrControllerOfUnit`
- `UnitIsPVP`
- `UnitIsRaidOfficer`
- `UnitLeadsAnyGroup`
- `UnitNameFromGUID`
- `UnitNameUnmodified`
- `UnitOwnerGUID`
- `UnitPVPName`
- `UnitPhaseReason`
- `UnitRace`
- `UnitResistance`
- `UnitSex`
- `UnitSexBase`
- `UnitTokenFromGUID`

### `RequiresFriendList` — 32

- `C_FriendList.AddFriend`
- `C_FriendList.AddIgnore`
- `C_FriendList.AddOrDelIgnore`
- `C_FriendList.AddOrRemoveFriend`
- `C_FriendList.DelIgnore`
- `C_FriendList.DelIgnoreByIndex`
- `C_FriendList.GetFriendInfo`
- `C_FriendList.GetFriendInfoByIndex`
- `C_FriendList.GetIgnoreName`
- `C_FriendList.GetNumFriends`
- `C_FriendList.GetNumIgnores`
- `C_FriendList.GetNumOnlineFriends`
- `C_FriendList.GetNumWhoResults`
- `C_FriendList.GetSelectedFriend`
- `C_FriendList.GetSelectedIgnore`
- `C_FriendList.GetWhoInfo`
- `C_FriendList.GetWhoRaceFilters`
- `C_FriendList.IsFriend`
- `C_FriendList.IsIgnored`
- `C_FriendList.IsIgnoredByGuid`
- `C_FriendList.IsLegacyFriendSystemEnabled`
- `C_FriendList.IsOnIgnoredList`
- `C_FriendList.RemoveFriend`
- `C_FriendList.RemoveFriendByIndex`
- `C_FriendList.SendWho`
- `C_FriendList.SetFriendNotes`
- `C_FriendList.SetFriendNotesByIndex`
- `C_FriendList.SetSelectedFriend`
- `C_FriendList.SetSelectedIgnore`
- `C_FriendList.SetWhoToUi`
- `C_FriendList.ShowFriends`
- `C_FriendList.SortWho`

### `RequiresValidActionSlot` — 25

- `C_ActionBar.GetActionAutocast`
- `C_ActionBar.GetActionChargeDuration`
- `C_ActionBar.GetActionCharges`
- `C_ActionBar.GetActionCooldown`
- `C_ActionBar.GetActionCooldownDuration`
- `C_ActionBar.GetActionDisplayCount`
- `C_ActionBar.GetActionLossOfControlCooldownDuration`
- `C_ActionBar.GetActionLossOfControlCooldownInfo`
- `C_ActionBar.GetActionText`
- `C_ActionBar.GetActionTexture`
- `C_ActionBar.GetActionUseCount`
- `C_ActionBar.HasAction`
- `C_ActionBar.HasRangeRequirements`
- `C_ActionBar.IsActionInRange`
- `C_ActionBar.IsAttackAction`
- `C_ActionBar.IsAutoRepeatAction`
- `C_ActionBar.IsConsumableAction`
- `C_ActionBar.IsCurrentAction`
- `C_ActionBar.IsEquippedAction`
- `C_ActionBar.IsItemAction`
- `C_ActionBar.IsMacroActionWithShowTooltip`
- `C_ActionBar.IsStackableAction`
- `C_ActionBar.IsUsableAction`
- `C_ActionBar.RegisterActionUIButton`
- `C_ActionBar.UsesActionText`

### `RequiresUnitAuraAccess` — 24

> Guarded APIs and events require that callers have access to unit aura data.

- `C_TooltipInfo.GetUnitAura`
- `C_TooltipInfo.GetUnitAuraByAuraInstanceID`
- `C_TooltipInfo.GetUnitBuff`
- `C_TooltipInfo.GetUnitBuffByAuraInstanceID`
- `C_TooltipInfo.GetUnitDebuff`
- `C_TooltipInfo.GetUnitDebuffByAuraInstanceID`
- `C_UnitAuras.CancelAuraByInstanceID`
- `C_UnitAuras.DoesAuraHaveExpirationTime`
- `C_UnitAuras.GetAuraApplicationDisplayCount`
- `C_UnitAuras.GetAuraBaseDuration`
- `C_UnitAuras.GetAuraCasterGUID`
- `C_UnitAuras.GetAuraDataByAuraInstanceID`
- `C_UnitAuras.GetAuraDataByIndex`
- `C_UnitAuras.GetAuraDataBySlot`
- `C_UnitAuras.GetAuraDispelTypeColor`
- `C_UnitAuras.GetAuraDuration`
- `C_UnitAuras.GetAuraSlots`
- `C_UnitAuras.GetBuffDataByIndex`
- `C_UnitAuras.GetDebuffDataByIndex`
- `C_UnitAuras.GetRefreshCarryOverDuration`
- `C_UnitAuras.GetRefreshExtendedDuration`
- `C_UnitAuras.GetUnitAuraInstanceIDs`
- `C_UnitAuras.GetUnitAuras`
- `C_UnitAuras.IsAuraFilteredOutByInstanceID`

### `SecretWhenAnchoringSecret` — 23

> Guarded APIs and events produce secret values when an object has secret anchoring information.

- `CalculateScreenAreaFromCharacterSpan`
- `FindCharacterIndexAtCoordinate`
- `GetBottom`
- `GetCenter`
- `GetHeight`
- `GetLeft`
- `GetNumLines`
- `GetPoint`
- `GetPointByName`
- `GetRect`
- `GetRight`
- `GetScaledRect`
- `GetSize`
- `GetStringHeight`
- `GetStringWidth`
- `GetTop`
- `GetUnboundedStringWidth`
- `GetUnboundedStringWidthForText`
- `GetWidth`
- `GetWrappedWidth`
- `Intersects`
- `IsMouseOver`
- `IsTruncated`

### `SecretWhenUnitAuraRestricted` — 23

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions.

- `C_Spell.GetSpellMaxCumulativeAuraApplications`
- `C_Spell.IsActiveSpell`
- `C_TooltipInfo.GetUnitAura`
- `C_TooltipInfo.GetUnitAuraByAuraInstanceID`
- `C_TooltipInfo.GetUnitBuff`
- `C_TooltipInfo.GetUnitBuffByAuraInstanceID`
- `C_TooltipInfo.GetUnitDebuff`
- `C_TooltipInfo.GetUnitDebuffByAuraInstanceID`
- `C_UnitAuras.DoesAuraHaveExpirationTime`
- `C_UnitAuras.GetAuraApplicationDisplayCount`
- `C_UnitAuras.GetAuraBaseDuration`
- `C_UnitAuras.GetAuraCasterGUID`
- `C_UnitAuras.GetAuraDataByAuraInstanceID`
- `C_UnitAuras.GetAuraDataByIndex`
- `C_UnitAuras.GetAuraDataBySlot`
- `C_UnitAuras.GetAuraDataBySpellName`
- `C_UnitAuras.GetAuraDispelTypeColor`
- `C_UnitAuras.GetBuffDataByIndex`
- `C_UnitAuras.GetDebuffDataByIndex`
- `C_UnitAuras.GetPlayerAuraBySpellID`
- `C_UnitAuras.GetRefreshCarryOverDuration`
- `C_UnitAuras.GetRefreshExtendedDuration`
- `C_UnitAuras.GetUnitAuraBySpellID`

### `SecretWhenUnitSpellCastRestricted` — 21

> Guarded APIs and events produce secret values if the unit being queried for cast information is not the player or their pet. Individual spells may be flagged as never or always secret, which takes priority.

- `GetUnitEmpowerHoldAtMaxTime`
- `GetUnitEmpowerMinHoldTime`
- `GetUnitEmpowerStageDuration`
- `UNIT_SPELLCAST_CHANNEL_START (event)`
- `UNIT_SPELLCAST_CHANNEL_STOP (event)`
- `UNIT_SPELLCAST_CHANNEL_UPDATE (event)`
- `UNIT_SPELLCAST_DELAYED (event)`
- `UNIT_SPELLCAST_EMPOWER_START (event)`
- `UNIT_SPELLCAST_EMPOWER_STOP (event)`
- `UNIT_SPELLCAST_EMPOWER_UPDATE (event)`
- `UNIT_SPELLCAST_FAILED (event)`
- `UNIT_SPELLCAST_FAILED_QUIET (event)`
- `UNIT_SPELLCAST_INTERRUPTED (event)`
- `UNIT_SPELLCAST_RETICLE_CLEAR (event)`
- `UNIT_SPELLCAST_RETICLE_TARGET (event)`
- `UNIT_SPELLCAST_SENT (event)`
- `UNIT_SPELLCAST_START (event)`
- `UNIT_SPELLCAST_STOP (event)`
- `UNIT_SPELLCAST_SUCCEEDED (event)`
- `UnitCastingInfo`
- `UnitChannelInfo`

### `SecretReturns` — 19

- `C_CombatText.GetCurrentEventInfo`
- `C_PvP.GetArenaOpponentSpec`
- `C_SpellDiminish.ShouldTrackSpellDiminishCategory`
- `ClosestGameObjectPosition`
- `ClosestUnitPosition`
- `GetRaidTargetIndex`
- `PlayerIsSpellTarget`
- `UnitCastingDuration`
- `UnitGetIncomingHeals`
- `UnitGetTotalAbsorbs`
- `UnitGetTotalHealAbsorbs`
- `UnitHealth`
- `UnitHealthMissing`
- `UnitHealthPercent`
- `UnitInRange`
- `UnitPercentHealthFromGUID`
- `UnitPowerBarTimerInfo`
- `UnitSpellTargetClass`
- `UnitSpellTargetName`

### `SecretWhenCooldownsRestricted` — 15

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual spells may be flagged as never or always secret, which takes priority over restrictions.

- `C_ActionBar.GetActionCharges`
- `C_ActionBar.GetActionCooldown`
- `C_ActionBar.GetActionDisplayCount`
- `C_ActionBar.GetActionLossOfControlCooldownInfo`
- `C_ActionBar.GetActionUseCount`
- `C_Spell.GetLastCategoryCooldownSource`
- `C_Spell.GetSpellCastCount`
- `C_Spell.GetSpellCharges`
- `C_Spell.GetSpellCooldown`
- `C_Spell.GetSpellDisplayCount`
- `C_Spell.GetSpellLossOfControlCooldownInfo`
- `C_SpellBook.GetSpellBookItemCastCount`
- `C_SpellBook.GetSpellBookItemCharges`
- `C_SpellBook.GetSpellBookItemCooldown`
- `C_SpellBook.GetSpellBookItemLossOfControlCooldownInfo`

### `RequiresRecentAllies` — 12

- `C_RecentAllies.CanSetRecentAllyNote`
- `C_RecentAllies.GetRecentAllies`
- `C_RecentAllies.GetRecentAllyByFullName`
- `C_RecentAllies.GetRecentAllyByGUID`
- `C_RecentAllies.IsRecentAllyByFullName`
- `C_RecentAllies.IsRecentAllyByGUID`
- `C_RecentAllies.IsRecentAllyDataReady`
- `C_RecentAllies.IsRecentAllyPinned`
- `C_RecentAllies.SearchRecentAllies`
- `C_RecentAllies.SetRecentAllyNote`
- `C_RecentAllies.SetRecentAllyPinned`
- `C_RecentAllies.TryRequestRecentAlliesData`

### `RequiresValidTimelineEvent` — 12

- `C_EncounterTimeline.CancelScriptEvent`
- `C_EncounterTimeline.FinishScriptEvent`
- `C_EncounterTimeline.GetEventColor`
- `C_EncounterTimeline.GetEventInfo`
- `C_EncounterTimeline.GetEventState`
- `C_EncounterTimeline.GetEventTimeElapsed`
- `C_EncounterTimeline.GetEventTimeRemaining`
- `C_EncounterTimeline.GetEventTrack`
- `C_EncounterTimeline.IsEventBlocked`
- `C_EncounterTimeline.PauseScriptEvent`
- `C_EncounterTimeline.ResumeScriptEvent`
- `C_EncounterTimeline.SetEventIconTextures`

### `RequiresCommentator` — 10

- `C_Commentator.EnterInstance`
- `C_Commentator.ExitInstance`
- `C_Commentator.GetCurrentMapID`
- `C_Commentator.GetInstanceInfo`
- `C_Commentator.GetMapInfo`
- `C_Commentator.GetWargameInfo`
- `C_Commentator.SetMapAndInstanceIndex`
- `C_Commentator.StartWargame`
- `C_Commentator.UpdateMapInfo`
- `C_Commentator.UpdatePlayerInfo`

### `RequiresTimedSignalMapAccess` — 8

> Guarded APIs on a timed signal map raise an error when the map holds secret values and is accessed from a tainted execution context.

- `CancelAllSignals`
- `CancelSignal`
- `GetNextSignal`
- `GetSignalCount`
- `GetSignalTime`
- `HasSignal`
- `SignalAfter`
- `SignalAt`

### `RequiresValidUnitAuraInstance` — 8

- `C_UnitAuras.DoesAuraHaveExpirationTime`
- `C_UnitAuras.GetAuraApplicationDisplayCount`
- `C_UnitAuras.GetAuraBaseDuration`
- `C_UnitAuras.GetAuraCasterGUID`
- `C_UnitAuras.GetAuraDispelTypeColor`
- `C_UnitAuras.GetAuraDuration`
- `C_UnitAuras.GetRefreshCarryOverDuration`
- `C_UnitAuras.GetRefreshExtendedDuration`

### `SecretWhenCurveSecret` — 8

- `C_UnitAuras.GetAuraDispelTypeColor`
- `EvaluateElapsedDuration`
- `EvaluateElapsedPercent`
- `EvaluateRemainingDuration`
- `EvaluateRemainingPercent`
- `EvaluateTotalDuration`
- `UnitHealthPercent`
- `UnitPowerPercent`

### `SecretPayloads` — 7

- `MINIMAP_PING (event)`
- `RUNE_POWER_UPDATE (event)`
- `RUNE_TYPE_UPDATE (event)`
- `UNIT_DISTANCE_CHECK_UPDATE (event)`
- `UNIT_IN_RANGE_UPDATE (event)`
- `UNIT_MAX_HEALTH_MODIFIERS_CHANGED (event)`
- `UNIT_SPELL_DIMINISH_CATEGORY_STATE_UPDATED (event)`

### `SecretWhenUnitPowerRestricted` — 7

> Guarded APIs and events produce secret values for power types not explicitly flagged as being never secret, unless the subject unit does not have a power of this type.

- `GetComboPoints`
- `GetUnitChargedPowerPoints`
- `UNIT_POWER_POINT_CHARGE (event)`
- `UnitPartialPower`
- `UnitPower`
- `UnitPowerMissing`
- `UnitPowerPercent`

### `RequiresAssignableScript` — 6

> Requires that this object permit assignment of scripts of this type. May fail for reasons such as the script type not being supported, or secret aspects blocking assignments.

- `HookScript`
- `HookScript`
- `HookScript`
- `SetScript`
- `SetScript`
- `SetScript`

### `RequiresLimitedInput` — 5

- `SetCursorPosition`
- `SimulateMouseClick`
- `SimulateMouseDown`
- `SimulateMouseUp`
- `SimulateMouseWheel`

### `RequiresValidAndPublicCVar` — 5

- `C_CVar.GetCVarDefault`
- `C_CVar.RemoveTempCVar`
- `C_CVar.SetCVar`
- `C_CVar.SetCVarBitfield`
- `C_CVar.SetTempCVar`

### `RequiresValidFontAsset` — 5

- `SetFont`
- `SetFont`
- `SetFont`
- `SetFont`
- `SetFont`

### `RequiresValidFontHeight` — 5

- `SetFont`
- `SetFont`
- `SetFont`
- `SetFont`
- `SetFont`

### `RequiresNonReadOnlyCVar` — 4

- `C_CVar.RemoveTempCVar`
- `C_CVar.SetCVar`
- `C_CVar.SetCVarBitfield`
- `C_CVar.SetTempCVar`

### `RequiresNonSecureCVar` — 4

- `C_CVar.RemoveTempCVar`
- `C_CVar.SetCVar`
- `C_CVar.SetCVarBitfield`
- `C_CVar.SetTempCVar`

### `RequiresValidInviteTarget` — 4

- `C_PartyInfo.ConfirmInviteUnit`
- `C_PartyInfo.ConfirmRequestInviteFromUnit`
- `C_PartyInfo.InviteUnit`
- `C_PartyInfo.RequestInviteFromUnit`

### `SecretWhenInCombat` — 4

> Guarded APIs and events produce secret values when combat addon restrictions are in effect.

- `C_DamageMeter.GetCombatSessionFromID`
- `C_DamageMeter.GetCombatSessionFromType`
- `C_DamageMeter.GetCombatSessionSourceFromID`
- `C_DamageMeter.GetCombatSessionSourceFromType`

### `RequiresCanChangeHitTestPoints` — 3

> Guarded APIs require that the nameplate frame must allow changes to its hit test points.

- `ClearAllHitTestPoints`
- `SetAllHitTestPoints`
- `SetHitTestPoints`

### `RequiresDeclassifiedUnitIdentity` — 3

> Guarded APIs and events require that callers have access to the identity of a supplied unit token.

- `C_CombatText.SetActiveUnit`
- `SetModelByUnit`
- `SetUnit`

### `RequiresNonSecretAura` — 3

> Guarded APIs require that that the requested aura be non-secret at the time of the API call. This does not raise a blocked action error - instead, protected APIs will return no values.

- `C_UnitAuras.GetAuraDataBySpellName`
- `C_UnitAuras.GetPlayerAuraBySpellID`
- `C_UnitAuras.GetUnitAuraBySpellID`

### `RequiresSpellDiminishUI` — 3

- `C_SpellDiminish.GetAllSpellDiminishCategories`
- `C_SpellDiminish.GetSpellDiminishCategoryInfo`
- `C_SpellDiminish.ShouldTrackSpellDiminishCategory`

### `RequiresSupportedScript` — 3

> Requires a valid script type supported by this object. If not supported, functions will return no values.

- `GetScript`
- `GetScript`
- `GetScript`

### `SecretWhenEncounterEvent` — 3

- `C_EncounterTimeline.GetEventColor`
- `C_EncounterTimeline.GetEventInfo`
- `ENCOUNTER_TIMELINE_EVENT_ADDED (event)`

### `SecretWhenLuaTableHasSecretKeys` — 3

> Guarded APIs produce secret values if the subject Lua table contains any secret keys.

- `table.count`
- `table.getcountinfo`
- `table.isempty`

### `SecretWhenNumericFormatterSecret` — 3

- `FormatElapsedDuration`
- `FormatRemainingDuration`
- `FormatTotalDuration`

### `RequiresFontStringTextAccess` — 2

> Guarded APIs reject access for tainted callers if the object has the secret Text aspect assigned.

- `CalculateScreenAreaFromCharacterSpan`
- `FindCharacterIndexAtCoordinate`

### `RequiresRestrictedAbbreviationBreakpoints` — 2

- `CreateAbbreviateConfig`
- `SetAbbreviateNumberData`

### `RequiresValidAbbreviationBreakpoints` — 2

- `AddBreakpoint`
- `SetBreakpoints`

### `SecretInActivePvPMatch` — 2

> Guarded APIs and events produce secret values when PvP match addon restrictions are in effect.

- `C_PvP.GetScoreInfo`
- `C_PvP.GetScoreInfoByPlayerGuid`

### `SecretWhenLossOfControlInfoRestricted` — 2

> Guarded APIs and events always produce secret values, unless the active player is an active spectator or commentator of a PvP match.

- `ARENA_CROWD_CONTROL_SPELL_UPDATE (event)`
- `C_PvP.GetArenaCrowdControlInfo`

### `SecretWhenLossOfControlRestricted` — 2

> Guarded APIs always produce secret values, unless the active player is an active spectator or commentator of a PvP match.

- `C_LossOfControl.GetActiveLossOfControlData`
- `C_LossOfControl.GetActiveLossOfControlDataByUnit`

### `SecretWhenTotemSlotSecret` — 2

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect. Individual totem spell auras may be flagged as never or always secret, which takes priority over restrictions.

- `GetTotemInfo`
- `GetTotemTimeLeft`

### `SecretWhenUnitPossessionRestricted` — 2

> Guarded APIs and events produce secret values based on aura secrecy, except for unit tokens under the player's direct control.

- `UnitIsCharmed`
- `UnitIsPossessed`

### `SecretWhenUnitThreatStateRestricted` — 2

> Guarded APIs and events produce secret values based upon supplied unit tokens. Queries where only one unit token is specified, or where one unit token is the player, their pet, or an ally while the other is a nameplate, boss, target, etc., are generally not secret.

- `UnitThreatLeadSituation`
- `UnitThreatSituation`

### `SecretWhenUnitThreatValuesRestricted` — 2

> Guarded APIs and events produce secret values based upon supplied unit tokens. Queries where only one unit token is specified, or where one unit token is the player, their pet, or an ally while the other is a non-boss or nameplate target, are generally not secret.

- `UnitDetailedThreatSituation`
- `UnitThreatPercentageOfLead`

### `RequiresComparableUnitTokens` — 1

> Guarded APIs only accept unit token pairs that can be compared with one another. For example, comparisons where either unit is 'player' or 'target' are permitted, but comparisons between 'nameplate3' and 'boss1' are not.

- `UnitIsUnit`

### `RequiresIndexInRange` — 1

- `C_CVar.SetCVarBitfield`

### `RequiresScriptObjectAlphaAccess` — 1

- `GetEffectiveAlpha`

### `RequiresScriptObjectDesaturationAccess` — 1

- `IsDesaturated`

### `RequiresStatusBarDesaturationAccess` — 1

- `IsStatusBarDesaturated`

### `RequiresUnitIdentityAccess` — 1

> Guarded APIs and events require that callers have access to unit identity values. This does not raise a blocked action error - instead, protected APIs will return no values.

- `UnitCreatureID`

### `SecretWhenAurasRestricted` — 1

> Guarded APIs and events produce secret values when combat, encounter, challenge mode, or PvP match addon restrictions are in effect.

- `UNIT_AURA (event)`

### `SecretWhenUnitComparisonRestricted` — 1

> Guarded APIs and events produce secret values based upon supplied unit tokens. Comparisons involving compound unit tokens (eg. 'boss1target') are always secret. This restriction only applies when the player is on an addon-restricted map.

- `UnitIsUnit`

### `SecretWhenUnitHealthMaxRestricted` — 1

> Guarded APIs and events produce secret values when the unit isn't player-controlled.

- `UnitHealthMax`

### `SecretWhenUnitNameIdentityRestricted` — 1

> Guarded APIs and events produce secret values under regular unit identity secrecy rules, except in PvP when the queried unit is a player.

- `UnitName`

### `SecretWhenUnitPowerMaxRestricted` — 1

> Guarded APIs and events produce secret values when the unit isn't player-controlled. Individual power types may be flagged as never or always secret, which takes priority.

- `UnitPowerMax`

## Fields that are never secret

`NeverSecret = true` on a field is a deliberate hole in a restriction: the structure goes
secret and these do not. They are where an addon on this client is still allowed to work, and
they are the most useful list in this file.

| structure | fields that survive |
|---|---|
| `ChatMessageEventParams` | `channelBaseName`, `channelIndex`, `channelName`, `hideSenderInLetterbox`, `isMobile`, `isSubtitle`, `languageID`, `languageName`, `lineID`, `specialFlags`, `suppressRaidIcons`, `zoneChannelID` |
| `ClubInfo` | `clubId`, `clubType`, `memberCount` |
| `ClubMemberInfo` | `faction`, `isSelf` |
| `ClubStreamInfo` | `streamType` |
| `DamageMeterCombatSource` | `classFilename`, `classification`, `deathRecapID`, `isLocalPlayer` |
| `DamageMeterCombatSpellUnitDetails` | `classification`, `unitClassFilename` |
| `EncounterTimelineEventInfo` | `duration`, `id`, `maxQueueDuration`, `source` |
| `LfgApplicantData` | `applicationStatus`, `numMembers`, `pendingApplicationStatus` |
| `LfgEntryData` | `activityIDs` |
| `LfgSearchResultData` | `partyGUID` |
| `LossOfControlData` | `displayType`, `priority` |
| `PVPScoreInfo` | `className`, `classToken`, `faction`, `gender`, `honorLevel`, `name`, `raceName` |
| `PVPStatInfo` | `iconName`, `name`, `orderIndex`, `pvpStatID`, `tooltip` |
| `SpellChargeInfo` | `isActive`, `maxCharges` |
| `SpellCooldownInfo` | `isActive`, `isEnabled`, `isOnGCD` |
| `SpellLossOfControlInfo` | `isActive`, `shouldReplaceNormalCooldown` |
| `UnitCastingInfoResult` | `castBarID`, `delayTimeMs`, `isTradeskill` |
| `UnitChannelInfoResult` | `castBarID`, `isEmpowered`, `isTradeskill`, `numEmpowerStages` |
| `VoiceChatChannel` | `channelID`, `channelType`, `clubId`, `isActive`, `isMuted`, `isTranscribing`, `isTransmitting`, `streamId`, `volume` |

## What is not loaded on `camelot`

Blizzard ships one interface for every game type and gates the files in each `.toc`. A function
defined in a gated-out file does not exist in this game, whatever the documentation says and
whatever CVar the file checks on its first line. This is the trap that catches every addon
ported from Classic or retail, and it is silent: the global is simply nil.

Whole addons excluded (48):

| addon | loads on |
|---|---|
| `Blizzard_AccountStore` | standard, wowlabs |
| `Blizzard_ArrowCalloutFrame` | plunderstorm |
| `Blizzard_ChallengesUI` | standard, mists |
| `Blizzard_ClassTrial` | standard |
| `Blizzard_ClassTrialSecure` | standard |
| `Blizzard_DelvesDifficultyPicker` | standard |
| `Blizzard_DelvesToast` | standard |
| `Blizzard_DeprecatedSpecialization` | classic, standard |
| `Blizzard_EncounterJournal` | standard, classic |
| `Blizzard_EncounterTimeline` | standard |
| `Blizzard_EncounterWarnings` | standard |
| `Blizzard_EndMatchUI` | plunderstorm |
| `Blizzard_EndOfMatchUI` | plunderstorm |
| `Blizzard_ExpansionLandingPage` | standard |
| `Blizzard_ExpansionTrial` | all, not camelot |
| `Blizzard_GarrisonUI` | mainline, not camelot |
| `Blizzard_GenericShoppingCart` | standard |
| `Blizzard_GroupFinder` | all, not camelot |
| `Blizzard_HUDInventoryTemplates` | plunderstorm, wowhack |
| `Blizzard_HouseEditor` | standard |
| `Blizzard_HouseList` | standard |
| `Blizzard_HousingBlueprint` | standard |
| `Blizzard_HousingBulletinBoard` | standard |
| `Blizzard_HousingCharter` | standard |
| `Blizzard_HousingControls` | standard |
| `Blizzard_HousingCornerstone` | standard |
| `Blizzard_HousingCreateNeighborhood` | standard |
| `Blizzard_HousingDashboard` | standard |
| `Blizzard_HousingEventHandler` | standard |
| `Blizzard_HousingHouseFinder` | standard |
| `Blizzard_HousingHouseSettings` | standard |
| `Blizzard_HousingInspectModeUI` | standard |
| `Blizzard_HousingMarketCart` | standard |
| `Blizzard_HousingModelPreview` | standard |
| `Blizzard_HousingTemplates` | standard |
| `Blizzard_HousingTutorials` | standard |
| `Blizzard_ItemBeltFrame` | plunderstorm |
| `Blizzard_PVPUI` | mainline, mists, not camelot |
| `Blizzard_PerksProgram` | all, not camelot |
| `Blizzard_PhotoSharing` | standard |
| `Blizzard_Plunderstorm` | plunderstorm |
| `Blizzard_PlunderstormPrematchUI` | plunderstorm |
| `Blizzard_RPE_TurnStrafe` | standard |
| `Blizzard_RemixArtifactTutorialUI` | standard |
| `Blizzard_RemixArtifactUI` | standard |
| `Blizzard_SpectateFrame` | plunderstorm |
| `Blizzard_SpellPickUpIndicator` | plunderstorm |
| `Blizzard_WorldLootObjectList` | plunderstorm |

Individual files excluded (225):

| addon | file | loads on |
|---|---|---|
| `Blizzard_AchievementUI` | `Cata\Blizzard_AchievementUI.lua` | cata, mists |
| `Blizzard_AchievementUI` | `Cata\Blizzard_AchievementUI.xml` | cata, mists |
| `Blizzard_CharacterSelectNavBar` | `CharacterSelectNavTemplates.xml` | all, not camelot |
| `Blizzard_ChatFrame` | `Mainline\ChatConfigFrameOverrides.lua` | mainline, not camelot |
| `Blizzard_ChatFrame` | `Vanilla\ChatConfigFrame.lua` | vanilla, tbc |
| `Blizzard_ChatFrame` | `Wrath\ChatConfigFrame.lua` | wrath, cata, mists |
| `Blizzard_Collections` | `Shared\Blizzard_CollectionsTabs.xml` | all, not camelot |
| `Blizzard_Collections` | `Shared\Blizzard_PetCollection.lua` | mists, mainline, not camelot |
| `Blizzard_Collections` | `Shared\Blizzard_PetCollection.xml` | mists, mainline, not camelot |
| `Blizzard_CombatLogBase` | `Vanilla\CombatLogColors.lua` | vanilla, tbc |
| `Blizzard_CombatLogBase` | `Wrath\CombatLogColors.lua` | wrath, cata, mists |
| `Blizzard_CustomizationUI` | `Shared\Blizzard_CustomizationOptionTemplates.xml` | all, not camelot classic |
| `Blizzard_Deprecated` | `Classic/Deprecated_1_15_8.lua` | classic |
| `Blizzard_Deprecated` | `Classic/Deprecated_2_5_5.lua` | classic |
| `Blizzard_EditMode` | `Classic\EditModePresetLayoutConstants.lua` | classic |
| `Blizzard_EditMode` | `Wrath\EditModePresetLayoutConstants.lua` | wrath, cata |
| `Blizzard_FrameXML` | `Cata\Blizzard_TalentUITemplates.xml` | cata, mists |
| `Blizzard_FrameXML` | `Cata\Blizzard_TalentUITemplates.xml` | cata, mists |
| `Blizzard_FrameXML` | `Cata\CharacterFrameTemplates.lua` | cata, mists |
| `Blizzard_FrameXML` | `Cata\CharacterFrameTemplates.xml` | cata, mists |
| `Blizzard_FrameXML` | `Cata\WorldStateFrame.xml` | cata |
| `Blizzard_FrameXML` | `EquipmentFlyout.lua` | cata, mists, standard, wowlabs, wowhack, plunderstorm |
| `Blizzard_FrameXML` | `EquipmentFlyout.xml` | cata, mists, standard, wowlabs, wowhack, plunderstorm |
| `Blizzard_FrameXML` | `FloatingPetBattleTooltip.lua` | mists, mainline, not camelot |
| `Blizzard_FrameXML` | `FloatingPetBattleTooltip.xml` | mists, mainline, not camelot |
| `Blizzard_FrameXML` | `TBC\WorldStateFrame.lua` | wrath, cata, mists |
| `Blizzard_FrameXML` | `TBC\WorldStateFrame.xml` | wrath |
| `Blizzard_FrameXML` | `Vanilla\TalentFrameBase.lua` | vanilla, tbc, wrath |
| `Blizzard_FrameXML` | `Wrath\SparkleFrame.lua` | wrath, cata, mists |
| `Blizzard_FrameXML` | `Wrath\SparkleFrame.xml` | wrath, cata, mists |
| `Blizzard_FrameXMLBase` | `Cata\Constants.lua` | cata mists |
| `Blizzard_FrameXMLBase` | `Mists\Constants.lua` | mists |
| `Blizzard_FrameXMLBase` | `TBC\Constants.lua` | tbc |
| `Blizzard_FrameXMLBase` | `TBC\Localization.lua` | tbc wrath cata mists |
| `Blizzard_FrameXMLBase` | `Vanilla\Constants.lua` | vanilla |
| `Blizzard_FrameXMLBase` | `Vanilla\Localization.lua` | vanilla |
| `Blizzard_FrameXMLBase` | `Wrath\Constants.lua` | wrath cata mists |
| `Blizzard_FrameXMLUtil` | `Classic\DifficultyUtil.lua` | classic |
| `Blizzard_FrameXMLUtil` | `Classic\DifficultyUtil_Base.lua` | classic |
| `Blizzard_FrameXMLUtil` | `Classic\PartyUtil.lua` | classic |
| `Blizzard_FrameXMLUtil` | `DifficultyUtil_Shared.lua` | classic |
| `Blizzard_FrameXMLUtil` | `Mainline\QuestUtilsOverrides.lua` | mainline, not camelot |
| `Blizzard_FrameXMLUtil` | `NameUtil.lua` | all, not camelot |
| `Blizzard_Game` | `Cata\EventImplementation.lua` | cata, mists |
| `Blizzard_Game` | `Cata\EventRouting.lua` | cata, mists |
| `Blizzard_Game` | `Cata\Game.lua` | cata, mists |
| `Blizzard_Game` | `Startup.lua` | classic, mainline, not vanilla, camelot |
| `Blizzard_Game` | `TBC\EventImplementation.lua` | tbc, wrath, cata, mists |
| `Blizzard_Game` | `TBC\EventRouting.lua` | tbc, wrath, cata, mists |
| `Blizzard_Game` | `TBC\Game.lua` | tbc, wrath, cata, mists |
| `Blizzard_Game` | `Vanilla\EventImplementation.lua` | classic |
| `Blizzard_Game` | `Vanilla\EventRouting.lua` | classic |
| `Blizzard_Game` | `Vanilla\Game.lua` | classic |
| `Blizzard_Game` | `Wrath\EventImplementation.lua` | wrath, cata, mists |
| `Blizzard_Game` | `Wrath\EventRouting.lua` | wrath, cata, mists |
| `Blizzard_Game` | `Wrath\Game.lua` | wrath, cata, mists |
| `Blizzard_GameMenu` | `Classic\GameMenuFrameOverrides.lua` | classic |
| `Blizzard_GlueXML` | `Cata\Localization.lua` | cata, mists |
| `Blizzard_GlueXML` | `Cata\RealmList.xml` | cata, mists |
| `Blizzard_GlueXML` | `Shared\CharacterServicesPaidNameChange.lua` | wrath, cata, mists |
| `Blizzard_GlueXML` | `SocialContract.lua` | classic |
| `Blizzard_GlueXML` | `SocialContract.xml` | classic |
| `Blizzard_GlueXML` | `TBC\CreditsFrame.lua` | tbc, wrath, cata, mists |
| `Blizzard_GlueXML` | `TBC\CreditsFrame.xml` | tbc, wrath, cata, mists |
| `Blizzard_GlueXML` | `TBC\RealmList.lua` | tbc, wrath, cata, mists |
| `Blizzard_GlueXML` | `TBC\RealmList.xml` | tbc, wrath |
| `Blizzard_GlueXML` | `Vanilla\CharacterSelectConstants.lua` | cata |
| `Blizzard_GlueXML` | `Vanilla\CharacterSelectConstants.lua` | vanilla, tbc, wrath |
| `Blizzard_GlueXMLBase` | `Wrath\Localization.lua` | wrath, cata, mists |
| `Blizzard_GuildBankUI` | `Mists\Blizzard_GuildBankUI.xml` | mists |
| `Blizzard_GuildBankUI` | `TBC\Blizzard_GuildBankUI.lua` | tbc, wrath, cata, mists |
| `Blizzard_GuildBankUI` | `TBC\Blizzard_GuildBankUI.xml` | tbc, wrath, cata |
| `Blizzard_InspectUI` | `Cata\InspectGuildFrame.lua` | cata, mists |
| `Blizzard_InspectUI` | `Cata\InspectGuildFrame.xml` | cata, mists |
| `Blizzard_InspectUI` | `Cata\InspectPaperDollFrame.lua` | cata, mists |
| `Blizzard_InspectUI` | `TBC\Blizzard_InspectUI.lua` | tbc, wrath, cata, mists |
| `Blizzard_InspectUI` | `TBC\Blizzard_InspectUI.xml` | tbc, wrath, cata, mists |
| `Blizzard_InspectUI` | `Vanilla\InspectPaperDollFrame.lua` | vanilla, tbc, wrath |
| `Blizzard_LFGUtil` | `Classic\LFGUtil.lua` | classic |
| `Blizzard_LFGUtil` | `Vanilla\LFGUtil.lua` | vanilla, tbc |
| `Blizzard_MainMenuBarBagButtons` | `Classic\BagsBarOverrides.lua` | classic |
| `Blizzard_MainMenuBarBagButtons` | `Classic\Keyring.lua` | classic |
| `Blizzard_MainMenuBarBagButtons` | `Classic\MainMenuBarBagButtonsConsts.lua` | vanilla, tbc |
| `Blizzard_MainMenuBarBagButtons` | `Mists\MainMenuBarBagButtonsConsts.lua` | mists |
| `Blizzard_MainMenuBarBagButtons` | `Wrath\MainMenuBarBagButtonsConsts.lua` | wrath, cata |
| `Blizzard_Menu` | `Cata\MenuVariants.lua` | cata, mists |
| `Blizzard_Menu` | `Menu.xml` | all, not camelot |
| `Blizzard_Menu` | `Vanilla\MenuVariants.lua` | vanilla, tbc, wrath |
| `Blizzard_MicroMenu` | `Shared\MainMenuBarMicroMenu.xml` | all, not camelot |
| `Blizzard_MicroMenu` | `Vanilla\MicroMenuContainerOverrides.lua` | tbc |
| `Blizzard_Minimap` | `Wrath\GameTime.lua` | wrath, cata, mists |
| `Blizzard_Minimap` | `Wrath\GameTime.xml` | wrath, cata, mists |
| `Blizzard_NamePlates` | `Blizzard_NamePlateConstants.lua` | all, not camelot |
| `Blizzard_NamePlates` | `Blizzard_NamePlateLevelFrame.lua` | all, not camelot |
| `Blizzard_NamePlates` | `Blizzard_NamePlateLevelFrame.xml` | all, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_DeathKnight.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_DeathKnight.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Dracthyr.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Dracthyr.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Druid.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Druid.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Mage.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Mage.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Monk.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Monk.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Paladin.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Paladin.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Rogue.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Rogue.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Warlock.lua` | mainline, not camelot |
| `Blizzard_NamePlates` | `Mainline\Blizzard_ClassNameplateBar_Warlock.xml` | mainline, not camelot |
| `Blizzard_NamePlates` | `WoWHack\Blizzard_ClassNameplateBar_AlternatePower.lua` | wowhack |
| `Blizzard_NamePlates` | `WoWHack\Blizzard_ClassNameplateBar_AlternatePower.xml` | wowhack |
| `Blizzard_PVPMatch` | `PVPMatchResults.lua` | standard |
| `Blizzard_PVPMatch` | `PVPMatchResults.xml` | standard |
| `Blizzard_PVPMatch` | `PVPMatchScoreboard.lua` | standard |
| `Blizzard_PVPMatch` | `PVPMatchScoreboard.xml` | standard |
| `Blizzard_PerformanceBar` | `Classic\PerformanceBarOverrides.lua` | classic |
| `Blizzard_PersonalResourceDisplay` | `AlternatePowerBars/DemonHunterAlternatePower.lua` | all, not camelot |
| `Blizzard_PersonalResourceDisplay` | `AlternatePowerBars/EvokerAlternatePower.lua` | all, not camelot |
| `Blizzard_PersonalResourceDisplay` | `AlternatePowerBars/MonkAlternatePower.lua` | all, not camelot |
| `Blizzard_ProfessionsBook` | `Blizzard_ProfessionsBook.xml` | all, not camelot |
| `Blizzard_ProjectConstants` | `WoWLabs\ProjectConstants.lua` | plunderstorm |
| `Blizzard_RaidFrame` | `Wrath\RaidFrame.xml` | wrath, cata, mists |
| `Blizzard_RaidUI` | `Mists\Blizzard_RaidUI.xml` | mists |
| `Blizzard_RaidUI` | `Wrath\Blizzard_RaidUI.xml` | wrath, cata |
| `Blizzard_RestrictedAddOnEnvironment` | `SecureAuraHeader.lua` | classic |
| `Blizzard_RestrictedAddOnEnvironment` | `SecureAuraHeader.xml` | classic |
| `Blizzard_SettingsDefinitions_Frame` | `Mounts.lua` | all, not camelot classic |
| `Blizzard_Settings_Shared` | `Mainline\NewDefinitions.lua` | standard |
| `Blizzard_SharedMapDataProviders_Mainline` | `EncounterJournalDataProvider.xml` | all, not camelot |
| `Blizzard_SharedXML` | `Classic\ClassicCvarUtil.lua` | classic |
| `Blizzard_SharedXML` | `Classic\Dialog\DialogTemplates.xml` | classic |
| `Blizzard_SharedXML` | `Classic\GlueCheck.lua` | classic |
| `Blizzard_SharedXML` | `Classic\SecureCurrencyUtil.lua` | classic |
| `Blizzard_SharedXML` | `Classic\SliderTemplates.xml` | classic |
| `Blizzard_SharedXML` | `Classic\Stubs.lua` | classic |
| `Blizzard_SharedXML` | `Classic\Stubs.xml` | classic |
| `Blizzard_SharedXML` | `Wrath\SoundKitConstants.lua` | wrath cata mists |
| `Blizzard_StoreUI` | `TBC\Blizzard_StoreUI.xml` | tbc wrath cata mists |
| `Blizzard_StoreUI` | `TBC\Blizzard_StoreUISecure.lua` | tbc wrath cata mists |
| `Blizzard_StoreUI` | `Vanilla\Blizzard_StoreUI.xml` | vanilla |
| `Blizzard_StoreUI` | `Vanilla\Blizzard_StoreUISecure.lua` | vanilla |
| `Blizzard_TimeManager` | `Cata\Blizzard_TimeManagerOverrides.lua` | cata, mists |
| `Blizzard_TokenUI` | `Mainline/Blizzard_TokenUI.lua` | all, not camelot |
| `Blizzard_TokenUI` | `Mainline/Blizzard_TokenUI.xml` | all, not camelot |
| `Blizzard_UIPanels_Game` | `Cata\HonorFrame.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\HonorFrame.xml` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\PVPFrame.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\PVPFrame.xml` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\PaperDollFrameStats.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\PetStable.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\PetStable.xml` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\QuestLogFrame.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\QuestLogFrame.xml` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\ReputationFrame.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\ReputationFrame.xml` | cata, mists |
| `Blizzard_UIPanels_Game` | `Cata\SpellBookProfessions.lua` | cata, mists |
| `Blizzard_UIPanels_Game` | `Mainline\PaperDollFrameStats.lua` | standard |
| `Blizzard_UIPanels_Game` | `Mists\BankFrame.xml` | mists |
| `Blizzard_UIPanels_Game` | `Mists\ContainerFrame.lua` | mists |
| `Blizzard_UIPanels_Game` | `Mists\QuestScrollFrameAndPanelTemplates.xml` | mists |
| `Blizzard_UIPanels_Game` | `Mists\WatchFrameScenario.xml` | mists |
| `Blizzard_UIPanels_Game` | `Shared\SocialQueue.lua` | classic |
| `Blizzard_UIPanels_Game` | `TBC\BankFrame.lua` | tbc, wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `TBC\BankFrame.xml` | tbc, wrath, cata |
| `Blizzard_UIPanels_Game` | `TBC\MerchantFrame.lua` | tbc, wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `TBC\MerchantFrame.xml` | tbc, wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `TBC\QuestFrame.lua` | tbc, wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `TBC\QuestFrame.xml` | tbc, wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `TBC\QuestFrameTemplates.xml` | tbc, wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `TBC\QuestScrollFrameAndPanelTemplates.xml` | tbc, wrath, cata |
| `Blizzard_UIPanels_Game` | `Vanilla\BankFrame.lua` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\BankFrame.xml` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\ContainerFrame.lua` | vanilla, tbc |
| `Blizzard_UIPanels_Game` | `Vanilla\HonorFrame.lua` | vanilla, tbc, wrath |
| `Blizzard_UIPanels_Game` | `Vanilla\HonorFrame.xml` | vanilla, tbc, wrath |
| `Blizzard_UIPanels_Game` | `Vanilla\Localization.lua` | vanilla, tbc |
| `Blizzard_UIPanels_Game` | `Vanilla\MerchantFrame.lua` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\MerchantFrame.xml` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\PaperDollFrameStats.lua` | classic |
| `Blizzard_UIPanels_Game` | `Vanilla\QuestFrame.lua` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\QuestFrame.xml` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\QuestFrameTemplates.xml` | vanilla |
| `Blizzard_UIPanels_Game` | `Vanilla\ReputationFrame.lua` | vanilla, tbc |
| `Blizzard_UIPanels_Game` | `Vanilla\ReputationFrame.xml` | vanilla, tbc |
| `Blizzard_UIPanels_Game` | `Vanilla\SpellBookFrame.lua` | vanilla, tbc, wrath |
| `Blizzard_UIPanels_Game` | `Vanilla\SpellBookFrame.xml` | vanilla, tbc, wrath |
| `Blizzard_UIPanels_Game` | `Wrath\BattlefieldFrame.lua` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\BattlefieldFrame.xml` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\ContainerFrame.lua` | wrath, cata |
| `Blizzard_UIPanels_Game` | `Wrath\PVPFrame.lua` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\PVPFrame.xml` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\PetStable.lua` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\PetStable.xml` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\QuestInfo.lua` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\QuestInfo.xml` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\QuestMapFrame.lua` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\QuestMapFrame.xml` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\QuestPOI.lua` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\QuestPOI.xml` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\ReputationFrame.lua` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\ReputationFrame.xml` | wrath |
| `Blizzard_UIPanels_Game` | `Wrath\WatchFrame.lua` | wrath, cata, mists |
| `Blizzard_UIPanels_Game` | `Wrath\WatchFrame.xml` | wrath, cata, mists |
| `Blizzard_UnitFrame` | `Cata\EclipseBarFrame.lua` | cata, mists |
| `Blizzard_UnitFrame` | `Cata\EclipseBarFrame.xml` | cata, mists |
| `Blizzard_UnitFrame` | `Cata\RuneFrame.lua` | cata, mists |
| `Blizzard_UnitFrame` | `Cata\RuneFrame.xml` | cata, mists |
| `Blizzard_UnitFrame` | `DemonHunterSoulFragmentsBar.lua` | mainline, not camelot |
| `Blizzard_UnitFrame` | `DemonHunterSoulFragmentsBar.xml` | mainline, not camelot |
| `Blizzard_UnitFrame` | `DevourerFuryBar.lua` | mainline, not camelot |
| `Blizzard_UnitFrame` | `DevourerFuryBar.xml` | mainline, not camelot |
| `Blizzard_UnitFrame` | `Mists\AlternatePowerBar.xml` | mists |
| `Blizzard_UnitFrame` | `Shared\Localization.lua` | all, not camelot |
| `Blizzard_UnitFrame` | `Vanilla\TargetFrameOverrides.lua` | vanilla |
| `Blizzard_UnitFrame` | `Wrath\AlternatePowerBar.lua` | wrath, cata, mists |
| `Blizzard_UnitFrame` | `Wrath\AlternatePowerBar.xml` | wrath, cata |
| `Blizzard_UnitFrame` | `Wrath\RuneFrame.lua` | wrath |
| `Blizzard_UnitFrame` | `Wrath\RuneFrame.xml` | wrath |
| `Blizzard_UnitPopup` | `TBC\UnitPopup.lua` | tbc, wrath, cata, mists |
| `Blizzard_UnitPopup` | `Wrath\UnitPopupButtons.lua` | cata, mists |
| `Blizzard_UnitPopup` | `Wrath\UnitPopupMenus.lua` | cata, mists |
| `Blizzard_WorldMap_Mainline` | `WoWLabs/WM_WoWLabsAreaDataProvider.lua` | plunderstorm |
| `Blizzard_WorldMap_Mainline` | `WoWLabs/WM_WoWLabsAreaDataProvider.xml` | plunderstorm |

## What this means for an addon on this realm

Every claim here is a reading of a row in this file. The rows are generated; the readings are
not, and they are marked as readings.

**The combat log is shut, and two replacements for it are open.** `C_DamageMeter` carries
`SecretWhenInCombat`, so its numbers arrive once the fight is over. `C_DeathRecap` carries
**nothing at all** -- four functions, no annotation on any of them -- and hands back
combat-log-shaped rows for the last seconds of your life.

**`mainline` in a `.toc` is a family, and camelot is inside it.** This is the most expensive
mistake available in this file and it is not a secrecy rule at all. Reading `AllowLoadGameType:
mainline` as a game type rather than a family hides twenty-eight addons that do load here --
the mail frame, the friends list, the auction house, professions, achievements, the collections
journal -- and it invents gaps in the interface that are not there. The giveaway is in the
tocs themselves: six addons gated to `mainline` go on to name camelot-only files inside
themselves, and `Blizzard_Collections` writes `[AllowLoadGameType mainline]` and
`[ExcludeLoadGameType camelot]` on the same line, which is only meaningful if mainline would
otherwise admit camelot. `standard` is the sibling, not the parent: eleven addons write
`standard, camelot` and none gated to `standard` alone names a camelot file.

**The two open namespaces have frames here after all, and the frames answer narrower
questions than the calls do.** `C_LossOfControl` and `C_DeathRecap` carry no secrecy
annotation whatever, and both of their frames load on this game type through the family above.
What is still missing is not the data and not a window -- it is the reading.

| namespace | its frame | loads here | what the frame shows |
|---|---|---|---|
| `C_LossOfControl` | `Blizzard_FrameXML/LossOfControlFrame.lua` | yes, mists + mainline | one effect at a time, highest priority then longest remaining, behind the `lossOfControl` CVar |
| `C_DeathRecap` | `Blizzard_DeathRecap/Mainline/Blizzard_DeathRecap.lua` | yes, mainline | the rows, in a window you open afterwards from the damage meter, the death dialog or a chat link |

**An enemy cast bar cannot be built.** `SecretWhenUnitSpellCastRestricted` is documented as
secret "if the unit being queried for cast information is not the player or their pet", and
`UnitCastingDuration` beside it carries a bare `SecretReturns`. There is no condition to wait
out and no window where it opens.

**Enemy names survive in PvP, deliberately.** `SecretWhenUnitNameIdentityRestricted` is
documented as the ordinary identity rules "except in PvP when the queried unit is a player".
That carve-out is what lets a kill tracker, a dossier and a battleground roster work at all.

**A battleground scoreboard is names and ranks until the match ends.** `SecretInActivePvPMatch`
seals `C_PvP.GetScoreInfo` for the whole match, and `PVPScoreInfo` leaves seven fields open --
including `honorLevel`, which on this game type is the PvP rank.

**Whether a cooldown is running is always knowable; how long is not.** `SpellCooldownInfo`
leaves `isActive`, `isEnabled` and `isOnGCD` never-secret while the call around it carries
`SecretWhenCooldownsRestricted`. An addon can say "that is on cooldown" under restriction and
cannot say for how long.

**`pcall` is not optional.** `RequiresUnitAuraAccess` fails by `Error`, which throws rather
than returning nothing. Anything reading auras needs the call wrapped.

**A secret is not a nil and not a zero.** Three different failures look identical from the
outside -- a secret value, a precondition that returned nothing, and a function that was never
loaded on this game type -- and each wants different code. The first needs unwrapping, the
second needs checking, and the third needs a different function.

## Namespaces, and where they are allowed to run

`Environment` is the client's own note about where a namespace exists. `All` is every
environment; anything else is worth reading before building on it.

| environment | namespaces |
|---|---|
| All | 284 |
| SecureOnly | 2 |

**SecureOnly** (2): `C_CombatLogSecure`, `C_PingSecure`

