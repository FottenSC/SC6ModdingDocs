# Leaderboards & Online Ranking

How SC6 stores character usage stats, ranked-match scores, and what an
external API client can read without touching the game binary.

All addresses are absolute (image base `0x140000000`).

## TL;DR — yes, you can read this from outside the game

SC6's character-usage and rank data lives in **Steam Leaderboards**, which are
publicly readable via the **Steam Web API** — no game install, no patching, and
no reverse-engineering of BNED's backend required.

| What you want | Where to get it |
|---|---|
| Character usage rates | Steam Leaderboard `Characterboard` (App ID 544750) |
| Ranked-match scores per region | `RankmatchWorld` / `RankmatchAsia` / `RankmatchAmerica` / `RankmatchEurope` / `RankmatchOther` |
| Per-entry data: rank, score, persona, region, character style | Standard Steam leaderboard entry + 16 metadata columns |

The other backend SC6 talks to (`cosmos.channel.or.jp`, Bandai Namco's
"Cosmos Channel" / CeBank service) is **outgoing-only**: it receives KPI and
match-result telemetry from clients but never serves ranking data back to
them. Reading it would require valid Steam encrypted-app-ticket auth, and it
holds nothing a third-party client wants anyway.

## Two backends, one read path

### 1. Steam Leaderboards (the read source)

The in-game ranking UI calls the Blueprint UFunction `RequestReadLeaderboards`,
a thin wrapper over UE4's `IOnlineLeaderboards::ReadLeaderboards`. On the Steam
build that maps to `ISteamUserStats::DownloadLeaderboardEntries`.

```text
ULuxRankingMenu  (BP)
  └─> RequestReadLeaderboards(LeaderboardName, Index, Range)
       └─> FOnlineLeaderboardsSteam::ReadLeaderboards
            └─> ISteamUserStats::DownloadLeaderboardEntries  (Steam SDK)
                 └─> Steam servers
```

The native implementation registers via
`UFunction_RequestReadLeaderboards_Register @ 0x140ab3f30`. Each entry's 16
metadata-column FNames are added by
`FOnlineLeaderboardRead_Init_AddAllSteamColumns @ 0x140579600`, and the
response is then reshaped into the UI's `rankingData` array by
`LuxRanking_BuildPayload_FromSteamLeaderboardRead @ 0x1405a70e0`.

### 2. BNED Cosmos Channel (write-only telemetry)

`https://cosmos.channel.or.jp/<service-id>/api/<endpoint>` — Bandai Namco's
internal backend. It handles ranked-match KPI submission, sign-in/sign-up
flows, and mode-change tracking. It is not a source for character-usage data.

| Field | Value |
|---|---|
| Bootstrap URL | `https://cosmos.channel.or.jp/000000/api/sys/get_env` |
| Service ID | `024803` (substituted into endpoint URLs after bootstrap) |
| HTTP method | `POST` |
| Payload format | **MessagePack** (`Content-Type: application/x-msgpack`) |
| Auth | Steam encrypted-app-ticket exchange |

Code references:
- `CosmosChannel_BuildGetEnvRequest @ 0x14301b850` — bootstrap call
- `CosmosChannel_DispatchApiRequest_ServiceId024803 @ 0x1404dd310` — generic
  endpoint dispatcher (replaces `000000` with `024803` in URL)
- `LuxRankedMatch_BuildKpiPayload_PostMatch @ 0x1405a8840` — outgoing
  ranked-match KPI payload constructor
- `ULuxCeBankManager` — the UE4 manager class (size `0x500`,
  `Z_Construct @ 0x1409a59d0`)
- Error enum: `ELuxCeBankRequestErrorType` —
  `NO_ERROR / PLATFORM_ID_ERROR / GET_ENV_ERROR / SIGN_IN_ERROR / SIGN_UP_ERROR / XB1_GET_TOKEN_ERROR / ERROR`

A third-party client **cannot** read this backend without spoofing a Steam
ticket — and there is no payoff, since everything visible to players is also
on the Steam leaderboards.

## The Steam leaderboards

Steam App ID for SoulCalibur VI: **`544750`**.

### Public list endpoint (no API key)

```text
https://steamcommunity.com/stats/544750/leaderboards/?xml=1
```

Returns XML with every leaderboard's id, display name, sort method, and
entry count.

### Public read endpoint (no API key)

```text
https://steamcommunity.com/stats/544750/leaderboards/<id>?xml=1&start=1&end=100
```

Returns top-N entries with `<steamid>`, `<score>`, `<rank>`, `<ugcid>`, and
the per-entry `<details>` blob (base64-encoded — the metadata column data).

### Authenticated endpoint (Steam Web API key)

```text
https://partner.steam-api.com/ISteamUserStats/GetLeaderboardsForGame/v2/
  ?key=<KEY>&appid=544750
```

```text
https://partner.steam-api.com/ISteamUserStats/GetLeaderboardEntries/v1/
  ?key=<KEY>&appid=544750&leaderboardid=<id>&rangestart=1&rangeend=100
```

### Known leaderboard names

| Name | What it is |
|---|---|
| `Characterboard` | Character usage / pick rate stats — the leaderboard most useful for analytics dashboards |
| `NewReplayBoard` | Public replay listing — each entry's `<ugcid>` resolves to a downloadable replay file (see [Replay Archival](#replay-archival)) |
| `RankmatchWorld` | Ranked-match scores, global |
| `RankmatchAsia` | Ranked-match scores, Asia region |
| `RankmatchAmerica` | Ranked-match scores, Americas region |
| `RankmatchEurope` | Ranked-match scores, Europe region |
| `RankmatchOther` | Ranked-match scores, everything else |

The names are passed verbatim to Steam; `IOnlineLeaderboardsSteam` does no
munging beyond what `DownloadLeaderboardEntries` requires (Steam internally
hashes the name to a numeric leaderboard ID).

