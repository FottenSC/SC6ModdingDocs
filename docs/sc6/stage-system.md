# Stage System

How SC6 enumerates, gates, loads, and configures stages — and the four pieces
you need to ship a custom map.

All addresses are absolute (image base `0x140000000`).

## At a glance

A stage in SC6 is the sum of four independent pieces:

| Piece | Where it lives | Mutable via |
|---|---|---|
| **Master enum entry** | `g_LuxStage_MasterEnumStringTable @ 0x144149c50` (`TArray<FBattleStageEnumEntry>`, 31 stock entries) | DLL hook into `InitGlobalLuxStageMasterEnumStringTable @ 0x140149720` |
| **Stage info row** | `LuxBattleStageInfoTableRow` UDataTable .uasset, looked up by `FName "StageInfoTable"` | Edit .uasset (UAssetGUI / FModel) |
| **Level .umap** | `/Game/Stage/<code>/Maps/<code>.umap` (resolver: `ResolveStageCodeToAssetPath @ 0x140641840`) | Drop a `_P.pak` into `Content/Paks/~mods/` |
| **Selected stage code** | `LuxDataTable` key `StageSetting.StageCode` in the battle launcher cache | `ULuxUIBattleLauncher::Start` / `GetBattleStageCode`; Blueprint picker hooks can rewrite it before match start |

The four pieces are independent: replacing the .umap alone is enough to reskin a
stock stage. Adding a wholly new stage means touching the master enum, which is
built statically and therefore needs a DLL hook.

## Key entry points

| Function | RVA | Role |
|---|---|---|
| `InitGlobalLuxStageMasterEnumStringTable` | `0x140149720` | Static initializer that builds the 31 stock master-enum entries. **Hook this to add new stages.** |
| `GetStageCodes_BuildMasterList` | `0x140640890` | Returns master roster minus `_T` anomaly variants. UFunction `ULuxUIGameFlowManager::GetStageCodes`. |
| `GetStageCodesIfAvailable_FilterByDLCChunks` | `0x1406409f0` | Filters by DLC ownership; final pool the random picker draws from. |
| `IsValidStageCodeStr_LookupInMasterEnum` | `0x140647230` | Validation — is this stage code in the table? |
| `ResolveStageCodeToAssetPath` | `0x140641840` | Stage code string → `/Game/Stage/...` asset path. Substring-based DLC routing. |
| `GetStageLocIdByStageCode` | `0x1406415B0` | Stage code → display loc ID. |
| `ApplyBattleSettingDataTableToBattleManager` | `0x140594eb0` | Match-start consumer. Reads `StageSetting.StageCode`, parses to packed int, fires async stage load. |
| `ULuxUIBattleLauncher::Start` | `0x1405eeb50` | Copies `StageSetting` and the other launch sub-tables into the BattleManager setup table. |
| `ULuxUIBattleLauncher::GetBattleStageCode` | `0x1405b0c60` | Reads `StageSetting.StageCode`; defaults to `STG001` if missing. |
| `LuxBattle_CreateStageInfoHandler` | `0x1403c3010` | Allocates the gameplay-side `scbattle::StageInfoHandler`. |
| `SetScbattleStageInfoBarrierGeometry` | `0x1402d77c0` | Copies exactly 12 deterministic ring-boundary entries into `g_aScbattleStageInfoBarrierEntries`. |
| `GetScbattleStageInfoBarrierGeometry` | `0x1402d7730` | Copies exactly 12 deterministic ring-boundary entries out when the valid flag is set. |
| `LuxBattle_SetFrameCacheHitChkDataPtrs` | `0x1402dae70` | Seeds the A/B `J_StgHitChkData*` globals used by frame-cache refresh. |
| `LuxBattle_AttachStgHitChkData` | `0x140392080` | Expands serialized terrain/wall collision blobs into live frame-bounds grids. |
| `LuxBattleManager_InitRound_TickTimers_ClearRoundData` | `0x1403fb660` | Round-start consumer of `ULuxStageAssetPaths.Setting.bWet`; drives `WetRatio`. |
| `LuxBattleManager_StopTimers_IsBattleRunning_WetRatio` | `0x1403eec20` | Round/shutdown cleanup for `IsBattleRunning` and `WetRatio` timer handles. |
| `LuxMove_RefreshProvider_CacheMeshesAndParts` | `0x1403cede0` | Copies `bAnomalyStageVFxEnabled` / `bBreath` into the stage/VFX refresh state. |
| `IsAnomalyStageByStageCodeStr` | `0x140646230` | Pure string check for `_T`; separate from `LuxStageSetting.bAnomalyStageVFxEnabled`. |

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

