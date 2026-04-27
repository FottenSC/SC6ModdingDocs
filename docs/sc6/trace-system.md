# Trace System (weapon-trail VFX)

The visual side of attacks. Drives the weapon-trail / sword-swoosh / particle effects you
see whenever a weapon attack swings — sword arcs, axe sweeps, whip ribbons. **Not consulted
by hit resolution.** The class names and the `FLuxCapsule` data type confused earlier
documentation passes into thinking this was the hitbox system; it isn't.

For the actual hit detection — strikes, kicks, hurtboxes, pushboxes, grabs — see
[Hitbox System (KHit linked lists)](hitbox-system.md). The two systems share an
`AttackTag` coordination key (`FLuxCapsule.CapsuleType` here, `KHitBase.KindTag` over
there) so a move script can open the trail and the hit window in lockstep, but they are
otherwise independent.

## At a glance

| What | Address / offset | Role |
|------|------------------|------|
| Visual driver actor | `chara+0x458` | `ALuxTraceManager*` — owns particle slots + trail renderer. |
| Trail renderer component | `chara+0x3A8` | `ULuxTraceComponent*` — lazy; created by `ActivateTrace`. |
| Slot-tag hash | `chara+0x3B0/+0x3F0/+0x3F8` | `FActiveAttackSlot[]` keyed by `AttackTag` 1..9. |
| Activate UFunction | `ALuxBattleChara::Active_Impl @ 0x1408CD940` | Opens slot tag. |
| Deactivate UFunction | `ALuxBattleChara::Inactive_Impl @ 0x1408D1420` | Closes slot, fades trail. |
| Capsule struct | `FLuxCapsule` (0x50 bytes) | Endpoint pair authored per-move. |
| Native query (stale on this build) | `ALuxTraceManager::GetTracePosition_Impl @ 0x1408D0BB0` | Returns `false` for every real chara — `chara+0x388` is now `CharaMesh0`. |

> Source: Ghidra reverse-engineering of the SC6 Steam build.

---

## Ownership chain (verified runtime layout)

```text
ALuxBattleChara
    ├ +0x168  USceneComponent*          CustomRoot0
    │
    ├ +0x388  USkeletalMeshComponent*   CharaMesh0     (NOT MoveProvider)
    ├ +0x390  USkeletalMeshComponent*   WeaponMesh0    (NOT Opponent)
    │
    ├ +0x3A8  ULuxTraceComponent*       (lazy; created by ActivateTrace)
    │
    ├ +0x3B0  FActiveAttackSlot[]       slot-tag hash, AttackTag 1..9
    │        +0x3F0/+0x3F8 hash bucket base / count
    │
    ├ +0x448  UBoxComponent*            TestCollision
    │
    ├ +0x458  ALuxTraceManager*         (visual-only weapon-trail driver)
    │           ├ +0x388  ULuxTraceDataAsset*
    │           ├ +0x398  UParticleSystemComponent*    EffectSlotA
    │           ├ +0x3A0  UParticleSystemComponent*    EffectSlotB
    │           ├ +0x3A8  ULuxTraceComponent*          (trail renderer)
    │           └ +0x400  int32                        KindIndex (ELuxTraceKindId)
    │
    ├ +0x1438 UObject*                  cached MoveComponent (lazy; empty on this build)
    │
    └ +0x973E8 ALuxBattleChara*         Opponent (read by LuxMoveVM_CheckRangeOrDistance)
```

Sources: `ALuxCharaActorBase_Constructor @ 0x140440FB0`, `ALuxBattleChara_Constructor @
0x1403AB8D0`, `ALuxTraceManager_ActivateTrace_Impl @ 0x1408D5D10`,
`LuxMoveVM_CheckRangeOrDistance @ 0x140365140`.

## Why `chara+0x388` no longer reaches a capsule container

`ULuxBattleMoveProvider` is **absent** from the shipping binary — no
`Z_Construct_UClass_ULuxBattleMoveProvider`, no string match for the class name. Functions
that still encode the old `chara+0x388 → +0x30` walk are stale code paths:

