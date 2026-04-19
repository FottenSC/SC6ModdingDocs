# Move System (command-script bytecode VM)

What the "move data" for a character actually *is* inside SoulcaliburVI.exe — and
what pieces you need to join together to export a full move-list (inputs / damage
/ frames / hit / counter-hit / stance) to a website.

TL;DR:

- SC6's move data is **not a flat frame-data table** like Tekken's `moveGen`
  export. It's a **per-move command-script bytecode** (a little VM program) plus
  two big per-character attribute tables that the opcodes read from.
- The UE4 reflection side (`FLuxBattleMoveListTableRow`) carries **text IDs
  only** — the strings a Training-Mode move-list panel displays. No frame data.
- To reconstruct "move X is i13 mid for 20 damage, +2 on hit / +6 on CH", you
  have to (a) load the bytecode for move X, (b) decode the ATK payload opcode,
  (c) cross-reference the resolved hit-reaction ("yarare") id against the
  character's attribute table. The game's own training-mode HUD does steps (b)
  and (c) live via the same VM documented here.

---

## The two data-layer split

| Layer | What it holds | Lives in | How to extract |
|---|---|---|---|
| **Display layer** (UE4 DataTable) | Per-move TextIDs: `CommandTextID`, `NameTextID`, `ReadingTextID`, `NoteTextID`, `MainMovesTextID`, `RethalHitTextID`, `AttributeTag`, `EffectTag` | `/Game/Style/<StyleId>/DA_MoveListTable_<StyleId>.uasset` | unpack pak → parse DataTable with `FLuxBattleMoveListTableRow` schema |
| **Gameplay layer** (native command-script) | Per-move bytecode: inputs, ATB/ATK payload, IF/goto/calc/RAND opcodes, on-hit/CH yarare ids, stance toggles | Per-style binary blob loaded into the battle manager's move provider; driven by the on-exe VM at `0x140365900` | must be **parsed** via the opcode dispatch table below; resolved yarare ids look up into `g_LuxCharaAttrTable_*` |

The UI docs for `DA_MoveListTable_*` already show up in
[Character Data](character-data.md). This page is the gameplay-layer side.

---

## Display-layer struct

### `FLuxBattleMoveListTableRow` (0x88 bytes)

Reflected via `Z_Construct_UScriptStruct_FLuxBattleMoveListTableRow @ 0x14094a910`.

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00 | `FTableRowBase` | (base) | inherited UE4 data-table row header |
| +0x08 | `FString` | CommandTextID | input notation (`6B`, `AGA`, etc.) |
| +0x18 | `FString` | NameTextID | localised move name |
| +0x28 | `FString` | ReadingTextID | localised reading/phonetic |
| +0x38 | `FString` | NoteTextID | tooltip / frame-data blurb |
| +0x48 | `FString` | MainMovesTextID | category tag |
| +0x58 | `FString` | RethalHitTextID | **Lethal-Hit** text id (typo in ROM: "Rethal") |
| +0x68 | `FString` | AttributeTag | high/mid/low/throw attribute tag id |
| +0x78 | `FString` | EffectTag | GuardImpact / Unblockable / BreakAttack / SpecialStance / LethalHit / SoulCharge / … |

The `AttributeTag` and `EffectTag` strings are the join keys into
`ELuxAttackTouchLevel` and `ELuxBattleMoveEffectType` respectively. They are
human tags — not bit-packed — so the display layer is *descriptive*, not
authoritative.

---

## Gameplay-layer runtime

### Actor class: `ALuxBattleMoveCommandPlayer`

Registered by `Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`.

Reflected UFunctions (all wrap `*_Impl` methods):

| UFunction | `_Impl` | Purpose |
|---|---|---|
| `GetMovePlayParam(MoveListId, Level, Idx, out)` | `@ 0x1404235C0` | fetch one `FLuxBattleMovePlayParam` from the 3-level `table[MoveListId].levels[Level].entries[Idx]` array |
| `IsPlaying(SideFilter)` | `@ 0x140426610` | read player-side at `this+0x3C0`: 0=none, 1=P1, 2=P2 |
| `PlayMove` | — | queue a move by `MoveListId` |
| `PlayMoveDirect` | — | queue a move by raw `FMoveDef*` |
| `StopMove` | — | cancel current queued move |

