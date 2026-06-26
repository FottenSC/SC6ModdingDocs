# Rollback Netcode Feasibility Investigation

**Goal**: decide whether SoulCalibur VI can support rollback-style online play,
what has to be snapshotted, and what the smallest useful prototype should test.

**Evidence source**: Ghidra MCP analysis of `SoulcaliburVI.exe`, plus local
prototype context under `E:/myMods`. The Ghidra database is the authority for
symbol names, offsets, and addresses below. The local files are supporting
implementation context, not proof by themselves.

## Verdict

Rollback is plausible as a native prototype, but not as a Blueprint/reflection-only
mod. SC6 already has a deterministic-looking fixed-frame Lux battle simulation,
input caches, replay input streams, per-round reset blobs, and native
HgCpuDirect save/restore helpers. Those are the right ingredients.

The stock online mode is still delay/catch-up based. It queues remote inputs
into `ALuxBattleFrameInputLog`, advances a master-clock driven simulation loop,
and stalls or drains when remote frames are missing. No Lux gameplay rollback
path was found; `Rollback` strings in the binary belong to UE engine/demo-net
support or unrelated libraries.

The hard part is not "can a frame be simulated again?" The hard part is proving
that the full gameplay state can be restored byte-for-byte enough for repeated
resimulation without leaking UE actor ticks, animation notifies, audio/VFX,
camera state, or RNG advances into the visible world.

Practical verdict:

| Question | Current answer |
|---|---|
| Is rollback theoretically feasible? | Yes, if native hooks can own the input boundary and state restore boundary. |
| Is it proven deterministic from inputs alone? | Not yet. Static analysis says "likely within a round"; a hash round-trip test is still required. |
| Can the stock online protocol be reused unchanged? | No. It only carries small input packets and 4-bit frame-low tags; rollback needs prediction, absolute frames, confirmations, and state hashes. |
| Is a scripting/reflection layer enough? | No. Frame stepping, snapshots, cache injection, and side-effect gates need native DLL hooks. |
| Best first prototype | Offline/local rollback lab in `E:/myMods/HorseMod`: snapshot, advance N frames, restore, resimulate, compare hashes. |

## Current online input path

The online input path is centered on `ALuxBattleFrameInputLog` at
`BM+0x478`. That actor owns the replay/online input cache at `InputLog+0x3C0`,
the online inbound packet deque at `InputLog+0x4480`, and the master clock at
`InputLog+0x3A4`.

Confirmed send path:

```text
LuxOnline_SendInputPacket_PerFrame_Opcode0 @ 0x1403F84E0
  builds a 3-byte channel-5 packet for one frame/slot
  low header bits: frameId & 0x0F
  high header bits: playerSlot << 4
  opcode: 0
  payload: one input byte

LuxOnline_SendInputPacket_BatchedRange_Opcode1 @ 0x1403F8710
  resends a window [nCurrentFrame - nWindowFrames, nCurrentFrame)
  reads pInputLog->pReplayInputCache[slot * 0x200 + (frame & 0x1FF)]
  stops if frame id/index mismatch or bFilled == 0
```

Confirmed receive/drain path:

```text
LuxOnline_PushToRingBuffer_WithCriticalSection @ 0x1403F4BE0
  network-thread receive entry
  locks InputLog+0x44A8
  pushes packet wrappers into the deque at InputLog+0x4480
  caps the deque at 100 entries and drops oldest entries past the cap

LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770
  game-thread drain
  requires dwOnlineRemoteRole != 0 and bSessionShutdownState != 5
  pops queued packet wrappers under the same InputLog+0x44A8 lock
  opcode 0 updates the sent-input bitmap
  opcode 1 writes pReplayInputCache[slot][frame & 0x1FF]
```

The cache reader used by battle simulation is:

```text
GetCachedInputForFrameInputLogSlot @ 0x1403F0720
  uint GetCachedInputForFrameInputLogSlot(
      ALuxBattleFrameInputLog *pInputLog,
      uint dwPlayerIdx,
      int nFrameID,
      uint dwFrameIndex)
```

It indexes `pReplayInputCache[(dwFrameIndex & 0x1FF) + dwPlayerIdx * 0x200]`
and returns `dwInputValue` only when both `nFrameID` and `dwFrameIndex` match.
It does not check `bFilled`; the tag match is the effective validity check.

The chara-side consumer is:

```text
LuxBattleChara_UpdatePlayerInputData_FromRoundCache @ 0x1403FCD10
  called from the BattleManager simulation loop
  reads frame (pInputLog->nMasterClock - nFramesBack) - 1
  writes BM current-input and edge-input arrays around BM+0x1498 / BM+0x14A8
```

The per-frame driver is:

```text
LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520
  reads InputLog+0x3A4 nMasterClock
  mirrors InputLog+0x3A0 nLastFrameId into BM+0x1488
  computes delta = masterClock - lastAppliedClock
  for each delta frame:
    LuxBattleChara_UpdatePlayerInputData_FromRoundCache(...)
    round-state processing
```

So the current online path is:

