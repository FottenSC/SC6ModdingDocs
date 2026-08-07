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
| Is it proven deterministic from inputs alone? | Not for a live SC6 peer pair. `RollbackGekkoSelfTest`, `RollbackGekkoRuntimeCoreSelfTest`, and `RollbackEndToEndSelfTest` exercise local Gekko Save/Load/Advance and checksum contracts, but those executable tests are not two-process in-game evidence. |
| Can the stock online protocol be reused unchanged? | No. It only carries small input packets and 4-bit frame-low tags; rollback needs prediction, absolute frames, confirmations, and state hashes. |
| Is a scripting/reflection layer enough? | No. Frame stepping, snapshots, cache injection, and side-effect gates need native DLL hooks. |
| Best next validation | Close the remaining presentation-dispatch manifest blocker, bind validation to the resulting DLL, then run two-process in-game PVP with delayed peer inputs, canonical hash agreement, and stage/presentation corrections. |

## 2026-08-06 camera, MoveVM, and FP corrections

New Ghidra work corrected and extended the native state model:

- `g_abLuxMoveVMSlotParamArray @ 0x14470E0C0` is two pointer-free
  `FLuxMoveVMSlotParam` records with 0x2C-byte stride. `LuxBattle_PerFrameTick
  @ 0x1402DBC60` advances both records after camera processing. They are future
  gameplay state, not allocator residue. `LuxMoveVM_AdvanceSlotParamLerp @
  0x14032F780` consumes and mutates only each lane's +0x00..+0x27 prefix. The
  +0x28 dword is zeroed by initialization but has no native consumer xref, so
  rollback restores and peer-hashes the two semantic prefixes while excluding
  that stride padding.
- `CopyLuxBattlePublishedCameraInfo @ 0x1402D7980` does not read one 0x68-byte
  global. It copies a 0x60-byte six-float4 bank at `0x14470D1A0`, then appends
  `g_flLuxBattleCameraYawTurns @ 0x14470D0DC` and
  `g_dwLuxBattleCameraMode @ 0x14470D198`.
- `LuxCameraDirector_Initialize @ 0x140321D90` proves that the effect-camera
  director `+0x7A0` and the HgCpu timer config alias the same action root. The
  timer config's indexed table resolves the director's 16 component slots.
- `LuxEffectCamera_UpdateAllComponentWeights @ 0x14031E080`,
  `LuxEffectCamera_BlendAndApplyAllComponents @ 0x14031E410`, and
  `LuxEffectCamera_BlendCameraState @ 0x14033E8E0` prove that component weights,
  rotations, positions, secondary positions, blend scalars, mode, and velocity
  offsets feed the next synthesized camera frame.
- Camera synthesis uses scalar SSE arithmetic, so rollback peers need a
  bilateral MXCSR/x87 policy instead of inheriting ambient thread state.

Horse now captures the MoveVM pair and the proven camera value projection,
preflights director/component/vtable identities atomically, and installs a
schema-bound FP policy around each owned complete native iteration. Production
still remains fail-closed, but camera coverage is no longer the blocker:
`RollbackBattleCameraSnapshot` uses each live component's native serializer and
is covered by `RollbackBattleCameraSnapshotSelfTest`. The sole remaining
`PendingEvidence` manifest entry is presentation object lifetime and thread
affinity. The 38-route presentation hub still passes source-frame events
through, while audio/VFX journal commits remain rejected.

## Horse production-path status (2026-08-07 cross-check)

HorseMod now contains a disabled-by-default production path built around a
Horse-owned transport and Gekko. Beta configuration version 2 defaults to
`RollbackSteamP2PTransport`, which reuses SC6's initialized
`SteamNetworking005` interface on Horse's dedicated channel `0x484F`;
`RollbackUdpRuntime` remains the explicit direct-UDP compatibility route. This
is an implementation milestone, not a claim that live SC6 rollback is
accepted. Activation refuses to install the frame hook unless the executable
fingerprint, static snapshot schema, active PVP lifecycle epoch, peer handshake,
and manifest coverage all match. `BuildInitialRollbackManifest` currently has
one gameplay entry marked `PendingEvidence`, `Presentation object lifetime and
thread affinity`, so production activation is intentionally blocked even when
the other gates succeed.

The implementation separates three hash domains:

- a static, ASLR-independent schema identifier;
- a local snapshot-integrity hash used to validate save/load handles; and
- a canonical gameplay hash exchanged by peers after corrected frames.

Full snapshots remain in a 128-state Horse ring. Gekko save states contain only
an epoch/frame/generation/hash handle. The game thread alone performs Gekko
updates, captures, restores, and native simulation; transport workers only move
authenticated bytes through bounded queues. SC6's stock opcode/cache path
remains a diagnostic surface and is not the production input-injection path.

The Horse protocol-v2 packet envelope carries an explicit packet type,
source/destination slots, payload length, sequence, optional acknowledgement,
random session nonces, and a 128-bit-truncated CNG HMAC-SHA256 tag. Steam P2P
adds a bounded ECDH bootstrap before that authenticated protocol handshake; its
bootstrap and Hello/HelloAck traffic are reliable, while heartbeats and gameplay
packets remain unreliable. The receiver maintains a 64-sequence replay window
and expires readiness after two seconds without a valid heartbeat. Queue
overflow, authentication or epoch loss, timeout, restore failure, and
corrected-hash disagreement all fail closed instead of returning to stock
simulation mid-round.

