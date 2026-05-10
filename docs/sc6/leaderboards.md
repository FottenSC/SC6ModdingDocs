# Leaderboards & Online Ranking

How SC6 stores character usage stats, ranked-match scores, and what an
external API client can read without touching the game binary.

All addresses are absolute (image base `0x140000000`).

## TL;DR — yes, you can read this from outside the game

SC6's character usage / rank data lives in **Steam Leaderboards**. They are
publicly readable via the **Steam Web API** without installing the game,
patching anything, or reverse-engineering BNED's backend.

| What you want | Where to get it |
|---|---|
| Character usage rates | Steam Leaderboard `Characterboard` (App ID 544750) |
| Ranked-match scores per region | `RankmatchWorld` / `RankmatchAsia` / `RankmatchAmerica` / `RankmatchEurope` / `RankmatchOther` |
| Per-entry data: rank, score, persona, region, character style | Standard Steam leaderboard entry + 16 metadata columns |

The other backend SC6 talks to (`cosmos.channel.or.jp`, BANDAI NAMCO's
"Cosmos Channel" / CeBank service) is **outgoing-only** — it receives KPI /
match-result telemetry from clients but does not serve ranking data back to
them. Reading it would require valid Steam encrypted-app-ticket auth and
isn't useful for a third-party client anyway.

## Two backends, one read path

### 1. Steam Leaderboards (the read source)

The in-game ranking UI calls Blueprint UFunction `RequestReadLeaderboards`
which is a thin wrapper over UE4's `IOnlineLeaderboards::ReadLeaderboards`,
which on the Steam build maps to `ISteamUserStats::DownloadLeaderboardEntries`.

```text
ULuxRankingMenu  (BP)
  └─> RequestReadLeaderboards(LeaderboardName, Index, Range)
       └─> FOnlineLeaderboardsSteam::ReadLeaderboards
            └─> ISteamUserStats::DownloadLeaderboardEntries  (Steam SDK)
                 └─> Steam servers
```

The native impl registers via
`UFunction_RequestReadLeaderboards_Register @ 0x140ab3f30`. Each entry's
metadata columns are added by
`FOnlineLeaderboardRead_Init_AddAllSteamColumns @ 0x140579600` (16 column
FNames), then the response is reshaped into the UI's `rankingData` array by
`LuxRanking_BuildPayload_FromSteamLeaderboardRead @ 0x1405a70e0`.

### 2. BNED Cosmos Channel (write-only telemetry)

`https://cosmos.channel.or.jp/<service-id>/api/<endpoint>` — Bandai Namco's
internal backend. Used for ranked-match KPI submission, sign-in/sign-up
flows, mode-change tracking. Not a source for character-usage data.

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
ticket — and there's no payoff because everything visible to players is
also on the Steam leaderboards.

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

The names are passed verbatim to Steam — `IOnlineLeaderboardsSteam` doesn't
do any munging beyond what `DownloadLeaderboardEntries` requires (Steam
internally hashes the name to a numeric leaderboard ID).

## Per-entry data

Every leaderboard entry has a Steam-side `score` (the sort key) and 16
**user-data columns** the game writes alongside. The native code populates
the column list at `FOnlineLeaderboardRead_Init_AddAllSteamColumns @ 0x140579600`.

Once the read completes,
`LuxRanking_BuildPayload_FromSteamLeaderboardRead @ 0x1405a70e0`
reshapes each entry into this shape for the UI:

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

For the Steam Web API XML response, the `<details>` field is a base64-encoded
binary blob containing the same column data. Decoding it is straightforward
once you know the column names — the column FNames are interned at
`DAT_144149{4d0,4d8,4e0,4e8,4f0,4f8,500,508,510,518,520,528,530,538,540,548}`
(16 columns). A live capture or the strings `value`, `lang`, `style`,
`rank`, `point`, `Score` near `0x1432d8980..0x1432d8e20` matches exactly
what the UI expects.

## Character style IDs

The `styleIcon` field is `%03d` of the character style enum (`ELuxFightStyle`).
The 31-style enum lists every base + DLC fighter — relevant entries:

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

## Building an external client

Recommended approach for an analytics dashboard or third-party tracker:

1. **Get a Steam Web API key** from `https://steamcommunity.com/dev/apikey`.
2. **List all SC6 leaderboards once** (cache the IDs):
   ```bash
   curl "https://partner.steam-api.com/ISteamUserStats/GetLeaderboardsForGame/v2/?key=KEY&appid=544750"
   ```
