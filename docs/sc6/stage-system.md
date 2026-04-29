# Stage System

How SC6 enumerates, gates, loads and configures stages — and the four pieces
you need to ship a custom map.

All addresses are absolute (image base `0x140000000`).

## At a glance

A stage in SC6 is the sum of four independent pieces:

| Piece | Where it lives | Mutable via |
|---|---|---|
| **Master enum entry** | `g_LuxStage_MasterEnumStringTable @ 0x144149c50` (`TArray<FBattleStageEnumEntry>`, 31 stock entries) | DLL hook into `InitGlobalLuxStageMasterEnumStringTable @ 0x140149720` |
| **Stage info row** | `LuxBattleStageInfoTableRow` UDataTable .uasset, looked up by `FName "StageInfoTable"` | Edit .uasset (UAssetGUI / FModel) |
| **Level .umap** | `/Game/Stage/<code>/Maps/<code>.umap` (resolver: `ResolveStageCodeToAssetPath @ 0x140641840`) | Drop a `_P.pak` into `Content/Paks/~mods/` |
| **Selected stage code** | `LuxDataTable` key `StageSetting.StageCode` set by stage-select UI | Blueprint hook on `ULuxUIBattleLauncher::SetStageCode` |

The four are independent: replacing the .umap alone is enough to reskin a stock
stage. Adding a wholly new stage requires touching the master enum (which is
statically built — needs a DLL hook).

## Key entry points

| Function | RVA | Role |
|---|---|---|
| `InitGlobalLuxStageMasterEnumStringTable` | `0x140149720` | Static initializer that builds the 31 stock master-enum entries. **Hook this to add new stages.** |
| `GetStageCodes_BuildMasterList` | `0x140640890` | Returns master roster minus `_T` anomaly variants. UFunction `ULuxUIGameFlowManager::GetStageCodes`. |
| `GetStageCodesIfAvailable_FilterByDLCChunks` | `0x1406409f0` | Filters by DLC ownership; final pool the random picker draws from. |
| `IsValidStageCodeStr_LookupInMasterEnum` | `0x140647230` | Validation — is this stage code in the table? |
| `ResolveStageCodeToAssetPath` | `0x140641840` | Stage code string → `/Game/Stage/...` asset path. Substring-based DLC routing. |
| `GetStageLocIdByStageCode` | `0x140641680` | Stage code → display loc ID. |
| `ApplyBattleSettingDataTableToBattleManager` | `0x140594eb0` | Match-start consumer. Reads `StageSetting.StageCode`, parses to packed int, fires async stage load. |
| `LuxBattle_CreateStageInfoHandler` | `0x1403c3010` | Allocates the gameplay-side `scbattle::StageInfoHandler`. |

## Master enum table

`g_LuxStage_MasterEnumStringTable` at `0x144149c50` is a `TArray<FBattleStageEnumEntry>`
with 31 stock rows. Count at `0x144149c58`.

```c
struct FBattleStageEnumEntry {  // 32 bytes
    FString DisplayLocId;       // e.g. "ID_CMN_Stag_D_001"
    FString StageCode;          // e.g. "STG001"
};
```

