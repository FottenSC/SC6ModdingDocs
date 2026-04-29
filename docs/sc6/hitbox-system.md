# Hitbox System (KHit linked lists)

How SC6 actually decides whether a hit landed. Strikes, kicks, hurtbox classification,
pushbox physics — all of it runs through three intrusive linked lists of `KHitBase*` nodes
on every chara, walked once per tick by `LuxBattle_TickHitResolutionAndBodyCollision @
0x14033CCA0`. No UE4 physics sweeps, no `GameTraceChannel` — analytical capsule-vs-capsule
tests on deterministic per-tick data.

This is a different system from the visual weapon trail. For the sword-swoosh / particle
effects, see [Trace System (weapon-trail VFX)](trace-system.md).

## At a glance

| What | Address / offset | Role |
|------|------------------|------|
| Tick driver | `LuxBattle_TickHitResolutionAndBodyCollision @ 0x14033CCA0` | Master per-tick hit resolution. |
| Body / pushbox list head | `chara+0x44478` | Chara-to-chara physical pushing only — not part of hit resolution. |
| Attack list head | `chara+0x44498` | Entries that DEAL damage or initiate a grab. |
| Hurtbox list head | `chara+0x444B8` | Entries that RECEIVE damage / reactions. |
| Classifier mask | `chara+0x44048` | Opponent's active-attack cell, copied each tick. |
| Own active-attack mask | `chara+0x44058` | Own move's per-frame mask cell. |
| Aggregation array | `chara+0x44078` (`u64[22]`) | `PerHurtboxBitmask` — one slot per kind tag. |
| Reaction output | `chara+0x1C74` (`i32[22]`) | `PerHurtboxReactionState` — `LuxHitReactionState` enum. |
| Node size | `0x80` (128 bytes) | Same for all subclasses. |
| Subclass tag | `node+0x16` | `0=Sphere`, `1=Area`, `2=FixArea`. |
| Geometry gate | `node+0x14` | `(hotMask >> KindTag) & 1` per tick. |
| Damage gate | `(hotMask & (1 << KindTag)) AND (*(u64*)(chara+0x44048))` | Both must be set for a hit to fire. |

> Source: Ghidra reverse-engineering of the SC6 Steam build, cross-validated by HorseMod's
> `KHitWalker.hpp` and `dllmain.cpp` plate comments.

---

## Three list heads on every chara

| Offset | Head | Role | Iterated by |
|-------:|------|------|-------------|
| `+0x44478` | `BodyListHead` | Body / pushbox — chara-to-chara physical pushing only. **Not** part of hit resolution. | `LuxBattle_SolvePhysBodyCollision @ 0x14030CCF0` |
| `+0x44498` | `AttackListHead` | Entries that DEAL damage or initiate a grab. | `LuxBattleChara_UpdateAllKHitWorldCenters @ 0x14030D6A0` (attacker side) |
| `+0x444B8` | `HurtboxListHead` | Entries that RECEIVE damage / reactions. | `UpdateAllKHitWorldCenters` (defender side) |

List counts live at the matching `head - 0x8` offsets (`+0x44470`, `+0x44490`, `+0x444B0`).

## Adjacent classifier state on the chara

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

## KHit node layout (0x80 bytes)

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

## Per-frame hot-mask

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

## Attack cell (`FLuxMoveBankCell`)

The pointer at `chara+0x44058` (and its per-tick opponent copy at `chara+0x44048`)
is **not** a `KHitBase`. It points at a 112-byte `FLuxMoveBankCell` row in the
character's move bank — see the [full layout in structures.md](structures.md#fluxmovebankcell-112-bytes).
The cell is what carries damage, hitstun, and hit-property values. Each cell holds:

- `u64SlotMask` (`+0x00`) — which authored hitbox slots are live while this cell is current.
- `wAttackFlags` (`+0x32`) — high / mid / low / unblockable bits.
- `nMasterWindowStart` / `nMasterWindowEnd` (`+0x36 / +0x38`) — frame range during which the cell is "active for damage" within the move's animation.
- `nBaseDamage` (`+0x3A`) and `nStunRecoil` (`+0x3C`) — the damage/stun applied on hit.
- `nBlockstunFrames` / `nHitstunStanding{Normal,Air}` / `nHitstunCrouch{Normal,Air}` / `nReactionId{Standing,Air}` / `nThrowEscapeId` (`+0x44 .. +0x54`) — per-stance reaction frame counts and post-hit move ids.
- `wHitboxGroupBitfield` (`+0x5E`) — selects one of 64 hit-sub-window timing entries; see [Per-cell sub-window timing](#per-cell-sub-window-timing).

### Cell lifetime: ONE cell per move

`LuxMoveVM_TransitionToMove @ 0x1402FE350` sets `chara+0x44058` from the move's
bank-slot record (`bank + bank[+0x10] + cellBone * 0x70`) and **does not change
it again** for the duration of the move. Verified two ways:

1. The bank-slot record carries a 6-entry short table at `+0x3C` — the
   "AnimVariant → cellBone" mapping. The lane state's `AnimVariantIndex`
   (`lane+0x460`) selects which entry to use. `TransitionToMove` resets that
   index to 0 at move start and never advances it natively.
2. `LuxMoveVM_SetActiveMoveSlot @ 0x140300C70` is the only function that
   re-resolves `chara+0x44058` mid-move using the variant table. It has zero
   native callers — only a `UFunction` wrapper. So a variant change requires
   an explicit reflection call from script (Lua / Blueprint), and the engine's
   bytecode VM (`LuxMoveVM_ExecuteAndDumpOpcode @ 0x140365900`) does not emit
   one. **Within a single native move, the cell is fixed.**

Practical consequence: every shape that hits while a given move is playing
applies the SAME `nBaseDamage` value. Damage does not vary mid-move.

### Per-part attack properties (e.g. tip-of-axe vs body-of-axe)

This is what the cell model actually supports:

- **Spatial selection only.** Each `KHitBase` shape on the AttackList has a
  distinct `KindTag` (`+0x17`), giving it a distinct `PerAttackerBit` (`1ULL <<
  KindTag`). The cell's `u64SlotMask` decides which of those shapes can register
  a hit. So a move with both a tip-shape and a body-shape can have its cell
  light only the tip bit — body contact then silently fails to register —
  without changing damage values.
- **Sub-window timing.** The cell can author up to 4 named sub-windows (one per
  bank) within its master window via `wHitboxGroupBitfield`, but the BaseDamage
  is still single-valued.
- **Damage variation across moves, not within one.** A character action whose
  damage actually differs depending on what hit (tip vs hilt vs body) is
  authored as **multiple separate moves**, with the move-VM bytecode chaining
  between them via `LuxMoveVM_EvaluateIfOpcode @ 0x1403732F0` predicates. Known
  IF subkeys that read state relevant to chaining:
  - `0x1389` — compares an immediate against `lane+0x460 AnimVariantIndex`.
  - The hit-window state at `chara+0x1980` (master-window phase 1/2/3) and the
    per-bank group ids at `chara+0x20BC..+0x20EE` are also exposed as predicates.
  Different sub-moves carry their own cell with their own `nBaseDamage`.

> The visual weapon trail (FLuxCapsule) does NOT modulate damage based on
> hilt-vs-tip contact distance. Damage is purely cell-driven.
> See [Trace System](trace-system.md).

### Per-cell sub-window timing

`LuxMoveVM_ClassifyHitboxFrameState @ 0x140300620` runs every tick to classify
where the current animation frame sits within the active cell's hit window:

```text
chara+0x1980 (state):
  1 = before MasterWindow      (curFrame < cell.nMasterWindowStart)
  2 = inside MasterWindow      (cell.nMasterWindowStart .. nMasterWindowEnd)
  3 = past MasterWindow
```

It then partitions `cell.wHitboxGroupBitfield & 0x7FF` into 4 banks of 16
groups (0..15, 16..31, 32..47, 48..63) and looks each up in a per-bank
sub-window timing table at:

| Bank | Table base | Stride | Entry shape |
|------|-----------|-------:|-------------|
| 0 | `DAT_1448554E8 + 0x338` | 8 | `(int16 startOffset, int16 endOffset, ...)` |
| 1 | `DAT_1448554E8 + 0x3B8` | 8 | same |
| 2 | `DAT_1448554E8 + 0x438` | 8 | same |
| 3 | `DAT_1448554E8 + 0x4B8` | 8 | same |

Each entry's offsets are relative to `nMasterWindowStart`, so the effective
sub-window is `[MasterWindowStart + entry.start, MasterWindowStart + entry.end]`.
The function writes 28 short slots at `chara+0x20BC..+0x20EE` that classify
the current frame against each sub-window — these are read by
`LuxBattleChara_GetImpactCategory @ 0x14033CB60` and as VM IF-opcode predicates.

This system controls **when** within the move's animation different hit-groups
are considered live. It does not provide a per-window damage value — the cell
still has only one `nBaseDamage`.

### Runtime cell mutation

The only field on a live cell known to change after move start is
`wRuntimePropagateField` at `+0x6A`, which `LuxMoveVM_PropagateFieldToHitboxGroup
@ 0x140303590` writes across the 8 cells of a hitbox-group entry (stride
`0x40`, 8 cell pointers at `+0x50/+0x58/+0x60/+0x68/+0x70/+0x78/+0x80/+0x88`).
The semantics aren't yet pinned down — open question for further RE.

### Cell-readers

| Function | RVA | Cell fields read |
|---|---|---|
| `LuxBattleChara_ProcessHit` | `0x342780` | `nBaseDamage` `nStunRecoil` `wExtraStateFlags` `wAttackFlags` |
| `LuxBattle_ApplyDamageFromPendingHit` | `0x2FF620` | `nBaseDamage` (counter-hit followup), null-check on `+0x44040 PrimaryAttackCellPtr` |
| `LuxMoveVM_EvaluateMoveTransition` | `0x33E140` | `wAttackFlags` `wInputCond` |
| `LuxBattle_ComputeHitReactionParams` | `0x343B90` | `wAttackFlags`, the full `+0x44 .. +0x54` block |
| `LuxBattle_ResolveAttackVsHurtboxMask22` | `0x33C100` | `u64SlotMask` (read as `attackerMask`), `wAttackFlags` (block-tier test) |
| `LuxMoveVM_SetActiveMoveSlot` | `0x300C70` | `u64SlotMask` (gates `KHitBase.+0x14`), `wPassthroughTag*` (mirrors to chara state) |
| `LuxMoveVM_ClassifyHitboxFrameState` | `0x300620` | `nMasterWindowStart` `nMasterWindowEnd` `wHitboxGroupBitfield` |
| `LuxMoveVM_PropagateFieldToHitboxGroup` | `0x303590` | writes `wRuntimePropagateField` |

## Strike vs throw partition

`LuxBattle_ResolveAttackVsHurtboxMask22 @ 0x14033C100` partitions the 64-slot mask space:

| Mask | Bits | Role |
|------|------|------|
| `0x80000080000000` | 31, 55 | **Throw / grab** |
| `0xFF7FFFFF7FFFFFFF` | every other | **Strike** |

A throw pre-scan runs before the per-hurtbox strike loop: if any throw bit is set in the
active-move mask, grab-transition logic fires first.

## KindTag inventory (partial)

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

## Reaction-state values

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

## Deserialisation path

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

## Reading hit volumes from a mod

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

## Frame-accurate damage gate

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

## What's still unfound

- **Projectile attacks** (Cervantes's pistol etc.). Whether they have entries in the
  attack list with a ranged-indicator kind tag, or use a parallel path, is open.
- **Per-character KindTag dictionaries.** Tags ≥18 and per-style overrides aren't catalogued.
- **Cross-reference with the trace system.** The visual `FLuxCapsule` system and the
  KHit `KHitArea` subclass both encode bone-pair endpoints. Whether any move authoring
  tool emits both representations from a single source isn't confirmed. See
  [Trace System](trace-system.md) for the visual side.

---

## Key binary addresses (RVA, image base `0x140000000`)

### Tick / classify / iterate

| Symbol | RVA | Description |
|--------|-----|-------------|
| `LuxBattle_TickHitResolutionAndBodyCollision` | `0x33CCA0` | Master hit-resolution tick. Plate comment in Ghidra documents the full hot-mask logic. |
| `LuxBattle_ResolveAttackVsHurtboxMask22` | `0x33C100` | Classifier; reads `OpponentActiveAttackCellCopy` and walks `PerHurtboxBitmask`. |
| `LuxBattle_SolvePhysBodyCollision` | `0x30CCF0` | Body / pushbox physics. Reads `BodyList`. |
| `LuxBattleChara_UpdateAllKHitWorldCenters` | `0x30D6A0` | Per-tick world-center refresh; runs the OR-aggregation that fills `PerHurtboxBitmask`. |

### Move-start deserialisation

| Symbol | RVA | Description |
|--------|-----|-------------|
| `LuxBattle_InitCharaSlotForMove_FirstRound` | `0x2D4070` | Top-level move-start init — calls the deserialiser for body / hurtbox / attack streams. |
| `Lux_KHitChk_DeserializeLinkedList` | (multiple sites) | Move-start deserialiser; called 3× from `InitCharaSlotForMove_FirstRound`. |
| `KHitChk_InitSphereFromStream` | `0x30E0D0` | Sphere-node deserialiser. |
| `KHitChk_InitAreaFromStream` | `0x30E3A0` | Area / FixArea deserialiser. |

### Per-tick world-center updates

| Symbol | RVA | Description |
|--------|-----|-------------|
| `KHitSphere_UpdateWorldCenter` | `0x30E1A0` | Per-tick sphere-node world refresh. |
| `KHitArea_UpdateWorldCenters` | `0x30E480` | Per-tick area-node world refresh (double-buffer toggle). |

### Hit / damage / state transitions

| Symbol | RVA | Description |
|--------|-----|-------------|
| `LuxBattleChara_ProcessHit` | `0x342780` | Defender-side post-hit handler; mirrors anim-frame into `chara+0x1360`. |
| `LuxBattle_ApplyDamageFromPendingHit` | (see Ghidra) | Damage application; checks `PrimaryAttackCellPtr +0x44040` for "damage window expired". |
| `LuxMoveVM_TransitionToMove` | `0x2FEC50` | Move-transition writer; sets per-lane state and `+0x44060` non-attack descriptor. |
| `LuxMoveVM_SetActiveMoveSlot` | `0x300C70` | Sets the per-move-slot mask at `**(chara+0x44058)`. |
| `LuxMoveVM_AdvanceLaneFrameStep` | `0x2FFEB0` | Per-tick lane frame-step advance. |
| `LuxMoveVM_CommitMoveEnd` | `0x2FCFB0` | Move-end finaliser. |
| `LuxBattleChara_SetStartPosition` | `0x301E60` | Canonical chara-teleport call. Writes `+0xA0` / `+0xC0` / `+0x2090` triples. |
| `LuxBattle_PositionCharasSymmetrically` | `0x302670` | Round-start pose; writes the side-flag at `+0x23C`. |
| `LuxEffectCamera_EvaluateAndTriggerSlowMotion` | `0x31D8F0` | Slow-motion gate; reads from active lane cursor. |

### Bone / matrix helpers

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