```text
local input -> InputLog cache -> send opcode 0/1 packets
remote packet -> locked deque -> game-thread drain -> InputLog cache
InputLog master clock -> BattleManager simulation loop -> chara input state
```

## Where delay-based netcode is enforced

The live delay is not the `InputDelay` UProperty.

Confirmed:

- `ALuxBattleFrameInputLog+0x390` is the reflected `InputDelay` property, but
  observed builds leave it at zero. Its known writer is constructor zero-init.
- `GetCachedInputForFrameInputLogSlot @ 0x1403F0720` can subtract that field
  when a vtable predicate returns true, but the subtraction is a no-op when the
  field is zero.
- The separate `InputDelayFrame` option belongs to `LuxBattleOptionParam`, not
  the live `ALuxBattleFrameInputLog` cache path.
- The old 8WAYRUN-style NOP around `0x1403F0751` is therefore a placebo for
  observed builds.

The real delay/catch-up behavior is in timing and cache availability:

- `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`
  advances only by the master-clock delta visible through `InputLog+0x3A4`.
- `GetCachedInputForFrameInputLogSlot @ 0x1403F0720` returns zero when the cache
  tag for the requested frame does not match.
- `LuxOnline_SendInputPacket_BatchedRange_Opcode1 @ 0x1403F8710` resends cached
  windows rather than rewinding simulation.
- `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770`
  fills future/remote cache slots from the drained network queue.
- `LuxBattleManager_UpdateOnlineFrameSyncCounter_At1638 @ 0x1403FDEC0`
  increments `BM+0x1638` when online, active, in round sequence state 2, and
  `nDeltaFrames == 0`. After more than 9 stalls it commits an event counter at
  `BM+0x163C` and resets. This is stall telemetry/sync handling, not rollback.

Confirmed absence:

- Ghidra string/function search did not find Lux gameplay rollback names.
- UE `RollbackNetStartupActorInfo` is engine/demo-net scaffolding, not SC6's
  battle netcode.

## Determinism from inputs

Static analysis supports a working hypothesis: within one active round, the core
Lux battle simulation is mostly deterministic if the same inputs, RNG state,
stage data, timers, and battle state are restored.

Important deterministic-looking paths:

```text
LuxBattle_PerFrameTick @ 0x1402DBC60
  top-level fixed battle frame:
  input mirrors, MoveSystem/MoveVM, chara input, state snapshot/round decision,
  chara main simulation, launcher sync, KHit/body collision, VFX/camera/stage
  wind, auto-advance, and g_LuxBattle_FrameCounter increment

LuxMoveSystem_PumpVMSlots @ 0x14031D460
  pumps queued MoveVM requests through start/tick/reaction substates

LuxBattle_TickCharaMainSimulation @ 0x14034DA70
  per-chara guard/movement, VM op-stream lanes, physics integration, terrain
  contact, damage/behavior locks, and state finalization

LuxBattle_TickHitResolutionAndBodyCollision @ 0x14033CCA0
  KHit damage, body collision, attack descriptor copies, hot masks, hurtbox
  resolution, and mutual-hit arbitration

LuxMoveVM_ClassifyHitboxFrameState @ 0x140300620
  writes chara active/startup/recovery phase and hitbox timing fields

LuxMoveVM_EvaluateMoveTransition @ 0x14033E140
  hit/block/special reaction classifier; uses gameplay RNG for some branches
```

RNG must be part of the snapshot:

```text
LuxBattle_InitRngAndHashPrimes @ 0x14034F610
LuxMoveVM_GetRandU32 @ 0x14034F130
LuxMoveVM_GetRandXorshift96Gameplay @ 0x14034F1F0
LuxMoveVM_GetRandLCG @ 0x14034F550
LuxMoveVM_GetRandFloat01 @ 0x14034F5E0
LuxMoveVM_CheckHeavyHitAndAdvanceRNG @ 0x140351840
```

The game uses at least LFSR, xorshift96, and LCG-style states. Some calls are
gameplay-relevant; others feed camera or effect variation. Treat all battle RNG
globals as snapshot state until a hash test proves otherwise.

Stage collision is promising for deterministic rollback:

```text
SetScbattleStageInfoBarrierGeometry @ 0x1402D77C0
GetScbattleStageInfoBarrierGeometry @ 0x1402D7730
```

These functions write/read exactly 12 `scbattle_BarrierEntry` records,
`0xC0` bytes total, through `g_aScbattleStageInfoBarrierEntries`. That fixed
barrier block is more rollback-friendly than arbitrary UE mesh collision.

Unproven parts:

- Whether every state byte used by `LuxBattle_PerFrameTick` is covered by the
  native HgCpuDirect save/restore helpers.
- Whether cosmetic RNG calls share state with gameplay RNG in ways that can
  perturb later gameplay branches.
- Whether UE actor/component ticks outside the Lux battle frame can mutate state
  between restore and resimulation.
- Whether online-only UI/debug/session logic changes battle state during stalls.

## Snapshot state

A rollback snapshot needs more than visible character transforms. Minimum state:

