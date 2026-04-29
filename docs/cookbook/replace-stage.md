# Recipe: Replace an existing stage

**Goal**: ship a custom map by overriding a stock stage's `.umap` — no DLL
hook required.

**Requires**: UE4 4.18 editor (matching SC6's engine version), UnrealPak.exe,
basic Blender → UE4 FBX workflow. Optionally UAssetGUI for editing the
`StageInfoTable` row.

## Pick a target stage

| Recommended | Why |
|---|---|
| `STG004` | Free Stage — visually generic, no `_R`/`_V` variants share the path |
| `STG003` | Same |
| `STG013` | Same |

Avoid `STG001`, `STG006`, `STG011`, `STG015`, `STG017` — they have variant
codes (`_R`, `_V`) that share the same UMAP path through the substring router
in `ResolveStageCodeToAssetPath @ 0x140641840`.

## Build the level

The level needs a specific actor hierarchy. Stub the SC6 classes in your UE4
project (just inherit from `AActor` with the right names):

- `ALuxBattleStage` (root)
  - `ALuxBattleStageActorManager` (manages the 9 actor lists at `+0x388..+0x408`)
  - 1+ `ALuxStageMeshActor` — visual + collision
  - 4–8 `ALuxStageBreakableBarrierActor` — invisible boxes forming the ring boundary
  - 0+ `ALuxStageBreakableWallActor` — visible breakable walls (optional)

The barrier boxes are the gameplay ring-out trigger — their box-component
extents are what gets pushed into `g_scbattle_StageInfo_BarrierArray @ 0x144844070`
at match start.

For visual collision (camera, particle, character proximity), give each
`ALuxStageMeshActor.StaticMesh` a custom `BodySetup`. In Blender, name the
collision meshes:

| Prefix | UE4 import becomes |
|---|---|
| `UCX_<MeshName>_NN` | `FKConvexElem` |
| `UBX_<MeshName>_NN` | `FKBoxElem` |
| `USP_<MeshName>_NN` | `FKSphereElem` |
| `UCP_<MeshName>_NN` | `FKSphylElem` (capsule) |

UE4's FBX importer auto-routes these into `StaticMesh.BodySetup.AggGeom`.

## Save and cook

1. Save the level as `STG004.umap` at content path
   `/Game/Stage/STG004/Maps/STG004`.
2. (Optional) Open the `StageInfoTable` .uasset in UAssetGUI and edit the
   row for `STG004` if your ring shape differs from stock.
3. Cook the project for Windows.

## Pack into a `_P.pak`

```bat
UnrealPak.exe pakchunk999-WindowsNoEditor_P.pak -create=filelist.txt -compress
```

Where `filelist.txt` lists your cooked `.uasset`/`.uexp` files relative to
their pak root.

## Install

Drop the resulting `pakchunk999-WindowsNoEditor_P.pak` into:

```text
<Steam>/steamapps/common/SoulcaliburVI/SoulcaliburVI/Content/Paks/~mods/
```

The `~mods/` subfolder is a community convention — UE4's pak system mounts
recursively and the `_P` suffix gives your pak load priority over the stock
asset.

## Verify

1. Launch the game.
2. Pick `STG004` in stage select. Your custom level should load instead of
   "Free Stage".
3. Check the in-game ring-out boundary matches your `ALuxStageBreakableBarrierActor`
   placements. If characters fall through the floor, your `BodySetup` collision
   isn't cooking — verify the `UCX_/UBX_` prefix names on import.

## Related

- [Stage System](../sc6/stage-system.md) — full reference for the stage
  pipeline, including how to add a wholly new stage (Approach B) and the
  scbattle gameplay-engine collision globals.
- The Ghidra plate on `LuxBattle_CreateStageInfoHandler @ 0x1403c3010`
  documents the Blender-side collision pipeline in detail.
