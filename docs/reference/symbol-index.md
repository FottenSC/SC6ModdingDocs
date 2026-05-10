# Symbol Index

Cross-cutting lookup tables for the **most-cited** symbols in these docs.

This page is **not exhaustive** — for a complete answer, read the topic
page each row links to. The intent is "I have a symbol/offset, where do I
look?", not "give me every fact about it".

All addresses absolute, image base `0x140000000`.

## How to find a fact (AI agent cheat sheet)

| You have ... | Do this |
|---|---|
| A function address (`0x140xxxxxx`) | `grep -rn "0x140xxxxxx" docs/` — all topic pages cite addresses inline |
| A function name | Grep the same; or [search the table below](#functions-most-cited) |
| A struct name | [Game Structures](../sc6/structures.md) is canonical; [size table below](#structs-most-cited) for quick size lookup |
| A `chara+0xN` offset | [chara offset table below](#chara-offsets-most-cited); follow link for the topic page that uses it |
| A `BM+0xN` offset | [Battle Manager subsystem layout](../sc6/battle-manager.md#battlemanager-subsystem-layout) — full 43-slot map |
| A global (`g_*`, `DAT_*`) | [Globals table below](#globals-most-cited); or grep — globals are usually cited inline |
| A `vmCtx+0xN` offset | [Move System: VM globals](../sc6/move-system.md#key-vm-globals) and [opcode scratch layout](../sc6/move-system.md#vm-opcode-scratch-layout-offsets-on-g_luxmovevm_commandplayerarrayslot) |
| An opcode (`0x40002`, `0x50008`, ...) | [Move System: opcode quick reference](../sc6/move-system.md#opcode-quick-reference) |
| A KHit list head | [Hitbox System: three list heads](../sc6/hitbox-system.md#three-list-heads-on-every-chara) |
| A vtable slot index | [Trace System](../sc6/trace-system.md) for `Active`/`Inactive` slots; [Hitbox System](../sc6/hitbox-system.md) for `KHitBase` family |

## Verification status conventions

Words used consistently across these docs:

| Marker | Meaning |
|---|---|
| **verified** | Read directly from the SC6 Steam binary via Ghidra decompile or runtime UE4SS introspection. Trust this. |
| **unverified** | Plausible but not directly read. May be cite-by-analogy or general fighting-game knowledge. Don't build on without checking. |
| **stale on this build** | Function/path exists in the binary but isn't reached at runtime. The shipping codepath has moved elsewhere. Don't use. |
| `> source:` blockquote | Specific Ghidra address / function plate-comment the claim is built on. Treat as the authoritative pointer. |
| `!!! warning` admonition | Known landmine, layout error, or correction notice. Read before acting. |

## Conventions

| Notation | Meaning |
|---|---|
| `chara+0xN` | Offset on `ALuxBattleChara*` (size 0x568, runtime extension to ~0x97000). [Layout](../sc6/structures.md#aluxbattlechara). |
| `BM+0xN` | Offset on `ALuxBattleManager*`. [Layout](../sc6/battle-manager.md#aluxbattlemanager-layout). |
| `vmCtx+0xN` | Offset on `FLuxMoveCommandPlayer*` (per-chara VM slot, 0x302C bytes). [Layout](../sc6/structures.md#fluxmovecommandplayer-12332-bytes). |
| `InputLog+0xN` | Offset on `ALuxBattleFrameInputLog*`. [Layout](../sc6/structures.md#aluxbattleframeinputlog-17428-bytes). |
| RVA `0xN` | Image-relative; absolute address = `0x140000000 + RVA`. Some "Code references" tables use RVAs. |
| `_Impl` suffix | The C++ body of a UFunction (e.g. `Active_Impl`). Game often calls these directly, bypassing the exec trampoline. |
| `Z_Construct_*` | UE4 reflection registrar — runs at startup to register a UClass / UStruct / UFunction / UEnum. |

---

## Functions (most-cited)

Sorted by the symbol — grep this section for the function name; follow
the page link for full context.

### Tick drivers and per-frame chains

| Symbol | Address | Page |
|---|---|---|
| `LuxBattle_PerFrameTick` | `0x1402DBC60` | [Replay System: Site 9](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |
| `LuxBattle_TickCharaMainSimulation` | `0x14034DA70` | [Movement: per-tick chara update flow](../sc6/movement.md#the-per-tick-chara-update-flow) |
| `LuxBattle_TickHitResolutionAndBodyCollision` | `0x14033CCA0` | [Hitbox System](../sc6/hitbox-system.md) |
| `LuxBattleManager_Update_Impl` | `0x140437590` | [Battle Manager: per-frame Update_Impl](../sc6/battle-manager.md#per-frame-update_impl) |
| `LuxBattleManager_Tick_MainStateMachine_At1461` | `0x1403FBF30` | [Replay System: Site 21](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |
| `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState` | `0x1403FE520` | [Replay System: SimulationLoop catch-up](../sc6/replay-system.md#simulationloop-catch-up) |
| `LuxBattleChara_Tick_AdvanceReplayFrame_OrLocal` | `0x1403F8410` | [Replay System: Site 11](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |
| `LuxBattleChara_VTable648_TickAndAdvanceReplayClock` | `0x1403E1FC0` | [Replay System: master clock R1](../sc6/replay-system.md#the-replay-master-clock-and-what-advances-it) |
| `LuxBattleChara_VTable648_TickAndAdvanceReplayClock_GatedBy4404` | `0x1403E2000` | [Replay System: master clock R2](../sc6/replay-system.md#the-replay-master-clock-and-what-advances-it) |
| `LuxActor_Tick_CallVtable5f8` | `0x1403FBDF0` | [Replay System: Site 20](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |
| `ALuxBattleChara_TickActor` | `0x1403D0590` | [Replay System: Site 22](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |
| `ALuxDemoHumanActor_TickActor` | `0x1404865B0` | [Replay System: Site 22b](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |
| `APreviewHumanActor_TickActor` | `0x140486C60` | [Replay System: Site 22c](../sc6/replay-system.md#the-seven-tick-paths-to-halt-for-a-frozen-replay) |

### Move VM

| Symbol | Address | Page |
|---|---|---|
| `LuxMoveVM_TickDriver` | `0x1403656B0` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveVM_ExecuteAndDumpOpcode` | `0x140365900` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveSystem_StartMoveForChara` | `0x14031C610` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveSystem_TickMove` | `0x140367EE0` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveSystem_TickMoveAndAutoAdvance` | `0x14031C740` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveVM_GetTimeDilationScalar` | `0x14030A8C0` | [Movement: TimeDilation](../sc6/movement.md#timedilation-system-verified) / [Replay: bypass](../sc6/replay-system.md#timedilation-fall-through-paths-bypasses-vmfreezebyte) |
| `LuxMoveVM_TransitionToMove` | `0x1402FE350` | [Hitbox System](../sc6/hitbox-system.md) |
| `LuxMoveVM_PostATKDelayGate` | `0x140365520` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveVM_OnMoveStart_SnapPositionAndFacing_LockRetrack` | `0x1402FF3E0` | [Movement: retrack](../sc6/movement.md#when-moves-retrack-against-the-opponent-verified) |
| `LuxMoveVM_ApplyMoveOffsetToChara` | `0x140344FC0` | [Movement: code references](../sc6/movement.md#code-references) |
| `LuxBattle_DispatchYarareReaction` | `0x1403521B0` | [Move System](../sc6/move-system.md#key-vm-entry-points) |

### Physics integration

| Symbol | Address | Page |
|---|---|---|
| `LuxBattleChara_IntegratePhysics_PerTick` | `0x140306BB0` | [Movement: integrator](../sc6/movement.md#what-integratephysics_pertick-actually-does) |
| `LuxBattleChara_ApplyHitCueRootMotion_DirectPositionWrite` | `0x140306530` | [Movement](../sc6/movement.md#whats-verified-about-applyhitcuerootmotion_directpositionwrite) |
| `LuxBattleChara_ApplyResidualVelocity_PostTick` | `0x140304280` | [Movement: code references](../sc6/movement.md#code-references) |
| `LuxBattleChara_RetrackFacingTowardOpponent` | `0x140369450` | [Movement: retrack gate](../sc6/movement.md#when-moves-retrack-against-the-opponent-verified) |
| `LuxBattleChara_ApplyFacingRotationDelta` | `0x140311350` | [Movement: code references](../sc6/movement.md#code-references) |
| `LuxBattleChara_SetMotionInputFlag` | `0x140304C00` | [Movement: motion-input flag bank](../sc6/movement.md#motion-input-flag-bank) |
| `LuxBattleChara_SetStartPosition` | `0x140301E60` | [Game Structures: chara reset offsets](../sc6/structures.md#aluxbattlechara) |
| `LuxBattle_PositionCharasSymmetrically` | `0x140302670` | [Game Structures: chara reset offsets](../sc6/structures.md#aluxbattlechara) |

### Battle Manager UFunctions

| Symbol | Address | Page |
|---|---|---|
| `ALuxBattleManager::PlayMove_Impl` | `0x140429840` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ALuxBattleManager::PlayMoveDirect_Impl` | `0x1404298E0` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ALuxBattleManager::StopMove_Impl` | `0x140434410` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ALuxBattleManager::ChangeBattleLife_Impl` | `0x14059B630` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ALuxBattleManager::ChangeBattleRounds_Impl` | `0x14059CCF0` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ALuxBattleManager::ChangeBattleTime_Impl` | `0x14059CEA0` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ALuxBattleManager::NotifyCharaMoveEnded_Impl` | `0x1403F9200` | [Battle Manager: UFunction map](../sc6/battle-manager.md#ufunction-map) |
| `ULuxBattleFunctionLibrary::SetBattlePause` (UFunction) | `0x140936190` | [Battle Manager: pause](../sc6/battle-manager.md#pause-inspection-bp-api-uluxbattlefunctionlibrary) |
| `LuxBattleManager_RegisterOnTickWhenPaused_Delegates` | `0x1403F8E70` | [Battle Manager: OnBattleTickWhenPaused](../sc6/battle-manager.md#onbattletickwhenpaused-what-still-ticks-during-setbattlepausetrue) |

### Trace (visual weapon-trail)

| Symbol | Address | Page |
|---|---|---|
| `ALuxTraceManager::Active_Impl` | `0x1408CD940` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) |
| `ALuxTraceManager::Inactive_Impl` | `0x1408D1420` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) |
| `ALuxTraceManager::GetTracePosition_Impl` | `0x1408D0BB0` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) (**stale on this build**) |
| `ALuxTraceManager_ActivateTrace_Impl` | `0x1408D5D10` | [Trace System](../sc6/trace-system.md) |
| `Z_Construct_UClass_ALuxTraceManager_Properties` | `0x140C0BA90` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) |

### KHit / classifier

| Symbol | Address | Page |
|---|---|---|
| `LuxBattle_SolvePhysBodyCollision` | `0x14030CCF0` | [Hitbox System](../sc6/hitbox-system.md#three-list-heads-on-every-chara) |
| `LuxBattleChara_UpdateAllKHitWorldCenters` | `0x14030D6A0` | [Hitbox System](../sc6/hitbox-system.md) |
| `LuxBattleChara_CheckGuardConditionForHitbox` | `0x1403056E0` | [Hitbox System: block direction](../sc6/hitbox-system.md#block-direction-ducking-while-guarding) |
| `LuxBattleChara_UpdateGuardStanceFlags` | `0x140309370` | [Hitbox System: per-frame stance update](../sc6/hitbox-system.md#per-frame-stance-update-luxbattlechara_updateguardstanceflags-0x140309370) |
| `LuxMoveVM_GetCharaEffectiveHeight` | `0x140309470` | [Hitbox System: throw connection](../sc6/hitbox-system.md#throw-connection-the-size-height-bucket-gate) |
| `LuxBattle_ResolveAttackVsHurtboxMask22` | `0x14033C100` | [Hitbox System](../sc6/hitbox-system.md) |

### Stage system

| Symbol | Address | Page |
|---|---|---|
| `GetStageCodes_BuildMasterList` | `0x140640890` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `GetStageCodesIfAvailable_FilterByDLCChunks` | `0x1406409F0` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `IsValidStageCodeStr_LookupInMasterEnum` | `0x140647230` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `ResolveStageCodeToAssetPath` | `0x140641840` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `GetStageLocIdByStageCode` | `0x1406415B0` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `ApplyBattleSettingDataTableToBattleManager` | `0x140594EB0` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `LuxBattle_CreateStageInfoHandler` | `0x1403C3010` | [Stage System: key entry points](../sc6/stage-system.md#key-entry-points) |
| `LuxActor_CollectActors_By8Classes_IntoTArrays` | `0x140417A70` | [Stage System: two-tier collision](../sc6/stage-system.md#two-tier-collision-gameplay-vs-visuals) |

### DataTable helpers (`FLuxDataTablePath`)

| Symbol | RVA | Page |
|---|---|---|
| `LuxDataTablePath_Ctor` | `0x2ED0AA0` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxDataTablePath_Dtor` | `0x2ED6A80` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxDataTablePath_AppendString` | `0x2EDA150` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxDataTablePath_AppendInt` | `0x2EDA300` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxDataTable_Resolve` | `0x2F2EE30` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxDataTable_Commit` | `0x2ED9000` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxDataTable_AddFloatRow` | `0x2F4E370` | [Battle Manager: helper API](../sc6/battle-manager.md#helper-api) |
| `LuxBattleRule_BuildTrainingModeDataTablePath` | `0x5D6F40` | [Battle Manager: boot-to-training](../sc6/battle-manager.md#boot-straight-to-training-recipe) |

---

## Structs (most-cited)

Authoritative size + layout: [Game Structures](../sc6/structures.md). For
the runtime-extension behaviour of `ALuxBattleChara` (where fields past
`+0x1438` exist beyond the registered class size), see the chara entry's
note on lazy extensions.

| Struct | Size | Page anchor |
|---|---|---|
| `ALuxBattleManager` | (large; subsystem layout in topic page) | [structures](../sc6/structures.md#aluxbattlemanager) / [battle-manager](../sc6/battle-manager.md#battlemanager-subsystem-layout) |
| `ALuxBattleChara` | `0x568` (registered) → ~`0x973F0` runtime | [structures](../sc6/structures.md#aluxbattlechara) |
| `FLuxBattleChara` (Ghidra) | `0x973F0` | [structures](../sc6/structures.md#aluxbattlechara) |
| `ALuxBattleFrameInputLog` | `0x4414` (17428) | [structures](../sc6/structures.md#aluxbattleframeinputlog-17428-bytes) |
| `ALuxBattleReplayPlayer` | `0x3D1` (977) | [structures](../sc6/structures.md#aluxbattlereplayplayer-977-bytes) |
| `ALuxBattleKeyRecorder` | `0x3BC` (956) | [structures](../sc6/structures.md#aluxbattlekeyrecorder-956-bytes) |
| `ALuxTraceManager` | `0x408` | [structures](../sc6/structures.md#aluxtracemanager) |
| `ULuxTraceComponent` | `0x4B0` | [structures](../sc6/structures.md#uluxtracecomponent) |
| `FLuxCapsule` | `0x50` | [trace-system](../sc6/trace-system.md#fluxcapsule-0x50-bytes) |
| `FLuxMoveCommandPlayer` | `0x302C` (12332) | [structures](../sc6/structures.md#fluxmovecommandplayer-12332-bytes) |
| `FLuxMoveBank` | `0x30` | [structures](../sc6/structures.md#fluxmovebank-48-bytes) |
| `FLuxMoveBankCell` | `0x70` | [structures](../sc6/structures.md#fluxmovebankcell-112-bytes) |
| `FLuxMoveBankSlotView` | `0x48` | [structures](../sc6/structures.md#fluxmovebankslotview-72-bytes) |
| `FLuxMoveDefEntry` | `0x10` | [structures](../sc6/structures.md#fluxmovedefentry-16-bytes) |
| `FLuxBattleMoveListTableRow` | `0x88` | [move-system](../sc6/move-system.md#fluxbattlemovelisttablerow-0x88-bytes) |
| `LuxMoveLaneState` | `0x468` | [structures](../sc6/structures.md#luxmovelanestate-1128-bytes) |
| `FLuxBattleMessageParam` | `0x0C` | [messages](../sc6/messages.md#fluxbattlemessageparam-verified-struct) |
| `FLuxBattleVMFreezeRecord` | `0x40` | [structures](../sc6/structures.md#fluxbattlevmfreezerecord-64-bytes) |
| `LuxBattleCharaMotionFlags` | `0x40` | [structures](../sc6/structures.md#luxbattlecharamotionflags-64-bytes) |
| `FLuxDataTablePath` | `0x18` | [structures](../sc6/structures.md#fluxdatatablepath-24-bytes) |
| `KHitBase` / `KHitFixArea` (runtime node) | `0xA0` | [structures](../sc6/structures.md#fluxkhitnode-160-bytes-full-node-view) |
| `FActiveAttackSlot` | `0x44` | [structures](../sc6/structures.md#factiveattackslot-68-bytes) |
| `FBatchedLine` | `0x34` | [structures](../sc6/structures.md#fbatchedline-0x34-bytes) |
| `LuxBattleStageInfoTableRow` | `0x108` | [stage-system](../sc6/stage-system.md#luxbattlestageinfotablerow) |
| `LuxBattleStageBasePositionParam` | `0x28` | [stage-system](../sc6/stage-system.md#luxbattlestagebasepositionparam) |

---

## Chara offsets (most-cited)

Layout source: [Game Structures: ALuxBattleChara](../sc6/structures.md#aluxbattlechara).
Anywhere `chara+0xN` appears in these docs, the type is documented there.

### Position / motion

| Offset | What | Used by |
|-------:|------|---------|
| `+0x90` | `flVelocityZ` | [SetStartPosition / PositionCharasSymmetrically](../sc6/structures.md#aluxbattlechara) |
| `+0x94` | `flVelocityX` | same |
| `+0x98` | `flVelocityY` (**aliased** with `ALuxBattleManager*` per `SetupWeaponBones`) | [structures](../sc6/structures.md#aluxbattlechara) |
| `+0xA0..+0xA8` | `flStartPosX/Y/Z` (round-spawn target) | [SetStartPosition](../sc6/structures.md#aluxbattlechara) |
| `+0xC0..+0xC8` | `flCurPosX/Y/Z` (game-thread current pose) | [Movement: integrator](../sc6/movement.md#what-integratephysics_pertick-actually-does) |
| `+0x130` / `+0x138` | MoveVelocity X / Z (per-tick velocity) | [Movement: integrator](../sc6/movement.md#what-integratephysics_pertick-actually-does) |
| `+0x140` / `+0x148` | "Ground" velocity X / Z | [Movement: integrator](../sc6/movement.md#what-integratephysics_pertick-actually-does) |
| `+0x150` / `+0x158` | One-shot offset X / Z | [Movement: integrator](../sc6/movement.md#what-integratephysics_pertick-actually-does) |
| `+0x1F0` / `+0x1F8` | Pushback velocity (decayed by hit-state machine) | [Movement: integrator](../sc6/movement.md#what-integratephysics_pertick-actually-does) |
| `+0x2090..+0x2098` | `flRenderPosX/Y/Z` (render pose, written each frame) | [SetStartPosition](../sc6/structures.md#aluxbattlechara) |
| `+0x23C` | `bPlayerSlotIndex` / `bSideByte` (P1=0 / P2=1 side flag) | many |
| `+0x3490` | Float scalar — multiplies the `+0x130` velocity term in the integrator | [Movement: integrator](../sc6/movement.md#what-changes-movement-verified-levers-only) |
| `+0x3500` | `flMoveTimeScaleA` (per-chara base time-scale; returned by TimeDilation fall-through) | [Movement: TimeDilation](../sc6/movement.md#timedilation-system-verified) |
| `+0x3510` | `flHitStopTrigger` (negative → Path A in TimeDilation) | [Movement: TimeDilation](../sc6/movement.md#timedilation-system-verified) |

### Motion-input flag bank (`+0x16D0..+0x170F`)

64-byte bank, indexed by flag id 0..0x3F. Full table in
[structures.md / LuxBattleCharaMotionFlags](../sc6/structures.md#luxbattlecharamotionflags-64-bytes).
High-traffic flags:

| Offset | Flag idx | Name |
|-------:|:-:|------|
| `+0x16D2` | 0x02 | `bGuardCrouchStateBase` (authoritative crouch state) |
| `+0x16E2` | 0x12 | `bAirborneFlag` (when CLEARED snaps Y to terrain) |
| `+0x16E5` | 0x15 | `bClassifyEnableGate` |
| `+0x16E6` | 0x16 | "in non-walk state" — read by retrack gate |
| `+0x16FB` | 0x2B | Damped-mode flag (selects damped path in IntegratePhysics) |
| `+0x16FC` | 0x2C | `bAltGuardCrouchState` (per-frame alt crouch) |
| `+0x16FD` | 0x2D | `bIsGuardingFlag` |
| `+0x1701` | 0x31 | `bAltGuardLocked` |

### KHit list heads + classifier

| Offset | What | Page |
|-------:|------|------|
| `+0x44478` | `BodyListHead` (pushbox / chara-to-chara physical pushing) | [Hitbox System: three list heads](../sc6/hitbox-system.md#three-list-heads-on-every-chara) |
| `+0x44498` | `AttackListHead` (entries that DEAL damage) | same |
| `+0x444B8` | `HurtboxListHead` (entries that RECEIVE damage) | same |
| `+0x44058` | `pCurrentAttackCellPtrPtr` (double-ptr to active attack cell) | [Hitbox System](../sc6/hitbox-system.md) |
| `+0x44060` | `NonAttackMoveDescrPtr` (non-damaging supers / SC finishers / stance / GI / parry) | [Hitbox System](../sc6/hitbox-system.md) |

### Replay-relevant chara fields

| Offset | What | Page |
|-------:|------|------|
| `+0x39C` | `dwReplayPlaybackCursor` | [Replay System](../sc6/replay-system.md) |
| `+0x3A0` | `dwReplayLastFrameID` | same |
| `+0x3A4` | `dwReplayMasterClock` | same |
| `+0x4400` | `dwReplayEnableFlag` (read by Site 11 prologue) | [Replay System: Site 11](../sc6/replay-system.md) |
| `+0x4424` | `bCharaMode` | same |

### Other

| Offset | What | Page |
|-------:|------|------|
| `+0x29130` | `pSubcompListHead` (sub-component linked list; null = chara mid-rebuild) | [structures](../sc6/structures.md#aluxbattlechara) |
| `+0x973E8` | **Opponent** chara back-ref | [structures](../sc6/structures.md#aluxbattlechara) |

---

## InputLog offsets (most-cited)

Layout source: [structures.md / ALuxBattleFrameInputLog](../sc6/structures.md#aluxbattleframeinputlog-17428-bytes).

| Offset | What |
|-------:|------|
| `+0x39C` | `dwPlaybackCursor` |
| `+0x3A0` | `nLastFrameID` |
| **`+0x3A4`** | **`nMasterClock`** — INC'd by R1/R2 every UE4 frame; pinned by `Horse::ReplayClockGate` during freeze |
| `+0x3A8` | `pRecordedFrameBuffer` (`FLuxRecordedFrame[]`, 192 B/entry) |
| `+0x3AC` | sub-tick advance counter (INC'd via `vtable[0x5F8]` from Site 20) |
| `+0x3B0` | `nTotalRecordedFrames` |
| `+0x4404` | `bDoubleTickGuard` (R2 prologue checks this) |

---

## Globals (most-cited)

| Address | Symbol | What | Page |
|---|---|---|---|
| `0x1448462D0` | `g_LuxBattle_VMFreezeRecord` | 64-byte freeze/slow-mo record. `+0x00 bVMFreezeByte`, `+0x04 flBaseAlpha`. | [Movement: TimeDilation](../sc6/movement.md#timedilation-system-verified) |
| `0x14470F390` | `g_LuxMoveVM_CommandPlayerArray` | Per-chara VM state, stride `0xC0E`. Slot indexed by `chara+0x23C`. | [Move System](../sc6/move-system.md#key-vm-globals) |
| `0x144710060` | `g_LuxMoveSystem_DataTableA` | Per-chara move-definition data, stride `0x3038`. | [Move System](../sc6/move-system.md#key-vm-globals) |
| `0x14470FCD8` | `g_LuxCharaAttrTable_Byte_0x181cStride` | Per-chara byte table (yarare frames etc.). | [Move System](../sc6/move-system.md#key-vm-globals) |
| `0x1447123BC` | `g_LuxCharaAttrTable_Int_0x3038Stride` | Per-chara int table. | [Move System](../sc6/move-system.md#key-vm-globals) |
| `0x1440F4750` | `g_LuxMoveStateTable` | Move-state ids, stride `0x14`, `0x29` rows. | [Move System](../sc6/move-system.md#key-vm-globals) |
| `0x144149C50` | `g_LuxStage_MasterEnumStringTable` | `TArray<FBattleStageEnumEntry>` — 31 stock entries. | [Stage System: master enum table](../sc6/stage-system.md#master-enum-table) |
| `0x143E87838` | `KHitBase_vftable` | Vtable for the `KHitBase` family. | [structures](../sc6/structures.md#hit-detection-node-structs-khit) |
| `0x1448554E8` | `g_LuxBattle_HitReactionSlideTable` | Per-hit-type slide-decay curves. | [Movement: code references](../sc6/movement.md#code-references) |

---

## Vtable slots (referenced)

| Slot | On | Role | Page |
|---:|---|---|---|
| `[0x5F8]` | `ALuxBattleFrameInputLog` | Sub-tick chain dispatched by Site 20 (counter advance + Stage 2/3 input dispatch) | [Replay System](../sc6/replay-system.md) |
| `[0x648]` | `LuxBattleChara` | Tick + master-clock advance (R1/R2) | [Replay System](../sc6/replay-system.md#the-replay-master-clock-and-what-advances-it) |
| `[0x6A8]` | `LuxBattleChara` | Stage 2/3 input pipeline (replay mode) | [Replay System: Stage 2/3](../sc6/replay-system.md#stage-23-input-pipeline-vtable0x6a8-0x6c8) |
| `[0x6C8]` | `LuxBattleChara` | Chara replay-state writer (replay mode) | [Replay System: Stage 2/3](../sc6/replay-system.md#stage-23-input-pipeline-vtable0x6a8-0x6c8) |
| `[208]` | `ALuxBattleChara` | `GetWeaponData` | [Battle Manager: BM+0x1450 note](../sc6/battle-manager.md#match-level-data) |

---

## Notes on this index

- The tables aim for the ~80 highest-frequency lookups — **not** a complete inventory.
  Pages are still authoritative; this is a navigational shortcut.
- When in doubt, **grep the actual address** across `docs/sc6/`. Every cited
  address appears inline at least once on its owning page.
- If a row here disagrees with the topic page, the **topic page wins** (it
  has the source citation). File a fix to this page.
