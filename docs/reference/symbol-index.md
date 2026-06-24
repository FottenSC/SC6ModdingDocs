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
| `InputLog+0xN` | Offset on `ALuxBattleFrameInputLog*`. [Layout](../sc6/structures.md#aluxbattleframeinputlog-17616-bytes). |
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
| `UDemoNetDriver_GotoTimeInSeconds` | `0x141E0ECA0` | [Replay System: scrubbing](../sc6/replay-system.md#scrubbing-a-match-replay-udemonetdrivergototimeinseconds) — UE4 native scrub for match replays |
| `RegisterCVar_DemoGotoTimeInSeconds` | `0x140255B00` | [Replay System: scrubbing](../sc6/replay-system.md#scrubbing-a-match-replay-udemonetdrivergototimeinseconds) — CVar `demo.GotoTimeInSeconds` registrar |

### Replay input serialization

| Symbol | Address | Page |
|---|---|---|
| `LuxReplay_DecodeInputPackets_FromFile` | `0x1403ED310` | [Replay System: custom Lux input replay opcodes](../sc6/replay-system.md#custom-lux-input-replay-opcodes) — expands 3-byte packed records into decoded input records |
| `LuxReplay_EncodeInputEvents_ToBuffer` | `0x1403ED980` | [Replay System: custom Lux input replay opcodes](../sc6/replay-system.md#custom-lux-input-replay-opcodes) — inverse encoder for Lux replay input streams |
| `LuxReplay_WriteThreeByteInputRecord_ToBuffer` | `0x1403F62E0` | [Replay System: custom Lux input replay opcodes](../sc6/replay-system.md#custom-lux-input-replay-opcodes) — appends one packed opcode record |

### Move VM (outer command-script VM)

| Symbol | Address | Page |
|---|---|---|
| `LuxMoveVM_TickDriver` | `0x1403656B0` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveVM_ExecuteAndDumpOpcode` | `0x140365900` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveSystem_StartMoveForChara` | `0x14031C610` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveSystem_TickMove` | `0x140367EE0` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveSystem_TickMoveAndAutoAdvance` | `0x14031C740` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveVM_GetTimeDilationScalar` | `0x14030A8C0` | [Movement: TimeDilation](../sc6/movement.md#timedilation-system-verified) / [Replay: bypass](../sc6/replay-system.md#timedilation-fall-through-paths-bypasses-vmfreezebyte) |
| `LuxMoveVM_TransitionToMove` | `0x1402FE350` | [Hitbox System](../sc6/hitbox-system.md) / [Move System: lane transitions](../sc6/move-system.md#how-transitions-actually-fire) |
| `LuxMoveVM_PostATKDelayGate` | `0x140365520` | [Move System](../sc6/move-system.md#key-vm-entry-points) |
| `LuxMoveVM_OnMoveStart_SnapPositionAndFacing_LockRetrack` | `0x1402FF3E0` | [Movement: retrack](../sc6/movement.md#when-moves-retrack-against-the-opponent-verified) |
| `LuxMoveVM_ApplyMoveOffsetToChara` | `0x140344FC0` | [Movement: code references](../sc6/movement.md#code-references) |
| `LuxBattle_DispatchYarareReaction` | `0x1403521B0` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |

### Reaction System (yarare)

| Symbol | Address | Page |
|---|---|---|
| `LuxBattleChara_ProcessHitReactionState` | `0x140342FF0` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxMoveVM_TickPickAndDispatchReaction` | `0x1402DEF50` | [Reaction System](../sc6/reaction-system.md) / [Hitbox: throw whiff](../sc6/hitbox-system.md#throw-connection-yarare-dispatch) |
| `LuxMoveVM_TickActiveYarareReaction` | `0x14035EF30` | [Reaction System: per-id Tick index](../sc6/reaction-system.md#per-id-init-tick-handler-index) |
| `LuxMoveVM_ProbeSpecialReactionOverride` | `0x1402DFD60` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxMoveVM_RollComboExtensionReaction` | `0x1402E04A0` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxBattle_YarareIdToReactionBitmask` | `0x14035F390` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxBattle_CheckYarareReactionGate` | `0x140362E70` | [Reaction System: 134 gate codes](../sc6/reaction-system.md#checkyararereactiongate-134-gate-codes) |
| `LuxBattle_CheckYarareGate_AttackCategoryGate` | `0x140362C30` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_AttackMotionGate` | `0x140362D30` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_StepRange` | `0x140360650` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_ReactionStateMatch` | `0x140360930` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_BackStepRange` | `0x1403607F0` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_AerialRange` | `0x140361240` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_GroundApproachRange` | `0x140361420` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_RingPositionAdvantage` | `0x1403615C0` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_HitStateRingAdvantage` | `0x140361740` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_OppHitRingAdvantage` | `0x140361820` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_OppAttackRingAdvantage` | `0x1403618F0` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_MutualGuardBreakRange` | `0x140362060` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_ApproachAngleRange` | `0x140362510` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_OppAttackHealthRange` | `0x1403626F0` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckYarareGate_SelfDistanceBucket` | `0x140362790` | [Reaction System: gate family dispatch](../sc6/reaction-system.md#gate-family-dispatch) |
| `LuxBattle_CheckReactionCancelClearance` | `0x140363D10` | [Reaction System: exit conditions](../sc6/reaction-system.md#exit-conditions) |
| `LuxMoveVM_BuildReactionCandidateList` | `0x140363EF0` | [Reaction System: filter chain](../sc6/reaction-system.md#reaction-pick-filter-chain-not-documented-in-detail-see-ghidra) |
| `LuxMoveVM_WeightedSelectReactionCandidate` | `0x1403647C0` | [Reaction System: filter chain](../sc6/reaction-system.md#reaction-pick-filter-chain-not-documented-in-detail-see-ghidra) |
| `LuxMoveVM_SelectReactionSlot` | `0x140351BB0` | [Reaction System: filter chain](../sc6/reaction-system.md#reaction-pick-filter-chain-not-documented-in-detail-see-ghidra) |
| `LuxBattle_PickRingoutReactionYarare` | `0x140353A00` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxBattle_ComputeHitReactionParams` | `0x140343B90` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxBattleChara_ApplyHitReactionMove` | `0x1403448A0` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxBattleChara_DecayHitstunSlideVelocity` | `0x140309160` | [Reaction System: pipeline](../sc6/reaction-system.md#at-a-glance) |
| `LuxMoveVM_AllocReactionParamBlock` | `0x1403306F0` | [Reaction System: FLuxBattleYarareReactionParamBlock](../sc6/reaction-system.md#fluxbattleyararereactionparamblock-1100-byte-global-param-table) |
| `LuxMoveVM_InitReactionParamBlock` | `0x140330760` | [Reaction System: FLuxBattleYarareReactionParamBlock](../sc6/reaction-system.md#fluxbattleyararereactionparamblock-1100-byte-global-param-table) |
| `LuxCameraAction_ActivateKnockdown` | `0x140327F20` | [Reaction System: Knockdown camera](../sc6/reaction-system.md#knockdown-camera-adjacent-state-machine) |
| `LuxCameraAction_InitKnockdown` | `0x1403282F0` | [Reaction System: Knockdown camera](../sc6/reaction-system.md#knockdown-camera-adjacent-state-machine) |
| `LuxCameraAction_TickKnockdown` | `0x14032B380` | [Reaction System: Knockdown camera](../sc6/reaction-system.md#knockdown-camera-adjacent-state-machine) |
| `LuxEffectCamera_UpdateCameraFreezeDuringThrow` | `0x14031B760` | [Reaction System: Throw-react camera](../sc6/reaction-system.md#throw-react-state-machine-camera-side) |
| `LuxEffectCamera_UpdateThrowCameraRotation` | `0x14031B880` | [Reaction System: Throw-react camera](../sc6/reaction-system.md#throw-react-state-machine-camera-side) |
| `LuxBattleChara_UpdateHitVisualLean` | `0x140308310` | [Reaction System: Adjacent visual subsystem](../sc6/reaction-system.md#adjacent-visual-subsystem) |

### Move VM (inner stack-based bytecode interpreter)

| Symbol | Address | Page |
|---|---|---|
| `LuxMoveVM_ExecuteBytecode` | `0x1402E5A30` | [Move System: Inner stack VM](../sc6/move-system.md#inner-stack-based-predicate-vm) |
| `LuxMoveVM_RunBytecodeScript` | `0x1402E67B0` | [Move System: Inner stack VM](../sc6/move-system.md#three-call-sites) |
| `LuxMoveVM_EvaluateIfOpcode` | `0x1403732F0` | [Move System: predicate sub-opcodes](../sc6/move-system.md#callcond-predicate-sub-opcodes-funcidx-0x000x01) |
| `LuxMoveVM_EvaluateIfOpcodeWithHeader` | `0x1402E5830` | [Move System: dispatch table](../sc6/move-system.md#callcond-dispatch-table-g_luxmovevm_opcodeifdispatchtable-143e83a90) |
| `LuxMoveVM_DispatchEffectOp` | `0x140376B20` | [Move System: effect-dispatcher clusters](../sc6/move-system.md#effect-dispatcher-opcode-clusters-luxmovevm_dispatcheffectop) |
| `LuxMoveVM_ResolveBankSlot` | `0x1402FC400` | [Move System: bank readers](../sc6/move-system.md#bank-readers) / [`FLuxMoveBankSlotView`](../sc6/structures.md#fluxmovebankslotview-72-bytes) |
| `LuxMoveVM_ExecuteOpStream` | `0x1402FDEA0` | [Move System: per-tick lane driver](../sc6/move-system.md#three-call-sites) |
| `LuxMoveVM_RunSecondaryLaneScript` | `0x1402FE1C0` | [Move System: per-tick lane driver](../sc6/move-system.md#three-call-sites) |
| `LuxMoveVM_DecodeVariadicStreamArgs` (TransitionAuthor) | `0x1402FC930` | [Move System: how transitions fire](../sc6/move-system.md#how-transitions-actually-fire) |
| `LuxMoveVM_ExecuteBankSlotScript` (CALLCOND 0x0D) | `0x1402FCC30` | [Move System: dispatch table](../sc6/move-system.md#callcond-dispatch-table-g_luxmovevm_opcodeifdispatchtable-143e83a90) |
| `LuxMoveVM_OpcodeIf_15_ScheduleTransitionScript` | `0x1402FCD30` | [Move System: deferred transitions](../sc6/move-system.md#how-transitions-actually-fire) |
| `LuxMoveVM_OpcodeIf_16_DrainPendingTransition` | `0x1402FCDE0` | [Move System: deferred transitions](../sc6/move-system.md#how-transitions-actually-fire) |
| `LuxMoveVM_OpcodeIf_RegisterEffectOpDedup_04` | `0x1402FD4A0` | [`FLuxMoveLane_EffectOp`](../sc6/structures.md#fluxmovelane_effectop-36-bytes) |
| `LuxMoveVM_CheckMoveTransitionTiming` | `0x1402FDD70` | [Move System: how transitions fire](../sc6/move-system.md#how-transitions-actually-fire) |
| `LuxMoveVM_OpcodeIf_05/06/07/08_TransitionAuthor` | `0x1402FCB80..0x1402FCC20` | [Move System: dispatch table](../sc6/move-system.md#callcond-dispatch-table-g_luxmovevm_opcodeifdispatchtable-143e83a90) (thin wrappers around `DecodeVariadicStreamArgs`) |

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
| `LuxBattleManager_BuildActorDependencyGraph_At28` | `0x1403F8A20` | [Battle Manager: subsystem dependency graph](../sc6/battle-manager.md#subsystem-dependency-graph) |

### Battle launcher / match setup

| Symbol | Address | Page |
|---|---|---|
| `ULuxUIBattleLauncher::Start` | `0x1405EEB50` | [Battle Manager: launcher startup](../sc6/battle-manager.md#battle-launcher-startup-path) — copies launch sub-tables into the BattleManager |
| `ULuxUIBattleLauncher::GetBattleStageCode` | `0x1405B0C60` | [Battle Manager](../sc6/battle-manager.md#battle-launcher-startup-path) / [Stage System](../sc6/stage-system.md) — reads `StageSetting.StageCode`, defaults to `STG001` |
| `ULuxUIBattleLauncher::SetSlipOutMode` | `0x1405ED550` | [Battle Manager: known leaf paths](../sc6/battle-manager.md#known-leaf-paths) — writes `BattleRule.SlipOut` |
| `ULuxUIBattleLauncher::SetNoRingOutMode` | `0x1405ECC70` | [Battle Manager: known leaf paths](../sc6/battle-manager.md#known-leaf-paths) — writes `BattleRule.NoRingOut` |
| `ULuxUIBattleLauncher::SetEndlessMode` | `0x1405EC390` | [Battle Manager: known leaf paths](../sc6/battle-manager.md#known-leaf-paths) — writes `BattleRule.Endless` |
| `ULuxUIBattleLauncher::SetDamageUpMode` | `0x1405EC190` | [Battle Manager: known leaf paths](../sc6/battle-manager.md#known-leaf-paths) — writes `BattleRule.DamageUp` |
| `ULuxUIBattleLauncher::SetBlowUpMode` | `0x1405EB7F0` | [Battle Manager: known leaf paths](../sc6/battle-manager.md#known-leaf-paths) — writes `BattleRule.BlowUp` |
| `ULuxUIBattleLauncher::SetRecordMode` | `0x1405ED170` | [Battle Manager: known leaf paths](../sc6/battle-manager.md#known-leaf-paths) — writes top-level `BattleRecord` |

### Trace (visual weapon-trail)

| Symbol | Address | Page |
|---|---|---|
| `ALuxTraceManager::Active_Impl` | `0x1408CD940` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) |
| `ALuxTraceManager::Inactive_Impl` | `0x1408D1420` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) |
| `ALuxTraceManager::GetTracePosition_Impl` | `0x1408D0BB0` | [Trace System: UFunctions](../sc6/trace-system.md#ufunctions-on-aluxtracemanager) (**stale on this build**) |
| `ALuxTraceManager_ActivateTrace_Impl` | `0x1408D5D10` | [Trace System](../sc6/trace-system.md) |
| `ALuxTraceManager_execActivateTrace` | `0x140C41AB0` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_execUpdate` | `0x140C415E0` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_Update_Impl` | `0x1408D5590` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_UpdateActiveAttackSlotPositions` | `0x1408D8490` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_ComputeCapsuleAndDirection` | `0x1408D1100` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_InsertActiveAttackSlot` | `0x1408C8D60` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_DispatchHitRequests` | `0x1408CEB40` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_SetSideActive` | `0x1408D5AB0` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
| `ALuxTraceManager_EffectReg_SetSideActive` | `0x1408D5AD0` | [Trace System: active trace slots](../sc6/trace-system.md#active-trace-slots-and-weapon-capsule-refresh) |
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
| `LuxActor_CollectActors_By8Classes_IntoTArrays` | `0x140417A70` | [Stage System: collision storage](../sc6/stage-system.md#stage-collision-storage) |
| `GetScbattleStageInfoBarrierGeometry` | `0x1402D7730` | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `SetScbattleStageInfoBarrierGeometry` | `0x1402D77C0` | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `LuxStage_RegisterBarrierActor_BattleEvent0x19` | `0x140427490` | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `LuxStage_RegisterWallActor_BattleEvent0x19` | `0x140428EE0` | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `LuxBattle_SetFrameCacheHitChkDataPtrs` | `0x1402DAE70` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `LuxBattle_ApplyFrameCacheHitChkDataSetup` | `0x1403CFC20` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `LuxObject_BuildParamSlots_FromBattleSubstrings_4Slots` | `0x1404208B0` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `Z_Construct_UClass_ULuxStageAssetPaths` | `0x140BACDB0` | [structures](../sc6/structures.md#uluxstageassetpaths-and-luxstagerawasset) |
| `Z_Construct_UScriptStruct_LuxStageRawAsset` | `0x140BD8C60` | [structures](../sc6/structures.md#uluxstageassetpaths-and-luxstagerawasset) |
| `Z_Construct_UEnum_LuxorGame_ELuxStageAssetType` | `0x140BBF230` | [structures](../sc6/structures.md#uluxstageassetpaths-and-luxstagerawasset) |
| `LuxBattle_RefreshFrameTerrainCache` | `0x140314480` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `LuxBattle_AttachStgHitChkData` | `0x140392080` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `LuxBattle_SampleTerrainAtXZ_Impl` | `0x140391350` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `LuxBattle_TestAndResolveWallCollision` | `0x140316600` | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |

### Audio / Voice

| Symbol | Address | Page |
|---|---|---|
| `LuxMoveVM_TriggerAudioPaletteCallback` | `0x1403693D0` | [Audio: Path A](../sc6/audio-system.md#path-a-audio-palette-tween-opcode-0x3a) |
| `LuxMoveVM_TickCharaEventCueScheduler` | `0x14038BD60` | [Audio: Path B](../sc6/audio-system.md#path-b-sound-cue-submission-event-scheduler) |
| `LuxAudio_PlayCueIdByByte` | `0x140550900` | [Audio: CRI middleware](../sc6/audio-system.md#cri-middleware-functions-the-playback-layer) |
| `LuxAudio_RegisterActiveVoiceInstance` | `0x14054F8B0` | [Audio: CRI middleware](../sc6/audio-system.md#cri-middleware-functions-the-playback-layer) |
| `LuxAudio_GetCriAtomManagerSingleton` | `0x140547D60` | [Audio: CRI middleware](../sc6/audio-system.md#cri-middleware-functions-the-playback-layer) |
| `LuxAudio_ResolveCueSheetEntryByKey` | `0x140547210` | [Audio: CRI middleware](../sc6/audio-system.md#cri-middleware-functions-the-playback-layer) |
| `LuxAudio_LookupVoiceCueIDConvTable` | `0x140425610` | [Audio: DataTable lookups](../sc6/audio-system.md#datatable-driven-config-lookups) |
| `LuxAudio_LookupDramaticVoiceData` | `0x140422930` | [Audio: DataTable lookups](../sc6/audio-system.md#datatable-driven-config-lookups) |
| `LuxAudio_LookupSoundBusDackingData` | `0x140423F40` | [Audio: DataTable lookups](../sc6/audio-system.md#datatable-driven-config-lookups) |
| `LuxAudio_LookupStageMaterialSoundTable` | `0x1404247B0` | [Audio: DataTable lookups](../sc6/audio-system.md#datatable-driven-config-lookups) |
| `LuxAudio_LookupWeaponBankIdTable` | `0x140425B80` | [Audio: DataTable lookups](../sc6/audio-system.md#datatable-driven-config-lookups) |
| `LuxObject_GetWeaponBankId_BySoulChargeAndBone` | `0x140425D00` | [Audio: weapon SE routing](../sc6/audio-system.md#weapon-se-bank-routing) |
| `LuxAudio_CreateAsyncLoader_WeaponSoundACB` | `0x14042C130` | [Audio: DLC ACB index map](../sc6/audio-system.md#dlc-weapon-acb-index-map) |
| `ALuxBattleChara_SelectAndPlaySound_Ranked` | `0x1403C8950` | [Audio: ranked flavor voice](../sc6/audio-system.md#2-ranked-match-flavor-voice) |
| `ResolveDramaticVoiceID_FromBattleSetting` | `0x1405F2910` | [Audio: DramaticVoice](../sc6/audio-system.md#3-dramaticvoice-story-persona) |
| `RegisterCompiledInClass_ULuxDramaticVoiceDataAsset` | `0x140161AD0` | [Audio: DramaticVoice](../sc6/audio-system.md#3-dramaticvoice-story-persona) |
| `LuxBattleChara_SyncAudioActiveState_FromBattleFlags` | `0x140438980` | [Audio: chara offsets](../sc6/audio-system.md#chara-offset-map-audio-state-on-aluxbattlechara) |
| `LuxAudio_ResolveCharaAudioComponentSlot` | `0x1404265D0` | [Audio: UAtomComponent bridge](../sc6/audio-system.md#ue-side-uatomcomponent-bridge) |
| `LuxAudio_FireSoundCue_ViaVfxDispatcher` | `0x1403110B0` | [Audio: VFX+Audio dispatcher](../sc6/audio-system.md#vfx-audio-dispatcher-g_pluxvfxdispatcher) — chokepoint for burst-playback mitigation |
| `LuxAudio_InitVoiceAcbMap_Char060` | `0x14040EB40` | [Audio: per-character ACB maps](../sc6/audio-system.md#per-character-voice-acb-maps) |
| `LuxAudio_OnCharaPartUnregister_RecordReplayIfActive` | `0x140427DF0` | [Audio System](../sc6/audio-system.md) — replay capture of audio state on chara teardown |
| `ULuxCeBankManager_StaticClass` | `0x1409A59D0` / `0x1409A92C0` | [Audio: per-character ACB maps](../sc6/audio-system.md#per-character-voice-acb-maps) |
| `LuxVoice_AddVoiceItemsForPose` | `0x14038D350` | [Audio: Enshutsu](../sc6/audio-system.md#enshutsu-cinematic-voice-subsystem) |
| `LuxVoice_EnshutsuHeader_AddVoiceItem` | `0x14038BC40` | [Audio: Enshutsu](../sc6/audio-system.md#enshutsu-cinematic-voice-subsystem) |
| `Audio_RandomTick` | `0x140399B70` | [Audio: determinism](../sc6/audio-system.md#replay-determinism) |

### Online / netplay

| Symbol | Address | Page |
|---|---|---|
| `ALuxBattleManager_CheckOnlineSessionActive` | `0x1403F2590` | [Leaderboards & Online: detection](../sc6/leaderboards.md#detection-is-this-match-online) — the canonical "are we online" gate |
| `ALuxBattleManager_IsBattleOnline` | `0x1403F1A60` | [Leaderboards & Online: detection](../sc6/leaderboards.md#detection-is-this-match-online) — world-context-aware wrapper |
| `GetLocalOnlineSession` | `0x1403F07A0` | [Leaderboards & Online: Steam interface accessors](../sc6/leaderboards.md#steam-interface-accessors) |
| `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache` | `0x1403F6770` | [Leaderboards & Online: per-frame input chain](../sc6/leaderboards.md#per-frame-input-chain-channel-5) |
| `LuxOnline_PushToRingBuffer_WithCriticalSection` | `0x1403F4BE0` | [Leaderboards & Online: per-frame input chain](../sc6/leaderboards.md#per-frame-input-chain-channel-5) |
| `LuxOnline_SendInputPacket_PerFrame_Opcode0` | `0x1403F84E0` | [Leaderboards & Online](../sc6/leaderboards.md#per-frame-input-chain-channel-5) — 3 B/slot/frame send |
| `LuxOnline_SendInputPacket_BatchedRange_Opcode1` | `0x1403F8710` | [Leaderboards & Online](../sc6/leaderboards.md#per-frame-input-chain-channel-5) — re-send for catch-up |
| `LuxOnline_DispatchNetMessage_ByKeyString` | `0x1403E0520` | [Leaderboards & Online: 3-channel protocol](../sc6/leaderboards.md#three-channel-protocol) — channel 7 (UI mirror) |
| `LuxOnlineBattleSync_OnRecvBattleSync_Dispatcher` | `0x140511CF0` | [Leaderboards & Online: 3-channel protocol](../sc6/leaderboards.md#three-channel-protocol) — channel 6 (KV handshake) |
| `LuxBattleManager_GetCachedRoundValue_ByIndex` | `0x1403F0720` | [Leaderboards & Online](../sc6/leaderboards.md#the-per-slot-input-cache-at-frameinputlog0x3c0) — cache reader |
| `LuxBattleChara_UpdatePlayerInputData_FromRoundCache` | `0x1403FCD10` | [Leaderboards & Online](../sc6/leaderboards.md#per-frame-input-chain-channel-5) — game-tick consumer |
| `LuxBattleChara_InitPlayerBitmask_FromOnlineSession` | `0x1403FA330` | [Leaderboards & Online: detection](../sc6/leaderboards.md#detection-is-this-match-online) — sets `dwOnlineActive` |
| `LuxBattleManager_InitOnlineSession_SetFlag1640` | `0x1403FB400` | [Leaderboards & Online: lobby entry points](../sc6/leaderboards.md#lobby-matchmaking-entry-points) |
| `LuxOnline_DisconnectAndClearSession` | `0x1403EDD00` | [Leaderboards & Online: lobby entry points](../sc6/leaderboards.md#lobby-matchmaking-entry-points) |
| `LuxBattleManager_UpdateOnlineFrameSyncCounter_At1638` | `0x1403FDEC0` | [Leaderboards & Online: delay-based](../sc6/leaderboards.md#delay-based-no-rollback) — stall counter |
| `LuxMatchLobby_RequestReady` | `0x1405EA160` | [Leaderboards & Online: lobby entry points](../sc6/leaderboards.md#lobby-matchmaking-entry-points) |
| `LuxLobby_DispatchUICommand` | `0x1405E21E0` | [Leaderboards & Online: lobby entry points](../sc6/leaderboards.md#lobby-matchmaking-entry-points) |
| `OnlineSubsystem_GetSubsystem_FromModule` | `0x1403BCFF0` | [Leaderboards & Online: Steam interface accessors](../sc6/leaderboards.md#steam-interface-accessors) — 64 callers |
| `Steam_InitAllInterfaces` | `0x1404C3DD0` | [Leaderboards & Online: Steam interface accessors](../sc6/leaderboards.md#steam-interface-accessors) — 21-iface bootstrap |
| `LuxOnline_GetPlayerProfileWriterInterface` | `0x140718540` | [Leaderboards & Online: Steam interface accessors](../sc6/leaderboards.md#steam-interface-accessors) — 53 callers |

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
the runtime-extension behaviour of `ALuxBattleChara` — where fields past
`+0x1438` exist beyond the registered class size — see the chara entry's
note on lazy extensions.

| Struct | Size | Page anchor |
|---|---|---|
| `ALuxBattleManager` | (large; subsystem layout in topic page) | [structures](../sc6/structures.md#aluxbattlemanager) / [battle-manager](../sc6/battle-manager.md#battlemanager-subsystem-layout) |
| `ALuxBattleChara` | `0x568` (registered) → ~`0x973F0` runtime | [structures](../sc6/structures.md#aluxbattlechara) |
| `FLuxBattleChara` (Ghidra) | `0x973F0` | [structures](../sc6/structures.md#aluxbattlechara) |
| `ALuxBattleFrameInputLog` | `~0x44D0` (17616) | [structures](../sc6/structures.md#aluxbattleframeinputlog-17616-bytes) |
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
| `FLuxMoveLane` (was `LuxMoveLaneState`) | `0x468` | [structures](../sc6/structures.md#fluxmovelane-1128-bytes-was-luxmovelanestate) |
| `FLuxMoveLane_EffectOp` | `0x24` | [structures](../sc6/structures.md#fluxmovelane_effectop-36-bytes) |
| `LuxMoveLaneState_Motion` | `0x44` | [structures](../sc6/structures.md#luxmovelanestate_motion-68-bytes-the-small-motion-playback-record) |
| `FLuxBattleMessageParam` | `0x0C` | [messages](../sc6/messages.md#fluxbattlemessageparam-verified-struct) |
| `FLuxBattleYarareReactionParamBlock` | `0x44C` (1100) | [reaction-system](../sc6/reaction-system.md#fluxbattleyararereactionparamblock-1100-byte-global-param-table) |
| `FLuxBattleVMFreezeRecord` | `0x40` | [structures](../sc6/structures.md#fluxbattlevmfreezerecord-64-bytes) |
| `LuxBattleCharaMotionFlags` | `0x40` | [structures](../sc6/structures.md#luxbattlecharamotionflags-64-bytes) |
| `FLuxDataTablePath` | `0x18` | [structures](../sc6/structures.md#fluxdatatablepath-24-bytes) |
| `KHitBase` / `KHitFixArea` (runtime node) | `0xA0` | [structures](../sc6/structures.md#fluxkhitnode-160-bytes-full-node-view) |
| `FActiveAttackSlot` | `0x44` | [structures](../sc6/structures.md#factiveattackslot-68-bytes) |
| `FBatchedLine` | `0x34` | [structures](../sc6/structures.md#fbatchedline-0x34-bytes) |
| `LuxBattleStageInfoTableRow` | `0x108` | [stage-system](../sc6/stage-system.md#luxbattlestageinfotablerow) |
| `LuxBattleStageBasePositionParam` | `0x28` | [stage-system](../sc6/stage-system.md#luxbattlestagebasepositionparam) |
| `scbattle_BarrierEntry` | `0x10` | [structures](../sc6/structures.md#scbattle-stage-info-globals) |
| `scbattle_StageBoundaryParams` | `0x40` | [structures](../sc6/structures.md#scbattle-stage-info-globals) |
| `scbattle_StageInfoParam` | `0x120` | [structures](../sc6/structures.md#scbattle-stage-info-globals) |
| `FLuxBattleEventRecord` | `0x18` | [structures](../sc6/structures.md#stage-actor-registration-event-record) |
| `ULuxStageAssetPaths` | class | [structures](../sc6/structures.md#uluxstageassetpaths-and-luxstagerawasset) |
| `LuxStageRawAsset` | `0x18` | [structures](../sc6/structures.md#uluxstageassetpaths-and-luxstagerawasset) |
| `LuxBattle_FrameCacheHitChkDataSetup` | `0x22` | [structures](../sc6/structures.md#j_stghitchkdata-frame-cache-setup) |
| `J_StgHitChkData_Header` | `0x30` | [structures](../sc6/structures.md#j_stghitchkdata-serialized-terrainwall-blob) |
| `J_StgHitChkData_CellHeader` | `0x10` | [structures](../sc6/structures.md#j_stghitchkdata-serialized-terrainwall-blob) |
| `J_StgHitChkData_PoolChunk` | variable | [structures](../sc6/structures.md#j_stghitchkdata-serialized-terrainwall-blob) |

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

### Audio state

| Offset | What | Page |
|-------:|------|------|
| `+0x394` | u32 audio active/mute bitfield (bit 0 should-play, bit 1 force-active, bit 2 force-mute, bit 3 always-active) | [Audio: chara offsets](../sc6/audio-system.md#chara-offset-map-audio-state-on-aluxbattlechara) |
| `+0x95750` | Event cue scheduler struct (sound + anim-notify timing) | [Audio: Path B](../sc6/audio-system.md#path-b-sound-cue-submission-event-scheduler) |
| `+0x95788` | Secondary action stack (sound-cue submit port) | [Audio: Path B](../sc6/audio-system.md#path-b-sound-cue-submission-event-scheduler) |
| `+0x971A8..+0x971B8` | `FLuxAudioPaletteTween` (palette id, frames-left, current/target/delta-per-frame) | [Audio: Path A](../sc6/audio-system.md#path-a-audio-palette-tween-opcode-0x3a) |

### Other

| Offset | What | Page |
|-------:|------|------|
| `+0x29130` | `pSubcompListHead` (sub-component linked list; null = chara mid-rebuild) | [structures](../sc6/structures.md#aluxbattlechara) |
| `+0x973E8` | **Opponent** chara back-ref | [structures](../sc6/structures.md#aluxbattlechara) |

---

## InputLog offsets (most-cited)

Layout source: [structures.md / ALuxBattleFrameInputLog](../sc6/structures.md#aluxbattleframeinputlog-17616-bytes).

| Offset | What |
|-------:|------|
| `+0x398` | `bEnable` (nNumPlayerSlots) |
| `+0x39C` | `dwPlaybackCursor` (bmActivePlayerSlots) |
| `+0x3A0` | `nLastFrameID` |
| **`+0x3A4`** | **`nMasterClock`** — INC'd by R1/R2 every UE4 frame; pinned by `Horse::ReplayClockGate` during freeze |
| `+0x3A8` | `pRecordedFrameBuffer` (`FLuxRecordedFrame[]`, 192 B/entry) |
| `+0x3AC` | sub-tick advance counter (INC'd via `vtable[0x5F8]` from Site 20) |
| `+0x3B0` | `nTotalRecordedFrames` |
| **`+0x3C0`** | **`pReplayInputCache`** (`FLuxReplayInputCacheEntry[1024]`, 16 KB) — `[2 slots][512 entries][16 B]`. Filled by the online drain; empty during offline / .replay viewing. |
| **`+0x4400`** | **`dwOnlineActive`** — 0=offline/spectator, 1/2=local player side, 3=hidden lobby. Drain entry guard. |
| `+0x4404` | `bDoubleTickGuard` (R2 prologue checks this) |
| `+0x4414` | `nMinStoreFrameIndex` — drain watermark |
| `+0x4424` | `bSessionShutdownState` — `5` = drain bails |
| `+0x4428` | `pSentInputBitmap` (88 B dedupe) |
| `+0x4480` | `pDequeStorage` — inbound-packet deque |
| `+0x44A0` | `qwDequeCount` — capped at 100 (drop-oldest) |
| `+0x44A8` | `DequeLock` (`CRITICAL_SECTION`, 40 B) |

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
| `0x144844010` | `g_scbattle_StageInfo_RngSeed` | Host-broadcast stage-info seed at the head of `scbattle_StageInfoParam`. | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `0x144844020` | `g_sScbattleStageBoundaryParams` | 64-byte origin/spawn/facing parameter block. | [structures](../sc6/structures.md#scbattle-stage-info-globals) |
| `0x14484406C` | `g_dwScbattleStageInfoBarrierValid` | Ring-boundary valid flag, not an entry count. | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `0x144844070` | `g_aScbattleStageInfoBarrierEntries` | Fixed `scbattle_BarrierEntry[12]` deterministic ring-boundary buffer. | [Stage System: scbattle ring-boundary block](../sc6/stage-system.md#scbattle-ring-boundary-block) |
| `0x14470D0D0` | `g_pLuxBattle_StgHitChkDataA` | Serialized `J_StgHitChkData*` attached into frame-bounds grid A. | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `0x14470D0F8` | `g_pLuxBattle_StgHitChkDataB` | Serialized `J_StgHitChkData*` attached into frame-bounds grid B. | [Stage System: J_StgHitChkData terrain/wall grid](../sc6/stage-system.md#j_stghitchkdata-terrainwall-grid) |
| `0x14470DEDC` | `g_LuxBattle_FrameContextUseB` | Selects frame-transform/grid A vs B. | [structures](../sc6/structures.md#frame-bounds-grid) |
| `0x144844DD0` | `g_LuxBattle_FrameBoundsGridA` | Live terrain/wall frame-bounds grid A. | [structures](../sc6/structures.md#frame-bounds-grid) |
| `0x144845E80` | `g_LuxBattle_FrameBoundsGridB` | Live terrain/wall frame-bounds grid B, embedded in FrameTransformB at `+0xC60`. | [structures](../sc6/structures.md#frame-bounds-grid) |
| `0x143E87838` | `KHitBase_vftable` | Vtable for the `KHitBase` family. | [structures](../sc6/structures.md#hit-detection-node-structs-khit) |
| `0x1448554E8` | `g_LuxBattle_HitReactionSlideTable` | Per-hit-type slide-decay curves. | [Movement: code references](../sc6/movement.md#code-references) |
| `0x14470E018` | `g_LuxBattle_YarareReactionParamBlock` (lazy-malloc'd) | The 1100-byte `FLuxBattleYarareReactionParamBlock` (per-intensity reach/knockback/weight tables). | [Reaction System](../sc6/reaction-system.md#fluxbattleyararereactionparamblock-1100-byte-global-param-table) |
| `0x14470E310` | per-charaKind ring-margin table | stride `0x8`, indexed by `chara+0x23C` `CharaKindByte`. Used by every "ring-advantage" gate. | [Reaction System: ring-margin formula](../sc6/reaction-system.md#ring-margin-formula) |
| `0x14470E330` | per-charaKind reach-offset table | stride `0x180`, scanned linearly (`{u32, s16 oppMoveStateId, s16 reachOffset}`). Subtracted from dispatcher's `nScaledKnockbackReach`. | [Reaction System: ring-margin formula](../sc6/reaction-system.md#ring-margin-formula) |
| `0x144711F88` | per-charaKind hit-intensity attribute table | stride `0xC0E`. First `int32` = base intensity for sub-handlers (0x42, 0x32, 0x1F). | [Reaction System: ring-margin formula](../sc6/reaction-system.md#ring-margin-formula) |

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
