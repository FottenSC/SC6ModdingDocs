# On-disk battle data files

If you have unpacked SC6's pak and dumped the `/Game/Battle/` tree to disk,
the per-character data lives in `dump/Battle/{hdr,mot,cpu,hit,AssetPaths}/`.
Each file family is **one-to-one with an in-memory engine struct** that is
already documented elsewhere; this page just maps file → struct.

## File map per character

| Path | Style id | Engine struct | Documented in |
|------|----------|---------------|---------------|
| `hdr/hdr<XXX>.khd` | `XXX` | [`FLuxMoveBank`](structures.md#fluxmovebank-48-bytes) | move bank — full reference below |
| `mot/chr<XXX>.mot` | `XXX` | offset-table of HgMotion frame data | [Move System / motion](move-system.md) |
| `cpu/cpuai<XXX>.dtp` | `XXX` | CPU personality table — 9 sections, always | [AI/CPU System](ai-cpu-system.md) |
| `hit/atkhit<XXX>.dat` | `XXX` | i16-tagged `KHitBase*` stream — attacker side | [Hitbox System](hitbox-system.md) |
| `hit/bodyhit<XXX>.dat` | `XXX` | i16-tagged `KHitBase*` stream — body / pushbox | [Hitbox System](hitbox-system.md) |
| `hit/yararehit<XXX>.dat` | `XXX` | i16-tagged `KHitBase*` stream — reaction | [Reaction System](reaction-system.md) |
| `AssetPaths/CP_<XXX>.uasset` | `XXX` | UE4 wrapper pointing at the above by name | — |

Three pseudo-style ids exist outside the normal `001..066` range:

- `000` — only ships `chr000.mot` (shared motion).
- `0FF` — only ships `chr0FF.mot` (783 motions, ~0% empty — "common motion").
- `013` — only ships `cpuai013.dtp` (AI placeholder slot).

## `.khd` = on-disk `FLuxMoveBank`

The `.khd` file IS the engine's `FLuxMoveBank` (a 48-byte header, located at
`chara+0x455C0` once loaded). On disk:

| Offset | Field | Value |
|-------:|-------|-------|
| `+0x00` | magic | ASCII `"KH11"` (`0x31314B48` LE) |
| `+0x10` | `dwAttackCellArrayOffset` | start of Section A (attack cells) |
| `+0x14` | `dwNonAttackDescTableOffset` | start of Section B |
| `+0x18` | `dwEventRecordTableOffset` | start of Section C (event records) |

