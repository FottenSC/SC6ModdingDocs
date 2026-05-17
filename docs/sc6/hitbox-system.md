# Hitbox System (KHit linked lists)

How SC6 actually decides whether a hit landed. Strikes, kicks, hurtbox classification, and
pushbox physics all run through three intrusive linked lists of `KHitBase*` nodes on every
chara, walked once per tick by `LuxBattle_TickHitResolutionAndBodyCollision @ 0x14033CCA0`.
There are no UE4 physics sweeps and no `GameTraceChannel` — just analytical
capsule-vs-capsule tests on deterministic per-tick data.

This is a different system from the visual weapon trail. For the sword-swoosh / particle
effects, see [Trace System (weapon-trail VFX)](trace-system.md). For what happens **after**
a hit is classified (yarare dispatch, per-id reaction Tick, knockdown camera, throw-react),
see [Reaction System](reaction-system.md).

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
| Geometry gate | `node+0x14` | Attack list: `(hotMask >> KindTag) & 1` per tick. Hurtbox list: written on demand by MoveVM opcode `0x13AC`. See [per-frame hot-mask](#per-frame-hot-mask). |
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
| `+0x44068` | `FLuxMoveLane*` | `ActiveLaneStateCursorPtr` — points at the running lane block (one of the three at `+0x444F0/+0x44958/+0x44DC0`). Was `LuxMoveLaneState*`. |
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

```
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

```
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

`+0x14 ActiveThisFrame` is written by two **separate** writers, one per list. They use
different mechanisms — do not assume the attack-side hot-mask logic applies to hurtboxes.

### Attack list (`chara+0x44498`)

Written every tick by `LuxBattle_TickHitResolutionAndBodyCollision`:

```
hotMask = 0x3FFFD                                  // FLOOR — slots {0, 2..17}
        | (animCellMask  ? *animCellMask  : 0)
        | (ownActiveCell ? *ownActiveCell : 0);

for (KHitBase* n in AttackList)                    // ATTACK ONLY
    n->ActiveThisFrame = (hotMask >> n->KindTag) & 1;
```

The `0x3FFFD` floor (`0b11_1111_1111_1111_1101`) forces slots `0, 2..17` on every frame —
structural / passive kinds (foot-anchored / body-attached volumes). Slot `1` is excluded:
it's the move-driven active-attack kind, the only one that genuinely toggles per move.

### Hurtbox list (`chara+0x444B8`)

Written **on demand** by the move-VM bytecode via opcode `0x13AC`
(`LuxMoveVM_SetHurtboxSlotsActiveMask @ 0x140308D70`). The opcode carries a slot bitmask;
the writer iterates the chara's hurtbox list and, for each node, ORs or clears the `+0x14`
byte depending on whether the node's `KindTag` bit is set in the bitmask.

There is **no per-tick floor** on the hurtbox side. A hurtbox authored with `+0x14 = 0`
stays at zero until a move's VM script flips it on, then reverts to zero when a later move
flips it off — the engine never ORs a default-on bit per frame. Most hurtboxes are
authored with `+0x14 = 1` and are never touched by `0x13AC`, so they appear "always on".
Moves with VM-gated extension hurtboxes (e.g. Geralt's two large rectangles) sit at
zero by default and are enabled only for the frames that move's script asks for.

The body list (`chara+0x44478`) is not iterated by either writer — its `+0x14` is whatever
the move's KHit deserializer authored.

### Damage requires both gates

`+0x14` is a **geometry-live / overlap-test** gate, not a damage-live gate. The defender's
overlap loop in `LuxBattleChara_UpdateAllKHitWorldCenters @ 0x14030D6A0` skips any
hurtbox with `+0x14 == 0`, so no `PerHurtboxBitmask` bits get OR'd and no reaction can fire.

For a hit to actually fire damage, both must pass:

1. `node->ActiveThisFrame != 0` (geometry/overlap pass)
2. The node's `KindTag` bit also set in `*(u64*)(chara + 0x44048)[0]` (classifier mask)

### Practical consequence for hitbox overlays

If a mod displays both lists with a single `+0x14`-based filter, the filter behaves
correctly on the attack side (per-tick rewrite) but will *under-show* the hurt side for
moves with VM-gated hurtbox extensions: the extension boxes appear only when their move
enables them and disappear otherwise. That is the engine truth — those hurtboxes are not
vestigial, they are gated geometry the move turns on per-frame.

## Attack cell (`FLuxMoveBankCell`)

The pointer at `chara+0x44058` (and its per-tick opponent copy at `chara+0x44048`)
is **not** a `KHitBase`. It points at a 112-byte `FLuxMoveBankCell` row in the
character's move bank — see the [full layout in structures.md](structures.md#fluxmovebankcell-112-bytes).
The cell carries the move's damage, hitstun, and hit-property values. Each cell holds:

- `u64SlotMask` (`+0x00`) — which authored hitbox slots are live while this cell is current.
- `wAttackFlags` (`+0x32`) — block-direction + modifier flags
  (`ELuxBattleAttackFlags`); see [Attack flags](#attack-flags) below.
- `nMasterWindowStart` / `nMasterWindowEnd` (`+0x36 / +0x38`) — frame range during which the cell is "active for damage" within the move's animation.
- `nBaseDamage` (`+0x3A`) and `nStunRecoil` (`+0x3C`) — the damage/stun applied on hit.
- `nBlockstunFrames` / `nHitstunStanding{Normal,Air}` / `nHitstunCrouch{Normal,Air}` / `nReactionId{Standing,Air}` / `nThrowEscapeId` (`+0x44 .. +0x54`) — per-stance reaction frame counts and post-hit move ids.
- `wHitboxGroupBitfield` (`+0x5E`) — selects one of 64 hit-sub-window timing entries; see [Per-cell sub-window timing](#per-cell-sub-window-timing).

### Attack flags

`cell+0x32 wAttackFlags` is a 16-bit flag word. Engine-verified bits
(Ghidra enum `ELuxBattleAttackFlags`, read by `LuxMoveVM_EvaluateMoveTransition
@ 0x14033E140` and `LuxBattle_ResolveAttackVsHurtboxMask22 @ 0x14033C100`):

| Bit | Name | Meaning |
|----:|------|---------|
| `0x001` | `HighBlockable` | blockable while standing |
| `0x002` | `LowBlockable` | blockable while crouching |
| `0x004` | `BlockBypass_GuardBreak` | routes to the counter-hit-special result vs a guard-broken defender |
| `0x008` | `LowAttack` | low block-level bit |
| `0x010` | `MidAttack` | mid block-level bit |
| `0x040` | `CrouchOnly` | attacker authored as crouching |
| `0x080` | `HighAttack` | high block-level bit (crouch ducks under) |
| `0x100` | `Special_FlagX100` | special framing rule (largely opaque) |
| `0x200` | `Unblockable_GIImmune` | defender's Guard-Impact roll is forced to fail. Alone (no block bits) → genuinely unblockable; combined with block bits → a **Break Attack** (blockable, but forces the stagger-block reaction). |

!!! warning "These flags are not a reliable move-class tag"
    The block-level bits drive block / hit resolution but are a poor proxy
    for the move's displayed **High / Mid / Low class** — most cells set
    `HighBlockable` regardless of the move's actual height, and one cell
    cannot represent a multi-hit move's class sequence. For a move's class
    use `DA_MoveListTable.AttributeTag` — see
    [Character Data: Move-list metadata](character-data.md#move-list-text-and-metadata).

### Cell lifetime: ONE cell per move

`LuxMoveVM_TransitionToMove @ 0x1402FE350` sets `chara+0x44058` from the move's
bank-slot record (`bank + bank[+0x10] + cellBone * 0x70`) and **does not change
it again** for the duration of the move. Verified two ways:

1. The bank-slot record carries a 6-entry short table at `+0x3C` — the
   "AnimVariant → cellBone" mapping. The lane state's `AnimVariantIndex`
   (`lane+0x460`) selects which entry to use. `TransitionToMove` resets that
   index to 0 at move start and never advances it natively.
2. `LuxMoveVM_SetActiveMoveSlot @ 0x140300C70` is the only function that
   re-resolves `chara+0x44058` mid-move via the variant table, and it has zero
   native callers — only a `UFunction` wrapper. A variant change therefore
   requires an explicit reflection call from script (Lua / Blueprint); the
   engine's bytecode VM (`LuxMoveVM_ExecuteAndDumpOpcode @ 0x140365900`) never
   emits one. **Within a single native move, the cell is fixed.**

Practical consequence: every shape that hits while a given move is playing
applies the SAME `nBaseDamage` value. Damage does not vary mid-move.

### Cell mask bit-pattern decoding (`u64SlotMask`)

`LuxMoveVM_TickHitResolutionAndBodyCollision` and `LuxMoveVM_TransitionToMove`
do double-duty on the cell's `u64SlotMask`:

1. As a **bitmap of which KHit shape slots are live** (used by the per-frame
   hot-mask gate at `KHitBase.+0x14` and by the classifier at
   `LuxBattle_ResolveAttackVsHurtboxMask22`).
2. As a **bit-pattern encoding of the move's hit-class** (high / mid / low /
   throw / wire / super) — decoded by `TransitionToMove` into two outputs.

The two outputs of the decode are written to the chara at move-start:

`chara+0x1354 dwMoveType` (5 values):

| Value | Meaning | Detect rule |
|---:|---|---|
| 1 | Strike | `(mask & 0x7FF0003F800000) != 0` |
| 3 | Grab | `(mask & 0x33F0C0) != 0` AND not strike |
| 4 | Wire | `cell+0x34 & 0x10` AND addr-flag in cell+0x0C |
| 6 | Super | None of the above set |
| 7 | SC attack | When chara's `MoveSubclassAlt == 7` |

`chara+0x1358 dwAnimKind` (high/mid/low classification):

| Value | Meaning | Detect rule |
|---:|---|---|
| 0 | Neutral / no-tag | default |
| 1 | Standard hit | default-strike |
| 2 | High-attack | bit pattern `0x1800000` (bits 23-24) |
| 3 | Mid-attack | bit pattern `0x6000000` (bits 25-26) |
| 4 | Low-attack | bit pattern `0x1000008000000` (bits 27, 48) |
| 5 | Special-mid | bit pattern `0x2000010000000` (bits 28, 49) |
| 6 | Special-low | bit pattern `0x4000020000000` (bits 29, 50) |
| 9 | Grab kind A | bit pattern `0x8100000000000` (bits 40, 51) |
| 10 | Grab kind B | bit pattern `0x10200000000000` (bits 41, 52) |
| 0xB | Grab kind C | bit pattern `0x20400000000000` OR `0x40800000000000` |

So the KindTag values in `[22..30]` form one "low-bits" hit-class group,
mirrored at `[48..55]` for the second hit-class group. Together the two
ranges encode 4-8 strike-class bits with distinct semantics, plus the
throw bits at 31/55 for grab signalling.

**Override chain via `chara+0x250 MoveSubclassAlt`:** the default decode
above is overridden for these subclass values:

- `4, 5, 0x1E, 0x23, 0x2F`: force `dwAnimKind = 0` (neutral).
- `0xB, 0x16`: set `bWasFlagSet`, force `dwAnimKind = 0`.
- `0x29` (41): tests bits `0x1C00000000000..0x40000000000000` plus
  `0x100..0x800000000000` to compute `dwAnimKind` with a complex priority
  chain.
- `0x36` (54): tests bits `0x800000 / 0x10000000000000` to toggle between
  0 and 1.
- `0x37` (55): if `mask & 0x2000010000000` sets `dwAnimKind = 6`.
- `0x3A` (58): tests `0x800000 / 0x10000000000000` → 0/1.
- `0x3B` (59): tests `0x800000 / 0x100000000000 / 0x10000000000000 /
  0x4000000000000` with priority — outputs 3 or 0.

These overrides reinterpret the same slot-mask bits per move class. They are
**not** per-character: chara+0x250 is the move's `MoveSubclassAlt` (set
per-move from the move definition), not a character ID. The character ID is at
`chara+0x23C CharaKindByte`.

### Non-attack ALT-path

When the resolved cell address has bit `0x1000` set in its high u16
(`shortAddr & 0x1000`), the move is a **non-attack** definition: it has no
damage-cell payload but still needs a per-move passthrough record for
stance/GI/parry transitions. `TransitionToMove` takes the ALT branch:

- Leaves `chara+0x44058 = NULL` (no active attack cell).
- Leaves `chara+0x44040 = NULL` (no primary attack cell either).
- Writes `chara+0x44060 = bankBase + bank[+0x14] + (subIdx & ~0x1000) * 6`
  pointing at the 6-byte short[3] non-attack descriptor:

```
[0]  i16 DamageMultiplier  — multiplied into final damage scalar
[1]  i16 PassthroughTag    — copied to defender chara+0x210C
[2]  i16 Duration60ths     — /60.0f → attacker+0x414 damage bucket
```

- Mirrors `short[1]` into `chara+0x210A` (PassthroughTag mirror).

The non-attack descriptor is consumed downstream by:

- `LuxBattle_ApplyDamageFromPendingHit @ 0x1402FF620` — reads all 3 shorts on
  damage application.
- `LuxMoveVM_EvaluateMoveTransition @ 0x14033E140` — branches on
  PassthroughTag for special hit-reaction selection.

Use cases: non-damaging supers, SC finishers, stance entries, GI/parry
reactions, throw-whiff recovery, scripted-damage move kickers.

### Per-part attack properties (e.g. tip-of-axe vs body-of-axe)

This is what the cell model actually supports:

- **Spatial selection only.** Each `KHitBase` shape on the AttackList has a
  distinct `KindTag` (`+0x17`), and therefore a distinct `PerAttackerBit` (`1ULL <<
  KindTag`). The cell's `u64SlotMask` decides which of those shapes can register
  a hit. A move with both a tip-shape and a body-shape can have its cell
  light only the tip bit — body contact then silently fails to register —
  without any change to damage values.
- **Sub-window timing.** The cell can author up to 4 named sub-windows (one per
  bank) within its master window via `wHitboxGroupBitfield`, but BaseDamage
  is still single-valued.
- **Damage variation across moves, not within one.** A character action whose
  damage genuinely differs depending on what hit (tip vs hilt vs body) is
  authored as **multiple separate moves**, with the move-VM bytecode chaining
  between them via `LuxMoveVM_EvaluateIfOpcode @ 0x1403732F0` predicates. Known
  IF subkeys that read chaining-relevant state:
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

```
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
the current frame against each sub-window; these are read by
`LuxBattleChara_GetImpactCategory @ 0x14033CB60` and as VM IF-opcode predicates.

This system controls **when**, within the move's animation, different hit-groups
are considered live. It does not provide a per-window damage value — the cell
still has only one `nBaseDamage`.

### Runtime cell mutation

The only field on a live cell known to change after move start is
`wRuntimePropagateField` at `+0x6A`. `LuxMoveVM_PropagateFieldToHitboxGroup
@ 0x140303590` writes it across the 8 cells of a hitbox-group entry (stride
`0x40`, 8 cell pointers at `+0x50/+0x58/+0x60/+0x68/+0x70/+0x78/+0x80/+0x88`).
Its semantics are not yet pinned down — an open question for further RE.

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
active-move mask, grab-transition logic fires first. The pre-scan stamps a single u16:

```
defender + 0x212E := attacker + 0x212C    // the throw "yarareId" pair-sync token
```

Normal strikes leave `defender+0x212E == 0xFFFF`. The yarareId is what
syncs the victim's getting-thrown ("yarare" / やられ) animation to the
initiator's grab animation.

## Throw connection: the size / height-bucket gate

Even when geometry overlaps AND the throw pre-scan stamps the yarareId,
the throw can still fail to connect. The downstream gate lives in
`LuxMoveVM_TickPickAndDispatchReaction @ 0x1402DEF50`.

### `LuxMoveVM_GetCharaEffectiveHeight @ 0x140309470`

Computes a per-chara "effective height" in game units. Default
(grounded-stance) branch:

```
iVar = (int)float(chara+0x44968)                                       // head bone world Y
     - (int)(short)g_LuxBattle_CharaKindStatureTable[bKindByte * 0xF0]  // PER-CHARAKIND OFFSET
     - (int)float(chara+0x44960);                                       // foot bone world Y
return clamp_lo0(iVar);
```

Special-case branches (combo-active, knockback, override, etc.) return
fixed buckets (0, 1, 9999, or `chara+0x1364` floor-contact). The
key per-character calibration is the table at
**`g_LuxBattle_CharaKindStatureTable @ 0x14470D200`**, stride `0xF0`,
indexed by `chara+0x23C bCharaKindByte`. Identical world-Y bones produce
different effective heights for tall vs. short charas — this is the
per-character "size" attribute.

### The dispatch-allow gate (root cause of "small grabs tall whiff")

At the END of `TickPickAndDispatchReaction`:

```c
iVar7 = GetCharaEffectiveHeight(self);             // self = DEFENDER (the chara whose VM is ticking)
iVar8 = GetCharaEffectiveHeight(self->OppChara);   // opp = attacker

// Pre-pick shortcut at ~0x1402DFB58:
if (((2 < iVar8) || (iVar8 == 0)) && (4 < iVar7)) goto SKIP_WEIGHT_PICK;

// (...weight-pick selects postEffectYarareId...)

// Final dispatch-allow bitset at ~0x1402DFBC0:
uint allowDispatch = (iVar7 < 5);                  // 0 when defender is TALL
if (postId in {0x1F, 0x21, 0x20})           allowDispatch = 1;
if (postId in {0x2C, 0x2D})                 allowDispatch = 1;   // launch / air-carry
if (postId in {0x2E..0x31, 0x3B})           allowDispatch = 1;   // ringout / back-breaker
if (intensity > 1 && postId in {0x28..0x2B}) allowDispatch = 1;
if (postId in {0xE..0x10})                  allowDispatch = 1;   // wall stagger

if ((MoveStateId == 3 && +0x1982 != 0) || allowDispatch != 0)
    LuxBattle_DispatchYarareReaction(...);          // <-- throw actually commits here
```

**Throw-catch yarareIds are NOT in the unconditional allow-set.** They
dispatch only when `iVar7 < 5`. When the DEFENDER is the tallest
character in the cast, `iVar7 >= 5` and the dispatch is silently
dropped: the geometry overlap registers and the throw classifier stamps
the yarareId at `defender+0x212E`, but no damage, animation, or reaction
ever fires. This is the gate behind the "smallest grabs tallest, boxes
contact, but throw whiffs" empirical bug.

The `iVar8` term (attacker height) is consulted only by the pre-pick
shortcut, which gates the **random weight-pick** for non-throw
reactions — not the throw dispatch itself.

| Field | Type | Role |
|-------|------|------|
| `g_LuxBattle_CharaKindStatureTable @ 0x14470D200` | `int16[stride 0xF0]` | per-charaKind stature offset (the "size" attribute) |
| `chara+0x23C` | `byte` `bCharaKindByte` | indexes the stature table |
| `chara+0x44960` | `float` | foot-bone world Y |
| `chara+0x44968` | `float` | head-bone world Y |
| `chara+0x44978` | `float` | projected reach scalar |
| `chara+0x19DC` | `u16` | reach override (when non-zero, replaces head-foot subtraction) |
| `chara+0x1364` | `float` | floor-contact height (used during combo-active branch) |
| `chara+0x212C` | `u16` | attacker's outgoing throw yarareId |
| `chara+0x212E` | `u16` | defender's incoming throw yarareId (`0xFFFF` when no throw stamped) |

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

## Block direction & ducking-while-guarding

How the engine decides whether a hit is BLOCKED, HITS, or DUCKS UNDER,
based on the defender's stance against the attack's level.

### The two-byte stance system

The defender carries TWO crouch-state bytes inside the per-chara
motion-flag bank (`chara+0x16D0..+0x170F`, 64 single-byte flags):

| Byte | Flag idx | Name | Role |
|------|---------:|------|------|
| `chara+0x16D2` | 0x02 | `bGuardCrouchStateBase` | AUTHORITATIVE crouch state. Set/cleared only when a stance-changing MOVE is committed (via `LuxMoveVM_ApplyLaneMotionInputMasks @ 0x1402FD7F0`, which reads the move-bank slot's `qwInputSetMask` / `qwInputClearMask` at `+0x20`/`+0x28`). 0 = standing, 1 = crouching. |
| `chara+0x16FC` | 0x2C | `bAltGuardCrouchState` | PER-FRAME re-derived stance. Reset to 0 every tick by `TickCharaMainSimulation @ 0x14034DA70`, then re-computed by `LuxBattleChara_UpdateGuardStanceFlags @ 0x140309370` when a guard predicate needs the freshest answer. Reads raw inputs from `chara+0x2150 / +0x2164 / +0x3494`. |
| `chara+0x1701` | 0x31 | `bAltGuardLocked` | When set, the alt is authoritative for hit-resolution. Cleared each tick + set by `UpdateGuardStanceFlags`. |
| `chara+0x16FD` | 0x2D | `bIsGuardingFlag` | Set this frame when the chara is actively in a guard pose with valid guard input. |

### Resolver: `LuxBattleChara_CheckGuardConditionForHitbox @ 0x1403056E0`

Returns the chara's effective crouch state for matching against an
incoming attack:

```
byte CheckGuardCondition(chara, cell)
{
  if (cell != NULL && (chara+0x3494 & 0x08) == 0) {
    // (bit 3 of +0x3494 = guard-disabled — fall through to alt)

    if (chara+0x16DC != 0 && (cell.AttackFlags & 0x3) != 0)
      return chara+0x16D2;   // BLOCKSTUN + block-tagged attack: lock to base
    if (chara+0x16DB != 0 && (cell.AttackFlags & 0x80) != 0)
      return chara+0x16D2;   // HITSTUN + high-tagged attack: lock to base
  }
  return (chara+0x1701 != 0) ? chara+0x16FC   // alt (per-frame)
                             : chara+0x16D2;  // base (move-VM)
}
```

The two LOCK conditions enforce the rule that you cannot change stance
mid-blockstun or mid-hitstun. The "alt" mechanism applies only during
neutral, between attacks, or in non-blocking gates.

### Per-frame stance update: `LuxBattleChara_UpdateGuardStanceFlags @ 0x140309370`

Reads inputs and stance constraints, writes `chara+0x16FC` and
`chara+0x16FD`. Algorithm:

```
if (chara+0x1701 != 0) return;  // already locked

inputAllowed = (chara+0x132C <= 1) || (chara+0x3494 & 0x04);
newStance = chara+0x16D2;      // start from base

if (chara+0x198C == 0x16) {
  // Perfect-guard window — lock stance to base.
} else if (chara+0x16DC == 0 && inputAllowed && (chara+0x2150 >> 3) & 1) {
  // Not in blockstun, stance-change allowed, guard input held.
  mask = chara+0x2164 & 0x4004;            // bits 2 & 14 of input mask
  if ((chara+0x3494 & 1) && mask == 0) newStance = 0;   // STAND input
  if ((chara+0x3494 & 2) && mask != 0) newStance = 1;   // SIT input
}
chara+0x16FC = newStance;

// Verify input matches new stance and commit IS-GUARDING latch:
if ((chara+0x3494 & 3) != 0) {
  if (newStance == 0 && (chara+0x3494 & 1) == 0) return;
  if (newStance == 1 && (chara+0x3494 & 2) == 0) return;
}
if (((chara+0x2150 >> 3) & 1) && inputAllowed) chara+0x16FD = 1;

chara+0x1701 = 1;   // lock the alt for this tick
chara+0x16D1 = 0;
```

Field decode:

| Field | Bits / value | Meaning |
|-------|-------------|---------|
| `chara+0x3494` | bit 0 (0x01) | "STAND-input allowed" flag from move bank |
| `chara+0x3494` | bit 1 (0x02) | "SIT-input allowed" flag from move bank |
| `chara+0x3494` | bit 2 (0x04) | "stance-change allowed" gate |
| `chara+0x3494` | bit 3 (0x08) | "guard-disabled" — guard ignored entirely |
| `chara+0x3494` | bit 5 (0x20) | guard-impact-related |
| `chara+0x2150` | bit 3 | "guard input active" master gate |
| `chara+0x2164` | bit 2 (0x0004) + bit 14 (0x4000) | DOWN-direction held (the SIT input) |
| `chara+0x132C` | int | `nDefenseModeAtLastHit` — sample of `chara+0x1334` taken at the moment of the last hit. See [DefenseMode](#defensemode-chara0x1334) below. `> 1` blocks free stance change unless `+0x3494 bit 2` overrides. |
| `chara+0x198C` | == 0x16 | perfect-guard window — stance locked to base |

`chara+0x3494` is set by `LuxBattleChara_ApplyHitReactionMove` from the
move bank slot's `+0x5C` field — so it's authored per-move.

### DefenseMode (`chara+0x1334`)

`chara+0x1334` is a per-tick "DefenseMode" classifier output, recomputed
every simulation tick by `LuxBattleChara_EvaluateDefenseMode @
0x14034EA60` and stashed straight into `chara+0x1334` from
`TickCharaMainSimulation`. Values:

| Value | Meaning |
|---:|---|
| 1 | normal defense (no special condition) |
| 2 | opp not attacking |
| 3 | self recovering, opp attacking, move type ≠ 1 |
| 4 | self backing away (`+0x16D5` held), opp attacking |
| 6 | counter window available (bank slot has counter-hit followup, no guard break) |
| 8 | hit recovery (`+0x1718`/`+0x1719` set, in mid-recovery move state 6..8) |
| 10 | counter super-armor / specific stance ID |
| 11 | full counter (`+0x170B` set) |
| 13 | special mode (`+0x171A` set) |

**`chara+0x132C` is a SAMPLE of this value, taken in
`LuxBattleChara_ProcessHit @ 0x140342780`** when a hit lands —
"the DefenseMode the chara was in when last hit". `TickCharaMainSimulation`
resets it back to `1` each tick whenever the chara is **not in
hitstun, or is in blockstun** (`+0x16DB == 0 || +0x16DC != 0`), so it
retains a non-trivial value only during pure hitstun.

The `+0x132C > 1` test in `UpdateGuardStanceFlags` therefore means "the
chara was in a special defensive posture (counter window / super armor /
backing / hit recovery / etc.) when last hit, and is still in the
hit-recovery move now". When that holds, free stance-change via raw
input is denied unless the move explicitly opts in via
`+0x3494 bit 2`. Effect on play:

- **Normal blockstun release** → `+0x132C == 1` (the per-tick reset
  fires during blockstun), so ducking/un-ducking mid-block is
  unrestricted. This is what enables the duck-under-on-blockstun-release
  trick.
- **Hit-recovery from a special-state hit** → `+0x132C` retains the
  fancy value, so the chara cannot free-flip stance during the recovery
  unless the recovery move is authored to allow it.

### Hit-resolution use

Both `LuxBattle_ResolveAttackVsHurtboxMask22 @ 0x14033C100` and
`LuxMoveVM_EvaluateMoveTransition @ 0x14033E140` call the resolver above
and use the returned byte as the "stance" axis of the (stance, attack
level) match table:

| Defender stance | Attack flag (cell+0x32) | Outcome |
|---|---|---|
| 0 (standing) | bit 7 (0x80) HighAttack | Hit normally; not blocked unless guarding HIGH |
| 0 (standing) | bit 3 (0x08) LowAttack | Cannot block low while standing — HITS |
| 0 (standing) | bit 4 (0x10) MidAttack | Blocks if guarding (any stance) |
| 1 (crouching) | bit 7 (0x80) HighAttack | DUCKS UNDER — hurtbox geometry already excluded the hit upstream; if it reached this gate, returns "no transition" |
| 1 (crouching) | bit 3 (0x08) LowAttack | Blocks if guarding |
| 1 (crouching) | bit 4 (0x10) MidAttack | Blocks if guarding |

The "duck under high" works on **two** levels:
1. **Geometry**: the chara's hurtbox shapes shrink when crouched, so the
   high attack's KHit shape simply does not overlap. No bit gets OR'd
   into `PerHurtboxBitmask`, and the classifier never sees the attack.
2. **Resolver fallback**: even if geometry passes (e.g. a tracking
   high), `EvaluateMoveTransition` returns `0` (no transition) when the
   stance + attack-level combination has no legal block / hit outcome.

### Throw exception

The throw pre-scan in the classifier uses the resolved stance byte:

```
if ((attackerMask & 0x0080000080000000) != 0       // throw bits set
    && (isBlockingActive == 0 || blockDirMatches != 0)) {
  // throw connects
}
```

A **stand-block** of a high throw escapes it
(`isBlockingActive=1 && blockDirMatches=0`). A **crouch-block**
(`blockDirMatches=1`) does not — high throws connect against
crouching defenders.

### Why ducking mid-blockstun-release works

The classic SC tech of "duck under a high while in blockstun":

1. Defender is in blockstun from the previous mid attack.
   `chara+0x16DC = 1`, `chara+0x16D2 = 0` (standing block).
2. Resolver locks to base byte (`+0x16D2 = 0`) for any cell with bit 0
   or 1 set in `AttackFlags` — so within blockstun, the stance can't
   change.
3. Blockstun expires (`+0x16DC = 0`), but the chara is still mid-recovery.
4. Player presses Down + Guard. `UpdateGuardStanceFlags` sees:
   - `+0x16DC == 0` ✓
   - `+0x132C` not blocking
   - guard input held (`+0x2150 bit 3`)
   - sit input held (`+0x2164 bit 2`)
   → writes `chara+0x16FC = 1` and `+0x1701 = 1` (alt locked).
5. The next-attack hit-resolution reads `+0x16FC = 1` (crouched),
   ducks under any high attack that lands during this 1-frame window.
6. Two ticks later the player commits to a crouching guard MOVE, the
   move's `qwInputSetMask` writes `+0x16D2 = 1` (base now crouched),
   and the alt mechanism is no longer needed.

The window is exactly **one tick**, between blockstun ending and the
move-VM committing a stance-change move. During that window the alt
is the only thing keeping the chara in the "crouching" stance — which
is why a high attack that would have hit during blockstun gets dodged
on the release frame.

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
`Lux_KHitChk_DeserializeLinkedList` three times, once per stream type, into the three
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

```
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
matrix multiply — the rotation rows of `M` have extracted-scale ≈ 1.0 and do not include
the cm→UE conversion.

## Frame-accurate damage gate

The mask in `**(chara+0x44058)` is set **once per move-slot** (by `LuxMoveVM_SetActiveMoveSlot
@ 0x140300C70`) and stays constant across that slot's startup / active / recovery frames. For
a per-sub-frame "is this slot dealing damage RIGHT NOW" answer, mirror the lookup
`TickHitResolutionAndBodyCollision` performs each tick:

```
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

- **Projectile attacks** (Cervantes's pistol, etc.). Whether they have entries in the
  attack list with a ranged-indicator kind tag, or use a parallel path, is open.
- **Per-character KindTag dictionaries.** Tags ≥18 and per-style overrides are not catalogued.
- **Cross-reference with the trace system.** The visual `FLuxCapsule` system and the
  KHit `KHitArea` subclass both encode bone-pair endpoints. Whether any move authoring
  tool emits both representations from a single source is not confirmed. See
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
| `LuxMoveVM_TransitionToMove` | `0x2FE350` | Move-transition writer; sets per-lane state and `+0x44060` non-attack descriptor. |
| `LuxMoveVM_SetActiveMoveSlot` | `0x300C70` | Sets the per-move-slot mask at `**(chara+0x44058)`. |
| `LuxMoveVM_SetHurtboxSlotsActiveMask` | `0x308D70` | Hurtbox-list `+0x14` writer. Called by VM opcode `0x13AC`; iterates `chara+0x444B8` and toggles each node's `+0x14` against an authored slot mask. |
| `LuxMoveVM_AdvanceLaneFrameStep` | `0x2FFEB0` | Per-tick lane frame-step advance. |
| `LuxMoveVM_CommitMoveEnd` | `0x2FCFB0` | Move-end finaliser. |
| `LuxBattleChara_SetStartPosition` | `0x301E60` | Canonical chara-teleport call. Writes `+0xA0` / `+0xC0` / `+0x2090` triples. |
| `LuxBattle_PositionCharasSymmetrically` | `0x302670` | Round-start pose; writes the side-flag at `+0x23C`. |
| `LuxEffectCamera_EvaluateAndTriggerSlowMotion` | `0x31D8F0` | Slow-motion gate; reads from active lane cursor. |

### Throw connection / yarare dispatch

| Symbol | RVA / Address | Description |
|--------|---------------|-------------|
| `LuxMoveVM_TickPickAndDispatchReaction` | `0x2DEF50` | Per-tick reaction picker. **Contains the height-bucket gate** that drops small-vs-tall throws (the dispatch-allow bitset at `~0x1402DFBC0`). |
| `LuxMoveVM_GetCharaEffectiveHeight` | `0x309470` | Computes per-chara effective height. Default branch: `head.Y - statureTable[bKindByte] - foot.Y`. |
| `LuxBattle_DispatchYarareReaction` | (see Ghidra) | Actual reaction commit — gated by `TickPickAndDispatchReaction`'s allow set. |
| `LuxBattle_CheckYarareReactionGate` | `0x362E70` | Per-yarare-table-entry gate test (consults `EvaluateAttackRange` for case 0x72). |
| `LuxMoveVM_EvaluateAttackRange` | `0x35F670` | Per-cell reach gate consulting `cell+0x62..+0x66` range bounds and `cell+0x38` reach ceiling. |
| `g_LuxBattle_CharaKindStatureTable` | `0x14470D200` | Per-charaKind stature offset table (stride `0xF0`, indexed by `chara+0x23C`). The "size attribute" that distinguishes tall and short charas. |

Throw-catch yarareIds NOT in the unconditional allow set (`{0x1F, 0x21,
0x20, 0x2C-0x2D, 0x2E-0x31, 0x3B, 0x28-0x2B@intensity>1, 0xE-0x10}`)
require the defender's effective-height bucket to be `< 5` for the
reaction to dispatch. When the defender is the tallest chara in the
cast, `iVar7 >= 5` and the throw is silently dropped.

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