| Region | Why it matters |
|---|---|
| `ALuxBattleManager` | Round state, player records, current input arrays, timers, status, per-round state. |
| Both `ALuxBattleChara` instances | Move state, pose, health, guard, input history, physics, hit reaction, MoveVM-owned state. |
| MoveVM / MoveSystem globals | Pending VM requests, op-stream lanes, action transitions, queued reactions. |
| Hitbox/KHit/body collision state | Active attack descriptors, hurtbox masks, body collision, pending damage. |
| Timers and frame counters | Round timers, hitstop, master clock, frame id, global battle frame counter. |
| RNG globals | LFSR/index, xorshift96, LCG, and any helper state consumed by gameplay or camera/effects. |
| Stage state | Deterministic scbattle barrier block, terrain/contact flags, breakable wall/barrier state. |
| Input buffers | `ALuxBattleFrameInputLog` cache, cache tags, current-input mirrors, cursors, sent-input bitmap. |
| Round-start data | Per-round reset blobs and transition state for preventing rollback across object lifecycle boundaries. |
| One-way side-effect fences | Audio/VFX/camera/HUD/animation notify state, or suppression masks for resim frames. |

The most useful native primitives found so far are:

```text
LuxBattle_HgCpuDirect_ExecMoveChangeAndPost @ 0x1403841E0
  snapshot writer

LuxBattle_HgCpuDirect_ExecFinalizeAndPost @ 0x140384540
  restore counterpart
```

Those helpers serialize/restore large battle regions: P1/P2 chara state,
selected globals, camera, timers, motion, physics, terrain query flags, VFX, and
pointer fixup descriptors. Local `E:/myMods` ReplayScrub work estimates the
HgCpuDirect sim blob at `0x28018` bytes, plus an `ALuxBattleFrameInputLog`
window of roughly `0x4084` bytes and smaller extras.

Do not assume HgCpuDirect is complete for online rollback. It likely needs
extras for:

- `g_LuxBattle_LatestEngineInput_PerPlayer`
- input ring/cursor globals used by `LuxBattle_PerFrameTick`
- `ALuxBattleFrameInputLog` cache/cursors/sent bitmaps
- LFSR/xorshift/LCG RNG state
- online session/drain cursors if the stock online path remains active

## Reusing replay and state systems

SC6's replay systems are useful, but they are not rollback by themselves.

Replay input stream evidence:

```text
LuxReplay_DecodeInputPackets_FromFile @ 0x1403ED310
  decodes 3-byte replay records into 8-byte decoded input records
  opcodes: frame, cursor, emit range, P1 input, P2 input, stop

LuxReplay_EncodeInputEvents_ToBuffer @ 0x1403ED980
  inverse encoder for replay input events

LuxReplay_WriteThreeByteInputRecord_ToBuffer @ 0x1403F62E0
  appends one 3-byte replay input record
```

Replay round-reset evidence:

```text
ALuxBattleReplayPlayer_Tick_CopyRoundResetSnapshotAndSetMoveState4 @ 0x140435C20
  copies 0xC0 bytes of FLuxBattleRoundStartData from ReplayPlayer+0x3A8
  into BattleManager+0x1360
  then calls ALuxBattleManager_SetMoveState(..., 4)
```

This is useful for round reset and replay viewing. It is not a per-frame
rollback snapshot.

Types inspected:

| Type | Size | Rollback relevance |
|---|---:|---|
| `ALuxBattleFrameInputLog` | ~17616 | Online/replay input cache, master clock, drain deque, sent bitmap. |
| `FLuxReplayInputCacheEntry` | 16 | `{ nFrameID, dwFrameIndex, dwInputValue, bFilled }` cache cell. |
| `ALuxBattleReplayPlayer` | 977 | Replay round cursor, round-start blobs, replay playback state. |
| `FLuxRecordedFrame` | 192 | Opaque recorded-frame structure; not proven to be a complete live snapshot. |
| `FLuxBattleRoundStartData` | 192 | Per-round reset blob copied into `BM+0x1360`. |
| `FLuxBattleRecordingData` | 16 | Replay round pointer/count/capacity wrapper. |
| `FLuxBattleCharaReplayInputOverlay` | 17446 | Chara-side replay input ring, separate from online `FrameInputLog` cache. |

Confirmed distinction: the chara-side replay overlay
`LuxBattleChara_ReplayPlayback_PushInputsToActiveSlots @ 0x1403F6600` uses an
embedded ring at `chara+0x3C0`; the online path uses
`ALuxBattleFrameInputLog+0x3C0`.

## Rewind and resimulation plan

Safe rollback needs to control one exact frame boundary:

1. Drain or bypass stock online packets.
2. Write/predict both players' inputs for the target frame.
3. Snapshot the current stable frame.
4. Advance simulation exactly one frame.
5. If a remote input arrives late, restore an earlier snapshot.
6. Patch the corrected remote input into the input history.
7. Resimulate frame-by-frame until current time.
8. Release only the final visible frame's side effects.