## Per-entry data

Every leaderboard entry has a Steam-side `score` (the sort key) plus 16
**user-data columns** the game writes alongside it. The native code populates
the column list at `FOnlineLeaderboardRead_Init_AddAllSteamColumns @ 0x140579600`.

Once the read completes,
`LuxRanking_BuildPayload_FromSteamLeaderboardRead @ 0x1405a70e0`
reshapes each entry into the following form for the UI:

```jsonc
{
  "rank":      1,                  // ordinal position
  "player":    "Steam persona",    // display name
  "point":     12345,              // rank points
  "areaIcon":  "World",            // region tag
  "styleIcon": "001",              // "%03d" of character style ID
  "rankIcon":  "Rank_S",           // rank tier
  "lang":      "ja",               // entry language
  "value":     "..."               // auxiliary
}
```

In the Steam Web API XML response, the `<details>` field is a base64-encoded
binary blob holding the same column data. Decoding it is straightforward once
you know the column names: the 16 column FNames are interned at
`DAT_144149{4d0,4d8,4e0,4e8,4f0,4f8,500,508,510,518,520,528,530,538,540,548}`.
A live capture — or the strings `value`, `lang`, `style`, `rank`, `point`,
`Score` near `0x1432d8980..0x1432d8e20` — matches exactly what the UI expects.

### Raw details column layout

`LuxUploadReplay_FillLeaderboardColumnsFromMatchData @ 0x1405EFF60` writes the
per-entry detail columns from `ULuxorMatchData`. The important correction is
that `ULuxorMatchData+0x48` is **style id**, not rank id. Rank id and rank
points are derived from the per-player match-data slot using that style id.

| Detail column | Source |
|---|---|
| `LbCol_01_AreaIcon` | `GetLuxorMatchDataAreaIconId(md)` / `md+0x2c` |
| `LbCol_02` | player slot 0 vfunc `+0x38` |
| `LbCol_03` | player slot 1 vfunc `+0x38` |
| `LbCol_04` | `GetLuxorMatchDataStyleId(md, 0)` |
| `LbCol_05` | `GetLuxorMatchDataStyleId(md, 1)` |
| `LbCol_06` | `GetLuxorMatchDataRankId(md, 0)` |
| `LbCol_07` | `GetLuxorMatchDataRankId(md, 1)` |
| `LbCol_08` | player slot 0 vfunc `+0x40` |
| `LbCol_09` | player slot 1 vfunc `+0x40` |
| `LbCol_10` | `GetLuxorMatchDataColumn10Value(md)` / `md+0x34` |
| `LbCol_11..15` | zero |

The read-side UI builder still uses FName lookup, so do not infer raw blob
index order from the lookup order in `LuxRanking_BuildPayload_FromSteamLeaderboardRead`.
Use the write path and `FOnlineLeaderboardRead_Init_AddAllSteamColumns` as the
source of truth.

## Character style IDs

The `styleIcon` field is `%03d` of the character style enum (`ELuxFightStyle`).
The 31-style enum lists every base and DLC fighter; relevant entries:

| ID | Style enum | Character |
|---:|---|---|
| 0x01 | EFS_MITSURUGI | Mitsurugi |
| 0x02 | EFS_MINA | Seong Mi-na |
| 0x03 | EFS_TAKI | Taki |
| 0x04 | EFS_MAXI | Maxi |
| 0x05 | EFS_VOLDO | Voldo |
| 0x06 | EFS_SOPHITIA | Sophitia |
| 0x07 | EFS_SIEG | Siegfried |
| 0x08 | EFS_IVY | Ivy |
| 0x09 | EFS_KILIK | Kilik |
| ... | ... | ... |
| 0x14 | EFS_GERALT | Geralt (DLC) |
| 0x16 | EFS_2B | 2B (DLC) |
| 0x17 | EFS_CASSANDRA | Cassandra (DLC) |
| 0x18 | EFS_AMY | Amy (DLC) |
| 0x19 | EFS_HILDA | Hilda (DLC) |
| 0x1A | EFS_SETSUKA | Setsuka (DLC) |
| 0x1B | EFS_HWANG | Hwang (DLC) |

Full enum listed at `0x1432994e8..0x14329aa18` in the binary.

## Ranking internals

SC6 keeps these as separate concepts:

| Value | Where it comes from | Notes |
|---|---|---|
| `StyleId` | `GetLuxorMatchDataStyleId @ 0x142E1A270` | Direct `int32` at `ULuxorMatchData+0x48 + playerIndex*4`. |
| `RankId` | `GetLuxorMatchDataRankId @ 0x142E192E0` | Calls player-slot vfunc `+0x90`, passing the player's `StyleId`. |
| `RankPoint` | `GetLuxorMatchDataRankPoint @ 0x142E19310` | Calls player-slot vfunc `+0x80`, passing the player's `StyleId`. |

Partial `ULuxorMatchData` layout for rank/leaderboard fields:

| Offset | Type | Meaning |
|-------:|------|---|
| `+0x2c` | `int32` | Area / region icon id. |
| `+0x34` | `int32` | Detail column 10 value; semantic still unknown. |
| `+0x48` | `int32[2]` | Per-player `StyleId` values. |
| `+0x70` | player slot | Player slot 0. |
| `+0x1b0` | player slot | Player slot 1, stride `0x140`. |

### Rank icon lookup

`GetRankIconStringByRankId @ 0x14050AFC0` is a bounds-checked lookup into a
global rank-icon `FString` array initialized by
`InitializeGlobalRankIconStringTable @ 0x1401363F0`:

```c
FString* GetRankIconStringByRankId(int nRankId)
{
    if (0 <= nRankId && nRankId < g_nRankIconStringCount)
        return &g_aRankIconStrings[nRankId];
    return &g_RankIconFallbackString;
}
```

