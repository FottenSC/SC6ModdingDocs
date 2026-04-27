# Trace / Hitbox System

SC6 runs **two parallel hit-volume pipelines**. They share a coordination key (`AttackTag`
on Pipeline 1, `KindTag` on Pipeline 2) but are otherwise independent.

## At a glance

| Pipeline | Status | What it covers | Where the data lives | Native accessor |
|----------|--------|----------------|----------------------|-----------------|
| **Pipeline 2 — KHit linked lists** | **LIVE — drives every hit decision** | strikes, kicks, hurtboxes, pushboxes, grabs (everything) | three intrusive `KHitBase*` linked lists at `chara+0x44478/+0x44498/+0x444B8` | `LuxBattle_TickHitResolutionAndBodyCollision @ 0x14033CCA0` |
| **Pipeline 1 — `FLuxCapsule` + `ALuxTraceManager`** | Visual only; native accessor stale | weapon trail / sword swoosh / particle effects on weapon attacks only | `FLuxCapsule[]` reachable through `ALuxTraceManager` at `chara+0x458` (still being audited; legacy `chara+0x388` walk is broken — `+0x388` is now `CharaMesh0`) | `ALuxTraceManager_GetTracePosition_Impl @ 0x1408D0BB0` (returns `false` on real charas) |