The likely native stepping target is `LuxBattle_PerFrameTick @ 0x1402DBC60`.
If that is too broad for online insertion, the narrower
`LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`
can drive the stock `ALuxBattleFrameInputLog` / BattleManager catch-up route,
but it may miss side effects that the full battle frame expects to occur around
it.

Rollback must respect existing gates:

- `InputLog+0x3A4` master clock must not run ahead during a frozen/restore
  window.
- `ALuxBattleFrameInputLog` actor ticks and `vtable[0x5F8]` sub-ticks must not
  double-advance caches while resim is manually stepping.
- `LuxMoveVM_GetTimeDilationScalar @ 0x14030A8C0` shows chara simulation can
  bypass some global freeze behavior, so time-dilation gates are not enough by
  themselves.
- The BattleManager main state machine may still perform round-over and
  lifecycle transitions around the simulation loop.

Do not roll back across round creation/destruction boundaries in a first
prototype. Keep rollback windows inside active round state only.

## Predicted remote inputs

Predicted remote inputs can probably be injected cleanly, but only at a
game-thread-owned boundary.

The cache format is simple:

```c
struct FLuxReplayInputCacheEntry { // 0x10
    int  nFrameID;      // +0x00
    uint dwFrameIndex;  // +0x04
    uint dwInputValue;  // +0x08
    byte bFilled;       // +0x0C
};
```

The online cache address is:

```text
pInputLog->pReplayInputCache[slot * 0x200 + (frameIndex & 0x1FF)]
```

A native prototype can inject prediction by writing the correct `nFrameID`,
`dwFrameIndex`, `dwInputValue`, and `bFilled` for the remote slot before
`LuxBattleChara_UpdatePlayerInputData_FromRoundCache @ 0x1403FCD10` reads it.

The race to avoid:

- `LuxOnline_PushToRingBuffer_WithCriticalSection @ 0x1403F4BE0` runs on the
  network side and only owns the inbound deque.
- `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770`
  writes the cache on the game thread.
- Cache readers are not protected by the deque lock.

Therefore, prediction should be inserted after the stock drain and before the
BattleManager consumes the cache, or the prototype should bypass the stock
online drain entirely for controlled tests. Do not write the cache from a
network thread.

The stock packet format is also too weak for full rollback transport:

- opcode 0 carries only one input byte and a 4-bit frame-low id
- opcode 1 resends a cached range, but still relies on stock cache tags
- no state hash, input confirmation, prediction age, or absolute frame id was
  found in the packet hot paths inspected here

## Side effects and correction policy

Rollback should correct gameplay state, not replay every transient side effect
blindly.

| System | Policy |
|---|---|
| Gameplay state | Restore and resimulate exactly. |
| Audio | Suppress during resim; play final-frame events only where possible. `Audio_RandomTick @ 0x140399B70` uses C `rand()` for audio mix variation. |
| VFX / particles | Suppress or kill/recreate on corrected final frame. `LuxEffectSystem_GetRandomVariantIndex @ 0x14038F6B0` uses gameplay xorshift. |
| Camera | Snapshot if gameplay-visible; otherwise smooth-correct. `LuxCameraAction_RandomizeArenaOrbitParams @ 0x140327250` uses xorshift. |
| HUD/debug/online UI | Do not drive from resim frames; update from final authoritative frame. |
| Animation notifies | Gate notifies during hidden resim or dedupe them by frame/event id. |
| UE actor/component ticks | Prevent unrelated ticks from mutating battle state during manual resim. |

The safest first prototype runs with side effects muted during hidden
resimulation and compares only gameplay-state hashes.

## Native hooks, not reflection wrappers

A lightweight tool layer can still help with:

- configuration
- UI/debug overlays
- logging and test controls
- calling exposed UFunctions through a native bridge, where that is useful

Native hooks are required for:

- inline hooks on non-UFunction battle functions
- capturing/restoring large native memory regions
- controlling exact frame/input boundaries
- preventing actor ticks and master-clock increments during restore/resim
- writing `ALuxBattleFrameInputLog` cache entries safely
- transport integration beyond stock 3-byte packets

Current local context under `E:/myMods` already points the prototype path toward
HorseMod/native DLL work rather than a reflected-call control layer.

## Minimal feasibility prototype

Start offline. Do not start by touching real online matchmaking.

1. In `E:/myMods/HorseMod`, add a rollback lab mode that only runs in local
   battle/replay-safe contexts.
2. Capture a stable active-round snapshot after both players and stage are
   fully initialized.
3. Include HgCpuDirect state plus explicit extras: input cache/cursors, latest
   input globals, RNG globals, frame counters, and BattleManager input arrays.
4. Record both players' input stream for a deterministic window.
5. Step `LuxBattle_PerFrameTick @ 0x1402DBC60` exactly one frame at a time.
6. Hash the gameplay state after each frame. Start with chara health/position,
   MoveVM state, KHit state, timers, RNG, and selected BattleManager fields.
7. Restore frame `N`, resimulate to frame `N + K`, and compare hashes for
   `K = 1, 2, 8, 15, 60`.