- `ALuxTraceManager::GetTracePosition_Impl @ 0x1408D0BB0` — returns `false` for every real
  chara because `chara+0x388` is now `CharaMesh0`.
- `LuxMoveProviderRef_Get @ 0x14045FC70`, `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0`
  — same staleness; ~20 adjacent functions are effectively dead code on this build.

## Classes

| Class | Purpose | Size |
|-------|---------|-----:|
| `ALuxBattleChara` | Fighter actor. Declares `Active` / `Inactive` / `GetTracePosition` UFunctions. | `0x568` |
| `FLuxCapsule` | Capsule endpoint pair (visual). Layout known; container location uncertain on this build. | `0x50` |
| `ALuxTraceManager` | Visual-only weapon-trail driver. | `0x408` |
| `ULuxTraceComponent` | Visual ticking component, holds `ActiveTraces[]`. | `0x4B0` |
| `ALuxTraceMeshActor` | Visual child actor, renders the trail. | — |
| `ULuxTracePartsDataAsset` | Visual curves / material params. | — |

## UFunctions on `ALuxBattleChara`

Three reflected UFunctions:

| UFunction | `_Impl` | exec trampoline | Behaviour |
|-----------|---------|-----------------|-----------|
| `Active(FTraceActiveParam)` | `0x1408CD940` | `0x140C3DA20` | Opens an attack-slot tag (1..9) into `chara+0x3B0`. |
| `Inactive(FTraceInactiveParam)` | `0x1408D1420` | `0x140C3FD00` | Closes the slot; starts trail fade. |
| `GetTracePosition(byte, int32, out FVector, out FVector)` | `0x1408D0BB0` | `0x140C3F9B0` | **Stale** on this build — always returns `false`. |

`Active` reads only the first byte of its 0x30-byte `FTraceActiveParam` for hit logic — that's
the `AttackTag`. The remaining 47 bytes configure the visual trail.

```cpp
struct FTraceActiveParam {  // sizeof == 0x30 (48 bytes)
    uint8    AttackTag;      // +0x00 — the only field Active_Impl reads for hit resolution
    uint32   Flags;          // +0x04 — visual
    // ... cosmetic fields through +0x2C (trail tint FLinearColor at +0x1C)
};
```

## `FLuxCapsule` (0x50 bytes)

```cpp
struct FLuxCapsule {
    uint8  header[48];       // +0x00..+0x2F  unread by GetTracePosition
    uint8  CapsuleType;      // +0x30  matched against Active() tag
    uint8  BoneId_A;         // +0x31  remapped via LuxSkeletalBoneIndex_Remap
    // +0x32..+0x33 pad
    float  LocalOffset_A[3]; // +0x34
    uint8  BoneId_B;         // +0x40
    // +0x41..+0x43 pad
    float  LocalOffset_B[3]; // +0x44
    // sizeof == 0x50
};
```

There is no visual-parts-asset pointer inside the capsule. Visual data lives on the trace
component's kind data-asset.