## Stage collision storage

SC6 stage collision is not one asset. The shipping build keeps at least three
separate representations, and each one answers a different runtime question.

### UE4 actor and `BodySetup` collision

The loaded `.umap` owns the actor hierarchy used by visuals, camera helpers,
particle physics, and ordinary UE4 component collision:

```
ALuxBattleStage  (root actor, class size 0x3a0)
└── ALuxBattleStageActorManager  (class size 0x420)
    ├── +0x388 StageActorList
    ├── +0x398 WolfCharacterList
    ├── +0x3a8 BreakableWallActorList
    ├── +0x3b8 BarrierActorList
    ├── +0x3c8 HideableMeshActorList
    ├── +0x3d8 VisibilitySwitcherList
    ├── +0x3e8 StageMobList
    ├── +0x3f8 StageMeshActorList
    └── +0x408 CuttableStageMeshActorList
```

`LuxActor_CollectActors_By8Classes_IntoTArrays @ 0x140417a70` walks the
persistent level, streamed sublevels, and relevant actor/component objects, then
partitions matching stage actors into those arrays. The arrays are not all
deterministic collision inputs; several are only visual, visibility, or
background-animation helpers.

| Manager list | Native object collected | Runtime role |
|---|---|---|
| `StageActorList` | Any `ALuxStageActorBase` subclass | Catch-all list for stage-specific Lux actors. It is a broad registry, not a collision layer by itself. |
| `WolfCharacterList` | `ALuxStageWolfCharacter` (`LuxStageWolfCharacter` registered class) | Background creature/animal actor bucket. Despite some decompiler names saying `MobBase`, the registered class is wolf-character-specific. |
| `BreakableWallActorList` | `ALuxStageBreakableWallActor` | Visible breakable wall/set-piece actors. After collection, each wall dispatches battle event class `0x19` through `LuxStage_RegisterWallActor_BattleEvent0x19`; gameplay then treats the wall as a registered breakable segment. |
| `BarrierActorList` | `ALuxStageBreakableBarrierActor` | Invisible/nonvisual arena-boundary or ring-out trigger actors. After collection, each barrier dispatches battle event class `0x19` through `LuxStage_RegisterBarrierActor_BattleEvent0x19`. The fixed 12-entry scbattle barrier block is still the authoritative deterministic boundary after registration. |
| `HideableMeshActorList` | `ALuxStageHideableMeshActor` | Mesh actors that can be hidden/faded based on camera, LOD, or stage state. The collector can immediately hide them if the active condition fails. |
| `VisibilitySwitcherList` | `ALuxStageVisibilitySwitcher` / registered `LuxStageVisibilitySwitcher` | Stage-state visibility controllers used by streamed BG/VFX/gimmick sublevels to toggle sets of actors. The current Ghidra wrapper name includes `Actor`, but the reflected class string is `LuxStageVisibilitySwitcher`. |
| `StageMobList` | `ULuxStageAnimInstance` from `ALuxStagePawnBase` actors | Stores stage mob animation instances, not the pawn actors themselves. Used for animated background characters/creatures and stage animation events. |
| `StageMeshActorList` | `ALuxStageMeshActor` | Visible stage meshes plus their ordinary UE4-side `ULuxStageMeshComponent`/`UBodySetup` collision. Useful for camera, particles, overlaps, and visual collision, but not sufficient for rollback-safe ring/wall gameplay geometry. |
| `CuttableStageMeshActorList` | `ALuxStageCuttableMeshBase` (`LuxStageCuttableMeshBase` registered class) | Optional weapon-overlap sliceable mesh actor. The native path owns an initial static mesh, a procedural mesh, slice particles/SE, `MinCuttableDistance`, and an `OnOverlapBegin` handler that only accepts overlaps involving a component whose name contains `weapon` and an `ALuxBattleChara`. No Soul Charge gate was observed in this path. |

