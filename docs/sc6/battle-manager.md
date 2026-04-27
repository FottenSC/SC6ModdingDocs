# Battle Manager & DataTable Config Tree

`ALuxBattleManager` is the authoritative per-match actor. Owns: player chara list, per-frame
axis/input buffer, move-command pipeline, and a hierarchical `FLuxDataTable` config tree at
`+0x50` (round rules, timer, per-player settings).

All addresses on this page are absolute (image base `0x140000000`).

## At a glance

### Most-used offsets on `ALuxBattleManager`

| Offset | Type | What |
|-------:|------|------|
| `+0x050` | `FLuxDataTable` | `ConfigTable` — see [DataTable path tree](#lux-datatable-path-tree) |
| `+0x098` | `UObject*` | `GameState` |
| `+0x140` | `UObject*` | (lazy MoveComponent slot — **not** related to `world+0x140` `OwningGameInstance`) |
| `+0x388` | `UClass*` | `BattleCharaClass` (TSubclassOf, NOT an embedded chara) |
| `+0x390` | `ALuxBattleChara**` | `PlayerCharas.Data` |
| `+0x398` | `int32` | `NumPlayerCharas` |
| `+0x3A8` | `ALuxBattleCamera*` | `Camera` |
| `+0x478` | `ALuxBattleFrameInputLog*` | `FrameInputLog` |
| `+0x488` | `ALuxBattleReplayPlayer*` | `ReplayPlayer` |
| `+0x4B8` | `ALuxBattleKeyRecorder*` | `KeyRecorder` (training-mode "Recorded" input) |
| `+0x4C0` | `ALuxBattleMoveCommandPlayer*` | `MoveCommandPlayer` — VM host (likely live capsule data) |
| `+0x12F3` | `bool` | `GlobalAxisInhibit` |
| `+0x1450/+0x1458` | TSharedPtr pair | move-provider / weapon-data context |
| `+0x1463` | `uint8` | global match move-state byte (`5=playing`, `6=stopping`) |

Full subsystem map of all 43 slots in `+0x00..+0x800`: see
[BattleManager subsystem layout](#battlemanager-subsystem-layout).

### Key UFunctions (call via reflection)

| UFunction | RVA | Behaviour |
|-----------|-----|-----------|
| `PlayMove(PlayerIdx, MoveTableIdx, MoveIdx)` | `0x429840` | bounds-check + tail-call `PlayMoveDirect` |
| `PlayMoveDirect(PlayerIdx, MoveDef*)` | `0x4298E0` | dispatches to MoveComponent or stages into `PendingMoveCommand` |
| `StopMove(PlayerIdx)` | `0x434410` | writes `(Stop, -1)` into pending; sets chara move-state = 6; fires `NotifyCharaMoveEnded` |
| `ChangeBattleLife(bRight, idx, float[2])` | `0x59B630` | writes `LifeInit` / `LifeMax` |
| `ChangeBattleRounds(int)` | `0x59CCF0` | writes `BattleRule.Rounds` |
| `ChangeBattleTime(uint8)` | `0x59CEA0` | enum → seconds via lazy static TMap |
| `ChangeBattlePlayerSetting(bRight, idx, Setting*)` | `0x59C6F0` | replace / append per-side row |
| `GetTracePositionForPlayer(...)` | `0x3F4960` | wraps `GetTracePosition` by `(playerIdx, slot)` |
| `NotifyCharaMoveEnded(playerIdx+1, finishReason)` | `0x3F9200` | 1-based playerIdx (not a typo — game-wide convention) |

### Pause / inspection BP API — `ULuxBattleFunctionLibrary`

CDO at `/Script/LuxorGame.Default__LuxBattleFunctionLibrary`. Reflection-callable. The
breakthrough function: **`SetBattlePause(bPause, inType, WorldContext)`** is the same path
the in-game pause menu uses — cleanly halts replay timer, replay cursor, round timer, and
chara hitstop in one call. Sibling UFunctions:

| UFunction | Role |
|-----------|------|
| `BattlePauseEnabled` | predicate — pause system available? |
| `GetBattleManager` | returns active `ALuxBattleManager*` |
| `GetBattlePauseController` | returns active pause controller |
| `IsBattleOnline` / `IsBattleOnlineInputSync` | online-match predicates |
| `IsBattlePaused` / `IsBattlePlaying` / `IsMatchFinished` | match-state predicates |
| `IsFinishBlow` | predicate — current frame is finish-blow? |
| `IsLocalUserControl` | predicate — local input controlling? |
| `SetBattlePause` | **engine pause path.** UFunction at `0x140936190`. Param struct (16B): `bool bPause; uint8 inType; UObject* WorldContext`. |
| `SetImmortality` / `SetSoulGaugeInfinity` / `SetUserInputCheck` | toggle helpers |
| `StepInBattlePause` | frame-step while paused |

---

## `ALuxBattleManager` layout

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x050 | `FLuxDataTable` | ConfigTable | see *DataTable path tree* below |
| +0x098 | `UObject*` | GameState | isa-checked against `ALuxBattleManager` every branch in `Update` |
| +0x388 | `UClass*` | BattleCharaClass | `TSubclassOf<ALuxBattleChara>` — the UClass pointer used to spawn player charas. **Not** an embedded chara: an embedded `ALuxBattleChara` (size 0x568) starting here would collide with Camera/EventListener at +0x3A8..+0x408. Per `Z_Construct_UClass_ALuxBattleManager @ 0x140949450`'s plate. |
| +0x390 | `ALuxBattleChara**` | PlayerCharas.Data | `TArray<ALuxBattleChara*>` — canonical iteration point for all active fighters |
| +0x398 | `int32` | NumPlayerCharas | |
| +0x3A0 | `uint8` | PendingMoveCommandType | 1 = PlayMove, 2 = Stop |
| +0x3A8 | `int32` | PendingMoveCommandParam | player index |
| +0x3B0 | `FLuxMoveCommandData` | PendingMoveCommandData | cleared/filled by PlayMoveDirect / StopMove (size ≥ 0x18; exact layout unverified) |
| +0x3E0 | `bool` | SavedLuxorPhotographyAllowed | `PlayMove` saves `LuxPhotography::IsLuxorAllowed()` here and force-disables the CVar for the duration; `StopMove` restores it. Not a "command player" flag — the name was a misread in an earlier pass. |
| +0x400 | `float*` | AxisValues (dyn) | per-tick axis buffer |
| +0x408 | `int32` | AxisCount | |
| +0x410 | `uint8*` | AxisInhibitFlags (dyn) | bytes; when set, the tick zeroes that axis |
| +0x418 | `int32` | AxisInhibitCount | |
| +0x420 | `float` | AxisXAccumulator | decays toward 0 each tick |
| +0x424 | `float` | AxisYAccumulator | decays toward 0 each tick |

> source: `ALuxBattleManager::Update_Impl @ 0x140437590`, `PlayMove_Impl @ 0x140429840`,
> `PlayMoveDirect_Impl @ 0x1404298e0`, `StopMove_Impl @ 0x140434410`.

## BattleManager subsystem layout

Runtime-verified map of UObject-pointer slots on `ALuxBattleManager`.
Captured 2026-04-19 via UE4SS class-name introspection of every 8-byte
slot in `BM+0x00..+0x800`. All 43 subsystem pointers that were live in
a training match are listed. Addresses in the middle column are
examples of one particular run; treat them as "this slot holds a
pointer to an instance of class X" rather than fixed addresses.

!!! warning "`ALuxBattleManager_GetMoveProviderPtr @ 0x140546600` is misnamed"
    The Ghidra symbol suggests the function reads `*(ALuxBattleManager* + 0x140)`.
    It does not — it reads `*(ptr + 0x140)` on whatever its single parameter
    is, and the sole caller (`ALuxBattleChara::GetMoveProvider @
    0x1403F00B0`) passes a **`ULuxGameInstance*`**, not a `ALuxBattleManager*`.
    The chain is:

    ```text
    chara->GetWorld()                      -> UWorld*
    *(UWorld* + 0x140)                     -> OwningGameInstance
                                              (= ULuxGameInstance* on SC6,
                                                 Z_Construct_UClass @ 0x140A55E60;
                                                 short-form static-class getter
                                                 at 0x140A51870 registers name
                                                 "LuxGameInstance" with size 0x220)
    ISA-check against ULuxGameInstance     -> bail if it fails
    *(ULuxGameInstance* + 0x140)           -> move-provider / move-component
    ```

    So the real chain is `UWorld → ULuxGameInstance → MoveProvider`, not
    `UWorld → ALuxBattleManager → MoveProvider`. `ALuxBattleManager` is
    reached separately through `GetBattleManagerFromWorldContext @
    0x1403EF7A0` (and its `_Checked` sibling at `0x1403EF860`; see
    `Update_Impl`'s own lookup pattern), and `BattleManager+0x140` is not
    part of the move-provider chain at all on this build.

    Runtime observation: `*(ULuxGameInstance + 0x140)` on a live training
    match appears as the IEEE 754 value `0x3F800000` (float `1.0f`).
    Either the slot is recycled as a tickrate / scale field in this
    build, or the MoveProvider pointer was moved and this address is
    stale. Downstream, `ALuxBattleChara::GetMoveProvider` caches that
    non-pointer at `chara+0x1438` on first call, so subsequent calls
    return whatever `1.0f` is treated as (currently "misinterpreted 8-byte
    bit pattern" — not dereferenceable). See the
    [`ALuxBattleChara` runtime-layout note](structures.md#aluxbattlechara)
    for the downstream consequences.

### Camera & events
| Offset | Type | Name |
|-------:|------|------|
| +0x3A8 | `ALuxBattleCamera*`             | Camera |
| +0x3B8 | `ULuxBattleEventListener*`      | EventListener |
| +0x3C8 | `ULuxBattleVFxEventHandler*`    | VFxEventHandler |
| +0x3D8 | `ULuxBattleSoundEventHandler*`  | SoundEventHandler |
| +0x3E8 | `ULuxBattleStageEventHandler*`  | StageEventHandler |
| +0x3F8 | `ULuxBattleTraceEventHandler*`  | TraceEventHandler |
| +0x408 | `ALuxBattleWeaponEventHandler*` | WeaponEventHandler (hosts the `ReceiveGetWeaponTip` BP event — [see note](trace-system.md#receivegetweapontip-promising-looking-dead-end)) |
| +0x410 | `ULuxBattlePauseTicker*`        | PauseTicker |
| +0x420 | `ULuxBattlePauseController*`    | PauseController |
| +0x430 | `ULuxBattleShortcutController*` | ShortcutController |

### Input & replay
| Offset | Type | Name |
|-------:|------|------|
| +0x440 | `ULuxBattleCommonInput*`        | CommonInput |
| +0x450 | `ULuxBattleFrameInput*`         | FrameInput |
| +0x460 | `ULuxBattleFrameStream*`        | FrameStream |
| +0x478 | `ALuxBattleFrameInputLog*`      | FrameInputLog — full layout in [Structures](structures.md#aluxbattleframeinputlog-17428-bytes); 17 KB ring buffer of `FLuxRecordedFrame` (192 bytes each ≈ 90-frame budget) plus a per-tick double-tick guard at `+0x4404` |
| +0x480 | `ULuxBattleReplayRecorder*`     | ReplayRecorder |
| +0x488 | `ALuxBattleReplayPlayer*`       | ReplayPlayer — see [Structures](structures.md#aluxbattlereplayplayer-960-bytes) for layout (round + time + state-reset blob + recording stream) |

### Training-mode managers
| Offset | Type | Name |
|-------:|------|------|
| +0x490 | `ULuxBattleTrainingManager*`    | TrainingManager |
| +0x498 | `ULuxBattleGaugeTypeChanger*`   | GaugeTypeChanger |
| +0x4A0 | `ULuxBattlePositionResetter*`   | PositionResetter |
| +0x4A8 | `ULuxBattleDummyCustomizer*`    | DummyCustomizer |
| +0x4B0 | `ULuxBattleAICustomizer*`       | AICustomizer |
| +0x4B8 | `ALuxBattleKeyRecorder*`        | KeyRecorder — Training-mode "Recorded" input playback. Layout in [Structures](structures.md#aluxbattlekeyrecorder-956-bytes); slot table holds `FLuxBattleKeyRecorderSlot` (12 bytes per queued input: duration / wait-counter / move-id) |

### Move system (critical for hit-detection work)
| Offset | Type | Name |
|-------:|------|------|
| +0x4C0 | `ALuxBattleMoveCommandPlayer*`    | MoveCommandPlayer — the command-script VM actor. See [Move System](move-system.md). Per-move capsule/hit data is believed to live inside this object. |
| +0x4C8 | `ULuxBattleTrainingReplayPlayer*` | TrainingReplayPlayer |

### Flow & demo
| Offset | Type | Name |
|-------:|------|------|
| +0x4D0 | `ULuxBattleDramaticVoice*`      | DramaticVoice |
| +0x4D8 | `ULuxBattleMissionManager*`     | MissionManager |
| +0x4E0 | `ULuxBattleMissionResultDemo*`  | MissionResultDemo |
| +0x4E8 | `ULuxBattleTutorialManager*`    | TutorialManager |
| +0x4F0 | `ULuxBattleVariableAI*`         | VariableAI |

### Stage, timing, VFX
| Offset | Type | Name |
|-------:|------|------|
| +0x4F8 | `ULuxBattleTimeManager*`        | TimeManager |
| +0x500 | `ULuxBattleStageActorManager*`  | StageActorManager |
| +0x508 | `ULuxVFxInstanceManager*`       | VFxInstanceManager — spawns trace VFx via `BattleMgrSubsystem_LookupOrAllocateMeshActorSlot @ 0x1408A2660`. |
| +0x510 | `ULuxBattleStageInfinityManager*` | StageInfinityManager |
| +0x518 | `ULuxBattleColorFadeManager*`   | ColorFadeManager |
| +0x520 | `ULuxBattleSound*`              | Sound |

### HUD, audio, replay tail
| Offset | Type | Name |
|-------:|------|------|
| +0x528 | `ULuxBattlePlayerDataWatcher*`       | PlayerDataWatcher |
| +0x530 | `ULuxBattleHUDManager*`              | HUDManager |
| +0x538 | `ULuxBattleSpecialtyVFxManager*`     | SpecialtyVFxManager |
| +0x540 | `ULuxBattleSpecialtySEManager*`      | SpecialtySEManager |
| +0x548 | `ULuxBattleSubtitleManager*`         | SubtitleManager |
| +0x550 | `ULuxBattleAchievementChecker*`      | AchievementChecker |
| +0x558 | `ULuxBattleRealtimeMultiplayManager*` | RealtimeMultiplayManager |

### Match-level data
| Offset | Type | Name |
|-------:|------|------|
| +0x1420 | `UMaterialParameterCollection*` | BattleMPC |
| +0x1450 | `UObject*` (TSharedPtr.Target)  | Target half of a TSharedPtr pair read by `LuxMoveProviderRef_Get @ 0x14045FC70` (vtable[0x10]=IsValid, [0x100]=GetDefaultSubProvider) and `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0` (vtable[0xE0]=GetSubProviderByIndex). The same pointer appears to be consumed by `ALuxBattleChara` vtable slot 208 (`GetWeaponData`) and slots 210/211 (`GetBoneDataSharedPtr`), so the concrete class is ambiguous — it behaves like a unified provider rather than a pure MoveProvider. |
| +0x1458 | `void*` (TSharedPtr.Ctrl)       | Refcount control block for the `+0x1450` pair (classic TSharedPtr layout: weak-count at +0x8, strong-count at +0xC). |
| +0x1463 | `uint8`                         | Global match move-state byte (`5 = playing`, `6 = stopping`) — written by `ALuxBattleManager_SetMoveState @ 0x1403F8370` |

> source: UE4SS class-name introspection of every 8-byte-aligned slot
> in `BM+0x00..+0x800` on a live training-match instance, captured by
> HorseMod's BattleManager slot-map diagnostic (2026-04-19).
> `Z_Construct_UClass_ALuxBattleManager @ 0x140949450` registered size.

Chara sub-structures touched by the move dispatcher:

```text
chara+0x30  void*   MoveTables.data       // TArray<FMoveTable> data ptr
chara+0x38  int32   MoveTables.count
  FMoveTable { MoveEntry* data(+0x0); int32 count(+0x8); ... }   // 0x10 bytes
  MoveEntry  { MoveId id(+0x0); MoveDef* def(+0x8); ... }        // 0x18 bytes
chara+0x458 ALuxTraceManager* TraceManager   (see trace-system.md)
```

## UFunction map

| UFunction | Impl @ | Notes |
|---|---|---|
| `PlayMove(PlayerIndex, MoveTableIndex, MoveIndex)` | `0x140429840` | validates bounds on `PlayerCharas` and `MoveTables`, saves + clears the Luxor-Photography CVar, then tail-calls `PlayMoveDirect_Impl(this, PlayerIndex, &entry->def)`. |
| `PlayMoveDirect(PlayerIndex, MoveDef*)` | `0x1404298e0` | low-level entry point. Either dispatches the move straight onto the chara's MoveComponent/CommandPlayer, or stages it in `PendingMoveCommand` for the next tick — branch depends on MoveComponent state. |
| `StopMove(PlayerIndex)` | `0x140434410` | restores the saved Luxor-Photography CVar, writes `PendingMoveCommand = (Stop, -1)` into `+0x3A0/+0x3A8/+0x3B0`, calls `ALuxBattleChara::SetMoveState(chara, 6)`, then fires `NotifyCharaMoveEnded(gameState, playerIdx+1, 1)`. |
| `ChangeBattleLife(bPlayerRight, Index, float[2])` | `0x14059B630` | writes `LifeInit` / `LifeMax` under the side's gauge path |
| `ChangeBattleRounds(int Rounds)` | `0x14059CCF0` | writes `BattleRule.Rounds` |
| `ChangeBattleTime(uint8 TimeEnum)` | `0x14059CEA0` | enum → seconds via a lazily-built static TMap |
| `ChangeBattlePlayerSetting(bPlayerRight, Index, Setting*)` | `0x14059C6F0` | replaces the row at that index, or appends if out of range |
| `GetTracePositionForPlayer({playerIdx,slot}, outHilt, outTip)` | `0x1403F4960` | resolves `(playerIdx, slot)` to the right chara and its `FLuxCapsule` tag, then calls `ALuxBattleChara::GetTracePosition_Impl` |
| `NotifyCharaMoveEnded(playerIdx+1, finishReason)` | `0x1403F9200` | 1-based playerIdx convention — the `+1` is not a typo, it's how the game encodes the "which side" field everywhere this helper is called from |

## Per-frame `Update_Impl`

The game's per-match tick. Instead of polling UE4's input system, the BattleManager
fetches axis values from a first-party **input processor** it holds a weak ref to
on the GameState:

```text
GameState+0x1420   UObject*  MoveCommandPlayer     (FName timer handles live here)
GameState+0x1450   UObject*  InputProcessor
GameState+0x1458   UObject*  InputProcessorRef     (refcount twin)
```

Each tick it calls the processor vtable (primary Y axis via `[+0x18]`, per-player
via `[+0xE0]`, axis accessor `[+0xB0]`) for up to 4 players, rolls min/max into
`AxisValues[]`, and:

- Pushes `(DeltaTime, AxisValues[p+2])` into each player's `ALuxTraceManager::Update_Impl`
  — that's what feeds `ULuxTraceComponent +0x444/+0x448 LastInputX/Y`.
- Ticks the `BattleTime` and `BattleSystemTime` FName timer handles on the
  MoveCommandPlayer.
- Sets `HasAxisInput` bool at `Owner+0x8AE` if `AxisValues[4] > 0`.

AxisInhibitFlags let specific axes be force-zeroed per-tick (used by pause / cinematic
paths). A global inhibit lives at `BattleManager+0x12F3` — when set, every axis is
zeroed regardless of the per-axis flag.

> source: `ALuxBattleManager::Update_Impl @ 0x140437590` (plate comment in Ghidra
> holds the full annotated flow).

## Lux DataTable path tree

The `ConfigTable` at `BattleManager+0x50` is not a standard `UDataTable`. It's a
hierarchical refcounted key-value tree addressed by string/int path segments.
All `ChangeBattle*` UFunctions are thin shims that build a path cursor, walk to
a leaf, and assign a value node into it.

### `FLuxDataTablePath` (24 bytes)

Every path / cursor on the API is this 24-byte value struct (stack-allocated
at every call site):

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `void*` | Vtable | always `PTR_FUN_143D81E88` — path-object vtable |
| +0x08 | `FLuxDataNode*` | pNodeRef | raw pointer into the refcounted node tree |
| +0x10 | `FRefCountBox*` | pRefCountBox | 0x18-byte holder with `{vtable, strongCount @+8, weakCount @+0xC, node @+0x10}` — same twin-counter pattern as UE's `TSharedRef` |

### Value-node type tags

Inside `pNodeRef`, each node carries an int32 type tag at `node->Inner + 0x08`:

| Tag | Semantic | Storage |
|:-:|---|---|
| 3 | float leaf | value stored as **double** at `+0x10` (every writer widens float → double) |
| 5 | int-indexed collection (array) | children accessed via `AppendInt(idx)`; countable via `LuxDataTable_GetRowCount` |
| 6 | string-keyed map | children accessed via `AppendString("key")` |

Any other tag is a non-collection / non-float leaf (strings, enum-strings, bools, etc.)
and makes `GetRowCount` return `-1`.

### Typical writer pattern

```cpp
// Every ChangeBattle* / LuxBattleRule_Build* impl looks like this
FLuxDataTablePath p, out, resolved;
LuxDataTablePath_Ctor(&p);                        // null-anchor; real root is
                                                  // wired in by subsequent ops
LuxDataTablePath_AppendString(&p,   &out,      "PlayerRight");
LuxDataTablePath_AppendInt   (&out, &out,      playerIndex);      // PlayerRight[0]
LuxDataTablePath_AppendString(&out, &out,      "PlayerParam");
LuxDataTablePath_AppendString(&out, &out,      "Gauge");
LuxDataTable_AddFloatRow     (&out, &resolved, "LifeInit", 240.f);  // leaf assign
// Commit to the live table (copy-assign the cursor onto the table's slot):
LuxDataTable_Commit          (&this->ConfigTable, &resolved);
// Dtor on every stack path releases the refs.
```

`LuxDataTable_Commit` is **both** a path copy-assign and the commit step — a
path is a refcounted cursor, and rebinding a cursor onto the table's root
slot is how writes publish. The helper has a fast path when the source is a
type-5 or type-6 node (adopts the refcount box in place instead of allocating
a fresh handle + box pair).

`LuxDataTablePath_AppendFloat` is **not** a key-append — the tree doesn't use
float keys. It's the leaf-value constructor ("make the RHS of `path = value`"
for a float). Use `LuxDataTable_AddFloatRow` instead when you want
`path[key] = float`.

### Known leaf paths

| Path | Type | Writer |
|---|---|---|
| `BattleRule.Rounds` | int | `ChangeBattleRounds` |
| `CommonParam.BattleTime` | int (seconds) | `ChangeBattleTime` |
| `<side>[idx].PlayerParam.Gauge.LifeInit` | float | `ChangeBattleLife` |
| `<side>[idx].PlayerParam.Gauge.LifeMax` | float | `ChangeBattleLife` |
| `<side>[idx]` (whole row) | struct | `ChangeBattlePlayerSetting` |

`<side>` is literal `"PlayerLeft"` or `"PlayerRight"`; `idx` is the 0-based
per-side slot.

### `BattleTime` enum → seconds

Built lazily in `ChangeBattleTime_Impl` (C++ `_Init_thread`-guarded static TMap):

| Enum | Seconds |
|:-:|:-:|
| 0 | `0xFFFFFFFF` (infinite) |
| 1 | 99 |
| 2 | 60 |
| 3 | 45 |
| 4 | 30 |
| 5 | 15 |

An unknown enum value is dropped silently (no-op commit).

### Helper API

| Symbol | RVA | Role |
|---|---|---|
| `LuxDataTablePath_Ctor` | `0x2ED0AA0` | zero-init a 24-byte path; seats the null-node sentinel |
| `LuxDataTablePath_Dtor` | `0x2ED6A80` | dual-counter refcount release (27 303 callers — every stack path's cleanup) |
| `LuxDataTablePath_AppendString` | `0x2EDA150` | walk one string-keyed step (map / type-6) |
| `LuxDataTablePath_AppendInt` | `0x2EDA300` | walk one int-indexed step (array / type-5) |
| `LuxDataTablePath_AppendFloat` | `0x2ED0E30` | **leaf-value constructor** for float (type-3 node, stores as double) |
| `LuxDataTable_Resolve` | `0x2F2EE30` | materialise lazy path into a live cursor; dispatches on typeTag |
| `LuxDataTable_Commit` | `0x2ED9000` | path copy-assign; when dst is the table root, also commits |
| `LuxDataTable_AddFloatRow` | `0x2F4E370` | `path[key] = float` (map-keyed float write) |
| `LuxDataTable_GetRowCount` | `0x4DC9B0` | child count if path resolves to type-5; `-1` otherwise |
| `LuxDataTablePath_InitAsNull` | `0x2ED1370` | allocate an empty-node path pair (used by Append* fall-back) |
| `LuxDataTablePath_AssignValue` | `0x2ED9550` | **actual leaf-write primitive** — wires a value node into a cursor slot (called by every builder after constructing a value via `MakeInt` / `MakeBool` / `MakeEnumStringW`) |
| `LuxDataTableValue_MakeInt` | `0x2ED0CC0` | build a type-tagged int leaf node on the stack |
| `LuxDataTableValue_MakeBool` | `0x2ED1630` | build a bool leaf (takes 0 / 1) |
| `LuxDataTableValue_MakeEnumStringW` | `0x2ED1100` | build a string-enum leaf from a wide literal (e.g. `L"BATTLE_RULE_BATTLETYPE_TRAINING"`) |
| `LuxBattleRule_BuildTrainingModeDataTablePath` | `0x5D6F40` | builds the full training-mode rule tree in one shot; mod entry point for "boot straight into Training" |

A C++ plugin can reach any leaf by replaying `Ctor → AppendString*/AppendInt → Resolve`
against `BattleManager+0x50`, then `Commit` a freshly-built value node with
`AssignValue`. Writes to enum-typed slots need a wide-string enum literal built
via `MakeEnumStringW` — the parser matches on the literal text, not on a numeric
enum value.

### Boot-straight-to-Training recipe

`LuxBattleRule_BuildTrainingModeDataTablePath @ 0x5D6F40` assembles the
complete Training-mode rule tree in one call. The hard-coded leaves it writes
(all as enum-strings except the two numerics):

| Path | Value |
|---|---|
| `CommonParam.BattleTime` | int (caller-supplied; seconds) |
| `CommonParam.BattleType.BattleType` | `"BATTLE_RULE_BATTLETYPE_TRAINING"` |
| `CommonParam.IntroType` | `"BATTLE_RULE_INTROTYPE_BATTLECALL"` |
| `CommonParam.CharacterIntroType` | `"BATTLE_RULE_CHARACTER_INTROTYPE_NOTHING"` |
| `CommonParam.OutroType` | `"BATTLE_RULE_OUTROTYPE_NOTHING"` |
| `BattleRule.Endless` | `1` (bool) |
| `BattleRule.Rounds` | `0` (int, means "unlimited when Endless=1") |
| `PlayerParam.PlayerRight[0].CPUType` | `"CPU_TYPE_STAND"` |

Invoking this directly (or its caller `ULuxTrainingBattleSetupSceneScript`)
after the Title scene is the cleanest way to skip MainMenu and land in a
configured training match. Only `BattleTime` is parameterised — the rest are
baked in, so if you need different rules you have to override the leaves after
the builder returns.

## VM-level pause flag and time-dilation overrides

`ULuxBattleFunctionLibrary::SetBattlePause` (see [at-a-glance](#pause-inspection-bp-api-uluxbattlefunctionlibrary))
is the clean way to pause. For finer-grained speed control, replace the engine's reads of
the global delta-time and per-VM dilation field with a single user-controlled `speedval`
slot at six sites:

| Site | Function | Patch |
|------|----------|-------|
| 1 | `KHit_SolvePendulumConstraint` | `movss xmm14, [global]` → `[speedval]` |
| 3 | `LuxMoveVM_GetTimeDilationScalar` | `movss xmm0, [global]` → `[speedval]` |
| 4 | `LuxMoveVM_AdvanceLinkedMotionObject` | `movss xmm0, [pVM+0x2080]` → `[speedval]` |
| 5 | `LuxMoveVM_ExecuteOpStream` | `movss [pVM+0x2080], xmm0` repurposed as a load (engine doesn't read downstream) |
| 6 | `LuxMoveVM_AdvanceLaneFrameStep` | single-byte ModRM patch `cvttss2si ecx, xmm4` → `xmm3` to avoid 0-frame rounding at `speedval ≈ 0.001` |
| 7 | `LuxMoveVM_PostATKDelayGate` (entry hook) | early-return 0 when `speedval == 0` so post-ATK recovery countdown freezes |
| 9 | `LuxBattle_PerFrameTick` (entry hook) | bare-RET when `speedval == 0` — blanket battle-tick freeze that catches the round timer, replay cursor, input ring age, and all per-tick counters that aren't dt-scaled |

Per-VM time dilation is stored at `vmCtx + 0x2080`, and the post-ATK delay countdown is at
`vmCtx + 0xCF0` (`nPostATKRemainingDelayFrames`). `chara + 0x16E6` is the engine's own
"VM paused" flag — any path that halts a chara propagates through this byte.

## `ELuxBattleRuleType`

`BattleRule` rows are keyed by this enum:

| Value | Name |
|:-:|---|
| 0 | `Normal` |
| 1 | `Training` |
| 2 | `Story` |

> source: reflection strings at `0x14337E540`–`0x14337E6F0`.