After that header, the file is a contiguous blob of three sub-arrays.
Full field map: [`FLuxMoveBank`](structures.md#fluxmovebank-48-bytes).

### Section A — `LuxBattleAttackCell[]` (stride `0x70`)

**THE attack-property array.** Every authored hitbox-cell of every move
lives here: damage, frame windows, blockstun, hitstun, reaction IDs,
ranges. Full reference: [`FLuxMoveBankCell`](structures.md#fluxmovebankcell-112-bytes)
(same on-disk layout, different historical name).

A cell with `wHitboxGroupBitfield == 0xFFFF` (`+0x5E`) is a cleared
sentinel — the engine treats that slot as inactive. Roughly 2-8 such sentinels
appear per character.

Empirical counts across all 24 shipped characters:

- 150-452 cells per `.khd` (avg ~290).
- Damage range typically 0..130; Geralt is the lowest (0..40), Xianghua
  the highest (0..130).
- Per-cell attack class is **not** reliably decodable from `wAttackFlags`:
  the block-level bits are blockability flags, set near-uniformly across all
  classes (see [hitbox-system.md: Attack flags](hitbox-system.md#attack-flags)).
  A move's authoritative per-hit class is `DA_MoveListTable.AttributeTag` —
  see [Character Data](character-data.md#move-list-text-and-metadata).

### Section B — `LuxBattleNonAttackMoveDescr[]` (stride `6`)

A small per-character table (9-61 rows) of non-attack descriptors. Used by
non-damaging supers, GI, parry, and stance-transition records, addressed as
`bank + bank[+0x14] + (subIdx & ~0x10000) * 6` (see
[hitbox-system.md / Non-attack ALT-path](hitbox-system.md#non-attack-alt-path)).

```c
struct LuxBattleNonAttackMoveDescr {  // 6 bytes
    int16 nSDamageMultiplier;   // +0x00 — observed 10..65
    int16 nSPassthroughTag;     // +0x02 — usually 0xFFFD (default reaction)
    int16 nSDuration60ths;      // +0x04 — duration in 60ths of a second
};
```

### Section C — event records + per-slot stack-VM bytecode

`wEventRecordCount` at header `+0x0E`, base at header `+0x18`, stride `0x30`.

The first 3-94 records of Section C form a **typed-header-record
prefix**: each is `[u8 typeTag][u8 subtype][u16 0][u32 index][24 bytes
payload]`, with `typeTag` drawn from the FLuxMoveDataEntry enum
(`0x00..0x1E` plus the `0xD6` count-marker).

**The rest of Section C is per-slot stack-VM bytecode**, reachable via
each slot's `dwBytecodeOffset_38`. See the [Slot table](#slot-table-move-state-records)
section below.

## Slot table (move-state records)

Right after the 48-byte `FLuxMoveBank` header, at bank+0x30, sits a contiguous
array of **`FLuxMoveBankSlotView` records** (72 bytes / 0x48 each). Each slot
is one move-state (idle, attack startup, attack active, transition, etc.).

Total slot count = `sum(bucket.Count)` over all 4 buckets at bank+0x1C..+0x2B.
Mitsurugi has 2899 slots; the per-character count scales with moveset
complexity.

| Offset | Type | Field | Notes |
|-------:|------|-------|-------|
| +0x00 | u16 | `wAnimationIndex_00` | HgMotion motion id |
| +0x02 | u16 | `wMotionPlaybackParam_02` | per-slot motion init param |
| +0x04 | i16 | `nField_04` | motion arg |
| +0x06 | u16 | `wMotionFlags_06` | motion flags |
| +0x10 | u32 | `dwSubTableOffset_10` | per-slot sub-table A offset (-1 = none) |
| +0x14 | u32 | `dwSubTableOffset_14` | sub-table B offset |
| +0x1C | u32 | `dwAltBytecodeOffset_1C` | alt-path bytecode (typically unused in 2.31) |
| +0x20 | u64 | `qwInputMask_20` | input mask -> `lane+0x448` at TransitionToMove |
| +0x28 | u64 | `qwInputMask_28` | input mask -> `lane+0x450` |
| +0x30 | f32 | `flAnimLength_30` | animation length (60Hz frames) |
| +0x34 | i16 | `nAnimLengthFlag_34` | -2 = use computed length from playback speed |
| +0x36 | i16 | `nHitWindowStart_36` | hit-window start frame |
| +0x38 | u32 | `dwBytecodeOffset_38` | **bank-relative byte offset to stack-VM bytecode** — the main per-slot script. Engine resolves as `(byte*)bank + dwBytecodeOffset_38`; `-1` means "no bytecode" |
| +0x3C | i16[6] | `nCellBoneIndexPerVariant` | variant index -> AttackCell index (-1 = no attack) |

## Stack-VM bytecode (per slot)

Each slot's `dwBytecodeOffset_38` points at a byte-packed bytecode stream
interpreted by `LuxMoveVM_ExecuteBytecode @ 0x1402E5A30`. **The stream is NOT
u32-aligned**; instructions are 1 or 3 bytes each. Each opcode byte holds a
low-7-bit opcode plus a `0x80` push-flag (push ACC afterward).

| Opcode | Size | Mnemonic | Notes |
|-------:|-----:|----------|-------|
| 0x00 | 1 | NOP | |
| 0x01 | 3 | `PUSH_IMM <BE u16>` | sets `dwLastImmediate = u16`; pushes to stack only if u16 != 0 (PC always +3) |
| 0x02 | 1 | `RET2` | return |
| 0x03/0x04 | 3 | `SET_ACC_U16 <BE u16>` | ACC = imm (no push) |
| 0x05/0x06 | 1 | `RET` | pop top, return value |
| 0x07 | 1 | `RETBRK` | return + set interrupt flag |
| 0x08 | 1 | `BRK` | set interrupt flag |
| 0x09/0x0B | 3 | `SET_ACC_U16 <BE u16>` | bare ACC set (+0x80 = also push) |
| 0x0A | 3 | `LOAD_VAR <BE u16 varid>` | ACC = var |
| 0x0C..0x18 | 1 | ADD/SUB/MUL/DIV/MOD/NEG/POSTINC/POSTDEC/AND/OR/LNOT/SHL/SAR | arithmetic |
| 0x19 | 3 | `STORE_VAR <varid>` | var = pop |
| 0x1A..0x1E | 3 | `ADD_VAR / SUB_VAR / MUL_VAR / DIV_VAR / MOD_VAR <varid>` | op-assign |
| 0x1F..0x24 | 1 | EQ/NE/LT/LE/GT/GE | comparison |
| 0x25 | 3 | `CALLCOND <u8 fnIdx> <u8 argc>` | dispatch table call |
| 0x26/0x27 | 1 | PUSH_ACC / POP_ACC | |
| 0x28/0x29 | 3 | `JNZ / JZ <BE u16 dest>` | pop top, jump if (non)zero. `dest` is an **absolute byte offset within this slot's bytecode buffer** (i.e., `dwPC = dest` directly, NOT a delta) |
| 0x2A | 3 | `JMP <BE u16 dest>` | unconditional jump. `dest` is an **absolute byte offset within this slot's bytecode buffer** (`dwPC = dest`, NOT a delta) |
| 0x2B..0x3C | 1 | NOP | reserved / unused |

`varid` addressing:

```
varid < 0xF0   -> GLOBAL[varid]   (per-character 240-entry i16 array
                                   at &g_LuxBattle_CharaKindStatureTable
                                                  + chara[+0x23C] * 0xF0)
0xF0..0xFF     -> LOCAL[varid-F0] (16 i16 args copied from caller)
0x100+         -> STACK[varid-100] (stack ring; persists across CALLCONDs)
```

### CALLCOND dispatch table (`g_LuxMoveVM_OpcodeIfDispatchTable @ 0x143E83A90`)

38 entries × 8-byte function pointers:

| Idx | Function | Notes |
|----:|----------|-------|
| 0x00, 0x01 | `LuxMoveVM_EvaluateIfOpcode` | IF-predicate evaluator (most common call) |
| 0x02, 0x03 | `LuxMoveVM_DispatchEffectOp` | Effect-system opcode dispatcher (movement / VFX / audio) |
| 0x04, 0x19 | `RegisterEffectOpDedup` | |
| 0x05..0x08 | `TransitionAuthor_05..08` | **Writes `lane[+0x5A] = MoveID`** — main "transition to next move" path |
| 0x09 | `LatchCharaStateFlag` | |
| 0x0A | `OpcodeIf_0A` | |
| 0x0B, 0x12, 0x13, 0x24 | `NullStub` | no-op |
| 0x0C | `OpcodeIf_0C` | |
| 0x0D | `ExecuteBankSlotScript` | **NESTED CALL** into another slot's bytecode |
| 0x0E..0x11 | `OpcodeIf_0E..11` | |
| 0x14 | `OpcodeIf_14` | |
| 0x15 | `ScheduleTransitionScript` | writes `lane[+0xB4]` (deferred transition) |
| 0x16 | `OpcodeIf_16` | drain `lane[+0xB4]` |
| 0x17/0x18 | `OpcodeIf_17/18` | save/restore staged transition |
| 0x1A | `OpcodeIf_1A` | clear `lane[+0xB4]` |
| 0x1B..0x1E (+ aliases 0x1F..0x22) | `OpcodeIf_1B..1E` | |
| 0x23 | `GetRandWeightedIndex` | weighted random index |
| 0x25 | `EvaluateIfOpcodeWithHeader` | header-aware IF |

### Empirical cross-slot stats (Mitsurugi, 2899 slots)

Average bytecode length: 73 instructions (range 3..1547 across slots).
Aggregate CALLCOND distribution:

```
ExecuteBankSlotScript      13,936   (move sub-graph navigation)
EvaluateIfOpcode            9,580   (predicates)
DispatchEffectOp            8,410   (effect-system ops)
EvaluateIfOpcodeWithHeader  6,871   (header IF)
OpcodeIf_14                   948
TransitionAuthor_07           687   (transition to next move)
```

The bytecode is the **canonical move-state graph**: every move-state-machine
transition fires through a `TransitionAuthor_*` CALLCOND in some slot's
script. A complete tool would walk the bytecode to reconstruct the
per-character move-transition DAG.

## `.mot` motion files

```text
+0x00  u32        nMotionCount               (628..2046 motions / char)
+0x04  u32        reserved                   (zero in shipped banks)
+0x08  u32[N]     motion_offsets             (absolute file offsets)
@offset[i]        HgMotion frame data        (private layout)
```

There is no guaranteed `N+1` end sentinel. Adjacent motion ids sharing the same
offset are aliases and resolve to the same payload in native code. An offline
tool can bound a payload by the next **greater** distinct offset; EOF is only an
upper bound for the final distinct payload because the native decoder uses the
clip's internal regions rather than an outer section size.

The bank split, compressed-frame decoder, Blender interchange contract, and
pose-fidelity limits are covered by
[Export SC6 `.mot` animations to Blender](../cookbook/export-mot-to-blender.md).

## `.dtp` CPU AI files

Same `nCount + u32[N+1] offsets` container as `.mot`. **Every shipped
file has exactly 9 sections**, several of them at fixed sizes:

| Section | Size (all chars) | Role |
|--------:|------------------|------|
| 0 | 27184-73424 (varies) | Decision-tree data (u16 weight/value pairs) |
| 1 | 4400-10064 (varies) | Personality custom table — u16 slot count at `+0x08`, per-slot 18-byte rows |
| 2 | **always 2320** | One weight-slot block |
| 4 | 83200 or 89600 | Big lookup table (only 2 distinct sizes across all chars) |
| 5 | **always 34880** | 15 × 2320-byte weight blocks (`u32 count=15` + offset table + entries) |
| 6 | **always 0** | Alternate weights (patched in at runtime) |
| 7 | **always 1488**, starts with `"PSNL"` | Personality vtable trigger |
| 8 | 2192-5024 (varies) | Per-character override / scratch |

Runtime loader: [`LuxBattle_InitCpuPersonalityData @ 0x140364950`](ai-cpu-system.md).

## `.dat` hit-volume files (atkhit / bodyhit / yararehit)

Each uses the same **i16-tagged stream format** the runtime walks via
[`Lux_KHitChk_DeserializeLinkedList @ 0x14030C940`](hitbox-system.md):

```text
+0x00  i16   tag         (0 = Sphere, 1 = Area, 2 = FixArea, <0 = end)
+0x02  u16   slot        (defender bone slot 0..63; PerAttackerBit = 1 << (slot & 0x3F))
+0x04  u32   node_flags  (authored; copied to in-memory KHit+0x10)
... variant tail ...
```

| Tag | Stride | Tail |
|----:|-------:|------|
| 0 (Sphere)  | `0x20` | `float[4]` (x, y, z, radius), `u32 id`, `u32 reserved` |
| 1 (Area)    | `0x28` | swept capsule — see [hitbox-system.md / KHit node layout](hitbox-system.md#khit-node-layout) |
| 2 (FixArea) | `0x30` | 3-point OBB — same reference |

Stream ends on the first `tag < 0` (typical sentinel: `0xFFFF` = -1).
Files always end with a 2-byte `FF FF` trailer.

Cross-character invariants:

- `bodyhit*.dat` — always exactly **17 sphere records**, 0 area, 0 fix.
- `yararehit*.dat` — always **18-19 sphere + exactly 1 area**, 0 fix.
- `atkhit*.dat` — varies, 30-72 records, sphere + area mix.

## Name-string obfuscation

Any string referenced from inside an `FLuxMoveBank` buffer is descrambled
in-place on first load by subtracting `0x40` from each byte up to the NUL
terminator (`*p -= 0x40`). The `+0x08 bDecoded` byte in the buffer guards
against a second descramble pass. Tools that read `.khd` files directly must
apply this transform when reading any embedded name.

## Editing safety

`.khd` / `.mot` / `.dtp` / `.dat` files are pak-loaded, so disk edits need
a pak-injection workflow. Runtime patching via native hooks is
simpler: the loaded `FLuxMoveBank` sits at `chara+0x455C0`, and the
attack-cell array can be edited in place between matches without
invalidating the engine's cached pointers (each cell pointer is set
once per move by [`LuxMoveVM_TransitionToMove`](move-system.md)).

For pure stat tweaks, `LuxBattleAttackCell::nBaseDamage`,
`nBlockstunFrames`, and `nHitstun*` are independent fields with no
cross-checks against header-level data — a single u16 is safe to edit.

`.vtb` and `.lpd` files (visual-tag and pose-delta data) are loaded through
chara-init params from elsewhere in the pak. Their headers — magic `"vtb\0"`
version `0x1002`, magic `"lpb\0"` version `0x201` — are handled in
[`LuxMoveVM_LoadVTBFile @ 0x14038EFA0`](move-system.md) and
[`LuxBattle_BindLPDMotionData @ 0x1402F7670`](move-system.md).