The initializer creates `0x26` entries:

| RankId | Icon | RankId | Icon | RankId | Icon | RankId | Icon |
|---:|---|---:|---|---:|---|---:|---|
| `0` | `B` | `10` | `F1` | `20` | `D1` | `30` | `B1` |
| `1` | `G5` | `11` | `E5` | `21` | `C5` | `31` | `A5` |
| `2` | `G4` | `12` | `E4` | `22` | `C4` | `32` | `A4` |
| `3` | `G3` | `13` | `E3` | `23` | `C3` | `33` | `A3` |
| `4` | `G2` | `14` | `E2` | `24` | `C2` | `34` | `A2` |
| `5` | `G1` | `15` | `E1` | `25` | `C1` | `35` | `A1` |
| `6` | `F5` | `16` | `D5` | `26` | `B5` | `36` | `S2` |
| `7` | `F4` | `17` | `D4` | `27` | `B4` | `37` | `S1` |
| `8` | `F3` | `18` | `D3` | `28` | `B3` |  |  |
| `9` | `F2` | `19` | `D2` | `29` | `B2` |  |  |

`BuildRankingCardPayloadWithRankIconLookup @ 0x1407DAB70` contains a second
fixed icon list under the `RankUpIconS` UI path and formats rank-name text ids
as `ID_DLC7_RANK_NAME_%03d` from the matched icon index plus one. This confirms
that `S2` and `S1` are rank icons, not just unrelated DLC/runtime strings.

`GetAreaIconStringByAreaId @ 0x14050B3B0` is the equivalent area/region-icon
lookup.

### Rank-band disparity scaling

`MapRankIdToRankBand @ 0x14047C620` maps rank ids to a coarse band used by
`LuxMoveSlot_ComputeScaleFromRankDiff_WithLazyInit @ 0x14044FB00`.

Observed explicit map entries:

| Rank IDs | Band |
|---|---:|
| `0x09`, `0x0f`, `0x1e` | `0` |
| `0x02`, `0x05`, `0x10`, `0x1d`, `0x1f` | `2` |
| `0x00`, `0x06`, `0x08`, `0x0a`, `0x0e`, `0x13`, `0x1c`, `0x20`, `0x21`, `0x22` | `3` |
| `0x03`, `0x04`, `0x07`, `0x0b`, `0x0c`, `0x0d`, `0x11`, `0x14`, `0x15` | `4` |

Unmapped rank ids return default band `5`. The explicit map inserts keys `0x00` up
to `0x22` (`34`, `A2`), so `0x23` (`A1`), `0x24` (`S2`), and `0x25` (`S1`) all fall into
that default top bucket.

The disparity scale table is:

```text
index: 0     1     2     3     4     5     6     7     8
scale: 1.10  1.08  1.05  1.03  1.00  0.95  0.90  0.85  0.80
```

The index calculation is:

```c
nScaleIndex = (localRankBand - opponentRankBand) + 4;
```

If the opponent band is default `5`, or if the computed index is out of range,
the function returns `1.0`. That means `A1`, `S2`, and `S1` opponents bypass
the normal disparity multiplier table and get neutral scaling.

When `A1`/`S2`/`S1` is on the **local** side, `localRankBand` is also `5`, so
`nScaleIndex = (5 - opponentRankBand) + 4` can still produce reduced gains
(`0.95` to `0.80`) against some lower-ranked opponents; it never produces a
multiplier above `1.0`.

### S1 / S2 status

`A1`, `S2`, and `S1` are real rank ids in this build:

| Rank | RankId | Evidence |
|---|---:|---|
| `A1` | `35` / `0x23` | `MapRankIdToRankBand @ 0x14047C620` has no explicit entry. |
| `S2` | `36` / `0x24` | `InitializeGlobalRankIconStringTable @ 0x1401363F0` entry 36. |
| `S1` | `37` / `0x25` | `InitializeGlobalRankIconStringTable @ 0x1401363F0` entry 37. |

Special handling is in the rank-band disparity path:

- `MapRankIdToRankBand @ 0x14047C620` omits explicit entries for `0x23`–`0x25`, so all three are mapped as band `5` by default.
- `LuxMoveSlot_ComputeScaleFromRankDiff_WithLazyInit @ 0x14044FB00` treats **opponent** band `5` as neutral and returns `1.0` instead of applying the normal `1.10` through `0.80` scale table.

`WriteMaximumRankConfigRow @ 0x1404AC9D0` writes the misspelled
`maximam_rank` config row (`table id 0x90`). Its caller
`UpdateMaximumRankFromPlayerProfile @ 0x1404ACCD0` reads the max-rank value from
the player-profile object at `+0x18`; the static rank-icon table establishes the
highest displayable id as `37` (`S1`).

## Building an external client

Recommended approach for an analytics dashboard or third-party tracker:

1. **Get a Steam Web API key** from `https://steamcommunity.com/dev/apikey`.
2. **List all SC6 leaderboards once** (cache the IDs):
   ```bash
   curl "https://partner.steam-api.com/ISteamUserStats/GetLeaderboardsForGame/v2/?key=KEY&appid=544750"
   ```
3. **Poll the leaderboards you care about** at whatever cadence you need.
   Steam rate-limits the public community endpoint to roughly one request per
   second per IP; the authenticated Web API allows much more.