8. Repeat using the narrower
   `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`
   only if the full tick is too difficult to isolate.
9. Add artificial remote-input delay locally: predict "held last input", then
   correct a delayed remote input and verify the final hash matches the no-delay
   baseline.
10. Only after local hashes pass, design a transport with absolute frame ids,
    confirmations, prediction age, and periodic state hashes.

Pass condition:

```text
same initial snapshot + same input stream + restore/resim window
  -> identical gameplay hash at the same final frame
```

Failure condition:

```text
hash mismatch after restore/resim
  -> missing snapshot state, uncontrolled side effect, RNG leak, or wrong frame boundary
```

## Testing methodology

Treat rollback as unproven until the tests below make it boring. Static
analysis identifies likely frame, input, snapshot, and RNG boundaries; the test
harness has to prove or falsify those boundaries with repeatable data.

The first rule is scope control. All positive results should be same-build,
same-mod-set, same-stage, same-round tests unless the test explicitly targets a
boundary fault. Do not count cross-round restore, actor recreation, or online
session recovery as supported until those cases have their own passing tests.

### Instrumentation to add first

Build the instrumentation before building correction logic. Otherwise every
hash mismatch becomes guesswork.

| Instrument | What to record | Why it matters |
|---|---|---|
| Per-frame gameplay hash | Frame id, master clock, selected `ALuxBattleManager` fields, both chara states, MoveVM state, KHit/body collision state, round timers, input mirrors, RNG state, and stage/barrier state. | This is the main determinism oracle. Start broad, then only exclude bytes after a named investigation proves they are nondeterministic and non-gameplay. |
| Input-history log | Local input, remote input, predicted/confirmed bit, source slot, absolute frame, `nFrameID`, `dwFrameIndex`, and cache cell address. | Lets a mismatch be tied to the exact input the sim consumed, not the input the rollback controller intended to provide. |
| Snapshot manifest | Snapshot id, source frame, HgCpuDirect blob hash, InputLog/cursor region hashes, extras region hashes, buffer size, restore target pointers, and pointer/lifetime validation result. | Prevents treating "restore succeeded" as proof that the right object graph was restored. |
| RNG state log | LFSR/xorshift/LCG states before and after each frame, plus optional call counters around `LuxMoveVM_GetRandU32 @ 0x14034F130`, `LuxMoveVM_GetRandXorshift96Gameplay @ 0x14034F1F0`, and related helpers. | Distinguishes missing state from an extra cosmetic/gameplay RNG consume. |
| Frame-boundary trace | Entry/exit for `LuxBattle_PerFrameTick @ 0x1402DBC60`, `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`, `ALuxBattleFrameInputLog` tick/drain sites, `InputLog+0x3A4`, `BM+0x1488/+0x148C/+0x1490`, and `g_LuxBattle_FrameCounter`. | Proves that every trial advanced exactly the intended number of simulation frames. |
| Side-effect event ledger | Audio, VFX, camera action, HUD/debug, animation notify, and actor tick events, tagged as visible-frame or hidden-resim. | Rollback can pass gameplay hashes and still double-play visible side effects. |
| Network fault log | Fault type, affected peer/slot, original arrival frame, injected arrival frame, packet/input contents, packet sequence if available, and whether the cache write was stock drain or test harness. | Makes injected latency/loss/reorder reproducible and separates transport faults from simulation faults. |
| Rollback/resim metrics | Snapshot save/restore microseconds, frames resimulated, max correction depth, hash compare time, dropped visible frames, side effects suppressed, and final catch-up latency. | Feasibility is not only correctness; the correction path must fit a real frame budget. |

The hash should be canonical, not a raw "hash every byte near the objects"
shortcut. Pointer values, allocator noise, telemetry counters, and padding bytes
can cause false failures. Exclude them only after they are listed in the
snapshot manifest with the reason they are safe to ignore.

### Phased test plan

Each phase should produce machine-readable logs and a short human summary. A
phase does not prove rollback globally; it only unlocks the next, riskier test.

