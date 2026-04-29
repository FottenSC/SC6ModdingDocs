# Recipe: Load a wholly new custom stage

**Goal**: ship a `.umap` with a brand-new stage code (e.g. `STGMOD`) and
trigger the game to load it, without replacing any stock stage.

**Requires**: UE4 4.18 editor, UnrealPak.exe, UE4SS (or a native injector) for
the runtime hook. Optional: UAssetGUI for editing data tables.

## Why this needs more than a `_P.pak`

Asset *discovery* is free — UE4's AssetManager indexes any `.umap` mounted
under `/Game/` as a `Map`-type primary asset. But the game's normal flow
only ever asks the AssetManager to load codes that came out of the Blueprint
stage picker, which validates against the static master enum table. So the
question is: **how does your custom code reach `StageSetting.StageCode` in
the LuxDataTable?** That's the actual hard part.

The C++ load chain itself does not care:

```text
ApplyBattleSettingDataTableToBattleManager (0x140594eb0)
  reads StageSetting.StageCode (FString)
   ↓
LuxBattle_KickStageAssetPreload (0x14064d940)
   ↓
UUILoadManager_PreloadStageAssets (0x142f124f0)
   ↓
UAssetManager.RequestAsyncLoad("Map", "<your code>")
```

No native call to `IsValidStageCodeStr_LookupInMasterEnum`,
`ResolveStageCodeToAssetPath`, or any other gate. If the AssetManager finds
the umap, the game loads it.

## Step 1 — Build the umap

Stub `ALuxBattleStage`, `ALuxBattleStageActorManager`, `ALuxStageMeshActor`,
`ALuxStageBreakableBarrierActor` in a UE4 4.18 project. The required hierarchy:

- `ALuxBattleStage` (root actor)
- `ALuxBattleStageActorManager` (it manages the 9 actor lists at
  `+0x388..+0x408` — see [Stage System](../sc6/stage-system.md))
- 1+ `ALuxStageMeshActor` (visuals + collision)
- 4–8 `ALuxStageBreakableBarrierActor` (invisible boxes — the ring-out
  boundary; their box transforms become the gameplay-engine
  `g_scbattle_StageInfo_BarrierArray` at match start)
- (Optional) `ALuxStageBreakableWallActor` (breakable walls)

For collision on the visual meshes use Blender naming:

| Prefix | UE4 → BodySetup |
|---|---|
| `UCX_<MeshName>_NN` | `FKConvexElem` |
| `UBX_<MeshName>_NN` | `FKBoxElem` |
| `USP_<MeshName>_NN` | `FKSphereElem` |
| `UCP_<MeshName>_NN` | `FKSphylElem` |

Save as `STGMOD.umap` at content path `/Game/Stage/STGMOD/Maps/STGMOD`.

## Step 2 — Pick a code without DLC-substring conflicts

Avoid these substrings — `ResolveStageCodeToAssetPath @ 0x140641840` will
misroute them to a DLC pak path if a Blueprint ever calls it on your code:

```text
014  _V  016  006_R  011_R  015  017  018
```

Safe: `STGMOD`, `STG999`, `STGCUSTOM01`, `STG042`.

## Step 3 — Pack into a `_P.pak`

```bat
UnrealPak.exe pakchunk999-WindowsNoEditor_P.pak -create=filelist.txt -compress
```

`filelist.txt` lists your cooked `.uasset`/`.uexp`/`.umap` files. Drop the
resulting pak into:

```text
<Steam>/steamapps/common/SoulcaliburVI/SoulcaliburVI/Content/Paks/~mods/
```

## Step 4 — Trigger the load (one of these)

### Option A: BP-level override after stage select (simplest)

Pick any stock stage in the menu, then hook the BP path that writes
`StageSetting.StageCode` and substitute your code. Concretely: hook
`ApplyBattleSettingDataTableToBattleManager @ 0x140594eb0` near the
`LuxDataTable_LookupByKey("StageSetting.StageCode", ...)` call (around
RVA `+0x140595400` inside the function) and rewrite the resolved string
to `"STGMOD"` before the preload kick.

This needs zero UI work. Pick "Free Stage" → load STGMOD.

### Option B: Add to the picker

Hook `InitGlobalLuxStageMasterEnumStringTable @ 0x140149720` once at
startup. After the original 31 entries are appended, push a new
`FBattleStageEnumEntry { DisplayLocId; StageCode; }` for your code. The
picker UI reads from `g_LuxStage_MasterEnumStringTable @ 0x144149c50` so
your code shows up.

The DLC chunk filter (`GetStageCodesIfAvailable_FilterByDLCChunks`) only
gates substrings of the DLC suffixes listed above, so a custom code with
none of them auto-passes.

You'll also want a localised display string for the picker label —
`GetStageLocIdByStageCode @ 0x140641680` returns the loc ID, so add
your own row to the loc table or hook the function to special-case
your code.

### Option C: Direct console / debug entry

If the build retains a way to launch a battle with an explicit stage code
(some debug menus do), bypass the picker entirely and pass `STGMOD` as the
stage-code argument.

## Step 5 — Verify

1. Launch the game with the mod pak installed.
2. Trigger the load via your chosen Option.
3. Watch the UE4SS log for:
   ```
   [UUILoadManager]:LoadMap:STGMOD
   [UUILoadManager]:Preloaded:STGMOD Started!
   [UUILoadManager]:Preloaded:STGMOD Completed!
   [UUILoadManager]:LoadedMap:STGMOD
   ```
4. If you see `Root Level is nullptr` or `No Sublevel Found` instead, the
   AssetManager didn't find your umap — verify the pak mounted (check
   `[FPakFile] Mounted Pak File ...` log lines) and the umap is at exactly
   `/Game/Stage/STGMOD/Maps/STGMOD`.

## Known gotchas

- **No `StageInfoTable` row** — the per-character lookup
  (`LuxMoveProvider_LoadStageInfo_FromTable @ 0x1403e2370`) fails gracefully;
  characters just won't have stage-specific corner/wall interaction quirks.
  No crash.
- **No `LuxBattleStageInfoTableRow` data** — the global stage info table is
  similarly forgiving. Add a row only if you need custom Center/RingEdge/Wall
  configuration.
- **Online play** — both peers need the mod installed and built identically.
  The host broadcasts the resolved stage code; the client's AssetManager
  must succeed at loading the same code or the match desyncs at stage load.

## Related

- [Stage System](../sc6/stage-system.md) — full reference for the stage
  pipeline, the two-tier collision system, master enum bias, and the
  `LuxBattleStageInfoTableRow` schema.
- [Replace a Stage](replace-stage.md) — even simpler if you don't need a new
  code, just custom geometry on a stock slot.