Observed stock-map usage from the current dump (`.umap` name-table string scan
under `/Content/Stage` and `/Content/DLC/*/Stage`; exact class-string matches
only):

| Manager list / class string | Stage folders observed |
|---|---|
| `ALuxStageMeshActor` | `STG001`, `STG001_T`, `STG002`, `STG002_T`, `STG003`, `STG003_T`, `STG005`, `STG005_T`, `STG008`, `STG008_D`, `STG008_T`, `STG009`, `STG010`, `STG010_T`, `STG011`, `STG011_T`, `STG012`, `STG012_T`, `STG013` |
| `ALuxStageBreakableBarrierActor` | `STG004` (`STG004_Gimmicks2.umap`) |
| `ALuxStageBreakableWallActor` | `STG009` (`STG009_Gimmicks.umap`) |
| `ALuxStageHideableMeshActor` | `STG001`, `STG001_T`, `STG003`, `STG003_T`, `STG009`, `STG011`, `STG011_T`, `STG012`, `STG012_T` |
| `ALuxStageVisibilitySwitcher` / `ALuxStageVisibilitySwitch*` | `STG001`, `STG001_T`, `STG002`, `STG002_D`, `STG002_T`, `STG003`, `STG003_T`, `STG004`, `STG005`, `STG005_T`, `STG006`, `STG008`, `STG008_T`, `STG009`, `STG010`, `STG010_T`, `STG011`, `STG011_T`, `STG012`, `STG012_T`, `STG013` |
| `ALuxStageCuttableMeshBase` / `Cuttable*` | No exact `.umap` matches in the dumped stock stages. The class exists natively, but the dump does not show stock map usage. |
| `ALuxStageWolfCharacter` / `StageMob*` | No exact `.umap` matches in the dumped stock stages. Treat these as supported optional background-actor paths unless a specific stage asset proves otherwise. |

No DLC stage `.umap` in the supplied dump matched these exact Lux stage actor
class strings. That does not prove the DLC stages have no equivalent behavior;
it only means this quick scan did not find those exact native class names in the
map packages.

Each `ULuxStageMeshComponent` carries a stock UE4 `UBodySetup`
(`Z_Construct_UClass_UBodySetup_NoRegister @ 0x1422b8e50` confirms verbatim
`AggGeom @+0x28`, `BodyInstance @+0x90`, `CollisionTraceFlag @+0x89`, etc.).
**No Lux customization** — FBX import with `UCX_/UBX_/USP_/UCP_` prefix
meshes produces the right cooked-PhysX BodySetup.

This does **not** define deterministic ring-out collision by itself. Editing a
static mesh `BodySetup` can fix camera/particle/UE4 overlap behavior, but the
battle simulation reads the scbattle and `J_StgHitChkData` paths below.

### scbattle ring-boundary block

`scbattle::StageInfoHandler` (allocated by `LuxBattle_CreateStageInfoHandler @ 0x1403c3010`)
backs deterministic ring-boundary state with globals at `0x144844010..0x144844130`:

| Address | Label | Size | Purpose |
|---|---|---:|---|
| `0x144844010` | `g_scbattle_StageInfo_RngSeed` | 4 B | host-broadcast match seed |
| `0x144844020` | `g_sScbattleStageBoundaryParams` | 64 B | stage origin, P1/P2 offsets, facing angles |
| `0x144844068` | `g_dwScbattleStageInfoInitialized` | 4 B | initialized flag |
| `0x14484406c` | `g_dwScbattleStageInfoBarrierValid` | 4 B | barrier-valid flag, not a count |
| `0x144844070` | `g_aScbattleStageInfoBarrierEntries` | `0xC0` | `scbattle_BarrierEntry[12]` ring-boundary segments |