| Phase | Test | Method | Pass criteria | Fail criteria |
|---|---|---|---|---|
| 0 | Baseline capture | In offline active-round play, record a no-rollback run for fixed characters, stage, costumes, settings, mod manifest, and input stream. Capture hashes and instrumentation every frame. | Replaying the same baseline setup without restore produces identical gameplay hashes for the tested window, or all differences are named non-gameplay fields. | Hash drift with no restore, unstable frame counts, unresolved actor pointers, or input-history disagreement. |
| 1 | Deterministic replay harness | Feed the same recorded input stream through the chosen one-frame boundary, starting with `LuxBattle_PerFrameTick @ 0x1402DBC60` and falling back to the BM/InputLog path if needed. | Frame count, input consumption, RNG state, and gameplay hash match the baseline at each compared frame. | Off-by-one cache reads, master-clock drift, RNG drift, or a match only when comparing coarse fields such as health/position. |
| 2 | Snapshot/restore hash tests | Capture snapshot `S`, restore it immediately, and compare pre-restore/post-restore hashes before any frame advances. Repeat at quiet frames, active attacks, hitstop, guard impact, wall contact, and camera/VFX-heavy frames. | Immediate restore is byte-for-byte or manifest-equivalent for gameplay state, and no visible side-effect ledger entries are emitted by restore alone. | Restore mutates gameplay state, misses InputLog/cursor/RNG/stage data, revives stale actor pointers, or emits visible events. |
| 3 | Resimulation equivalence | Capture at frame `N`, advance `K` frames, restore `N`, replay the same inputs for `K = 1, 2, 8, 15, 60`, and compare final and per-frame hashes. | Every final hash matches the no-restore path, and per-frame traces show exactly `K` simulated frames with matching inputs and RNG. | Any unexplained hash mismatch, extra/missing tick, side-effect leak during hidden frames, or a result that only passes for `K = 1`. |
| 4 | Prediction/correction | Delay a known remote input inside the local lab, predict "held last input" or neutral, then correct the frame when the real input arrives. Compare against a no-delay authoritative baseline. | After restore/resim, final gameplay hash equals the authoritative baseline, prediction age is logged, and hidden resim side effects are suppressed or deduped. | Corrected state diverges, rollback depth is wrong, the wrong cache cell is patched, or visible side effects replay from discarded frames. |
| 5 | Online-drain isolation | In native hooks, prove the rollback controller owns the input boundary: stock drain either runs before prediction injection or is bypassed in the lab. Never write cache entries from the network thread. | `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770` and prediction writes have deterministic ordering, cache tags match the intended absolute frame, and late packets cannot overwrite confirmed history incorrectly. | Races between drain and cache readers, stock parser overwriting predictions after simulation consumed them, deque growth hiding test faults, or thread-side writes into live cache. |
| 6 | Side-effect gating | Run the same correction with side-effect gates enabled and disabled. Use the event ledger to verify audio/VFX/camera/HUD/notifies/actor ticks only escape from final visible frames. | Gameplay hashes match with gates enabled, hidden-resim event counts are zero or explicitly deduped, and final-frame events are not lost. | Duplicate audio/VFX, camera pops caused by hidden frames, actor tick state mutation outside the snapshot, or gameplay hash changes when presentation-only gates are toggled. |
| 7 | Stress/soak | Run long local sessions with randomized but seeded input, random fault schedules, maximum rollback windows, stage interactions, hitstop-heavy sequences, and repeated round starts that rollback refuses to cross. | No unexplained hash mismatches, bounded memory, stable restore/resim timing, no stale pointers, no rollback across refused lifecycle boundaries, and useful diagnostics on every injected fault. | Intermittent drift, growing snapshot memory, correction time over budget, actor lifecycle crashes, or a failure that cannot be reproduced from logs. |

### Fault injection

Fault injection should be deterministic. Every injected fault needs a seed, a
frame number, a target slot, the original input/packet metadata, and the exact
mutation written to the log. A fault that cannot be replayed is only a bug
report, not a rollback test.

The offline lab in `E:/myMods/HorseMod` can safely inject many faults before
real networking exists. Use a game-thread test controller that edits the input
history, `FLuxReplayInputCacheEntry` cells, clocks, or gates at known frame
boundaries. Do not mutate the live online cache from a network thread.