3. **Poll the leaderboards you care about** at whatever cadence you need.
   Steam rate-limits to roughly one request per second per IP for the public
   community endpoint, much higher for the authenticated Web API.
4. **Decode the per-entry `<details>` base64 blob** to get the 16 metadata
   columns. The column order is the order in
   `FOnlineLeaderboardRead_Init_AddAllSteamColumns`; sample a few real
   entries to nail down the exact column types (most are int32 or short
   string).

Don't bother with the Cosmos Channel backend — it's pure outgoing telemetry
and the data you'd recover from it is the same data Steam already exposes.

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

The score parameter is a **raw signed `int32`** carried from the BP `StatValue`
all the way to Steam. There is **no signing, no salt, no server-side
validation, no rate-limit, and no SC6-side anti-tamper.**
Steam authenticates the upload only by the local user's Steam ID — the score
value itself is whatever the client sends.

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

The choice between **`KeepBest`** (Steam keeps the higher of old/new) and
**`ForceUpdate`** (overwrite even if lower) is per-call. SC6 normally uses
`KeepBest`, which is why a cheated max-score sticks: legitimate matches
afterward upload smaller numbers and Steam discards them.

### What the cheat looks like

Anyone with a UE4SS Lua mod can dispatch the UFunction directly:

```lua
local PC = UEHelpers.GetPlayerController()
local KSL = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
KSL:WriteLeaderboardInteger(PC, FName("RankmatchWorld"), 999999999)
```

That's the whole exploit — one BP UFunction call. There is nothing on the
client side to detect, validate, or undo it.

## Can you fix the cheater's score?

**Short answer: no, not from a client mod.** Steam's permission model is
strict — only the user who owns an entry can upload to it via the
authenticated session. The Steam Web API has no public write endpoint for
leaderboard entries; the `UploadLeaderboardEntry/v1/` and
`SetUserStatsForGame/v1/` endpoints both require a **publisher key** that
only Bandai Namco and Project Soul have.

### What CAN be done

| Path | Who can do it | Effect |
|---|---|---|
| **Report to Bandai Namco** | anyone | Publisher uses the Steamworks dashboard's leaderboard moderation tools to delete the cheated entry. |
| **Report to Steam** | anyone | Account-level moderation for egregious cheating. |
| **Filter cheated entries in a 3rd-party tracker** | anyone with a Steam Web API key | Hide entries above a sensible cap when displaying the leaderboard externally. The score is a raw `int32`; values above what's physically achievable from match math are provably fake. |
| **Cosmetic UI mod** | local modder | Hook `RequestReadLeaderboards`'s response handler (`LuxRanking_BuildPayload_FromSteamLeaderboardRead @ 0x1405a70e0`) and drop entries above your filter threshold. Only affects the local view. |

### What CANNOT be done

- Write to another player's leaderboard entry from a client mod. Steam
  blocks that at the SDK level — `UploadLeaderboardScore` always uses the
  caller's authenticated Steam ID.
- "Force-overwrite" the cheater by playing them in ranked. SC6 uses
  `KeepBest`, so even if the cheater eats a loss their existing maximum is
  preserved.
- Patch the binary to fix it. The vulnerability is on the server side
  (Bandai Namco never enforced score caps when accepting uploads). No
  amount of client patching can retract a score that's already on Steam.

### "Can I lose to them and overflow their points to negative?" — no

A common idea is: lose enough matches to the cheater that their gain
arithmetic overflows past `INT32_MAX`, wraps to `INT32_MIN`, and gets
written back as a negative number that displays at the bottom of the
leaderboard. **It does not work.** Five independent reasons:

1. **The winner's client computes their own delta.** Score upload is
   strictly client-authoritative. Whatever you do on your end has zero
   influence on what value the opponent's client decides to upload — the
   loser's client doesn't even talk to Steam about the winner's score.
2. **The Impl clamps negatives to zero.** `WritePlayerPoint` (the function
   that hands the value to the Steam interface) explicitly does
   `iVar5 = max(0, playerPoint)`. So even if a cheater's modified gain math
   produced a wrap-around negative, this clamp would write `0` — useful for
   them, not "rolling back" anywhere recoverable.
3. **The calc has no opponent-controlled inputs that can grow without
   bound.** The disparity multiplier is bounded by SC6's rank-curve table;
   the loser's rank only affects the *winner's* gain (and only by a small
   factor). You can't feed numbers large enough to overflow even at peak
   bonus.
4. **The cheater's client is fully under their control.** A serious
   cheater isn't running stock `WritePlayerPoint`. They've either replaced
   the calc, hooked the Impl, or just don't queue ranked matches at all.
   Whatever values you trick *stock* code into producing, theirs ignores.
