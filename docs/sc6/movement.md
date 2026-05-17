# Movement System

What the SC6 binary actually contains for chara movement, with each claim
tied to a specific Ghidra address. All addresses are absolute (image base
`0x140000000`).

!!! warning "Earlier drafts retracted"
    Earlier versions of this page mixed binary-verified facts with
    general fighting-game knowledge. This rewrite includes only what has
    been read directly from Ghidra. Anything that could not be
    verified is flagged "**unverified**" rather than asserted.

## The per-tick chara update flow

`LuxBattle_TickCharaMainSimulation @ 0x14034da70` runs once per chara per
battle tick. The movement-relevant calls it makes, in order:

1. `LuxMoveVM_ExecuteOpStream(chara, 0)` — runs move bytecode for slot 0
2. `LuxMoveVM_ExecuteOpStream(chara, 1)` — slot 1
3. `LuxMoveVM_ExecuteOpStream(chara, 2)` — slot 2
4. `LuxBattleChara_UpdateProximityBlendWeight(chara)`
5. `LuxBattleChara_UpdateStanceCategory(chara)`
6. `LuxBattleChara_TickHitStateStateMachine(chara)` — hit-state slide decay
7. **`LuxBattleChara_IntegratePhysics_PerTick(chara)`** — integrates velocity into world position
8. `LuxBattleChara_EvaluateDefenseMode(chara)`
9. `LuxBattleChara_UpdateBlockStateStochastic` + `LuxBattleChara_TickDamageAndBehaviorLock`
10. `LuxBattle_TickCharaTerrainContactBlend(chara)`
11. `LuxBattleChara_FinalizeTickPoseAndState(chara)`

The position update is step 7. Steps 1-3 (the move VM) run **before**
the integrator, so any opcode that writes velocity has already executed by
the time integration happens.

## What `IntegratePhysics_PerTick` actually does

Decompiled directly from `0x140306bb0`:

**Inputs read from chara:**

| Offset | What |
|---|---|
| `+0x130` / `+0x138` | MoveVelocity X/Z (per-tick velocity) |
| `+0x140` / `+0x148` | "Ground" velocity X/Z (third additive term) |
| `+0x1f0` / `+0x1f8` | Pushback velocity X/Z (decayed by hit-state machine) |
| `+0x150` / `+0x158` | One-shot offset X/Z (added without time-scaling) |
| `+0x3490` | Float scalar that multiplies only the `+0x130/+0x138` term |
| `+0x16fb` | Damped-mode flag (selects alternate path) |
| `+0x198c` | Motion state code (0x12 = airborne uncapped) |
| `+0x44dc2` | Bone-anchor index (-1 disables bone anchor integration) |

**Outputs written to chara:**

| Offset | What |
|---|---|
| `+0xa0` / `+0xa8` | World XZ position (the sum is added in) |
| `+0xa4` | World Y position |
| `+0x1d0` / `+0x1d8` | "This frame's position delta" cache |

**Normal-path math** (when `chara+0x16fb == 0`):

```
delta_x = (chara+0x3490 * chara+0x130
           + chara+0x140
           + chara+0x1f0) * TimeDilation
          + chara+0x150
chara+0xa0 += delta_x
(same shape for Z using +0x138, +0x148, +0x1f8, +0x158)
```

**Damped path** (when `chara+0x16fb != 0`):

```
chara+0x130 *= DAT_143e8a2d4   (decay constant)
chara+0x138 *= DAT_143e8a2d4
chara+0x134 *= DAT_143e8a2e8   (different Y decay)
chara+0xa0 += TimeDilation * chara+0x130
chara+0xa8 += TimeDilation * chara+0x138
```

`TimeDilation` comes from `LuxMoveVM_GetTimeDilationScalar @ 0x14030a8c0`
and gates the whole thing: when `g_LuxBattle_VMFreezeRecord.bVMFreezeByte`
is 0, the scalar returns 0 and no position change happens. That is how
hitstop / super-freeze pauses movement.

## The MoveVelocity field is unverified in source