| Fault | Offline HorseMod lab | Native online/transport hook needed | Pass/fail signal |
|---|---|---|---|
| Dropped input packets | Safe to model by withholding the remote input from the rollback controller while retaining the authoritative baseline input in the test script. | Required to prove real packet loss handling before shipping online. | Pass: prediction is used, correction restores the right frame, final hash matches baseline. Fail: stall, wrong rollback depth, or missing correction. |
| Delayed remote inputs | Safe and essential: deliver frame `F` at `F + delay` with delays from 1 to max rollback window plus one. | Required to measure real jitter and queue behavior. | Pass: delays within the window correct; delays beyond the window trigger a defined stall/desync policy. Fail: silent divergence or unbounded catch-up. |
| Reordered packets | Safe to model by delivering remote inputs out of order to the input scheduler. | Required if using or extending the stock online parser/deque. | Pass: absolute frame id wins over arrival order. Fail: lower frame-low tags overwrite newer cache cells. |
| Duplicate packets | Safe to inject as repeated confirmed inputs for the same absolute frame. | Required for real transport dedupe validation. | Pass: duplicate is idempotent and logged. Fail: duplicate increments metrics, rewrites confirmed history differently, or triggers extra rollback. |
| Corrupted cache tags | Safe in offline cache-path tests by mutating `nFrameID`, `dwFrameIndex`, or `bFilled` in one `FLuxReplayInputCacheEntry`. | Not a transport fault by itself, but online hooks should guard malformed decoded records. | Pass: tag mismatch is detected as missing/invalid input and does not masquerade as neutral unless policy says so. Fail: stale cell is consumed as valid input. |
| Wrong frame IDs | Safe to inject in the local input-history layer and in cache cells. | Required for stock packet compatibility because opcode 0 only carries a 4-bit frame-low tag. | Pass: rollback protocol rejects or disambiguates the frame. Fail: input lands in the wrong 512-cell ring slot. |
| Stale predictions | Safe: keep an old predicted remote input across a known change and correct later. | Required to tune prediction age and confirmation policy online. | Pass: stale prediction age is logged, corrected, and bounded. Fail: old prediction becomes confirmed by accident. |
| Master clock jumps/stalls | Safe with HorseMod-style clock gates around `InputLog+0x3A4` and manual test writes in offline lab. | Required to see how real online stall/drain logic interacts with rollback ownership. | Pass: unexpected jumps/stalls are detected before simulation, and rollback refuses or repairs according to policy. Fail: `BM+0x1488/+0x148C/+0x1490` drift from `InputLog+0x3A4`. |
| Skipped/double ticks | Safe by deliberately suppressing or double-running one controlled frame in the harness. ActorTickGate-style sites are useful for reproducing sibling-tick leaks. | Required only to validate integration with live UE actor tick order. | Pass: frame-boundary trace catches the extra/missing tick immediately. Fail: hash drift appears later with no clear tick anomaly. |
| RNG perturbation | Safe in lab by flipping/restoring a logged RNG state or by inserting one extra traced RNG consume in a controlled test build. | Not transport-specific, but online testing must prove both peers keep identical RNG. | Pass: hash mismatch points at the first divergent RNG state/call. Fail: mismatch is delayed or only visible through gameplay later. |
| Side-effect leaks | Safe by temporarily disabling a side-effect gate for one hidden resim frame. | Required online because correction may happen under real rendering/audio load. | Pass: event ledger identifies the leaked event and gates prevent it in normal tests. Fail: duplicate visible effects, camera discontinuity, or gameplay-affecting notify mutation. |
| Round transition boundary faults | Safe only as a refusal test: schedule corrections near KO, round end, replay reset, or object teardown and verify rollback does not cross the lifecycle boundary. | Required before any online prototype can survive real rounds. | Pass: rollback refuses, stalls, or resyncs with an explicit reason. Fail: restore into freed/recreated chara or stage objects. |
| Actor lifecycle invalidation | Do not fake freed pointers. Safe tests are pointer/lifetime validation failures captured from natural transitions or controlled refusal cases. | Required for real online exits, rematches, loading, and disconnects. | Pass: snapshot manifest marks the target invalid and restore is blocked. Fail: restore writes into stale actor memory. |
| Stage state mutation | Safe if limited to known deterministic stage state, such as the scbattle barrier block, or a tracked lab-only mutation. | Required for modded stages and online stage-object interactions. | Pass: mutation is either snapshotted/restored or detected as unsupported. Fail: same inputs diverge after wall/barrier/contact changes. |
| Mod mismatch | Safe to model with manifest mismatch, hash mismatch, or altered test constants; avoid silently changing live assets mid-run. | Required in real transport before matchmaking/handshake. | Pass: peers refuse rollback or mark desync before gameplay correction. Fail: different gameplay data produces plausible but divergent hashes. |

Offline-safe does not mean low-risk. Keep these tests behind an explicit lab
mode and only run them on the game thread at known frame boundaries.

### Where to hook and what not to trust

For the offline lab, the cleanest first hooks are the same ones used by the
minimal prototype:

- capture before and after `LuxBattle_PerFrameTick @ 0x1402DBC60`;
- if using the stock cache path, inject after
  `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770`
  and before `LuxBattleChara_UpdatePlayerInputData_FromRoundCache @ 0x1403FCD10`;
- trace `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`
  whenever `ALuxBattleFrameInputLog` or BM cursors are involved;
- use HorseMod's ReplayClockGate/ActorTickGate lessons as a checklist for
  sibling ticks that can mutate state while the main battle frame is frozen.

Do not trust:

- visual similarity;
- health/position-only hashes;
- the HgCpuDirect blob by itself;
- wall-clock timing as a frame counter;
- stock online frame-low tags as absolute frame identity;
- a successful restore return without pointer/lifetime validation;
- a passing quiet-frame test as proof for hitstop, wall contact, VFX-heavy
  frames, or round boundaries.

To reduce false positives, pin every variable that is not under test: same SC6
build, same HorseMod build, same gameplay-affecting mods, same stage files,
same costumes/equipment, same input device source, same graphics settings where
presentation can affect actor tick load, and a fixed test seed. Warm up the
match before recording baseline frames, compare immediate restore before
longer resim, and keep a list of excluded hash fields with evidence for each
exclusion.

## Other ways to improve online play

Rollback is the largest intervention. Lower-risk improvements can still help:

- reduce local render/input latency with engine settings and driver settings
- validate the "remove delay" patches against the real input path rather than
  `InputDelay+0x390`
- add connection diagnostics: packet loss, jitter, resend-window occupancy, and
  stall counter from `BM+0x1638`
- make adaptive delay explicit instead of hiding stalls
- improve packet validation and drop behavior around the 100-entry inbound deque
- expose desync/state-hash diagnostics before attempting correction
- require both peers to run identical gameplay-affecting mods and stage data

