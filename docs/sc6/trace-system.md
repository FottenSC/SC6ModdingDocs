# Trace System (weapon-trail VFX)

The visual side of attacks. This system drives the weapon-trail / sword-swoosh / particle
effects you see whenever a weapon swings — sword arcs, axe sweeps, whip ribbons. **It is
not consulted by hit resolution.** The class names and the `FLuxCapsule` data type led
earlier documentation passes to mistake this for the hitbox system; it is not.

For the actual hit detection — strikes, kicks, hurtboxes, pushboxes, grabs — see
[Hitbox System (KHit linked lists)](hitbox-system.md). The two systems share one
coordination key, `AttackTag` (`FLuxCapsule.CapsuleType` here, `KHitBase.KindTag` over
there), so a move script can open the trail and the hit window in lockstep. They are
otherwise independent.

## At a glance

| What | Address / offset | Role |
|------|------------------|------|
| Visual driver actor | `chara+0x458` | `ALuxTraceManager*` — owns particle slots + trail renderer. |
| Trail renderer component | `chara+0x3A8` | `ULuxTraceComponent*` — lazy; created by `ActivateTrace`. |
| Slot-tag hash | `chara+0x3B0/+0x3F0/+0x3F8` | `FActiveAttackSlot[]` keyed by `AttackTag` 1..9. |
| Activate UFunction | `ALuxTraceManager::Active_Impl @ 0x1408CD940` | Opens slot tag. Registered as a UFunction on `ALuxTraceManager` (not `ALuxBattleChara` — earlier docs got the class wrong). |
| Deactivate UFunction | `ALuxTraceManager::Inactive_Impl @ 0x1408D1420` | Closes slot, fades trail. |
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

`ULuxBattleMoveProvider` is **absent** from the shipping binary — there is no
`Z_Construct_UClass_ULuxBattleMoveProvider` and no string match for the class name. Any
function that still encodes the old `chara+0x388 → +0x30` walk is a stale code path:

- `ALuxTraceManager::GetTracePosition_Impl @ 0x1408D0BB0` — returns `false` for every real
  chara because `chara+0x388` is now `CharaMesh0`.
- `LuxMoveProviderRef_Get @ 0x14045FC70`, `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0`
  — same staleness; ~20 adjacent functions are effectively dead code on this build.

## Classes

| Class | Purpose | Size |
|-------|---------|-----:|
| `ALuxBattleChara` | Fighter actor; owns the `ALuxTraceManager*` at `+0x458`. | `0x568` |
| `ALuxTraceManager` | Visual-only weapon-trail driver. **Hosts the `Active` / `Inactive` / `GetTracePosition` UFunctions** (registered via `Z_Construct_UClass_ALuxTraceManager_Properties @ 0x140C0BA90`). Earlier docs attributed these to `ALuxBattleChara`, which was wrong: both the class header on the `_Impl` decompile and the UClass property registration confirm `ALuxTraceManager`. | `0x408` |
| `FLuxCapsule` | Capsule endpoint pair (visual). Layout known; container location uncertain on this build. | `0x50` |
| `ULuxTraceComponent` | Visual ticking component, holds `ActiveTraces[]`. | `0x4B0` |
| `ALuxTraceMeshActor` | Visual child actor, renders the trail. | — |
| `ULuxTracePartsDataAsset` | Visual curves / material params. | — |

## UFunctions on `ALuxTraceManager`

Three reflected UFunctions, registered via
`Z_Construct_UClass_ALuxTraceManager_Properties @ 0x140C0BA90`. Earlier
docs attributed these to `ALuxBattleChara`, which was wrong. To invoke them
on a chara, a reflection caller must first walk
`chara+0x458 → ALuxTraceManager*`, or else call the `_Impl` directly via RVA.

| UFunction | `_Impl` | exec trampoline | Behaviour |
|-----------|---------|-----------------|-----------|
| `Active(FTraceActiveParam)` | `0x1408CD940` | `0x140C3DA20` | Opens an attack-slot tag (1..9) into `traceMgr+0x3B0`. |
| `Inactive(FTraceInactiveParam)` | `0x1408D1420` | `0x140C3FD00` | Closes the slot; starts trail fade. |
| `GetTracePosition(byte, int32, out FVector, out FVector)` | `0x1408D0BB0` | `0x140C3F9B0` | **Stale** on this build — always returns `false`. |