`GetScbattleStageInfoBarrierGeometry @ 0x1402d7730` and
`SetScbattleStageInfoBarrierGeometry @ 0x1402d77c0` both copy exactly 12
`scbattle_BarrierEntry` records: 12 entries × 16 bytes = `0xC0`. Older notes
that described a 24-entry / `0x180`-byte block were stale.

```c
struct scbattle_BarrierEntry {  // 0x10
    float flX0;
    float flY0;
    float flX1;
    float flY1;
};
```

The UE4 barrier/wall actor bridge is event-based. `LuxActor_CollectActors_By8Classes_IntoTArrays @ 0x140417a70`
collects the stage actor lists, then `LuxStage_RegisterBarrierActor_BattleEvent0x19 @ 0x140427490`
and `LuxStage_RegisterWallActor_BattleEvent0x19 @ 0x140428ee0` dispatch event
class `0x19` records for those actors. `HandleStageBreakableBarrierHit @ 0x140549f40`
is visual break-event logic; it does not write the deterministic barrier array.

### `J_StgHitChkData` terrain/wall grid

Terrain height, wall contacts, ring-edge tags, and several Move VM geometry
predicates use a separate legacy Namco collision blob named by the debug string
`"J_StgHitChkData::Attach" @ 0x143e89f20`.

Content-side storage is a `ULuxStageAssetPaths` data asset. Reflection shows the
class layout as `Identifier @ +0x38`, `RawAssets @ +0x40`, and `Setting @ +0x50`.
Each `RawAssets` element is a `LuxStageRawAsset` record:

```c
struct LuxStageRawAsset {    // 0x18
    ELuxStageAssetType Type;  // +0x00
    uint               Pad04; // +0x04 alignment
    FString            Path;  // +0x08
};
```

`ELuxStageAssetType` values are:

| Value | Enum | Runtime setup slot |
|---:|---|---|
| 0 | `ESA_HitData` | `J_StgHitChkData*` A |
| 1 | `ESA_HitData2` | `J_StgHitChkData*` B |
| 2 | `ESA_IntroCameraData` | intro camera data pointer |
| 3 | `ESA_StartCameraData` | start camera data pointer |

`LookupLuxStageAssetPathNameByPackedStageId @ 0x14089b2c0` formats the selected
packed stage id as `"%03X"` and looks up the matching `ULuxStageAssetPaths`
asset name/path handle from the asset-registry map.
`BuildLuxStageRawAssetLookupMap @ 0x14089d9a0` indexes the object's `RawAssets`,
then `LuxObject_BuildParamSlots_FromBattleSubstrings_4Slots @ 0x1404208b0` maps
the raw assets by `Type`: values 0 and 1 become the two `J_StgHitChkData*`
pointers later copied by `LuxBattle_SetFrameCacheHitChkDataPtrs`.

### `LuxStageSetting` cosmetic flags

`ULuxStageAssetPaths.Setting @ +0x50` is a compact 3-byte `LuxStageSetting`
struct. These flags are content-side stage behavior toggles, not part of the
deterministic collision layer:

| Asset offset | Field | Verified runtime consumer |
|---:|---|---|
| `+0x50` | `bAnomalyStageVFxEnabled` | Copied by `LuxMove_RefreshProvider_CacheMeshesAndParts @ 0x1403cede0` into the stage/VFX refresh state at `+0x460`. The exact owner layout conflicts with the currently documented `ALuxBattleChara+0x460` UPROPERTY, so runtime-check this offset before hooking it. |
| `+0x51` | `bWet` | Read by `LuxBattleManager_InitRound_TickTimers_ClearRoundData @ 0x1403fb660`. Round init first drives the `WetRatio` timer handle at `BM+0x1428` to `0.0`; if this flag is true, it immediately drives `WetRatio` to `1.0`. `LuxBattleManager_StopTimers_IsBattleRunning_WetRatio @ 0x1403eec20` stops/clears the same timer path. |
| `+0x52` | `bBreath` | Copied by `LuxMove_RefreshProvider_CacheMeshesAndParts @ 0x1403cede0` into the stage/VFX refresh state at `+0x462`; same owner-layout caveat as `bAnomalyStageVFxEnabled`. |