Reflected fields on the class (`+0x390 .. +0x3D0`):

| Offset | Type | Name |
|-------:|------|------|
| +0x390 | `FStructProperty` | PlayData |
| +0x3A0 | `FEnumProperty` (u32) | Request |
| +0x3A8 | `FStructProperty` | RequestInfo |
| +0x3C0 | `FEnumProperty` (u32) | PlayState |
| +0x3C8 | `FStructProperty` | PlayStateInfo |

On top of the reflected fields, the VM uses **non-reflected** scratch state at
higher offsets (documented inline on `LuxBattleMoveCommandPlayer_DebugDumpCommand`
at `0x140365900` — copy-paste reproduced below).

### Runtime payload: `FLuxBattleMovePlayParam` (~0x10 bytes)

Small struct (only 2 × 8-byte slots, zero-initialised by
`FLuxBattleMovePlayParam_DefaultCtor @ 0x140406F40`). It's the "handle" copied
into a UFunction out-param so blueprint can reference a queued move without
owning its backing buffer.

---

## Command-script format

Source of truth: `LuxBattleMoveCommandPlayer_DebugDumpCommand @ 0x140365900`.
That function is a **disassembler** — it walks one opcode at a time and writes a
human-readable line to `this+0x2A28`. Every opcode and every field we know
about is visible in that function's string literals.

### Opcode dispatch (upper 16 bits of each uint32 cell)

| `op >> 16` | Mnemonic | Cells | Payload |
|---|---|---|---|
| `0x1xxxx` | `BTN+TIME` | 2 | cell 0 = button mask, cell 1 = time (float reinterpret) |
| `0x40001` | `ATB` | variable | combo_id (low 16 of first cell); reads until next cell has `0x4xxxx` prefix; accumulates `yarare` id |
| `0x40002` | `ATK` | 5 | `op, power, range_raw, speed, direction_mask` |
| `0x40004` | `RESERVE_NOWAIT` | 1 | sets `this+0x2A10 = 1` |
| `0x40005` | `RESERVE_WAIT` | 1 | sets `this+0x2A10 = 0` |
| `0x50001` | `start!` | 1 | zero-inits the condition-flag ring at `chara+0x19F0..+0x1A64` |
| `0x50002` | (pad) | 1 | falls through to IF decode |
| `0x50003` | `goto` | 2 | cell 1 = jump delta added to cursor |
| `0x50004` | `calc` | 5 | `dst = a OP b OP c` (4 operand cells) |
| `0x50005` | flag-set | 1 | sets `this+0x2698 = 1` |
| `0x50006` | `RAND` | 3 | threshold, jump-delta |
| `0x50007` | `_REVERSE` | 1 | sets `this+0x269C = 1` |
| `0x50008` | `notif` / `IF` | 5 | `op, class (0x6xxxx), subject, value, delta` |
| `0x80000` | raw command no | 1 | `"command no = %08x"` then loop |
| other | `ERROR COMMAND!` | — | bail |

### ATK payload (the "attack data" every move has at least one of)

5 cells, high half of cell 0 = `0x40002`:

| Slot | Field | Stored at | Display format |
|---|---|---|---|
| 0 | (opcode) | — | `"ATK:"` |
| 1 | `power` | `this+0x26D8` | `"power=%x"` |
| 2 | `range_raw` | `this+0x26DC` | `"range=%7.3fm"` — `range_raw / g_LuxMoveVM_AtkRangeDivisor` (float at `0x143E8A504`) |
| 3 | `speed` | `this+0x26E0` | `"speed=%x"` |
| 4 | `direction_mask` | `this+0x26E4` | bits below |

`direction_mask` bit → mnemonic (the `"dir="` field the debug dumper emits):

