# Reaction System (yarare)

What happens AFTER the hitbox classifier says "yes, a hit landed": picking the
defender's reaction animation, advancing it per tick, and chaining knockdown /
ringout / get-up state. The binary refers to this pipeline as the
**yarare** subsystem (やられ = "being hit").

For the upstream hit-detection side (KHit lists, `PerHurtboxBitmask`, the
classifier output `LuxHitReactionState`), see [Hitbox System](hitbox-system.md).
For the outer command-script VM that hosts these calls, see
[Move System](move-system.md).

## At a glance

| Stage | Function | Address | Role |
|-------|----------|---------|------|
| Classify | `LuxBattle_ResolveAttackVsHurtboxMask22` | `0x14033C100` | Writes `chara+0x43DA0` (result code) and `chara+0x252` (`LuxHitReactionState`). |
| State-write | `LuxBattleChara_ProcessHitReactionState` | `0x140342FF0` | Branches on `+0x43DA0`, writes per-frame flag bitset at `chara+0x6DC..+0x824` (wiped every tick). |
| Pick | `LuxMoveVM_TickPickAndDispatchReaction` | `0x1402DEF50` | Walks opp's yarare table, filters via the 134-code gate, picks a yarareId. Contains the [throw height gate](hitbox-system.md#throw-connection-yarare-dispatch). |
| Dispatch | `LuxBattle_DispatchYarareReaction` | `0x1403521B0` | **80-case switch on yarareId** — commits reach / lane / sub-mode and saves the prior state triplet. |
| Advance | `LuxMoveVM_TickActiveYarareReaction` | `0x14035EF30` | Switch on `vmCtx->dwActiveYarareId` → per-id `TickYarare_0xXX` handler. |
| Override | `LuxMoveVM_ProbeSpecialReactionOverride` | `0x1402DFD60` | Combo-extension override path (replaces the picked yarare mid-flight). |
| Bitmask | `LuxBattle_YarareIdToReactionBitmask` | `0x14035F390` | Maps yarareId `1..0x1A` → single-bit class mask written to `vmCtx+0x2AD0`. |