`Active` reads only the first byte of its 0x30-byte `FTraceActiveParam` for hit logic: the
`AttackTag`. The remaining 47 bytes configure the visual trail.

```cpp
struct FTraceActiveParam {  // sizeof == 0x30 (48 bytes)
    uint8    AttackTag;      // +0x00 — the only field Active_Impl reads for hit resolution
    uint32   Flags;          // +0x04 — visual
    // ... cosmetic fields through +0x2C (trail tint FLinearColor at +0x1C)
};
```

## Active trace slots and weapon-capsule refresh

`Active_Impl` opens weapon-trace attack tags `1..9`. Reopening the same tag is
idempotent: the existing slot is reused or updated, not duplicated. `Inactive_Impl`
with tag `0` clears all active trace slots; with tag `1..9` it removes only that tag
from the active-slot hash. The visible trail may continue fading on `ULuxTraceComponent`
after `Inactive`, but the active-slot path no longer treats the tag as live.

`Update_Impl(X, Y)` is only an axis-feed setter. It writes
`ULuxTraceComponent+0x444 = X` and `ULuxTraceComponent+0x448 = Y`; it is not the
component tick and does not sample bones by itself.

| Symbol | Address | Modding use |
|---|---:|---|
| `ALuxTraceManager_execActivateTrace` | `0x140C41AB0` | UE4 exec trampoline for `ActivateTrace(Mode, SkeletalMesh, OwnerChara, KindIndex)` |
| `ALuxTraceManager_execUpdate` | `0x140C415E0` | UE4 exec trampoline for `Update(X, Y)` |
| `ALuxTraceManager_Active_Impl` | `0x1408CD940` | Opens weapon-trace attack tag `1..9` |
| `ALuxTraceManager_Inactive_Impl` | `0x1408D1420` | Closes one tag, or all tags when tag is `0` |
| `ALuxTraceManager_InsertActiveAttackSlot` | `0x1408C8D60` | Adds or updates one active trace slot |
| `ALuxTraceManager_UpdateActiveAttackSlotPositions` | `0x1408D8490` | Per-frame refresh of active weapon-trace slot positions |
| `ALuxTraceManager_ComputeCapsuleAndDirection` | `0x1408D1100` | Converts one matching `FLuxCapsule` into world hilt/tip/direction |
| `ALuxTraceManager_DispatchHitRequests` | `0x1408CEB40` | Dispatches queued weapon-trace hit requests |
| `ALuxTraceManager_SetSideActive` | `0x1408D5AB0` | Wrapper for trace effect visibility toggling |
| `ALuxTraceManager_EffectReg_SetSideActive` | `0x1408D5AD0` | Applies visibility to registered trace effect components |

`FActiveAttackSlot` entries are 0x44 bytes:

| Offset | Field | Meaning |
|---:|---|---|
| `+0x00` | `uint8 Tag` | Attack tag, matched against `FLuxCapsule.CapsuleType` |
| `+0x04` | `FVector VelocityA` | Hilt velocity |
| `+0x10` | `FVector VelocityB` | Tip velocity |
| `+0x1C` | `FVector PositionMid` | `(hilt + tip) * 0.5` |
| `+0x28` | `FVector DirectionUnit` | Direction from capsule/bone transform |
| `+0x34` | `uint8 GateStateByte` | Runtime validation state |
| `+0x38` | `int32 GateCountdown` | Six-frame grace window on gate changes |
| `+0x3C` | `int32 HashNextBucket` | Hash-chain link |
| `+0x40` | `int32 HashThisBucket` | Hash bucket/index bookkeeping |

!!! warning "Trace slots are not general hitboxes"
    Kicks, body strikes, throws, pushboxes, and hurtboxes do not use this
    trace-slot path. Those remain on the KHit linked-list system documented in
    [Hitbox System](hitbox-system.md). The trace helpers are useful for
    weapon-trail visuals and weapon-capsule visualization only.

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
name, the factor is 10: `LocalOffset` is stored in millimetres or a similar
decimetre-scaled internal unit, and multiplying by 10 lands the value in UE4 cm.

## `FLuxCapsuleContainer` (0x40 bytes — legacy view)

| Offset | Type | Name |
|-------:|------|------|
| +0x00..+0x2F | — | internal header |
| +0x30 | `FLuxCapsule**` | `Data` |
| +0x38 | `int32` | `Num` |
| +0x3C | `int32` | `Max` |

