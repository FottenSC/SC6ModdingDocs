# Battle Manager & DataTable Config Tree

`ALuxBattleManager` is the authoritative per-match actor. It owns the player chara
pointers, the per-frame axis/input buffer, the move-command pipeline, and an
in-memory **Lux DataTable** config tree that stores round rules, timer, and
per-player settings as a hierarchical string/int key path.

!!! note "Scope"
    Everything in this page is confirmed from the shipping Steam build via
    Ghidra. Addresses are absolute (image base `0x140000000`).

## `ALuxBattleManager` layout

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x050 | `FLuxDataTable` | ConfigTable | see *DataTable path tree* below |
| +0x098 | `UObject*` | GameState | isa-checked against `ALuxBattleManager` every branch in `Update` |
| +0x388 | `ALuxBattleChara` (embedded) | SubChara | arg source for `ALuxBattleChara::GetMoveComponent` |
| +0x390 | `ALuxBattleChara**` | PlayerCharas | array of player chara pointers |
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
hierarchical key-value tree addressed by string/int path segments. All
`ChangeBattle*` UFunctions are thin shims that build a path, resolve it, write
a leaf value, and commit.

```cpp
// Typical pattern seen in every ChangeBattle* impl
FLuxDataTablePath p;
LuxDataTablePath_Ctor(&p, &this->ConfigTable);
LuxDataTablePath_AppendString(&p, &out, "PlayerRight");   // or "PlayerLeft"
LuxDataTablePath_AppendInt   (&p, &out, playerIndex);
LuxDataTablePath_AppendString(&p, &out, "PlayerParam");
LuxDataTablePath_AppendString(&p, &out, "Gauge");
LuxDataTable_AddFloatRow     (&p, &out, "LifeInit", 240.f);
LuxDataTable_Resolve         (&p, &resolved);
LuxDataTable_Commit          (&this->ConfigTable, &resolved);
```

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
| `LuxDataTablePath_Ctor` | `0x2ED0AA0` | anchor a path to a table ref |
| `LuxDataTablePath_AppendString` | `0x2EDA150` | path `/ "key"` |
| `LuxDataTablePath_AppendInt` | `0x2EDA300` | path `/ int` |
| `LuxDataTablePath_AppendFloat` | `0x2ED0E30` | path `/ float` |
| `LuxDataTablePath_Dtor` | `0x2ED6A80` | refcount-release builder nodes |
| `LuxDataTable_Resolve` | `0x2F2EE30` | materialize path into a value handle |
| `LuxDataTable_Commit` | `0x2ED9000` | write-back into the table |
| `LuxDataTable_AddFloatRow` | `0x2F4E370` | append-or-replace a `{key: float}` |
| `LuxDataTable_GetRowCount` | `0x4DC9B0` | count child rows at path |

Xref counts are huge (`LuxDataTablePath_Dtor` has 27 303 callers) — this is the
game's primary in-memory config surface. A C++ plugin can reach any leaf by
replaying the ctor/append/resolve sequence against `BattleManager+0x50`.

## `ELuxBattleRuleType`

`BattleRule` rows are keyed by this enum:

| Value | Name |
|:-:|---|
| 0 | `Normal` |
| 1 | `Training` |
| 2 | `Story` |

> source: reflection strings at `0x14337E540`–`0x14337E6F0`.