5. **Steam upload is bound to the caller's Steam ID.** Even if every other
   step worked, the upload would write to *your* account, not theirs.

The clamp is documented at
[`ULuxPlayerProfileWriter_WritePlayerPoint_Impl @ 0x140528bd0`](../sc6/leaderboards.md#code-references).
It's the protective mechanism that makes overflow rollback infeasible
even in scenarios where the calc could be coerced into producing a
negative.

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
- A back-of-envelope max — e.g. "max-rank players have ~15,000 points; this
  account shows 999,999,999."
- A note that the upload path is `WriteLeaderboardInteger` with no signing,
  so any modder can do this trivially. (Bandai Namco can patch this by
  switching to authenticated-server score uploads, but that's a server-side
  fix — won't happen from a community mod.)

## Replay archival

Public-shared replays are stored using **Steam UGC** (User-Generated Content)
+ a regular **Steam Leaderboard** entry that holds a `UGCHandle_t` reference
to the file. Both halves are publicly readable from outside the game — no
install needed.

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

**2. Page through entries** — leaderboards cap at ~5,000 entries per request,
so loop with `rangestart` / `rangeend`:

```bash
for offset in 1 5001 10001 15001; do
  end=$((offset + 5000 - 1))
  curl "https://steamcommunity.com/stats/544750/leaderboards/<id>?xml=1&start=${offset}&end=${end}" \
    > replay_entries_${offset}.xml
done
```

The XML format gives you `<entry>` blocks with `<steamid>`, `<score>`,
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

**5. Cross-reference with leaderboard metadata** — keep the `<details>` blob
alongside each download. Decoding the columns gives you the players' names,
character IDs, ranks, region, and date without having to parse the binary
file.

### Replay file format (high-level)

The binary `inDataArray` payload is SC6's deterministic match recording.
Format outline (verified at the SC6 binary level):

| Section | Notes |
|---|---|
| Header | `REPLAY` magic + `REPLAYVersion` u32 (one of the leaderboard column names) |
| `ULuxorMatchData` blob | The full 0x300-byte match metadata struct serialized |
| Match settings | Stage code (e.g. `STG006`), round count, time, BGM, etc. |
| RNG seed | The host-broadcast seed (sets the deterministic LCG; `g_scbattle_StageInfo_RngSeed @ 0x144844010`) |
| Per-player config | Character IDs, weapon, customization data |
| Per-frame input log | The deterministic input stream that, replayed against the same engine version, reproduces the match exactly |

The replay is rollback-deterministic — if you have the same game build, the
file plays back the entire match with no other state. SC6's anomaly stages
are signalled in the `MatchData` so the right ring/wall config is loaded.

### Practical considerations

- **Rate limits**: Steam community XML allows ~1 req/sec per IP without
  an API key; the authenticated Web API allows much higher. For a full
  archive of tens of thousands of replays, run multi-threaded with the
  Web API key and back off on 429.
- **UGC retention**: Steam keeps UGC files indefinitely as long as the app
  exists, but BNED could request mass deletion. Archive sooner rather than
  later if you care about historical data.
- **Player privacy**: Replay metadata includes Steam IDs and persona names.
  Hash or anonymize before publishing if you redistribute.
- **Storage size**: A typical SC6 replay is ~200-500 KB compressed. Across
  the lifetime of the game with `NewReplayBoard` entries in the hundreds
  of thousands, expect tens of GB at full archive.
- **Region drift**: Some entries' UGC handles 404 (deleted by the user via
  `Unregister` or by Steam moderation). Skip-and-continue rather than
  retry.

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
| `LuxRanking_BuildPayload_FromSteamLeaderboardRead` | `0x1405a70e0` | Steam → UI payload transform — **hook to filter cheated entries from the local UI.** |
| `LuxRankedMatch_BuildKpiPayload_PostMatch` | `0x1405a8840` | Outgoing KPI payload (BNED, not Steam) |
| `CosmosChannel_BuildGetEnvRequest` | `0x14301b850` | BNED bootstrap |
| `CosmosChannel_DispatchApiRequest_ServiceId024803` | `0x1404dd310` | BNED endpoint dispatcher |
| `ULuxCeBankManager_StaticClass` | `0x1409a59d0` | BNED client UClass |
| `g_str_CosmosChannel_GetEnvUrl` | `0x143db97a0` | `https://cosmos.channel.or.jp/000000/api/sys/get_env` |
| Update-task vtable | `0x143ba9600` | `FOnlineAsyncTaskSteamUpdateLeaderboard` vtable |