Current CMake registers 69 rollback-labelled CTest entries: 68 under
`rollback-fast` plus `RollbackProtocolV2Benchmark`. The latest HorseMod
verification record reports 69/69 passing. In particular,
`RollbackGekkoSelfTest` exercises two local Gekko sessions with Save, Load,
normal Advance, rollback Advance, and matching final checksums, while
`replay_input_script_selftest.py` checks `11141/11141` extracted records. The
normal-render strict replay report `20260807-103220-seek` passed four of four
600-frame watch cases with `2400/2400` state comparisons, zero mismatches, and a
maximum seek-validation time of `0.42s`. That report has no artifact-evidence
binding, and neither the CTest results nor replay seek/oracle results are live
two-process SC6 acceptance. The release-authority path is
`rollback_two_client_acceptance_run.py --beta-release-gate`;
`rollback_full_validation_run.py` explicitly identifies itself as developer
validation only.

## Current online input path

The online input path is centered on `ALuxBattleFrameInputLog` at
`BM+0x478`. That actor owns the replay/online input cache at `InputLog+0x3C0`,
the online inbound packet deque at `InputLog+0x4480`, and the master clock at
`InputLog+0x3A4`.

Confirmed send path:

```text
LuxOnline_SendInputPacket_PerFrame_Opcode0 @ 0x1403F84E0
  builds a 3-byte channel-5 packet for one frame/slot
  if nFrameID is negative, uses pInputLog->nLastFrameId as the absolute frame
  low header bits: frameId & 0x0F
  high header bits: playerSlot << 4
  opcode: 0
  payload: one input byte
  uses the absolute frame, not its low nibble, for the sent-input bitmap

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

Do not derive the cache's `nFrameID` tag from `dwFrameIndex & 0xF`. Ghidra
validation of the native producer/consumer chain shows that cache identity uses
`ALuxBattleFrameInputLog::nLastFrameId` alongside the absolute frame index. The
4-bit low frame value belongs to the stock wire header, not the in-memory cache
tag model. Stock diagnostic opcode-0 handling must likewise resolve a negative
frame argument through the current `InputLog+0x3A0` value and read that same
current `nLastFrameId` when constructing a diagnostic cache record.

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

Round-restore state includes a fixed structured payload:

```text
SetScbattleRoundSnapshotPayload @ 0x1402D77C0
GetScbattleRoundSnapshotPayload @ 0x1402D7730
```

These functions write/read exactly `0xC0` bytes through
`g_LuxBattleRoundSnapshotPayload`. Decompiled save/restore consumers identify
the bytes as round index, gameplay xorshift, winner, two character records, and
motion entries. The twelve 16-byte copies are XMM lanes, not barrier records.
Deterministic terrain/wall/ring collision instead comes from the paired
`J_StgHitChkData` frame-bounds grids.

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
| Stage state | Deterministic `J_StgHitChkData` terrain/contact state plus gameplay-relevant breakable wall/barrier state. |
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
selected globals, bounds, terrain queries, camera, timers, motion, physics,
VFX state, and pointer-fixup descriptors. Local `E:/myMods` ReplayScrub work
measures the HgCpuDirect sim blob at `0x28018` bytes. These ranges should be
classified as native-covered rather than duplicated as speculative extras.

### Recovered HgCpu physics, motion, and timer layouts

The recovered `FLuxHgCpuPhysicsSnapshotBlock_Partial` is `0xD80` bytes:

| Offset | Storage | Evidence-backed role |
|---:|---|---|
| `+0x000` | `byte[0xC60]` | Physics/frame-context payload. |
| `+0xC60` | `int[8]` | Eight wall-smoothing integers. |
| `+0xC80` | `byte[0xC0]` | Wall reset/vector payload. |
| `+0xD40` | `FLuxHgCpuDirectRelocPair[4]` | Four direct relocation records. |

The motion writer and reader consume an independently recovered
`FLuxFrameBoundsGrid_Partial` of size `0x44C`. Its proven fields are the axis
span pointer at `+0x0`, relocation base at `+0x8`, terrain-entry storage at
`+0x408`, and a two-byte terrain-VFX latch at `+0x414`. Terrain records use a
`0x40` stride, including accessed fields at `+0x0C` and `+0x1C`.

The recovered `FLuxHgCpuTimerNode_Partial` is `0x2F0` bytes. It contains the
preserved live identity at `+0x0`, backing-state reference at `+0x8`, storage
for 17 child serializers beginning at `+0x10`, and an opaque tail beginning at
`+0x98`. Its writer serializes the `0x2F0` node, a `0x41E0` backing block,
17 children through their writer slot at `+0x20`, and four trailing globals.
The reader preserves the live `+0x0` and `+0x8` values across the raw node
restore, restores the same `0x41E0` backing block, invokes the 17 child readers
through `+0x28`, and restores the same four globals. Treating the node as a
blind byte blob without those preserve semantics would overwrite live object
identity.

`FLuxHgCpuTimerConfig_Partial` is `0x12C` bytes: registry storage begins at
`+0x8`, the indexed table at `+0x90`, the timer node at `+0xA0`, and the
remaining configuration blocks extend through `+0x128`. The native config
restore reconstructs timer types 0 through 8 and uses component vtable slots
`+0xE0`, `+0x100`, and `+0x108`; this is object reconstruction, not a single
flat memcpy. These recovered HgCpu ranges are native-covered for local snapshot
integrity, but their pointer-bearing bytes are not automatically canonical
peer-hash evidence.

The world-mode owner was also consolidated into one canonical
`FLuxBattle_WorldModePump` (`0x40` bytes): `pCurrentMode` at `+0x0`,
`pQueuedNextMode` at `+0x8`, `dwTransitionCompleted` at `+0x10`,
`dwScratchState` at `+0x20`, `nSubDriverState` at `+0x24`,
`pActiveSessionData` (`FLuxBattleActiveSessionRoot_Partial *`) at `+0x30`, and
`pSubDriver` at `+0x38`. Runtime lifecycle discovery should still use
`GetActiveBattleManager`; the recovered pump layout does not justify depending
on an unresolved field as a BattleManager pointer.

HgCpuDirect is still not complete for online rollback by itself. Independently
captured extras include:

- `g_LuxBattle_LatestEngineInput_PerPlayer`
- input ring/cursor globals used by `LuxBattle_PerFrameTick`
- LFSR/xorshift/LCG RNG state
- `g_dwLuxBattleRoundResultFlowState @ 0x1448463A8` (four bytes). The
  round-result evaluator writes the committed result flow, and both
  `LuxBattle_RoundResult_Tick @ 0x140387540` and
  `LuxBattle_RoundResult_WaitAndAdvance @ 0x140387430` consume it. The latter
  queues the stock advance/new-round mode only for verified values `1..3`.
- Do **not** add a second explicit copy of the 11 reusable WorldModePump mode
  objects. Ghidra xrefs at `0x140301884/976/B74/C66` prove HgCpu's native
  archive already serializes these objects, including `0x144100D88`; a second
  copy would duplicate coverage. The later live stall at D88 counters 14/21
  versus limit 240 was instead caused by the observer freezing on a transient
  BattleManager state 2 during the result sequence. A safe next-round boundary
  requires state 2 **and** round ordinal `old + 1` **and** a changed nonzero
  round-start digest. Complete the first stock result tick after releasing
  ownership, then keep all inter-round ticks stock-owned until that full
  identity predicate succeeds.
- breakable wall state (`wall+0x450` id, `+0x468` break state, `+0x46C` fade)
- breakable barrier state (`barrier+0x420` id, `+0x424` endurance,
  `+0x468` hit count), serialized in stable actor-type/id order

`ALuxBattleFrameInputLog` cache/cursors/sent bitmaps now belong to a separate
stock-path diagnostic schema. The Horse production path supplies decoded peer
inputs directly to temporary native tick arguments and does not accept stock
cache injection as a production gate.

The explicit global cursor at image RVA `0x485EB20` is eight bytes. Treating it
as a 16-byte range overlaps the adjacent Lux battle LCG state and can corrupt
RNG during restore.

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

Safe rollback needs to control one exact frame boundary. In the Horse
production path that boundary is a PolyHook detour on
`LuxBattle_PerFrameTick @ 0x1402DBC60`:

1. Capture only the local player's low 32-bit gameplay input and submit it to
   Gekko.
2. Process Gekko Save, Load, and Advance events in their emitted order.
3. Resolve Save/Load through the Horse snapshot-handle ring and validate the
   complete lifecycle epoch before either operation.
4. Decode both gameplay inputs into temporary native tick arguments.
5. Call the PolyHook trampoline exactly once for each Gekko Advance event.
6. Return from the detour without an additional stock tick.
7. Exchange corrected frame, canonical hash, and both applied input values;
   accept the frame only when both clients cross-match all fields.
8. Commit journaled presentation events only after peer confirmation.

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
| Audio | Journal requests by epoch/frame/idempotency key and commit once after peer confirmation. `LuxAudio_FireSoundCue_ViaVfxDispatcher @ 0x1403110B0` and `LuxMoveVM_DispatchVFXEffectForSlot @ 0x140311190` both dispatch through `g_pLuxVfxDispatcher` vtable `+0x38`; request byte `+0xC` distinguishes the two variants. |
| VFX / particles | Journal the external dispatcher call (the PerFrameTick edge path uses vtable `+0xB8`) and commit once after confirmation. `LuxEffectSystem_GetRandomVariantIndex @ 0x14038F6B0` uses gameplay xorshift. |
| Camera | Snapshot if gameplay-visible; otherwise smooth-correct. `LuxCameraAction_RandomizeArenaOrbitParams @ 0x140327250` uses xorshift. |
| HUD/debug/online UI | Do not drive from resim frames; update from final authoritative frame. |
| Animation notifies | Gate notifies during hidden resim or dedupe them by frame/event id. |
| UE actor/component ticks | Prevent unrelated ticks from mutating battle state during manual resim. |

`LuxBattle_SpawnStageWindParticles @ 0x140334960` is a special case. It consumes
Lux RNG and mutates emitter timer/count state before allocating the visual wind
object. A rollback resimulation path must reproduce that RNG/timer/count
progression while skipping only the external particle allocation; skipping the
whole function changes later deterministic state.

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

### Local automated test topology

A useful rollback lab does not need machines around the world. Start with a
single-machine deterministic harness that runs the same match script twice:

1. an authoritative no-delay baseline that feeds both players' real inputs on
   the exact frame they are meant to be consumed;
2. a faulted rollback run that gives local input immediately, delays or mutates
   the remote side according to a seeded fault schedule, predicts missing remote
   input, then restores/resimulates when the confirmed input arrives.

Both runs should start from the same active-round snapshot and consume the same
scripted input file. The baseline is the oracle. A rollback correction only
passes when the corrected run reaches the same gameplay hash as the no-delay
baseline at the same absolute frame.

Recommended local topology:

| Component | Role |
|---|---|
| Scenario runner | Loads a fixed character/stage/settings/mod manifest, waits for a stable active-round frame, then starts scripted input playback. |
| Virtual peer pair | Represents local and remote players inside the lab. The remote peer is not a real socket at first; it is a deterministic input producer behind a fault queue. |
| Authoritative baseline lane | Runs the same scenario with zero transport delay, no prediction, and full per-frame hashes. This lane never uses rollback correction. |
| Faulted rollback lane | Runs the scenario through the rollback controller, prediction policy, snapshot ring, restore/resim path, and side-effect gates. |
| Fault scheduler | Applies latency, jitter, loss, reorder, duplication, and corruption from a seed and config file. It writes the exact mutation into the fault log. |
| Input-delay/prediction matrix | Repeats the same scenario with different local input delay, max rollback depth, prediction window, prediction policy, and late-input policy. |
| Comparator | Aligns baseline and faulted logs by absolute frame, compares canonical gameplay hashes, and prints the first divergent frame plus nearby input/RNG/tick context. |
| Replayer | Reruns one failure from its seed, scenario id, mod manifest, baseline hash id, and fault schedule without requiring the original live session. |

The first version can be entirely in-process. A later loopback mode can put the
fault scheduler between two local processes or a local UDP/TCP transport shim,
but that should be a transport-integration test, not the first determinism
oracle.

### Harness components

Keep the harness boring and file-driven. A failed run should be reproducible
from artifacts alone.

| File or module | Contents |
|---|---|
| Scenario file | Character ids, stage, round settings, equipment/costume assumptions, startup wait, input script, expected supported/refused lifecycle boundaries, and tags such as `hitstop`, `wall`, or `round_end_refusal`. |
| Input script | Absolute frame, P1 input byte, P2 input byte, optional labels, and optional "hold previous" ranges. Store the post-expansion stream in the artifact so later parser changes cannot change the test silently. |
| Fault config | Seed, base one-way delay, jitter distribution, loss rate, reorder window, duplicate rate, corruption rules, burst-loss model, and target slot. |
| Rollback config | Local input delay, max rollback frames, snapshot interval or per-frame snapshot policy, prediction window, prediction policy, late-input policy, and side-effect gate mode. |
| Run manifest | SC6 build identifier, HorseMod/native DLL build identifier, loaded gameplay-affecting mods, scenario hash, input hash, fault-config hash, and rollback-config hash. |
| Baseline artifact | Per-frame authoritative inputs, hashes, RNG states, frame-boundary trace, and snapshot hash at the initial frame. |
| Failure capsule | Minimal rerun command/config, seed, first divergent frame, last matching frame, nearby input cells, RNG delta, snapshot ids, and log excerpts. |

The scenario runner should refuse to start if the manifest changes between
baseline and faulted runs. Do not compare a faulted rollback run against a
baseline from a different build, mod set, stage, or expanded input script.

### Configuration matrix

Use a small fixed matrix for quick developer runs and a broader seeded matrix
for overnight or CI-style runs.

| Axis | Quick values | Soak values |
|---|---|---|
| Scenario class | idle, walk/block, simple hit, hitstop | wall/barrier contact, throw, ring edge, camera/VFX-heavy, KO-boundary refusal |
| Local input delay | 0, 1, 2 frames | 0..4 frames |
| Max rollback depth | 2, 6, 10 frames | 1..20 frames, plus one over-limit refusal case |
| Prediction policy | neutral, hold-last | hold-last with age cap, scripted branch predictor if one exists later |
| Base one-way latency | 0, 2, 5, 8 frames | 0..15 frames |
| Jitter | none, +/-1 frame | seeded uniform/burst jitter up to the rollback limit |
| Loss | 0%, 1%, 5% | seeded random and burst-loss windows |
| Reorder window | none, 2 frames | 2..8 frames |
| Duplication | off, 1% | 1..10% duplicate inputs/packets |
| Corruption | off, cache-tag flip | input-bit flip, frame-id flip, malformed decoded record |
| Side-effect gates | on | on/off comparison, visible-frame-only ledger check |

The quick matrix should be small enough to run before committing a risky change.
The soak matrix should prefer breadth over random noise: every row must still
produce a named scenario, seed, config, and reproducible failure capsule.

### CI, headless, and scripted local runs

SC6 itself may not be friendly to true headless CI, so split the automation into
tiers:

- **Offline parser/comparator CI**: validate scenario files, expand input
  scripts, replay saved logs, compare existing baseline/faulted artifacts, and
  verify that failure capsules can reconstruct the intended fault schedule.
- **Scripted local game run**: launch the game with the lab DLL enabled, run a
  named matrix, write artifacts, and return a process exit code based on the
  pass/fail gates. This is the main developer workflow.
- **Loopback transport run**: use two local peers or two local processes with a
  deterministic fault shim once the in-process harness is already stable.
- **Manual online smoke test**: only after local gates pass, run a small number
  of real matches to inspect NAT/session behavior, real scheduling jitter, UI
  diagnostics, and presentation side effects.

A useful command shape is:

```text
rollback_lab run --scenario simple_hit --matrix quick --seed 0x51C6
rollback_lab replay --failure artifacts/rollback/failures/2026-07-01-001.json
rollback_lab compare --baseline artifacts/.../baseline.jsonl --run artifacts/.../faulted.jsonl
```

The exact command names can differ in HorseMod, but the contract should not:
one command creates artifacts, one command replays a failure, and one command
compares two existing logs without launching the game.

### Metrics, artifacts, and pass/fail gates

Every run should emit JSONL or another machine-readable format first, with a
short text summary second. Screenshots or videos are useful for presentation
bugs, but they are never the determinism oracle.

Minimum artifacts:

- `manifest.json`: build, mod, scenario, input, fault, rollback, and environment
  hashes;
- `baseline.jsonl`: authoritative no-delay frame records;
- `faulted.jsonl`: rollback/prediction/correction frame records;
- `faults.jsonl`: generated latency/jitter/loss/reorder/duplicate/corruption
  events after seed expansion;
- `snapshots.jsonl`: snapshot ids, source frames, region hashes, restore target
  validation, save/restore timings, and retained/dropped snapshot counts;
- `events.jsonl`: side-effect ledger entries and whether they happened on a
  visible frame or hidden resim frame;
- `summary.txt` or `summary.json`: first failure, gate results, max rollback
  depth, max prediction age, max correction time, average correction time, and
  artifact paths.

Useful pass/fail gates:

| Gate | Pass condition |
|---|---|
| Baseline determinism | Replaying the no-delay scenario produces identical gameplay hashes for the compared window. |
| Immediate restore | Restore without frame advance preserves the canonical gameplay hash and emits no visible side-effect events. |
| Resim equivalence | Restore/resim windows match the no-delay baseline at every compared final frame. |
| Correction equivalence | Delayed or mispredicted inputs within the configured rollback window correct to the no-delay baseline. |
| Over-limit policy | Inputs arriving beyond the rollback window trigger the configured stall/desync/refusal path instead of silent divergence. |
| Input ownership | The consumed `FLuxReplayInputCacheEntry` metadata matches the rollback controller's intended absolute frame and slot. |
| Side-effect gate | Hidden resim frames do not emit visible audio/VFX/camera/HUD/notify events, or every dedupe is named in the ledger. |
| Timing budget | Snapshot, restore, resim, and compare times stay under the configured frame-budget threshold for the target hardware. |
| Reproducibility | A failure capsule reruns to the same first divergent frame with the same seed and artifacts. |

Do not weaken a gate by comparing only health, position, or final winner. Those
are smoke checks. The rollback claim depends on canonical state hashes and a
clear reason for every excluded field.

### What local tests cannot prove

The local lab is the right place to prove deterministic rollback mechanics, but
it is not a substitute for real online testing.

Local automated tests can prove:

- the snapshot contains enough state for the tested active-round windows;
- the chosen frame boundary consumes the intended inputs exactly once;
- prediction/correction converges to the no-delay baseline under seeded faults;
- side-effect gates suppress hidden resim events in controlled conditions;
- failure logs are reproducible from seeds and artifacts.

Real online tests are still needed for:

- OS scheduler and driver behavior under real rendering/audio/network load;
- NAT traversal, relay behavior, firewall interference, and Steam/session
  timing;
- real jitter patterns from congested LANs, VPN/relay paths, overloaded
  systems, and unstable routes that are not well modeled by a simple seeded
  distribution;
- remote peer disconnects, alt-tab stalls, loading hitches, rematches, and
  process lifetime changes;
- player-facing UI behavior when the connection is unstable or diagnostics are
  unavailable.

Treat online tests as integration validation after the local oracle is stable.
If local rollback cannot match the no-delay baseline, real network tests will
only make the failure harder to explain.

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
| Jittered input delivery | Safe to model as a seeded per-frame delay curve around a base latency, including bursts where several frames arrive at once. | Required to tune queue sizing, prediction age, and adaptive delay under real scheduling noise. | Pass: every correction within the window matches baseline and max prediction age is bounded. Fail: burst arrivals overwrite confirmed history or produce frame-boundary drift. |
| Reordered packets | Safe to model by delivering remote inputs out of order to the input scheduler. | Required if using or extending the stock online parser/deque. | Pass: absolute frame id wins over arrival order. Fail: lower frame-low tags overwrite newer cache cells. |
| Duplicate packets | Safe to inject as repeated confirmed inputs for the same absolute frame. | Required for real transport dedupe validation. | Pass: duplicate is idempotent and logged. Fail: duplicate increments metrics, rewrites confirmed history differently, or triggers extra rollback. |
| Corrupted cache tags | Safe in offline cache-path tests by mutating `nFrameID`, `dwFrameIndex`, or `bFilled` in one `FLuxReplayInputCacheEntry`. | Not a transport fault by itself, but online hooks should guard malformed decoded records. | Pass: tag mismatch is detected as missing/invalid input and does not masquerade as neutral unless policy says so. Fail: stale cell is consumed as valid input. |
| Corrupted input data | Safe to model by flipping one input bit, opcode-like field, frame id, or decoded-record field before the rollback controller sees it. | Required before trusting any real transport, especially if extending stock packet handling. | Pass: invalid records are rejected or corrected by later confirmation, and the failure is visible in logs. Fail: corrupted data becomes confirmed input without a checksum/state-hash complaint. |
| Wrong frame IDs | Safe to inject in the local input-history layer and in cache cells. | Required for stock packet compatibility because opcode 0 only carries a 4-bit frame-low tag. | Pass: rollback protocol rejects or disambiguates the frame. Fail: input lands in the wrong 512-cell ring slot. |
| Stale predictions | Safe: keep an old predicted remote input across a known change and correct later. | Required to tune prediction age and confirmation policy online. | Pass: stale prediction age is logged, corrected, and bounded. Fail: old prediction becomes confirmed by accident. |
| Master clock jumps/stalls | Safe with HorseMod-style clock gates around `InputLog+0x3A4` and manual test writes in offline lab. | Required to see how real online stall/drain logic interacts with rollback ownership. | Pass: unexpected jumps/stalls are detected before simulation, and rollback refuses or repairs according to policy. Fail: `BM+0x1488/+0x148C/+0x1490` drift from `InputLog+0x3A4`. |
| Skipped/double ticks | Safe by deliberately suppressing or double-running one controlled frame in the harness. ActorTickGate-style sites are useful for reproducing sibling-tick leaks. | Required only to validate integration with live UE actor tick order. | Pass: frame-boundary trace catches the extra/missing tick immediately. Fail: hash drift appears later with no clear tick anomaly. |
| RNG perturbation | Safe in lab by flipping/restoring a logged RNG state or by inserting one extra traced RNG consume in a controlled test build. | Not transport-specific, but online testing must prove both peers keep identical RNG. | Pass: hash mismatch points at the first divergent RNG state/call. Fail: mismatch is delayed or only visible through gameplay later. |
| Side-effect leaks | Safe by temporarily disabling a side-effect gate for one hidden resim frame. | Required online because correction may happen under real rendering/audio load. | Pass: event ledger identifies the leaked event and gates prevent it in normal tests. Fail: duplicate visible effects, camera discontinuity, or gameplay-affecting notify mutation. |
| Round transition boundary faults | Safe only as a refusal test: schedule corrections near KO, round end, replay reset, or object teardown and verify rollback does not cross the lifecycle boundary. | Required before any online prototype can survive real rounds. | Pass: rollback refuses, stalls, or resyncs with an explicit reason. Fail: restore into freed/recreated chara or stage objects. |
| Actor lifecycle invalidation | Do not fake freed pointers. Safe tests are pointer/lifetime validation failures captured from natural transitions or controlled refusal cases. | Required for real online exits, rematches, loading, and disconnects. | Pass: snapshot manifest marks the target invalid and restore is blocked. Fail: restore writes into stale actor memory. |
| Stage state mutation | Safe only if limited to known deterministic stage state, such as a tracked lab-only terrain/contact or stage-object mutation. | Required for modded stages and online stage-object interactions. | Pass: mutation is either snapshotted/restored or detected as unsupported. Fail: same inputs diverge after wall/barrier/contact changes. |
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

## Player connection instability diagnostics

Rollback testing is developer-facing, but connection diagnostics are
player-facing. The UI should help players understand unstable matches without
claiming certainty the mod does not have.

### Primary instability signals

Diagnose the observable connection behavior first. Adapter type is a weak proxy;
rollback needs to know whether input delivery is stable enough for the current
rollback window.

Prefer rolling live metrics:

- rolling RTT and p95/p99 RTT;
- rolling jitter in milliseconds and in 60 fps frame units;
- packet/input loss rate and burst-loss length;
- reorder and duplicate counts;
- resend-window occupancy;
- stock stall counter behavior such as `BM+0x1638`, where available;
- rollback depth, prediction age, correction count, and over-window late inputs;
- desync/state-hash warnings once hashes exist.

Report these as rolling windows, not single samples. A 10 to 30 second window is
usually more useful than one ping spike. Keep the units visible: milliseconds
for network time, frames for simulation impact.

### Optional local adapter hints

Adapter information can be shown as a local troubleshooting hint when the OS
exposes it, but it should not be treated as the primary diagnostic or a match
policy input. On Windows, an external launcher, overlay, or native helper may be
able to tell the local user that the active route appears wireless, wired-like,
virtual/VPN, or unknown. That hint should stay local unless the player explicitly
chooses to include it in a support report.

Remote adapter detection is not reliable. NAT, Steam/relay paths, VPNs, virtual
adapters, and OS privacy boundaries generally prevent one peer from proving the
other peer's last-hop connection type. Even voluntary self-reporting is weaker
than live jitter, loss, RTT, stall, and rollback metrics.

### Honest UI wording

Use careful wording:

- "Connection unstable: high jitter over the last 20 seconds."
- "Packet loss burst detected; rollback corrections may fail."
- "Rollback limit exceeded; match may stall or desync."
- "High jitter suggests one peer may be on Wi-Fi, a congested LAN, VPN/relay,
  overloaded system, or unstable route."
- "Local adapter hint: route appears wireless. Live quality is currently stable."

Avoid absolute claims:

- "Opponent is on Wi-Fi."
- "Bad connection because Wi-Fi."
- "Wired connection is good."
- "NAT type caused lag" unless the transport layer has specific evidence.

Do not block matchmaking or rank policy based on adapter category. At most, show
a warning or require confirmation for ranked/competitive modes if rolling jitter,
loss, stalls, or rollback pressure are already outside policy.

### Thresholds and warnings

Tune thresholds with real data, but start with frame-aware defaults:

| Signal | Caution | Warning |
|---|---:|---:|
| p95 jitter | above 1 frame / 16.7 ms | above 2 frames / 33.3 ms |
| Jitter burst | any burst above 2 frames | repeated bursts above rollback delay budget |
| Packet/input loss | above 0.2% | above 1% or any burst longer than 3 frames |
| Rolling RTT | above 70 ms | above 120 ms |
| Reorder/duplicate rate | recurring in the last 30 seconds | enough to trigger corrections or queue pressure |
| Prediction age | above half the rollback window | reaches the rollback window |
| Rollback depth | frequent corrections above 3 frames | repeated over-window late inputs |
| Stall counter | recurring stalls | stalls that coincide with input starvation or correction failure |

Warnings should explain the observable problem, not just the presumed cause:

```text
Connection unstable: jitter is averaging 2.4 frames over the last 20 seconds.
High jitter suggests one peer may be on Wi-Fi, a congested LAN, VPN/relay,
overloaded system, or unstable route.
```

```text
Packet loss burst: 5 missing input frames in the last 10 seconds.
Rollback corrections may fail.
```

```text
Local adapter hint: route appears wireless.
Live quality is currently stable.
```

### Privacy-safe telemetry

If telemetry is collected, keep it aggregate and opt-in where possible. The
useful diagnostics do not need SSID, BSSID, MAC address, local IP, public IP,
geolocation, adapter name, adapter category, raw packet payloads, or per-frame
player inputs.

Safe fields are rolling metrics and coarse session outcomes:

- NAT/session category if already exposed by the transport layer;
- rolling RTT, jitter, loss, reorder, duplicate, stall, and rollback metrics;
- SC6/mod build ids, gameplay-affecting mod manifest hash, and scenario/test
  identifiers for lab runs;
- whether a warning was shown, dismissed, or followed by a disconnect.

Do not upload local or remote adapter categories as routine telemetry. If a
player chooses to attach a local support bundle, an adapter hint can be included
as an explicit local note, not as a match-quality verdict.

For public logs, hash peer/session ids with a per-session salt or omit them.
The goal is to debug connection quality, not identify a player's home network.

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
| RNG/stage/side effects | `LuxBattle_InitRngAndHashPrimes @ 0x14034F610`, `LuxMoveVM_GetRandU32 @ 0x14034F130`, `LuxMoveVM_GetRandXorshift96Gameplay @ 0x14034F1F0`, `LuxMoveVM_GetRandLCG @ 0x14034F550`, `LuxMoveVM_GetRandFloat01 @ 0x14034F5E0`, `SetScbattleRoundSnapshotPayload @ 0x1402D77C0`, `GetScbattleRoundSnapshotPayload @ 0x1402D7730`, `Audio_RandomTick @ 0x140399B70`, `LuxEffectSystem_GetRandomVariantIndex @ 0x14038F6B0`, `LuxCameraAction_RandomizeArenaOrbitParams @ 0x140327250` |
| Snapshot primitives | `LuxBattle_HgCpuDirect_ExecMoveChangeAndPost @ 0x1403841E0`, `LuxBattle_HgCpuDirect_ExecFinalizeAndPost @ 0x140384540` |
| HgCpu motion/timers | Motion writer/reader at `0x140391CA0` / `0x140391E10`; timer-config writer/reader at `0x140321750` / `0x140321A30`; timer-node writer/reader at `0x140324900` / `0x1403249E0` |
| World/stage lifecycle | `LuxBattle_AdvanceWorldModePump @ 0x1402D9CD0`, `LuxStage_RegisterBarrierActor_BattleEvent0x19 @ 0x140427490` |

Every function touched in this production-path Ghidra pass was re-scored after
prototype, type, variable, and comment cleanup. Each has fewer than 10 fixable
completeness-deduction points; remaining deductions are documented decompiler
artifacts or otherwise non-actionable evidence gaps.

Known remaining unknowns:

- `FLuxRecordedFrame` fields are still mostly opaque.
- The implemented production insertion point is the guarded
  `LuxBattle_PerFrameTick` detour, but live two-process acceptance is pending.
- The current manifest combines HgCpu-native coverage with explicit Horse
  snapshots, but only the presentation-dispatch entry remains deliberately
  incomplete; cross-process SC6 canonical-hash equality is not yet proven.
- Local Gekko Save/Load/Advance and hash contracts pass their executable tests;
  those tests do not prove that two SC6 processes converge under correction.
- Stock online packets do not provide enough metadata for real rollback
  transport.
- Round and lifecycle coordination have concrete Horse components and
  self-tests, but still need live match, rematch, disconnect, and teardown
  evidence.

## Related local context

Local files under `E:/myMods` used as implementation context:

- `E:/myMods/HorseMod/horselib/RollbackProductionRuntime.hpp`
- `E:/myMods/HorseMod/horselib/RollbackSnapshot.hpp`
- `E:/myMods/HorseMod/horselib/RollbackGekkoRuntimeCore.hpp`
- `E:/myMods/HorseMod/horselib/RollbackSteamP2PTransport.hpp`
- `E:/myMods/HorseMod/horselib/RollbackReplayOracle.hpp`
- `E:/myMods/tools/rollback_full_validation_run.py`
- `E:/myMods/tools/rollback_two_client_acceptance_run.py`

Use those files to guide the prototype, but keep future public documentation
grounded in Ghidra MCP evidence and reproducible local tests.

## Outstanding implementation work

This is the status of the current uncommitted `E:/myMods` implementation, not a
future architecture proposal. Component and test presence establishes local
implementation coverage only unless a live artifact-bound result is named.

### Implemented and self-tested pieces

- **Gekko event execution and local correction contracts:**
  `RollbackGekkoAdapter` and `RollbackGekkoRuntimeCore` implement ordered Save,
  Load, and Advance handling. `RollbackGekkoSelfTest`,
  `RollbackGekkoRuntimeCoreSelfTest`, and `RollbackEndToEndSelfTest` exercise
  local two-session traffic, rollback Advance events, and checksum convergence.
  These are executable harness results, not two SC6 processes.
- **Snapshot schema, handle ring, and recent deterministic state:**
  `RollbackSnapshot`, `RollbackSnapshotStore`,
  `RollbackLuxMoveVmSlotParamSnapshot`, `RollbackBattleCameraSnapshot`, and
  `RollbackFloatingPointEnvironment` cover the manifest, the 128-state handle
  ring, MoveVM slot parameters, camera serializers, and the schema-bound FP
  policy. The focused evidence is `RollbackSnapshotSelfTest`,
  `RollbackSnapshotStoreSelfTest`, `RollbackLuxMoveStateSelfTest`,
  `RollbackBattleCameraSnapshotSelfTest`, and
  `RollbackFloatingPointEnvironmentSelfTest`.
- **Transport and protocol scaffolding:** `RollbackProtocolV2`,
  `RollbackUdpRuntime`, and `RollbackSteamP2PTransport` implement authenticated
  protocol-v2 traffic over direct UDP or Horse's dedicated Steam P2P channel.
  `RollbackProtocolV2SelfTest`, `RollbackUdpRuntimeSelfTest`,
  `RollbackSteamP2PTransportSelfTest`, `RollbackBetaConfigSelfTest`, and
  `RollbackPeerLivenessSelfTest` cover their local contracts.
- **Native iteration, round, and fail-closed lifecycle controls:**
  `RollbackNativeSimulationIteration`, `RollbackRoundCoordinator`,
  `RollbackNativeTerminalGate`, `RollbackNativePreNewRoundGate`, and
  `RollbackProductionActiveGuard` have focused tests with the corresponding
  `*SelfTest` names. This demonstrates the modeled state machines and refusal
  paths, not real match lifecycle behavior.
- **Stage and replay evidence machinery:** `RollbackOnlineStageState`,
  `RollbackStageWindSnapshot`, `RollbackStageWindAuthority`, and
  `RollbackReplayOracle` have `RollbackOnlineStageStateSelfTest`,
  `RollbackStageWindSnapshotSelfTest`, `RollbackStageWindAuthoritySelfTest`, and
  `RollbackReplayOracleSelfTest`. The replay oracle test proves schema/hash
  behavior; it is not an online determinism result.

### Evidence still pending

- No artifact-bound result proves that the DLL built from the current dirty
  HorseMod worktree passes the complete gate. The recorded normal-render run
  `20260807-103220-seek` passes its replay corridor, but its report contains
  `artifact_evidence: null`; it must not be promoted to proof for later source
  changes or to live rollback proof.
- `RollbackGekkoSelfTest`, `RollbackEndToEndSelfTest`,
  `RollbackReplayOracleSelfTest`, and `replay_input_script_selftest.py` are local
  executable/parser evidence. Cross-process SC6 state restore, corrected-frame
  canonical hash agreement, real consumed-input agreement, and visible
  presentation behavior remain unproven.
- Live evidence is still required for Steam session/bootstrap behavior, NAT or
  relay routes, loss/reorder/duplication, rollback-window limits, round and
  rematch transitions, disconnect/recovery, process teardown, and breakable or
  wind-heavy stages. The evidence must bind both peers, the candidate DLL,
  configuration, replay/golden inputs, and runner version.

### Blockers before live two-process acceptance or production activation

- `BuildInitialRollbackManifest` deliberately leaves exactly one gameplay
  capability incomplete: `Presentation object lifetime and thread affinity`
  (`RollbackCoverageCapabilityId::PresentationDispatch`). Source-frame listener
  events still pass through, and production audio/VFX journal commit is
  rejected. `RollbackAudioPresentationSelfTest` and
  `RollbackVfxPresentationSelfTest` validate scaffolding; they do not close the
  native terminal, persistent playback/slot-ID, confirmed-epoch materialization,
  manager time-scale/visibility, or exactly-once commit boundaries.
- Production must remain disabled until that manifest entry is evidence-backed
  and `RollbackSnapshotSelfTest` is updated only because the implementation has
  actually closed it. A passing support-hook mask, listener descriptor audit,
  or replay seek cannot substitute for terminal suppression and confirmed
  commit.
- After the code blocker closes, validation must run against the exact candidate
  artifact. `rollback_full_validation_run.py` is explicitly developer-only.
  The release authority is `rollback_two_client_acceptance_run.py
  --beta-release-gate`, which requires the artifact-bound local qualification,
  trusted normal-render golden/replay evidence, manual stock-online attach
  evidence, and a passing physical two-machine qualification manifest. The
  local full gate also enforces a 14-replay corpus and a 3,600-second,
  ten-completed-match soak; self-test or policy-lint modes cannot satisfy those
  requirements.