No function that writes `chara+0x130` during a *normal* walking move
has been found yet. What is confirmed:

- It is *read* by `IntegratePhysics_PerTick` and added to position.
- It is *written* by `LuxMoveVM_ApplyMoveOffsetToChara @ 0x140344fc0` for
  attacks that include forward lunges (decoded from a 3-int16 cell payload).
- It is *decayed* by the damped-mode path inside `IntegratePhysics_PerTick`
  itself (when `+0x16fb` is set).

The earlier claim — that animation root motion drives `chara+0x130` —
is **plausible**, because `ULuxRootMotionComponent @ chara+0x3b0` exists
and `LuxBattleChara_ApplyHitCueRootMotion_DirectPositionWrite @ 0x140306530`
does process pose-derived motion. But that hit-cue path **bypasses
`+0x130` entirely** and writes directly to `chara+0xa0/+0xa8`, so it
cannot be asserted that animation root motion drives the `+0x130` value
used by the integrator.

A definitive answer needs one of:
- Tracing every writer of `chara+0x130` (which would mean finding all
  stores to that offset across the binary).
- Finding the move VM opcode that writes velocity (the available docs
  list 0x40002 ATK and a few others, but no "velocity write" opcode
  by name).

Until then, **the source of normal-walking velocity is unverified.**

## What's verified about `ApplyHitCueRootMotion_DirectPositionWrite`

`LuxBattleChara_ApplyHitCueRootMotion_DirectPositionWrite @ 0x140306530`
applies pose-driven motion to the chara: it reads per-slot hit-cue data
(4 slots, indexed by the `slotIdx` parameter) and writes **directly** to
`chara+0xa0/+0xa8`. It does NOT go through the velocity field.

Slot data (one per slotIdx in 0..3):

| Field | What |
|---|---|
| `(slotIdx + 0x649) * 0xb0` | Hit-cue slot base on chara |
| `+0x16` | Hit-cue index (i16, -1 = inactive) |
| `+0x3c` | Per-slot weight gate (float, 0 = skip slot) |
| `+0x60..+0x68` | Cached local-axis hit-cue translation |
| `+0x70..+0x78` | Cached world-axis hit-cue translation |
| `slotIdx * 0xc0 + 0x95fa0` | Pose pack on chara |
| `+0x818` | Pose-active byte |
| `+0x820` | Active weight |
| `+0x8c0..` | 4 sub-pose tail (0x300 stride each) |