`IsAnomalyStageByStageCodeStr @ 0x140646230` is only a string helper: it returns
true when the stage code contains `_T`. Do not treat that helper as proof that
`bAnomalyStageVFxEnabled` was enabled; the reflected asset flag is copied through
the VFX-refresh path separately.

Modding implication: `bWet` is the cleanest verified no-code toggle in this
group. If a replacement stage overrides the stock `ULuxStageAssetPaths` object
and sets `Setting.bWet`, the battle manager's material-parameter path should
start wet at round init without a native hook. `bAnomalyStageVFxEnabled` and
`bBreath` are promising cosmetic toggles, but the destination owner/offset needs
one live-memory pass before a hook should rely on it.

Runtime storage chain:

| Address / function | Role |
|---|---|
| `ULuxStageAssetPaths.RawAssets` | content-side paths for `ESA_HitData` / `ESA_HitData2` |
| `LuxObject_BuildParamSlots_FromBattleSubstrings_4Slots @ 0x1404208b0` | maps loaded raw assets into setup slots 0..3 by `ELuxStageAssetType` |
| `g_pLuxBattle_StgHitChkDataA @ 0x14470d0d0` | serialized `J_StgHitChkData*` for frame context A |
| `g_pLuxBattle_StgHitChkDataB @ 0x14470d0f8` | serialized `J_StgHitChkData*` for frame context B |
| `LuxBattle_SetFrameCacheHitChkDataPtrs @ 0x1402dae70` | copies those two blob pointers out of a setup packet |
| `LuxBattle_RefreshFrameTerrainCache @ 0x140314480` | pairs FrameTransformA/B with the A/B blobs each refresh |
| `LuxBattle_AttachStgHitChkData @ 0x140392080` | expands the serialized blob into the live frame-bounds grid |
| `g_LuxBattle_FrameBoundsGridA @ 0x144844dd0` | live grid A |
| `g_LuxBattle_FrameBoundsGridB @ 0x144845e80` | live grid B, inside `g_LuxBattle_FrameTransformB + 0xc60` |
| `g_LuxBattle_FrameContextUseB @ 0x14470dedc` | selects A vs B accessors |

Consumers include `LuxBattle_SampleTerrainAtWorldXZ @ 0x1403915a0`,
`LuxBattle_SampleTerrainAtXZ_Impl @ 0x140391350`, and
`LuxBattle_TestAndResolveWallCollision @ 0x140316600`. The terrain tag mapping
observed in the wall path is: tag `1` → `0x3A`, tag `3` → `0x3C`, otherwise
`dwSurfaceFlags >> 4`; `0x3A` is the ring/wall clearance-gated contact,
`0x3B` is vertical floor/ceiling contact, `0x3C` is edge/ring-out terrain, and
`0x3F` is the excluded scan tag.

### Can collisions be modified or added?

Yes, but the viable path depends on which collision layer you mean:

| Goal | Plausible path | Hard limit / risk |
|---|---|---|
| Modify existing deterministic ring boundary | Hook `SetScbattleStageInfoBarrierGeometry @ 0x1402d77c0` or patch `g_aScbattleStageInfoBarrierEntries @ 0x144844070` after it is set | Fixed 12-entry buffer; both peers need identical data online |
| Add more deterministic ring segments | Binary patch the fixed storage, getter/setter copies, and every consumer that assumes 12 entries | More invasive than a data mod; no spare count field was found at `0x14484406c` |
| Move visible/UE4 collision | Edit the `.umap` and each mesh `UBodySetup.AggGeom` with normal UE4 collision meshes | Does not change rollback-safe ring-out/wall tests by itself |
| Move barrier actors in a custom/replaced `.umap` | Author matching `ALuxStageBreakableBarrierActor` transforms and verify the event 0x19 registration path | Still test against the 12-entry scbattle buffer at runtime |
| Modify terrain/wall/ring tags without runtime code | Override the stock `ULuxStageAssetPaths` asset and/or the raw assets referenced by its `ESA_HitData` / `ESA_HitData2` `RawAssets` entries in a higher-priority pak | Requires exact stock object paths and a valid `J_StgHitChkData` binary blob format |
| Modify terrain/wall/ring tags with runtime code | Hook `LuxBattle_SetFrameCacheHitChkDataPtrs` / `LuxBattle_AttachStgHitChkData` to substitute A/B blobs | Easier to experiment, but needs native code and both peers online |