| Bit | Char | Meaning |
|---:|---|---|
| 0x0001 | `0` | 8-way dir 0 (neutral) |
| 0x0002..0x0080 | `1`..`7` | 8-way dirs 1..7 |
| 0x0100 | `S` | Sit / crouch |
| 0x0200 | `U` | Up (jump) |
| 0x0400 | `M` | Mid |
| 0x0800 | `L` | Low |
| 0x1000 | `D` | Down |
| 0x2000 | `G` | Guard (+G sim-press) |

A single ATK cell is **one hitbox pulse**, not the whole move. A multi-hit
string is encoded as `ATK, timegap, ATK, timegap, …` (the BTN+TIME pair after an
ATK is its active-phase window). That's where frame data is hiding —
**startup/active/recovery is the sum of the `BTN+TIME` cells between ATKs**.

### BTN+TIME pair (the "hold this input for N frames" primitive)

First cell: `op_high = 0x1xxxx`. Low bits encode the button-mask. The bits map
to these mnemonics (`_W _1.._9 _A _B _K _G _C _NOGUARD`) — exact bit layout
visible in the `strncat_s` sequence inside the VM dumper.

Second cell: time value (reinterpreted as float; stored at `this+0x26B0`).

The unit is *game frames*, 1.0f = 1 frame. (Scaled by
`g_LuxMoveVM_UnitsPerInt @ 0x143E89FD4` where int comparisons happen in the IF
subject branch.)

### ATB (hit-reaction chain)

Format: `0x40001 <combo_id>` then a variable number of yarare-id cells that
belong to the same ATB. The ATB terminates when the next cell has a `0x4xxxx`
upper half that isn't `0x40001`.

