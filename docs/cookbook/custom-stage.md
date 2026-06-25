# Recipe: Load a wholly new custom stage

**Goal**: ship a `.umap` with a brand-new stage code and get battle flow to
load it without replacing any stock stage.

**Running example**: `STG042`. A numeric `STG###` code keeps the map asset name,
stage code string, and packed stage-id consumers easier to reason about. A
nonnumeric code such as `STGMOD` may still be useful for a map-load experiment,
but validate `ParseStageCodeStrToId` and any packed-id consumers before treating
it as production-safe.

**Requires**: UE4 4.17.2 editor, UnrealPak.exe, UE4SS or a native injector for
the runtime hook, and optional UAssetGUI/FModel for table or data-asset edits.

## What has to line up

A new stage is not one asset. Treat it as several independent layers:

| Layer | What you provide | How to verify |
|---|---|---|
| Map primary asset | `/Game/Stage/STG042/Maps/STG042` | Pak list contains the cooked `.umap`; `UUILoadManager` logs `STG042`. |
| Selected stage code | `StageSetting.StageCode = "STG042"` | Your hook logs the final string before preload. |
| Picker validation, if used | `FBattleStageEnumEntry` in `g_LuxStage_MasterEnumStringTable` | `IsValidStageCodeStr_LookupInMasterEnum` succeeds after your append. |
| Optional display text | Loc row or hook result for `GetStageLocIdByStageCode` | The picker label resolves to the intended string. |
| Optional stage metadata | `StageInfoTable` row for the code | Round start, center/ring-edge metadata, and camera settings match your row. |
| Optional deterministic collision | `ULuxStageAssetPaths` plus paired `ESA_HitData` / `ESA_HitData2`, or a native substitution hook | Runtime inspection shows the intended A/B `J_StgHitChkData*` blobs and scbattle barrier entries. |

The C++ load chain does not require the picker enum:

```text
ApplyBattleSettingDataTableToBattleManager @ 0x140594eb0
  reads StageSetting.StageCode from the LuxDataTable
  ->
LuxBattle_KickStageAssetPreload @ 0x14064d940
  ->
UUILoadManager_PreloadStageAssets @ 0x142f124f0
  ->
UAssetManager.GetPrimaryAssetIdsForType("Map", ...)
UAssetManager.RequestAsyncLoad(...)
```

