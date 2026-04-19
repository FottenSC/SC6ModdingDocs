# Game Structures

Reversed class layouts and offsets. Entries are community-verified — cite the Ghidra address you
reversed it from.

## Template for a new entry

```
### <ClassOrStruct name>

- **Path**: `/Script/<Module>.<Class>`
- **Size**: 0x???
- **Discovered via**: <UE4SS dumper / hook / xref / …>
- **Notes**: …

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| 0x00   | FName | Id | |
```

Use that template verbatim so the search index picks up fields consistently.

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
| +0x388 | `ALuxBattleChara` (embedded) | SubChara | host of `MoveComponent` used by `PlayMoveDirect` |
| +0x390 | `ALuxBattleChara**` | PlayerCharas | array of player chara ptrs |
| +0x398 | `int32` | NumPlayerCharas | |
| +0x3A0 | `uint8` | PendingMoveCommandType | 1 = PlayMove, 2 = Stop |
| +0x3A8 | `int32` | PendingMoveCommandParam | player index |
| +0x3B0 | `FLuxMoveCommandData` | PendingMoveCommandData | pending move-dispatch payload; `StopMove` zeroes a 0x18 local then copies it in, so the visible footprint is ≥ 0x18 (exact size unconfirmed) |
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

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x388 | `ULuxBattleMoveProvider*` | MoveProvider | holds the capsule container (hit + hurt geometry). `GetTracePosition_Impl` dereferences this then walks `+0x30 → +0x30 / +0x38` to iterate the `FLuxCapsule*` array. |
| +0x3A8 | `ULuxTraceComponent*` | TraceComponent | active-trace list (see below) |
| +0x3B0 | `TArray<FActiveAttackSlot>` data ptr | slot hash data | stride 0x44; key byte at +0x00, hash chain at +0x3C |
| +0x3B8 | `int32` | slot count | |
| +0x3F0 | `int32*` | hash bucket base | open-addressing hash over `+0x3B0` |
| +0x3F8 | `int32` | bucket count | mask = count − 1 |
| +0x400 | `int32` | current attack tag cache | read by `Active_Impl` validation |
| +0x458 | `ALuxTraceManager*` | TraceManager | **visual-only** — drives the weapon-trail / FX. Not part of hit resolution. |

> source: Ghidra reversing of `ALuxBattleChara_Active_Impl @ 0x1408CD940`,
> `ALuxBattleChara_Inactive_Impl @ 0x1408D1420`, `ALuxBattleManager_Update_Impl @ 0x140437590`.

### `ALuxTraceManager`

- **Path**: `/Script/LuxorGame.LuxTraceManager`
- **Size**: 0x408
- **Role**: drives the **visual** weapon trail / particle FX for one chara. Despite the name, this
  actor has nothing to do with hit resolution — hitboxes are `FLuxCapsule` entries on the
  `MoveProvider`. Everything on this class is visual state: two particle components, the
  trail-rendering `ULuxTraceComponent`, and a `KindIndex` picking the visual style.

| Offset | Type | Name |
|-------:|------|------|
| +0x388 | `UObject*` | OwnerMoveProvider (back-ref) |
| +0x398 | `UParticleSystemComponent*` | EffectSlotA |
| +0x3A0 | `UParticleSystemComponent*` | EffectSlotB |
| +0x3A8 | `ULuxTraceComponent*` | TraceComponent |
| +0x3B0 | … | active-trace hash |
| +0x400 | `int32` | KindIndex (`ELuxTraceKindId`) |

> source: `Z_Construct_UClass_ALuxTraceManager @ 0x140C096B0`,
> `ALuxTraceManager_ActivateTrace_Impl @ 0x1408D5D10`.

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
- **Storage**: the MoveProvider owns a *container* struct at `MoveProvider +0x30`; that container
  holds an array-of-pointer — `FLuxCapsule**` at `container +0x30`, count `int32` at `container +0x38`.
  So the iteration chain is `chara +0x388 → +0x30 (container) → +0x30 (FLuxCapsule**) / +0x38 (count)`.
- The first 48 bytes (`+0x00 .. +0x2F`) are an internal header — `GetTracePosition_Impl` never
  touches them. The documented fields all live in the tail of the struct.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x30 | `uint8` | CapsuleType | matched against `Active()` tag 1..9 |
| +0x31 | `uint8` | BoneId_A | 8-bit internal index (remapped via `LuxSkeletalBoneIndex_Remap`) |
| +0x34 | `float[3]` | LocalOffset_A | bone-local; scaled by `DAT_143E8A418` (≈100 — cm→UE units) |
| +0x40 | `uint8` | BoneId_B | second endpoint's bone index |
| +0x44 | `float[3]` | LocalOffset_B | second endpoint's bone-local offset |

There is **no `VisualPartsAsset` field on `FLuxCapsule`** — an earlier pass guessed a
`ULuxTracePartsDataAsset*` at `+0x50`, but that offset is past the end of the 80-byte struct and
`GetTracePosition_Impl` never reads it. Visual-parts data-assets are referenced elsewhere in the
trace pipeline (kind data-asset on `ULuxTraceComponent`, stored in the per-trace record), not
embedded in a capsule.

> source: `ALuxBattleChara_GetTracePosition_Impl @ 0x1408D0BB0`, `FLuxCapsule` type in the
> Ghidra data-type manager (80 bytes, header + 32-byte endpoint pair).

See [Trace / Hitbox System](trace-system.md) for how these fields feed the per-tick hit resolver
and the world-space transform math.

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