4. **Decode the per-entry `<details>` base64 blob** to get the 16 metadata
   columns. The column order matches the order in
   `FOnlineLeaderboardRead_Init_AddAllSteamColumns`; see
   [Raw details column layout](#raw-details-column-layout) for the rank/style
   split.

Don't bother with the Cosmos Channel backend — it is pure outgoing telemetry,
and anything you could recover from it is already exposed by Steam.

## How rank points get *set* (the cheat vector)

Score uploads go through **stock UE4 plumbing** with no SC6-side validation:

```text
Blueprint script
  └─> UKismetSystemLibrary::WriteLeaderboardInteger(
          PlayerController, FName StatName, int32 StatValue) → bool
       └─> IOnlineLeaderboards::WriteLeaderboards(SessionName, Player, WriteObject)
            └─> FOnlineLeaderboardsSteam::WriteLeaderboards
                 └─> enqueue FOnlineAsyncTaskSteamUpdateLeaderboard
                      └─> ISteamUserStats::UploadLeaderboardScore(
                              handle, method, score, columnDetails, count)
```

The score parameter is a **raw signed `int32`** carried straight from the BP
`StatValue` to Steam. There is **no signing, no salt, no server-side
validation, no rate-limit, and no SC6-side anti-tamper.** Steam authenticates
the upload only by the local user's Steam ID — the score value itself is
whatever the client sends.

The async task struct (vtable @ `0x143ba9600`) stores:

| Offset | Field | Notes |
|-------:|---|---|
| `+0x18` | `bIsComplete` | uint8 |
| `+0x19` | `bWasSuccessful` | uint8 |
| `+0x20` | `SteamCallHandle` | `SteamAPICall_t` |
| `+0x30` | `LeaderboardName` | `FString` (e.g. `"RankmatchWorld"`) |
| `+0x40` | **`Score`** | **`int32` — uploaded as-is** |
| `+0x50` | `ColumnUpdates` | metadata column TMap |
| `+0xa8` | `UpdateMethod` | `0`/anything → `KeepBest`, `1` → `ForceUpdate` |

The choice between **`KeepBest`** (Steam keeps the higher of the old and new
values) and **`ForceUpdate`** (overwrite even if lower) is per-call. SC6
normally uses `KeepBest`, which is why a cheated max-score sticks: legitimate
matches afterward upload smaller numbers and Steam discards them.

### What the cheat looks like

Anyone with a UE4SS Lua mod can dispatch the UFunction directly:

```lua
local PC = UEHelpers.GetPlayerController()
local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
KSL:WriteLeaderboardInteger(PC, FName("RankmatchWorld"), 999999999)
```

That is the whole exploit — one BP UFunction call. There is nothing on the
client side to detect, validate, or undo it.

## Can you fix the cheater's score?

**Short answer: no, not from a client mod.** Steam's permission model is
strict — only the user who owns an entry can upload to it through the
authenticated session. The Steam Web API exposes no public write endpoint for
leaderboard entries; the `UploadLeaderboardEntry/v1/` and
`SetUserStatsForGame/v1/` endpoints both require a **publisher key** that only
Bandai Namco and Project Soul have.

### What CAN be done

| Path | Who can do it | Effect |
|---|---|---|
| **Report to Bandai Namco** | anyone | Publisher uses the Steamworks dashboard's leaderboard moderation tools to delete the cheated entry. |
| **Report to Steam** | anyone | Account-level moderation for egregious cheating. |
| **Filter cheated entries in a 3rd-party tracker** | anyone with a Steam Web API key | Hide entries above a sensible cap when displaying the leaderboard externally. The score is a raw `int32`; values above what's physically achievable from match math are provably fake. |
| **Cosmetic UI mod** | local modder | Hook the `RequestReadLeaderboards` response handler (`LuxRanking_BuildPayload_FromSteamLeaderboardRead @ 0x1405a70e0`) and drop entries above your filter threshold. Affects only the local view. |

### What CANNOT be done

- Write to another player's leaderboard entry from a client mod. Steam
  blocks that at the SDK level — `UploadLeaderboardScore` always uses the
  caller's authenticated Steam ID.
- "Force-overwrite" the cheater by playing them in ranked. SC6 uses
  `KeepBest`, so even if the cheater eats a loss, their existing maximum is
  preserved.
- Patch the binary to fix it. The vulnerability is server-side — Bandai
  Namco never enforced score caps when accepting uploads — and no amount of
  client patching can retract a score already on Steam.

### "Can I lose to them and overflow their points to negative?" — no

A common idea: lose enough matches to the cheater that their point-gain
arithmetic overflows past `INT32_MAX`, wraps to `INT32_MIN`, and gets written
back as a negative number that sorts to the bottom of the leaderboard. **It
does not work.** Five independent reasons:

1. **The winner's client computes their own delta.** Score upload is
   strictly client-authoritative. Whatever you do on your end has zero
   influence on what value the opponent's client decides to upload — the
   loser's client doesn't even talk to Steam about the winner's score.
2. **The Impl clamps negatives to zero.** `WritePlayerPoint` — the function
   that hands the value to the Steam interface — explicitly does
   `iVar5 = max(0, playerPoint)`. So even if a cheater's modified gain math
   produced a wrap-around negative, this clamp writes `0` — which helps the
   cheater and rolls nothing back.
3. **The calc has no opponent-controlled inputs that can grow without
   bound.** The disparity multiplier is bounded by SC6's rank-curve table,
   and the loser's rank affects only the *winner's* gain, by a small factor
   at that. You cannot feed in numbers large enough to overflow even at peak
   bonus.
4. **The cheater's client is fully under their control.** A serious cheater
   is not running stock `WritePlayerPoint` — they have either replaced the
   calc, hooked the Impl, or simply never queue ranked matches. Whatever
   values you coax *stock* code into producing, theirs ignores.
5. **Steam upload is bound to the caller's Steam ID.** Even if every other
   step worked, the upload would write to *your* account, not theirs.

The clamp is documented at
[`ULuxPlayerProfileWriter_WritePlayerPoint_Impl @ 0x140528bd0`](../sc6/leaderboards.md#code-references).
It is the safeguard that makes overflow rollback infeasible even in scenarios
where the calc could be coerced into producing a negative.

### Other angles people ask about

| Idea | Why it doesn't work |
|---|---|
| "Spoof the cheater's Steam ID" | Steam SDK signs all upload requests with the local user's session ticket. You can't impersonate another Steam user from a mod. |
| "Crash their game during match-end" | Their client retries; their existing max is unaffected by failed uploads. Also requires you to be matched against them, which is RNG. |
| "Submit `INT32_MIN` via Web API" | The Web API upload endpoints require a publisher key. There's no public write path. |
| "Beat them so hard the system glitches" | The match-end pipeline is well-tested — there's no known crash, race, or state-machine bug to exploit. |
| "Use the post-match KPI submission to BNED" | That's outgoing-only telemetry to `cosmos.channel.or.jp`. It doesn't write to Steam leaderboards. |
| "Find a buffer overflow in the score column write" | The score is a single int32 passed through unchanged; no string copy or length-prefixed buffer is involved. |

### Reporting checklist (if you go that route)

When you contact Bandai Namco or Steam, the useful evidence:

- The cheater's Steam ID (visible in the in-game ranking UI; also the
  `<steamid>` in the public XML feed).
- The leaderboard name (e.g. `RankmatchWorld`) and the impossible score.
- A back-of-the-envelope max — e.g. "max-rank players have ~15,000 points;
  this account shows 999,999,999."
- A note that the upload path is `WriteLeaderboardInteger` with no signing,
  so any modder can do this trivially. (Bandai Namco can patch this by
  switching to authenticated server-side score uploads, but that is a
  server-side fix — it won't come from a community mod.)

## In-match netplay (the per-frame input ring)

How SC6 transports opponent inputs during an online match. **Useful for any
mod that needs to know "are we online right now?" or "should I disable my
feature in online play?"**

### Detection: is this match online?

Three options, listed from most authoritative to coarsest:

| What you can read | Where | Notes |
|---|---|---|
| **Call `ALuxBattleManager_CheckOnlineSessionActive @ 0x1403F2590`** | static | Returns `bool`. Internally calls `GetLocalOnlineSession` and checks the session's role-byte (`vtable[0]() != -1`). 16 in-engine callers use this as the canonical "are we online" gate. |
| Read `uint32` at `FrameInputLog+0x4400` (`dwOnlineActive_at0x4400`) | per-InputLog | Set by `LuxBattleChara_InitPlayerBitmask_FromOnlineSession @ 0x1403FA330` at round init. `0` = offline / spectator (the drain early-exits), `1` = local is PLAYER_SIDE_B, `2` = local is PLAYER_SIDE_A, `3` = hidden lobby. Same field the network drain function uses as its entry guard. |
| Read `bool` at `BM+0x1640` | per-BM | Set by `LuxBattleManager_InitOnlineSession_SetFlag1640 @ 0x1403FB400`, cleared by `LuxOnline_DisconnectAndClearSession @ 0x1403EDD00`. Coarser — only `true` between explicit init/teardown calls. |

If your mod tests online status from Lua via UE4SS, the BP UFunction
`ALuxBattleManager::IsBattleOnline @ 0x1403F1A60` is a world-context-aware
wrapper around `CheckOnlineSessionActive` — it looks up the chara's
WorldContext first, then defers to it.

### Delay-based, no rollback

SC6's online play uses **input-delay netcode**: the simulation stalls when the
peer's input has not arrived. There is **no rollback** (zero `Rollback`-named
functions in the binary) and **no per-frame state hash**. Desync detection is
purely stall-based — `LuxBattleManager_UpdateOnlineFrameSyncCounter_At1638 @ 0x1403FDEC0`
increments `BM+0x1638` when `delta == 0` and commits a desync event to
`BM+0x163C` after 10 consecutive zero-delta frames (~166 ms at 60 Hz).

### Three-channel protocol

Steam P2P / FArchive channel byte:

| Channel | Carries | Handler |
|--------:|---|---|
| **5** | Binary frame input (3 bytes per slot per frame; opcode in header upper nibble) | `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770` |
| **6** | **BattleSync KV** — match handshake by msg-id string | `LuxOnlineBattleSync_OnRecvBattleSync_Dispatcher @ 0x140511CF0` |
| **7** | **UI mirror KV** — settings toggles, fight requests | `LuxOnline_DispatchNetMessage_ByKeyString @ 0x1403E0520` |

Channel-6 msg ids (recognized strings in the recv dispatcher):
`ReadyToConnect`, `RequestProfile`, `ProfileSet`, `GuestProfile`,
`RequestCharacterSet`, `CharacterSet`, `GuestCharacter`, `CharacterComplete`,
`RequestStage`, `Stage`, `GuestAll`, `AllComplete`, `Move`.

Channel-7 keys: `fightRequest`, `modeAndStateInfo`, `keyDisplay`,
`damageIcon`, `damageInfo`.

### Per-frame input chain (channel 5)

```text
Steam P2P recv
  └─> OnlineSubsystem recv callback (unnamed; dispatched by delegate-bind anchor 0x1448B2464)
       └─> LuxDelegate_WeakPtrThunk_F4be0_ByteArg_Wrapper       @ 0x1403EEF30
            └─> LuxDelegate_WeakPtrThunk_CallF4be0_WithByteArg  @ 0x1403EECD0
                 └─> LuxOnline_PushToRingBuffer_WithCriticalSection  @ 0x1403F4BE0
                      ║   (network thread; cap-100 drop-oldest deque at FrameInputLog+0x4480)
                      ║   ── CS handoff at FrameInputLog+0x44A8 ──
                      ▼
                 LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache  @ 0x1403F6770
                      ║   (game thread; writes FrameInputLog+0x3C0 cache)
                      ▼
                 LuxBattleManager_GetCachedRoundValue_ByIndex          @ 0x1403F0720
                      ║   (called from the SimulationLoop catch-up loop, once per active slot per frame)
                      ▼
                 LuxBattleChara_UpdatePlayerInputData_FromRoundCache   @ 0x1403FCD10
                      └─> chara consumes the cached input on the next sim step
```

Senders (local → peer):

| Function | RVA | Notes |
|---|---|---|
| `LuxOnline_SendInputPacket_PerFrame_Opcode0` | `0x1403F84E0` | 3-byte packet per active slot per frame (~180 B/s/peer at 60 Hz) |
| `LuxOnline_SendInputPacket_BatchedRange_Opcode1` | `0x1403F8710` | Variable-length re-send for catch-up after drops |

### The per-slot input cache at `FrameInputLog+0x3C0`

A 16 KB rolling window. Layout = `[2 slots][512 entries][16 B FLuxReplayInputCacheEntry]`.
Indexed by `(dwFrameIndex & 0x1FF) + playerSlot * 0x200`. Filled **only by the
online drain** — offline play and .replay viewing do NOT write here; they feed
inputs through a different chara-side pipeline (see the
[InputLog cache is online-only](../sc6/replay-system.md) note).

When you seek backward by more than 512 frames during replay scrubbing, the
cache entries at the target frame are stale, and `GetCachedRoundValue` returns
0 for any query past the wrap window. The workaround is to restore the cache
region alongside chara state.

### Lobby / matchmaking entry points

These are the BP-callable lobby actions you can hook from UE4SS:

| Function | RVA | What it does |
|---|---|---|
| `LuxMatchLobby_RequestReady` | `0x1405EA160` | Host hits "Ready" — advances BattleSync substate to 1, starts handshake |
| `LuxMatchLobby_CancelReady` | `0x140599D40` | Reverse of RequestReady |
| `LuxMatchLobby_RequestLeave` | `0x1405E7E80` | Opens leave-confirm dialog |
| `LuxMatchLobby_DecideKickTarget` | `0x1405E02F0` | Kick a guest by index |
| `LuxMatchLobby_OpenChatMenu` | `0x1405E5270` | Quick-chat words selection |
| `LuxMatchLobby_OpenTextChat` | `0x1405E5E60` | Free-form text chat input |
| `LuxLobby_DispatchUICommand` | `0x1405E21E0` | Router — wstring-compares the UI command name and calls the matching handler above |
| `LuxBattleChara_OnlineSession_SetUsingMultiplayerFeatures` | `0x140433930` | Tells Steam's `ISteamFriends` rich-presence we're in MP |
| `LuxBattleManager_InitOnlineSession_SetFlag1640` | `0x1403FB400` | Match-start hook: calls `Session->vtable[+0x40]` (InitSession) and sets `BM+0x1640 = 1` |
| `LuxOnline_DisconnectAndClearSession` | `0x1403EDD00` | Match-end hook: calls `Session->vtable[+0x48]` (Disconnect) and clears `BM+0x1640` |

### Steam interface accessors

| Function | RVA | What it returns |
|---|---|---|
| `OnlineSubsystem_GetSubsystem_FromModule` | `0x1403BCFF0` | The `FOnlineSubsystem*` singleton via `FModuleManager` (the "OnlineSubsystem" module). 64 callers. |
| `Steam_InitAllInterfaces` | `0x1404C3DD0` | One-shot bootstrap that fills a 168-byte `SteamContext` struct with 21 `ISteam*` pointers (`SteamClient017` through `STEAMVIDEO_INTERFACE_V001`). |
| `GetLocalOnlineSession` | `0x1403F07A0` | TSharedPtr to the process-wide `FLuxOnlineSession`. 22 callers. |
| `LuxOnline_GetPlayerProfileWriterInterface` | `0x140718540` | `IProfileWriter*` for stat/score uploads (53 callers — most-used profile accessor). |

### `FLuxOnlineSession` vtable (observed slots)

| Slot | Returns | Purpose |
|-----:|---|---|
| `[0x00]` | `char` (`ELuxOnlineSessionRole`) | `-1` = no session, `0` = PLAYER_SIDE_A, `1` = PLAYER_SIDE_B, `2` = SPECTATOR, `3` = hidden lobby |
| `[0x08]` | `char` (`ELuxOnlineSessionState`) | `1`/`4`/`6` are the "alive" states; everything else is "disconnected or not started" |
| `[0x20]` | — | `SendDatagram(buf, channel)` — used by both Send Opcode 0 and Send Opcode 1 |
| `[0x40]` | — | `InitSession()` — handshake start |
| `[0x48]` | — | `Disconnect()` — clean hang-up |

### What doesn't apply

- **No checksums, no rollback, no state hash.** There is nothing on this
  codepath for a mod's "frame hash" or "rollback restore" hook to attach to.
- **The per-frame input cache at `FrameInputLog+0x3C0` is empty during
  offline play and .replay file viewing.** Don't rely on it for offline
  features — during replay viewing it is the chara-side input pipeline
  (`chara+0x3C0..+0x43C0`) that fills.
- **Spectator mode uses channel 6, not channel 5.** A spectator's
  `dwOnlineActive_at0x4400` stays at `0`, so the channel-5 drain early-exits;
  inputs flow through the BattleSync "Move" sub-record instead.

### The 8WAYRUN "1 fake frame" mod is a placebo

The community mod that NOPs six bytes at `0x1403F0751` (the `SUB EBX,[RDI+0x390]`
instruction inside `GetCachedRoundValue_ByIndex`) has **no functional effect**
in any game mode. The instruction subtracts `InputDelay_at0x390` from the cache
index, but that field is permanently 0 in observed builds:

- Its only writer in the binary is `LuxMoveProvider_BaseData_Constructor @ 0x1403DC3FB`,
  which writes 0. Round-init, online-session bind, and the network drain all
  skip `+0x390`. No UI handler exists (no "Frame Delay" / "FrameDelay" strings).
- The CDO default is 0.
- The `vtable[0x658]` gate (`UObject::IsReadyForFinishDestroy` default for the
  `ALuxBattleFrameInputLog` parent; `ALuxBattleFrameInputSync_IsNotInOnlineSyncHandshake @ 0x1403E9610`
  for the online subclass) returns 1 in normal play, so the `SUB` *does* fire —
  it just subtracts 0.
- The "InputDelayFrame" UProperty at `LuxBattleOptionParam+0x00` (registered by
  `FUN_140992DA0`) is a separate training-mode config field and is never
  propagated to `FrameInputLog+0x390`.

**Implication for mods:** don't waste a patch slot on `0x1403F0751`. To
actually shift input timing, work with the live input pipeline — the
per-player ring at `g_LuxBattle_PerPlayerInputRing` and the
`g_LuxBattle_InputRingBaseOffset_PerPlayer` global (the latter is BSS-zero
with no writer, the same dead-code pattern).

## Replay archival

Publicly shared replays are stored as **Steam UGC** (User-Generated Content),
paired with a regular **Steam Leaderboard** entry that holds a `UGCHandle_t`
reference to the file. Both halves are publicly readable from outside the
game, with no install needed.

### Architecture

```text
Player chooses "Register" in the in-game replay menu
   ↓
ULuxUploadReplay::FlushReplayFile(MatchData, inDataArray)        @ UFunction (BP)
   ↓
Steam Cloud FileWrite        ← writes binary replay to per-user namespace
   ↓
ISteamRemoteStorage::FileShare(filename) → UGCHandle_t  (uint64)
   ↓
ISteamUserStats::WriteLeaderboard("NewReplayBoard")
   - score        = match score (or 0 if no scoring)
   - 16 columns   = match metadata (chars, ranks, region, date)
   - UGC handle   = the FileShare handle (gets written as one of the columns)
```

The leaderboard entry's XML response includes a `<ugcid>` field with the
handle. Anyone with a Steam Web API key can resolve it to a download URL.

### Step-by-step archival

**1. Find the leaderboard ID for `NewReplayBoard`** (do this once, cache):

```bash
curl "https://partner.steam-api.com/ISteamUserStats/GetLeaderboardsForGame/v2/?key=KEY&appid=544750" \
  | jq '.response.leaderboards[] | select(.name=="NewReplayBoard")'
```

**2. Page through entries.** Leaderboards cap at ~5,000 entries per request,
so loop with `rangestart` / `rangeend`:

```bash
for offset in 1 5001 10001 15001; do
  end=$((offset + 5000 - 1))
  curl "https://steamcommunity.com/stats/544750/leaderboards/<id>?xml=1&start=${offset}&end=${end}" \
    > replay_entries_${offset}.xml
done
```

The XML response gives you `<entry>` blocks with `<steamid>`, `<score>`,
`<rank>`, `<ugcid>`, and `<details>` (base64 of the 16 metadata columns).

**3. Resolve each UGC handle to a download URL** (Web API key required):

```bash
curl "https://api.steampowered.com/ISteamRemoteStorage/GetUGCFileDetails/v1/?key=KEY&steamid=<entry_steamid>&ugc=<ugc_handle>&appid=544750"
```

Response shape:
```jsonc
{
  "data": {
    "filename": "REPLAY_xxxxxxxx",
    "url": "https://cloud-{n}.steamusercontent.com/ugc/{handle}/.../file",
    "size": 123456
  }
}
```

**4. Download the binary replay file**:

```bash
curl -o "replay_${ugc_handle}.bin" "${url_from_step_3}"
```

**5. Cross-reference with leaderboard metadata.** Keep the `<details>` blob
alongside each download. Decoding the columns yields the players' names,
character IDs, ranks, region, and date without having to parse the binary
file.

### Replay file format (high-level)

The binary `inDataArray` payload is SC6's deterministic match recording.
Format outline, verified at the SC6 binary level:

| Section | Notes |
|---|---|
| Header | `REPLAY` magic + `REPLAYVersion` u32 (one of the leaderboard column names) |
| `ULuxorMatchData` blob | The full 0x300-byte match metadata struct serialized |
| Match settings | Stage code (e.g. `STG006`), round count, time, BGM, etc. |
| RNG seed | The host-broadcast seed (sets the deterministic LCG; `g_scbattle_StageInfo_RngSeed @ 0x144844010`) |
| Per-player config | Character IDs, weapon, customization data |
| Per-frame input log | The deterministic input stream that, replayed against the same engine version, reproduces the match exactly |

The replay is rollback-deterministic: given the same game build, the file
plays back the entire match with no other state required. SC6's anomaly
stages are flagged in the `MatchData` so the correct ring/wall config loads.

### Practical considerations

- **Rate limits**: the Steam community XML endpoint allows ~1 req/sec per IP
  without an API key; the authenticated Web API allows much more. For a full
  archive of tens of thousands of replays, run multi-threaded with the Web
  API key and back off on 429.
- **UGC retention**: Steam keeps UGC files indefinitely as long as the app
  exists, but BNED could request a mass deletion. If you care about
  historical data, archive sooner rather than later.
- **Player privacy**: replay metadata includes Steam IDs and persona names.
  Hash or anonymize them before publishing if you redistribute.
- **Storage size**: a typical SC6 replay is ~200-500 KB compressed. With
  `NewReplayBoard` entries in the hundreds of thousands over the game's
  lifetime, expect tens of GB for a full archive.
- **Dead handles**: some entries' UGC handles 404 — deleted by the user via
  `Unregister` or by Steam moderation. Skip and continue rather than retry.

### Replay code references

| Function / Symbol | RVA | Role |
|---|---|---|
| `ULuxUploadReplay_StaticClass` | `0x1401b34b0` | Class registration (`/Script/LuxorGame.LuxUploadReplay`, size `0x40`) |
| `Z_Construct_UClass_ULuxUploadReplay` | `0x140cc0ef0` | Property/UFunction builder |
| `Z_Construct_UFunction_FlushReplayFile` | `0x140ce14b0` | Defines `FlushReplayFile(MatchData, inDataArray)` |
| `Z_Construct_UFunction_InitalizeReplay` | `0x140ce18b0` | (sic — typo in original: "Initalize") |
| `Z_Construct_UFunction_FinalizeReplay` | `0x140ce1360` | |
| `ULuxorMatchData_StaticClass` | `0x142e1f800` | Class registration (`LuxorMatchData`, size `0x300`, 37 native UFunctions) |
| `ULuxorMatchData_RegisterNativeFunctions` | `0x142e1fd80` | Binds the 37 BP-callable accessors |

## Code references

| Function / Symbol | RVA | Role |
|---|---|---|
| `ULuxPlayerProfileWriter_StaticClass` | `0x140afdf40` | The SC6 subsystem that owns all profile / score writes. Class size `0x40`. |
| `Z_Construct_UFunction_WritePlayerPoint` | `0x140b14d20` | Registers the BP UFunction `WritePlayerPoint(styleId, playerPoint, playerClass)` |
| `execWritePlayerPoint` | `0x140b23880` | UE4 exec trampoline (param-marshalling) for WritePlayerPoint |
| `ULuxPlayerProfileWriter_WritePlayerPoint_Impl` | `0x140528bd0` | **★ The actual rank-point writer.** Clamps `playerPoint = max(0, x)` then queues to the Steam profile-writer interface (vtable `0x78`). Negatives become 0 — overflow rollback to negative is blocked here. |
| `Z_Construct_UFunction_BoostPlayerPoint` | `0x140b136b0` | Registers `BoostPlayerPoint(battleChara, afterRank)` — DLC5 unlock-bonus rank fast-track |
| `execBoostPlayerPoint` / `_Impl` | `0x140b20480` / `0x140500780` | Boost-rank exec + impl |
| `LuxOnline_GetPlayerProfileWriterInterface` | `0x140718540` | Resolves the Steam OSS profile-writer interface used by the Impls |
| `UFunction_WriteLeaderboardInteger_Register` | `0x142e8a2c0` | Stock UE4 BP write UFunction (params: PlayerController, StatName, StatValue, return bool). Lower-level path; SC6 routes through `WritePlayerPoint` instead. |
| `FOnlineAsyncTaskSteamUpdateLeaderboard_Tick` | `0x1429e0b80` | The actual `UploadLeaderboardScore` call site |
| `FOnlineAsyncTaskSteamUpdateLeaderboard_ToString` | `0x1429e45d0` | Debug formatter — `bWasSuccessful: %d Leaderboard: %s Score: %d`. **Hook target if you want to log every score upload locally.** |
| `FOnlineLeaderboardsSteam_FindLeaderboardByName_Locked` | `0x1429c9d10` | Name → handle cache lookup |
| `UFunction_RequestReadLeaderboards_Register` | `0x140ab3f30` | BP read entry point |
| `FOnlineLeaderboardRead_Init_AddAllSteamColumns` | `0x140579600` | Adds the 16 metadata column FNames |
| `LuxUploadReplay_FillLeaderboardColumnsFromMatchData` | `0x1405eff60` | Writes leaderboard detail columns from `ULuxorMatchData`. Confirms `StyleId` columns before rank columns. |
| `GetLuxorMatchDataStyleId` | `0x142e1a270` | Reads `StyleId` from `ULuxorMatchData+0x48 + playerIndex*4`. |
| `GetLuxorMatchDataRankId` | `0x142e192e0` | Calls player-slot vfunc `+0x90` with style id. |
| `GetLuxorMatchDataRankPoint` | `0x142e19310` | Calls player-slot vfunc `+0x80` with style id. |
| `InitializeGlobalRankIconStringTable` | `0x1401363f0` | Initializes the 38-entry rank icon table: `0=B`, `36=S2`, `37=S1`. |
| `GetRankIconStringByRankId` | `0x14050afc0` | Bounds-checked rank-icon string lookup. |
| `BuildRankingCardPayloadWithRankIconLookup` | `0x1407dab70` | Ranking-card UI path that maps rank icons to `ID_DLC7_RANK_NAME_%03d`. |
| `MapRankIdToRankBand` | `0x14047c620` | Converts rank id to coarse rank band for disparity scaling. |
| `LuxMoveSlot_ComputeScaleFromRankDiff_WithLazyInit` | `0x14044fb00` | Rank-band disparity multiplier table. |
| `WriteMaximumRankConfigRow` | `0x1404ac9d0` | Writes the `maximam_rank` config row from the profile max-rank value. |
| `WriteMatchingRankDisparityRow` | `0x1404ae020` | Writes `matching_rank_disparity` rows keyed by mode and rank-point delta. |
| `LuxRanking_BuildPayload_FromSteamLeaderboardRead` | `0x1405a70e0` | Steam → UI payload transform — **hook to filter cheated entries from the local UI.** |
| `LuxRankedMatch_BuildKpiPayload_PostMatch` | `0x1405a8840` | Outgoing KPI payload (BNED, not Steam) |
| `CosmosChannel_BuildGetEnvRequest` | `0x14301b850` | BNED bootstrap |
| `CosmosChannel_DispatchApiRequest_ServiceId024803` | `0x1404dd310` | BNED endpoint dispatcher |
| `ULuxCeBankManager_StaticClass` | `0x1409a59d0` | BNED client UClass |
| `g_str_CosmosChannel_GetEnvUrl` | `0x143db97a0` | `https://cosmos.channel.or.jp/000000/api/sys/get_env` |
| Update-task vtable | `0x143ba9600` | `FOnlineAsyncTaskSteamUpdateLeaderboard` vtable |
