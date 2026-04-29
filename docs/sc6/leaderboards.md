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

## Code references

| Function / Symbol | RVA | Role |
|---|---|---|
| `UFunction_RequestReadLeaderboards_Register` | `0x140ab3f30` | Registers the BP entry point |
| `FOnlineLeaderboardRead_Init_AddAllSteamColumns` | `0x140579600` | Adds the 16 metadata column FNames |
| `LuxRanking_BuildPayload_FromSteamLeaderboardRead` | `0x1405a70e0` | Steam → UI payload transform |
| `LuxRankedMatch_BuildKpiPayload_PostMatch` | `0x1405a8840` | Outgoing KPI payload (BNED, not Steam) |
| `CosmosChannel_BuildGetEnvRequest` | `0x14301b850` | BNED bootstrap |
| `CosmosChannel_DispatchApiRequest_ServiceId024803` | `0x1404dd310` | BNED endpoint dispatcher |
| `ULuxCeBankManager_StaticClass` | `0x1409a59d0` | BNED client UClass |
| `g_str_CosmosChannel_GetEnvUrl` | `0x143db97a0` | `https://cosmos.channel.or.jp/000000/api/sys/get_env` |
| `g_FName_PrimaryAssetType_Map` (unrelated) | `0x144391728` | (stage system) |