Each yarare cell is an **id** into the per-character yarare table. The yarare
id tells the engine *which hit-reaction animation* the opponent plays — and that
is exactly what determines **on-hit** and **on-counter-hit** frame advantage.
In SC6, frame advantage isn't stored on the attacker's move — it's stored on
the *defender's hit-reaction*, so `ATK.yarare_onhit` → `Yarare[id].Recovery -
Attacker.Recovery`. For a website, either export the computed delta per yarare
id or expose both raw numbers.

### IF / notif

5 cells: `op, class, subject, value, delta`. `class` is one of
`0x60001..0x60006` (six test families). `subject` is the specific register, and
the conditional jumps to `cursor += delta` when the test passes.

`subject` values above `0x60028` directly index a per-character table:

- `[subject - 0x60028]` in `0x60028..0x60037` (16 entries, stride 2 bytes) →
  `g_LuxCharaAttrTable_Byte_0x181cStride @ 0x14470FCD8`
- `0x60054..` → a second larger table at
  `g_LuxCharaAttrTable_Int_0x3038Stride @ 0x1447123BC`

Both tables are row-major, indexed by **`chara+0x23C` (character kind byte)**.
Per-row size is `0x181C` and `0x3038` bytes respectively. With ≈44 styles this
puts each table in the ~270 KB / ~540 KB range — these are the *real*
per-character tuning tables.

### Condition-flag ring (on the chara, not the command player)

Each IF subject in `0x60007..0x60058` reads one `uint32`/`int32`/`float` slot
inside `chara+0x19F0 .. chara+0x1A64`. The full subject → chara-offset map is
in the plate comment on `0x140365900`. The ring is zeroed by the `start!`
opcode of every move, so these are **per-move transient flags** (e.g.
"opponent has been hit by this move's first attack", "we are in a stance").

### IF predicate families — the six test kinds

The `class` cell in an IF opcode selects one of six native predicate
functions. The first three are near-identical state-id lookups in
`g_LuxMoveStateTable @ 0x1440F4750`; the last three pull real game
state (range, geometry, move-class pair) from the chara and its
opponent.

| Class | Predicate | RVA | Shape |
|-------|-----------|-----|-------|
| A (family 0xF)  | `LuxMoveVM_CheckCharaStateEqualsU16` | `0x140364FC0` | `chara->MoveStateId == 0xF  && chara->+0x1982 == value` |
| B (family 0x7)  | `LuxMoveVM_CheckNotifFamilyB`        | `0x140365040` | same shape, different state-id |
| C (family 0x1C) | `LuxMoveVM_CheckNotifFamilyC`        | `0x1403650C0` | same shape, different state-id |
| D (range)       | `LuxMoveVM_CheckRangeOrDistance`     | `0x140365140` | terrain/reach sample `param` units along the opponent direction |
| E (angle/geom)  | `LuxMoveVM_CheckAngleOrGeometry`     | `0x1403652E0` | range + angle rotation + terrain-type filter |
| F (class-name)  | `LuxMoveVM_CompareMoveClassName`     | `0x140394E30` | reads move-class pair vs one of 18 symbolic tokens |

All three state predicates look up their state id in `g_LuxMoveStateTable`
(a fixed 0x29-entry table, stride 0x14 bytes per row = 5 x uint32) and
match the chara's own `MoveStateId` at `chara+0x2B4A4` against the row's
key field.

### Move-class pair descriptor (IF class F)

`LuxMoveVM_BuildMoveClassPair @ 0x140394AC0` packs self's and opponent's
current moves into a 7-uint32 descriptor that subsequent IF-F predicates
compare against:

```
outPair[0]  self.MoveSubclass (chara+0x19FE)
outPair[1]  self.MoveClassB   (chara+0x6E)
outPair[2]  self.MoveClassA   (chara+0x6C) (low 16)
outPair[3]  self bucket       (0=kick?, 1=throw?, 2=special? by class range)
outPair[4]  (self.MoveFlags at chara+0x70 != 0) ? 1 : 0
outPair[5]  opp.MoveClassA    + opp bucket
outPair[6]  ClassifyMovePairKind(selfMoveClassA, oppMoveClassA)
```

`ClassifyMovePairKind @ 0x140394BB0` maps the (self, opp) MoveClass
pair to a small integer kind used for yarare/frame-data lookups —
e.g. `horizontal vs horizontal → 7`, `kick vs throw → 2`, various
`default → 3`. See the Ghidra plate comment on that function for the
full map.

### Opponent & self position access (runtime-verified chara offsets)

Reverse-engineering `LuxMoveVM_CheckRangeOrDistance` at `0x140365140`
confirmed several chara-class field locations that weren't previously
documented:

| Chara offset | Type | Purpose |
|-------:|------|---------|
| +0xA0 | `float` | `SelfPos.X` (world-space) |
| +0xA8 | `float` | `SelfPos.Z` (lateral world-space) |
| +0x6C  | `int16`  | `MoveClassA`    (5..12 — SC6 move category) |
| +0x6E  | `uint16` | `MoveClassB`    (subclass) |
| +0x70  | `int32`  | `MoveFlags`     (flag bits) |
| +0x23C | `uint8`  | `CharaKindByte` (row index into `g_LuxCharaAttrTable_*`) |
| +0x250 | `uint16` | `MoveSubclassAlt` (checked `==100` / `0x69` by IF-F) |
| +0x1982 | `uint16` | `CurrentNotifToken` (read by IF families A/B/C) |
| +0x19FE | `uint16` | `MoveSubclass` (read by `BuildMoveClassPair`) |
| +0x2B4A4 | `int32` | `MoveStateId` (key into `g_LuxMoveStateTable`) |
| +0x973E8 | `ALuxBattleChara*` | **Opponent** — direct pointer, NOT `chara+0x390` as an earlier pass of these docs claimed |

The **opponent pointer at `chara+0x973E8`** is the critical correction.
Earlier versions of this page and of `structures.md` described
`chara+0x390` as the opponent pointer (on the basis of Ghidra
annotations that turned out to be wrong for this build). Runtime
class-name introspection shows `chara+0x390` is actually
`WeaponMesh0` (a `USkeletalMeshComponent*`), and `LuxMoveVM_CheckRangeOrDistance`
dereferences `chara+0x973E8 → +0xA0/+0xA8` to read opponent
world-space position for range checks.

### Spatial acceleration chain (call graph underneath predicates D and E)

Predicates D (`CheckRangeOrDistance`) and E (`CheckAngleOrGeometry`) are the only
two families that actually touch the arena geometry. They both fan out through
the same helpers into a single shared acceleration grid:

```
LuxMoveVM_CheckRangeOrDistance                (0x140365140)
 └─> LuxBattle_TryTraceSegmentAgainstBounds   (0x140314BC0)
      └─> LuxBattle_TraceSegmentThroughFrameBoundsGrid (0x1403149E0)
           └─> LuxBattle_TestFrameBoundsCell  (0x1403916E0)
                └─> LuxBattle_IntersectSegmentWithTerrainTriangle (0x140390A90)