## Ghidra evidence touched in this pass

Program:

```text
SoulcaliburVI.exe
image base 0x140000000
```

Functions typed/renamed during this investigation:

| Function | Address | MCP changes |
|---|---:|---|
| `LuxBattleManager_UpdateOnlineFrameSyncCounter_At1638` | `0x1403FDEC0` | Typed `param_1` as `ALuxBattleManager_Partial *`, renamed to `pBM`; renamed `param_2` to `nDeltaFrames`. |
| `LuxOnline_SendInputPacket_PerFrame_Opcode0` | `0x1403F84E0` | Typed `param_1` as `ALuxBattleFrameInputLog *`, renamed to `pInputLog`; renamed `param_2` to `bInputByte`; renamed `param_3` to `nFrameID`. |
| `LuxOnline_SendInputPacket_BatchedRange_Opcode1` | `0x1403F8710` | Typed `param_1` as `ALuxBattleFrameInputLog *`; typed `param_6` as `uint`; renamed params to `pInputLog`, `dwSlotBitmask`, `nFrameID`, `nCurrentFrame`, `nWindowFrames`, `dwResendCounter`. |
| `LuxOnline_PushToRingBuffer_WithCriticalSection` | `0x1403F4BE0` | Typed `param_1` as `ALuxBattleFrameInputLog *`; typed `param_3` as `void *`; renamed params to `pFrameInputLog`, `unusedArg`, `pPacketWrapper`. |

Evidence functions reviewed:

| Area | Functions |
|---|---|
| Input cache/online drain | `GetCachedInputForFrameInputLogSlot @ 0x1403F0720`, `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770`, `LuxBattleChara_UpdatePlayerInputData_FromRoundCache @ 0x1403FCD10`, `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520` |
| Replay input/state | `LuxReplay_DecodeInputPackets_FromFile @ 0x1403ED310`, `LuxReplay_EncodeInputEvents_ToBuffer @ 0x1403ED980`, `LuxReplay_WriteThreeByteInputRecord_ToBuffer @ 0x1403F62E0`, `LuxBattleChara_ReplayPlayback_PushInputsToActiveSlots @ 0x1403F6600`, `ALuxBattleReplayPlayer_Tick_CopyRoundResetSnapshotAndSetMoveState4 @ 0x140435C20` |
| Core simulation | `LuxBattle_PerFrameTick @ 0x1402DBC60`, `LuxMoveSystem_PumpVMSlots @ 0x14031D460`, `LuxBattle_TickCharaMainSimulation @ 0x14034DA70`, `LuxBattle_TickHitResolutionAndBodyCollision @ 0x14033CCA0`, `LuxMoveVM_ClassifyHitboxFrameState @ 0x140300620`, `LuxMoveVM_EvaluateMoveTransition @ 0x14033E140` |
| RNG/stage/side effects | `LuxBattle_InitRngAndHashPrimes @ 0x14034F610`, `LuxMoveVM_GetRandU32 @ 0x14034F130`, `LuxMoveVM_GetRandXorshift96Gameplay @ 0x14034F1F0`, `LuxMoveVM_GetRandLCG @ 0x14034F550`, `LuxMoveVM_GetRandFloat01 @ 0x14034F5E0`, `SetScbattleStageInfoBarrierGeometry @ 0x1402D77C0`, `GetScbattleStageInfoBarrierGeometry @ 0x1402D7730`, `Audio_RandomTick @ 0x140399B70`, `LuxEffectSystem_GetRandomVariantIndex @ 0x14038F6B0`, `LuxCameraAction_RandomizeArenaOrbitParams @ 0x140327250` |
| Snapshot primitives | `LuxBattle_HgCpuDirect_ExecMoveChangeAndPost @ 0x1403841E0`, `LuxBattle_HgCpuDirect_ExecFinalizeAndPost @ 0x140384540` |

Known remaining unknowns:

- `FLuxRecordedFrame` fields are still mostly opaque.
- The exact online tick insertion point for prediction is not finalized.
- HgCpuDirect coverage for live online rollback is not proven complete.
- No deterministic hash harness has yet proven restore/resim equality.
- Stock online packets do not provide enough metadata for real rollback
  transport.
- Cross-round and object-lifecycle rollback should be treated as out of scope
  for the first prototype.

## Related local context

Local files under `E:/myMods` used as implementation context:

- `E:/myMods/docs/investigations/rollback-netcode-methods-2026-05-19.md`
- `E:/myMods/docs/investigations/sc6-replay-input-rollback-boundary-2026-05-21.md`
- `E:/myMods/RemoveDelay.md`
- `E:/myMods/HorseMod/horselib/ReplayScrub.hpp`
- `E:/myMods/HorseMod/horselib/ReplayClockGate.hpp`
- `E:/myMods/HorseMod/horselib/ActorTickGate.hpp`

Use those files to guide the prototype, but keep future public documentation
grounded in Ghidra MCP evidence and reproducible local tests.