State for the active reaction lives on the per-chara VM slot
`FLuxMoveCommandPlayer*` (`vmCtx`). See
[Game Structures: FLuxMoveCommandPlayer](structures.md#fluxmovecommandplayer-12332-bytes)
for the offset map.

> **Verification status.** The pipeline and the gate / dispatch / advance call
> graph are read directly from Ghidra decompiles. The per-id behavior summaries
> below come from per-handler decompiles. The yarare-id → display-name mapping
> (e.g. "ShortBackStagger") is **inferred from handler behavior**, not from
> any string table in the binary.

---

## `LuxHitReactionState` — chara-side state code

Set by the classifier upstream; consumed by `ProcessHitReactionState`,
`UpdateHitVisualLean`, and the AI. A 4-byte enum at `chara+0x252`.

| Value | Name |
|------:|------|
| 0 | `None` |
| 1 | `Hit` |
| 2 | `BlockedLow` |
| 3 | `BlockedHigh` |
| 4 | `MutualHit_Loser` |
| 6 | `Tech` |
| 8 | `MutualHit_Winner` |
| 9 | `AirHit` |
| 0xA | `MutualHit_Trade` |
| 0xB | `WallSplat` |
| 0xC | `Stagger` |

Also written as `i32[22]` aggregate at `chara+0x1C74` (`PerHurtboxReactionState`).

## `EYarareReactionId` — per-VM-slot reaction id

A `u16` at `vmCtx+0x2B30` (`ActiveYarareId`), range `0x01..0x50`. The
categorical groups below are derived from the `DispatchYarareReaction` switch
and the per-id Init / Tick handler addresses:

| Range | Group | Notes |
|------:|-------|-------|
| `0x01..0x1A` | **Generic light hits** | No sub-handler; sets bitmask `1 << (id-1)` via `YarareIdToReactionBitmask`. Tick path = `TickWithNotifTokenSwitch`. |
| `0x03` | CrumpleFall | Intensity-modulated hang (lower intensity → longer pause). |
| `0x0E..0x10` | Wall stagger trio | `WallStaggerStart` / `WallStagger` / `WallStaggerEnd`. Always passes throw-dispatch allow-set. |
| `0x1B` | ShortBackStagger | cos-rand reach. |
| `0x1C` | StaggerVar / ResetToIdle | reach = 60.0f. |
| `0x1D` | WallStagger | full per-id Init+Tick. |
| `0x1E`, `0x50` | Knockdown | reach = 30.0f, sub-mode = 8. |
| `0x1F`, `0x21`, `0x38` | StandardLaunch | Shares one Tick handler. The "tall-pose" launch in the unconditional allow-set. |
| `0x20` | SideStumble / LaunchVar | cos-rand reach. Always passes allow-set. |
| `0x22..0x27` | Medium reactions | Per-id Init+Tick. |
| `0x26` | SideStumblePoseCopy | Variant of 0x20 that copies `vmCtx->dwActivePose`. |
| `0x27` | HardKnock | Sub-mode = 4. |
| `0x28` | NullReaction | No-op probe. |
| `0x29` | HitVsBlockBranch | Step-direction-aware. |
| `0x2A` | PureStateSwap | Only the save-prior-triplet runs. |
| `0x2B` | GenericSideRng | Variant of 0x20. |
| `0x2C`, `0x2D` | LaunchAirCarry | Shared Tick handler with dual-timer hold. Always passes allow-set. |
| `0x2E..0x31` | RingoutFall variants | Shared Tick handler with internal state 0x17→0x18→0x19→0x1A. Always passes allow-set. |
| `0x32` | PickRingoutReaction | Stage-edge-aware re-pick. |
| `0x33..0x37`, `0x39`, `0x3A` | Heavy reactions | Per-id Init+Tick. |
| `0x35`, `0x36` | AerialForcedLaunch / Variant | Remap targets when 0x21 hits a high-velocity airborne defender. |
| `0x3B` | BackBreaker | Stamina-style escape + edge-aware fall. Always passes allow-set. |
| `0x3C`, `0x3D` | WallHit / WallHitVar | Id↔handler swap (`0x3C` calls `InitYarare_0x3D` and vice versa). |
| `0x3E..0x41` | Heavy mid-reactions | Per-id Init+Tick. |
| `0x42` | BackBreakerCrit | Critical-edge finisher; reads per-charaKind reach pair. |
| `0x43` | KnockdownLike | Falls into the 0x50 reach-30 block. |
| `0x44`, `0x45` | QuickRise tech recovery | reach = 3.0f. Inline timer-based exit, no sub-handler. |
| `0x46..0x4E` | GetUp / ParryBreak | All call `InitYarare_0x4F` and stash its return as a post-effect callback. |
| `0x4F` | ParryRecovery | Calls `InitYarare_0x50`. |
| `0x50` | GetUp / Knockdown terminal | Shared with `0x1E` reach-30 path. |

The categorical names above are **inferred from handler behavior**, not from
any in-binary string. They are useful as a reference when authoring moves or
reading the ATB opcode's yarare-id stream — see
[Move System: ATB hit-reaction chain](move-system.md#atb-hit-reaction-chain).

---

## Per-id Init / Tick handler index

Every yarare ≥ `0x1B` (and `0x03`) has a per-id Init function (`LuxBattle_InitYarare_0xXX`)
and Tick function (`LuxMoveVM_TickYarare_0xXX`). The dispatcher routes by `vmCtx->dwActiveYarareId`.

### Tick handlers

| YarareId | Function | Address |
|---------:|----------|---------|
| `0x1B` | `LuxMoveVM_TickYarare_0x1B_Stagger` | `0x140358B10` |
| `0x1C` | `LuxMoveVM_TickYarare_0x1C_StaggerVar` | `0x140358C20` |
| `0x1D` | `LuxMoveVM_TickYarare_0x1D_WallStagger` | `0x140354090` |
| `0x1E` | `LuxMoveVM_TickYarare_0x1E_WallStaggerVar` | `0x140354270` |
| `0x1F`/`0x21`/`0x38` | `LuxMoveVM_TickYarare_0x1F_StandardLaunch` | `0x140356AC0` |
| `0x20` | `LuxMoveVM_TickYarare_0x20_LaunchVar` | `0x140356620` |
| `0x22`..`0x29` | `LuxMoveVM_TickYarare_0x22`..`0x29` | individual; see Ghidra |
| `0x2A`/`0x2B` | `LuxMoveVM_TickYarare_0x2A` / `0x2B` | `0x140358E50` / `0x140358F60` |
| `0x2C`/`0x2D` | `LuxMoveVM_TickYarare_0x2C_2D_Crumple` | `0x140359180` |
| `0x2E`..`0x31` | `LuxMoveVM_TickYarare_0x2E_RingOut` | `0x1403536A0` |
| `0x32` | `LuxMoveVM_TickYarare_0x32` | `0x140353D70` |
| `0x33`..`0x37`, `0x39`, `0x3A` | `LuxMoveVM_TickYarare_0x33`..`0x3A` | individual |
| `0x3B` | `LuxMoveVM_TickYarare_0x3B_BackBreaker` | `0x140359480` |
| `0x3C` | `LuxMoveVM_TickYarare_0x3C_WallHit` | `0x14035A940` |
| `0x3D` | `LuxMoveVM_TickYarare_0x3D_WallHitVar` | `0x14035A790` |
| `0x3E`..`0x41` | `LuxMoveVM_TickYarare_0x3E`..`0x41` | individual |
| `0x42` | `LuxMoveVM_TickYarare_0x42_BackBreakerCrit` | `0x1403597F0` |
| `0x43` | `TickWithNotifTokenSwitch(0x43)` | (shared) |
| `0x44`/`0x45` | inline | (in `TickActiveYarareReaction`) |
| `0x46`..`0x4E` | `LuxMoveVM_TickWithAirStageTracking` | (shared) |
| `0x4F`/`0x50` | `LuxMoveVM_TickYarare_0x4F` / `0x50` | (individual) |

A Tick handler returns `1` to signal "reaction-slot commit, re-evaluate next
tick", and `0` to continue or cleanly exit.

---

## `CheckYarareReactionGate` — 135 gate codes

The reaction picker reads the opponent's per-character yarare table (entries
`{u16 yarareId, s16 weight, s16 bodyPart}` at `opp+0x10 + idx*0x12`) and gates
each entry via `LuxBattle_CheckYarareReactionGate @ 0x140362E70`. The gate
function dispatches by gate-code `1..0x87` (135 inclusive codes) into one of 15 family
helpers.

### Gate family dispatch

| Code range | Family | Address |
|-----------:|--------|---------|
| `1..2` | inline simple flags | (in master) |
| `3` | `LuxBattle_CheckYarareGate_AttackCategoryGate` | `0x140362C30` |
| `4` | `LuxBattle_CheckYarareGate_AttackMotionGate` | `0x140362D30` |
| `5..8` | `LuxBattle_CheckYarareGate_StepRange` | `0x140360650` |
| `9..0xE` | `LuxBattle_CheckYarareGate_ReactionStateMatch` | `0x140360930` |
| `0xF..0x11` | `LuxBattle_CheckYarareGate_BackStepRange` | `0x1403607F0` |
| `0x12` | `LuxBattle_CheckReactionCancelClearance` | (see Ghidra) |
| `0x13..0x16` | `LuxBattle_CheckPrevCategoryTerrainGate` / `LuxBattle_CheckCategoryTerrainGate` | (see Ghidra) |
| `0x17..0x1E` | `LuxBattle_CheckYarareGate_AerialRange` | `0x140361240` |
| `0x1F..0x26` | `LuxBattle_CheckYarareGate_GroundApproachRange` | `0x140361420` |
| `0x27..0x2C` | inline stance-state checks `wStanceState197E ∈ {0xF, 0x10, 0x11}` (self/opp) | (in master) |
| `0x2D` | `LuxBattle_CheckYarareGate_RingPositionAdvantage` | `0x1403615C0` |
| `0x2E` | `LuxBattle_CheckYarareGate_HitStateRingAdvantage` | `0x140361740` |
| `0x2F..0x38` | per-charaKind step-approach distance threshold | (inline in master) |
| `0x33` | `LuxBattle_CheckYarareGate_OppHitRingAdvantage` | `0x140361820` |
| `0x34` | `LuxBattle_CheckYarareGate_OppAttackRingAdvantage` | `0x1403618F0` |
| `0x39` | opp aerial + altitude threshold | (inline in master) |
| `0x3A..0x3B` | `LuxBattle_CheckOpponentFrontTerrainMatch` | (see Ghidra) |
| `0x3C..0x3D` | wall/edge adjacency + intensity gate | (inline in master) |
| `0x3E..0x41`, `0x46..0x49` | `LuxMoveVM_ClassifyRangeBucket` quadrant (front/back/left/right) | (inline in master) |
| `0x42..0x45` | `LuxBattle_CheckYarareGate_MutualGuardBreakRange` | `0x140362060` |
| `0x4A..0x69` | `LuxBattle_CheckYarareGate_ApproachAngleRange` (32 codes = 8 angle bands × 4 range buckets) | `0x140362510` |
| `0x6A..0x6D` | `LuxBattle_CheckYarareGate_OppAttackHealthRange` | `0x1403626F0` |
| `0x6E..0x71` | `LuxBattle_CheckYarareGate_SelfDistanceBucket` | `0x140362790` |
| `0x72` | airborne + reaction-state==8 (consults `LuxMoveVM_EvaluateAttackRange`) | (inline) |
| `0x73..0x74` | misc state flags | (inline) |
| `0x75..0x76` | battle-mode phase / world-mode pump | (inline) |
| `0x77..0x80` | self/opp `nDefenseModeAtLastHit ∈ {1, 3, 6, 8}` + active-hit flag | (inline) |
| `0x81..0x82` | self/opp `bInBlockstunFlag == 1` | (inline) |
| `0x83..0x84` | self/opp `bInHitstunFlag == 1` AND `wMoveTransitionState == 0x16` (perfect guard) | (inline) |
| `0x85..0x86` | self/opp `field_0x197C ∈ {2, 5}` | (inline) |
| `0x87` | wall-edge flag + `field_0x19C4 == 10` | (inline) |

### Ring-margin formula

All four "ring-advantage" gates (`0x2E`, `0x33`, `0x34`, `0x2D`) use the same
sliding-threshold formula:

```
d        = bMasterWindowFlag_16EC ? perCharaKindMargin[CharaKindByte] : 0.0f
intensity = clamp(perCharaKindIntensity[CharaKindByte], 0, 6)
threshold = 13 - 2*intensity     // higher intensity → less margin needed
require: d >= threshold AND <chara-flag-predicate>
```

The two table backings:

| Table | Address | Stride | Indexed by |
|-------|---------|-------:|------------|
| `g_LuxBattle_RingMarginPerChara` (informal name) | `0x14470E310` | `0x8` | `chara+0x23C` `CharaKindByte` |
| `g_LuxBattle_IntensityPerChara` (informal name) | `0x144711F88` | `0xC0E` | same |

Per-charaKind reach-offset table for the dispatcher's knockback subtraction:
`DAT_14470E330`, stride `0x180` (up to 32 entries, each `{u32 pad, s16 oppMoveStateId,
s16 reachOffset}`, scanned linearly).

---

## `FLuxBattleYarareReactionParamBlock` — 1100-byte global param table

Lazy-allocated at `DAT_14470E018` by `LuxMoveVM_AllocReactionParamBlock @
0x1403306F0`, and initialised by `LuxMoveVM_InitReactionParamBlock @ 0x140330760`.
It holds the per-intensity reach / knockback / weight tables that the dispatcher
and the per-id handlers consult.

| Offset | Type | Field | Used by |
|-------:|------|-------|---------|
| +0x38 | `float[7]` | `pIntensityWeight` + fallback at +0x54 | `TickPickAndDispatchReaction` weight bonus |
| +0x54 | `float` | reach for `InitYarare_0x42` | BackBreakerCrit reach pair (with +0x70) |
| +0x70 | `float` | reach alt for `InitYarare_0x42` | BackBreakerCrit |
| +0x188 | `float[7]` | `pIntensityReach1F_Norm` + fallback at +0x1A4 | `InitYarare_0x1F` (StandardLaunch) |
| +0x1A8 | `float[7]` | `pIntensityReach1F_Alt` + fallback at +0x1C4 | `InitYarare_0x1F` |
| +0x310 | `int32[7]` | `pKnockbackPrimary` + fallback at +0x328 | `DispatchYarareReaction` knockback precompute |
| +0x32C | `int32[7]` | `pKnockbackSecondary` + fallback at +0x344 | same |
| +0x428 | `float[7]` | `pRingoutBaseDuration` + fallback at +0x440 | `TickYarare_0x2E_RingOut` state 0x19 timeout |

Knockback formula (`DispatchYarareReaction @ ~0x140352270`):

```
i             = clamp(vmCtx->dwHitIntensity, 0, 6)
primary       = paramBlock[+0x310 + i*4]
secondary     = paramBlock[+0x32C + i*4]
r             = vmCtx->flRngRoll1                  // unit (0..1)
scaledReach   = (1 - r) * primary + r * secondary
// then subtract per-charaKind reach offset from DAT_14470E330[CharaKindByte*0x180]
vmCtx->nScaledKnockbackReach = max(scaledReach - reachOffset, 0)
```

The block is the ONLY global parameter store for the reaction system —
patching it tunes every character's reaction reach and knockback at once.

---

## Reaction-state fields on `FLuxMoveCommandPlayer` (vmCtx)

Per-chara per-tick reaction state. The full layout is in
[Game Structures: FLuxMoveCommandPlayer](structures.md#fluxmovecommandplayer-12332-bytes);
the reaction-specific block is:

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x2AD0 | `u32` | `dwReactionKindBitmask` | `1 << n` via `YarareIdToReactionBitmask` |
| +0x2AD4 | `s16` | yarareId echo | |
| +0x2AD8 | `float` | `flRingout_EdgeReach` | per-case knockback target duration (3 / 30 / 60 / cos-rand-scaled) |
| +0x2B24..+0x2B2C | `u32[3]` | saved prior `{ActiveYarareId, ReactionTimer, ActiveYarareAce}` | replay buffer (3-slot) |
| +0x2B30 | `u32` | `dwActiveYarareId` | **the EYarareReactionId** |
| +0x2B34 | `float` | `dwReactionTimer` | counted up per Tick |
| +0x2B38 | `u32` | `dwActiveYarareAce` | `2 = idle`, `!=2 = active` |
| +0x2B4C | `u16` | active sentinel | `0xFFFF` for normal, `0x270F` (9999) for crumple |
| +0x2B68 | `u32` | sub-mode (0/4/9) | handler-specific |
| +0x2B74 | `u32` | sub-mode flag (0/4/8) | saved lane direction |
| +0x2B78..+0x2B9C | `u32[4]` | `dwRingout_*` | `YarareId`, `SuccessFlag`, `DirectionCode` |
| +0x2B90 | `u32` | combo-extension lane direction | |
| +0x2BD0..+0x2BF0 | `u32[8]` | lane-direction publish chain | `current → saved → published` |
| +0x2BC4 | `u32` | `dwPostEffectYarareId` | id chosen by picker, dispatched at tick tail |
| +0x2BC8 | `u32` | `dwPostEffectBodyPart` | |
| +0x2BF8 | `u32` | `dwHitIntensity` | clamped 0..6 by every consumer |
| +0x2C34 | `i32` | `nScaledKnockbackReach` | decremented each Tick; reaches 0 ⇒ publish stage |
| +0x2C44 | `u32` | post-effect tag | cleared on most exits |
| +0x2C48 | `u32` | post-effect dispatched | `1` = in post-effect chain (via `TickWithNotifTokenSwitch`) |
| +0x2C5C | `u32` | notif-token / post-effect index | |
| +0x2C90 | `u32` | opp-change re-eval flag | |
| +0x2CF4 | `float` | unknown/scratch | no write from `DispatchYarareReaction` in the 83-function static sweep |
| +0x2CF8 | `float` | `flPrimaryRoll` | primary dispatcher RNG sample |
| +0x2CFC | `float` | `flSecondaryRoll` | secondary dispatcher RNG sample |
| +0x3008 | `u32` | `dwBodyPartStash` | bodyPart of the latest hit |

---

## Exit conditions

A reaction terminates and writes `dwActiveYarareAce = 2` + clears
`dwActiveYarareId` and lane direction when ANY of the following triggers:

1. **Timer expiry** (most common): `dwReactionTimer >= flRingout_EdgeReach`
   AND post-effect gate clear (`+0x2C48 == 0`).
2. **Hitstun break**: chara no longer in hitstun (`bInHitstunFlag == 0`) AND
   not in blockstun.
3. **Combo re-dispatch**: `CheckYarareReactionGate(0x2D / 0x2F / 0x30)` opens
   mid-tick → current reaction clears, picker selects fresh next tick.
4. **Chained follow-up**: `TickYarare_0x2E_RingOut` state `0x1A` calls
   `DispatchYarareReaction` directly to chain a follow-up yarareId.
5. **Post-effect bridge**: `TickYarare_0x1B / 0x3C` with `+0x2C48` active →
   `LuxMoveVM_TickWithNotifTokenSwitch` for the post-effect token swap.
6. **Knockdown takeover**: knockdown-class yarareIds (`0x1E / 0x50 / 0x43`)
   activate `LuxCameraAction_ActivateKnockdown` which drives its own state
   machine until completion.

---

## Knockdown camera (adjacent state machine)

Triggered when a reaction enters knockdown class. It runs independently of the
yarare Tick and drives the post-knockdown procedural fall camera.

| Function | Address | Role |
|----------|---------|------|
| `LuxCameraAction_ActivateKnockdown` | `0x140327F20` | Entry. Picks procedural fall vs. authored cutscene based on `pCameraAction+0x3B0` knockdown-feature bitset and an RNG roll. |
| `LuxCameraAction_InitKnockdown` | `0x1403282F0` | One-shot init. RNG-rolls **25+ bit groups** for procedural variety (4-way Z-step direction × 4-way Z-magnitude × 3-way X / Y / roll, etc.). Authored moves can pre-set bits to force a specific look. |
| `LuxCameraAction_TickKnockdown` | `0x14032B380` | Per-tick advance. State machine on `pCameraAction+0x3A0`: `0=idle`, `1=tracking-mid-fall`, `2=lock-frame`, `4=finalize`. |
| `LuxCameraAction_LoadKnockdownCutsceneData` | `0x140328000` | Authored-cutscene path. |
| `LuxCameraAction_TickKnockdownOrCinematic` | `0x140328BC0` | Phase-dispatch wrapper. |
| `LuxCameraAction_Finalize` | (see Ghidra) | Resets weights at terminal phase. |

Key fields on `pCameraAction`:

| Offset | Field | Notes |
|-------:|-------|-------|
| `+0x28` | `nFrameTimer` | current elapsed time in this action |
| `+0x30` | action-active flag | `1` during knockdown |
| `+0x344` | `flStepRateA` | per-axis advance rate (set by bits 0x02/0x04/0x08/0x10 from `+0x3B0`) |
| `+0x348` | `flStepRateB` | per-axis advance rate (set by bits 0x40/0x80/0x100) |
| `+0x34C` | `flDecayFactor` | per-axis smoothing (bits 0x18..0x1B) |
| `+0x368` | `flOffsetZ` | per-tick accumulator |
| `+0x36C` | `flOffsetX` | per-tick accumulator |
| `+0x370` | `flOffsetY` | per-tick accumulator |
| `+0x374` | `dwDurationAnchor` | derived from `pPrimaryChara.flStature_44968` |
| `+0x388` | cutscene-active flag | `1 = authored`, `0 = procedural` |
| `+0x3A0` | `dwKnockdownPhase` | `0=idle, 1=tracking, 2=lock, 4=done` |
| `+0x3A4` | `dwDurationLimit` | target end-time (frames) |
| `+0x3B0` | `dwKnockdownFlags` | feature bitset — authored or RNG-rolled at Init |
| `+0x3B8` | `pPrimaryChara` | the chara whose knockdown this is |

Globals consumed:

| Symbol | Address | Role |
|--------|---------|------|
| `DAT_144846360` | — | `g_LuxBattle_RoundDecisionDeactivated` — suppresses knockdown activation. |
| `DAT_1440F4A84` | — | global "knockdown active" marker set by `ActivateKnockdown`. |
| `DAT_14470DEE4` | — | chosen procedural-variant index (debug / replay). |

---

## Throw-react state machine (camera side)

For the actual throw classifier and the small-vs-tall throw whiff, see
[Hitbox System: Throw connection / yarare dispatch](hitbox-system.md#throw-connection-yarare-dispatch).
The camera-side response runs in parallel:

| Function | Address | Role |
|----------|---------|------|
| `LuxEffectCamera_UpdateCameraFreezeDuringThrow` | `0x14031B760` | Edge-detects `chara+0x16F9 \| chara+0x16FA` (throw-active flag pair) and snapshots both charas' world positions on the rising edge. |
| `LuxEffectCamera_UpdateThrowCameraRotation` | `0x14031B880` | Per-tick lerp from snapshot toward fixed target offset (drives the camera "frozen" look). |

The throw-active flags `+0x16F9` / `+0x16FA` are written by the yarare
classifier when a throw resolves; the camera path is purely a consumer.

---

## Hook points (HorseMod / live-mod use cases)

| Want to know ... | Hook |
|---|---|
| "What yarare just got dispatched on me?" | Tail of `LuxBattle_DispatchYarareReaction @ 0x1403521B0` — read `vmCtx->dwActiveYarareId` and `vmCtx->dwBodyPartStash`. |
| "What kind of hit am I taking?" | Tail of `LuxBattleChara_ProcessHitReactionState @ 0x140342FF0` — read attacker's flag bitset at `+0x6DC..+0x824` (wiped every tick). See [hit-by tracker design](hitbox-system.md). |
| "Am I in active reaction this tick?" | Read `vmCtx->dwActiveYarareAce != 2`. |
| "Is the current reaction in the unconditional throw allow-set?" | Read `vmCtx->dwActiveYarareId`, test against `{0x0E..0x10, 0x1F, 0x20, 0x21, 0x2C..0x2D, 0x2E..0x31, 0x3B}`. |
| "Did a knockdown just trigger?" | Hook `LuxCameraAction_ActivateKnockdown @ 0x140327F20`. |
| "What's the active reaction reach budget?" | `vmCtx->nScaledKnockbackReach @ +0x2C34` (counts DOWN each Tick). |

---

## Adjacent visual subsystem

`LuxBattleChara_UpdateHitVisualLean @ 0x140308310` (formerly named
`UpdateCombatModeState`) is the visual-feedback driver for the `MutualHit_Loser`
(4) and `WallSplat` (0xB) states. It reads `chara+0x252` and `chara+0x1984`
(sub-state), writes a "lean amount" float to `chara+0x1B84` and
`chara+0x29158`, and dispatches VFX notifications via the global VFX dispatcher
`g_pLuxVfxDispatcher` (vtable+0x100).

It is not gameplay-critical. Modders are unlikely to need it unless changing
visual hit feedback.

---

## Key binary addresses (absolute, image base `0x140000000`)

### Pipeline
| Symbol | Address |
|--------|---------|
| `LuxBattle_ResolveAttackVsHurtboxMask22` | `0x14033C100` |
| `LuxBattleChara_ProcessHitReactionState` | `0x140342FF0` |
| `LuxMoveVM_TickPickAndDispatchReaction` | `0x1402DEF50` |
| `LuxBattle_DispatchYarareReaction` | `0x1403521B0` |
| `LuxMoveVM_TickActiveYarareReaction` | `0x14035EF30` |
| `LuxMoveVM_ProbeSpecialReactionOverride` | `0x1402DFD60` |
| `LuxMoveVM_RollComboExtensionReaction` | `0x1402E04A0` |
| `LuxBattle_YarareIdToReactionBitmask` | `0x14035F390` |
| `LuxMoveVM_CalcYarareWeightBonus` | `0x1402E07C0` |
| `LuxMoveVM_CheckActiveComboYarareState` | `0x140350BA0` |

### Reaction-pick filter chain (NOT documented in detail — see Ghidra)
| Symbol | Address |
|--------|---------|
| `LuxMoveVM_BuildReactionCandidateList` | `0x140363EF0` |
| `LuxMoveVM_FilterReactionCandidatesByTypeCode` | `0x140363F70` |
| `LuxMoveVM_FilterReactionCandidatesByPriorityByte` | `0x140364010` |
| `LuxMoveVM_FilterReactionCandidatesTopN` | `0x1403640A0` |
| `LuxMoveVM_FilterReactionCandidatesByStateBits` | `0x140364210` |
| `LuxMoveVM_FilterReactionCandidatesByFlagBits` | `0x140364340` |
| `LuxMoveVM_FilterReactionCandidatesByDistance` | `0x140364430` |
| `LuxMoveVM_FilterReactionCandidatesBySoulCharge` | `0x1403646D0` |
| `LuxMoveVM_WeightedSelectReactionCandidate` | `0x1403647C0` |
| `LuxMoveVM_SelectReactionSlot` | `0x140351BB0` |
| `LuxMoveVM_SelectAndCommitReactionSlot` | `0x140351B30` |

### Param block management
| Symbol | Address |
|--------|---------|
| `LuxMoveVM_AllocReactionParamBlock` | `0x1403306F0` |
| `LuxMoveVM_GetOrAllocReactionParamBlock` | `0x1403306C0` |
| `LuxMoveVM_InitReactionParamBlock` | `0x140330760` |
| `DAT_14470E018` | the 1100-byte param block (lazy-malloc'd) |

### Adjacent
| Symbol | Address |
|--------|---------|
| `LuxBattleChara_UpdateHitVisualLean` | `0x140308310` |
| `LuxMoveVM_SpawnCounterHitWindEffect` | `0x1402FC5B0` |
| `LuxBattle_PickRingoutReactionYarare` | `0x140353A00` |
| `LuxBattle_SetupRingoutFallVariant` | (see Ghidra) |
| `LuxBattle_ComputeHitReactionParams` | `0x140343B90` |
| `LuxBattleChara_ApplyHitReactionMove` | `0x1403448A0` |
| `LuxBattleChara_DecayHitstunSlideVelocity` | `0x140309160` |
| `LuxBattle_CheckReactionCancelClearance` | `0x140363D10` |