The 31 stock rows include 5 DLC variants gated by chunk availability and 7 `_T`
anomaly variants stripped from the random pool. See
[Random-pool bias](#random-pool-bias) below.

## Stage code → path resolution

`ResolveStageCodeToAssetPath` does **substring matching** on the stage code,
not numeric parsing:

| Stage code contains | Routes to |
|---|---|
| `014` | `/Game/DLC/01/Stage/%s/Maps/%s` (Hilde) |
| `_V` | `/Game/DLC/13/Stage/%s/%s` (DLC13 — note: NO `/Maps/`) |
| `016` or `006_R` | `/Game/DLC/09/Stage/%s/Maps/%s` (Haohmaru) |
| `011_R` or `015` or `015_R` | `/Game/DLC/07/Stage/%s/Maps/%s` (Cassandra) |
| `017` | `/Game/DLC/11/Stage/%s/Maps/%s` (Setsuka) |
| `018` | `/Game/DLC/13/Stage/%s/Maps/%s` (Hwang) |
| anything else | `/Game/Stage/%s/Maps/%s` (base game) |

!!! warning "Custom stage codes — avoid these substrings"
    Custom codes that contain `014`, `_V`, `016`, `006_R`, `011_R`, `015`,
    `017`, or `018` will be misrouted to a DLC pak path. Safe choices:
    `STG999`, `STG_MOD_A`, `STGCUSTOM01`, `STG042`.

## DLC availability gate

`GetStageCodesIfAvailable_FilterByDLCChunks @ 0x1406409f0` runs the master list
through DLC chunk ownership checks. A stage is dropped if it contains:

| Substring | Required runtime condition |
|---|---|
| `014` | `RUNTIME_CHAR_060_AVAILABLE` (Hilde) |
| `_V` | `RUNTIME_DLC13_CHUNK_AVAILABLE` |
| `011_R` or `015` | `RUNTIME_DLC7_CHUNK_AVAILABLE` |
| `016` | `RUNTIME_CHAR_061_AVAILABLE` (Haohmaru) |
| `006_R` | `RUNTIME_DLC9_CHUNK_AVAILABLE` |
| `017` | `RUNTIME_DLC11_CHUNK_AVAILABLE` |
| `018` | `RUNTIME_DLC13_CHUNK_AVAILABLE` |

Stage codes that don't match any of these substrings auto-pass. **Custom
stages with mod-friendly codes survive without any availability hook.**

## `LuxBattleStageInfoTableRow`

UScriptStruct registered by `Z_Construct_UScriptStruct_LuxBattleStageInfoTableRow @ 0x140999d80`.
Row type for the StageInfoTable — per-stage round-position config.

- **Path**: `/Script/LuxorGame.LuxBattleStageInfoTableRow`
- **Size**: `0x108` (264 bytes)

| Offset | Type | Name | Notes |
|-------:|------|------|------|
| +0x008 | `LuxBattleStageBasePositionParam` | `Center` | default arena center |
| +0x030 | `TArray<LuxBattleStageBasePositionParam>` | `OptionalCenters` | per-round-number alternate centers (stages where the arena shifts between rounds) |
| +0x048 | `LuxBattleStageBasePositionParam` | `RingEdge` | ring boundary descriptor |
| +0x058 | `bool` | `bRingEdgeAvailable` | |
| +0x078 | `LuxBattleStageBasePositionParam` | `Wall` | wall-break descriptor |
| +0x088 | `bool` | `bWallAvailable` | |
| +0x0a0 | `FLuxDOFParams` (0x60) | DOF | depth-of-field camera params |
| +0x100 | `int32` | `RoundNumberForGeneratePositionParam` | |

### `LuxBattleStageBasePositionParam`

UScriptStruct registered by `Z_Construct_UScriptStruct_LuxBattleStageBasePositionParam @ 0x140999700`.

- **Size**: `0x28` (40 bytes)

| Offset | Type | Name | Notes |
|-------:|------|------|------|
| +0x00 | `FVector` | `Position` | XYZ in cm (UE4 units) |
| +0x0c | `FRotator` | `Rotation` | Pitch/Yaw/Roll |
| +0x10 | `float` | `DistanceOffset` | ring radius in cm; SC6 stock rings ≈ 700 cm |
| +0x18 | `TArray<int32>` | `RoundNumbers` | which rounds this entry applies to |

## Two-tier collision (gameplay vs visuals)

A SC6 stage has two parallel collision representations. Both must exist for
the stage to function but the gameplay engine only consults the second.

**1. UE4 actor world** (visual + camera + particle physics):

```
ALuxBattleStage  (root actor, class size 0x3a0)
└── ALuxBattleStageActorManager  (class size 0x420, 9 TArray<UObject*> at +0x388..+0x408)
    ├── StageMeshActorList          (ALuxStageMeshActor, visual + UE4 collision)
    ├── BarrierActorList            (ALuxStageBreakableBarrierActor, ring-out triggers)
    ├── BreakableWallActorList      (ALuxStageBreakableWallActor, wall-break)
    ├── CuttableStageMeshActorList  (Soul-Charge sliceable scenery)
    ├── HideableMeshActorList / VisibilitySwitcherList / StageMobList
    ├── WolfCharacterList           (background animals)
    └── StageActorList              (catch-all)
```

Each `ULuxStageMeshComponent` carries a stock UE4 `UBodySetup`
(`Z_Construct_UClass_UBodySetup_NoRegister @ 0x1422b8e50` confirms verbatim
`AggGeom @+0x28`, `BodyInstance @+0x90`, `CollisionTraceFlag @+0x89`, etc.).
**No Lux customization** — FBX import with `UCX_/UBX_/USP_/UCP_` prefix
meshes produces the right cooked-PhysX BodySetup.

**2. scbattle gameplay engine** (deterministic, rollback-safe):

`scbattle::StageInfoHandler` (allocated by `LuxBattle_CreateStageInfoHandler @ 0x1403c3010`)
backed by globals at `0x144844010..0x144844158`:

| Address | Label | Size | Purpose |
|---|---|---:|---|
| `0x144844010` | `g_scbattle_StageInfo_RngSeed` | 4 B | host-broadcast match seed |
| `0x144844020` | `g_scbattle_StageInfo_StageBoundaryParams` | 64 B | spawn data (Origin/P1/P2 offsets/facing) |
| `0x144844068` | `g_scbattle_StageInfo_Initialized` | 4 B | flag |
| `0x14484406c` | `g_scbattle_StageInfo_BarrierCount` | 4 B | valid flag (0/1) |
| `0x144844070` | `g_scbattle_StageInfo_BarrierArray` | 384 B | 24 × 16-byte ring polygon entries |

Populated at match start by walking `BarrierActorList` + `BreakableWallActorList`
and pushing geometry through `scbattle_StageInfo_SetBarrierGeometry @ 0x1402d77c0`
(StageInfoHandler vtable slot 21, vtable at `0x143269070`).

The two systems coordinate at match start via event 0x19 dispatched by
`LuxStage_RegisterBarrierActor_BattleEvent0x19 @ 0x140427490` and
`LuxStage_RegisterWallActor_BattleEvent0x19 @ 0x140428ee0` — fired per actor
from `LuxActor_CollectActors_By8Classes_IntoTArrays @ 0x140417a70`.

## Adding a wholly new stage

The hard part isn't getting your `.umap` discovered — UE4 does that for free.
The hard part is bypassing the Blueprint stage-picker so a custom code reaches
the C++ load path.

### What's already free

The C++ stage-load path is **agnostic to the master enum table**. The validation
functions (`IsValidStageCodeStr_LookupInMasterEnum @ 0x140647230` and
`ResolveStageCodeToAssetPath @ 0x140641840`) are only reachable via the
Blueprint exec wrappers (`execIsValidStageCodeStr`, `execResolveStageCodeToAssetPath`)
— the actual native load chain never calls them. Confirmed by single-caller
xrefs.

The actual load chain is:

```text
ApplyBattleSettingDataTableToBattleManager @ 0x140594eb0
  reads  StageSetting.StageCode  (FString from the LuxDataTable)
  ↓
LuxBattle_KickStageAssetPreload @ 0x14064d940
  hands the FString off to the UILoadManager
  ↓
UUILoadManager_PreloadStageAssets @ 0x142f124f0
  ↓
UAssetManager.GetPrimaryAssetIdsForType("Map", ...)   ← uses standard UE4 PrimaryAssetType
UAssetManager.RequestAsyncLoad(paths)
```

So **any `.umap` mounted under `/Game/` is auto-discovered as a `Map` primary
asset.** No native code patches are needed for asset discovery, validation,
or path resolution. Drop a properly-built umap in a `_P.pak` and the
AssetManager will find it.

The per-character `StageInfoTable` lookup
(`LuxMoveProvider_LoadStageInfo_FromTable @ 0x1403e2370`) **fails gracefully**
when the row is missing — it just doesn't override the move-provider's
defaults at `+0x250..+0x2b0`. So you don't need to author table rows for
custom stages unless you want character-specific corner / wall interactions.

### The actual hard part: getting your code into `StageSetting.StageCode`

The string in `StageSetting.StageCode` becomes the `FPrimaryAssetId.AssetName`
that the AssetManager looks up. The Blueprint stage-select UI writes this
field; nothing else does in normal flow. To get a custom code there you have
to either:

1. **Override after the BP picks** — hook
   `ApplyBattleSettingDataTableToBattleManager @ 0x140594eb0` (or one of the
   `LuxDataTable_LookupByKey` calls inside it) and rewrite
   `StageSetting.StageCode` to your custom code before the preload kick. This
   doesn't need any UI changes — pick "Free Stage" in the menu, get your
   custom map.
2. **Inject into the Blueprint picker** — UE4SS BP hook on
   `ULuxUIBattleLauncher::SetStageCode` (or the picker widget's
   construction) to add your code to the picker list. Validation in the
   picker calls `execIsValidStageCodeStr`, which does check the master enum
   — so you also need to:
3. **Append to the master enum** — hook
   `InitGlobalLuxStageMasterEnumStringTable @ 0x140149720` (runs once at
   startup; append `FBattleStageEnumEntry` rows to the TArray it builds).

Combinations:

| Goal | Hooks needed |
|---|---|
| Test load only (no UI) | (1) BP-level redirect of StageSetting.StageCode |
| Custom in normal stage select | (2) + (3): BP picker injection + master enum append |
| Custom in random pool | (3) only — `GetStageCodes_BuildMasterList` reads the TArray you appended; substring-safe codes auto-pass the DLC gate |

### Required umap contents

Whichever route you pick, the `.umap` must contain the correct actor
hierarchy so the match-start collection (`LuxActor_CollectActors_By8Classes_IntoTArrays @ 0x140417a70`)
finds geometry to register with the gameplay engine:

- `ALuxBattleStage` (root)
- `ALuxBattleStageActorManager` (manages the 9 lists)
- 1+ `ALuxStageMeshActor` — visuals + UE4 collision (`UCX_/UBX_/USP_/UCP_`
  meshes auto-route into `BodySetup.AggGeom`)
- 4–8 `ALuxStageBreakableBarrierActor` — invisible boxes forming the
  ring-out boundary
- (Optional) `ALuxStageBreakableWallActor` — breakable walls

Stub these classes in a UE4 4.18 project with the right `UClass` names and
property layouts so the cooked package's class references resolve against
the shipping `SoulcaliburVI.exe` `UClass*` lookup.

### Naming the stage code

Pick a code that **doesn't** contain any of these DLC substrings, or
`ResolveStageCodeToAssetPath` will misroute the path if a Blueprint ever
asks it to resolve your code:

```text
014  _V  016  006_R  011_R  015  017  018
```

Safe: `STG999`, `STG_MOD_A`, `STGCUSTOM01`, `STG042`. The actual native
load path doesn't use the resolver, but the BP picker may.

### Online play

The custom-code mod needs to be **installed on both peers**. The host
broadcasts the stage code via the LuxOnlineBattleSync "Stage" message; if
the client's AssetManager can't resolve the code (no umap at the matching
primary-asset path) the stream load fails and the match desyncs at level
load time.

## Runtime collision overlay (collision-only mods)

If you want to reshape ring-out / wall-break geometry without authoring a
new umap, hook `scbattle_StageInfo_SetBarrierGeometry @ 0x1402d77c0` and
rewrite the 192-byte buffer that gets copied to
`g_scbattle_StageInfo_BarrierArray @ 0x144844070`. Visual stage stays the
same; the deterministic ring boundary becomes whatever you supply. Online
play needs the same hook on both peers — otherwise rollback snapshots
disagree about ring-out events.

## Random-pool bias

`GetStageCodes_BuildMasterList` filters out only `_T` anomaly variants — it
**keeps** `_R` remix and `_V` alt variants. With all DLC owned the random
pool ends up with these counts:

| Stage | Entries | Roll bias |
|---|:---:|---|
| STG006 | 3 (`STG006`, `STG006_R`, `STG006_V`) | 3× |
| STG011 | 3 (`STG011`, `STG011_R`, `STG011_R_V`) | 3× |
| STG001 | 2 (`STG001`, `STG001_V`) | 2× |
| STG015 | 2 (`STG015`, `STG015_R`) | 2× |
| STG017 | 2 (`STG017`, `STG017_V`) | 2× |
| All others | 1 | baseline |

Probabilities over the 24-stage filtered pool (uniform `RandHelper(24)`):

- `STG006*` / `STG011*`: 3/24 ≈ 12.5%
- `STG001*` / `STG015*` / `STG017*`: 2/24 ≈ 8.3%
- Singleton stages: 1/24 ≈ 4.2%

This is the single largest cause of "some maps show up more often." A
de-duplication mod that hooks `GetStageCodes_BuildMasterList` and folds
`_R` / `_V` siblings into their base entry would flatten the distribution.

## Stage-code packing

`ParseStageCodeStrToId` (called from `ApplyBattleSettingDataTableToBattleManager`)
encodes the stage string into a packed int:

| String | → Packed int |
|---|---|
| `"RND"` | `-1` (random sentinel — Blueprint substitutes a concrete code before match start) |
| `"UNK"` | `1000` |
| `"STG003"` | `0x003` |
| `"STG011_R"` | `0x111` (bit 8 set = `_R`) |
| `"STGxxx_V"` | `0xxx \| 0x200` (bit 9 set = `_V`) |

The packed int is written to `FBattleStageInfo+0x148` on the active
MoveProvider. The is-anomaly bit (`_T` suffix) goes to `+0x14c`.

## Cross-references

- **Custom stage collision authoring** — see [Drawing 3D Debug Lines](line-batching.md)
  for the BodySetup format and the Blender pipeline doc on
  `LuxBattle_CreateStageInfoHandler @ 0x1403c3010` (Ghidra plate comment).
- **Match-start data flow** — see
  [Battle Manager](battle-manager.md) for how the LuxDataTable BattleSetting
  hands `StageSetting.StageCode` down to the runtime.
