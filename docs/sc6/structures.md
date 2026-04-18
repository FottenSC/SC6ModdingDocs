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
| +0x098 | `UObject*` | GameState-like | isa-checked against `ALuxBattleManager` in tick path |
| +0x388 | `ULuxBattleMoveProvider*` | MoveProvider | holds hit capsules; the source of truth for hitbox geometry |
| +0x3A8 | `ULuxTraceComponent*` | TraceComponent | active-trace list (see below) |
| +0x3B0 | `TArray<FActiveAttackSlot>` data ptr | slot hash data | stride 0x44; key byte at +0x00, hash chain at +0x3C |
| +0x3B8 | `int32` | slot count | |
| +0x3F0 | `int32*` | hash bucket base | open-addressing hash over `+0x3B0` |
| +0x3F8 | `int32` | bucket count | mask = count - 1 |
| +0x400 | `int32` | current attack tag cache | read by `Active_Impl` validation |
| +0x458 | `ALuxTraceManager*` | TraceManager | thin wrapper actor |

> source: Ghidra reversing of `ALuxBattleChara_Active_Impl @ 0x1408CD940`,
> `ALuxBattleChara_Inactive_Impl @ 0x1408D1420`, `ALuxBattleManager_Update_Impl @ 0x140437590`.

### `ALuxTraceManager`

- **Path**: `/Script/LuxorGame.LuxTraceManager`
- **Size**: 0x408

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

- **Size**: 80 (0x50)
- **Storage**: `TArray<FLuxCapsule*>` (array-of-pointer) at `MoveProvider +0x30 -> +0x30 / +0x38`

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x30 | `uint8` | CapsuleType | matched against `Active()` tag 1..9 |
| +0x31 | `uint8` | BoneId_A | 8-bit internal index (remapped via `LuxSkeletalBoneIndex_Remap`) |
| +0x34 | `float[3]` | LocalOffset_A | bone-local, pre cm→UE scaling |
| +0x40 | `uint8` | BoneId_B | |
| +0x44 | `float[3]` | LocalOffset_B | |
| +0x50 | `ULuxTracePartsDataAsset*` | VisualPartsAsset | visual only; not collision |

> source: `ALuxBattleChara_GetTracePosition_Impl @ 0x1408D0BB0`.

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