The world-space chain (used internally by the visual updater and reused by the hitbox-side
`KHitArea` subclass — see [Hitbox System: Reading hit volumes from a mod](hitbox-system.md#reading-hit-volumes-from-a-mod)):

```text
bone  = LuxSkeletalBoneIndex_Remap(BoneId)
M     = ALuxBattleChara_GetBoneTransformForPose(chara, pose, bone)
off   = LocalOffset * g_LuxCmToUEScale * M.scale
World = M.rot * off + M.pos
```

`g_LuxCmToUEScale @ 0x143E8A418` = `10.0f` (bit pattern `0x41200000`). Despite the symbol
name, the factor is 10 — `LocalOffset` is stored in millimetres or a similar
decimetre-scaled internal unit; multiplying by 10 lands the value in UE4 cm.

## `FLuxCapsuleContainer` (0x40 bytes — legacy view)

| Offset | Type | Name |
|-------:|------|------|
| +0x00..+0x2F | — | internal header |
| +0x30 | `FLuxCapsule**` | `Data` |
| +0x38 | `int32` | `Num` |
| +0x3C | `int32` | `Max` |

## Where the live `FLuxCapsule` array is on this build

Unconfirmed. The `FLuxCapsule` struct layout is correct, but the array of pointers is no
longer reachable through `chara+0x388`. Best candidate is `ALuxBattleMoveCommandPlayer*` at
`BattleManager+0x4C0` — registered name `"BattleMoveCommandPlayer"` via
`Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`, exposes 5 UFunctions
(`GetMovePlayParam`, `IsPlaying`, `PlayMove`, `PlayMoveDirect`, `StopMove`) plus 5 reflected
UPROPERTYs (`PlayData`, `Request`, `RequestInfo`, `PlayState`, `PlayStateInfo`) at
`+0x390..+0x3D0`.

Walk its fields for an 8-byte aligned pointer to a 0x40-byte container whose `+0x30..+0x3C`
matches `FLuxCapsuleContainer` shape.

## `ELuxTraceKindId` (visual trail kinds)

`ULuxTraceComponent +0x498 KindIndexCopy` (i32). The enum has >30 entries — strings live at
`0x14335A7B0+`.

| Symbol prefix | Meaning |
|---------------|---------|
| `TRC_KIND_NONE` | no trail |
| `TRC_KIND_AUTO` | engine-driven default |
| `TRC_KIND_NORMAL` / `TRC_KIND_NORMAL_S` | default swing trail (S = short) |
| `TRC_KIND_TUBE` / `TRC_KIND_LINE` | geometry variants |
| `TRC_KIND_THUNDER` / `TRC_KIND_WIND` / `TRC_KIND_FLAME` / `TRC_KIND_LIGHT` | elemental |
| `TRC_KIND_SPARK` / `TRC_KIND_FIRE_S` | short-lived VFX |
| `TRC_KIND_P*` | particle-only trails (`PFLAME`, `PSMOKE`, `PBURN`, `PLIGHT`, `PDUST`, `PAURA`, `PTHUNDER`, `PWIND`); `_L` = large |
| `TRC_KIND_LIGHTSABER` | unconfirmed character variant |
| `TRC_KIND_KICK` | kick-attack trail |
| `TRC_KIND_ULTIMATE_EDGE` / `TRC_KIND_ULTIMATE_CALIBUR` | super / reversal trails |

## Empirical `CapsuleType` / `AttackTag` ranges

The plate comment on `Z_Construct_UFunction_..._GetTracePosition` documents the valid range
as 1..9 based on one caller's `SlotIdx + 1` usage. A training-mode scan iterating
`InTracePartsId` from 1 to 64 sees many more types populated:

- **Always-on (idle stance)**: 1, 2, 3, 15, 18, 21, 24, 27. Shared hilt points across 1/2/3
  suggest body segments — likely **hurtboxes**.
- **Active-frame only**: the actual attack capsules. Numeric values vary per character /
  per move.

A mod that wants to visualise everything should scan at least 1..31, possibly 1..63.

---

## Calling the trace UFunctions from Lua

`ALuxBattleChara::Active` / `Inactive` / `GetTracePosition` cannot be called from UE4SS Lua
reflection in the current public UE4SS builds. The class was registered with the short
`UE4_RegisterClass` variant (no `Ex`), so its UFunction parameter UProperty metadata is
missing. UE4SS surfaces this as the misleading *"Tried calling a member function but the
UObject instance is nullptr"* error on any call that takes arguments. Inherited AActor
UFunctions like `K2_GetActorLocation` still work.

See [UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md) for the diagnosis.

## `ReceiveGetWeaponTip` — promising-looking dead end

SC6 registers a `BlueprintImplementableEvent` named `ReceiveGetWeaponTip` on
`ALuxBattleWeaponEventHandler`. It fires every frame during attacks (including ranged
moves like Cervantes's gun) — looks like a universal weapon-endpoint query.

It isn't useful: **no SC6 character's Blueprint subclass overrides the event.** Every
`ProcessEvent` post-hook arrives with `outRoot == outTip == (0,0,0)` and `bReturnValue == 0`.
The native caller (`ALuxBattleManager::GetTracePositionForPlayer @ 0x1403F4960`) ignores
the result and falls through to `GetTracePosition_Impl` unconditionally. The event is a BP
extension point that no one shipped an implementation for.

Layout: see
[`ALuxBattleWeaponEventHandler` in Structures](structures.md#aluxbattleweaponeventhandler).

## Debug-draw flags (stripped in shipping)

`ULuxTraceDataAsset` declares three UPROPERTY bools, stored as a bitfield at `+0x50`:

- `bDebugDrawTraceFrame` (bit 0)
- `bDebugDrawTraceKeyFrame` (bit 1)
- `bDebugDrawTraceVelocity` (bit 2)

Registered at `0x140C0CF60`. **Zero consumers** in the shipping binary — the debug-draw
paths were compiled out via `UE_BUILD_SHIPPING`. Setting these flags does nothing.

`UKismetSystemLibrary::DrawDebugLine` is also non-functional: the UFunction reflection
entry survives (`Z_Construct_UFunction_UKismetSystemLibrary_DrawDebugLine @ 0x142558090`)
but its native exec handler is unbound. Calling it via reflection from UE4SS is a silent
no-op.

The one drawing path that **is** live is `ULineBatchComponent` on the `UWorld` — see
[Drawing 3D Debug Lines](line-batching.md). For the broader inventory of dev-left-behind
hooks, see [Dev / Debug Hooks](dev-debug-hooks.md).

---

## What's still unfound

- **Live `FLuxCapsule` container on this build.** Layout known (0x50); container address
  uncertain since `chara+0x388` is now `CharaMesh0`. Best candidate: walk
  `ALuxBattleMoveCommandPlayer*` at `BattleManager+0x4C0`.
- **`FLuxCapsule` radius.** The 80-byte struct holds two endpoints but no radius field;
  likely lives on `TracePartsDataAsset` or a sibling struct the live container points at.
- **Cross-reference with the hitbox system.** The visual `FLuxCapsule` system here and the
  KHit `KHitArea` subclass on the [Hitbox System](hitbox-system.md) page both encode
  bone-pair endpoints. Whether any move authoring tool emits both representations from a
  single source isn't confirmed.

---

## Key binary addresses (RVA, image base `0x140000000`)

### Trace UFunctions and visual driver

| Symbol | RVA | Description |
|--------|-----|-------------|
| `ALuxBattleChara_Active_Impl` | `0x8CD940` | Opens attack slot. |
| `ALuxBattleChara_Inactive_Impl` | `0x8D1420` | Closes attack slot. |
| `ALuxTraceManager_GetTracePosition_Impl` | `0x8D0BB0` | **Stale** — returns `false` for every real chara. |
| `execGetTracePosition_ALuxBattleChara` | `0xC3F9B0` | VM trampoline. |
| `ALuxTraceManager_ActivateTrace_Impl` | `0x8D5D10` | Lazy-creates `TraceComponent`, spawns trail. |
| `ULuxTraceComponent_BeginTrace` | `0x8D5FF0` | Populates `ActiveTraces[]` from kind data asset. |
| `ULuxTraceComponent_StartTrace` | `0x8D8C40` | `SetActive(true)`. |
| `ALuxBattleManager_GetTracePositionForPlayer` | `0x3F4960` | BM helper; inherits the same staleness as `GetTracePosition_Impl`. |

### Bone / matrix helpers (shared with the hitbox system)

| Symbol | RVA | Description |
|--------|-----|-------------|
| `ALuxBattleChara_GetBoneTransformForPose` | `0x462760` | `(chara, pose, boneIdx) → FMatrix`. Returns 4×4 affine, NOT FTransform. |
| `LuxSkeletalBoneIndex_Remap` | `0x898140` | 8-bit internal idx → UE skeleton bone idx. Returns `0xFFFFFFFF` on failure. |
| `g_LuxCmToUEScale` | `0x143E8A418` | Scale constant; value is `10.0f`. |