## Adding a wholly new stage

The hard part isn't getting your `.umap` discovered — UE4 does that for free.
The hard part is bypassing the Blueprint stage-picker so a custom code reaches
the C++ load path.

### What's already free

The C++ stage-load path is **agnostic to the master enum table**. The validation
functions (`IsValidStageCodeStr_LookupInMasterEnum @ 0x140647230` and
`ResolveStageCodeToAssetPath @ 0x140641840`) are reachable only through the
Blueprint exec wrappers (`execIsValidStageCodeStr`, `execResolveStageCodeToAssetPath`);
the native load chain never calls them. Confirmed by single-caller xrefs.

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
asset.** Asset discovery, validation, and path resolution need no native code
patches. Drop a properly built umap in a `_P.pak` and the AssetManager will
find it.

The per-character `StageInfoTable` lookup
(`LuxMoveProvider_LoadStageInfo_FromTable @ 0x1403e2370`) **fails gracefully**
when the row is missing — it simply leaves the move-provider defaults at
`+0x250..+0x2b0` unchanged. So you only need to author table rows for custom
stages if you want character-specific corner or wall interactions.

### The actual hard part: getting your code into `StageSetting.StageCode`

The string in `StageSetting.StageCode` becomes the `FPrimaryAssetId.AssetName`
that the AssetManager looks up. In normal flow the Blueprint stage-select UI is
the only writer of this field. To get a custom code there, take one of these
routes:

1. **Override after the BP picks** — hook
   `ApplyBattleSettingDataTableToBattleManager @ 0x140594eb0` (or one of the
   `LuxDataTable_LookupByKey` calls inside it) and rewrite
   `StageSetting.StageCode` to your custom code before the preload kick. This
   needs no UI changes: pick "Free Stage" in the menu and get your custom map.
2. **Inject into the Blueprint picker** — a native hook at the picker widget
   or stage-code setter path that adds your code to the picker list. The
   picker's validation calls
   `execIsValidStageCodeStr`, which *does* check the master enum — so this
   route also requires:
3. **Append to the master enum** — hook
   `InitGlobalLuxStageMasterEnumStringTable @ 0x140149720` (it runs once at
   startup) and append `FBattleStageEnumEntry` rows to the TArray it builds.

Combinations:

| Goal | Hooks needed |
|---|---|
| Test load only (no UI) | (1) BP-level redirect of StageSetting.StageCode |
| Custom in normal stage select | (2) + (3): BP picker injection + master enum append |
| Custom in random pool | (3) only — `GetStageCodes_BuildMasterList` reads the TArray you appended; substring-safe codes auto-pass the DLC gate |

### Required umap contents

Whichever route you pick, the `.umap` must contain the correct actor
hierarchy, so the match-start collection pass
(`LuxActor_CollectActors_By8Classes_IntoTArrays @ 0x140417a70`) finds geometry
to register with the gameplay engine:

- `ALuxBattleStage` (root)
- `ALuxBattleStageActorManager` (manages the 9 lists)
- 1+ `ALuxStageMeshActor` — visuals + UE4 collision (`UCX_/UBX_/USP_/UCP_`
  meshes auto-route into `BodySetup.AggGeom`)
- `ALuxStageBreakableBarrierActor` placements covering the ring boundary;
  the deterministic scbattle buffer has room for 12 `scbattle_BarrierEntry`
  segments
- (Optional) `ALuxStageBreakableWallActor` — breakable walls