## Where the live `FLuxCapsule` array is on this build

Unconfirmed. The `FLuxCapsule` struct layout is correct, but the pointer array is no
longer reachable through `chara+0x388`. The best candidate is `ALuxBattleMoveCommandPlayer*`
at `BattleManager+0x4C0` — registered name `"BattleMoveCommandPlayer"` via
`Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`. It exposes 5 UFunctions
(`GetMovePlayParam`, `IsPlaying`, `PlayMove`, `PlayMoveDirect`, `StopMove`) plus 5 reflected
UPROPERTYs (`PlayData`, `Request`, `RequestInfo`, `PlayState`, `PlayStateInfo`) at
`+0x390..+0x3D0`.

Walk its fields for an 8-byte-aligned pointer to a 0x40-byte container whose `+0x30..+0x3C`
matches the `FLuxCapsuleContainer` shape.

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
as 1..9, based on one caller's `SlotIdx + 1` usage. A training-mode scan iterating
`InTracePartsId` from 1 to 64 sees many more types populated:

- **Always-on (idle stance)**: 1, 2, 3, 15, 18, 21, 24, 27. The hilt points shared across
  1/2/3 suggest body segments — likely **hurtboxes**.
- **Active-frame only**: the actual attack capsules. Numeric values vary per character and
  per move.

A mod that wants to visualise everything should scan at least 1..31, and possibly 1..63.

---

## Calling the trace UFunctions from Lua

`ALuxBattleChara::Active` / `Inactive` / `GetTracePosition` cannot be called via UE4SS Lua
reflection in the current public UE4SS builds. The class was registered with the short
`UE4_RegisterClass` variant (no `Ex`), so its UFunction parameter UProperty metadata is
missing. UE4SS surfaces this as the misleading *"Tried calling a member function but the
UObject instance is nullptr"* error on any call that takes arguments. Inherited AActor
UFunctions such as `K2_GetActorLocation` still work.

See [UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md) for the diagnosis.

## `ReceiveGetWeaponTip` — promising-looking dead end

SC6 registers a `BlueprintImplementableEvent` named `ReceiveGetWeaponTip` on
`ALuxBattleWeaponEventHandler`. It fires every frame during attacks — including ranged
moves like Cervantes's gun — so it looks like a universal weapon-endpoint query.

It is not useful: **no SC6 character's Blueprint subclass overrides the event.** Every
`ProcessEvent` post-hook arrives with `outRoot == outTip == (0,0,0)` and `bReturnValue == 0`.
The native caller (`ALuxBattleManager::GetTracePositionForPlayer @ 0x1403F4960`) ignores
the result and falls through to `GetTracePosition_Impl` unconditionally. The event is a BP
extension point that no one ever shipped an implementation for.

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

- **Public `GetTracePosition_Impl` remains stale / unreliable for reflection callers.**
  For weapon-capsule visualization, prefer hooking
  `ALuxTraceManager_UpdateActiveAttackSlotPositions @ 0x1408D8490` or
  `ALuxTraceManager_ComputeCapsuleAndDirection @ 0x1408D1100`.
- **`FLuxCapsule` radius.** The 80-byte struct holds two endpoints but no radius field. It
  likely lives on `TracePartsDataAsset` or on a sibling struct that the live container
  points at.
- **Cross-reference with the hitbox system.** The weapon-trace `FLuxCapsule` path here is
  still separate from the general KHit linked-list hitbox system. Do not use trace
  capsules as a substitute for KHit when inspecting kicks, body strikes, throws,
  pushboxes, or hurtboxes.

---

## Key binary addresses (RVA, image base `0x140000000`)

### Trace UFunctions and visual driver

| Symbol | RVA | Description |
|--------|-----|-------------|
| `ALuxTraceManager_Active_Impl` | `0x8CD940` | Opens weapon-trace attack slot. |
| `ALuxTraceManager_Inactive_Impl` | `0x8D1420` | Closes one weapon-trace tag, or all tags when tag is `0`. |
| `ALuxTraceManager_GetTracePosition_Impl` | `0x8D0BB0` | **Stale** — returns `false` for every real chara. |
| `ALuxTraceManager::GetTracePosition` exec trampoline | `0xC3F9B0` | VM trampoline; older Ghidra databases may still carry a chara-class label here. |
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
