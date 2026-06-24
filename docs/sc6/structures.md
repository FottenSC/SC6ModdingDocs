# Game Structures

Reversed class layouts and offsets, cited against Ghidra addresses on the SC6 Steam build
(image base `0x140000000`).

## Struct index

Alphabetical jump table. Click through for full layout.

### Battle / hit-resolution

| Struct | Size | Purpose |
|--------|------|---------|
| [`ALuxBattleChara`](#aluxbattlechara) | `0x568` | One fighter on stage. Three KHit list heads at `+0x44478/+0x44498/+0x444B8`. |
| [`ALuxBattleManager`](#aluxbattlemanager) | (large) | Per-match actor; player chara list, axis input, config tree at `+0x50`. |
| [`ALuxBattleFrameInputLog`](#aluxbattleframeinputlog-17616-bytes) | `~0x44D0` | Input record/replay actor; embedded per-slot input cache at `+0x3C0`, inbound-packet deque at `+0x4480`. |
| [`FLuxReplayInputCacheEntry`](#fluxreplayinputcacheentry-16-bytes) | `0x10` | One slot in `pReplayInputCache_at0x3C0`. |
| [`ALuxBattleKeyRecorder`](#aluxbattlekeyrecorder-956-bytes) | `0x3BC` | Training-mode "Recorded" input playback. |
| [`ALuxBattleReplayPlayer`](#aluxbattlereplayplayer-977-bytes) | `0x3D1` | Replay playback actor. |
| [`ALuxTraceManager`](#aluxtracemanager) | `0x408` | **Visual-only** weapon-trail driver. |
| [`FActiveAttackSlot`](#factiveattackslot-68-bytes) | `0x44` | Per-tag active-attack hash slot at `chara+0x3D0`. |
| [`FKHitNodeBase`](#fkhitnodebase-36-bytes-header-view) / [`FLuxKHitNode`](#fluxkhitnode-variable-size-node-view) | Sphere `0x80`; Area/FixArea `0xA0` | KHit linked-list node — shared header plus subclass tails. |
| `FLuxBattleChara` (Ghidra type) | `0x973F0` | Big-struct view of a fighter's runtime state — same entity as [`ALuxBattleChara`](#aluxbattlechara), with wider field coverage. (Previously documented as `0x97330`; the Ghidra struct now reports `0x973F0` = 619504 bytes.) |
| [`FLuxBattleCharaVisibilityFlags`](#fluxbattlecharavisibilityflags-7-bytes) | `0x07` | 7-byte mesh visibility bitfield. |
| [`FLuxBattleVMFreezeRecord`](#fluxbattlevmfreezerecord-64-bytes) | `0x40` | Slow-motion / VM-freeze blend state. |
| [`LuxBattleCharaMotionFlags`](#luxbattlecharamotionflags-64-bytes) | `0x40` | 64-byte motion-input flag bank at `chara+0x16D0..+0x170F`. Holds the guard-stance bytes (`+0x02 base`, `+0x2C alt`, `+0x31 alt-locked`) and other state flags. |
| [`FLuxCapsule`](#fluxcapsule) | `0x50` | Trace-system capsule endpoint pair (visual). |
| [`FLuxCapsuleContainer`](trace-system.md#fluxcapsulecontainer-0x40-bytes-legacy-view) / [`FLuxMoveProvider_CapsuleSlot`](#fluxmoveprovider_capsuleslot-64-bytes) | `0x40` | TArray-shaped wrapper around `FLuxCapsule*`. |
| [`FLuxDamageInfo`](#fluxdamageinfo-18-bytes) | `0x12` | HUD/network hit-event payload. |
| [`FTraceActiveParam`](#ftraceactiveparam-0x30-bytes) | `0x30` | Param to `ALuxBattleChara::Active` (only `+0x00 AttackTag` matters). |
| [`FTraceInactiveParam`](#ftraceinactiveparam-0x8-bytes) | `0x08` | Param to `ALuxBattleChara::Inactive`. |
| [`ULuxTraceComponent`](#uluxtracecomponent) | `0x4B0` | Visual trail renderer. |
| [`ULuxTraceDataAsset`](#uluxtracedataasset) | `0x80` | Trace-parts data asset (with three dead `bDebugDrawTrace*` bools). |

### Move VM

| Struct | Size | Purpose |
|--------|------|---------|
| [`FLuxMoveCommandPlayer`](#fluxmovecommandplayer-12332-bytes) | `0x302C` | Per-chara VM context (the "slot" indexed by `g_LuxMoveVM_CommandPlayerArray`). |
| [`FLuxMoveVM_OpcodeScratch`](#fluxmovevm_opcodescratch-96-bytes) | `0x60` | 96-byte view over `vmCtx+0x26AC..+0x26E4` (the per-opcode scratch). |
| [`FLuxMoveVM_ATKPayload`](#fluxmovevm_atkpayload-16-bytes) | `0x10` | 4-uint32 `(power, range, speed, dir_mask)` tuple. |
| [`FLuxMoveBank`](#fluxmovebank-48-bytes) | `0x30` | Per-character move-bank header at `chara+0x455C0`. Bucket headers + sub-table offsets. |
| [`FLuxMoveBankSlotView`](#fluxmovebankslotview-72-bytes) | `0x48` | View into a slot record returned by `ResolveBankSlot`. Holds the variant→cell-bone-id table. |
| [`FLuxMoveBankCell`](#fluxmovebankcell-112-bytes) | `0x70` | One row of the per-character move bank. The "attack cell" the hit pipeline consumes. |
| [`FLuxMoveDefEntry`](#fluxmovedefentry-16-bytes) | `0x10` | One entry in the FMoveDef array (table indexed by current move id). `+0x02` = StartCellCursor. |
| [`FLuxMoveSchedState`](#fluxmoveschedstate-96-bytes) | `0x60` | Dual-slot move scheduler. |
| [`FLuxMoveStartRequest`](#fluxmovestartrequest-108-bytes) | `0x6C` | "Queue this move" request. |
| [`FLuxMoveSubFrameRecord`](#fluxmovesubframerecord-72-bytes) | `0x48` | 60→120 Hz sub-frame interpolation record. |
| [`FLuxMoveLane`](#fluxmovelane-1128-bytes-was-luxmovelanestate) | `0x468` | Per-lane VM state; three lanes per chara at `+0x444F0/+0x44958/+0x44DC0`. Holds `nNextMoveID_5A` (immediate-transition target), `flTransitionThreshold_68`, `aEffectOpTable_1F4[16]`. |
| [`FLuxMoveLane_EffectOp`](#fluxmovelane_effectop-36-bytes) | `0x24` | One entry of the lane's 16-slot effect-op table; `(triggerFrame, argc, fired, args[16])`. |
| [`LuxMoveLaneState_Motion`](#luxmovelanestate_motion-68-bytes-the-small-motion-playback-record) | `0x44` | Small per-motion-slot playback record (Ghidra type `FLuxMoveLaneState`). Pointed to from the two motion slots inside `FLuxMoveLane`. |
| [`FLuxAttackTouchParam`](move-system.md#fluxattacktouchparam-0x20-bytes) | `0x1D` | Hit-registered struct. |
| [`FLuxBattleMoveListTableRow`](move-system.md#fluxbattlemovelisttablerow-0x88-bytes) | `0x88` | UI move-list row. |

### Camera

| Struct | Size | Purpose |
|--------|------|---------|
| [`APlayerCameraManager` POV](#aplayercameramanager-pov-the-live-render-source) | (engine class) | The render-source. POV at `+0x410..+0x44B`. |
| [`ALuxBattleCamera_PoseFields`](#aluxbattlecamera_posefields-34-bytes) | `0x22` | Packed pose snapshot. |
| [`FCameraCacheEntry_PCM_0x400`](#fcameracacheentry_pcm_0x400-55-bytes) | `0x37` | PCM-style cache entry, customised. |
| [`FLuxBattleCameraInternalPOV`](#fluxbattlecamerainternalpov-56-bytes) | `0x38` | Internal POV transform. |
| [`FLuxCameraAction`](#fluxcameraaction-740-bytes) | `0x2E4` | Camera action snapshot. |

### Engine / line drawing

| Struct | Size | Purpose |
|--------|------|---------|
| [`UWorld`](#uworld) | (engine) | `+0x40/+0x48/+0x50` line batchers; `+0xF0` `AuthorityGameMode`; `+0x140` `OwningGameInstance`. |
| [`ULineBatchComponent`](#ulinebatchcomponent) | `0x850` | Three append arrays at `+0x808/+0x818/+0x830`. |
| [`FBatchedLine`](#fbatchedline-0x34-bytes) | `0x34` | Single line entry. |
| [`TArrayHeader`](#tarrayheader-16-bytes) | `0x10` | UE4 `{Data, Num, Max}` triple. |

### Stage geometry

| Struct | Size | Purpose |
|--------|------|---------|
| [`scbattle_BarrierEntry`](#scbattle-stage-info-globals) | `0x10` | One deterministic ring-boundary segment. Fixed array of 12 at `0x144844070`. |
| [`scbattle_StageBoundaryParams`](#scbattle-stage-info-globals) | `0x40` | Stage origin, spawn offsets, and facing angles. |
| [`scbattle_StageInfoParam`](#scbattle-stage-info-globals) | `0x120` | Whole scbattle stage-info block: seed, boundary params, flags, 12 barrier entries. |
| [`FLuxBattleEventRecord`](#stage-actor-registration-event-record) | `0x18` | Event packet used by stage barrier/wall registration event class `0x19`. |
| [`ULuxStageAssetPaths`](#uluxstageassetpaths-luxstagerawasset-and-luxstagesetting) | class | Per-stage content-side asset list. `RawAssets` names hit-data/camera raw assets. |
| [`LuxStageRawAsset`](#uluxstageassetpaths-luxstagerawasset-and-luxstagesetting) | `0x18` | `{ELuxStageAssetType Type; FString Path;}` entry in `ULuxStageAssetPaths.RawAssets`. |
| [`LuxStageSetting`](#uluxstageassetpaths-luxstagerawasset-and-luxstagesetting) | `0x03` | Three content-side cosmetic flags: anomaly VFX, wet, breath. |
| [`LuxBattle_FrameCacheHitChkDataSetup`](#j_stghitchkdata-frame-cache-setup) | `0x22` | Setup packet that seeds the A/B `J_StgHitChkData*` globals. |
| [`J_StgHitChkData_*`](#j_stghitchkdata-serialized-terrainwall-blob) | variable | Serialized legacy terrain/wall collision blob expanded into frame-bounds grids. |
| [Frame-bounds grid](#frame-bounds-grid) | (`>=0x44b`) | Runtime terrain/wall spatial acceleration for VM predicates and wall collision. |
| [`FLuxFrameBoundsCellRow`](#fluxframeboundscellrow-32-bytes-and-fluxterraintriangleentry-64-bytes) | `0x20` | Cell row in the bounds grid. |
| [`FLuxTerrainTriangleEntry`](#fluxframeboundscellrow-32-bytes-and-fluxterraintriangleentry-64-bytes) | `0x40` | Triangle entry with pre-baked plane equation. |
| `ALuxBattleStage` | `0x3a0` | Per-stage root actor; loaded from `/Game/Stage/<code>/Maps/<code>.umap`. Owns one `ALuxBattleStageActorManager`. |
| `ALuxBattleStageActorManager` | `0x420` | Manages 9 stage actor/object arrays from `+0x388..+0x408`: StageActor, WolfCharacter, BreakableWall, Barrier, HideableMesh, VisibilitySwitcher, StageMob, StageMesh, CuttableStageMesh. Populated by `LuxActor_CollectActors_By8Classes_IntoTArrays @ 0x140417a70`. See [Stage System](stage-system.md). |
| `ALuxStageMeshActor` | `0x3d0` | Visible stage mesh actor with ordinary UE4 `ULuxStageMeshComponent`/`UBodySetup` collision; visual/camera/particle layer, not deterministic scbattle terrain by itself. |
| `ALuxStageHideableMeshActor` | `0x3b0` | Stage mesh actor that can be hidden/faded by camera, LOD, or stage-state conditions. |
| `ALuxStageVisibilitySwitcher` | `0x3d0` | Stage-state visibility controller used by streamed BG/VFX/gimmick sublevels. Reflected class string is `LuxStageVisibilitySwitcher`. |
| `ALuxStageCuttableMeshBase` | `0x460` | Optional weapon-overlap sliceable mesh actor with procedural cut mesh, particles/SE, and `MinCuttableDistance`; no Soul Charge gate observed in the native slice path. |
| `ALuxStageWolfCharacter` | `0x7a0` | Optional background creature/animal actor bucket used by `WolfCharacterList`; no exact stock `.umap` usage observed in the current dump. |
| `ALuxStageBreakableBarrierActor` | `0x4f0` | Invisible box-trigger actor registered through stage event class `0x19`; deterministic ring storage is the fixed 12-entry scbattle buffer. |
| `ALuxStageBreakableWallActor` | `0x480` | Visible breakable walls (Soul Charge wall-break geometry). Standard UE4 `BodySetup` collision. |
| `FBattleStageEnumEntry` | `0x20` | One row in the master stage roster: `{FString DisplayLocId; FString StageCode;}`. 31 stock entries at `g_LuxStage_MasterEnumStringTable @ 0x144149c50`. |
| `LuxBattleStageInfoTableRow` | `0x108` | UDataTable row type; per-stage round-position config (Center, RingEdge, Wall, OptionalCenters). See [Stage System](stage-system.md#luxbattlestageinfotablerow). |
| `LuxBattleStageBasePositionParam` | `0x28` | Inner element of `LuxBattleStageInfoTableRow` arrays — `{FVector Position; FRotator Rotation; float DistanceOffset; TArray<int32> RoundNumbers;}`. |
| scbattle stage globals | `0x120` | Match-time stage-info block at `0x144844010..0x144844130`: RngSeed, StageBoundaryParams (64 B), valid flag, BarrierArray (12 × 16 B). See [Stage System](stage-system.md#stage-collision-storage). |

### Misc / discovered-but-uncategorised

`ALuxBattleManager_Partial`, `ALuxBattleManager_PropertyLayout`, `FLinearColor`, `FMatrix64`,
`FTransform64`, `FVector`, `FLuxBattleKeyRecorderSlot`, `FLuxRecordedFrame`,
`FLuxTraceManagerLayout`, `FLuxTraceComponentLayout`, `FLuxDataTablePath`. See the
[Other reversed structs](#other-reversed-structs) section.

### Net / Steam (unrelated to gameplay)

`FNamedOnlineSession_Steam`, `FOnlinePresenceSteam`, `FOnlineSessionInfoSteam`,
`FFriendStateRecord`. See [Net / Steam structs](#net-steam-structs-unrelated-to-hitbox-work).

## Template for a new entry

```
### <ClassOrStruct name>

- **Path**: `/Script/<Module>.<Class>`
- **Size**: 0x???
- **Discovered via**: <UE4SS dumper / hook / xref / …>

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| 0x00   | FName | Id | |
```

---

## Battle manager

### `ALuxBattleManager`

- **Path**: `/Script/LuxorGame.LuxBattleManager`
- **Discovered via**: `ALuxBattleManager__StaticClass @ 0x140947390`,
  `ALuxBattleManager::Update_Impl @ 0x140437590`,
  `ALuxBattleManager::PlayMove_Impl @ 0x140429840`

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x050 | `FLuxDataTable` | ConfigTable | round / timer / per-player settings tree |
| +0x098 | `UObject*` | GameState | isa-checked against `ALuxBattleManager` every tick |
| +0x388 | `UClass*` | BattleCharaClass | `TSubclassOf<ALuxBattleChara>` per `Z_Construct_UClass_ALuxBattleManager @ 0x140949450`. **Not** an embedded chara. An earlier pass of these docs called it "SubChara", but a 0x568-byte embedded chara starting here would collide with the Camera/EventListener slots at +0x3A8..+0x408 in the runtime-verified subsystem map ([battle-manager.md](battle-manager.md#camera-events)). |
| +0x390 | `ALuxBattleChara**` | PlayerCharas.Data | `TArray<ALuxBattleChara*>` — iterate `PlayerCharas[0..NumPlayerCharas-1]` for all active fighters |
| +0x398 | `int32` | NumPlayerCharas | |
| +0x3A0 | `uint8` | PendingMoveCommandType | 1 = PlayMove, 2 = Stop |
| +0x3A8 | `int32` | PendingMoveCommandParam | player index |
| +0x3B0 | `FLuxMoveCommandData` | PendingMoveCommandData | pending move-dispatch payload. `StopMove` zeroes a 0x18 local then copies it in, so the visible footprint is at least 0x18 bytes (exact size unconfirmed). |
| +0x3E0 | `bool` | SavedLuxorPhotographyAllowed | `PlayMove` caches `LuxPhotography::IsLuxorAllowed()` here and clears the CVar; `StopMove` restores the cached value. Gameplay has nothing to do with it — this slot only exists to keep Photography Mode from capturing through scripted move dispatches. |
| +0x400 | `float*` | AxisValues | dynamic float array |
| +0x408 | `int32` | AxisCount | |
| +0x410 | `uint8*` | AxisInhibitFlags | dynamic byte array |
| +0x418 | `int32` | AxisInhibitCount | |
| +0x420 | `float` | AxisXAccumulator | per-tick decay |
| +0x424 | `float` | AxisYAccumulator | per-tick decay |
| +0x508 | `UObject*` | (axis-consumer; walked by `Update`) | |
| +0x12F3 | `bool` | GlobalAxisInhibit | when set, zeroes every axis this tick |

See [Battle Manager & DataTable Config Tree](battle-manager.md) for the
UFunction map and the hierarchical config-tree path convention.

---

## Trace / hitbox system

### `ALuxBattleChara`

- **Path**: `/Script/LuxorGame.LuxBattleChara`
- **Size**: 0x568 (1384)
- **Class CRC**: `0x5BDCD706`
- **Registered via**: short-form `UE4_RegisterClass` (no property builder — see
  [Reflection Gotchas](../ue4ss/reflection-gotchas.md))
- **Discovered via**: `ALuxBattleChara__StaticClass @ 0x14015EA40`

!!! warning "Layout verified at runtime on the Steam build (2026-04-19)"
    The field table below was corrected against the **actual running
    binary** using UE4SS class-name introspection on a live chara.
    Earlier versions of this page described `chara+0x388` as the
    `ULuxBattleMoveProvider` pointer — that is **wrong on the shipping
    Steam build**. `+0x388` and `+0x390` are actually the `CharaMesh0`
    and `WeaponMesh0` `USkeletalMeshComponent*`s, stored by
    `ALuxCharaActorBase_Constructor @ 0x140440FB0` as
    `param_1[0x71]` / `param_1[0x72]`. This build has no per-chara
    `ULuxBattleMoveProvider`.

    The real opponent pointer is **`chara+0x973E8`** (not `+0x390`),
    identified by `LuxMoveVM_CheckRangeOrDistance @ 0x140365140`
    dereferencing that field to read the opponent's world-space
    position.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x6C   | `int16` | MoveClassA | SC6 move category (5..12) — `HorizontalAttack`, `VerticalAttack`, `Kick`, `Throw`, etc. |
| +0x6E   | `uint16` | MoveClassB | subclass |
| +0x70   | `int32` | MoveFlags | |
| +0x90   | `float` | flVelocityZ | Per-tick movement velocity Z. Cleared by `LuxBattle_PositionCharasSymmetrically @ 0x140302670` on round start (`pChara->flVelocityZ_at0x90 = 0.0`). |
| +0x94   | `float` | flVelocityX | Per-tick movement velocity X. Set by `LuxBattle_PositionCharasSymmetrically` to `extraout_XMM0_Da / g_LuxMoveVM_AngleSinScale` (the chara's facing-yaw projected onto a per-tick contribution). |
| +0x98   | `float` *or* `ALuxBattleManager*` | flVelocityY / BattleManager | **Aliased slot — readers disagree, and both interpretations are attested.** `LuxBattle_PositionCharasSymmetrically` writes `0.0f` here as a 4-byte float (`flVelocityY_at0x98`). `ALuxBattleChara_SetupWeaponBones @ 0x1403CAEB0` reads `param_1[0x13]` (= +0x98) as an 8-byte `ALuxBattleManager*`, ISA-checks the dereferenced UClass against `ALuxBattleManager`, then passes it to `LuxAnimInstance_SetBattleManager`. The Ghidra struct `ALuxBattleChara_Partial` types the slot as `float`. The two readers are mutually consistent only if the `BattleManager` pointer's low 4 bytes are float-`0.0` (`0x00000000`) — possible if the pointer happens to be aligned so bytes `[0x98..0x9B]` are all zero, but that would be coincidence, not the canonical layout. **Treat this slot as ambiguous until disassembly resolves which reader has the wrong offset.** |
| +0xA0   | `float` | flStartPosX | Round-spawn target X. Written by `LuxBattleChara_SetStartPosition @ 0x140301E60`. |
| +0xA4   | `float` | flStartPosY | Round-spawn target Y (Y is plane-up in SC6's world). |
| +0xA8   | `float` | flStartPosZ | Round-spawn target Z. Same float read by `LuxMoveVM_CheckRangeOrDistance` as `SelfPos.Z` for ring-distance checks (start and current Z are equal at the round-spawn instant). |
| +0xC0   | `float` | flCurPosX | Game-thread current world-pose X. Updated each tick by `LuxBattleChara_IntegratePhysics_PerTick`. |
| +0xC4   | `float` | flCurPosY | |
| +0xC8   | `float` | flCurPosZ | |
| +0x168  | `USceneComponent*` | CustomRoot0 | stored by `ALuxCharaActorBase_Constructor` `param_1[0x2D]` |
| +0x23C  | `uint8` | CharaKindByte | row index into `g_LuxCharaAttrTable_*` |
| +0x250  | `uint16` | MoveSubclassAlt | alternative move-category byte (checked `==100` / `0x69` by IF predicates) |
| +0x388  | `USkeletalMeshComponent*` | CharaMesh0 | **NOT MoveProvider.** Set by `ALuxCharaActorBase_Constructor` `param_1[0x71]`. |
| +0x390  | `USkeletalMeshComponent*` | WeaponMesh0 | **NOT Opponent.** Set by `ALuxCharaActorBase_Constructor` `param_1[0x72]`. |
| +0x398  | `float` | MaegamiL_Pos | Maegami-L (front-hair-L) position; ctor init `0` |
| +0x39C  | `float` | MaegamiR_Pos | Maegami-R position; ctor init `0` |
| +0x3A0  | `int32` | PlayerIndex | ctor init `-1`; UPROPERTY |
| +0x3A4  | `int32` | CharaID | ctor init `-1`; doubles as `SoulChargeMode` at runtime |
| +0x3A8  | `int32` | WeaponID | **NOT a TraceComponent pointer** (earlier docs claimed `ULuxTraceComponent*` here — that was wrong). Ctor init `-1`; doubles as `WeaponTypeCode` at runtime. The ctor writes `*(uint32*)(param_1+0x3A8) = 0xFFFFFFFF`, so this is clearly a 4-byte int, not an 8-byte pointer. |
| +0x3B0  | `TArray<USkeletalMeshComponent*>` | CreationComponents | UPROPERTY Instanced; `.Data/.Num/.Max` at `+0x3B0/+0x3B8/+0x3BC`. Earlier docs described an "active-attack slot hash" here with stride 0x44; the constructor initialises this block as CreationComponents, so the slot-hash interpretation was wrong. |
| +0x3C0  | `USkeletalMeshComponent*` | MaegamiL_SkeletalMeshComponent | UPROPERTY Instanced |
| +0x3C8  | `USkeletalMeshComponent*` | MaegamiR_SkeletalMeshComponent | UPROPERTY Instanced |
| +0x3D0..+0x3E7 | bytes + float | Maegami / anim-side state | anim-side bytes, phase-trigger flag, phase timer |
| +0x3E8  | `TArray<ALuxCharaAppxActor*>` | AppxActors | `.Data/.Num/.Max` at `+0x3E8/+0x3F0/+0x3F4` |
| +0x3F8..+0x447 | `TSet/TMap` (0x50) | AppxAnimInstanceMap | standard UE4 TSet layout — sparse array at `+0x3F8..+0x42F`, hash extension at `+0x430..+0x447` |
| +0x448  | `UBoxComponent*` | CollisionComponent | **type is `UBoxComponent*`, not `UShapeComponent*`** (the FName used at construction is `"TestCollision"` but the field is named `CollisionComponent`). Stored by `ALuxBattleChara_Constructor` `param_1[0x89]`. UPROPERTY Instanced. |
| +0x450  | `uint32` | BreakFlag | UPROPERTY EditAnywhere; cleared by vtable[201] `ResetBreakAndAttackState` |
| +0x458  | `ALuxTraceManager*` | TraceManager | **visual-only** — drives the weapon-trail / FX. Not part of hit resolution. |
| +0x460  | `ULuxBattlePlayerSetup*` | PlayerSetupOverride | UPROPERTY; weapon-data cache pointer |
| +0x468  | `bool` | bDummyPlayer | UPROPERTY, ctor init `false` |
| +0x469  | `bool` | bEvilFlag | controls MoveProvider sub-object selection |
| +0x470..+0x4BF | `TSet` (0x50) | EntityTracking | internal non-UPROPERTY |
| +0x4C0..+0x50F | `TSet` (0x50) | (unnamed internal) | non-UPROPERTY |
| +0x510  | `TArray<ELuxPartsSE>` | SEMaterials | UPROPERTY; `.Data/.Num/.Max` at `+0x510/+0x518/+0x51C` |
| +0x520  | `TArray<FWeakObjectPtr+...>` | (internal anim-inst array) | stride 16B |
| +0x530..+0x537 | 8 bytes | setup/phase flag block | see constructor plate for per-byte meaning |
| +0x538  | `bool` | IsSetupCompleted | ctor init `false`; cleared by TearDown |
| +0x548  | `TArray<FLuxPermanentEffectRuntime>` | PermanentEffects | `.Data/.Num/.Max` at `+0x548/+0x550/+0x554` |
| +0x558  | `TSharedPtr<BoneDB>.DataPtr` | (bone-DB cache) | |
| +0x560  | `TSharedPtr<BoneDB>.RefCtrl` | (bone-DB cache) | |
| +0x568  | — | **end of object** | `sizeof(ALuxBattleChara) = 0x568` |
| +0x29130 | `void*` | pSubcompListHead | Sub-component linked-list head walked by `LuxBattleChara_SetStartPosition @ 0x140301E60`. Each node has `next` at `+0x40`, an inner array pointer at `+0x48`, and a count byte at `+0x50`; the inner walk only writes a 16-bit zero at each item's `+0x7C`. Useful as a **"chara fully constructed"** sentinel: when null, the chara is mid-rebuild (e.g. immediately after a character swap), and `SetStartPosition` will walk the list and crash on a null deref (raising the 0xE06D7363 unhandled C++ exception). HorseMod's `ResetOverride` validates this slot before invoking the engine's teleport helper. |
| +0x1438 | `UObject*` | cached MoveComponent | Lazy cache filled by `ALuxBattleChara_GetMoveProvider @ 0x1403F00B0`. Chain: `chara->GetWorld()->OwningGameInstance (world+0x140) → ISA-check ULuxGameInstance → *(ULuxGameInstance+0x140)`. On this build the final read returns the IEEE 754 value `0x3F800000` (float `1.0f`), not a pointer, so the cache stays at sentinel (`0xFFFFFFFF_FFFFFFFF`) indefinitely. The misnamed Ghidra symbol `ALuxBattleManager_GetMoveProviderPtr @ 0x140546600` actually operates on a `ULuxGameInstance*`, not an `ALuxBattleManager*`. Note that `+0x1438` is **past the `0x568` class size**: either the lazy cache lives in a separately-allocated extension, or `0x568` understates the actual live size. Under active investigation. |
| +0x1463 | `uint8` | current move-state byte | set by `ALuxBattleManager_SetMoveState @ 0x1403F8370`; `5=playing`, `6=stopping` |
| +0x1982 | `uint16` | CurrentNotifToken | read by VM IF-predicate families A/B/C |
| +0x19FE | `uint16` | MoveSubclass | read by `BuildMoveClassPair` |
| +0x19F0..+0x1A64 | condition-flag ring | cleared by VM opcode `start!` (`0x50001`); read by IF-subject `0x60007..0x60058` |
| +0x2B4A4 | `int32` | MoveStateId | looked up in `g_LuxMoveStateTable @ 0x1440F4750` (0xF / 7 / 0x1C / … ) |
| +0x973E8 | `ALuxBattleChara*` | **Opponent** | direct pointer to the other player's chara — used by `LuxMoveVM_CheckRangeOrDistance` / `LuxMoveVM_CheckAngleOrGeometry` |

> source: Ghidra reversing of `ALuxBattleChara_Constructor @ 0x1403AB8D0`,
> `ALuxCharaActorBase_Constructor @ 0x140440FB0`, `ALuxBattleChara_Active_Impl
> @ 0x1408CD940`, `ALuxBattleChara_Inactive_Impl @ 0x1408D1420`,
> `LuxMoveVM_CheckRangeOrDistance @ 0x140365140`. Runtime class-name
> introspection on both live charas in a training match confirmed `+0x388`
> and `+0x390` are SkeletalMeshComponents on this Steam build.

!!! note "`ULuxBattleMoveProvider` on this build"
    Searches for `Z_Construct_UClass_ULuxBattleMoveProvider*` and for any
    literal `"LuxBattleMoveProvider"` / `"LuxBattleMoveComponent"`
    string in the shipping binary return **zero hits** — neither name
    survives as a UClass registration. The class was renamed,
    dropped, or folded into another type somewhere between the earlier dev
    snapshot the older docs described and the 2026-04-19 Steam build.

    **What's actually reachable — the four move-related slots on
    `ALuxBattleManager`** (no UE4 reflection metadata for any of these
    because `ALuxBattleManager` is registered short-form via
    `UE4_RegisterClassEx` with no UPROPERTY list — see
    `Z_Construct_UClass_ALuxBattleManager @ 0x140949450`):

    | Slot | Inferred class | Notes |
    |------|----------------|-------|
    | `BM+0x140` | `UObject*` (class unknown) | Read by the misnamed `ALuxBattleManager_GetMoveProviderPtr @ 0x140546600`, which — despite the name — takes a `ULuxGameInstance*`. Lazy-cached on every chara at `chara+0x1438` by `ALuxBattleChara_GetMoveProvider @ 0x1403F00B0`. |
    | `BM+0x1450` | `UObject*` (TSharedPtr Target) | Read by `LuxMoveProviderRef_Get @ 0x14045FC70`, which ISA-checks `world+0x98` against `ALuxBattleManager`, then fetches `(*BM+0x1450, *BM+0x1458)` as a TSharedPtr-style pair. On the target, `vtable[0x10]` is `IsValid`, `vtable[0x100]` returns the default sub-provider, and `vtable[0xE0]` returns an indexed sub-provider. Also referenced by `ALuxBattleChara` vtable slots 208 (`GetWeaponData`) and 210/211 (`GetBoneDataSharedPtr`); its role is ambiguous between a MoveProvider and a unified weapon/bone/move data asset. |
    | `BM+0x1458` | ref-count control block | Second half of the TSharedPtr pair at `BM+0x1450`. |
    | `BM+0x4C0` | `ALuxBattleMoveCommandPlayer*` | **The one slot whose class IS known** — registered name `"BattleMoveCommandPlayer"` via `Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`. This is the command-script VM actor that runs move bytecode; see [Move System](move-system.md). The per-move capsule data is believed to live inside this object, but its exact `FLuxCapsuleContainer` offset is still being located. |

    **Stale call paths to avoid** — these functions were written for an
    older layout where `chara+0x388` held a MoveProvider pointer. On
    this build `chara+0x388` is `CharaMesh0`, so they produce garbage
    or silently fail:

    - `ALuxTraceManager_GetTracePosition_Impl @ 0x1408D0BB0`
      (Ghidra-renamed; was `ALuxBattleChara_GetTracePosition_Impl`)
      reads `this+0x388 → +0x30 → +0x30 / +0x38` expecting the
      `FLuxCapsuleContainer` chain, but instead walks a `USkeletalMeshComponent`.
    - `LuxMoveProviderRef_Get @ 0x14045FC70` and
      `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0` — callers pass
      `chara+0x388` as the "context" pair, and these functions invoke
      `(*(param_1))->vtable[0]` on it to "get world". On a SkeletalMeshComponent,
      `vtable[0]` is the destructor, so the ISA-check at
      `world+0x98 -> ALuxBattleManager` falls through with garbage and
      the functions early-out. Their many callers in `FUN_1403A66F0`
      through `FUN_1403AAA60` (~20 adjacent functions) are effectively
      dead code on this build.

    The live move pipeline routes through `ALuxBattleMoveCommandPlayer`
    and the raw `BM+0x1450` TSharedPtr, not through the chara's
    `+0x388` slot.

### `ALuxTraceManager`

- **Path**: `/Script/LuxorGame.LuxTraceManager`
- **Size**: 0x408
- **Role**: drives the **visual** weapon trail / particle FX for one chara. Despite the name, this
  actor has nothing to do with hit resolution — live hit detection uses KHit linked-list nodes
  documented in [Hitbox System](hitbox-system.md). Every field on this class is visual state: two
  particle components, the trail-rendering `ULuxTraceComponent`, and a `KindIndex` that picks the
  visual style.

| Offset | Type | Name |
|-------:|------|------|
| +0x388 | `ULuxTraceDataAsset*` | TraceDataAsset |
| +0x398 | `UParticleSystemComponent*` | EffectSlotA |
| +0x3A0 | `UParticleSystemComponent*` | EffectSlotB |
| +0x3A8 | `ULuxTraceComponent*` | TraceComponent |
| +0x3B0 | … | active-trace hash |
| +0x400 | `int32` | KindIndex (`ELuxTraceKindId`) |

> source: `Z_Construct_UClass_ALuxTraceManager @ 0x140C096B0`,
> `ALuxTraceManager_ActivateTrace_Impl @ 0x1408D5D10`.

### `ULuxTraceDataAsset`

- **Path**: `/Script/LuxorGame.LuxTraceDataAsset`
- **Size**: 128 bytes (0x80)
- **Discovered via**: `Z_Construct_UProperties_ULuxTraceDataAsset @ 0x140C0CF60`

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00..+0x2F | — | UObject base | unread by trace code |
| +0x30 | `ULuxTracePartsDataAssetList*` | `TracePartsDataAssetList` | the list of capsule-shaped trace-parts metadata |
| +0x38 | `ULuxTraceColorPalletDataAsset*` | `TraceColorPalletDataAsset` | per-chara palette |
| +0x40 | `ULuxTraceInfinityDataAsset*` | `TraceInfinityDataAsset` | infinity-mode override asset |
| +0x50 | `uint8` (bitfield) | `bDebugDrawBits` | bit 0 = `bDebugDrawTraceFrame`, bit 1 = `bDebugDrawTraceKeyFrame`, bit 2 = `bDebugDrawTraceVelocity`. **All three are dead in shipping** — see [Dev / Debug Hooks](dev-debug-hooks.md). |

Held at `ALuxTraceManager+0x388` as `TraceManager.TraceDataAsset` on this build.

### `ULuxTraceComponent`

- **Path**: `/Script/LuxorGame.LuxTraceComponent`
- **Size**: 0x4B0
- **Role**: **visual-only** ticking component that renders the weapon trail. Holds the
  `ActiveTraces` TArray of in-flight trail segments and spawns an `ALuxTraceMeshActor` to draw
  them. Consumed by `ALuxTraceManager`; not referenced by the hit resolver.

| Offset | Type | Name |
|-------:|------|------|
| +0x418 | `FActiveTrace**` | ActiveTraces data ptr |
| +0x420 | `int32` | ActiveTraces count |
| +0x424 | `int32` | ActiveTraces capacity |
| +0x438 | `uint8` | bTraceRunning |
| +0x444 | `float` | LastInputX (per-tick axis feed from `ALuxTraceManager::Update`) |
| +0x448 | `float` | LastInputY |
| +0x470 | `float` | LengthFrames |
| +0x478 | `int32` | TotalFrames |
| +0x488 | `ULuxTraceKindDataAsset*` | KindDataAsset |
| +0x490 | `USkeletalMeshComponent*` | MeshRef |
| +0x498 | `int32` | KindIndexCopy |
| +0x49C | `uint8` | TraceSubMode (0=normal, 1=thunder, 2=saber) |

> source: `Z_Construct_UClass_ULuxTraceComponent @ 0x140C09950`,
> `ULuxTraceComponent_BeginTrace @ 0x1408D5FF0`.

### `FLuxCapsule`

- **Size**: 80 bytes (0x50) — confirmed from the Ghidra struct layout.
- **Storage**: the legacy container shape is `FLuxCapsuleContainer` (`FLuxCapsule**` at
  `container+0x30`, count at `+0x38`), but the old runtime chain
  `chara+0x388 -> +0x30 -> container` is stale on this build because `chara+0x388` is
  `CharaMesh0`, not a MoveProvider. The live capsule-container owner is still unconfirmed; see
  [Trace System](trace-system.md#where-the-live-fluxcapsule-array-is-on-this-build).
- The first 48 bytes (`+0x00 .. +0x2F`) are an internal header that `GetTracePosition_Impl` never
  touches. The documented fields all live in the tail of the struct.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x30 | `uint8` | CapsuleType | matched against `Active()` tag 1..9 |
| +0x31 | `uint8` | BoneId_A | 8-bit internal index (remapped via `LuxSkeletalBoneIndex_Remap`) |
| +0x34 | `float[3]` | LocalOffset_A | bone-local; scaled by `g_LuxCmToUEScale @ 0x143E8A418`. The Ghidra label calls this a cm→UE conversion, but the actual value is `10.0f` (bit pattern `0x41200000`), which implies the stored offset is in millimetres (or some other decimetre-like internal unit) rather than cm. Multiplying by 10 lands it in UE4's native cm units. |
| +0x40 | `uint8` | BoneId_B | second endpoint's bone index |
| +0x44 | `float[3]` | LocalOffset_B | second endpoint's bone-local offset |

There is **no `VisualPartsAsset` field on `FLuxCapsule`**. An earlier pass guessed a
`ULuxTracePartsDataAsset*` at `+0x50`, but that offset is past the end of the 80-byte struct and
`GetTracePosition_Impl` never reads it. Visual-parts data-assets are referenced elsewhere in the
trace pipeline (the kind data-asset on `ULuxTraceComponent`, stored in the per-trace record), not
embedded in a capsule.

> source: `ALuxTraceManager_GetTracePosition_Impl @ 0x1408D0BB0` (formerly misnamed
> `ALuxBattleChara_GetTracePosition_Impl` in older Ghidra databases — the function body
> receives a chara `this`, but the UFunction is registered under `ALuxTraceManager`),
> `FLuxCapsule` type in the Ghidra data-type manager (80 bytes, header + 32-byte
> endpoint pair). Per its plate comment, this function is **stale on the current
> Steam build** — it reads the legacy MoveProvider slot, which no longer holds
> live capsule data.

See [Hitbox System](hitbox-system.md) for how the equivalent `KHitArea` / `KHitSphere`
endpoints feed the per-tick hit resolver, and [Trace System](trace-system.md) for
`FLuxCapsule`'s role in the visual weapon-trail pipeline.

---

## UScriptStructs used by the trace UFunctions

### `FTraceActiveParam` (0x30 bytes)

Passed to `ALuxBattleChara::Active`. Only the first byte matters for hit logic.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint8` | AttackTag | 1..9 — indexes the slot hash at chara+0x3B0 |
| +0x04 | `uint32` | Flags | visual only |
| +0x1C | `FLinearColor` | InputColor | trail tint |
| +… | … | padding / cosmetic | ignored by `Active_Impl` |

> source: `Z_Construct_UScriptStruct_FTraceActiveParam @ 0x140C3D380`,
> `execActive_ALuxBattleChara @ 0x140C3DA20`.

### `FTraceInactiveParam` (0x8 bytes)

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `uint8` | InactiveType (`ETraceInactiveType`: `Immediatery` / `Standard` / `Stoped`) |
| +0x01 | `uint8` | SubSlot |

---

## Stage / frame spatial acceleration (used by the `LuxMoveVM` IF predicates)

The two spatial `IF` predicates in `LuxMoveVM` (`CheckRangeOrDistance @ 0x140365140`,
`CheckAngleOrGeometry @ 0x1403652E0`) query two global, non-thread-safe spatial
structures shared across the battle subsystem. Both structures come in matched
A/B pairs, selected via the byte flag `g_LuxBattle_FrameContextUseB @
0x14470DEDC`: when it is non-zero, the accessors
`LuxBattle_GetActiveFrameBoundsGrid @ 0x1403133E0` and
`LuxBattle_GetActiveFrameTransform @ 0x140313400` return the "B" variant.

### scbattle stage-info globals

- **Global block**: `0x144844010..0x144844130`
- **Writers/readers**: `GetScbattleStageInfoBarrierGeometry @ 0x1402D7730`,
  `SetScbattleStageInfoBarrierGeometry @ 0x1402D77C0`,
  `scbattle_StageInfo_SetStageBoundaryParams @ 0x1402D7670`
- **Storage conclusion**: the ring-boundary array is fixed at 12 entries. The
  flag at `+0x5C` / `0x14484406C` is a valid bit, not a count.

`scbattle_StageInfoParam` is the whole contiguous global block:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x000 | `uint32` | `dwRngSeed` | `g_scbattle_StageInfo_RngSeed @ 0x144844010` |
| +0x004 | `byte[12]` | `p_pad_04` | alignment gap before the boundary params |
| +0x010 | `scbattle_StageBoundaryParams` | `sBoundaryParams` | `g_sScbattleStageBoundaryParams @ 0x144844020` |
| +0x058 | `uint32` | `dwInitialized` | `g_dwScbattleStageInfoInitialized @ 0x144844068` |
| +0x05C | `uint32` | `dwBarrierValid` | `g_dwScbattleStageInfoBarrierValid @ 0x14484406C` |
| +0x060 | `scbattle_BarrierEntry[12]` | `pABarrierEntries` | `g_aScbattleStageInfoBarrierEntries @ 0x144844070`, total `0xC0` bytes |

`scbattle_BarrierEntry` is one deterministic ring segment:

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `float` | `flX0` |
| +0x04 | `float` | `flY0` |
| +0x08 | `float` | `flX1` |
| +0x0C | `float` | `flY1` |

`scbattle_StageBoundaryParams` is 64 bytes:

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `float` | `flStageOriginX` |
| +0x04 | `float` | `flStageOriginY` |
| +0x08 | `float` | `flStageOriginZ` |
| +0x0C | `float` | `flPadding_0c` |
| +0x10 | `float` | `flPlayer1Offset_DX` |
| +0x14 | `float` | `flPlayer1Offset_DY` |
| +0x18 | `float` | `flPlayer1Offset_DZ` |
| +0x1C | `float` | `flPlayer2Offset_DX` |
| +0x20 | `float` | `flPlayer2Offset_DY` |
| +0x24 | `float` | `flPlayer2Offset_DZ` |
| +0x28 | `float` | `flPadding_28` |
| +0x2C | `float` | `flPadding_2c` |
| +0x30 | `float` | `flStageFacingRadians` |
| +0x34 | `float` | `flPerPlayerFacingDelta_P1` |
| +0x38 | `float` | `flPerPlayerFacingDelta_P2` |
| +0x3C | `float` | `flPadding_3c` |

### Stage actor registration event record

`LuxStage_RegisterBarrierActor_BattleEvent0x19 @ 0x140427490` and
`LuxStage_RegisterWallActor_BattleEvent0x19 @ 0x140428EE0` build a 24-byte event
record before dispatching class `2`. For barrier actors the observed values are
`bEventType = 3`, `dwPayloadExt = 1`, and `bEventClassId = 0x19`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `byte` | `bEventType` | barrier path writes `3` |
| +0x01 | `byte[3]` | `p_pad_01` | |
| +0x04 | `uint32` | `dwPayloadExt` | barrier path writes `1` |
| +0x08 | `uint64` | `qwPayload` | actor / payload pointer-sized value |
| +0x10 | `uint32` | `dwReserved` | |
| +0x14 | `byte` | `bEventClassId` | barrier/wall registration uses `0x19` |
| +0x15 | `byte[3]` | `p_pad_15` | |

### `ULuxStageAssetPaths`, `LuxStageRawAsset`, and `LuxStageSetting`

`ULuxStageAssetPaths` is the content-side data asset that names the raw files
used for a stage. `Z_Construct_UClass_ULuxStageAssetPaths @ 0x140BACDB0`
registers these reflected fields:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x38 | `FString` or name-like id | `Identifier` | matched against selected stage id formatted as `"%03X"` by `FUN_14089B2C0` |
| +0x40 | `TArray<LuxStageRawAsset>` | `RawAssets` | entries keyed by `ELuxStageAssetType` |
| +0x50 | `LuxStageSetting` | `Setting` | three cosmetic/content behavior bools |

`LuxStageRawAsset` is 0x18 bytes, registered by
`Z_Construct_UScriptStruct_LuxStageRawAsset @ 0x140BD8C60`:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `ELuxStageAssetType` | `Type` | 0=`ESA_HitData`, 1=`ESA_HitData2`, 2=`ESA_IntroCameraData`, 3=`ESA_StartCameraData` |
| +0x08 | `FString` | `Path` | raw asset path loaded by the Lux asset path system |

`LuxStageSetting` is 3 bytes, registered by
`Z_Construct_UScriptStruct_LuxStageSetting @ 0x140BD9120`:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `bool` | `bAnomalyStageVFxEnabled` | copied by `LuxMove_RefreshProvider_CacheMeshesAndParts @ 0x1403CEDE0` into the stage/VFX refresh state |
| +0x01 | `bool` | `bWet` | consumed by `LuxBattleManager_InitRound_TickTimers_ClearRoundData @ 0x1403FB660`; true drives `WetRatio` to `1.0` at round init |
| +0x02 | `bool` | `bBreath` | copied by `LuxMove_RefreshProvider_CacheMeshesAndParts @ 0x1403CEDE0` into the stage/VFX refresh state |

The VFX destination offsets observed in `LuxMove_RefreshProvider_CacheMeshesAndParts`
conflict with the currently documented `ALuxBattleChara+0x460` UPROPERTY layout,
so treat those destination fields as owner-layout-pending until a live-memory pass
confirms the object type. The source asset offsets above are reflected and stable.

`LuxObject_BuildParamSlots_FromBattleSubstrings_4Slots @ 0x1404208B0` maps
loaded `RawAssets` into the four setup slots. Type 0 and 1 become the A/B
`J_StgHitChkData*` pointers used by the frame-cache terrain/wall grid.

### `J_StgHitChkData` frame-cache setup

`LuxBattle_SetFrameCacheHitChkDataPtrs @ 0x1402DAE70` copies a small setup
packet into globals. The first two fields are then consumed by
`LuxBattle_RefreshFrameTerrainCache @ 0x140314480`, which passes them to
`LuxBattle_AttachStgHitChkData @ 0x140392080`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `J_StgHitChkData*` | `pStgHitChkDataA` | copied to `g_pLuxBattle_StgHitChkDataA @ 0x14470D0D0` |
| +0x08 | `J_StgHitChkData*` | `pStgHitChkDataB` | copied to `g_pLuxBattle_StgHitChkDataB @ 0x14470D0F8` |
| +0x10 | `void*` | `pField10` | copied to `DAT_14470D0C8`; role still unknown |
| +0x18 | `void*` | `pField18` | copied to `DAT_14470D180`; role still unknown |
| +0x20 | `byte` | `bField20` | copied to `DAT_14470D0DB` |
| +0x21 | `byte` | `bField21` | copied to `DAT_14470D0D8` |

### `J_StgHitChkData` serialized terrain/wall blob

`J_StgHitChkData` is the serialized legacy stage collision blob expanded into
the live frame-bounds grid. The attach function uses the debug tag string
`"J_StgHitChkData::Attach" @ 0x143E89F20`, which is the strongest fingerprint
that this path is not UE4 PhysX.

Header view (`J_StgHitChkData_Header`, 0x30 bytes):

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `byte[40]` | `pReserved_00` | opaque header bytes not decoded by attach |
| +0x28 | `int16` | `nCellCount` | number of 16-byte cell headers |
| +0x2A | `int16` | `nPoolChunkCount` | number of pool chunks / reindex entries |
| +0x2C | `int16` | `nTerrainEntryCount` | terrain-entry count used for tag scans |
| +0x2E | `int16` | `nReserved_2e` | |

Cell header (`J_StgHitChkData_CellHeader`, 0x10 bytes):

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `uint16` | `wPoolBaseA` |
| +0x02 | `uint16` | `wMetaA` |
| +0x04 | `uint16` | `wPoolBaseB` |
| +0x06 | `uint16` | `wCountA` |
| +0x08 | `uint16` | `wPoolBaseC` |
| +0x0A | `uint16` | `wCountB` |
| +0x0C | `uint16` | `wMetaC` |
| +0x0E | `uint16` | `wCountC` |

Pool chunk header (`J_StgHitChkData_PoolChunk`, variable-size tail):

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `void*` | `pRuntimePatchedNext` | patched after attach |
| +0x08 | `uint16` | `wEntryCount` | packed index count |
| +0x0A | `byte` | `bReady` | initialized to 1 after pointer fixup |
| +0x0B | `byte` | `bReserved_0b` | |
| +0x0C | `uint32` | `dwRuntimePatched` | runtime-patched metadata |
| +0x10 | `uint16[1]` | `pPackedIndices` | variable tail; attach rewrites indices into terrain-entry pointers |

### Frame-bounds grid

- **Instances**:
  - `g_LuxBattle_FrameBoundsGridA` @ `0x144844DD0`
  - `g_LuxBattle_FrameBoundsGridB` @ `0x144845E80`
- **Discovered via**: `LuxBattle_GetActiveFrameBoundsGrid @ 0x1403133E0`,
  `LuxBattle_TraceSegmentThroughFrameBoundsGrid @ 0x1403149E0`,
  `LuxBattle_TestFrameBoundsCell @ 0x1403916E0`
- **Size**: at least 0x44b bytes (reads observed through terrain-query flags
  at `+0x448`; the grid header is ~0x30 bytes plus a `cells[]` tail).

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x000 | `void*` | `cells` | 0 when the grid is not built. Each slot `cells[i+1]` points to a row bucket. |
| +0x00C | `float` | `cellSize` | world units per cell along the scanned axis |
| +0x010 | `float` | `axisMin` | first valid axis value |
| +0x018 | `float` | `axisMax` | last valid axis value (inclusive) |
| +0x028 | `int16` | `cellCount` | number of cells in the row |
| +0x410 | `int8` | `isValid` | non-zero when the grid has been populated. The accessors bail when this is 0. |

**Cell layout (row bucket)** — an 8-byte pointer array indexed as
`cells[cellIndex + 1]`, each pointing to a struct with:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `void*` | `primaryEntries` | array of 8-byte pointers to triangle entries |
| +0x08 | `uint16` | `primaryCount` | |
| +0x10 | `void*` | `secondaryEntries` | alt-list (used when the "retry with secondary" flag is on) |
| +0x18 | `uint16` | `secondaryCount` | |

**Triangle entry** — used by `LuxBattle_IntersectSegmentWithTerrainTriangle @ 0x140390A90`:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `float[3]` | `vertexA` | world XYZ |
| +0x0C | `uint32` | `flagsA` | sub-flags (bits 4..11 = kind) |
| +0x10 | `float[3]` | `vertexB` | |
| +0x1C | `uint32` | `flagsB` | bits 8..11 = sub-kind, bits 12..15 = terrain tag |
| +0x20 | `float[3]` | `vertexC` | |
| +0x30 | `float[4]` | `plane` | (nx, ny, nz, d); plane equation `n·p + d = 0` |

> The plane is stored with a pre-baked offset `d` so the test is a single
> dot-product per endpoint.

### Frame transform

- **Instances**:
  - `g_LuxBattle_FrameTransformA` @ `0x144844170`
  - `g_LuxBattle_FrameTransformB` @ `0x144845220`
- **Discovered via**: `LuxBattle_GetActiveFrameTransform @ 0x140313400`
- **Pairs with** the bounds grid of the same letter. Every read of
  `GetActiveFrameBoundsGrid` in the VM predicate call path is immediately
  followed by a read of `GetActiveFrameTransform`. This suggests the two
  describe arena / camera frames that can be swapped atomically — the two sides
  of a stage-swap scenario, or two chara-local frames during a switch-cam move.

### Global terrain scratch vec4s

- **Instances**:
  - `g_LuxBattle_TerrainProbeUp` @ `0x1440FBC38` — primed to `(X, +100.0f, Z, 1.0f)`
  - `g_LuxBattle_TerrainProbeDown` @ `0x1440F7688` — primed to `(X, -100.0f, Z, 1.0f)`
- **Discovered via**: `LuxBattle_SampleTerrainAtXZ_Impl @ 0x140391350`
- **Size**: 16 bytes each (one `FVector4`).

`LuxBattle_SampleTerrainAtXZ_Impl` fills both with the XZ of the probe point
and a vertical component before kicking off the terrain query. Downstream,
`LuxBattle_IntersectSegmentWithTerrainTriangle` reuses the same two memory
locations as edge-cross-product scratch during point-in-triangle classification.

> **Thread safety**: these two globals are not TLS. The VM predicate call path
> is game-thread-serialized and depends on no other tick overlapping the terrain
> query. If you hook further up the chain, don't introduce parallelism here.

### Orphaned constants wired to the predicate chain

| Address | Name | Meaning |
|---------|------|---------|
| `0x143E8A3F4` | `g_LuxMoveVM_AngleCosScale` | `cos(θ)` scale factor baked into the angle predicate math |
| `0x143E8A3F8` | `g_LuxMoveVM_AngleSinScale` | `sin(θ)` scale factor baked into the angle predicate math |
| `0x143E8A674` | `g_LuxBattle_TerrainSample_Invalid` | sentinel returned by `LuxBattle_SampleTerrainAtXZ_Impl` when no entry matches |

---

## Engine structures referenced by SC6 mods

### `UWorld`

- **Path**: `/Script/Engine.World`
- **Discovered via**: `Z_Construct_UClass_UWorld @ 0x1428A5B90`

Offsets of interest to SC6 modding. The full UE4 4.17.2 `UWorld` has many more fields;
only the ones mods commonly need are listed here. The offsets below are confirmed
against the property-builder sequence inside `Z_Construct_UClass_UWorld`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x030 | `ULevel*` | `PersistentLevel` | |
| +0x038 | `UNetDriver*` | `NetDriver` | |
| +0x040 | `ULineBatchComponent*` | `LineBatcher` | depth-tested debug lines, per-frame |
| +0x048 | `ULineBatchComponent*` | `PersistentLineBatcher` | depth-tested, persists until `FLUSHPERSISTENTDEBUGLINES` |
| +0x050 | `ULineBatchComponent*` | `ForegroundLineBatcher` | **no depth test, always on top** — recommended for debug overlays |
| +0x088 | `TArray<ULevelStreaming*>` | `StreamingLevels` | |
| +0x098 | `FString` | `StreamingLevelsPrefix` | 24-byte FString — **not a UObject pointer.** Earlier docs claimed this was `AuthorityGameMode`; that is wrong. `AuthorityGameMode` is at `+0xF0`. |
| +0x0E8 | `UNavigationSystem*` | `NavigationSystem` | |
| +0x0F0 | `AGameModeBase*` | `AuthorityGameMode` | the real slot. ISA-checked against `ALuxBattleManager` by `GetPlayerIndex`, `GetTracePositionForPlayer`, etc. |
| +0x0F8 | `AGameStateBase*` | `GameState` | |
| +0x100 | `UAISystemBase*` | `AISystem` | |
| +0x138 | `ULevel*` | `CurrentLevel` | |
| +0x140 | `UGameInstance*` | `OwningGameInstance` | **On SC6 this points to `ULuxGameInstance`** (registered name `"LuxGameInstance"`, size 0x220, `Z_Construct_UClass_ULuxGameInstance @ 0x140A55E60`; short-form static-class getter at `0x140A51870`). `ALuxBattleChara::GetMoveProvider @ 0x1403F00B0` reads this slot, ISA-checks it against `ULuxGameInstance`, then reads **the GameInstance's own `+0x140`** to get the move-provider pointer. |

!!! warning "Do not confuse `world+0x140` with `ALuxBattleManager+0x140`"
    They're unrelated fields on unrelated objects that happen to share an
    offset. `world+0x140 = OwningGameInstance` (= `ULuxGameInstance*` on
    SC6). `BattleManager+0x140` is the (lazy) MoveComponent slot on the
    BattleManager itself. The Ghidra symbol
    `ALuxBattleManager_GetMoveProviderPtr @ 0x140546600` is MISNAMED — its
    actual parameter is a `ULuxGameInstance*`, reached through
    `world+0x140`. See
    [`ALuxBattleChara` runtime-layout note](#aluxbattlechara) for the
    downstream consequence (the chara's cached MoveProvider slot stays
    sentinel on this build).

See [Drawing 3D Debug Lines](line-batching.md) for the batcher path.

### `ULineBatchComponent`

- **Path**: `/Script/Engine.LineBatchComponent`
- **Size**: 0x850
- **Discovered via**: `Z_Construct_UClass_ULineBatchComponent @ 0x1425C9590`

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x808 | `FBatchedLine*` | `BatchedLines.Data` | append target for drawing lines |
| +0x810 | `int32` | `BatchedLines.Num` |  |
| +0x814 | `int32` | `BatchedLines.Max` |  |
| +0x818 | `FBatchedPoint*` | `BatchedPoints.Data` |  |
| +0x820 | `int32` | `BatchedPoints.Num` |  |
| +0x830 | `FBatchedMesh*` | `BatchedMeshes.Data` |  |
| +0x838 | `int32` | `BatchedMeshes.Num` |  |

### `FBatchedLine` (0x34 bytes)

```cpp
struct FBatchedLine {
    FVector      Start;              // +0x00
    FVector      End;                // +0x0C
    FLinearColor Color;              // +0x18
    float        Thickness;          // +0x28
    float        RemainingLifeTime;  // +0x2C
    uint8        DepthPriority;      // +0x30
    // +0x31..+0x33  padding to align 4
};
```

> source: `Z_Construct_UScriptStruct_FBatchedLine @ 0x1425CFCD0` (registered name `"BatchedLine"`, size `0x34`).

---

## Dead or vestigial classes — document once, stop chasing

### `ALuxBattleWeaponEventHandler`

- **Path**: `/Script/LuxorGame.LuxBattleWeaponEventHandler`
- **Status**: **Live event source, dead BP override slot in SC6.**

The native game fires the Blueprint-implementable event
`ReceiveGetWeaponTip(FLuxBattleEvent, out FVector outRoot, out FVector outTip,
out bool bReturnValue, bool bGetType) -> void` on this handler during attacks, including
ranged attacks like Cervantes's gun, where the `FLuxCapsule` trace system is silent. On
paper, hooking it would be an attractive "universal hitbox endpoint query".

**In practice, no SC6 character's Blueprint subclass overrides the event.** Every post-hook
sample observed arrives with `outRoot == outTip == (0,0,0)` and `bReturnValue == 0`. The
native caller (`ALuxBattleManager::GetTracePositionForPlayer`) calls the event first,
ignores the result, and falls through unconditionally to
`ALuxBattleChara::GetTracePosition_Impl` — so any "hitbox" value a mod reads from the
hook is garbage by construction.

This is documented here so the next person who sees the class in a `ProcessEvent` spy log
can skip the RE chase. The real hit-detection geometry lives in the
[Hitbox System (KHit linked lists)](hitbox-system.md), not on this UFunction. And the
weapon-tip query path the event was meant to feed —
[`GetTracePosition_Impl`](trace-system.md#ufunctions-on-aluxtracemanager) — is itself
stale on the shipping build.

**UFunction registration**: `Z_Construct_UFunction_ALuxBattleWeaponEventHandler_ReceiveGetWeaponTip
@ 0x1409CFCE0`. The param block is 0x24 bytes:

| Offset | Type | Name | In/Out |
|-------:|------|------|--------|
| +0x00 | `FLuxBattleEvent` (8 bytes) | `inEvent` | IN |
| +0x08 | `FVector` (12 bytes) | `outRoot` | OUT |
| +0x14 | `FVector` (12 bytes) | `outTip` | OUT |
| +0x20 | `bool` | `bReturnValue` | OUT |
| +0x21 | `bool` | `bGetType` | IN |

> source: `FUN_1409A9A80 @ 0x1409A9A80` (the native caller wrapper that invokes
> `ReceiveGetWeaponTip` via `FindFunction` + `vtable[0x1F8]::ProcessEvent`) called from
> `ALuxBattleManager::GetTracePositionForPlayer @ 0x1403F4960`.

---

## Other reversed structs

The Ghidra database holds a number of additional struct layouts that surface in callers
but don't yet have a dedicated section above. Listed here for completeness; cross-reference
in the relevant subsystem doc (move system, battle manager, trace system) for context.

### `TArrayHeader` (16 bytes)

The 16-byte UE4 `TArray<T>` header used everywhere as a `{Data, Num, Max}` triple. Defined
in Ghidra so other structs can reference it by name instead of pasting three raw fields.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `void*` | `Data` | element pointer (heap allocation owned by `GMalloc`) |
| +0x08 | `int32` | `Num` | element count |
| +0x0C | `int32` | `Max` | allocator capacity |

Used by `ULineBatchComponent_Partial` for the three batch arrays at `+0x808/+0x818/+0x830`,
and by every `TArray<T>` field on a Lux class.

### `APlayerCameraManager` POV (the live render-source)

The render thread reads its scene view from `APlayerController->PlayerCameraManager`,
**not** from `ALuxBattleManager.BattleCamera`. The latter is a "director" camera whose
output the PCM *consumes*. Mods that want to override the rendered pose write to
the PCM, not to the BattleCamera.

`APlayerCameraManager` carries an `FCameraCacheEntry` at `+0x400`, and the
`FMinimalViewInfo` block sits at `+0x410..+0x44B`:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| `+0x400` | `float` | `TimeStamp` | gate — > 0.0f during active battle |
| `+0x410` | `float` | `Location.X` | written every tick by the director chain |
| `+0x414` | `float` | `Location.Y` | |
| `+0x418` | `float` | `Location.Z` | |
| `+0x41C` | `float` | `Rotation.Pitch` | |
| `+0x420` | `float` | `Rotation.Yaw` | |
| `+0x424` | `float` | `Rotation.Roll` | |
| `+0x428` | `float` | `FOV` | |
| `+0x42C` | `float` | `DesiredFOV` | |
| `+0x430..+0x44B` | … | tail | `AspectRatio` / `OrthoWidth` / `PostProcess` settings |

The per-tick commit chain runs from `UWorld::Tick @ 0x141F02230`: each frame, the
`AController` iteration loop calls `APlayerCameraManager_CommitPOV_NoInterp(playerController[+0x84*8])`,
where `playerController[+0x84*8]` is the `PlayerCameraManager` pointer.
Read-back from the renderer goes through:

- `APlayerController::GetPlayerViewPoint @ 0x142046410`
- `APlayerController::GetCameraViewLoc @ 0x142042730`

Both read from the same `+0x410..+0x424` block on the PCM, and `ULocalPlayer::CalcSceneView`
is the consumer.

**Free-camera technique** (used by HorseMod's `FreeCamera`): NOP the engine's per-tick
stores to `+0x410..+0x428`, then write your own pose into the same offsets each cockpit
tick. The 5 store sites sit at `SoulcaliburVI.exe + 0x11EAB225` (primary, `[rdi+...]`)
and in a sibling sequence (`[rbx+...]`); both follow the same 5-store / 4-load pattern over
the offset table:

```text
+0x00 (8B) movsd  [rdi+0x410], xmm0    ; Location.X / Y      ← NOP
+0x08 (6B) movsd  xmm0, [rsp+0x3C]     ; load Z / pitch       LEAVE
+0x0E (8B) movsd  [rdi+0x41C], xmm0    ; Rotation.Pitch/Yaw  ← NOP
+0x16 (5B) movups xmm0, [rsp+0x48]     ; load tail FOV/etc.   LEAVE
+0x1B (6B) mov    [rdi+0x418], eax     ; Location.Z          ← NOP
+0x21 (4B) mov    eax, [rsp+0x44]                             LEAVE
+0x25 (6B) mov    [rdi+0x424], eax     ; Rotation.Roll       ← NOP
+0x2B (4B) mov    eax, [rsp+0x5C]                             LEAVE
+0x2F (7B) movups [rdi+0x428], xmm0    ; FOV + tail          ← NOP
```

Three additional pose writers may also need patching for a full lock-on rotational
override (empirical):

| Function | Address | Note |
|----------|---------|------|
| `PerTickPOVUpdater` (whole-pose committer despite the name) | `FUN_1420520F0` | NOP the entire 29-byte store block |
| `TargetFollowRotationWriter` | `FUN_141F935B0` | rotation-only writer |
| `SetPOV` (combined setter) | `FUN_141D27C80` | another whole-pose writer; called by `FUN_141D5BB90` (camera-follow updater) |

### Camera structs

#### `ALuxBattleCamera_PoseFields` (34 bytes)

A packed pose snapshot that the `LuxBattleCamera` uses to record sampled poses for
deterministic replay. The byte/float interleaving (no compiler alignment) is unusual
for UE4-derived code and looks bytecode-driven.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint8`  | `b_prefix` | header tag |
| +0x01 | `float`  | `flActiveTimestamp` | unaligned (sequence packing) |
| +0x05 | `uint8`  | `b_gap_404` | |
| +0x06 | `float`  | `flLocationX` | world XYZ, all unaligned |
| +0x0A | `float`  | `flLocationY` | |
| +0x0E | `float`  | `flLocationZ` | |
| +0x12 | `float`  | `flRotationPitch` | euler PYR |
| +0x16 | `float`  | `flRotationYaw` | |
| +0x1A | `float`  | `flRotationRoll` | |
| +0x1E | `float`  | `flFOV` | |

#### `FCameraCacheEntry_PCM_0x400` (55 bytes)

UE4 `APlayerCameraManager`-style cache entry, customised — same packed-byte / unaligned-float
discipline as `ALuxBattleCamera_PoseFields`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `float` | `flTimeStamp` | |
| +0x04 | 2 × `uint8` | `b_pad_404`, `b_pad_408` | |
| +0x06 | `float[3]` | `flLocation_X/Y/Z` | unaligned XYZ |
| +0x12 | `float[3]` | `flRotation_Pitch/Yaw/Roll` | unaligned PYR |
| +0x1E | `float` | `flFOV` | |
| +0x22 | `float` | `flDesiredFOV` | |
| +0x26 | `float` | `flAspectRatio` | |
| +0x2A | `float` | `flOrthoWidth` | |
| +0x2E | `float` | `flOrthoNear` | |
| +0x32 | `uint32` | `dwFlags` | |
| +0x36 | `bool` | `bConstrainAspectRatio` | |

#### `FLuxBattleCameraInternalPOV` (56 bytes)

Internal POV transform held by the battle camera's per-tick state. Mixes packed
`{X,Y}` qword pairs with an unaligned `Z` float to keep the on-disk replay
encoding compact.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint64` | `Location_XY` | packed pair |
| +0x08 | `float`  | `flLocation_Z` | |
| +0x0C | `uint64` | `Rotation_PitchYaw` | |
| +0x14 | `float`  | `flRotation_Roll` | |
| +0x18 | `uint64` | `FieldA_8` | unannotated |
| +0x20 | `uint64` | `FieldB_8` | unannotated |
| +0x28 | `uint32` | `dwFieldC_4` | |
| +0x2C | `uint32` | `dwFlags_Low2BitsUsed` | |
| +0x30 | `bool`   | `bBoolFlag` | |
| +0x34 | `float`  | `flTailFloat_FOV_Maybe` | |

#### `FLuxCameraAction` (740 bytes)

Per-action camera snapshot. Spawned and ticked by the camera state machine —
holds replay timeline state plus the active camera component reference.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00  | `void*` | `vtable` | |
| +0x10  | `void*` | `pParentChara` | |
| +0x18  | `void*` | `pParentContextB` | |
| +0x24  | `int32` | `nReplayCounter` | |
| +0x28  | `float` | `flCurrentPlaybackFrame` | |
| +0x30  | `int32` | `nActiveFlag` | |
| +0x38  | `void*` | `pCameraComponent` | |
| +0x44  | `int32` | `nSlotEnabledFlag` | |
| +0x80  | `float` | `flPerActionSpeed` | |
| +0x88  | `int32` | `nNegSpeedMode` | |
| +0x8C  | `int32` | `nEndedFlag` | |
| +0x90  | `int32` | `nReplayModeFlag` | |
| +0xB0  | `int32` | `nLoopOnEnd` | |
| +0x2DC | `int32` | `nMinFrame` | |
| +0x2E0 | `int32` | `nMaxFrame` | |

### Battle subsystem structs

#### `ALuxBattleFrameInputLog` (~17616 bytes)

Per-match input record/playback actor at `BattleManager+0x478`. Owns the
per-slot **replay input cache** (used by the online drain path), an SPSC
deque that receives inbound network packets, a master-clock counter, and a
double-tick guard that stops two ticks in a single frame from corrupting
the replay buffer.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00   | `void*`  | `pVtable` | |
| +0x388  | `void*`  | `pUE4Component_at0x388` | UE4 actor base sub-component |
| +0x390  | `int32`  | `InputDelay_at0x390` | UProperty `InputDelay` (registered by `ALuxBattleFrameInputLog_RegisterProperties @ 0x1409188E0`). **Verified permanently 0** in observed builds — its only writer is the constructor's zero-init at `LuxMoveProvider_BaseData_Constructor @ 0x1403DC3FB`. Subtracted from `dwFrameIndex` at `LuxBattleManager_GetCachedRoundValue_ByIndex @ 0x1403F0751` and `LuxBattleChara_ReplayPlayback_PushInputsToActiveSlots @ 0x1403F66A1` when `vtable[0x658]() != 0`, but with the field at 0 both `SUB`s are no-ops. See [8WAYRUN "1 fake frame" mod](leaderboards.md#the-8wayrun-1-fake-frame-mod-is-a-placebo). |
| +0x394  | `uint32` | `dwForwardReverseBitfield_at0x394` | |
| +0x398  | `bool`   | `bEnable_at0x398` | nNumPlayerSlots (typically 2) |
| +0x39C  | `uint32` | `dwPlaybackCursor_at0x39C` | bmActivePlayerSlots (BIT *i* = slot *i* active) |
| +0x3A0  | `int32`  | `nLastFrameID_at0x3A0` | current frame id |
| +0x3A4  | `int32`  | `nMasterClock_at0x3A4` | **the replay master clock** — see [Replay System](replay-system.md) |
| +0x3A8  | `void*`  | `pRecordedFrameBuffer_at0x3A8` | array of `FLuxRecordedFrame` |
| +0x3B0  | `int32`  | `nTotalRecordedFrames_at0x3B0` | |
| +0x3C0  | `FLuxReplayInputCacheEntry[1024]` | `pReplayInputCache_at0x3C0` | **16 KB per-slot input cache** — `[2 slots][512 entries][16 B]`; written by the online drain, read by the catch-up loop. See [Leaderboards & Online: in-match netplay](leaderboards.md#in-match-netplay-the-per-frame-input-ring). |
| +0x4400 | `uint32` | `dwOnlineActive_at0x4400` | **online-active flag** — 0=offline/spectator (drain early-exits), 1=PLAYER_SIDE_B, 2=PLAYER_SIDE_A, 3=hidden lobby. Set by `LuxBattleChara_InitPlayerBitmask_FromOnlineSession @ 0x1403FA330`. |
| +0x4404 | `bool`   | `bDoubleTickGuard_at0x4404` | per-tick re-entrancy guard |
| +0x4410 | `int32`  | `nDrainCursor_at0x4410` | |
| +0x4414 | `int32`  | `nMinStoreFrameIndex_at0x4414` | drain watermark (cache writes below this are skipped) |
| +0x4424 | `byte`   | `bSessionShutdownState_at0x4424` | 5 = terminal; drain bails on this value |
| +0x4428 | `byte[88]` | `pSentInputBitmap_at0x4428` | per-frame-per-input dedupe bitmap |
| +0x4480 | `void*`  | `pDequeStorage_at0x4480` | inbound-packet deque (network thread → game thread) |
| +0x4488 | `void*`  | `pDequeEntries_at0x4488` | |
| +0x4490 | `ulonglong` | `qwDequeMask_at0x4490` | circular-buffer mask |
| +0x4498 | `ulonglong` | `qwDequeHeadIdx_at0x4498` | read cursor |
| +0x44A0 | `ulonglong` | `qwDequeCount_at0x44A0` | count; capped at 100 (drop-oldest) |
| +0x44A8 | `CRITICAL_SECTION` (40 B) | `DequeLock_at0x44A8` | held by push (network thread) AND drain (game thread) |

#### `FLuxReplayInputCacheEntry` (16 bytes)

One slot in `ALuxBattleFrameInputLog.pReplayInputCache_at0x3C0`. Indexed by
`(dwFrameIndex & 0x1FF) + playerSlot * 0x200`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `int32` | `nFrameID` | match `nLastFrameID_at0x3A0` to read |
| +0x04 | `uint32` | `dwFrameIndex` | absolute frame number (master-clock indexed) |
| +0x08 | `uint32` | `dwInputValue` | 16-bit input cast to u32 |
| +0x0C | `byte` | `bFilled` | 1 = entry valid; written **before** `dwInputValue` (latent TOCTOU under contention) |
| +0x0D | `byte[3]` | `pReserved` | padding |

#### `ALuxBattleKeyRecorder` (956 bytes)

Training-mode key-recorder actor at `BattleManager+0x4B8`. Holds a slot table
of `FLuxBattleKeyRecorderSlot` entries that script the training dummy's input
playback (the `Recorded` setting in Training menu).

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00  | `void*`  | `vtable` | |
| +0x388 | `void*`  | `pParentActor` | back-ref to the BattleManager |
| +0x398 | `bool`   | `bRecordPhase` | recording vs playback |
| +0x39C | `uint32` | `dwPlayerIndex` | which side records |
| +0x3A0 | `int32`  | `nSlotIndex` | active slot cursor |
| +0x3A8 | `void*`  | `pSlotTable` | `FLuxBattleKeyRecorderSlot[]` heap array |
| +0x3B8 | `int32`  | `nMoveSelectionMode` | |

#### `FLuxBattleKeyRecorderSlot` (12 bytes)

One queued input in the key recorder's slot table.

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `int32` | `nDuration` |
| +0x04 | `int32` | `nWaitCounter` |
| +0x08 | `int32` | `nMoveID` |

#### `ALuxBattleReplayPlayer` (977 bytes)

Playback actor at `BattleManager+0x488`. Reconstructs the match from a
serialised state-reset blob plus a `RecordingData` ref. The Ghidra struct
size is `0x3D1` (977 bytes); earlier docs cited `0x3C0` (960 bytes).

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x398 | `bool` | `bEnable_at0x398` | |
| +0x39C | `int32` | `nCurrentRound_at0x39C` | |
| +0x3A0 | `float` | `flCurrentTime_at0x3A0` | |
| +0x3A8 | `void*` | `pStateResetData_at0x3A8` | round-start serialised blob |
| +0x3B0 | `int32` | `nTotalRounds_at0x3B0` | |
| +0x3B8 | `void*` | `pRecordingData_at0x3B8` | raw recording stream |
| +0x3D0 | `bool` | `fIsPlayingBack_at0x3D0` | the byte that pushes the struct past `0x3C0` |

#### `FLuxRecordedFrame` (192 bytes)

One frame's worth of input/state recorded by `ALuxBattleFrameInputLog`. The
field layout has not been broken down past the byte-grid yet — enough to
size buffers, but not enough to interpret individual fields.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00..+0x9F  | 20 × `uint64` | `qw00..qw98` | undecoded |
| +0xA0..+0xBF  | 8 × `uint32`  | `dwDw_a0..dwDw_bc` | undecoded tail |

#### `FLuxBattleCharaVisibilityFlags` (7 bytes)

A 7-byte bitfield struct that controls per-frame visibility of the character and
weapon meshes — two pad bytes plus four boolean toggles.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00..+0x01 | 2 × `uint8` | `b_pad_530`, `b_pad_531` | |
| +0x02 | `bool` | `bForceHideOverride` | master "hide" override |
| +0x03 | `bool` | `bCharacterMeshVisibilityFlag` | |
| +0x04 | `bool` | `bWeaponMeshVisibilityFlag` | |
| +0x05 | `bool` | `bCharaSecondaryVisibilityGate` | |
| +0x06 | `bool` | `bWeaponSecondaryVisibilityGate` | |

#### `FLuxBattleVMFreezeRecord` (64 bytes)

Slow-motion / VM-freeze blend state. Holds three candidate alphas + per-mode
tags and produces a blended output per tick. The `flAlphaCandidate3_SlowMo`
slot is the slow-mo source (e.g. dramatic finishing-blow camera).

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `bool`   | `bVMFreezeByte` | enable gate |
| +0x04 | `float`  | `flBaseAlpha` | |
| +0x08 | `float`  | `flAlphaCandidate1` | |
| +0x0C | `float`  | `flAlphaCandidate2` | |
| +0x10 | `int32`  | `nCountdown1` | |
| +0x14 | `int32`  | `nCountdown2` | |
| +0x18 | `int32`  | `nModeTag1` | |
| +0x1C | `int32`  | `nModeTag2` | |
| +0x20..+0x2C | 4 × `float` | `flOutBlendW0..2`, `flOutScaledAlpha` | output side |
| +0x30 | `int32`  | `nOutModeTag` | |
| +0x34 | `float`  | `flAlphaCandidate3_SlowMo` | slow-mo source |
| +0x38 | `int32`  | `nField_38` | |
| +0x3C | `int32`  | `nSlowMotionEnabled` | |

#### `LuxBattleCharaMotionFlags` (64 bytes)

A 64-byte flag bank at `chara+0x16D0..+0x170F`, indexed by flag id 0..0x3F.
Each flag is a single byte (0 / 1). Guard / hit-state predicates read it;
`LuxBattleChara_SetMotionInputFlag @ 0x140304C00` writes it (with
side-effects for special indices). The move bank's slot record carries
two 64-bit "set/clear" masks at slot+0x20 / slot+0x28; on every move
transition, `LuxMoveVM_ApplyLaneMotionInputMasks @ 0x1402FD7F0` walks
the bits and calls SetMotionInputFlag for each corresponding flag.

| Flag idx | Chara offset | Name | Role |
|----:|---|------|------|
| 0x00 | `chara+0x16D0` | `abFlag00_GuardLockReason` | Cleared in special branches. Used by `CanTrackOpponentLookAt` to decide auto-rotation suppression. |
| 0x01 | `chara+0x16D1` | `bFlag01_GuardDirty` | per-frame latch; reset by `TickCharaMainSimulation`. |
| **0x02** | `chara+0x16D2` | **`bGuardCrouchStateBase`** | **Authoritative crouch state. 0=stand, 1=crouch.** Set/cleared only by move-VM transitions via `ApplyLaneMotionInputMasks`. Used as block-direction byte by `CheckGuardConditionForHitbox` when `+0x16FC` alt isn't locked. |
| 0x03 | `chara+0x16D3` | `bFlag03_Uninterruptible` | uninterruptible state |
| 0x04 | `chara+0x16D4` | `bFlag04_TerrainGate` | TerrainGateFlag — `CheckOpponentFrontTerrainMatch` early-exit. |
| 0x0B | `chara+0x16DB` | `bFlag0B_HitstunActive` | "in hit-reaction" — locks block-direction to base for high-tagged attacks. |
| 0x0C | `chara+0x16DC` | `bFlag0C_BlockstunActive` | "in block-stun" — locks block-direction to base for block-tagged attacks. |
| 0x0F | `chara+0x16DF` | `bFlag0F_PostHitstunActive` | post-hitstun reaction state |
| 0x10 | `chara+0x16E0` | `bFlag10_TerrainGateAlt` | secondary terrain gate |
| 0x12 | `chara+0x16E2` | `bFlag12_Airborne` | airborne; cleared by `SetMotionInputFlag` snaps Y to terrain |
| **0x2C** | `chara+0x16FC` | **`bAltGuardCrouchState`** | **Per-frame re-derived crouch state**. Reset to 0 each tick; re-computed by `UpdateGuardStanceFlags`. Used as block-direction byte when `+0x1701` alt-locked is set. |
| **0x2D** | `chara+0x16FD` | **`bIsGuardingFlag`** | "actively guarding this frame" — set by UpdateGuardStanceFlags when guard-input is held + stance-input matches. |
| **0x31** | `chara+0x1701` | **`bAltGuardLocked`** | when set, the alt is authoritative for hit resolution. Reset each tick. |

The bank is a unified motion-state machine: both the move-VM bytecode and the
input system call `SetMotionInputFlag(chara, flagIdx, value)` to mutate
flags. Several flag indices have side effects:

- `flag 0x0B` is auto-set when flags `{0x0C..0x11, 0x29, 0x35}` are set
  (the cluster mask `0x2000200003F000`).
- `flag 0x12` (airborne) when CLEARED snaps Y to chara+0x3C8 (terrain).
- `flag 0x29` when CLEARED also clears flag 0x21 and sets flag 0x30.
- `flag 0x2A` when SET copies a 4-byte attack-launch state.

See [Block direction & ducking-while-guarding](hitbox-system.md#block-direction-ducking-while-guarding)
for how these flags drive the duck-under-high-attack mechanic.

### Hit-detection node structs (KHit)

These are the structs that drive the **live** hit resolver — kicks, punches, hurtboxes,
pushboxes, grabs. See [Hitbox System](hitbox-system.md)
for the full call-graph walkthrough.

`FKHitNodeBase` and `FLuxKHitNode` are Ghidra-named partial views. The canonical names
in the binary's vtables (`KHitBase_vftable @ 0x143E87838`, etc.) are `KHitBase`, `KHitSphere`,
`KHitArea`, and `KHitFixArea`. Runtime storage is mixed-size: `Lux_KHitChk_DeserializeLinkedList
@ 0x14030C940` advances Sphere nodes by `0x80` bytes and Area/FixArea nodes by `0xA0` bytes.
The sparse `FLuxKHitNode` layout in the data-type manager covers the common header plus the
largest FixArea tail.

#### `FKHitNodeBase` (36 bytes — header view)

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `void*`  | `vtable` | one of `KHitBase / Sphere / Area / FixArea` |
| +0x08 | `uint64` | `PerAttackerBit` | `1ULL << (KindTag & 0x3F)` — a single-bit mask. The same value is produced for every subclass; its role depends on context (attacker mask / hurtbox mask / body mask). |
| +0x10 | `uint32` | `dwNode_Flags10_WriteOnly` | authored, write-only — no runtime reader. **Don't gate or classify on this.** |
| +0x14 | `uint16` | `wActiveThisFrame` | per-frame **geometry** gate, written from the MoveVM hot-mask as `(hotMask >> KindTag) & 1`. `hotMask` has a permanent floor of `0x3FFFD` (slots `{0, 2..17}` are always on). |
| +0x16 | `uint8`  | `bStreamTypeTag` | `0=Sphere`, `1=Area`, `2=FixArea` |
| +0x17 | `uint8`  | `bKindTag` | KHit category in `[0, ~22)`, not a skeletal bone id. Drives the `+0x08` mask, the `PerHurtboxBitmask` index, and the strike-vs-throw partition (slots 31, 55 = throw). |
| +0x18 | `void*`  | `next` | intrusive linked-list link |
| +0x20 | `int32` | `nNextDeltaBytes` | Relative offset to the next emitted node; `0x80` after Sphere, `0xA0` after Area/FixArea, zero on the tail. |

#### `FLuxKHitNode` (variable-size node view)

Same header as `FKHitNodeBase`, plus the largest `0x80`-byte tail `KHitFixArea` uses for its
three reference points and transforms. `KHitSphere` stops at `0x80` total node bytes;
`KHitArea` and `KHitFixArea` consume `0xA0` total bytes.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint64`        | `data_00` | shared with `FKHitNodeBase::vtable`-derived layout |
| +0x08 | `uint64`        | `CategoryMask` | aliased name for `PerAttackerBit` / `PerHurtboxBit` |
| +0x10 | `uint32`        | `dwField_10` | aliased `Node_Flags10` (write-only) |
| +0x14 | `uint16`        | `wPerFrameLiveGate` | aliased `ActiveThisFrame` |
| +0x17 | `uint8`         | `bKindTag` | aliased `KindTag` |
| +0x18 | `uint64`        | `Next` | aliased `next` |
| +0x20 | `int32`         | `nNextDeltaBytes` | Relative next-node delta; see header view. |
| +0x28 | `byte[8]`       | `pPad_28` | padding / ABI gap before subclass fields |
| +0x30 | `byte[]`        | `pSubclassTail` | subclass-specific fields below |

#### Subclass-specific layouts

```text
KHitSphere (StreamTypeTag = 0):
    +0x30  FVector  BoneLocalCenter      (mirrored at +0x40)
    +0x50  FVector  WorldCenterCurrent   (this frame; written by
                                          KHitSphere_UpdateWorldCenter @ 0x14030E1A0)
    +0x60  FVector  WorldCenterPrevious  (last frame; for sweep tests)
    +0x70  float    Radius               (may be scaled by anim cell)
    +0x74  float    RadiusAuthored
    +0x78  float    ContactImpulseScale  (pushbox contact force)
    +0x7C  uint32   BoneIndexUe4         (post-Remap)

KHitArea (StreamTypeTag = 1) — SWEPT CAPSULE, double-buffered for CCD:
    +0x30  FVector  BoneLocalP1
    +0x40  FVector  BoneLocalP2
    +0x50..+0x6F   WorldSpaceBufA  (P1, P2)
    +0x70..+0x8F   WorldSpaceBufB  (P1, P2)
                   g_LuxKHitArea_DoubleBufferToggle selects cur vs prev each tick;
                   the overlap test does 4-way segment/segment CCD across both halves.
    +0x90  uint32   BoneIndexUe4_P1
    +0x94  uint32   BoneIndexUe4_P2

KHitFixArea (StreamTypeTag = 2) — STATIC OBB from THREE reference points:
    +0x30  FVector  BoneLocalPoint1   (P1, w=1.0 at +0x3C)
    +0x40  FVector  BoneLocalPoint2   (P2, w=1.0 at +0x4C)
    +0x50  FVector  BoneLocalPoint3   (P3, w=1.0 at +0x5C)
    +0x60  FVector  WorldPoint1
    +0x70  FVector  WorldPoint2
    +0x80  FVector  WorldPoint3
    +0x90  uint32   BoneIndexUe4
```

Only `KHitSphere` carries a verified contact-impulse scale (`+0x78`), used by the
body / pushbox solver. Area and FixArea nodes are overlap geometry only in the
verified paths.

`KHitFixArea`'s OBB is derived at overlap-test time by Gram-Schmidting `(P2-P1)` and
`(P3-P1)` — see [hitbox-system.md](hitbox-system.md#khit-node-layout)
for the formula.

**Subclass vtables**:

| Symbol | Address |
|--------|---------|
| `KHitBase_vftable` | `0x143E87838` |
| `KHitSphere_vftable` | `0x143E877F0` |
| `KHitArea_vftable` | `0x143E877A8` |
| `KHitFixArea_vftable` | `0x143E87760` |

#### `FActiveAttackSlot` (68 bytes)

The per-tag active-attack slot stored in `ALuxBattleChara_Partial.ActiveAttackSlots`
(`+0x3D0`/`+0x3D8`). Holds two velocity vectors (slot start and slot end) plus
the chained hash-bucket pointers used by `chara->HashBuckets_Data`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint8`    | `bTag` | 1..N attack-tag key |
| +0x04 | `float[3]` | `flVelocityA_x/y/z` | |
| +0x10 | `float[3]` | `flVelocityB_x/y/z` | |
| +0x1C | `float[3]` | `flPositionMid_x/y/z` | |
| +0x28 | `float[3]` | `flDirectionUnit_x/y/z` | unit direction |
| +0x34 | `bool`     | `bGateStateByte` | |
| +0x38 | `int32`    | `nGateCountdownFrames` | |
| +0x3C | `int32`    | `nHashNextBucket` | linked-list next |
| +0x40 | `int32`    | `nHashThisBucket` | self-bucket marker |

### Move-VM structs

The move VM has substantial scratch state beyond the well-known opcode scratch.
See [Move System](move-system.md) for the per-opcode semantics; the structs
themselves are listed here.

#### `FLuxMoveCommandPlayer` (12332 bytes)

The per-chara VM context indexed by `g_LuxMoveVM_CommandPlayerArray @
0x14470F390` (slot stride `0xC0E`). Despite the name, this is **not** the
`ALuxBattleMoveCommandPlayer` actor at `BattleManager+0x4C0` — it is a fixed
global static array holding the live VM state for each chara.

The struct is sparse: most of the 12 KB is uncovered scratch / cell buffers.
Only the fields pinned in Ghidra are listed below.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00     | `void*`  | `vtable` | |
| +0x08     | `void*`  | `SelfChara` | back-ref to owning `ALuxBattleChara` |
| +0x10     | `void*`  | `OppChara` | mirror of `chara->Opponent` (`+0x973E8`) |
| +0x1C     | `uint32` | `dwMode` | VM mode |
| +0x20     | `uint32` | `dwActivePose` | |
| +0x340    | `void*`  | `FuncPtr340` | callback ptr used during dispatch |
| +0xCD0    | `uint32` | `dwPredicateRefreshEnable` | gate for `RefreshConditionFlagRing` |
| +0xCE0    | `void*`  | `MoveDefArrayBase` | mirror of `g_LuxMoveSystem_MoveDefArrayPerSlot` for this chara |
| +0xCF0    | `int32`  | `nPostATKRemainingDelayFrames` | feeds `LuxMoveVM_PostATKDelayGate` |
| +0x1988   | `uint32` | `dwOverrideFlag` | |
| +0x198C   | `uint32` | `dwActiveFlag` | |
| +0x1990   | `uint32` | `dwParserState` | |
| +0x1998   | `void*`  | `CellArrayPtr` | active move's opcode cell array |
| +0x19C8   | `uint32` | `dwVMEnabled` | mirror of `chara+0x18` |
| +0x19F0..+0x1A64 | `uint32`/`float`[~30 fields] | `dwPredRing_*` | condition-flag ring: `Self16EC`, `Self1727`, `OppBehaviorInRange`, `StanceInWindow`, etc. — see Ghidra layout for full list |
| +0x2150   | `uint32` | `dwMoveState0` | |
| +0x2158   | `uint32` | `dwMoveState1` | |
| +0x2684..+0x269C | `uint32`[6] | move-counters | `MoveCount`, `CurrentMoveIdx`, `CharaVMPhase`, `StartFlag`, `MoveEnded`, `ReverseFlag` |
| +0x26A0..+0x26A8 | 3 × `uint32` | `CalcOpA/B/C` | `0x50004 calc` operands |
| +0x26AC..+0x26B0 | `uint32`,`float` | `BTN_Mask`, `BTN_Time` | `0x1xxxx BTN+TIME` opcode |
| +0x26B4..+0x26B8 | 2 × `uint32` | `ATB_ComboId`, `ATB_YarareId_0` | `0x40001 ATB` |
| +0x26BC..+0x26C8 | 4 × `uint32` | `IF_Op/Delta/Subject/Value` | `0x50008 IF` |
| +0x26CC | `uint32` | `Goto_Delta` | `0x50003 goto` |
| +0x26D0..+0x26D4 | 2 × `uint32` | `Rand_Threshold`, `Rand_JumpDelta` | `0x50006 RAND` |
| +0x26D8..+0x26E4 | 4 × `uint32` | `ATK_Power`, `ATK_RangeRaw`, `ATK_Speed`, `ATK_DirectionMask` | `0x40002 ATK` |
| +0x2A10..+0x2A24 | `uint32`[6] | reservation+cell counters | `Reserve_NoWait`, `AnimSettleFrames`, `CellLoopCounter`, `CellCount`, `Cursor` |
| +0x2A28 | `char[128]` | `pDebugTextBuf` | per-tick debug-trace text — written every tick, never read in shipping (see [Dev / Debug Hooks](dev-debug-hooks.md)) |
| +0x2AD8 | `float`  | `flRingout_EdgeReach` | |
| +0x2B30..+0x2B38 | 3 × `uint32` | `ActiveYarareId`, `ReactionTimer`, `ActiveYarareAce` | |
| +0x2B68..+0x2B9C | 4 × `uint32` | `Ringout_*` | `YarareId`, `SuccessFlag`, `DirectionCode` |
| +0x2BC4..+0x2BC8 | 2 × `uint32` | `PostEffectYarareId`, `PostEffectBodyPart` | |
| +0x2BF8 | `uint32` | `HitIntensity` | |
| +0x2C34 | `int32`  | `ScaledKnockbackReach` | |
| +0x2C4C | `int32`  | `PostDispatchHang` | per-hit hang frames |
| +0x2CF4..+0x2CF8 | 2 × `float` | `RngRoll1`, `RngRoll2` | per-tick RNG samples |
| +0x2D08..+0x2D10 | 3 × `int32` | `TimerB43..B45` | |
| +0x3004 | `uint32` | `BodyPartStash` | |
| +0x3018..+0x3028 | 4 × `uint32` | `AirMoveIndex`, `ReactionCode`, `AirSubFlag`, … | air-juggle subflags |

#### `FLuxMoveVM_OpcodeScratch` (96 bytes)

The 96-byte scratch buffer the VM fills in once per opcode — see
[Move System: VM opcode scratch layout](move-system.md#vm-opcode-scratch-layout-offsets-on-g_luxmovevm_commandplayerarrayslot).
Layout matches the `+0x26AC..+0x26E4` slice of `FLuxMoveCommandPlayer`.

#### `FLuxMoveVM_ATKPayload` (16 bytes)

A 16-byte tuple matching the four ATK-opcode fields — used as a struct return /
local copy for the ATK arm of `LuxMoveVM_ExecuteAndDumpOpcode`.

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `uint32` | `dwPower` |
| +0x04 | `uint32` | `dwRangeRaw` |
| +0x08 | `uint32` | `dwSpeed` |
| +0x0C | `uint32` | `dwDirectionMask` |

#### `FLuxMoveBank` (48 bytes)

Per-character move-bank header at `chara+0x455C0`. Resolved by
`LuxMoveVM_ResolveBankSlot @ 0x1402FC400` and read by every
`LuxMoveVM_TransitionToMove`, `SetActiveMoveSlot`, and
`TickHitResolutionAndBodyCollision` site.

| Offset | Size | Type | Field | Notes |
|-------:|-----:|------|-------|-------|
| +0x00 | 8 | qword | header magic / unread | unread by hit pipeline |
| +0x08 | 4 | dword | unknown | |
| +0x0C | 2 | u16 | unknown | |
| +0x0E | 2 | u16 | `wEventRecordCount` | count of records in event-record table |
| +0x10 | 4 | u32 | `dwAttackCellArrayOffset` | offset to AttackCell array (`bank + bank[+0x10] + cellBone * 0x70`) |
| +0x14 | 4 | u32 | `dwNonAttackDescTableOffset` | offset to non-attack 6-byte descr table (`bank + bank[+0x14] + (subIdx & ~0x10000) * 6`) |
| +0x18 | 4 | u32 | `dwEventRecordTableOffset` | offset to event-record table (stride `0x30`, count = `wEventRecordCount`) |
| +0x1C..+0x2B | 16 | `FLuxMoveBankBucket[4]` | bucket0..bucket3 `(StartIdx, Count)` | `ResolveBankSlot` uses `(packedAddr >> 12) & 3` to pick a bucket |
| +0x2C | 4 | u32 | reserved / padding | |
| +0x30 | … | array | slot table starts | stride `0x48`; `(BucketN.StartIdx + slotInBucket) * 0x48` |

`FLuxMoveBankBucket` (4 bytes): `{ uint16 StartIdx; uint16 Count; }`.

#### `FLuxMoveBankSlotView` (72 bytes)

Returned by `LuxMoveVM_ResolveBankSlot` as
`bank + (StartIdx + slot) * 0x48 + 0x30`. The `+0x30` is intentional:
the structure straddles two adjacent slot records so the engine can read
related fields with one dereference. **All offsets are relative to the
returned pointer**, not to the absolute slot start.

| Offset | Size | Type | Field | Notes |
|-------:|-----:|------|-------|-------|
| +0x00 | 2 | u16 | `wAnimationIndex_00` | animation id used by motion-init-loop in `TransitionToMove` (was `psVar22Base`) |
| +0x02 | 2 | u16 | `wMotionPlaybackParam_02` | motion-init param (was unnamed; differs widely between sister slots like 0x13C/0x13D) |
| +0x04 | 2 | i16 | `nField_04` | motion arg (read by `TransitionToMove` second loop) |
| +0x06 | 2 | u16 | `wMotionFlags_06` | motion flag bits |
| +0x10 | 4 | u32 | `dwSubTableOffset_10` | per-slot offset into a sub-table A (`-1` = none) |
| +0x14 | 4 | u32 | `dwSubTableOffset_14` | per-slot offset into a sub-table B |
| +0x1C | 4 | u32 | bytecode offset (alt path) | added to bank base if `!= -1` |
| +0x20 | 8 | u64 | `qwInputMask_20` | copied to `lane->qwInputMaskCopy_448` at TransitionToMove |
| +0x28 | 8 | u64 | `qwInputMask_28` | copied to `lane->qwInputMaskCopy_450` |
| +0x30 | 4 | f32 | `flAnimLength_30` | move's anim length (60Hz frames) |
| +0x34 | 2 | i16 | `nAnimLengthFlag_34` | `-2` = use computed length from playback speed; otherwise the length itself in 60ths |
| +0x36 | 2 | i16 | `nHitWindowStart_36` | hit-window start frame (cell.MasterWindowStart for primary cell) |
| +0x38 | 4 | u32 | `dwBytecodeOffset_38` | **bank-relative bytecode offset** for the slot's per-tick / move-start script. Resolved as `bank + dwBytecodeOffset_38` when `!= -1`. Both `TransitionToMove` and `ExecuteOpStream` read this. |
| +0x3C..+0x46 | 12 | i16[6] | `nCellBoneIndexPerVariant[6]` | Variant index → AttackCell index. `-1` = no attack on this variant. The lane's `dwVariantIndex_460` (default 0) selects which entry to use. See [Cell lifetime](hitbox-system.md#cell-lifetime-one-cell-per-move). |

#### `FLuxMoveDefEntry` (16 bytes)

One row in the per-character `FMoveDef` array at
`g_LuxMoveSystem_MoveDefArrayPerSlot + CharaKindByte*0x3038`. Indexed by
`CurrentMoveIdx`.

| Offset | Size | Type | Field | Notes |
|-------:|-----:|------|-------|-------|
| +0x00 | 2 | u16 | `wField0` | move-id or flags (unread by `StartMoveForChara`) |
| +0x02 | 2 | u16 | `wStartCellCursor` | initial value for `g_LuxMoveSystem_CellCursorPerSlot` (= bytecode entry point) |
| +0x04..+0x0F | 12 | (opaque) | tail | unread by `StartMoveForChara` |

#### `FLuxMoveBankCell` (112 bytes)

One row in the per-character "move bank". This is the **attack-cell** the hit
pipeline consumes: `chara+0x44058 OwnActiveAttackCell` and the per-tick
opponent copy at `chara+0x44048` both point at one of these. It holds the per-cell
damage / hitstun / hit-property data; the byte arithmetic is `bank + bank[+0x10]
+ cellBone * 0x70`. The pointer at `chara+0x44058` is set ONCE per
`LuxMoveVM_TransitionToMove` and stays put for the move's duration —
`LuxMoveVM_SetActiveMoveSlot` (the function that would re-point it) has no
native callers, only a `UFunction` wrapper. See
[Attack cell](hitbox-system.md#attack-cell-fluxmovebankcell) for the full
runtime model.

Field offsets verified by tracing reads in `LuxBattleChara_ProcessHit @ 0x140342780`,
`LuxBattle_ApplyDamageFromPendingHit @ 0x1402FF620`,
`LuxMoveVM_EvaluateMoveTransition @ 0x14033E140`,
`LuxBattle_ComputeHitReactionParams @ 0x140343B90`,
`LuxMoveVM_ClassifyHitboxFrameState @ 0x140300620`, and
`LuxMoveVM_PropagateFieldToHitboxGroup @ 0x140303590`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint64` | `u64SlotMask` | which authored hitbox slots are LIVE while this cell is current — ANDed with defender's `PerHurtboxBitmask[i]` by the classifier |
| +0x08..+0x30 | (opaque) | | not read by hit pipeline |
| +0x32 | `uint16` | `wAttackFlags` | bit 0x001 = block-high, 0x002 = block-low, 0x008 = LowAttack, 0x010 = MidAttack, 0x040 = CrouchOnly, 0x080 = HighAttack, 0x200 = Unblockable / GI-immune |
| +0x34 | `uint16` | `wInputCond` | move-input precondition mask, fed to `LuxMoveVM_EvaluateMoveInputCondition` |
| +0x36 | `int16` | `nMasterWindowStart` | hit-window start frame (60Hz). `ClassifyHitboxFrameState` writes `chara+0x1980 = 1` while `currentAnimFrame < this`, `2` while inside, `3` while past |
| +0x38 | `int16` | `nMasterWindowEnd` | hit-window end frame. **DUAL-USE**: also reused by `LuxMoveVM_EvaluateAttackRange @ 0x14035F670` as a signed-short reach ceiling — when `chara+0x44978` (the projected reach scalar) exceeds this value, the range gate returns out-of-range. One 16-bit scalar serves both timing and reach |
| +0x3A | `int16` | `nBaseDamage` | THE damage figure read by `ProcessHit`, added into `attacker+0x3FC`. **One value per cell** — the same value for every shape that hits while this cell is active |
| +0x3C | `int16` | `nStunRecoil` | hitstun bucket, written into `attacker+0x3E4` |
| +0x3E | `uint16` | `wExtraStateFlags` | mirrored verbatim into `attacker+0x400` |
| +0x44 | `int16` | `nBlockstunFrames` | `ComputeHitReactionParams` case 1 (blocked) |
| +0x46 | `int16` | `nHitstunStandingNormal` | case 4–5 (standing hit) |
| +0x48 | `int16` | `nHitstunStandingAir` | case 4–5 (airborne defender) |
| +0x4C | `int16` | `nHitstunCrouchNormal` | case 7 (counter-hit / crouch hit) |
| +0x4E | `int16` | `nHitstunCrouchAir` | case 7 (airborne crouch) |
| +0x50 | `int16` | `nReactionIdStanding` | case 4–5/9 reaction-move id (standing) |
| +0x52 | `int16` | `nReactionIdAir` | case 4–5/9 reaction-move id (air) |
| +0x54 | `int16` | `nThrowEscapeId` | case 7 throw-escape id |
| +0x5A | `uint16` | `wPassthroughTagA` | mirrored to `chara+0x210A` on slot transition |
| +0x5E | `uint16` | `wHitboxGroupBitfield` | mirrored to `chara+0x20F6`. **bits 0..10** = group ID (0..63) selecting one of 4 banks of 16 hit-sub-window entries at `DAT_1448554E8 + 0x338 / 0x3B8 / 0x438 / 0x4B8`; **bits 11..13** mirrored to `chara+0x20F2`; **bits 14..15** mirrored to `chara+0x20F0`. See [Per-cell sub-window timing](hitbox-system.md#per-cell-sub-window-timing). |
| +0x60 | `uint16` | `wPassthroughTagC` | mirrored to `chara+0x20FC` |
| +0x62 | `int8`   | `cI8RangeStandMin` | per-cell stand-stance min reach (signed byte). `0x81` (-127) = "no constraint on this side". Read by `LuxMoveVM_EvaluateAttackRange` |
| +0x63 | `int8`   | `cI8RangeStandMax` | per-cell stand-stance max reach (signed byte). `0x81` sentinel as above |
| +0x64 | `int8`   | `cI8RangeCrouchMin` | per-cell crouch-stance min reach |
| +0x65 | `int8`   | `cI8RangeCrouchMax` | per-cell crouch-stance max reach |
| +0x66 | `int16`  | `nReachExtraGate` | per-cell extra reach gate (signed short). `-1` or `0` disables. Used in conjunction with the four byte bounds above to gate `EvaluateAttackRange` |
| +0x68..+0x69 | (opaque) | | tail-padding |
| +0x6A | `uint16` | `wRuntimePropagateField` | mutated at runtime by `LuxMoveVM_PropagateFieldToHitboxGroup @ 0x140303590` across the 8 cells of a hitbox-group entry. The only cell field known to change after move start; semantics not yet identified |
| +0x6C..+0x6F | (opaque) | | trailing pad |

**`LuxMoveVM_EvaluateAttackRange @ 0x14035F670`** (the per-cell reach
gate) is consulted ONLY by `LuxBattle_CheckYarareReactionGate` case
0x72 (yarare-table reach predicate), NOT by the throw classifier
itself. Returns: `0` = in range; `0xFFFFFFFD` = out of range; `0xFFFFFFFE`
= cell has no range constraints (all four bytes are `0` or `0x81`,
or `nReachExtraGate` is `-1`/`0`); `0xFFFFFFFF` = above-ceiling
(`chara+0x44978` reach scalar > `nMasterWindowEnd` short).

#### `FLuxMoveSchedState` (96 bytes)

Move scheduler state — a per-chara dual-slot system that lets the next move be
queued while the current one is still ticking. The `pMoveIdSlot[2]`,
`pPrevMoveId[2]`, and similar arrays hold one entry per slot.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x08 | `uint32`   | `dwSelectedSlotIdx` | 0 or 1 — which of the two queued slots is current |
| +0x10 | `void*`    | `pChara` | back-ref |
| +0x30 | `uint32[2]` | `pMoveIdSlot` | per-slot move id |
| +0x38 | `uint32[2]` | `pPrevMoveId` | per-slot previous move id |
| +0x40 | `uint32[2]` | `pMoveChangedCounter` | bumps on transition |
| +0x48 | `uint16[2]` | `pExtraParam0Slot` | per-slot extra arg |
| +0x4C | `uint16[2]` | `pExtraParam1Slot` | per-slot extra arg |
| +0x50 | `void*`    | `pSubVM` | optional sub-VM ptr |
| +0x5C | `uint32`   | `dwActiveSlotIdx` | active vs selected (debug aid) |

#### `FLuxMoveStartRequest` (108 bytes)

The "queue this move" request struct passed into `PlayMove` / `PlayMoveDirect`.
Carries its own state-machine field (`dwStateMachine`), a completion flag,
and two candidate move-id slots so the dispatcher can resolve a request that
spans a transition window.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `void*`  | `pVtable` | |
| +0x08 | `uint32` | `dwStatus` | |
| +0x10 | `void*`  | `pChara` | target chara |
| +0x18 | `uint16` | `wMoveId` | |
| +0x1A | `uint16` | `wLevelId` | |
| +0x20 | `uint32` | `dwMode` | |
| +0x38 | `uint32` | `dwStateMachine` | request-internal SM phase |
| +0x54 | `uint32` | `dwCompleted` | |
| +0x68 | `int16`  | `nCandidateMoveIdA` | for candidate-pair resolution |
| +0x6A | `int16`  | `nCandidateMoveIdB` | |

#### `FLuxMoveSubFrameRecord` (72 bytes)

Sub-frame record — a 60→120 Hz interpolation entry recorded per VM tick. The
`flRangeStart`/`flRangeEnd` interval gates which sub-frame samples the record
applies to.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `float`  | `flFrame_0` | frame index |
| +0x04 | `float`  | `flRangeStart` | sub-frame interval start |
| +0x08 | `float`  | `flRangeEnd` | sub-frame interval end |
| +0x0C | `uint32` | `dwField_0C` | |
| +0x10..+0x30 | 5 × `uint64` | `field_10..field_30` | |
| +0x38 | `uint32` | `dwField_38` | |
| +0x3C | `int16`  | `nCellBoneIndex` | which bone this sub-frame describes |
| +0x40 | `uint64` | `field_40` | tail |

#### `FLuxMoveLane` (1128 bytes — was `LuxMoveLaneState`)

Per-lane VM state for the move bytecode interpreter. Three lane blocks live
inline at fixed offsets in every chara:

| Offset on chara | Lane | Role |
|---:|---|---|
| `+0x444F0` | Lane 0 | Primary active move (most strikes) |
| `+0x44958` | Lane 1 | Secondary lane (mirror / queued script) |
| `+0x44DC0` | Lane 2 | Stance / yarare / hit-reaction |

Stride = `0x468` bytes. The Ghidra type is `FLuxMoveLane` (originally
typed as `LuxMoveLaneState` with mostly-undecoded padding). The field map below
reflects what the Cervantes 3B move-extension investigation uncovered, plus
pre-existing instrumentation. `chara+0x44068` (`ActiveLaneStateCursorPtr`)
points at whichever lane is currently driving the move.

Key fields (only the well-understood ones; undecoded scratch is omitted):

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `int16` | `nLaneIdx` | 0 / 1 / 2 |
| +0x02 | `int16` | `nMoveID` | packed `(bank<<12) \| slot`; `-1` = idle |
| +0x04 | `uint32` | `dwScratch_04` | |
| +0x08 | `float` | `flAnimFrameCurrent` | **THE frame counter** — advanced as `+0x08 += time_dilation * +0x30` each tick. Truncate for "current frame N". |
| +0x10 | `float` | `flAnimLength` | total anim frames; from bank cell `+0x34` (or computed from playback speed when `wAnimLengthFlag_34 == -2`) |
| +0x1A..+0x1B | `byte[2]` | `bByUnused_1A/1B` | |
| +0x1C | `int16` | `nSignedFrameCounter` | per-tick frame delta |
| +0x1E..+0x1F | `byte[2]` | `bByTransitionAlreadyMatchedFlag_1E/1F` | latched after `TransitionToMove(samePackedMoveAddr)` |
| +0x20 | `float` | `flAnimFramePrev` | tick-start snapshot of `flAnimFrameCurrent` |
| +0x24..+0x25 | `byte[2]` | `bByField_24/25` | |
| +0x26..+0x27 | `byte[2]` | `bByScriptInProgress_26/27` | "primary script running" gate |
| +0x28..+0x29 | `byte[2]` | `bBySecondaryRunning_28/29` | "secondary lane script running" gate |
| +0x2C | `int32` | `nTransitionFiredMarker_2C` | tx-fired marker; set by `CheckMoveTransitionTiming`, cleared every tick by `FinalizeTickPoseAndState` |
| +0x30 | `float` | `flAnimLengthCopyA_30` | playback-speed source |
| +0x34 | `float` | `flAnimLengthCopyB_34` | playback-speed target |
| +0x38..+0x3F | `byte[8]` | `pClearedOnTransition_38` | wiped by TransitionToMove |
| +0x50..+0x51 | `byte[2]` | `bByScriptInProgressMarker_50/51` | "Run currently entering" guards |
| +0x52 | `uint16` | `wMotionInputBank_52` | |
| +0x54 | `uint16` | `wStepCounter_54` | reentrant-step guard inside `ExecuteOpStream`; if > 16 the lane bails into `TransitionToMove(0,0)` (lane 0) or `CommitMoveEnd` (lane 1+) |
| +0x56 | `int16` | `nLaneIdxMirror_56` | written by `DecodeVariadicStreamArgs` |
| +0x5A | `int16` | **`nNextMoveID_5A`** | **immediate-transition target** — set by `DecodeVariadicStreamArgs` (CALLCOND TransitionAuthor); fires when `flTransitionThreshold_68` is reached |
| +0x5C | `int16` | `nMoveIDOverride16FE_5C` | replaces `nNextMoveID_5A` when `chara+0x16FE != 0` |
| +0x5E | `int16` | `nMoveIDOverride16EB_5E` | replaces it when `chara+0x16EB != 0` (multi-hit lockout) |
| +0x60 | `int16` | `nMoveIDOverrideMode2_60` | replaces it when `chara+0x973E8 + 0x132C > 1` (mode 2) |
| +0x64 | `uint32` | `dwTransitionStartTime_64` | |
| +0x68 | `float` | **`flTransitionThreshold_68`** | when other-lane's anim cursor reaches this, `CheckMoveTransitionTiming` fires `TransitionToMove(nNextMoveID_5A)` |
| +0x6C | `uint16` | `wMotionArgCount_6C` | |
| +0x6E | `int16[17]` | `anMotionArgs_6E` | motion args copied from the bytecode's CALLCOND arg tail |
| +0x90 | `int32` | `nPVarCount_90` | "extra param" arg count (motion-arg copy from `DecodeVariadicStreamArgs` for arg-count > 4) |
| +0x94 | `int16[16]` | `anPVarBuffer_94` | extra-arg storage |
| +0xB4 | `int16` | **`nDeferredMoveID_B4`** | **deferred-transition target** — written by `DecodeVariadicStreamArgs` when `g_LuxMoveVM_DeferredTransitionScheduleFlag != 0` (i.e. inside an `OpcodeIf_15` wrapper); drained next tick by `OpcodeIf_16` |
| +0xB6 | `int16` | `nDeferredLaneIdx_B6` | which lane the deferred transition targets |
| +0xB8 | `int16` | `nDeferredCommitFlag_B8` | snapshot of `g_LuxMoveVM_DeferredTransitionCommitFlag` |
| +0xBC | `float` | `flDeferredStartFrame_BC` | scheduled start frame |
| +0xC0 | `float` | `flDeferredCurrentFrame_C0` | snapshot of current frame |
| +0xD8 | `FLuxMoveLaneState*` | `pMotionPlaybackSlotA_D8` | small per-lane motion-playback record (see [LuxMoveLaneState_Motion](#luxmovelanestate_motion-68-bytes-the-small-motion-playback-record) below) |
| +0xE0 | `FLuxMoveLaneState*` | `pMotionPlaybackSlotB_E0` | second motion slot (upper-body / lower-body split) |
| +0x1F4 | `FLuxMoveLane_EffectOp[16]` | `aEffectOpTable_1F4` | 16-entry lane effect-op table (see below) |
| +0x438 | `qword` | `qwField_438` | input mask scratch |
| +0x440 | `qword` | `qwField_440` | input mask scratch |
| +0x448 | `qword` | `qwInputMaskCopy_448` | copy of slot's `qwInputMask_20` |
| +0x450 | `qword` | `qwInputMaskCopy_450` | copy of slot's `qwInputMask_28` |
| +0x458 | `qword` | `qwField_458` | total-tick counter (monotonic across advances) |
| +0x460 | `uint32` | `dwVariantIndex_460` | bank variant index 0..5 — picks which `nCellBoneIndex_3C[N]` from the slot view to resolve into an attack cell |

For a "current move frame N / M" HUD overlay, read `Lane0->flAnimFrameCurrent`
and `Lane0->flAnimLength` every tick — pure pointer arithmetic, no hooks
required. `chara+0x1350` is the `MoveStartCounter`, bumped on each
`TransitionToMove` call (handy for "did the move change?" checks without
diffing `nMoveID`). `chara+0x1360` is the `LastHitAnimFrame` mirror written
by `ProcessHit` for HUD consumers.

#### `FLuxMoveLane_EffectOp` (36 bytes)

One entry of the 16-slot effect-op table at `FLuxMoveLane->aEffectOpTable_1F4`.
Inserted by `LuxMoveVM_OpcodeIf_RegisterEffectOpDedup_04 @ 0x1402FD4A0`
(CALLCOND funcIdx 0x04 / 0x19 / 0x1A), walked per-tick by
`LuxMoveVM_ExecuteOpStream @ 0x1402FDEA0`, and dispatched via
`LuxMoveVM_DispatchEffectOp @ 0x140376B20` once `nTriggerFrame` is reached.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `int16` | `nTriggerFrame` | when `lane->flAnimFrameCurrent >= nTriggerFrame`, fire (`-1` = empty slot) |
| +0x02 | `byte` | `bArgc` | arg count - 1 (passed as `argc` to `DispatchEffectOp`) |
| +0x03 | `byte` | `bFiredFlag` | set on first fire to suppress re-trigger |
| +0x04 | `int16[16]` | `anArgs` | the args originally pushed onto the inner-VM stack before the registering CALLCOND |

#### `LuxMoveLaneState_Motion` (68 bytes — the small motion-playback record)

Per-motion-slot playback state. Two of these are pointed to from
`FLuxMoveLane->pMotionPlaybackSlotA_D8` / `pMotionPlaybackSlotB_E0`. (The Ghidra
type is currently `FLuxMoveLaneState`, distinct from the `FLuxMoveLane`
above; the legacy name collision is being phased out.)

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `float`  | `flUnknown00` | |
| +0x04 | `uint`   | `dwTickCounter` | |
| +0x08 | `float`  | `flAnimFrameCurrent` | |
| +0x0C | `float`  | `flAnimFramePrev` | |
| +0x10 | `float`  | `flAnimLengthFrames` | |
| +0x1A | `ushort` | `wAtEndFlag` | `1` at final frame |
| +0x1C | `short`  | `nFrameDeltaThisTick` | |
| +0x24 | `ushort` | `wFrameStepFinished` | |
| +0x26 | `ushort` | `wInTransitionFlag` | |
| +0x30 | `float`  | `flPlaybackSpeedCurrent` | ramps to target |
| +0x34 | `float`  | `flPlaybackSpeedTarget` | |
| +0x38 | `float`  | `flPlaybackSpeedDelta` | |
| +0x3C | `float`  | `flPlaybackSpeedRate` | |
| +0x40 | `float`  | `flPlaybackSpeedCountdown` | |

#### `FLuxMoveProvider_CapsuleSlot` (64 bytes)

Same shape as `FLuxCapsuleContainer` (header + Data/Num/Max), but referenced
from a different legacy code path. The layout is identical to `FLuxCapsuleContainer`;
the old MoveProvider ownership chain is stale on this build and the live owner is
still unconfirmed.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `byte[48]` | `pHeader` | unread |
| +0x30 | `void*`    | `CapsulesData` | pointer to `FLuxCapsule*` array |
| +0x38 | `int32`    | `nCapsulesNum` | element count |
| +0x3C | `int32`    | `nCapsulesMax` | allocator capacity |

### Trace-component layouts (extended)

The Ghidra DB carries two extended layouts that overlap the
[ALuxTraceManager](#aluxtracemanager) and [ULuxTraceComponent](#uluxtracecomponent)
sections above but reach further into the byte-grid.

#### `FLuxTraceManagerLayout` (1032 bytes)

Includes the 904-byte `AActor` base plus the trace-manager-specific tail.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x388 | `void*` | `pTraceDataAsset` | `ULuxTraceDataAsset*` |
| +0x398 | `void*` | `pEffectSlotA` | `UParticleSystemComponent*` |
| +0x3A0 | `void*` | `pEffectSlotB` | `UParticleSystemComponent*` |
| +0x3A8 | `void*` | `pTraceComponent` | `ULuxTraceComponent*` |
| +0x3B0 | `byte[48]` | `pActiveTraceHashBase` | 6-bucket active-trace hash |
| +0x400 | `int32` | `nKindIndex` | `ELuxTraceKindId` |

#### `FLuxTraceComponentLayout` (1200 bytes)

Includes the 1048-byte `UActorComponent` base plus the trace-component-specific
tail. Field names match the [`ULuxTraceComponent`](#uluxtracecomponent) section
above; this layout is the Ghidra struct definition used for type-aware decompilation.

#### `FTraceActiveParam` (48 bytes — full layout)

The full-layout version of the `FTraceActiveParam` documented above. The Ghidra
struct is 48 bytes, matching `Active_Impl`'s parameter size. The earlier section
lists only the hit-relevant fields; all 48 bytes are below.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `uint8`   | `bAttackTag` | the only field `Active_Impl` reads for hit logic |
| +0x04 | `uint32`  | `dwFlags` | visual |
| +0x08 | `uint16`  | `wSubSlot` | |
| +0x0C | `uint32`  | `dwFrames` | trail duration |
| +0x10 | `bool`    | `bUseDefault` | |
| +0x14 | `uint32`  | `dwReservedInt14` | |
| +0x18 | `uint8`   | `bMode` | |
| +0x1C | `uint8`   | `bEffectParam` | |
| +0x2C | `uint32`  | `dwReserved_2C` | |

### Frame-bounds triangle entry

#### `FLuxFrameBoundsCellRow` (32 bytes) and `FLuxTerrainTriangleEntry` (64 bytes)

The cell-row and triangle-entry types referenced by
[Stage / frame spatial acceleration](#frame-bounds-grid). The Ghidra struct
definitions match the field list documented in that section. `FLuxTerrainTriangleEntry`
holds a vertex triple plus a pre-baked plane equation `(nx,ny,nz,d)`, so
`LuxBattle_IntersectSegmentWithTerrainTriangle @ 0x140390A90` can do the test
in one dot-product per endpoint.

### Misc reflected structs

#### `FLuxAttackTouchParam` (29 bytes)

See [Move System: enums and small structs](move-system.md#fluxattacktouchparam-0x20-bytes) —
fired when a hit registers, holds `(player, position, hit type, attack type, level, can-down)`.

#### `FLuxDamageInfo` (18 bytes)

See [Move System: FLuxDamageInfo](move-system.md#fluxdamageinfo-0x14-bytes) — HUD/network
hit-event payload `(side, damage, total, is_critical, is_limited)`.

#### `FLuxDataTablePath` (24 bytes)

The 24-byte hierarchical-path cursor used by every `LuxDataTable*` writer.
Documented as the vehicle for `BattleManager+0x50` config writes — see
[Battle Manager: FLuxDataTablePath](battle-manager.md#fluxdatatablepath-24-bytes).

### Net / Steam structs (unrelated to hitbox work)

A handful of online-session structs are also defined for the Steam-online
subsystem — `FNamedOnlineSession_Steam` (236 bytes), `FOnlinePresenceSteam`
(496 bytes), `FOnlineSessionInfoSteam` (88 bytes), `FFriendStateRecord`
(232 bytes). Listed for completeness; not relevant to gameplay reversing.