Stub these classes in a UE4 4.17.2 project with the correct `UClass` names and
property layouts, so the cooked package's class references resolve against the
shipping `SoulcaliburVI.exe` `UClass*` lookup.

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

The custom-code mod must be **installed on both peers**. The host broadcasts
the stage code via the LuxOnlineBattleSync "Stage" message; if the client's
AssetManager can't resolve the code — no umap at the matching primary-asset
path — the stream load fails and the match desyncs at level-load time.

## Runtime collision overlay (collision-only mods)

To reshape ring-out or wall-break geometry without authoring a new umap, hook
`SetScbattleStageInfoBarrierGeometry @ 0x1402d77c0` and rewrite the `0xC0`
buffer it copies into `g_aScbattleStageInfoBarrierEntries @ 0x144844070`.
The visual stage stays the same; the deterministic ring boundary becomes the
12 segments you supply. Online play needs the same hook on both peers —
otherwise rollback snapshots disagree about ring-out events.

For terrain height, wall tags, or ring-edge tags, the barrier setter is the
wrong layer. Substitute the `J_StgHitChkData` blob before
`LuxBattle_AttachStgHitChkData @ 0x140392080`, or hook
`LuxBattle_SetFrameCacheHitChkDataPtrs @ 0x1402dae70` to provide replacement
A/B blob pointers.

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
de-duplication mod that hooks `GetStageCodes_BuildMasterList` and folds each
`_R` / `_V` sibling back into its base entry would flatten the distribution.

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
MoveProvider; the is-anomaly bit (`_T` suffix) goes to `+0x14c`.

## Stage investigation backlog

This pass picked `ULuxStageAssetPaths.Setting` first because it is directly
content-authorable and affects visible runtime behavior. Good next stage threads:

| Target | Why it matters | Starting symbols |
|---|---|---|
| Stage wind emitters | Per-stage wind could drive cloth, particles, or force-style cosmetic effects that custom maps may want to preserve. | `AddStageWindParamFromAsset @ 0x1403b3100`, `LuxBattle_RebuildStageWindEmitterList @ 0x1402d9f30`, `LuxBattle_TickStageWindAndAccumulateForces @ 0x140333fd0` |
| Intro/start camera raw assets | `ESA_IntroCameraData` / `ESA_StartCameraData` already map to setup slots 2 and 3, but the binary camera payload format is still not documented. | `LuxCameraAction_StartStageIntro @ 0x140324ad0`, `LuxEffectSystem_InitStageIntroCameraSlot @ 0x140322240`, `LuxEffectCamera_GetStageIntroCameraTypeID @ 0x140301490` |
| Stage BGSE / ambience audio | Custom or replaced stages may need matching background SE `.acb` assets and DLC path routing. | `LuxObject_CreateAsyncLoader_StageBGSE_ACB_RegisterAndAppend @ 0x14042d3d0`, `LuxAudio_LookupStageMaterialSoundTable @ 0x1404247b0` |
| Destructible and visibility actors | Breakable walls, hideable meshes, and visibility switchers are likely the next layer after deterministic barriers. | `HandleStageBreakableWallBroken @ 0x14053d4b0`, `SetStageVisibilitySwitcherEnableFlag @ 0x140bdeaa0`, `SetLuxStageHideableMeshActorMeshHidden @ 0x14055cbf0` |
| Online stage sync payload | New-stage mods need exact host/client stage-code and random-stage behavior to avoid load desyncs. | `LuxOnlineBattleSync_SendStage_StageCode_IsRandom_RngSeed @ 0x14051fc80`, `LuxOnlineBattleSync_RequestStage_SendOpcode6 @ 0x14051dbc0` |

## Cross-references

- **Custom stage collision authoring** — see [Drawing 3D Debug Lines](line-batching.md)
  for the BodySetup format and the Blender pipeline doc on
  `LuxBattle_CreateStageInfoHandler @ 0x1403c3010` (Ghidra plate comment).
- **Match-start data flow** — see
  [Battle Manager](battle-manager.md) for how the LuxDataTable BattleSetting
  hands `StageSetting.StageCode` down to the runtime.
