# Random Functions and Gameplay Impact

**Goal**: explain which SoulCalibur VI random-number paths participate in the
battle simulation, which known paths are nondeterministic presentation details,
and how to investigate or modify them without breaking replays or online sync.

**Evidence source**: the existing Ghidra-backed investigations linked throughout
this page. All addresses are absolute for the documented executable (image base
`0x140000000`). A recovered name describes the behavior seen so far; it is not a
claim that every caller or every gameplay consequence has been mapped.

## The important split

SC6 does not have one interchangeable source of "randomness."

| Domain | What is established | Reproducibility requirement |
|---|---|---|
| Seeded Lux battle PRNG state | The battle code keeps LFSR-, xorshift96-, and LCG-style state. A host-broadcast seed is stored with replay data, and gameplay, CPU, VFX, and camera consumers reach Lux RNG helpers. | The initial seed, complete mutable RNG state, and the number and order of calls must match. |
| C runtime / audio randomness | Known audio paths use `rand()` or a run-dependent log-path seed. Audio output and instance handles may differ between viewings. | It is not part of the deterministic gameplay state documented so far. Do not use it to make gameplay decisions. |

The first row is **deterministic only as a state machine**. Supplying the same
seed is not enough after simulation begins: every draw advances some state. If
one peer, replay path, or rollback resimulation adds, removes, or reorders a
draw, later results can diverge even if the extra draw was originally intended
for a cosmetic effect. The rollback investigation therefore treats all battle
RNG globals as snapshot state until testing proves a particular state can be
excluded. See [Determinism from inputs](rollback-netcode-investigation.md#determinism-from-inputs).

The second row is intentionally allowed to vary. For example,
`LuxAudio_RegisterActiveVoiceInstance` uses `rand()` to produce a nonzero voice
handle, while `Audio_RandomTick` changes an audio-mix scalar. The documented
consumers do not feed those values back into combat. Ranked-match flavor voice
selection is also seeded from digits in the game log path, so it can choose a
different line on replay without changing the match. See
[Audio replay determinism](../sc6/audio-system.md#replay-determinism).

| Known nondeterministic path | Address | Documented effect |
|---|---:|---|
| `LuxAudio_RegisterActiveVoiceInstance` | `0x14054F8B0` | Uses `rand()` for a nonzero, non-colliding voice instance handle. |
| `Audio_RandomTick` | `0x140399B70` | Uses `rand()` for an audio-mix scalar when its gate is active. |
| `ALuxBattleChara_SelectAndPlaySound_Ranked` | `0x1403C8950` | Selects a pre-/post-round flavor line from a log-path-derived seed. |

These effects are documented as audio-only. That is scoped evidence about the
listed consumers, not proof that every unreviewed `rand()` call in the
executable is harmless.

!!! warning "Do not cross the streams"
    Never drive a move, hit reaction, CPU choice, stage state, or other gameplay
    branch from `rand()`, wall-clock time, an audio callback, or the log-path
    seed. Conversely, do not call the Lux battle RNG merely to vary a new sound
    or particle. Give mod-only presentation effects their own local PRNG state.

## Recovered battle RNG helpers

These are the named boundaries currently documented by the
[rollback investigation](rollback-netcode-investigation.md#determinism-from-inputs):

| Function | Address | Evidence-backed interpretation |
|---|---:|---|
| `LuxBattle_InitRngAndHashPrimes` | `0x14034F610` | Battle initialization boundary for RNG state and hash-prime setup. |
| `LuxMoveVM_GetRandU32` | `0x14034F130` | MoveVM-facing unsigned random-value helper. |
| `LuxMoveVM_GetRandXorshift96Gameplay` | `0x14034F1F0` | Advances/reads the gameplay xorshift96-style path. |
| `LuxMoveVM_GetRandLCG` | `0x14034F550` | Advances/reads the LCG-style path. |
| `LuxMoveVM_GetRandFloat01` | `0x14034F5E0` | MoveVM-facing random float helper. |
| `LuxMoveVM_CheckHeavyHitAndAdvanceRNG` | `0x140351840` | A recovered heavy-hit check that also advances RNG; its name does not prove every condition or downstream effect. |

The exact transition constants and output transformations are not documented
here. The evidence establishes multiple state families and recovered helper
boundaries, not a source-level specification of their algorithms. In
particular, do not replace these functions with a favorite textbook LFSR,
xorshift96, or LCG implementation merely because the family name matches.

Two snapshot facts are especially useful:

- `SetScbattleRoundSnapshotPayload @ 0x1402D77C0` and
  `GetScbattleRoundSnapshotPayload @ 0x1402D7730` copy a `0xC0` round-restore
  payload that includes gameplay xorshift state. The payload lives at
  `g_LuxBattleRoundSnapshotPayload @ 0x144844070`; it is not stage geometry.
- Replay data includes the host-broadcast seed associated with
  `g_scbattle_StageInfo_RngSeed @ 0x144844010`, alongside match settings and
  the per-frame input stream. See the
  [replay file outline](../sc6/leaderboards.md#replay-file-format-high-level)
  and the [stage round-restore correction](../sc6/stage-system.md#round-restore-storage-formerly-misidentified-as-stage-geometry).

Those facts do **not** prove that the `0xC0` payload contains every RNG state
needed for arbitrary mid-round rollback. The current rollback work explicitly
tracks LFSR, xorshift, and LCG state as additional snapshot/hash inputs.

## Gameplay-relevant consumers

"Impact" below means the consequence if a result or draw order changes. It does
not mean every named function has been proven to change competitive gameplay.

| Consumer category | Evidence | Confidence | Potential impact |
|---|---|---|---|
| Move transitions and hit reactions | `LuxMoveVM_EvaluateMoveTransition @ 0x14033E140` uses gameplay RNG for some hit/block/special-reaction branches. The hitbox analysis separately identifies a random weighted pick for non-throw reactions. `LuxMoveVM_CheckHeavyHitAndAdvanceRNG @ 0x140351840` is another recovered boundary, but its full conditions are not mapped here. | **High** that some transition/reaction paths consume battle RNG; **medium** for the complete set of player-visible outcomes. | **High** when the selected branch changes reaction, damage flow, position, timing, or the next legal move. |
| CPU action selection | The CPU system computes weighted action candidates and its per-frame Tick samples the pick array through VM RNG. In live CPU play, the chosen action becomes frame input. | **High** for live CPU selection. | **High** in CPU matches because a different choice changes the future input stream. In replay viewing, recorded input overwrites the still-running AI output, so that discarded choice is not the replay authority. |
| Stage seed and synchronization | Replay data stores the host-broadcast RNG seed. Online stage sync has the recovered sender `LuxOnlineBattleSync_SendStage_StageCode_IsRandom_RngSeed @ 0x14051FC80` and request path `LuxOnlineBattleSync_RequestStage_SendOpcode6 @ 0x14051DBC0`. | **High** that stage code/random metadata/seed are synchronized and recorded; **not proven here** that every stage-randomization decision uses the same mutable state. | **High** if peers start from different concrete stage data or battle seed: loading or simulation can diverge before ordinary inputs can reconcile it. |
| VFX and particles | `LuxEffectSystem_GetRandomVariantIndex @ 0x14038F6B0` uses gameplay xorshift. `LuxBattle_SpawnStageWindParticles @ 0x140334960` consumes Lux RNG and changes emitter timer/count state before allocating the particle. | **High** for the documented calls; **unproven** that every VFX choice affects gameplay. | Usually visual, but **high determinism risk** when it advances shared RNG state. Skipping the whole stage-wind function during resimulation changes later state. |
| Camera | `LuxCameraAction_RandomizeArenaOrbitParams @ 0x140327250` uses xorshift. | **High** for RNG consumption; **unproven** as a direct combat mechanic. | Primarily presentation in current evidence, but call-count drift can perturb a shared sequence. Rollback must snapshot gameplay-visible camera state or correct presentation safely. |

The move-transition claim is deliberately narrower than "hits are random."
Collision eligibility and most hit classification use deterministic per-frame
state; randomness appears only in some downstream branches. The
[hitbox gates](../sc6/hitbox-system.md#damage-requires-geometry-mask-and-phase) explain
the deterministic gates, while the documented
[random weight-pick](../sc6/hitbox-system.md#the-dispatch-allow-gate-root-cause-of-small-grabs-tall-whiff)
is specifically described as a non-throw reaction path.

Likewise, CPU RNG affects live decisions, but the replay system records the
resulting input stream. During replay viewing, decoded input replaces the CPU's
output before consumption. See [CPU replay determinism](../sc6/ai-cpu-system.md#ai-output-frame-input).

## Replay and rollback implications

For a same-build replay, the documented authority is the match configuration,
host seed, and recorded per-frame inputs. Gameplay can reproduce while audio
handles, mixer modulation, and flavor lines vary. Therefore a verifier should
compare gameplay state and RNG state, not raw audio output.

Rollback is stricter because it restores an earlier frame and executes the same
frames again:

1. Capture every battle RNG state consumed in the rollback window, not only the
   initial seed or the xorshift fields found in the round snapshot.
2. Restore RNG state at the same simulation boundary as character, MoveVM,
   hitbox, timer, stage, and input state.
3. Re-execute the original RNG calls in the original order. Suppress only the
   external presentation side effect, not the state advance that preceded it.
4. Journal or deduplicate audio/VFX/camera output so hidden resimulation does not
   double-play it.
5. Hash named gameplay fields and RNG states after every resimulated frame.

The stage-wind path demonstrates why a blanket "skip cosmetics during rollback"
hook is unsafe: the same function advances Lux RNG and internal emitter state
before creating the visible object. The correction policy is documented in
[Side effects and correction policy](rollback-netcode-investigation.md#side-effects-and-correction-policy).

!!! danger "Rule for mod authors"
    Do not add, delete, hoist, defer, or reorder calls to the stock Lux RNG on a
    simulation path. Do not make an existing call conditional on local graphics,
    audio, frame rate, wall-clock time, or one peer's configuration. A harmless-
    looking extra particle roll can shift a later CPU or reaction roll. If a
    gameplay modification intentionally changes RNG behavior, every peer, replay
    producer, and replay consumer must run the identical code and call schedule.

## Safe investigation workflow

Use an offline match or replay and a matching executable build. Keep the first
pass observational.

1. **Choose one helper and enumerate callers.** Start from the recovered
   functions above. For each call site, record the containing function, whether
   it runs inside `LuxBattle_PerFrameTick @ 0x1402DBC60`, and the returned value's
   first downstream branch or write. Do not label a caller "gameplay" merely
   because it is under the battle namespace.
2. **Log state, call order, and context.** At each helper entry/exit, record the
   absolute simulation frame, player slot if applicable, return address/call
   site, RNG state before and after, and result. Give every call a monotonically
   increasing per-frame ordinal.
3. **Establish a same-seed baseline.** Run the same replay twice on the same
   build and mod set. The battle-RNG trace and named gameplay hashes should
   match. Audio `rand()` values and flavor-line choices are expected exclusions.
4. **Classify consumers by data flow.** A value that selects a reaction, action
   id, state transition, timer, or collision-affecting write is gameplay-relevant.
   A value used only to select a cue handle or mixer scalar is presentation in
   the current evidence. Mark unresolved paths as hypotheses instead of guessing.
5. **Test one controlled difference offline.** Change only the candidate seed or
   one candidate call result in a disposable experiment, then compare call
   traces and named state fields. Do not take an altered client online.
6. **Verify restore/resimulation.** Save at frame `N`, run to `N + K`, restore,
   and run the same inputs again for `K = 1, 2, 8, 15, 60`. Compare per-frame
   gameplay hashes, all RNG states, and call ordinals. A first mismatch identifies
   the frame and call site to investigate.
7. **Audit side-effect gates.** Confirm that hidden resimulation still performs
   required RNG/timer mutations exactly once per simulated frame while external
   audio, particle allocation, camera presentation, and HUD output are suppressed
   or deduplicated.
8. **Repeat across boundaries.** Test round start, stage load, hitstop, a CPU
   match, a reaction with weighted alternatives, and VFX-heavy moves. Keep
   same-build/same-stage tests separate from compatibility experiments.

The rollback page's
[instrumentation checklist](rollback-netcode-investigation.md#instrumentation-to-add-first)
provides the complementary snapshot manifest, input history, frame-boundary
trace, and side-effect ledger. A hash mismatch after restore/resimulation is
evidence of missing state, a different call schedule, an uncontrolled side
effect, or a wrong frame boundary—not proof that the underlying PRNG is
nondeterministic.

## What remains hypothesis

- Whether cosmetic and gameplay consumers share every state family, or only
  some of them.
- Whether all RNG state needed for mid-round rollback has been found.
- The complete list of reaction outcomes and heavy-hit conditions controlled by
  RNG.
- Whether the documented camera choices ever feed a gameplay-visible branch.
- Whether any unreviewed `rand()` caller outside the known audio paths affects
  battle state.

Until call traces and restore/hash tests resolve those questions, preserve all
Lux battle RNG state and call ordering, and describe new consumers with scoped
confidence rather than treating every random-looking helper as a gameplay roll.