Algorithm:
1. Skip if airborne (`chara+0x16e2`) or hit-cue inactive
2. Compute final blend weight by multiplying through `(1 - subPoseWeight)` chain
3. `LuxBattleChara_EvaluateHitCueQuaternion` extracts the local-axis translation
4. Scale by `chara+0x3490` (same multiplier as the integrator's MoveVel term)
5. Optionally scale by per-slot multiplier at `chara+0x2084 + slotIdx*4`
6. Transform local→world via Euler matrix (`chara+0x90/+0x94/+0x98`)
7. Add directly to `chara+0xa0/+0xa8`
8. Also adds to `chara+0x1c0/+0x1c8` (residual velocity for next frame's
   `ApplyResidualVelocity_PostTick`)

So this is the **post-hit follow-through** path: when a hit-reaction
animation pulls the chara through space, this is where the per-frame
displacement comes from. It does NOT handle normal walking.

## Motion-input flag bank

`LuxBattleChara_SetMotionInputFlag @ 0x140304c00` is the canonical writer
to a 64-byte flag array at `chara+0x16d0..+0x170f`. Each byte is one
binary motion-input flag, indexed by the `flagIdx` parameter (0..0x3f).

**Verified flag indices:**

| Flag | Meaning (from binary context) |
|---|---|
| `0x0b` | Fall reaction. Written by `TickCharaMainSimulation` when chara goes off platform (airborne flag set + falling Y velocity + matching state in `DAT_144125c50` table) |
| `0x12` | Airborne state. Special handler: when CLEARED, snaps Y to terrain floor at `chara+0x3c8` and clears airborne pose at `chara+0x96f68` |
| `0x29` | Recursive: clearing this also calls `SetMotionInputFlag(0x21, 0)` and `SetMotionInputFlag(0x30, 1)`. High-level "movement done" trigger |
| `0x2a` | When SET: copies `chara[1].field_0x4a0..+0x4a3` (4 bytes) into `chara->bActiveAttackStateFlag` area |
| Mask `0x2000200003f000` for flags < 0x36 | Cluster {0xc, 0xd, 0xe, 0xf, 0x10, 0x11, 0x29, 0x35} — setting any triggers a chained `SetMotionInputFlag(0xb, ...)` (fall reaction) |

**Flags read by `CanTrackOpponentLookAt @ 0x14030a550`** (any non-zero
disables auto-rotation toward opponent):

`+0x16d3`, `+0x16d4`, `+0x16d8`, `+0x16db`, `+0x16df`,
`+0x16e5`, `+0x16e6`, `+0x16e9`, `+0x16ec`, `+0x16fe`

The semantics of these flags have NOT been individually verified.
Their names ("hit-reaction", "step-state", "movement-commit") are
guesses based on which other systems gate on them. The precise
meaning of each individual byte is **unverified**.

## TimeDilation system (verified)

`LuxMoveVM_GetTimeDilationScalar @ 0x14030a8c0` returns a per-chara
multiplier. Verified inputs:

| Source | What |
|---|---|
| `g_LuxBattle_VMFreezeRecord.bVMFreezeByte @ 0x1448462d0` | Consulted **only on Path B** (see below). When non-zero on Path B, returns 0. Often-cited as the "primary hitstop control" — true for normal hit-stop / super-flash / Critical Edge, not true for replay viewing. |
| `g_LuxBattle_VMFreezeRecord.flBaseAlpha` | Base alpha multiplier (used when freeze byte is 0 on Path B). |
| `chara+0x3500` | Per-chara base time-scale slot. |
| `chara+0x3510` | Per-chara fallback slot (negative triggers Path A — special-move slow-mo). |
| `chara+0x23c` | CharaKindByte (0/1 selects perCharaCap). |
| `chara+0x19ec` | Match-state id (must be 2 for normal play). |
| `chara+0x973e8` | Opponent chara back-ref (read for the P2-ish entry-gate predicate). |
| `DAT_144846458` / `DAT_14484645c` | Global mode array. |

### The four return paths

The function has **four** distinct returns, and only one of them honours
`bVMFreezeByte`:

```c
float LuxMoveVM_GetTimeDilationScalar(LuxBattleChara* chara) {
    byte charaKindByte = chara->CharaKindByte;            // +0x23C

    // OUTER GUARD — per-opp-mode cell. If 3, skip everything below.
    if ((&DAT_14484645c)[charaKindByte ^ 1] != 3) {

        if ((int)DAT_144846458 < 0) {                     // global mode
            // ENTRY GATE — only reaches Path A/B if state != 2 OR
            // (P2 AND opp.state == 2). For P1 in normal play (state==2),
            // condition is FALSE → fall through to chara+0x3500 below.
            if ((chara->state_at0x19EC != 2) ||
                (charaKindByte != 0 &&
                 chara->Opp->state_at0x19EC == 2)) {

                if (chara->slot_at0x3510 < 0.0f) {
                    // PATH A — special slow-mo (super-flash, finishing-blow).
                    // *** BYPASSES VMFreezeByte ***
                    return flOutBlendW1 * chara->scale_at0x3500;
                }

                // PATH B — normal play, honours VMFreezeByte.
                float fVar1 = (g_VMFreezeRecord.bVMFreezeByte == 0)
                                ? g_VMFreezeRecord.flBaseAlpha : 0.0f;
                return fVar1 * min(chara->scale_at0x3500, perCharaCap);
            }
            // P1 in state==2 falls through ↓
        }
        else if (DAT_144846458 != charaKindByte) {
            // PATH C — mode mismatch.
            return 0.0f;
        }
    }

    // FALL-THROUGH — per-chara base time-scale (typically 1.0).
    // *** BYPASSES VMFreezeByte ***
    return chara->scale_at0x3500;
}
```

| Path | Condition | Honours `bVMFreezeByte`? | Returns |
|------|-----------|:-:|---------|
| **A** | `+0x3510 < 0` (super-flash, finishing-blow) | **No** | `flOutBlendW1 * chara+0x3500` |
| **B** | normal play, entry gate matches | **Yes** | `(VMFreezeByte == 0 ? flBaseAlpha : 0) * scale` |
| **C** | global-mode mismatch on charaKindByte | n/a | `0.0f` |
| **Fall-through** | outer guard == 3, OR `DAT_144846458 < 0` and entry gate **doesn't** match (P1 in state==2) | **No** | `chara+0x3500` (typically `1.0f`) |

### Why `bVMFreezeByte = 1` alone fails replay viewing

In replay watching, the chara's match-state byte at `+0x19EC` stays at
**2** (normal play), even though inputs come from a recorded file. For
P1 (`charaKindByte == 0`) the entry gate evaluates
`(2 != 2) || (0 != 0 && ...)` = `FALSE`, so Path A/B is skipped and the
function falls through to `chara+0x3500` (≈ 1.0). Setting `bVMFreezeByte`
does nothing: UE4 anim instances scale by the engine's tick dilation,
the BM round timer keeps draining, and the replay auto-advances.

Hit-stop / super-freeze still work in stock SC6 because the engine writes
`+0x3510 < 0` (Path A) or transitions chara state out of 2 (Path B), so
the VMFreezeByte path actually executes. A mod that wants to freeze
*regardless* of chara state needs an entry hook on this function — see
[Replay System: HorseMod gate stack](replay-system.md#horsemod-gate-stack-summary).

### What VMFreezeByte halts (verified caller list)

Setting `bVMFreezeByte != 0` zeros the scalar across the full Move-VM and physics stack:
`LuxMoveVM_TickDriver`, `LuxBattle_TickCharaMainSimulation`,
`LuxBattle_TickHitStopSchedulerAndInputMirror`, `LuxBattleChara_FinalizeTickPoseAndState`,
`LuxMoveVM_ExecuteOpStream`, `LuxMoveVM_AdvanceLinkedMotionObject`,
`LuxMoveVM_AdvanceLaneFrameStep`, `LuxMoveVM_AdvanceCharaAnimClipPlayer`,
`LuxBattleChara_ApplyKnockbackForce`, `LuxBattleChara_IntegratePhysics`,
`LuxBattle_TickCharaCollisionPhysics`, `LuxBattle_DispatchFootstepEvents`,
`LuxBattle_DispatchWeaponTraceContactVFX`, `LuxBattle_SetupPoseFromENSTData`,
`LuxBattle_BattlePhase_Tick`, plus a handful of visual-FX selectors. Effectively every
"this is part of the gameplay simulation" tick.

### What VMFreezeByte does NOT halt

Anything that runs off UE4's `World::DeltaTime` rather than the VM scalar. Notable:

- UMG widget Tick (HUD, training-mode panels, input-display widgets)
- Particle / Niagara render time (visual decay continues)
- Audio playback engine
- The animation root-motion blender as it samples per-frame poses for non-battle actors

Practical consequence: a freeze mod that uses only VMFreezeByte will halt the gameplay
loop cleanly, but display-rate widgets reading chara state at render rate (input-history
overlays, etc.) keep polling and may visually decouple from the simulation.
For full pause semantics including UI, use UE4's `bGamePaused`; for simulation-only
freeze, VMFreezeByte is enough.

## Step types — what's actually in the binary

The training-mode dummy enum `ELuxBattleDummyMoveType` lists six
step-type entries:

```
Run_Right         (0x1433b00c0)
Run_Left          (0x1433b0110)
Run_FrontStep     (0x1433b0160)
Run_BackStep      (0x1433b01b0)
Run_RightStep     (0x1433b0200)
Run_LeftStep      (0x1433b0250)
```

These are **dummy behaviors** — they tell the training dummy to perform
that motion. They are labels, not input commands. The `Run_` prefix
suggests they all execute out of a "run" state, but the binary does not
spell out what input the player presses to trigger each one — that
mapping lives in per-character move-bank bytecode that has not been decoded.

The CPU AI has matching action classes for these too: `HgCpuDirectRightStep`,
`HgCpuDirectLeftStep`, `HgCpuDirectFrontStep`, `HgCpuDirectBackStep` (RTTI
strings at `0x144141918` etc.).

`ELuxBattleMoveCategory` (the move-class enum) has separate entries:
`HorizontalAttacks`, `VerticalAttacks`, `Kicks`, `EightWayRunMoves`,
`Throws`, etc. The `EightWayRunMoves` category covers attacks that
come *out of* 8WR, not the 8WR movement itself.

## Counter-hit messages

`ELuxBattleMessage::EMS_RunCounter` exists at `0x1432712e8`. It sits in
the same enum, next to `EMS_AttackCounter`, `EMS_BreakCounter`, and
`EMS_ImpactCounter`. Where it is *fired* has not been traced — there are no
xrefs to the string itself in static code, only references in the
reflection enum table. So the *existence* of a "RunCounter" category
is verified, but the *trigger conditions* are not.

## What CHANGES movement (verified levers only)

| Lever | Mechanism (verified) |
|---|---|
| **`g_LuxBattle_VMFreezeRecord.bVMFreezeByte`** at `0x1448462d0` | When 0, `GetTimeDilationScalar` returns 0; integrator multiplies delta by 0; position frozen. Hitstop / super-freeze. |
| **`chara+0x3510`** | Negative value triggers slow-mo path inside `GetTimeDilationScalar`. Per-chara special-move time scale. |
| **`chara+0x3500`** | Per-chara base time-scale slot. |
| **`chara+0x3490`** | Multiplied into the `chara+0x130` MoveVel term of the integrator AND the hit-cue translation in `ApplyHitCueRootMotion`. Per-frame motion blend weight. |
| **`chara+0x16fb`** | Picks the damped path in `IntegratePhysics_PerTick` (decays MoveVel each frame instead of integrating it). |
| **`chara+0x198c == 0x12`** | Selects airborne uncapped Y integration (no terrain clamp). |
| **`chara+0x16e2`** | Airborne flag (read by `ApplyHitCueRootMotion` to skip; read by `TickCharaMainSimulation` to detect off-platform fall) |

The cluster of flags at `chara+0x16d0..+0x170f` collectively gates
auto-rotation via `CanTrackOpponentLookAt`. **What individually toggles
each one is unverified** — they are written by `SetMotionInputFlag` from
move bytecode, but which moves write which flags has not been traced.

## Things I claimed earlier and now retract

- **"Per-character step distance lives in animation `.uasset` files."**
  Plausible but unverified. `chara+0x130` is read by the integrator;
  whether it is written by anim root motion or by VM bytecode is not known
  from what has been decoded.
- **"Soul Charge mode flag (`chara+0x170c`) doesn't affect normal stepping."**
  Half-right: it does not appear in `IntegratePhysics_PerTick` or
  `ApplyHitCueRootMotion`, but it could feed into VM bytecode that writes
  `chara+0x130`. **Unverified either way.**
- **"Best stepping strategy" recommendations.** Those were extrapolated
  from the existence of `EMS_RunCounter` and the move-class enum, plus
  general fighting-game knowledge. The binary confirms only that:
  - `EMS_RunCounter` is a defined message category.
  - `Run_*` step types exist in the dummy enum.
  - `HorizontalAttacks` and `VerticalAttacks` are distinct move categories.
  
  Whether vertical attacks actually have narrower hitboxes than horizontal
  ones, whether RunCounter actually fires for steps mistimed against
  horizontals, and what frame ranges step-G covers — **none of those
  are verified from the binary alone.** They are game-design conventions
  consistent with the systems that exist, but consistency is not proof.

## Code references

| Function / Symbol | RVA | What's verified |
|---|---|---|
| `LuxBattle_TickCharaMainSimulation` | `0x14034da70` | Master per-tick chara update; calls the movement subsystems in the order listed above |
| `LuxBattleChara_IntegratePhysics_PerTick` | `0x140306bb0` | The integrator math (above). Confirmed reads / writes |
| `LuxBattleChara_ApplyHitCueRootMotion_DirectPositionWrite` | `0x140306530` | Direct world-position writer for hit-reaction follow-through. Bypasses `+0x130` |
| `LuxBattleChara_ApplyResidualVelocity_PostTick` | `0x140304280` | Adds `+0x1c0/+0x1c8` to position with decay |
| `LuxBattleChara_DecayHitstunSlideVelocity` | `0x140309160` | Decays `+0x1f0/+0x1f8` (the pushback term in the integrator) per hit-type curve |
| `LuxBattleChara_TickHitStateStateMachine` | `0x140308ec0` | Calls the slide decay; switches phases by `+0x1994` state |
| `LuxBattleChara_CanTrackOpponentLookAt` | `0x14030a550` | Returns false when any flag in `+0x16d0..+0x170f` cluster is set |
| `LuxBattleChara_SetMotionInputFlag` | `0x140304c00` | Canonical writer to flag bank `+0x16d0..+0x170f` |
| `LuxMoveVM_GetTimeDilationScalar` | `0x14030a8c0` | Per-chara time scale; returns 0 when VMFreezeByte is 0 |
| `LuxMoveVM_ApplyMoveOffsetToChara` | `0x140344fc0` | Writes `+0x130` from a 3-int16 cell payload (attack lunges only — verified writer for attack-driven velocity) |
| `LuxMoveVM_ResolveRangeAndAngleOffset` | `0x140307bd0` | Decoder used by the above |
| `g_LuxBattle_VMFreezeRecord` | `0x1448462d0` | Master freeze byte + multipliers struct |
| `g_LuxBattle_HitReactionSlideTable` | `0x1448554e8` | Per-hit-type slide-decay curves (formerly misnamed `g_LuxMoveVM_PerSlotScaleTable`) |
| `ULuxRootMotionComponent_StaticClass` | `0x140196680` | Class registration. Component is at chara+0x3b0. Whether it writes `+0x130` is **unverified** |
| `Z_Construct_UClass_ULuxRootMotionComponent` | `0x140b7ce50` | Property layout: Owner, RootMotionParams, CachedRootMotionTransform |

## When moves retrack against the opponent — verified

Retracking — the chara's body rotating to face the opponent during a move —
runs once per tick from `LuxBattle_TickCharaMainSimulation` step (J),
which calls `LuxBattleChara_UpdateOpponentRelativeAngles_PerTick @ 0x140305e50`,
which in turn calls `LuxBattleChara_RetrackFacingTowardOpponent @ 0x140369450`.

The retrack function is the gate. Verified read of `0x140369450`:

```
target_angle = chara+0x15a4
if (chara+0x16f0 == 0 AND chara+0x16d9 != 0):
    target_angle += 0.5    // 180° side-mirror flip

★ THE GATE:
if (chara+0x16e6 != 0 AND chara+0x16e1 == 0):
    return                  // no rotation this frame

// Otherwise: compute SLERP-clamped delta and call ApplyFacingRotationDelta
```

So a move retracks iff `chara+0x16e6 == 0` OR `chara+0x16e1 != 0`.

> **Correction (2026-05-01).** An earlier version of this page interpreted
> `chara+0x16e1` as a per-move "homing override" / "tracking flag". That
> interpretation was wrong. Both `+0x16e6` and `+0x16e1` are entries in
> the **64-element motion-input flag bank** at `chara+0x16D0..+0x170F`,
> documented under `LuxBattleChara_SetMotionInputFlag @ 0x140304c00`.
>
> - `chara+0x16e6` = motion-input flag `0x16` — set by various
>   move-state transitions (acts as "in-some-non-walk-state" inside
>   the gate).
> - `chara+0x16e1` = motion-input flag `0x11` — part of the
>   fall-reaction cluster `{0x0c..0x11, 0x29, 0x35}` that gets OR'd
>   to derive flag `0x0b` (master fall flag). Verified writer:
>   `LuxBattle_ComputeHitReactionParams @ 0x140343b90`, **case 0xd**
>   (a specific knockback / recovery reaction type), where it is
>   CLEARED (= 0). The line is:
>   ```c
>   pDefender->field_0x16e1 = 0;
>   LuxBattleChara_SetMotionInputFlag(pDefender, 0xb, ...);
>   ```
>
> Re-reading the gate truth table with corrected semantics:
>
> | `+0x16e6` | `+0x16e1` | Retrack | Real meaning |
> |---|---|---|---|
> | 0 | any | runs | idle / walking — natural facing |
> | 1 | 0 | **blocked** | mid-move, NOT in fall — facing locked |
> | 1 | 1 | runs | mid-move AND in fall-reaction — engine realigns |
>
> **There is no "homing override" flag in this gate.** Moves that track
> the opponent in SC6 (homing throws, certain supers) implement that
> through a different mechanism — most likely the SLERP-weight system
> at `chara+0x971ac..+0x971b8` (set up at move-start with non-default
> presets), or by the move script writing `chara+0x94` directly.

**Verified writer of `chara+0x16e6`:**
`LuxMoveVM_OnMoveStart_SnapPositionAndFacing_LockRetrack @ 0x1402ff3e0`
sets `chara+0x16e6 = 1` at move start. It also:
1. Snaps chara world XZ to `chara+0x300/+0x308` (cached look-at position)
2. Computes a target rotation from move-attribute data at `chara+0x96928`
3. Calls `ApplyFacingRotationDelta` to snap facing to that target
4. Sets bit `0x400000` of `chara+0x44930 + animState*0x468`

This is the "commit to the move's facing direction" function. Once it
fires, retracking is suppressed for the rest of the move — **unless**
the chara enters a fall-reaction state and that path toggles
`chara+0x16e1` (motion-input flag `0x11`).

**Verified consumer of `chara+0x16e1`:**
`UpdateOpponentRelativeAngles_PerTick @ 0x140305e50` reads `chara+0x16e1`
to gate the **animation-sector pointer update** at `chara+0x97248`:

```
if (chara+0x16e1 == 0
    AND (chara+0x198c & 0xfffc) == 0
    AND chara+0x198c != 1):
    // skip: don't change which 8-direction animation variant plays
else:
    update sector pointer, recalc per-frame look-target scalar at +0x15c0
```

So `chara+0x16e1` is read in two places: by the retrack gate (above)
and by the animation-sector update (here). In both, the meaning is
the same — when the chara is in a fall-reaction state, the engine
re-allows aiming and animation alignment toward the opponent.

**Per-frame rotation caps inside `RetrackFacingTowardOpponent`:**

| Stance / state | Cap |
|---|---|
| Default (`chara+0x19b0 != 1`) | `0.5` (i.e. 180°/frame — effectively no cap) |
| `chara+0x19b0 == 1` | `DAT_143e8a040` (smaller cap — restricted stance) |
| `chara+0x19b0 == 1` AND `chara+0x16e5 != 0` | `DAT_143e8a084` (smallest cap) |

**SLERP weight at `chara+0x971b0`:**

The rotation delta is multiplied by a SLERP weight at `chara+0x971b0`
before clamping. The weight system has four fields:

| Field | Role |
|---|---|
| `chara+0x971ac` | Countdown timer (frames remaining) |
| `chara+0x971b0` | Current weight value, 0..1 |
| `chara+0x971b4` | Preset value loaded when countdown reaches 0 |
| `chara+0x971b8` | Per-frame increment (added each tick while countdown active) |
| `chara+0x971a8` | Mode selector: 0 = scale-then-clamp, 1 = clamp-by-weight, other = no rotation |

Tracking moves that should retrack gradually rather than snap write to these
fields to control the ramp-in. Move bytecode is the suspected writer,
but **the writer is unverified** — finding it would reveal how
per-move tracking strength is encoded.

**Bone-target retracking (secondary system):**

When `chara+0x44dc2 != -1`, `RetrackFacingTowardOpponent` runs a second
pass that aims at a specific opponent bone (read from a pose at
`chara+0x35a0` vtable[8], offset `+0xc0` or `+0x300` depending on
`chara+0x971d0`). It uses `atan2` of the bone delta against the cached
opponent position at `chara+0x964a0/+0x964a8`, with its own SLERP
weight system at `chara+0x971c0..+0x971cc`. This is what aligns
attacks that need to hit a specific bone (likely throws and grabs).

### Summary of "when does a move retrack"

| Frame state | Retracks? |
|---|---|
| No move active (idle / walking / 8WR) — `+0x16e6 == 0` | **Yes**, every frame, full speed (capped at 180°/frame) |
| Move active, `+0x16e6 == 1`, `+0x16e1 == 0` (normal animation) | **No**, facing locked |
| Move active, `+0x16e6 == 1`, `+0x16e1 == 1` (fall-reaction during move) | **Yes**, gradually (SLERP weight ramps in) |
| Restricted stance `+0x19b0 == 1` | Caps per-frame angle to `DAT_143e8a040` |
| Restricted stance + `+0x16e5` set | Caps even tighter to `DAT_143e8a084` |

The third row is **not** a "homing move" path; it is the engine
realigning the chara during a fall-reaction state mid-move. A move's
"tracking / homing" attribute — in the gameplay sense, moves that
track the opponent during their own active frames — is implemented
through a different mechanism, likely the SLERP-weight system at
`chara+0x971ac..+0x971b8` configured at move-start, but that has
**not yet been verified end-to-end**.

### Verified callers / writers

| Symbol | RVA | Role |
|---|---|---|
| `LuxBattleChara_RetrackFacingTowardOpponent` | `0x140369450` | The retrack gate + math + ApplyFacingRotationDelta call |
| `LuxBattleChara_UpdateOpponentRelativeAngles_PerTick` | `0x140305e50` | Per-tick caller; computes target angle and bone-target data; gates animation-sector update on `+0x16e1` |
| `LuxBattleChara_ApplyFacingRotationDelta` | `0x140311350` | Wrapping/clamping writer to `chara+0x94` (facing), `+0x22c`, `+0x15a4`, `+0x15ac` |
| `LuxMoveVM_OnMoveStart_SnapPositionAndFacing_LockRetrack` | `0x1402ff3e0` | Sets `chara+0x16e6 = 1` at move start |

### Unverified

- **How "homing" / "tracking" moves are actually authored.** The
  per-move "track the opponent" attribute is most likely the SLERP-
  weight preset at `chara+0x971b4` (loaded into `chara+0x971b0` when
  the countdown at `chara+0x971ac` reaches zero). Find the writer of
  `+0x971b4 / +0x971b8 / +0x971ac` to pin this down.
- **The writers of `chara+0x16e6`** at move end (the path that lets
  default retracking resume after the move). The lock-retrack writer at
  move-start is found, but the cleanup path is not.
- **The writers of `chara+0x16e1`** beyond the verified case-0xd
  hit-reaction site. Other entry points to that flag are unmapped.
- **The actual values of `DAT_143e8a040` and `DAT_143e8a084`**
  (the restricted-stance per-frame angle caps).

## What needs verification next

- **Find the writer of `chara+0x130` during a non-attack move** (walking,
  8WR, sidestep). This is the central unanswered question.
- **Find the writers of the SLERP weight fields at `chara+0x971ac..+0x971b8`.**
  That pins down the per-move "homing" / "tracking" attribute encoding.
  (The flag pair `+0x16e6` / `+0x16e1` is NOT how homing is encoded —
  see the correction note above.)
- **Trace which motion-input flags get set by which moves.** The flag bank
  and the flag-clearing predicate are known, but not the per-flag
  semantics.
- **Find where `EMS_RunCounter` is actually fired.** The string has no
  static xref, but it gets emitted somewhere at runtime.
- **Confirm or refute the V-vs-H hitbox-width hypothesis** by inspecting
  KHit node geometry for representative moves of each category.