LuxMoveVM_CheckAngleOrGeometry                (0x1403652E0)
 ├─> LuxBattle_TryTraceSegmentAgainstBounds   (0x140314BC0)      — same reach test
 └─> LuxBattle_SampleTerrainAtWorldXZ         (0x1403915A0)
      └─> LuxBattle_SampleTerrainAtXZ_Impl    (0x140391350)
           ├─> LuxBattle_FindTerrainRowBucketByZ        (0x140390E90)
           ├─> LuxBattle_IsTerrainProbeInsideTriangleXZ (0x140391270)
           └─> LuxBattle_IsTerrainEntryActive           (0x140391270 path)
```

Key globals on the shared layer (see `structures.md` §
"Stage / frame spatial acceleration"):

- `g_LuxBattle_FrameContextUseB @ 0x14470DEDC` — byte flag; selects A vs B variants.
- `g_LuxBattle_FrameBoundsGridA @ 0x144844DD0` / `g_LuxBattle_FrameBoundsGridB @ 0x144845E80` —
  the two alternate 2D cell grids of triangle entries that the VM traces against.
- `g_LuxBattle_FrameTransformA @ 0x144844170` / `g_LuxBattle_FrameTransformB @ 0x144845220` —
  matched transform blocks read in lockstep with the bounds grid.
- `g_LuxBattle_TerrainProbeUp @ 0x1440FBC38` / `g_LuxBattle_TerrainProbeDown @ 0x1440F7688` —
  two 16-byte vec4 scratch slots. Primed by `SampleTerrainAtXZ_Impl` as vertical
  probes at ±100 units, reused by `IntersectSegmentWithTerrainTriangle` as
  edge-cross-product scratch for the point-in-triangle step. **NOT thread safe.**

The triangle entries the grid holds are **arena frame walls and floor tris**,
not character hitboxes. That's why these two predicates flag moves like "are you
close enough to the ring-out edge to use this ring-throw" or "is there a wall
behind the opponent for this wall-splat". They do **not** resolve move hit detection.

> If you're instrumenting the geometry chain, the cheapest single-detour point
> is `LuxBattle_TryTraceSegmentAgainstBounds` (0x140314BC0) — it's called by
> both predicates and its parameters are the fully-baked segment + filter tags.

---

## Stances

Stances are **not** a separate type — in SC6 they're just moves tagged with
`ELuxBattleMoveCategory::SpecialStance` and/or `ELuxBattleMoveEffectType::SpecialStance`,
whose command-script doesn't terminate after the animation. While the stance
move is queued, the command player keeps its condition-flag ring alive, and
follow-up inputs dispatch into *different* moves via the IF branches.

Concretely:

- The Training-Mode "move list" exposes a stance as a single row with
  `EffectTag = SpecialStance`.
- The *gameplay* layer encodes the stance as a move whose bytecode ends in a
  `goto -1` (loop) gated by IF tests on per-chara flag bits. Flag bits flipped
  by enter/exit moves are at `chara+0x19F0..+0x1A64`.
- Moves that exit a stance (e.g. `A` from Amy's stance) query those bits via
  IF `class 0x60001`, `subject 0x60016..0x6001c`, then `goto` into a different
  command region.

Any frontend wanting to render stance trees needs to walk IF-goto edges from
each stance's entry move — the "tree" is implicit in the bytecode.

---

## On-hit / on-counter-hit / on-block

Crucial point for a frame-data website: SC6 does **not** store
`{on_hit, on_ch, on_block}` as three integers on the move. It stores:

1. Per ATK cell: `(power, range, speed, dir_mask)`. `speed` is the attack's
   startup/active window.
2. Per ATB cell: a set of **yarare ids** — which reaction the opponent plays.
   These include separate ids for on-hit vs counter-hit vs low-parry etc.
3. In the character-attribute tables (`g_LuxCharaAttrTable_*`): the actual
   frame counts (stagger/hit-stun/block-stun) per yarare id.

To produce `+2 on hit / +6 on CH` you need to compute:

```
on_hit       = YarareTable[atb.yarare_onhit].opponent_stun
             - MoveRecovery(attacker_move)

