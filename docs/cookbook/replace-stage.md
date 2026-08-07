# Recipe: Replace an existing stage

**Goal**: ship a custom map by overriding a stock stage slot. The simple path
replaces the stock `.umap` in a higher-priority `_P.pak` and needs no DLL hook.

**Requires**: UE4 4.17.2 editor (matching SC6's engine version), UnrealPak.exe,
and a basic Blender -> UE4 FBX workflow. UAssetGUI/FModel is optional for
editing `StageInfoTable` or `ULuxStageAssetPaths` assets.

## What replacement changes

Replacing a stage code keeps the stock menu entry, stage id, DLC gate, and match
flow. You are only overriding assets that the stock stage already resolves.

| Layer | No-code replacement path | Notes |
|---|---|---|
| Visible level | Override `/Game/Stage/<code>/Maps/<code>.umap` | Enough for a visual reskin. |
| UE4 mesh collision | Cook replacement static meshes with valid `BodySetup.AggGeom` | Used by camera, particles, overlaps, and visual collision. |
| Breakable wall/barrier actors | Author matching `ALuxStageBreakableWallActor` / `ALuxStageBreakableBarrierActor` placements in the replacement `.umap` | Needed for visible set pieces and event registration, but not enough by itself to create new deterministic wall cells or unlimited barrier segments. |
| Spawn/camera row | Edit the `StageInfoTable` row for the stock code | Does not rewrite deterministic ring/wall collision by itself. |
| Terrain/wall/ring tags | Override the stock `ULuxStageAssetPaths` object and its `ESA_HitData` / `ESA_HitData2` raw assets | This is the no-DLL path for `J_StgHitChkData`, but the raw blob format must be valid. |
| Cosmetic stage flags | Override `ULuxStageAssetPaths.Setting` | `bWet` is the best verified flag; anomaly VFX and breath also copy through stage/VFX refresh. |

The native path confirmed in Ghidra is:

```text
UUILoadManager_PreloadStageAssets @ 0x142f124f0
  requests AssetManager PrimaryAssetType "Map" for the selected stock code

LookupLuxStageAssetPathNameByPackedStageId @ 0x14089b2c0
  formats packed stage id as "%03X", for example STG004 -> "004"

BuildLuxStageRawAssetLookupMap @ 0x14089d9a0
  indexes ULuxStageAssetPaths.RawAssets by path

LuxObject_BuildParamSlots_FromBattleSubstrings_4Slots @ 0x1404208b0
  maps ESA_HitData / ESA_HitData2 / camera raw assets into battle setup slots
```

## Pick a target stage

| Recommended | Why |
|---|---|
| `STG004` | Free Stage; visually generic; no `_R`/`_V` siblings share the same base-game map path. |
| `STG003` | Same general replacement behavior. |
| `STG013` | Same general replacement behavior. |

Avoid `STG001`, `STG006`, `STG011`, `STG015`, and `STG017` for first tests.
They have `_R` or `_V` variants that share or reroute paths through
`ResolveStageCodeToAssetPath @ 0x140641840`, so it is easier to accidentally
replace more than one menu choice or miss a DLC-specific layout.

For the rest of this recipe, the target is `STG004`.

## Build the level

Save the replacement level at the exact stock content path:

```text
/Game/Stage/STG004/Maps/STG004
```

The level needs the SC6 actor class names to resolve when the cooked package is
loaded by `SoulcaliburVI.exe`. In a UE4 4.17.2 mod project, stub the native classes
with the right names. For a simple map, inheriting from `AActor` is enough for
authoring the package references.

Required actor set:

| Actor/class | Purpose |
|---|---|
| `ALuxBattleStage` | Root stage actor. |
| `ALuxBattleStageActorManager` | Owns the stage actor lists at `+0x388..+0x408`. |
| `ALuxStageMeshActor` | Visible meshes and UE4 `BodySetup` collision. |
| `ALuxStageBreakableBarrierActor` | Barrier/ring-boundary bridge actors. |
| `ALuxStageBreakableWallActor` | Optional visible breakable wall/set-piece actors. |

The actor manager's nine native lists are documented in
[Stage System](../sc6/stage-system.md#ue4-actor-and-bodysetup-collision). The
important replacement rule is that `ALuxStageMeshActor` handles visible geometry,
while barrier/wall gameplay still has separate deterministic data paths.

## Author collision

For visual collision, give each replacement `ALuxStageMeshActor.StaticMesh` a
proper UE4 `BodySetup`. UE4's FBX importer converts these Blender mesh-name
prefixes into `StaticMesh.BodySetup.AggGeom` entries:

| Prefix | UE4 import becomes |
|---|---|
| `UCX_<MeshName>_NN` | `FKConvexElem` |
| `UBX_<MeshName>_NN` | `FKBoxElem` |
| `USP_<MeshName>_NN` | `FKSphereElem` |
| `UCP_<MeshName>_NN` | `FKSphylElem` capsule |

This fixes ordinary UE4 collision: camera avoidance, particles, actor overlaps,
and visual proximity. It does **not** automatically rewrite the deterministic
ring-out or wall grid.

For replacement work, keep the collision layers separate:

| Layer | Content path | Good for | Limit |
|---|---|---|---|
| UE4 `BodySetup` / actors | Replacement `.umap` and cooked static meshes | Visual floor contact, camera avoidance, particles, overlap triggers, wall props. | Fighters can still obey stock ring/wall rules. |
| Round-restore payload | Runtime `g_LuxBattleRoundSnapshotPayload @ 0x144844070` | Round/RNG/VFX/motion restoration only. | Not collision geometry; patching it corrupts restored battle state. |
| `J_StgHitChkData` terrain/wall grid | `ULuxStageAssetPaths.RawAssets` entries `ESA_HitData` and `ESA_HitData2` | Terrain height, wall contacts, ring-edge tags, and Move VM geometry predicates. | Raw blob format is only partially documented; replacement blobs must attach cleanly. |
| Breakable wall/barrier actors | `ALuxStageBreakableWallActor` / `ALuxStageBreakableBarrierActor` in the map | Visible breakable set pieces and event-class `0x19` registration. | Actor placement alone has not been proven to author new rollback-safe wall cells. |

Barrier actors still run through the stage setup path, but their count and
component bounds do not define the `J_StgHitChkData` terrain/wall/ring grid.

## Optional: replace raw hit data

If the replacement only changes visuals, skip this section. If the ring edge,
terrain height, wall contact tags, or start camera data need to differ from the
stock stage, inspect the stock `ULuxStageAssetPaths` object for the packed id
`"004"`.

Ghidra-confirmed reflected layout:

```c
struct LuxStageRawAsset {          // 0x18
    ELuxStageAssetType Type;       // +0x00
    uint                Pad04;     // +0x04 alignment
    FString             Path;      // +0x08
};

struct LuxStageSetting {           // 0x03
    bool bAnomalyStageVFxEnabled;  // +0x00
    bool bWet;                     // +0x01
    bool bBreath;                  // +0x02
};

class ULuxStageAssetPaths {        // native size 0x58
    /* UObject / ULuxAssetPathsBase */
    FName                  Identifier; // +0x38, usually "004" for STG004
    TArray<LuxStageRawAsset> RawAssets; // +0x40
    LuxStageSetting        Setting;    // +0x50
};
```

`ELuxStageAssetType` maps as follows:

| Value | Enum | Runtime destination |
|---:|---|---|
| 0 | `ESA_HitData` | `LuxStageAssetParamSlots.pHitData` -> `J_StgHitChkData*` A |
| 1 | `ESA_HitData2` | `LuxStageAssetParamSlots.pHitData2` -> `J_StgHitChkData*` B |
| 2 | `ESA_IntroCameraData` | `LuxStageAssetParamSlots.pIntroCameraData` |
| 3 | `ESA_StartCameraData` | `LuxStageAssetParamSlots.pStartCameraData` |

The slot builder strips each loaded candidate path down to its `Battle/` suffix
before matching it against `RawAssets.Path`. If you override `ULuxStageAssetPaths`,
keep paths consistent with the raw assets you actually ship in the pak.

Treat `ESA_HitData` and `ESA_HitData2` as an A/B pair. For experiments, replace
both entries from the same source stage or from the same custom build; do not
mix one stock blob with one edited blob unless the mismatch is the thing being
tested. The serialized `J_StgHitChkData` header, cell headers, pool chunks, and
runtime frame-bounds grid are partially documented in
[Structures](../sc6/structures.md#j_stghitchkdata-serialized-terrainwall-blob),
but the docs do not yet define a complete authoring schema for wall-break
regions or every terrain tag.

## Explore wall and breakable-wall replacement

Use this when the goal is more than stage skinning: moving wall collision,
making the existing wall behavior follow new geometry, or testing whether a
stage slot can support extra breakable walls.

What is known:

- Visual replacement is solved by `.umap` and `BodySetup` overrides.
- `ALuxStageBreakableWallActor` and `ALuxStageBreakableBarrierActor` are real
  stage actors collected by the actor manager and registered through stage event
  class `0x19`.
- Deterministic terrain/wall/ring geometry comes from the paired
  `J_StgHitChkData` grids. Adding barrier actors is not the same thing as adding
  deterministic terrain entries.
- Terrain height, wall contacts, and ring-edge tags flow through the
  `ULuxStageAssetPaths.RawAssets` -> `ESA_HitData` / `ESA_HitData2` ->
  `J_StgHitChkData` path.

What is still unproven:

- Whether a newly added breakable wall actor becomes gameplay-active without a
  matching entry in the raw hit data.
- Which raw `J_StgHitChkData` fields bind wall-break regions to wall actors,
  wall names, indices, stage state, or Soul Charge break behavior.
- Whether any stock stage slot has spare deterministic wall capacity beyond the
  data already present in its shipped raw hit blobs.

Practical community workflow:

1. Pick a donor that already has the behavior you want to study. Use `STG009`
   for breakable-wall behavior and `STG004` for barrier/ring-boundary behavior
   before trying a stage with no similar stock feature.
2. Build a visual-only replacement first. Keep the stock `ULuxStageAssetPaths`
   and raw hit data unchanged, then verify that camera/particle collision follows
   the new meshes while fighter ring/wall behavior still matches stock.
3. Add or move one `ALuxStageBreakableWallActor` in the `.umap` while leaving
   raw hit data stock. If the prop appears or breaks visually but fighter wall
   contact stays stock, record that as actor-layer success and deterministic
   collision failure.
4. Prove raw asset routing before editing bytes. Override the stock
   `ULuxStageAssetPaths` object with paths that still point to the original
   stock raw assets, then verify the stage behaves identically.
5. Try a stock-blob swap next. Point both `ESA_HitData` and `ESA_HitData2` for
   the target stage at another stock stage's paired hit-data blobs. If wall or
   ring behavior follows the donor while visuals do not, the no-DLL content path
   is working.
6. Only then try raw hit-data edits. Change one variable at a time, keep before
   and after hashes, and test both A/B blobs through round start, wall contact,
   wall break, ring-out, rematch, and stage reload.
7. Treat "more breakable walls" as unverified until a test shows all three
   layers agree: visible actor exists, deterministic wall contact occurs at the
   new wall, and the break state stays stable across round transitions.

Read failures by layer:

| Result | Interpretation |
|---|---|
| Camera stops at the new mesh, fighters do not | UE4 `BodySetup` changed; deterministic collision did not. |
| Fighters hit a stock invisible wall after the visual wall moved | `J_StgHitChkData` still describes the stock layout. |
| A wall breaks visually but still blocks or never blocks fighters | Breakable actor/event path and deterministic wall grid are out of sync. |
| Donor raw hit data changes gameplay under target visuals | `ULuxStageAssetPaths` raw-hit routing is confirmed; the remaining work is valid `J_StgHitChkData` authoring. |
| New barrier actors appear but ring-out stays stock | Actor presentation changed without replacing the `J_StgHitChkData` ring-edge entries. |

## Optional: edit StageInfoTable

Open the `StageInfoTable` `.uasset` in UAssetGUI only if the replacement needs
different round positions, center/ring-edge metadata, or camera depth-of-field
settings.

For `STG004`, edit the existing row instead of adding a new one. The row type is
`LuxBattleStageInfoTableRow`; see [Stage System](../sc6/stage-system.md#luxbattlestageinfotablerow)
for offsets. This table is forgiving but limited: it does not replace
`J_StgHitChkData`.

## Cook and pack

Cook the UE4 4.17.2 project for Windows. Then build a high-priority patch pak:

```bat
UnrealPak.exe pakchunk999-WindowsNoEditor_P.pak -create=filelist.txt -compress
```

Example `filelist.txt` entries for a map-only `STG004` replacement. Include only
the sidecar files that cooking actually produced:

```text
"C:\ModProject\Saved\Cooked\WindowsNoEditor\ModProject\Content\Stage\STG004\Maps\STG004.umap" "../../../SoulcaliburVI/Content/Stage/STG004/Maps/STG004.umap"
"C:\ModProject\Saved\Cooked\WindowsNoEditor\ModProject\Content\Stage\STG004\Maps\STG004.uexp" "../../../SoulcaliburVI/Content/Stage/STG004/Maps/STG004.uexp"
"C:\ModProject\Saved\Cooked\WindowsNoEditor\ModProject\Content\Stage\STG004\Maps\STG004.ubulk" "../../../SoulcaliburVI/Content/Stage/STG004/Maps/STG004.ubulk"
```

Use the same destination path format for edited `StageInfoTable`,
`ULuxStageAssetPaths`, or raw hit/camera assets. The destination path inside the
pak must match the stock asset you want to override.

## Install

Drop the resulting pak into:

```text
<Steam>/steamapps/common/SoulcaliburVI/SoulcaliburVI/Content/Paks/~mods/
```

The `~mods/` subfolder is a community convention. UE4 mounts paks recursively,
and the `_P` suffix gives this pak priority over the stock asset.

## Verify

1. Launch the game.
2. Pick `STG004` in stage select. The replacement map should load instead of
   Free Stage.
3. In game or native hook logs, look for `UUILoadManager` preload lines for `STG004`.
4. Walk the whole arena and test camera collision, floor collision, ring edge,
   wall interaction, and round transitions.
5. If characters fall through visual geometry, check the cooked static mesh
   `BodySetup` and Blender collision prefixes.
6. If ring-out or wall behavior still matches stock, the deterministic
   `J_StgHitChkData` path is still stock.
7. For breakable-wall tests, check contact before break, the break trigger, post-break
   traversal, rematch, and a full stage reload.
8. If wet/breath/anomaly effects do not change, verify the stock
   `ULuxStageAssetPaths` object for id `"004"` was overridden and not just the
   `.umap`.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Stock map still loads | Pak path mismatch or pak priority too low | Confirm destination path is `/Content/Stage/STG004/Maps/STG004.*` and filename ends in `_P.pak`. |
| Map loads, but floor collision fails | Static mesh `BodySetup` did not cook | Reimport with `UCX_`, `UBX_`, `USP_`, or `UCP_` collision meshes and recook. |
| Visual collision works, ring-out stays stock | Only UE4 collision changed | Override `ULuxStageAssetPaths` raw hit data or use a runtime hook for `J_StgHitChkData`. |
| Breakable walls are visible but not gameplay-active | Wall actors are present, but deterministic wall data still stock or missing matching wall regions | Check the wall actor registration path, then prove the paired `ESA_HitData` / `ESA_HitData2` blobs route correctly. |
| Extra barrier or wall actors do not change collision | Actor presentation/registration is separate from deterministic terrain data | Author or substitute matching A/B `J_StgHitChkData` blobs; treat additional geometry as raw-hit-data/runtime-hook research. |
| Stage select entry name is still stock | Replacement keeps the stock stage code and loc id | This is expected for a no-DLL replacement. Use a custom-stage mod for new UI entries. |
| DLC variant also changed | Target code shares a base/DLC route | Use a simpler target such as `STG004`, `STG003`, or `STG013`. |

## When replacement is not enough

Use [Load a wholly new custom stage](custom-stage.md) instead if you need a new
stage code, a new stage-select entry, or a custom random-pool entry. The no-DLL
replacement route intentionally reuses the stock code and stock UI flow.

## Related

- [Stage System](../sc6/stage-system.md) - full reference for stage loading,
  collision storage, `ULuxStageAssetPaths`, and the round-restore correction.
- [Structures](../sc6/structures.md#j_stghitchkdata-serialized-terrainwall-blob)
  - partial `J_StgHitChkData` and frame-bounds-grid structure notes.
- `LuxBattle_AttachStgHitChkData @ 0x140392080` - expands the serialized raw-hit
  blob into the live terrain/wall/ring frame-bounds grid.
