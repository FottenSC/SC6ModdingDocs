# Online Matchmaking Internals

How SC6 advertises, searches, and filters online player rooms and ranked
matches. This page covers lobby discovery and session metadata; for the
per-frame netplay transport after a match starts, see
[Leaderboards & Online: in-match netplay](leaderboards.md#in-match-netplay-the-per-frame-input-ring).

All addresses are absolute (image base `0x140000000`).

!!! note "Scope"
    The code below is the PC Steam build's Luxor/UE session layer. It uses
    UE4.17.2 `IOnlineSession` settings and search queries, backed by
    OnlineSubsystemSteam. It is not Steam's `StartMatchmaking` API and it is
    not the channel-5 input transport used during the fight.

## At a glance

SC6 has two game-facing matchmaking families:

| Family | What it creates/searches | Native setting struct |
|---|---|---|
| Player match | Player rooms, casual lobbies, tournament/private room metadata | `FLuxorPlayerMatchSessionSetting` |
| Ranked match | Ranked match tickets with rank-window, area/language, QoS, and previous-result metadata | `FLuxorRankMatchSessionSetting` |

Both paths publish plain UE session key/value metadata such as
`CUSTOMSEARCHINT1`, `SEARCHKEYWORDS`, and `PRESENCESEARCH`. The important
thing for modders is that search behavior is almost entirely controlled by
which keys are inserted into `FOnlineSessionSearch::QuerySettings`.

## Entry points

The reflected API lives under `/Script/LuxorSessionUtil` on `ULuxorSessionHub`.
The dispatcher functions marshal BP parameters, then call the native helpers:

| Reflected dispatcher | Native helper | Role |
|---|---|---|
| `DispatchLuxorSessionHubCreatePlayerSession @ 0x142e47d80` | `CreateLuxorPlayerSession @ 0x142e14bd0` | Advertise a player-match room. |
| `DispatchLuxorSessionHubFindPlayerSession @ 0x142e48180` | `FindLuxorPlayerSession @ 0x142e17580` | Search player-match rooms. |
| `DispatchLuxorSessionHubCreateRankSession @ 0x142e47ee0` | `CreateLuxorRankSession @ 0x142e15850` | Advertise a ranked-match ticket. |
| `DispatchLuxorSessionHubFindRankSession @ 0x142e48360` | `FindLuxorRankSession @ 0x142e18030` | Search ranked-match tickets. |
| - | `CreatePlayerMatchSessionSearch @ 0x142e18e20` | Allocates the shared `FOnlineSessionSearch` object used by both find paths. |
| - | `InitializePlayerMatchSessionSettings @ 0x142e18ef0` | Seeds common advertised session settings. |

The find helpers replace `ULuxorSessionHubPartial+0x38` and `+0x40` with the
new search object and its shared-reference controller, then call the online
session interface's `FindSessions` path.

## Repeated matches and rematches

There are two similarly named concepts in this area, but they are not the
same thing.

| Concept | Where it lives | What it does |
|---|---|---|
| Previous ranked result | `FLuxorRankMatchSessionSetting.nPrevBattleResult` at `+0x34` | Becomes `CUSTOMSEARCHINT7` in ranked session metadata. `FindLuxorRankSession` only searches this key when the value is nonzero. |
| Rematch type | `ULuxorMatchData.nRematchType` at `+0x2f0` | Match-data/UI state exposed by `GetLuxorMatchDataRematchType` / `SetLuxorMatchDataRematchType`. It is not inserted into session search settings. |

So the repeated-match-looking filter in the verified matchmaking helpers is
ranked-only and result-based: `nPrevBattleResult -> CUSTOMSEARCHINT7`.
Player-match search has no previous-result key, and neither helper family
adds a recent opponent Steam ID, `FUniqueNetId`, or explicit opponent blacklist
to the search query. If SC6 avoids some immediate repeats, that behavior would
have to live above or beside these helpers; it is not visible in the session
metadata path documented here.

The producer side is in the cooked Blueprint
`BP_LuxFightRequest.CreateMatchSetting`. It builds
`FLuxorRankMatchSessionSetting.PrevBattleResult` from the local profile's
winning-streak state:

| `PrevBattleResult` | Producer-side meaning | Native search behavior |
|---:|---|---|
| `0` | Ignore/relaxed search bucket | Do not insert `CUSTOMSEARCHINT7` into the ranked query. |
| `1` | `GetWinningStreak(profile, StyleId) != 0` | Exact-match `CUSTOMSEARCHINT7 == 1` when the filter gate is active. |
| `2` | `GetWinningStreak(profile, StyleId) == 0` | Exact-match `CUSTOMSEARCHINT7 == 2` when the filter gate is active. |

That means the first ranked search tries to match the same recent-result
bucket: winning-streak players with winning-streak advertisements, and
zero-streak/not-winning players with zero-streak/not-winning advertisements.
It is not a hard "never match winners with losers" rule, because
`CreateMatchSetting` gates the finder-side filter with
`IsSessionCreater ? true : RetryCount < 1`. Creators advertise `1` or `2`,
but finders switch to `0` after the first retry and the native search then
stops filtering on previous result.

### Same-opponent avoidance check

No native same-opponent avoidance filter has been found in the verified ranked
session path.

| Checked area | Evidence |
|---|---|
| Ranked setting metadata | `GetLuxorRankMatchSessionSettingStruct @ 0x142e46e30` registers only the fields shown in [`FLuxorRankMatchSessionSetting`](#ranked-match-settings). There is no reflected Steam ID, `FUniqueNetId`, recent-opponent, blacklist, or "same match" field. |
| Ranked query builder | `FindLuxorRankSession @ 0x142e18030` inserts rank-window, area/language, QoS-adjacent, near-class, keyword, presence, and optional previous-result keys. It does not read or insert an opponent identity key. |
| Search-result collection | `HandleLuxorFindSessionResult @ 0x142e1b970` copies every returned search result pointer from the current `FOnlineSessionSearch` into the callback array. It does not reject, reorder, or compare candidates by identity. |
| Reflected callback bridge | `InvokeFindSessionCallback @ 0x142e1ef40` copies the native result array into reflected callback parameters and calls `ProcessEvent`. It does not iterate over individual candidates. |
| `IsSameMatch` string | The recovered `IsSameMatch` metadata belongs to `ALuxBattleReplayPlayer`, not the `ULuxorSessionHub` ranked search path. |
| `opponent_*` and `revenge_match_num` strings | The recovered uses are post-match KPI/stat fields, not `FindSessions` query keys. |

The remaining place this could exist is higher-level Blueprint/UI code after
the native callback receives the result list. The native session query and
native result handoff documented here do not implement "avoid the previous
opponent" by identity.

Official patch notes line up with that reading: Ver. 1.30 says ranked
matchmaking quality was changed by removing the "Language" and "Area" search
filters and defaulting the ping/connection filter to "more than 4 Bars"; the
same note says ranked rematch-option limits were removed. It does not describe
a same-opponent avoidance rule during ranked search. See Bandai Namco's
[SOULCALIBUR VI Patch Notes Ver. 1.30](https://en.bandainamcoent.eu/soulcalibur/news/soulcalibur-vi-patch-notes-ver-130).

## Player-match settings

`FLuxorPlayerMatchSessionSetting` is `0x68` bytes:

| Offset | Type | Field |
|-------:|---|---|
| `+0x00` | `FString` | `sessionDisplayName` |
| `+0x10` | `int` | `nBattleType` |
| `+0x14` | `int` | `nBattleFormat` |
| `+0x18` | `int` | `nPlayStyle` |
| `+0x1c` | `int` | `nBattleCount` |
| `+0x20` | `int` | `nBattleTime` |
| `+0x24` | `int` | `nPlayerNum` |
| `+0x28` | `bool` | `fPublicFlag` |
| `+0x2c` | `int` | `nAreaSetting` |
| `+0x30` | `int` | `nAreaId` |
| `+0x34` | `int` | `nLanguageSetting` |
| `+0x38` | `int` | `nLanguageId` |
| `+0x3c` | `int` | `nMostRankId` |
| `+0x40` | `FString` | `roomName` |
| `+0x50` | `bool` | `fIsTournament` |
| `+0x58` | `FString` | `tournamentMatchId` |

### Player room advertisement

`CreateLuxorPlayerSession` initializes common session settings, clamps
`nPlayerNum` into public connections `[2, 8]`, caches pending room state in
`g_LuxorPendingPlayerSessionCreate`, then advertises these keys:

| Session key | Advertised value |
|---|---|
| `CUSTOMSEARCHINT1` | `nBattleType` |
| `CUSTOMSEARCHINT2` | `nBattleFormat` |
| `CUSTOMSEARCHINT3` | `nPlayStyle` |
| `CUSTOMSEARCHINT4` | `nBattleCount` |
| `CUSTOMSEARCHINT5` | `nBattleTime` |
| `CUSTOMSEARCHINT6` | `nAreaId` when `nAreaSetting == 0`; otherwise `0xff` |
| `CUSTOMSEARCHINT7` | `nLanguageId` when `nLanguageSetting == 0`; otherwise `0xff` |
| `EXCUSTOMSEARCHINT1` | raw `nAreaId` |
| `EXCUSTOMSEARCHINT2` | raw `nLanguageId` |
| `EXCUSTOMSEARCHINT3` | `nMostRankId` |
| `EXCUSTOMSEARCHINT4` | computed by `ComputePlayerMatchSearchInt4` from session name and tournament flag |
| `EXCUSTOMSEARCHINT5` | `roomName` |
| `SEARCHKEYWORDS` | text form of the incoming `FName` session name |
| `g_OnlineSessionPresenceFlagKey` | presence marker |

The advertised `SEARCHKEYWORDS` value is the session `FName`, not the visible
room name. A create/find mismatch here is enough to make rooms disappear from
search.

### Player room search

`FindLuxorPlayerSession` always inserts:

| Query key | Query value |
|---|---|
| `PRESENCESEARCH` | `true` |
| `CUSTOMSEARCHINT1` | `nBattleType` |
| `SEARCHKEYWORDS` | text form of the incoming `FName` session name |

It then conditionally inserts the optional filters:

| Query key | Inserted when | Query value |
|---|---|---|
| `CUSTOMSEARCHINT2` | `nBattleFormat != 0` | `nBattleFormat` |
| `CUSTOMSEARCHINT3` | `nPlayStyle != 0` | `nPlayStyle` |
| `CUSTOMSEARCHINT4` | `nBattleCount != 0` | `nBattleCount` |
| `CUSTOMSEARCHINT5` | `nBattleTime != 0` | `nBattleTime` |
| `CUSTOMSEARCHINT6` | `nAreaSetting == 0` | exact `nAreaId` |
| `CUSTOMSEARCHINT6` | `nAreaSetting == 1` | sentinel `0xff` |
| `CUSTOMSEARCHINT7` | `nLanguageSetting == 0` | exact `nLanguageId` |
| `CUSTOMSEARCHINT7` | `nLanguageSetting == 1` | sentinel `0xff` |

For area/language, search recognizes `0` as exact and `1` as world/all. Other
values fall through without adding that query key. Player-match search does
not add `nMostRankId`, previous result, rematch type, or opponent identity.

## Ranked-match settings

`FLuxorRankMatchSessionSetting` is `0x38` bytes:

| Offset | Type | Field |
|-------:|---|---|
| `+0x00` | `FString` | `sessionDisplayName` |
| `+0x10` | `int` | `nPlayerClass` |
| `+0x14` | `int` | `nLower` |
| `+0x18` | `int` | `nHigher` |
| `+0x1c` | `int` | `nSearchRankType` |
| `+0x20` | `int` | `nAreaSetting` |
| `+0x24` | `int` | `nAreaId` |
| `+0x28` | `int` | `nLanguageSetting` |
| `+0x2c` | `int` | `nLanguageId` |
| `+0x30` | `int` | `nQualityOfService` |
| `+0x34` | `int` | `nPrevBattleResult` |

`nSearchRankType` is present in the struct, but the verified create/find helper
pair does not directly publish it as a search key.

### Ranked advertisement

`CreateLuxorRankSession` clamps negative lower/higher rank bounds to `0`, then
advertises:

| Session key | Advertised value |
|---|---|
| `CUSTOMSEARCHINT1` | `nPlayerClass` |
| `CUSTOMSEARCHINT2` | `nPlayerClass` |
| `CUSTOMSEARCHINT3` | `max(nLower, 0)` |
| `CUSTOMSEARCHINT4` | `max(nHigher, 0)` |
| `CUSTOMSEARCHINT5` | `nAreaId` when `nAreaSetting == 0`; otherwise `0xff` |
| `CUSTOMSEARCHINT6` | `nLanguageId` when `nLanguageSetting == 0`; otherwise `0xff` |
| `CUSTOMSEARCHINT7` | `nPrevBattleResult` |
| `EXCUSTOMSEARCHINT3` | `nQualityOfService` |
| `RANKMATCH_NEAR_CLASS` | `nPlayerClass` |
| `SEARCHKEYWORDS` | text form of the incoming `FName` session name |
| `g_OnlineSessionPresenceFlagKey` | presence marker |

The duplicate `nPlayerClass` keys are intentional: the search path compares
the advertised class against the local lower/higher range in two directions.

### Ranked search

`FindLuxorRankSession` always inserts presence, rank-window, near-class, and
keyword criteria:

| Query key | Query value | Comparison mode |
|---|---|---:|
| `PRESENCESEARCH` | `true` | `0` |
| `CUSTOMSEARCHINT1` | `max(nLower, 0)` | `3` |
| `CUSTOMSEARCHINT2` | `max(nHigher, 0)` | `5` |
| `CUSTOMSEARCHINT3` | `nPlayerClass` | `5` |
| `CUSTOMSEARCHINT4` | `nPlayerClass` | `3` |
| `RANKMATCH_NEAR_CLASS` | `nPlayerClass` | `6` |
| `SEARCHKEYWORDS` | text form of the incoming `FName` session name | `0` |

Using UE4.17's `EOnlineComparisonOp` ordering, modes `3`, `5`, and `6` are
`GreaterThanEquals`, `LessThanEquals`, and `Near`. In practical terms, the
ranked query checks both sides of the rank window: "their rank is inside my
allowed range" and "my rank is inside their advertised range."

Area/language filters mirror the player-match path:

| Query key | Inserted when | Query value |
|---|---|---|
| `CUSTOMSEARCHINT5` | `nAreaSetting == 0` | exact `nAreaId` |
| `CUSTOMSEARCHINT5` | `nAreaSetting == 1` | sentinel `0xff` |
| `CUSTOMSEARCHINT6` | `nLanguageSetting == 0` | exact `nLanguageId` |
| `CUSTOMSEARCHINT6` | `nLanguageSetting == 1` | sentinel `0xff` |

The previous-result filter is ranked-only:

| Query key | Inserted when | Query value |
|---|---|---|
| `CUSTOMSEARCHINT7` | `nPrevBattleResult != 0` | `nPrevBattleResult` |

The debug text labels this field `IsPreBattleWon` and prints `Ignore` when the
value is zero, `Equals` otherwise. That matches the query behavior exactly:
zero means do not filter on previous result; nonzero means exact-match
`CUSTOMSEARCHINT7`.

### Previous-result producer

The native create/find helpers consume `nPrevBattleResult`; they do not compute
it. The live producer found so far is the cooked Blueprint function
`BP_LuxFightRequest.CreateMatchSetting`:

| Bytecode offset in `CreateMatchSetting` export | Recovered operation |
|---:|---|
| `0x02f0` | `CallFunc_GetWinningStreak_ReturnValue = GetWinningStreak(CallFunc_GetLocalPlayerProfile_outData, StyleId)` |
| `0x0318` | `CallFunc_Less_IntInt_ReturnValue2 = RetryCount < 1` |
| `0x032e` | `CallFunc_NotEqual_IntInt_ReturnValue = CallFunc_GetWinningStreak_ReturnValue != 0` |
| `0x0373` | `Temp_bool_Variable2 = IsSessionCreater ? true : (RetryCount < 1)` |
| `0x053a` | `PrevBattleResult = Temp_bool_Variable2 ? ((GetWinningStreak != 0) ? 1 : 2) : 0` |

So the caller-side rules are:

| Situation | `PrevBattleResult` sent to native helper |
|---|---|
| Creating a ranked ticket, winning streak nonzero | `1` |
| Creating a ranked ticket, winning streak zero | `2` |
| First ranked find attempt, winning streak nonzero | `1` |
| First ranked find attempt, winning streak zero | `2` |
| Later ranked find retry (`RetryCount >= 1`) | `0` |

The result-history backing store is profile/style data, not session identity.
`ResetLuxorMatchDataRecentBattleResult @ 0x142e1d8c0` resets the selected
player's current-style history by tail-calling
`ResetProfileStyleHistoryFlags @ 0x142dcc460`, which clears
`FLuxProfileStyleRankEntry.dwHistoryFlags`. During match-result updates,
`AdvanceProfileStyleHistoryCounters @ 0x142dcb750` shifts the history window,
`IncrementProfileStyleWinStreak @ 0x142dce7f0` sets bit 0 for a win, and
`ClearProfileStyleCurrentStreak @ 0x142dcb670` clears bit 0 for a non-win.

The important modding conclusion: `PrevBattleResult` can initially separate
winner/winning-streak searches from zero-streak/not-winning searches, but it
cannot directly stop a repeat opponent. It contains no Steam ID, no
`FUniqueNetId`, no session id, and no previous-opponent cache. Once the finder
retries with `PrevBattleResult == 0`, the native ranked search ignores the
previous-result bucket entirely.

## Session search object

Both find helpers call `CreatePlayerMatchSessionSearch @ 0x142e18e20`. Despite
the name, the helper is shared by player and ranked search.

The recovered partial `FOnlineSessionSearch` layout:

| Offset | Field | Meaning |
|-------:|---|---|
| `+0x08` | `pSearchResults` | Backing storage for returned session-result records. |
| `+0x10` | `nSearchResultCount` | Number of returned result records. |
| `+0x14` | `nSearchResultCapacity` | Capacity of the result storage. |
| `+0x1c` | `nMaxSearchResults` | Set from the `Find*Session` `nMaxResults` argument. |
| `+0x20` | `pQuerySettings` | Embedded UE search-setting map receiving the keys above. |
| `+0x78` | `fLanQuery` | Set from the `Find*Session` LAN flag. |
| `+0x84` | float `10.0` | Stock search tuning field; likely the UE ping bucket size. |

The helper also seeds `EXCUSTOMSEARCHINT4` by calling
`ComputePlayerMatchSearchInt4 @ 0x142e190c0` with the session name and
tournament flag. That means tournament/session-name state exists on the search
object before the caller adds the visible filters.

### Find-session result handoff

`HandleLuxorFindSessionResult @ 0x142e1b970` is shared by player-match and
ranked search. When the online subsystem reports success, it reads the current
search object's result storage and appends each result pointer to a temporary
array:

| Source | Meaning |
|---|---|
| `FOnlineSessionSearch+0x08` | First returned result record. |
| `FOnlineSessionSearch+0x10` | Result count. |
| result stride `0xc8` | Size of each native search-result record in this build. |

The function then walks `ULuxorSessionHubPartial+0x120/+0x128`, skips invalid
callback objects, and calls `InvokeFindSessionCallback @ 0x142e1ef40` with the
same result array. There is no per-result predicate in this native handoff:
no rank re-check, no Steam ID comparison, no recent-opponent cache, and no
`IsSameMatch` call. Any post-query choice between candidates would have to
happen in the reflected callback receiver.

## Match-data fields adjacent to rematch flow

`ULuxorMatchData` is the post-match metadata object used by replay, leaderboard,
and UI flows. The relevant recovered fields are:

| Offset | Type | Field |
|-------:|---|---|
| `+0x30` | `int` | `nBattleCountMax` |
| `+0x40` | `int[2]` | `pBattleCounts` |
| `+0x58` | `bool` | `fIsUniqueCharacter` |
| `+0x59` | `bool` | `fIsActiveUserCached` |
| `+0x60` | `FStringFwd` | `stageCode` |
| `+0x70` | `FLuxorBlueprintUserProfileData[2]` | `pPlayerProfiles` |
| `+0x2f0` | `int` | `nRematchType` |

The native accessors are useful hook points for UI/state tracing:

| Function | Address | Role |
|---|---:|---|
| `GetLuxorMatchDataRematchType` | `0x142e19370` | Reads `ULuxorMatchData+0x2f0`. |
| `SetLuxorMatchDataRematchType` | `0x142e1d9e0` | Writes `ULuxorMatchData+0x2f0`. |
| `DispatchLuxorMatchDataGetRematchType` | `0x142e490f0` | Reflected getter dispatcher. |
| `DispatchLuxorMatchDataSetRematchType` | `0x142e4c410` | Reflected setter dispatcher. |
| `GetLuxorMatchDataBattleCountMax` | `0x140507b40` | Reads `ULuxorMatchData+0x30`. |
| `SetLuxorMatchDataBattleCountMax` | `0x142e1d900` | Writes `ULuxorMatchData+0x30`. |

These fields explain post-match rematch UI state and replay metadata. They do
not alter the `FindLuxorPlayerSession` or `FindLuxorRankSession` query unless a
higher-level caller copies one of their values into the session setting structs
before calling the helper.

## Modding implications

- To broaden player-room search, leave optional player filters as `0` and use
  `nAreaSetting == 1` / `nLanguageSetting == 1` for the all-region/all-language
  sentinel.
- To disable the ranked previous-result filter, make
  `FLuxorRankMatchSessionSetting.nPrevBattleResult` zero before
  `FindLuxorRankSession`.
- To intentionally require the previous-result bucket, use nonzero
  `nPrevBattleResult`: `1` for the nonzero winning-streak bucket, `2` for the
  zero-streak/not-winning bucket. Create always advertises it and find only
  searches it when nonzero.
- Stock `BP_LuxFightRequest.CreateMatchSetting` relaxes the finder-side bucket
  after the first retry by sending `0`. Patch that caller if you want the
  bucket to remain strict across retries.
- `SEARCHKEYWORDS` is a hard join between create and find. If a mod changes
  session names, change both sides together.
- Do not use `ULuxorMatchData.nRematchType` as a matchmaking filter unless you
  also patch the caller that builds `FLuxorRankMatchSessionSetting` or
  `FLuxorPlayerMatchSessionSetting`; the find helpers never read it.

## Code references

| Symbol | Address | Role |
|---|---:|---|
| `CreateLuxorPlayerSession` | `0x142e14bd0` | Advertises player-room metadata. |
| `FindLuxorPlayerSession` | `0x142e17580` | Builds player-room query settings and starts `FindSessions`. |
| `CreateLuxorRankSession` | `0x142e15850` | Advertises ranked metadata, rank bounds, QoS, and previous result. |
| `FindLuxorRankSession` | `0x142e18030` | Builds ranked query settings and starts `FindSessions`. |
| `CreatePlayerMatchSessionSearch` | `0x142e18e20` | Allocates the shared search object and seeds `EXCUSTOMSEARCHINT4`. |
| `HandleLuxorFindSessionResult` | `0x142e1b970` | Copies all returned search results into the callback array; no native candidate filtering. |
| `InvokeFindSessionCallback` | `0x142e1ef40` | Marshals the result array to the reflected callback object via `ProcessEvent`. |
| `InitializePlayerMatchSessionSettings` | `0x142e18ef0` | Initializes common advertised session settings. |
| `ComputePlayerMatchSearchInt4` | `0x142e190c0` | Computes the `EXCUSTOMSEARCHINT4` session/search value. |
| `GetLuxorRankMatchSessionSettingStruct` | `0x142e46e30` | Registers the reflected ranked setting struct; no opponent identity field. |
| `GetLuxorBlueprintFindSessionResultStruct` | `0x142e44740` | Registers the 8-byte Blueprint result wrapper used by find-session callbacks. |
| `GetOnlineSessionInterfaceShared` | `0x142ea0470` | Shared UE OnlineSession interface resolver used by create/find. |
| `ResetLuxorMatchDataRecentBattleResult` | `0x142e1d8c0` | Clears the selected player/style recent-result history used by ranked previous-result bucket construction. |
| `ResetProfileStyleHistoryFlags` | `0x142dcc460` | Clears `FLuxProfileStyleRankEntry.dwHistoryFlags`. |
| `AdvanceProfileStyleHistoryCounters` | `0x142dcb750` | Shifts the per-style result-history window before the latest result bit is applied. |
| `IncrementProfileStyleWinStreak` | `0x142dce7f0` | Sets `dwHistoryFlags` bit 0 and increments current streak on a win. |
| `ClearProfileStyleCurrentStreak` | `0x142dcb670` | Clears `dwHistoryFlags` bit 0 and clears/restores current streak state on a non-win. |
| `CheckRankedMatchWinningFromProfile` | `0x14050f470` | Checks the profile-writer ranked-winning state for a style id. |
| `CheckRankedMatchWinningInBattle` | `0x14050f540` | Reads active `ULuxorMatchData` winning streak state for the reflected ranked-winning predicate. |