on_counter   = YarareTable[atb.yarare_oncounter].opponent_stun
             - MoveRecovery(attacker_move)

on_block     = YarareTable[atb.yarare_onblock].opponent_stun
             - MoveRecovery(attacker_move)
```

`MoveRecovery` is the sum of BTN+TIME cells from the final ATK to the end of
the bytecode.

---

## Move-VM helper functions (labelled)

| Address | Name | Role |
|---|---|---|
| `0x140363C10` | `LuxMoveVM_DebugTextAppendF` | snprintf-style debug-line formatter used by the dumper |
| `0x140364FC0` | `LuxMoveVM_CheckCharaStateEqualsU16` | IF predicate: chara's `u16 @ +0x1982` equals value |
| `0x140365040` | `LuxMoveVM_CheckNotifFamilyB` | IF predicate family B (notif tokens 0x00, 0x20, 0x23, 0x25) |
| `0x1403650C0` | `LuxMoveVM_CheckNotifFamilyC` | IF predicate family C (tokens 0x8D..0x90) |
| `0x140365140` | `LuxMoveVM_CheckRangeOrDistance` | IF range/distance-to-opponent predicate |
| `0x1403652E0` | `LuxMoveVM_CheckAngleOrGeometry` | IF angle/geometry predicate |
| `0x140394AC0` | `LuxMoveVM_BuildMoveClassPair` | populates a 7×u32 output describing self vs opponent move-class (for `0x60055`) |
| `0x140394BB0` | `LuxMoveVM_ClassifyMovePairKind` | classifies a (self, opp) move-class pair into an integer kind |
| `0x140394E30` | `LuxMoveVM_CompareMoveClassName` | equality test on the pair built above |
| `0x140365900` | `LuxBattleMoveCommandPlayer_DebugDumpCommand` | the VM disassembler / single opcode decoder |

Tuning constants:

| Address | Name | Role |
|---|---|---|
| `0x143E8A504` | `g_LuxMoveVM_AtkRangeDivisor` | ATK range_raw → metres divisor |
| `0x143E89FD4` | `g_LuxMoveVM_UnitsPerInt` | int-to-float scale for IF threshold comparisons |
| `0x14470FCD8` | `g_LuxCharaAttrTable_Byte_0x181cStride` | char-attr byte table, row = chara kind, row-stride 0x181C |
| `0x1447123BC` | `g_LuxCharaAttrTable_Int_0x3038Stride` | char-attr int table, row-stride 0x3038 |

---

## Enums

### `ELuxBattleMoveCategory` (0..10)

`MainMoves`, `ReversalEdgeMoves`, `SoulGaugeMoves`, `HorizontalAttacks`,
`VerticalAttacks`, `Kicks`, `SimultaneousPressMoves`, `EightWayRunMoves`,
`Throws`, `SpecialStance`, `LethalHitMoves`.

### `ELuxBattleMoveEffectType` (0..10)

`Throw`, `UnblockableAttack`, `BreakAttack`, `GuardImpact`, `SpecialStance`,
`LethalHit`, `SoulCharge`, `SoulGaugeFull`, `SoulGaugeHalf`,
`SoulGaugeQuarter`, `ReversalEdge`.

### `ELuxAttackTouchLevel` (0..6)

`E_ATL_HIGH`, `E_ATL_MIDDLE`, `E_ATL_LOW`, `E_ATL_SMIDDLE`, `E_ATL_SLOW`,
`E_ATL_OTHER`, `E_ATL_NULL`.

### `ELuxBattleDamage` (0..4)

`EBD_Unknown`, `EBD_Slash`, `EBD_Blow`, `EBD_Throw`, `EBD_RingOut`.

### `FLuxAttackTouchParam` (0x20 bytes)

Emitted when a hit registers.

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `uint8` | PlayerIndex |
| +0x04 | `FVector2D` | Position |
| +0x10 | `uint8` | HitType |
| +0x14 | `uint8` | AttackType (`ELuxWeaponAttackType`) |
| +0x18 | `uint8` | Level (`ELuxAttackTouchLevel`) |
| +0x1C | `bool` | bCanDownHit |

### `FLuxDamageInfo` (0x14 bytes)

HUD/network hit-event struct.

| Offset | Type | Name |
|-------:|------|------|
| +0x00 | `uint8` | player_side (the side that took damage) |
| +0x04 | `uint8` | damage_side (the side that dealt it) |
| +0x08 | `int32` | damage (this hit) |
| +0x0C | `int32` | total_damage (cumulative) |
| +0x10 | `bool` | is_critical |
| +0x11 | `bool` | is_limited (combo-scaling cap reached) |

---

## Extraction strategy for a frame-data website

### Recommended path (fastest to get to a website)

1. **Dump the UE4 pak chunks**. Unreal 4.21-era cooked paks; use UnrealPak /
   FModel. The `DA_MoveListTable_<StyleId>.uasset` files give you the Training-
   Mode display text for every move (CommandTextID → localised move name →
   AttributeTag/EffectTag). That alone is enough to stand up a browsable
   move-list with categories.
2. **Dump the command-script blob**. It ships as either an additional uasset
   per style or a flat binary inside the battle-data pak (needs confirming —
   follow loader at `ALuxBattleManager_PlayMove_Impl @ 0x140429840` → provider
   fetch).
3. **Write a bytecode parser** that implements the opcode dispatch above. Emit
   one JSON blob per move with:
   - `inputs`: decoded from BTN+TIME cells
   - `atks`: list of `{power, range_m, speed, dir_mask}`
   - `atb_yarare_ids`: the ids that resolve on hit / CH / block
   - `stance_entry_flag_bits`: IF-subject bits in `0x60007..0x60058` that the
     move toggles
4. **Join** each yarare id against the per-chara attribute row in
   `g_LuxCharaAttrTable_Byte_0x181cStride`. That gives opponent stun frames —
   subtract own recovery to get `on_hit/on_ch/on_block`.

### Minimum viable v0 (display-only)

Just step 1 + localisation strings. This gets you a "move list per character"
site with no frame data. It's still useful (no one has a clean SC6 notation
reference online) and requires zero reverse-engineering beyond reading
`FLuxBattleMoveListTableRow`.

### Risk / anti-tamper

The move-list DataTables are **not** gated — they load at startup with no
signature check. Editing them on disk requires pak-injection but reading them
does not. The command-script blob loader has not been audited for checksums
yet; read-only export should be safe.

> Source trail: `LuxBattleMoveCommandPlayer_DebugDumpCommand @ 0x140365900`,
> `Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`,
> `Z_Construct_UScriptStruct_FLuxBattleMoveListTableRow @ 0x14094A910`,
> `Z_Construct_UScriptStruct_FLuxAttackTouchParam_RegisterProps @ 0x14098F950`,
> `Z_Construct_UScriptStruct_FLuxDamageInfo_RegisterProps @ 0x140A4A3B0`.