The important distinction is that the native load path can load any discovered
`Map` primary asset, while the normal Blueprint stage picker validates against
the static master enum. See [Stage System: adding a wholly new stage](../sc6/stage-system.md#adding-a-wholly-new-stage)
for the lower-level call chain.

## Pick a stage code

Use an uppercase ASCII code whose folder name, map package name, and
`StageSetting.StageCode` string are identical.

Recommended first tests:

```text
STG042
STG099
STG999
```

Avoid these substrings:

```text
014  _V  016  006_R  011_R  015  017  018
```

`ResolveStageCodeToAssetPath @ 0x140641840` uses substring routing for DLC
paths. The direct C++ load path does not call that resolver, but Blueprint
picker/helper code can. A custom code containing one of those substrings can be
misrouted to a DLC path before your map ever reaches the AssetManager.

Also avoid `RND`, `UNK`, and `_T` for first tests. Those have documented special
meaning in random-stage and packed-id handling. Add variants only after the base
custom code loads cleanly.

Validation rules by route:

| Route | Needs master enum append? | Needs DLC-substring-safe code? | Notes |
|---|---:|---:|---|
| Late redirect after a stock pick | No | Yes, if any BP resolver sees it | Fastest proof that the map can load. |
| Normal picker entry | Yes | Yes | Also needs a picker/UI insertion path and display text. |
| Random pool | Yes | Yes | `GetStageCodes_BuildMasterList` reads the appended enum table; `_T` variants are filtered. |
| Direct debug launch | No, unless the debug path validates | Yes | Only use if the build exposes such a path. |

## Build the level

Create the mod project in UE4 4.17.2 and save the level as:

```text
/Game/Stage/STG042/Maps/STG042
```

The `.umap` must reference SC6 stage classes by native class name so the cooked
package resolves against `SoulcaliburVI.exe` at runtime. For first-pass authoring,
stub only the documented class names and keep behavior simple:

| Actor/class | Purpose |
|---|---|
| `ALuxBattleStage` | Root stage actor. |
| `ALuxBattleStageActorManager` | Owns the nine documented actor lists at `+0x388..+0x408`. |
| `ALuxStageMeshActor` | Visible geometry and ordinary UE4 `BodySetup` collision. |
| `ALuxStageBreakableBarrierActor` | Boundary/barrier bridge actors; verify the deterministic buffer after load. |
| `ALuxStageBreakableWallActor` | Optional visible breakable wall/set-piece actors. |

Do not assume actor count equals gameplay collision capacity. The scbattle ring
boundary is a fixed 12-entry `g_aScbattleStageInfoBarrierEntries` buffer, and
terrain/wall/ring tags use the separate `J_StgHitChkData` path. The actor lists
and collision layers are documented in [Stage System: UE4 actor and BodySetup collision](../sc6/stage-system.md#ue4-actor-and-bodysetup-collision).

For visual mesh collision, use UE4's normal FBX collision names:

| Prefix | UE4 import becomes |
|---|---|
| `UCX_<MeshName>_NN` | `FKConvexElem` |
| `UBX_<MeshName>_NN` | `FKBoxElem` |
| `USP_<MeshName>_NN` | `FKSphereElem` |
| `UCP_<MeshName>_NN` | `FKSphylElem` capsule |

This fixes camera, particles, overlaps, and visual collision. It does not by
itself author rollback-safe wall, ring-out, or terrain-tag data.

## Lay out the content

Keep the cooked assets under the same `/Game/Stage/<code>/...` tree as the map.
A minimal project-side layout might look like this:

```text
Content/
  Stage/
    STG042/
      Maps/
        STG042.umap
      Meshes/
        SM_STG042_Floor.uasset
        SM_STG042_Wall.uasset
      Materials/
        MI_STG042_Stone.uasset
      Textures/
        T_STG042_Stone_D.uasset
```

After cooking for Windows, the source files usually live under:

```text
C:\SC6StageMod\Saved\Cooked\WindowsNoEditor\SC6StageMod\Content\Stage\STG042\...
```

The pak destination paths should land under the game's `Content` tree. Do not
put `/Game` in the UnrealPak destination; `/Game` is the runtime mount alias for
`SoulcaliburVI/Content`.

Example `filelist.txt`:

```text
"C:\SC6StageMod\Saved\Cooked\WindowsNoEditor\SC6StageMod\Content\Stage\STG042\Maps\STG042.umap" "../../../SoulcaliburVI/Content/Stage/STG042/Maps/STG042.umap"
"C:\SC6StageMod\Saved\Cooked\WindowsNoEditor\SC6StageMod\Content\Stage\STG042\Maps\STG042.uexp" "../../../SoulcaliburVI/Content/Stage/STG042/Maps/STG042.uexp"
"C:\SC6StageMod\Saved\Cooked\WindowsNoEditor\SC6StageMod\Content\Stage\STG042\Maps\STG042_BuiltData.uasset" "../../../SoulcaliburVI/Content/Stage/STG042/Maps/STG042_BuiltData.uasset"
"C:\SC6StageMod\Saved\Cooked\WindowsNoEditor\SC6StageMod\Content\Stage\STG042\Meshes\SM_STG042_Floor.uasset" "../../../SoulcaliburVI/Content/Stage/STG042/Meshes/SM_STG042_Floor.uasset"
"C:\SC6StageMod\Saved\Cooked\WindowsNoEditor\SC6StageMod\Content\Stage\STG042\Materials\MI_STG042_Stone.uasset" "../../../SoulcaliburVI/Content/Stage/STG042/Materials/MI_STG042_Stone.uasset"
```

Include only sidecars that cooking actually produced (`.uexp`, `.ubulk`, built
lighting data, mesh/material dependencies, and so on). A missing dependency can
look like an AssetManager failure even when the map package is in the right
place.

For stage-only work, do not add `/Game/Battle/{hdr,mot,cpu,hit,AssetPaths}/`
files unless you are also changing character data. Those pak-loaded binary file
families are separate from stage maps; see [On-disk Battle Data Files](../sc6/on-disk-files.md).

## Pack and install

Build the pak:

```bat
UnrealPak.exe pakchunk999-WindowsNoEditor_P.pak -create=filelist.txt -compress
```

Install it under:

```text
<Steam>\steamapps\common\SoulcaliburVI\SoulcaliburVI\Content\Paks\~mods\
```

Before launching, inspect the pak:

```bat
UnrealPak.exe pakchunk999-WindowsNoEditor_P.pak -List
```

The list should include entries like:

```text
../../../SoulcaliburVI/Content/Stage/STG042/Maps/STG042.umap
../../../SoulcaliburVI/Content/Stage/STG042/Meshes/SM_STG042_Floor.uasset
```

If those paths are wrong, fix the pak before debugging hooks.

## Get the code to the load path

Choose the smallest hook route that proves the layer you are testing.

### Option A: late redirect after a stock stage pick

Use this for the first proof of life.

Pick any stock stage in the menu, then hook
`ApplyBattleSettingDataTableToBattleManager @ 0x140594eb0` or the
`LuxDataTable_LookupByKey("StageSetting.StageCode", ...)` site inside it. Rewrite
the resolved string to `STG042` before `LuxBattle_KickStageAssetPreload`.

This does not add UI. It only proves that the custom code can reach the native
load chain and that the AssetManager can find the map.

Quality gate: log the original code, the rewritten code, and the point where the
preload function sees `STG042`. The exact instruction site is build-specific and
needs native validation before you ship the hook.

### Option B: launcher-level rewrite

Hook the launch handoff before the battle settings are applied. The documented
native path is `ULuxUIBattleLauncher::Start @ 0x1405eeb50`, which copies
`StageSetting` into the BattleManager setup table, and
`ULuxUIBattleLauncher::GetBattleStageCode @ 0x1405b0c60`, which reads
`StageSetting.StageCode`.

This can be a good UE4SS route if your runtime inspection can see the relevant
UFunction or launcher object. The exact Blueprint widget/property path that
writes the stage selection is not documented here; discover it at runtime rather
than hardcoding an unverified path.

Quality gate: prove the final `StageSetting.StageCode` value immediately before
`ApplyBattleSettingDataTableToBattleManager` runs.

### Option C: add a real picker entry

Use this after the map loads through Option A or B.

1. Hook `InitGlobalLuxStageMasterEnumStringTable @ 0x140149720` and append an
   `FBattleStageEnumEntry` with your display loc id and `StageCode = "STG042"`.
2. Add or hook the picker UI path so the new code appears in the selectable
   list. The picker validation path can call `IsValidStageCodeStr_LookupInMasterEnum`.
3. Provide display text by adding the appropriate loc data or by special-casing
   `GetStageLocIdByStageCode @ 0x1406415b0`.

Appending the master enum is also what lets `GetStageCodes_BuildMasterList` see
the new code for random-pool work. See [Stage System: master enum table](../sc6/stage-system.md#master-enum-table)
and [Stage System: DLC availability gate](../sc6/stage-system.md#dlc-availability-gate).

### Option D: direct debug launch

If your build or tooling exposes a direct battle launch with an explicit stage
code, pass `STG042` and bypass the picker. Treat this as a test harness, not a
documented retail UI flow, unless you have confirmed the exact entry point.

## Optional metadata and collision data

Start with a map-only load. Add these pieces only when the simpler layer is
verified.

| Need | Conservative path | Validation required |
|---|---|---|
| Different round positions, center, ring edge, wall metadata, or camera DOF | Add a `StageInfoTable` row for the custom code. | Verify row lookup at round start. Missing per-character `StageInfoTable` data is documented as graceful, but custom rows still need table-path validation. |
| Custom UE4 collision, camera collision, overlaps, particles | Cook valid static-mesh `BodySetup.AggGeom` via `UCX_` / `UBX_` / `USP_` / `UCP_` meshes. | Walk the whole map and test camera/overlap behavior. |
| Custom deterministic ring boundary | Author barrier actors and inspect or patch the 12-entry scbattle buffer. | Runtime-check `g_aScbattleStageInfoBarrierEntries @ 0x144844070`; actor placement alone is not proof. |
| Custom terrain height, wall tags, or ring-edge tags | Route paired `ESA_HitData` / `ESA_HitData2` raw assets through `ULuxStageAssetPaths`, or substitute A/B blobs with a native hook. | New-code `ULuxStageAssetPaths` discovery is not documented as a finished cookbook path. Validate the exact asset path/identifier and both A/B blob pointers at runtime. |

For a no-DLL content replacement of stock raw hit data, follow
[Replace a Stage: optional raw hit data](replace-stage.md#optional-replace-raw-hit-data).
For the underlying structures, see [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid)
and [Structures: ULuxStageAssetPaths](../sc6/structures.md#uluxstageassetpaths-luxstagerawasset-and-luxstagesetting).

## Verify

Use this checklist in order:

1. `UnrealPak.exe -List` shows `../../../SoulcaliburVI/Content/Stage/STG042/Maps/STG042.umap`
   and every dependency the map references.
2. The pak filename ends in `_P.pak` and the game log shows it mounted from
   `Content/Paks/~mods/`.
3. Your hook logs the final selected code as `STG042` before stage preload.
4. UE4SS or game logs show the expected load sequence:

   ```text
   [UUILoadManager]:LoadMap:STG042
   [UUILoadManager]:Preloaded:STG042 Started!
   [UUILoadManager]:Preloaded:STG042 Completed!
   [UUILoadManager]:LoadedMap:STG042
   ```

5. The level appears in battle and does not fall back to the stock stage.
6. Camera collision, mesh collision, actor overlaps, and round transitions work.
7. If barriers or walls matter, inspect the scbattle 12-entry barrier buffer or
   hook the documented getter/setter path.
8. If raw hit data matters, inspect both A/B `J_StgHitChkData*` pointers and
   test terrain height, wall contact, ring-out, rematch, and full stage reload.
9. For online experiments, both peers use the same pak and the same hook build.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No mount log for the pak | Wrong install folder or pak naming | Put the pak under `SoulcaliburVI/Content/Paks/~mods/` and keep the `_P.pak` suffix. |
| `LoadMap` still names the stock code | Hook ran too early, too late, or the code was overwritten afterward | Log the code at the hook and immediately before `LuxBattle_KickStageAssetPreload`. |
| Picker rejects the custom code | Master enum table was not appended | Append `FBattleStageEnumEntry` in `InitGlobalLuxStageMasterEnumStringTable` before picker validation runs. |
| Picker entry appears with bad or missing text | Loc id is missing or `GetStageLocIdByStageCode` returns an unresolved id | Add a valid localized string or hook the loc-id lookup for the custom code. |
| `Root Level is nullptr` or `No Sublevel Found` | AssetManager did not find a usable map package | Confirm the map package is named `STG042`, lives at `/Game/Stage/STG042/Maps/STG042`, and all cooked sidecars/dependencies are in the pak. |
| Map load starts, then crashes during package load | Cooked with the wrong UE version, missing dependencies, or native class references do not resolve | Recook with UE4 4.17.2, inspect load errors, and verify the stubbed SC6 class names. |
| Code resolves to a DLC-looking path | The custom code contains a DLC routing substring | Rename the code to a substring-safe value such as `STG042` and update folder/map names. |
| Map loads, but floor/camera collision fails | Static mesh `BodySetup` collision did not cook | Reimport meshes with `UCX_`, `UBX_`, `USP_`, or `UCP_` collision and recook. |
| Visual collision works, but ring-out/wall behavior is stock | Only the UE4 collision layer changed | Work on scbattle barrier entries or `J_StgHitChkData`; see the replacement-stage collision notes. |
| More barrier segments are ignored or behave unpredictably | The deterministic barrier buffer is fixed at 12 entries | Collapse the boundary to 12 segments or use a native patch that updates every consumer safely. |
| Custom raw hit data appears ignored | `ULuxStageAssetPaths` lookup, identifier, or A/B raw asset paths are wrong | Prove the raw asset lookup first with runtime inspection before editing blob bytes. |
| Online match desyncs at stage load | The other peer cannot resolve the same code/map or runs different hook/data | Install identical paks and hook builds on both peers; avoid online tests until local reload/rematch is stable. |

## Known limits

- A map-only pak is enough to prove AssetManager loading, but it is not enough to
  author every gameplay collision layer.
- Missing per-character `StageInfoTable` data is documented as graceful; add
  custom rows only for behavior you actually need.
- New-code `ULuxStageAssetPaths` authoring is not yet a fully documented
  no-hook workflow. For terrain/wall/ring-tag experiments, label the exact asset
  lookup and A/B blob attachment checks in your notes.
- Both peers need identical content and hook behavior for online play. The host
  broadcasts the resolved stage code; the client must load the same map primary
  asset or the match can desync at stage load.

## Related

- [Stage System](../sc6/stage-system.md) - master enum, stage-code routing,
  AssetManager load chain, actor lists, scbattle storage, and raw hit-data path.
- [Replace a Stage](replace-stage.md) - simpler stock-slot workflow with
  concrete replacement pak paths and collision-layer diagnostics.
- [Structures: stage geometry](../sc6/structures.md#stage-geometry) - native
  structures for stage actors, `ULuxStageAssetPaths`, scbattle globals, and
  `J_StgHitChkData`.
- [On-disk Battle Data Files](../sc6/on-disk-files.md) - separate
  `/Game/Battle/` character-data file families that a stage-only pak should not
  modify.