To draw the actual hit volumes a mod author cares about, walk Pipeline 2.
[HorseMod's `KHitWalker`](https://example.com) is the reference implementation.

**Key offsets, both pipelines combined**:

| Offset | Type | What |
|-------:|------|------|
| `chara+0x388` | `USkeletalMeshComponent*` | `CharaMesh0` (NOT a MoveProvider on this build) |
| `chara+0x390` | `USkeletalMeshComponent*` | `WeaponMesh0` (NOT the opponent ptr) |
| `chara+0x3A8` | `ULuxTraceComponent*` | Pipeline-1 trail renderer (lazy) |
| `chara+0x3B0/+0x3F0/+0x3F8` | `FActiveAttackSlot[]` + hash | Pipeline-1 attack-slot hash |
| `chara+0x458` | `ALuxTraceManager*` | Pipeline-1 visual driver |
| **`chara+0x44478`** | `KHitBase*` | **Pipeline-2** body / pushbox list head |
| **`chara+0x44498`** | `KHitBase*` | **Pipeline-2** attack list head |
| **`chara+0x444B8`** | `KHitBase*` | **Pipeline-2** hurtbox list head |
| `chara+0x44048` | `KHitBase*` | Opponent's active-attack cell, copied each tick |
| `chara+0x44058` | `KHitBase*` | Own active-attack cell |
| `chara+0x44078` | `u64[22]` | `PerHurtboxBitmask` (defender-side aggregation) |
| `chara+0x1C74` | `i32[22]` | `PerHurtboxReactionState` (`LuxHitReactionState` enum) |
| `chara+0x973E8` | `ALuxBattleChara*` | Opponent (read by `LuxMoveVM_CheckRangeOrDistance`) |

> Source: Ghidra reverse-engineering, cross-validated by HorseMod's `KHitWalker.hpp` and
> `dllmain.cpp` plate comments.

---

## Pipeline 2 — KHit linked lists (live hit resolution)

The legacy Namco-port hit system. **Every hit decision in SC6 — strikes, kicks, throws,
hurtbox classification, pushbox physics — runs through these three linked lists.** No
UE4 physics sweeps, no `GameTraceChannel` — analytical capsule-vs-capsule tests on
deterministic per-tick data.

### Three list heads on every chara

| Offset | Head | Role | Iterated by |
|-------:|------|------|-------------|
| `+0x44478` | `BodyListHead` | Body / pushbox — chara-to-chara physical pushing only. **Not** part of hit resolution. | `LuxBattle_SolvePhysBodyCollision @ 0x14030CCF0` |
| `+0x44498` | `AttackListHead` | Entries that DEAL damage or initiate a grab. | `LuxBattleChara_UpdateAllKHitWorldCenters @ 0x14030D6A0` (attacker side) |
| `+0x444B8` | `HurtboxListHead` | Entries that RECEIVE damage / reactions. | `UpdateAllKHitWorldCenters` (defender side) |

List counts live at the matching `head - 0x8` offsets (`+0x44470`, `+0x44490`, `+0x444B0`).

### Adjacent classifier state on the chara

| Offset | Type | Name |
|-------:|------|------|
| `+0x44048` | `KHitBase*` | `OpponentActiveAttackCellCopy` — copy of opponent's `+0x44058`. The pointee's first `u64` is the live attacker-slot mask the classifier reads. |
| `+0x44050` | `short(*)[3]` | Mirror of opponent's `+0x44060` (downstream classifier reads only). |
| `+0x44058` | `KHitBase*` | `OwnActiveAttackCell` — own move's per-frame mask cell. |
| `+0x44060` | `short(*)[3]` | `NonAttackMoveDescrPtr` — `(DamageMultiplier, PassthroughTag, DurationTicks)` for non-damaging supers / SC finishers / stance / GI / parry transitions. Set by `LuxMoveVM_TransitionToMove`. |
| `+0x44068` | `LuxMoveLaneState*` | `ActiveLaneStateCursorPtr` — points at the running lane block (one of the three at `+0x444F0/+0x44958/+0x44DC0`). |
| `+0x44070` | `u8[6]` | `LastHitSourceCellLo48` — opaque 48-bit packed hit-id snapshot. |
| `+0x44078` | `u64[22]` | `PerHurtboxBitmask` — defender-side aggregation; bits of every attack-list node currently overlapping kind-tag `i`. |
| `+0x44494` | `i32` | `ClassifierHurtboxBound` — loop count for the per-kind walk (= attack list's max kind-tag + 1; reused as hurtbox iter bound). |
| `+0x444B4` | `i32` | `HurtboxMaxSlot` — hurtbox list's own max kind-tag + 1. **Not read by hit pipeline.** |
| `+0x1C74` | `i32[22]` | `PerHurtboxReactionState` — classifier output. See [reaction-state values](#reaction-state-values). |

### KHit node layout (0x80 bytes)

Common header (every subclass):

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| `+0x00` | `void*` | `vtable` | one of four subclass vtables (see addresses below) |
| `+0x08` | `u64` | `PerAttackerBit` / `PerHurtboxBit` | `1ULL << (KindTag & 0x3F)` — single-bit value derived from `+0x17` |
| `+0x10` | `u32` | `Node_Flags10` | **authored, write-only** — no runtime reader. Don't classify or gate on it. |
| `+0x14` | `u16` | `ActiveThisFrame` | per-frame **geometry** gate. See [hot-mask](#per-frame-hot-mask). |
| `+0x16` | `u8` | `StreamTypeTag` | `0=Sphere`, `1=Area`, `2=FixArea` |
| `+0x17` | `u8` | `KindTag` | KHit kind/category in `[0, ~22)`. **Not** a skeletal bone id. |
| `+0x18` | `KHitBase*` | `Next` | intrusive list link; null-terminates |
| `+0x20` | `i64` | `nextDelta` | `0x80` in practice |

Subclass vtables:

| Symbol | Address |
|--------|---------|
| `KHitBase_vftable` | `0x143E87838` |
| `KHitSphere_vftable` | `0x143E877F0` |
| `KHitArea_vftable` | `0x143E877A8` |
| `KHitFixArea_vftable` | `0x143E87760` |

Subclass extension fields:

```text
KHitSphere (StreamTypeTag = 0):
    +0x30  FVector  BoneLocalCenter         (mirrored at +0x40)
    +0x50  FVector  WorldCenterCurrent      (this frame)
    +0x60  FVector  WorldCenterPrevious     (last frame; for sweep tests)
    +0x70  float    Radius                  (may be scaled by anim cell)
    +0x74  float    RadiusAuthored
    +0x78  float    ContactImpulseScale
    +0x7C  uint32   BoneIndexUe4            (post-Remap)

KHitArea (StreamTypeTag = 1) — SWEPT CAPSULE, double-buffered for CCD:
    +0x30  FVector  BoneLocalP1
    +0x40  FVector  BoneLocalP2
    +0x50..+0x6F   WorldSpaceBufA  (P1, P2)
    +0x70..+0x8F   WorldSpaceBufB  (P1, P2)
                   g_LuxKHitArea_DoubleBufferToggle selects cur vs prev each tick.
                   Overlap test does 4-way segment/segment CCD across both halves.
    +0x90  float    ContactImpulseScale
    +0x94  uint32   BoneIndexUe4_P2

KHitFixArea (StreamTypeTag = 2) — STATIC OBB from THREE reference points:
    +0x30  FVector  BoneLocalPoint1   (P1, w=1.0 at +0x3C)
    +0x40  FVector  BoneLocalPoint2   (P2, w=1.0 at +0x4C)
    +0x50  FVector  BoneLocalPoint3   (P3, w=1.0 at +0x5C)
    +0x60  FVector  WorldPoint1
    +0x70  FVector  WorldPoint2
    +0x80  FVector  WorldPoint3
    +0x90  uint32   BoneIndexUe4
    +0x94  float    ContactImpulseScale
```

To recover an OBB from `KHitFixArea`'s three world-space points:

```cpp
// Gram-Schmidt
X       = normalize(WP2 - WP1);                    // primary axis
sideRaw = WP3 - WP1;
Y       = normalize(sideRaw - dot(sideRaw, X) * X);
Z       = cross(X, Y);
lenX    = |WP2 - WP1|;
lenY = lenZ = |sideRaw - dot(sideRaw, X) * X|;     // square cross-section
```

Cheaper alternative for visualisation: draw two lines `WP1→WP2` (spine) + `WP1→WP3` (side).

### Per-frame hot-mask

`+0x14 ActiveThisFrame` is written every tick by `LuxBattle_TickHitResolutionAndBodyCollision`:

```c
hotMask = 0x3FFFD                                  // FLOOR — slots {0, 2..17}
        | (animCellMask  ? *animCellMask  : 0)
        | (ownActiveCell ? *ownActiveCell : 0);

for (KHitBase* n in AttackList ∪ HurtboxList ∪ BodyList)
    n->ActiveThisFrame = (hotMask >> n->KindTag) & 1;
```

The `0x3FFFD` floor (`0b11_1111_1111_1111_1101`) forces slots `0, 2..17` on every frame —
structural / passive kinds (pushbox, standing hurtboxes, foot-anchored volumes). Slot `1`
is excluded: it's the move-driven active-attack kind, the only one that genuinely toggles
per move.

`+0x14` is a **geometry-live** gate, not a damage-live gate. A hit requires both:

1. `node->ActiveThisFrame != 0` (geometry/overlap pass)
2. The node's `KindTag` bit also set in `*(u64*)(chara + 0x44048)[0]` (classifier mask)

### Strike vs throw partition

`LuxBattle_ResolveAttackVsHurtboxMask22 @ 0x14033C100` partitions the 64-slot mask space:

| Mask | Bits | Role |
|------|------|------|
| `0x80000080000000` | 31, 55 | **Throw / grab** |
| `0xFF7FFFFF7FFFFFFF` | every other | **Strike** |

A throw pre-scan runs before the per-hurtbox strike loop: if any throw bit is set in the
active-move mask, grab-transition logic fires first.

### KindTag inventory (partial)

| Tag | Role |
|----:|------|
| 0 | passive structural (in floor) |
| 1 | **move-driven active attack** (NOT in floor) |
| 2..5 | passive hurtbox tiers (in floor) |
| 6, 7 | foot-anchored hit volumes (trigger ground-clamp pass) |
| 8..17 | other always-on structural volumes (in floor) |
| 18..21 | move-specific extensions |
| 22 | VFX-trigger marker (`LuxMoveVM_TransitionToMove` special case) |
| 23 | terrain-contact-blend marker |
| 31 | throw / grab |
| 55 | throw / grab |

The 22-wide `PerHurtboxBitmask` array mirrors this — one slot per kind tag.

### Reaction-state values

`PerHurtboxReactionState[i]` (i32[22] at `chara+0x1C74`) — the `LuxHitReactionState` enum:

| Value | Meaning |
|------:|---------|
| 0 | `None` |
| 1 | `Hit` |
| 2 | `BlockedLow` |
| 3 | `BlockedHigh` |
| 4 | `MH_Loser` |
| 6 | `Tech` |
| 8 | `MH_Winner` |
| 9 | `AirHit` |
| 0xA | `MH_Trade` |
| 0xB | `WallSplat` |
| 0xC | `Stagger` |

### Deserialisation path

Move bytecode hit volumes are deserialised on move-start by
`LuxBattle_InitCharaSlotForMove_FirstRound @ 0x1402D4070`, which calls
`Lux_KHitChk_DeserializeLinkedList` three times — once per stream type — into the three
list heads:

| Stream | Init helpers | List head | Max-slot |
|--------|--------------|-----------|----------|
| BODY | `KHitChk_InitSphereFromStream @ 0x14030E0D0` (sphere) / `KHitChk_InitAreaFromStream @ 0x14030E3A0` (area) / inlined FixArea branch | `chara+0x44478` | `chara+0x44484` |
| HURTBOX | (same three helpers) | `chara+0x444B8` | `chara+0x444B4` |
| ATTACK | (same three helpers) | `chara+0x44498` | `chara+0x44494` |

Per-frame world-center updates run in `LuxBattleChara_UpdateAllKHitWorldCenters @
0x14030D6A0`, which dispatches to the subclass updater:

- `KHitSphere_UpdateWorldCenter @ 0x14030E1A0` — `World = M * BoneLocal` using the chara's
  skeletal-mesh pose matrix.
- `KHitArea_UpdateWorldCenters @ 0x14030E480` — same per endpoint, plus toggles the
  double-buffer.

### Reading hit volumes from a mod

Resolve a bone-attached node's world-space geometry through `GetBoneTransformForPose`,
which returns an `FMatrix` (4×4 row-major affine — **not** an `FTransform` despite the
name):

```cpp
// 1) Internal bone id → UE4 bone index
//    For hurt/body nodes: remap the KindTag.
//    For sphere subclass:  use node[+0x7C] BoneIndexUe4 (already remapped).
int32 ueBone = LuxSkeletalBoneIndex_Remap(node->KindTag);

// 2) Bone matrix at this chara's pose (PoseSelector = playerIndex 0 or 1)
FMatrix M;
ALuxBattleChara_GetBoneTransformForPose(&M, chara, /*pose=*/playerIndex, ueBone);

// 3) World-space transform of bone-local point P (row-vector convention):
FVector world;
world.X = P.X*M.M[0][0] + P.Y*M.M[1][0] + P.Z*M.M[2][0] + M.M[3][0];
world.Y = P.X*M.M[0][1] + P.Y*M.M[1][1] + P.Z*M.M[2][1] + M.M[3][1];
world.Z = P.X*M.M[0][2] + P.Y*M.M[1][2] + P.Z*M.M[2][2] + M.M[3][2];
```

`g_LuxCmToUEScale = 10.0f @ 0x143E8A418` applies to the bone-local point **before** the
matrix multiply — the rotation rows of `M` have extracted-scale ≈ 1.0 and don't include
the cm→UE conversion.

### Frame-accurate damage gate

The mask in `**(chara+0x44058)` is set **once per move-slot** (in `LuxMoveVM_SetActiveMoveSlot
@ 0x140300C70`) and stays constant across that slot's startup / active / recovery frames. For
a per-sub-frame "is this slot dealing damage RIGHT NOW" answer, mirror the lookup
`TickHitResolutionAndBodyCollision` does each tick:

```c
moveSubId = *(uint16_t*)(chara + 0x44dc2);     // current sub-frame id
bankBase  = *(void**   )(chara + 0x455c0);     // MoveVM bank base
subBank   = (moveSubId >> 12) & 0xF;            // 0..15 sub-bank index
subOff    = *(uint16_t*)(bankBase + (subBank + 7)*4);
subCnt    = *(uint16_t*)(bankBase + 0x1e + subBank*4);
frameIdx  = moveSubId & 0x7FF;
if (frameIdx < subCnt) {
    sfRec    = bankBase + (subOff + frameIdx)*0x48 + 0x30;
    cellBone = *(int16_t*)(sfRec + 0x3c);
    cell     = (uint64_t*)(bankBase
                          + *(uint32_t*)(bankBase + 0x10)
                          + cellBone * 0x70);
    perFrameMask = *cell;   // <-- per-frame damage gate
}
```

---

## Pipeline 1 — Visual weapon trail (`FLuxCapsule` + `ALuxTraceManager`)

The visual side. Drives weapon-trail / sword-swoosh / particle effects on weapon attacks
(sword, axe, whip). **Not consulted by hit resolution.** The native accessor for reading
its capsule geometry is **stale on the shipping Steam build**.

### Ownership chain (verified runtime layout)

```text
ALuxBattleChara
    ├ +0x168  USceneComponent*          CustomRoot0
    │
    ├ +0x388  USkeletalMeshComponent*   CharaMesh0     (NOT MoveProvider)
    ├ +0x390  USkeletalMeshComponent*   WeaponMesh0    (NOT Opponent)
    │
    ├ +0x3A8  ULuxTraceComponent*       (lazy; created by ActivateTrace)
    │
    ├ +0x3B0  FActiveAttackSlot[]       hit-slot hash, AttackTag 1..9
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

### Why `chara+0x388` no longer reaches a capsule container

`ULuxBattleMoveProvider` is **absent** from the shipping binary — no
`Z_Construct_UClass_ULuxBattleMoveProvider`, no string match for the class name. Functions
that still encode the old `chara+0x388 → +0x30` walk are stale code paths:

- `ALuxTraceManager::GetTracePosition_Impl @ 0x1408D0BB0` — returns `false` for every real
  chara because `chara+0x388` is now `CharaMesh0`.
- `LuxMoveProviderRef_Get @ 0x14045FC70`, `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0`
  — same staleness, ~20 adjacent functions are effectively dead code on this build.

### Classes

| Class | Purpose | Size |
|-------|---------|-----:|
| `ALuxBattleChara` | Fighter actor. Declares `Active` / `Inactive` / `GetTracePosition` UFunctions. | `0x568` |
| `FLuxCapsule` | Pipeline-1 capsule endpoint pair. Layout known; container location uncertain on this build. | `0x50` |
| `ALuxTraceManager` | Visual-only weapon-trail driver. | `0x408` |
| `ULuxTraceComponent` | Visual ticking component, holds `ActiveTraces[]`. | `0x4B0` |
| `ALuxTraceMeshActor` | Visual child actor, renders the trail. | — |
| `ULuxTracePartsDataAsset` | Visual curves / material params. | — |

### UFunctions on `ALuxBattleChara`

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

### `FLuxCapsule` (0x50 bytes)

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

The legacy world-space chain (still used internally by `KHitArea` / Pipeline 2 — see
[Reading hit volumes from a mod](#reading-hit-volumes-from-a-mod)):

```text
bone  = LuxSkeletalBoneIndex_Remap(BoneId)
M     = ALuxBattleChara_GetBoneTransformForPose(chara, pose, bone)
off   = LocalOffset * g_LuxCmToUEScale * M.scale
World = M.rot * off + M.pos
```

`g_LuxCmToUEScale @ 0x143E8A418` = `10.0f` (bit pattern `0x41200000`). Despite the symbol
name, the factor is 10 — `LocalOffset` is stored in millimetres or a similar
decimetre-scaled internal unit; multiplying by 10 lands the value in UE4 cm.

### `FLuxCapsuleContainer` (0x40 bytes — legacy view)

| Offset | Type | Name |
|-------:|------|------|
| +0x00..+0x2F | — | internal header |
| +0x30 | `FLuxCapsule**` | `Data` |
| +0x38 | `int32` | `Num` |
| +0x3C | `int32` | `Max` |

### Where the live `FLuxCapsule` array is on this build

Unconfirmed. The `FLuxCapsule` struct layout is correct, but the array of pointers is no
longer reachable through `chara+0x388`. Best candidate is `ALuxBattleMoveCommandPlayer*` at
`BattleManager+0x4C0` — registered name `"BattleMoveCommandPlayer"` via
`Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`, exposes 5 UFunctions
(`GetMovePlayParam`, `IsPlaying`, `PlayMove`, `PlayMoveDirect`, `StopMove`) plus 5 reflected
UPROPERTYs (`PlayData`, `Request`, `RequestInfo`, `PlayState`, `PlayStateInfo`) at
`+0x390..+0x3D0`.

Walk its fields for an 8-byte aligned pointer to a 0x40-byte container whose `+0x30..+0x3C`
matches `FLuxCapsuleContainer` shape.

### `ELuxTraceKindId` (visual trail kinds)

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

### Empirical `CapsuleType` / `AttackTag` ranges

The plate comment on `Z_Construct_UFunction_..._GetTracePosition` documents the valid range
as 1..9 based on one caller's `SlotIdx + 1` usage. A training-mode scan iterating
`InTracePartsId` from 1 to 64 sees many more types populated:

- **Always-on (idle stance)**: 1, 2, 3, 15, 18, 21, 24, 27. Shared hilt points across 1/2/3
  suggest body segments — likely **hurtboxes**.
- **Active-frame only**: the actual attack capsules. Numeric values vary per character /
  per move.

A mod that wants to visualise everything should scan at least 1..31, possibly 1..63.

---

## Common across both pipelines

### Calling the trace UFunctions from Lua

`ALuxBattleChara::Active` / `Inactive` / `GetTracePosition` cannot be called from UE4SS Lua
reflection in the current public UE4SS builds. The class was registered with the short
`UE4_RegisterClass` variant (no `Ex`), so its UFunction parameter UProperty metadata is
missing. UE4SS surfaces this as the misleading *"Tried calling a member function but the
UObject instance is nullptr"* error on any call that takes arguments. Inherited AActor
UFunctions like `K2_GetActorLocation` still work.

See [UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md) for the diagnosis.

### `ReceiveGetWeaponTip` — promising-looking dead end

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

### Debug-draw flags (stripped in shipping)

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

- **Pipeline 1 → Pipeline 2 cross-reference.** `FLuxCapsule` (Pipeline 1) and `KHitArea`
  (Pipeline 2) both encode bone-pair endpoints. Whether any move authoring tool emits both
  representations from a single source isn't confirmed.
- **Live `FLuxCapsule` container on this build.** Layout known (0x50); container address
  uncertain since `chara+0x388` is now `CharaMesh0`. Best candidate: walk
  `ALuxBattleMoveCommandPlayer*` at `BattleManager+0x4C0`.
- **Projectile attacks** (Cervantes's pistol etc.). Whether they have entries in the
  Pipeline 2 attack list with a ranged-indicator kind tag, or use a parallel path, is open.
- **Per-character KindTag dictionaries.** Tags ≥18 and per-style overrides aren't catalogued.
- **`FLuxCapsule` radius.** The 80-byte struct holds two endpoints but no radius field;
  likely lives on `TracePartsDataAsset` or a sibling struct the live container points at.

---

## Key binary addresses (RVA, image base `0x140000000`)

### Pipeline 2 (live hit resolution)

| Symbol | RVA | Description |
|--------|-----|-------------|
| `LuxBattle_TickHitResolutionAndBodyCollision` | `0x33CCA0` | The master hit-resolution tick. Plate comment in Ghidra documents the full hot-mask logic. |
| `LuxBattle_ResolveAttackVsHurtboxMask22` | `0x33C100` | Classifier; reads `OpponentActiveAttackCellCopy` and walks `PerHurtboxBitmask`. |
| `LuxBattle_SolvePhysBodyCollision` | `0x30CCF0` | Body / pushbox physics. Reads `BodyList`. |
| `LuxBattleChara_UpdateAllKHitWorldCenters` | `0x30D6A0` | Per-tick world-center refresh; runs the OR-aggregation that fills `PerHurtboxBitmask`. |
| `LuxBattle_InitCharaSlotForMove_FirstRound` | `0x2D4070` | Top-level move-start init — calls the deserialiser for body / hurtbox / attack streams. |
| `Lux_KHitChk_DeserializeLinkedList` | (multiple sites) | Move-start deserialiser; called 3× from `InitCharaSlotForMove_FirstRound`. |
| `KHitChk_InitSphereFromStream` | `0x30E0D0` | Sphere-node deserialiser. |
| `KHitChk_InitAreaFromStream` | `0x30E3A0` | Area / FixArea deserialiser. |
| `KHitSphere_UpdateWorldCenter` | `0x30E1A0` | Per-tick sphere-node world refresh. |
| `KHitArea_UpdateWorldCenters` | `0x30E480` | Per-tick area-node world refresh (double-buffer toggle). |
| `LuxBattleChara_ProcessHit` | `0x342780` | Defender-side post-hit handler; mirrors anim-frame into `chara+0x1360`. |
| `LuxBattle_ApplyDamageFromPendingHit` | (see Ghidra) | Damage application; checks `PrimaryAttackCellPtr +0x44040` for "damage window expired". |
| `LuxMoveVM_TransitionToMove` | `0x2FEC50` | Move-transition writer; sets per-lane state and `+0x44060` non-attack descriptor. |
| `LuxMoveVM_SetActiveMoveSlot` | `0x300C70` | Sets the per-move-slot mask at `**(chara+0x44058)`. |
| `LuxMoveVM_AdvanceLaneFrameStep` | `0x2FFEB0` | Per-tick lane frame-step advance. |
| `LuxMoveVM_CommitMoveEnd` | `0x2FCFB0` | Move-end finaliser. |
| `LuxBattleChara_SetStartPosition` | `0x301E60` | Canonical chara-teleport call. Writes `+0xA0` / `+0xC0` / `+0x2090` triples. |
| `LuxBattle_PositionCharasSymmetrically` | `0x302670` | Round-start pose; writes the side-flag at `+0x23C`. |
| `LuxEffectCamera_EvaluateAndTriggerSlowMotion` | `0x31D8F0` | Slow-motion gate; reads from active lane cursor. |

### Pipeline 1 (visual trail; mostly stale on this build)

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

### Common helpers (used by both pipelines)

| Symbol | RVA | Description |
|--------|-----|-------------|
| `ALuxBattleChara_GetBoneTransformForPose` | `0x462760` | `(chara, pose, boneIdx) → FMatrix`. Returns 4×4 affine, NOT FTransform. |
| `LuxSkeletalBoneIndex_Remap` | `0x898140` | 8-bit internal idx → UE skeleton bone idx. Returns `0xFFFFFFFF` on failure. |
| `g_LuxCmToUEScale` | `0x143E8A418` | Scale constant; value is `10.0f`. |

### Subclass vtables

| Symbol | Address |
|--------|---------|
| `KHitBase_vftable` | `0x143E87838` |
| `KHitSphere_vftable` | `0x143E877F0` |
| `KHitArea_vftable` | `0x143E877A8` |
| `KHitFixArea_vftable` | `0x143E87760` |
