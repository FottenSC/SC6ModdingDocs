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
| +0x388 | `UClass*` | BattleCharaClass | `TSubclassOf<ALuxBattleChara>` per `Z_Construct_UClass_ALuxBattleManager @ 0x140949450`. **Not** an embedded chara — an earlier pass of these docs called this "SubChara" but a 0x568-byte embedded chara starting here would collide with the Camera/EventListener slots at +0x3A8..+0x408 confirmed by the runtime-verified subsystem map in [battle-manager.md](battle-manager.md#camera--events). |
| +0x390 | `ALuxBattleChara**` | PlayerCharas.Data | `TArray<ALuxBattleChara*>` — iterate `PlayerCharas[0..NumPlayerCharas-1]` for all active fighters |
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

!!! warning "Layout verified at runtime on the Steam build (2026-04-19)"
    The field table below was corrected against the **actual running
    binary** using UE4SS class-name introspection on a live chara.
    Earlier versions of this page described `chara+0x388` as the
    `ULuxBattleMoveProvider` pointer — that is **wrong on the shipping
    Steam build**. `+0x388` and `+0x390` are actually the `CharaMesh0`
    and `WeaponMesh0` `USkeletalMeshComponent*`s, stored by
    `ALuxCharaActorBase_Constructor @ 0x140440FB0` as
    `param_1[0x71]` / `param_1[0x72]`. There is no per-chara
    `ULuxBattleMoveProvider` on this build.

    The real opponent pointer is **`chara+0x973E8`** (not `+0x390`) —
    identified by `LuxMoveVM_CheckRangeOrDistance @ 0x140365140`
    dereferencing that field to read the opponent's world-space
    position.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x6C   | `int16` | MoveClassA | SC6 move category (5..12) — `HorizontalAttack`, `VerticalAttack`, `Kick`, `Throw`, etc. |
| +0x6E   | `uint16` | MoveClassB | subclass |
| +0x70   | `int32` | MoveFlags | |
| +0x98   | `ALuxBattleManager*` | BattleManager | non-UPROPERTY back-ref; read by `SetupWeaponBones` and isa-checked against `ALuxBattleManager` throughout `LuxMoveVM` |
| +0xA0 | `float` | SelfPos.X | world-space position — read by `LuxMoveVM_CheckRangeOrDistance` |
| +0xA8 | `float` | SelfPos.Z | |
| +0x168  | `USceneComponent*` | CustomRoot0 | stored by `ALuxCharaActorBase_Constructor` `param_1[0x2D]` |
| +0x23C  | `uint8` | CharaKindByte | row index into `g_LuxCharaAttrTable_*` |
| +0x250  | `uint16` | MoveSubclassAlt | alternative move-category byte (checked `==100` / `0x69` by IF predicates) |
| +0x388  | `USkeletalMeshComponent*` | CharaMesh0 | **NOT MoveProvider.** Set by `ALuxCharaActorBase_Constructor` `param_1[0x71]`. |
| +0x390  | `USkeletalMeshComponent*` | WeaponMesh0 | **NOT Opponent.** Set by `ALuxCharaActorBase_Constructor` `param_1[0x72]`. |
| +0x398  | `float` | MaegamiL_Pos | Maegami-L (front-hair-L) position; ctor init `0` |
| +0x39C  | `float` | MaegamiR_Pos | Maegami-R position; ctor init `0` |
| +0x3A0  | `int32` | PlayerIndex | ctor init `-1`; UPROPERTY |
| +0x3A4  | `int32` | CharaID | ctor init `-1`; doubles as `SoulChargeMode` at runtime |
| +0x3A8  | `int32` | WeaponID | **NOT a TraceComponent pointer** (earlier docs claimed `ULuxTraceComponent*` here — that was wrong). Ctor init `-1`; doubles as `WeaponTypeCode` at runtime. The ctor writes `*(uint32*)(param_1+0x3A8) = 0xFFFFFFFF` so this is clearly a 4-byte int, not an 8-byte pointer. |
| +0x3B0  | `TArray<USkeletalMeshComponent*>` | CreationComponents | UPROPERTY Instanced; `.Data/.Num/.Max` at `+0x3B0/+0x3B8/+0x3BC`. Earlier docs described "active-attack slot hash" here with stride 0x44 — the constructor initialises this block as CreationComponents, so the slot-hash interpretation was wrong. |
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
| +0x1438 | `UObject*` | cached MoveComponent | lazy cache filled by `ALuxBattleChara_GetMoveProvider @ 0x1403F00B0`. Chain: `chara->GetWorld()->OwningGameInstance (world+0x140) → ISA-check ULuxGameInstance → *(ULuxGameInstance+0x140)`. On this build the final read returns the IEEE 754 value `0x3F800000` (float `1.0f`), not a pointer, so the cache stays at sentinel (`0xFFFFFFFF_FFFFFFFF`) indefinitely. The misnamed Ghidra symbol `ALuxBattleManager_GetMoveProviderPtr @ 0x140546600` actually operates on a `ULuxGameInstance*`, not `ALuxBattleManager*`. Note: the offset `+0x1438` is **past the `0x568` class size** — this means the lazy cache lives in a separately-allocated extension or the `0x568` is an understatement of the actual live size. Under active investigation. |
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
    Searches for `Z_Construct_UClass_ULuxBattleMoveProvider*` and any
    literal `"LuxBattleMoveProvider"` / `"LuxBattleMoveComponent"`
    string in the shipping binary return **zero hits**. Neither name
    survives as a UClass registration. The class was either renamed,
    dropped, or folded into another type between an earlier dev snapshot
    (which the older docs described) and the 2026-04-19 Steam build.

    **What's actually reachable — the four move-related slots on
    `ALuxBattleManager`** (no UE4 reflection metadata for any of these
    because `ALuxBattleManager` is registered short-form via
    `UE4_RegisterClassEx` with no UPROPERTY list — see
    `Z_Construct_UClass_ALuxBattleManager @ 0x140949450`):

    | Slot | Inferred class | Notes |
    |------|----------------|-------|
    | `BM+0x140` | `UObject*` (class unknown) | Read by the misnamed `ALuxBattleManager_GetMoveProviderPtr @ 0x140546600` — which, despite the name, takes a `ULuxGameInstance*`. Lazy-cached on every chara at `chara+0x1438` by `ALuxBattleChara_GetMoveProvider @ 0x1403F00B0`. |
    | `BM+0x1450` | `UObject*` (TSharedPtr Target) | Read by `LuxMoveProviderRef_Get @ 0x14045FC70` — which ISA-checks `world+0x98` against `ALuxBattleManager`, then fetches `(*BM+0x1450, *BM+0x1458)` as a TSharedPtr-style pair. The target's `vtable[0x10]` is `IsValid`, `vtable[0x100]` returns the default sub-provider, `vtable[0xE0]` returns an indexed sub-provider. Also referenced by `ALuxBattleChara` vtable slots 208 (`GetWeaponData`) and 210/211 (`GetBoneDataSharedPtr`) — role is ambiguous between a MoveProvider and a unified weapon/bone/move data asset. |
    | `BM+0x1458` | ref-count control block | Second half of the TSharedPtr pair at `BM+0x1450`. |
    | `BM+0x4C0` | `ALuxBattleMoveCommandPlayer*` | **The one slot whose class IS known** — registered name `"BattleMoveCommandPlayer"` via `Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`. This is the command-script VM actor that runs move bytecode; see [Move System](move-system.md). The per-move capsule data is believed to live inside this object, but the exact `FLuxCapsuleContainer` offset is still being located. |

    **Stale call paths to avoid** — these functions were written for an
    older layout where `chara+0x388` held a MoveProvider pointer. On
    this build `chara+0x388` is `CharaMesh0`, so these produce garbage
    or silently fail:

    - `ALuxTraceManager_GetTracePosition_Impl @ 0x1408D0BB0`
      (Ghidra-renamed; was `ALuxBattleChara_GetTracePosition_Impl`) —
      reads `this+0x388 → +0x30 → +0x30 / +0x38` expecting the
      `FLuxCapsuleContainer` chain; instead walks a `USkeletalMeshComponent`.
    - `LuxMoveProviderRef_Get @ 0x14045FC70` and
      `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0` — callers pass
      `chara+0x388` as the "context" pair and these functions invoke
      `(*(param_1))->vtable[0]` on it to "get world". On a SkeletalMeshComponent
      vtable[0] is the destructor, so the ISA-check at
      `world+0x98 -> ALuxBattleManager` falls through with garbage and
      the functions early-out. The many callers in `FUN_1403A66F0`
      through `FUN_1403AAA60` (~20 adjacent functions) are effectively
      dead code on this build.

    The live move pipeline routes through `ALuxBattleMoveCommandPlayer`
    and the raw `BM+0x1450` TSharedPtr, not through the chara's
    `+0x388` slot.

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
| +0x34 | `float[3]` | LocalOffset_A | bone-local; scaled by `g_LuxCmToUEScale @ 0x143E8A418` — the Ghidra label calls it a cm→UE conversion but the actual value is `10.0f` (bit pattern `0x41200000`), which implies the stored offset is in millimetres (or some other decimetre-like internal unit) rather than cm. Multiplying by 10 lands the value in UE4's native cm units. |
| +0x40 | `uint8` | BoneId_B | second endpoint's bone index |
| +0x44 | `float[3]` | LocalOffset_B | second endpoint's bone-local offset |

There is **no `VisualPartsAsset` field on `FLuxCapsule`** — an earlier pass guessed a
`ULuxTracePartsDataAsset*` at `+0x50`, but that offset is past the end of the 80-byte struct and
`GetTracePosition_Impl` never reads it. Visual-parts data-assets are referenced elsewhere in the
trace pipeline (kind data-asset on `ULuxTraceComponent`, stored in the per-trace record), not
embedded in a capsule.

> source: `ALuxTraceManager_GetTracePosition_Impl @ 0x1408D0BB0` (formerly misnamed
> `ALuxBattleChara_GetTracePosition_Impl` in older Ghidra databases — the function body
> receives a chara `this` but the UFunction is registered under `ALuxTraceManager`),
> `FLuxCapsule` type in the Ghidra data-type manager (80 bytes, header + 32-byte
> endpoint pair). Per its plate comment this function is **stale on the current
> Steam build** — it reads the legacy MoveProvider slot that no longer contains
> live capsule data.

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

---

## Stage / frame spatial acceleration (used by the `LuxMoveVM` IF predicates)

The two spatial `IF` predicates in `LuxMoveVM` (`CheckRangeOrDistance @ 0x140365140`,
`CheckAngleOrGeometry @ 0x1403652E0`) query two global, non-thread-safe spatial
structures shared across the battle subsystem. Both structures come in matched
A/B pairs and are selected via the byte flag `g_LuxBattle_FrameContextUseB @
0x14470DEDC` — when non-zero, the "B" variant is returned by the accessors
`LuxBattle_GetActiveFrameBoundsGrid @ 0x1403133E0` and
`LuxBattle_GetActiveFrameTransform @ 0x140313400`.

### Frame-bounds grid

- **Instances**:
  - `g_LuxBattle_FrameBoundsGridA` @ `0x144844DD0`
  - `g_LuxBattle_FrameBoundsGridB` @ `0x144845E80`
- **Discovered via**: `LuxBattle_GetActiveFrameBoundsGrid @ 0x1403133E0`,
  `LuxBattle_TraceSegmentThroughFrameBoundsGrid @ 0x1403149E0`,
  `LuxBattle_TestFrameBoundsCell @ 0x1403916E0`
- **Size**: at least 0x430 bytes (reads observed up to the `isValid` byte
  at +0x410; the grid header is ~0x30 bytes plus a `cells[]` tail).

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
- **Pairs with** the bounds grid of the same letter; every read of
  `GetActiveFrameBoundsGrid` in the VM predicate call path is immediately
  followed by a read of `GetActiveFrameTransform`, which suggests they describe
  two arena / camera frames that can be swapped atomically (the two sides of a
  stage-swap scenario, or two chara-local frames during a switch-cam move).

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

Offsets of interest to SC6 modding. The full UE4.17 `UWorld` has many more fields —
only the ones mods commonly need are listed here. Offsets below are confirmed
against the property-builder sequence inside `Z_Construct_UClass_UWorld`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x030 | `ULevel*` | `PersistentLevel` | |
| +0x038 | `UNetDriver*` | `NetDriver` | |
| +0x040 | `ULineBatchComponent*` | `LineBatcher` | depth-tested debug lines, per-frame |
| +0x048 | `ULineBatchComponent*` | `PersistentLineBatcher` | depth-tested, persists until `FLUSHPERSISTENTDEBUGLINES` |
| +0x050 | `ULineBatchComponent*` | `ForegroundLineBatcher` | **no depth test, always on top** — recommended for debug overlays |
| +0x088 | `TArray<ULevelStreaming*>` | `StreamingLevels` | |
| +0x098 | `FString` | `StreamingLevelsPrefix` | 24-byte FString — **not a UObject pointer.** Earlier docs claimed this was `AuthorityGameMode`; that's wrong. `AuthorityGameMode` is at `+0xF0`. |
| +0x0E8 | `UNavigationSystem*` | `NavigationSystem` | |
| +0x0F0 | `AGameModeBase*` | `AuthorityGameMode` | the real slot. ISA-checked against `ALuxBattleManager` by `GetPlayerIndex`, `GetTracePositionForPlayer`, etc. |
| +0x0F8 | `AGameStateBase*` | `GameState` | |
| +0x100 | `UAISystemBase*` | `AISystem` | |
| +0x138 | `ULevel*` | `CurrentLevel` | |
| +0x140 | `UGameInstance*` | `OwningGameInstance` | **On SC6 this points to `ULuxGameInstance`** (registered name `"LuxGameInstance"`, size 0x220, `Z_Construct_UClass_ULuxGameInstance @ 0x140A55E60`; short-form static-class getter at `0x140A51870`). `ALuxBattleChara::GetMoveProvider @ 0x1403F00B0` reads this slot, ISA-checks it against `ULuxGameInstance`, and then reads **the GameInstance's own `+0x140`** to get the move-provider pointer. |

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
ranged attacks like Cervantes's gun where the `FLuxCapsule` trace system is silent. On
paper, hooking it would be an attractive "universal hitbox endpoint query".

**In practice, no SC6 character's Blueprint subclass overrides the event.** Every post-hook
sample observed arrives with `outRoot == outTip == (0,0,0)` and `bReturnValue == 0`. The
native caller (`ALuxBattleManager::GetTracePositionForPlayer`) calls the event first,
ignores the result, and falls through to `ALuxBattleChara::GetTracePosition_Impl`
unconditionally — so any "hitbox" value a mod might have read from the hook is garbage
by construction.

Documented here so the next person who sees the class in a `ProcessEvent` spy log can
skip the RE chase. The real hit-detection geometry is [`FLuxCapsule`](structures.md#fluxcapsule);
the real query path is [`GetTracePosition_Impl`](trace-system.md#ufunctions-exposed-on-aluxbattlechara).

**UFunction registration**: `Z_Construct_UFunction_ALuxBattleWeaponEventHandler_ReceiveGetWeaponTip
@ 0x1409CFCE0`. Param block is 0x24 bytes — layout:

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
