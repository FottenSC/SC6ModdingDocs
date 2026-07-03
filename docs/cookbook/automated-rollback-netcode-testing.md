# Recipe: Test SC6 rollback netcode on one machine

**Goal**: build repeatable local tests for SC6 online and rollback experiments
before spending time on real peer-to-peer online sessions.

**Requires**: an authorized SC6 install, a native hook or logging harness for
live gameplay tests, a fixed mod/build manifest, and scripted input or replay
input data. Source-code access is not assumed. The function names and memory
constraints below come from the
[Rollback Netcode Feasibility Investigation](rollback-netcode-investigation.md).

## What this proves

A one-machine lab can prove whether a rollback implementation behaves like the
same match with no transport delay for the scenarios it exercises. It can also
prove that the parser, comparator, fault scheduler, snapshot ring, prediction
policy, and logging are good enough to reproduce failures.

It cannot prove that stock Steam matchmaking, NAT traversal, Steam Datagram
Relay routing, remote system load, or two real players' machines will behave
well. Treat local tests as a gate before online testing, not a substitute for
online testing.

## Ground rules from the current investigation

Keep these facts in mind when designing the harness:

- The stock online path uses `ALuxBattleFrameInputLog` at `BM+0x478`.
- The online/replay input cache starts at `InputLog+0x3C0`; the inbound online
  packet deque is around `InputLog+0x4480`; the master clock is at
  `InputLog+0x3A4`.
- The stock receive path drains through
  `LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770`
  on the game thread.
- Battle input is consumed through
  `LuxBattleChara_UpdatePlayerInputData_FromRoundCache @ 0x1403FCD10`, using
  cache cells read by `GetCachedInputForFrameInputLogSlot @ 0x1403F0720`.
- The broad one-frame simulation target is
  `LuxBattle_PerFrameTick @ 0x1402DBC60`. The narrower BattleManager/InputLog
  route is
  `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`.
- The useful snapshot primitives are currently
  `LuxBattle_HgCpuDirect_ExecMoveChangeAndPost @ 0x1403841E0` and
  `LuxBattle_HgCpuDirect_ExecFinalizeAndPost @ 0x140384540`, but the
  HgCpuDirect blob is not proven complete for online rollback by itself.
- Stock online packets are too small for a full rollback protocol. Opcode 0
  carries a one-byte input and a 4-bit frame-low tag; opcode 1 resends a cached
  range. A rollback protocol still needs absolute frames, confirmations,
  prediction age, state hashes, and desync policy.
- Do not write `FLuxReplayInputCacheEntry` cells from a network thread. Inject
  prediction after the stock drain and before the cache consumer, or bypass the
  stock online drain in the lab.
- Keep the first rollback window inside an active round. Cross-round restore,
  actor destruction/recreation, rematches, disconnects, and loading boundaries
  need refusal tests before they become supported behavior.

## Choose the smallest topology

Start with the topology that answers the current question. Moving to a more
realistic topology too early makes failures harder to reproduce.

| Topology | Best question | What it does not prove |
|---|---|---|
| Parser/comparator CI | Are logs, schemas, fault schedules, and failure capsules deterministic? | Live game determinism or hook correctness. |
| Replay/log-driven tests | Can recorded input and hashes be replayed and compared offline? | Live transport behavior or snapshot completeness. |
| In-process virtual peers | Does the rollback controller correct seeded faults at the intended frame boundary? | OS sockets, process isolation, Steam, or real scheduling. |
| Baseline-vs-faulted harness | Does the faulted rollback lane converge to the no-delay oracle? | Real network quality or matchmaking behavior. |
| Loopback transport shim | Does the local protocol survive latency, jitter, loss, reorder, duplicates, and corruption? | Steam relay/NAT behavior unless the shim is placed at that exact layer. |
| Two local game processes | Do two live SC6 instances stay synchronized through the same local protocol? | Real remote machines or reliable stock Steam self-match behavior. |
| VM/sandbox isolation | Does process, profile, adapter, or route isolation expose integration issues? | GPU, relay, controller, and timing behavior on normal player machines. |
| Windows network emulation | Does the transport tolerate coarse host-level packet faults? | Precise per-input mutation when traffic is encrypted, relayed, or loopback-bypassed. |

## Parser and comparator CI

Build the parser and comparator first because they do not need SC6 to be
running. This layer catches the boring failures that otherwise waste game-test
time.

Useful CI checks:

- validate scenario, input, rollback, and fault config schemas;
- expand held-input ranges into absolute per-frame input streams;
- check that every generated fault has a seed, affected peer/slot, original
  frame, arrival frame, and mutation record;
- compare existing baseline and faulted JSONL artifacts by absolute frame;
- verify that a failure capsule names every file needed to replay the failure;
- reject logs that have missing frame ids, duplicate frame ids, or mixed build
  manifests.

Example file layout:

```text
artifacts/rollback/simple_hit/seed_000051C6/
  manifest.json
  scenario.json
  input_expanded.jsonl
  rollback_config.json
  fault_config.json
  faults.jsonl
  baseline.jsonl
  faulted.jsonl
  compare.json
  summary.txt
```

Do not let the comparator infer missing data. If a run did not record the
consumed input, RNG state, frame boundary, or snapshot id for a frame, mark the
run incomplete instead of guessing.

## Replay and log-driven tests

Replay/log-driven tests are useful before the live rollback hook exists. They
can consume recorded input streams, expected frame hashes, and previously
captured fault schedules.

Good uses:

- test replay input parsing without touching live online state;
- regression-test comparator behavior when hash fields are added or removed;
- verify that a historical failure still points at the same first divergent
  frame;
- exercise desync-report formatting and artifact bundling;
- check that scenario manifests reject mismatched SC6 builds, mod manifests,
  stages, costumes, or gameplay-affecting files.

Limits:

- a replay input stream is not a complete rollback snapshot;
- `FLuxRecordedFrame` is not proven to be a complete live-state record;
- a passing log replay does not prove that `LuxBattle_PerFrameTick` can be
  restored and resimulated;
- parser tests cannot validate hidden side effects such as audio, VFX, camera,
  animation notifies, or sibling actor ticks.

## In-process virtual peers

The first live rollback lab should use virtual peers inside one SC6 process.
Here, "peer" means an input/transport state machine, not a second cloned game
world. SC6 still has one live battle simulation unless the harness explicitly
runs lanes sequentially through restore/resim.

Recommended shape:

1. Load a fixed active-round scenario.
2. Feed both players from an expanded input script.
3. Run a no-delay baseline lane and log per-frame hashes.
4. Reset to the same scenario.
5. Run a faulted lane where the remote peer delivers inputs through a seeded
   latency/loss/reorder/corruption queue.
6. Predict missing remote inputs, restore when late confirmations arrive, and
   resimulate to the visible frame.
7. Compare the faulted lane to the no-delay baseline by absolute frame.

This is the fastest place to debug:

- off-by-one reads around `InputLog+0x3A4`;
- wrong `FLuxReplayInputCacheEntry` tags;
- missing RNG state;
- incomplete snapshot extras outside HgCpuDirect;
- double ticks from `ALuxBattleFrameInputLog` or sibling actor ticks;
- hidden resim side effects leaking into audio, VFX, camera, HUD, or notifies.

Keep the virtual transport deterministic. It should deliver the same fault
schedule every time for the same seed and config, regardless of wall-clock
timing.

## Baseline-vs-faulted harness

The baseline lane is the oracle. It runs the same scenario with both players'
real inputs available on time, no prediction, and no correction.

The faulted lane runs the rollback code under test. It should see only the local
input immediately. Remote input arrives according to the fault schedule.

Minimum lane contract:

| Field | Baseline lane | Faulted lane |
|---|---|---|
| Scenario | Same build, stage, characters, costumes, settings, mods, and seed. | Must match baseline manifest exactly. |
| Inputs | Full P1/P2 input stream available at the intended frame. | Local input immediate; remote input delayed, dropped, reordered, duplicated, or corrupted by config. |
| Frame id | Absolute frame id in active-round time. | Same absolute frame id after restore/resim. |
| Hash | Canonical gameplay hash after each frame. | Must match baseline after correction. |
| Side effects | Final visible frame only. | Hidden resim effects must be suppressed, deduped, or logged as unsupported. |

Do not compare against visuals alone. Health and position are also too weak.
Start with a broad canonical hash that covers selected `ALuxBattleManager`
fields, both `ALuxBattleChara` states, MoveVM state, KHit/body collision state,
timers, current input mirrors, input cache metadata, RNG state, and deterministic
stage/barrier state. Remove fields only after a named investigation proves they
are nondeterministic and non-gameplay.

## Loopback transport shim

After the in-process lab is stable, move the virtual transport behind a local
loopback shim. The goal is to test the protocol and queueing behavior without
depending on Steam matchmaking.

Useful shim behavior:

- listen on `127.0.0.1` or a local virtual adapter;
- accept peer A and peer B connections from the rollback test harness;
- assign monotonic packet sequence ids and log send/arrival/delivery frames;
- inject latency, jitter, loss, reorder, duplication, and corruption from a
  seed;
- preserve absolute frame ids and confirmation metadata in the custom rollback
  protocol;
- emit a transport JSONL that can be aligned with gameplay hashes.

Use the shim for custom rollback transport. It should not be treated as proof
that stock SC6 online packets are sufficient. If testing the stock online path,
place hooks at a known game-thread boundary: after
`LuxOnline_DrainRingBuffer_DecodeInputPackets_AndUpdateCache @ 0x1403F6770`
and before `LuxBattleChara_UpdatePlayerInputData_FromRoundCache @ 0x1403FCD10`,
or bypass the stock drain for the lab.

## Two local game processes

Two local SC6 processes are an integration test, not the first determinism test.
Use them only after one-process baseline/faulted tests are boring.

What to isolate:

- process-specific log and artifact directories;
- save/config/profile directories where the launcher or mod supports it;
- controller/input routing so both clients receive deterministic inputs;
- graphics settings and frame pacing;
- mod manifest and build ids;
- local transport ports;
- focus/minimize behavior, because inactive UE4 windows can change timing.

Expected limitations:

- Steam may not allow two live instances from the same account or same app
  context.
- Two local instances may not be able to match each other through stock online
  matchmaking.
- Steam relay behavior on one PC is not representative of two remote players.
- Encrypted or abstracted transport can prevent per-input packet mutation.
- A failure to create a stock self-match is not evidence that rollback logic is
  wrong.

The useful pass condition is narrower: when both processes run the same local
rollback protocol and receive the same confirmed inputs, their per-frame
gameplay hashes and correction decisions agree.

## VM, container, and sandbox isolation

VMs and sandboxes can help isolate profiles, network routes, and process state,
but they add their own timing and rendering variables.

Use them for:

- separate Windows user/profile state;
- separate Steam or app contexts where authorized;
- testing virtual adapters, NAT, and VM-router paths;
- forcing traffic through a controllable router or proxy;
- finding hidden dependencies on current working directory, config paths, or
  shared files.

Be cautious:

- Windows containers are usually not a practical way to run a UE4/DX11 Steam
  game with GPU rendering and input.
- Windows Sandbox is useful for clean-state checks but resets state and may not
  match normal GPU/input behavior.
- Full VMs need GPU acceleration or passthrough to be meaningful for live SC6.
- A VM-router topology can reveal routing and queue issues, but it is still not
  equivalent to remote residential networks.

If a VM setup is used, record the hypervisor, GPU mode, virtual NIC type,
display mode, and host load in `manifest.json`.

## Windows network emulation options

Prefer a harness-owned loopback shim when possible. It is deterministic,
per-input aware, and easy to log.

Host-level Windows network emulation is still useful for integration smoke
tests, but it is less precise:

- Packet-filter tools can add delay/loss/reorder to selected TCP or UDP flows
  when the traffic crosses a filterable interface.
- A local proxy can emulate network faults while preserving application-level
  packet metadata.
- A VM-router setup can route traffic through a Linux or appliance VM that
  applies queueing rules before packets return to the host or another VM.
- QoS, firewall, and adapter settings are useful for coarse bandwidth/routing
  checks, but they usually do not model per-frame rollback jitter by themselves.

Important caveats:

- Some tools do not affect `127.0.0.1` loopback traffic.
- Filtering the physical adapter can affect every application on the machine.
- Steam relay or P2P layers may encrypt, batch, retransmit, or reroute traffic
  below the level where SC6 input packets are visible.
- Corruption tests are rarely useful against encrypted transport. Inject
  corrupted decoded input records in the harness instead.
- Wall-clock latency is not a simulation frame id. Always log absolute frame
  ids at the game boundary.

## Steam and relay limitations

Steam is a deployment and matchmaking reality, but it is not a good first
rollback laboratory.

One-machine tests generally cannot prove:

- NAT traversal behavior;
- relay selection or fallback behavior;
- real remote jitter and congestion;
- firewall behavior on another user's network;
- two different machines' scheduling and render load;
- same-account or same-machine matchmaking edge cases;
- whether the stock online session layer can carry a full rollback protocol.

Use local tests to prove deterministic mechanics and transport policy. Then run
real online tests to validate session integration, relay behavior, disconnects,
join/leave boundaries, and player-facing diagnostics.

## Fault injection

Every injected fault needs a seed, frame id, peer/slot, original value, mutated
value, injection layer, and delivery result. A fault that cannot be replayed is
only a bug report.

| Fault | Local injection point | Pass gate |
|---|---|---|
| Delayed remote input | Fault queue delivers frame `F` at `F + delay`. | Delay inside the rollback window corrects to the baseline; over-window delay triggers the configured stall/desync/refusal policy. |
| Jitter burst | Seeded delay curve around a base latency. | Max prediction age and rollback depth stay within policy, and hashes match after correction. |
| Dropped input | Withhold one or more remote frames while keeping the baseline oracle intact. | Prediction is used, late confirmation corrects, and loss is visible in artifacts. |
| Reordered input | Deliver absolute frames out of order. | Absolute frame id wins over arrival order. |
| Duplicate input | Deliver the same confirmed input more than once. | Duplicate is idempotent and logged. |
| Corrupted input | Flip a decoded input bit or decoded-record field before the rollback controller sees it. | Invalid records are rejected or later corrected with a visible desync/hash signal. |
| Wrong cache tags | Mutate `nFrameID`, `dwFrameIndex`, or `bFilled` in a controlled `FLuxReplayInputCacheEntry` test. | Tag mismatch is detected as invalid or missing input, not silently consumed as neutral. |
| Master-clock stall/jump | Gate or edit `InputLog+0x3A4` in a lab-only run. | Frame-boundary trace catches drift before simulation advances. |
| Skipped/double tick | Suppress or double-run one controlled frame. | Trace shows the exact missing or extra `LuxBattle_PerFrameTick`/BM tick. |
| RNG perturbation | Flip a logged RNG state or add one controlled RNG consume in a test build. | First mismatch points at the divergent RNG state or call counter. |
| Side-effect leak | Disable one hidden-resim gate for a test. | Event ledger identifies the leaked audio/VFX/camera/HUD/notify event. |
| Round boundary | Schedule correction near KO, round end, replay reset, or object teardown. | Rollback refuses to cross the lifecycle boundary with a clear reason. |
| Build/mod mismatch | Alter manifest, hash, or gameplay-affecting test constants. | Peers refuse to compare or mark desync before correction. |

## Instrumentation

Add instrumentation before broadening the topology.

| Log | Include | Why |
|---|---|---|
| Frame boundary trace | Entry/exit for `LuxBattle_PerFrameTick @ 0x1402DBC60`, BM/InputLog tick paths, master clock, BM frame mirrors, and global frame counter. | Proves the harness advanced exactly the intended frames. |
| Input history | Intended input, consumed input, predicted/confirmed bit, slot, absolute frame, `nFrameID`, `dwFrameIndex`, and cache cell address. | Separates controller intent from what battle code actually read. |
| Snapshot manifest | Snapshot id, source frame, HgCpuDirect hash, extra-region hashes, buffer sizes, target pointers, and pointer/lifetime validation. | Prevents treating a successful restore call as proof that the right object graph was restored. |
| Gameplay hash | BattleManager fields, both chara states, MoveVM, KHit/body collision, timers, input mirrors, RNG, and deterministic stage state. | Main determinism oracle. |
| RNG trace | LFSR/xorshift/LCG state and optional counters around known RNG helpers. | Distinguishes missing snapshot state from extra RNG consumption. |
| Side-effect ledger | Audio, VFX, camera, HUD, animation notify, and actor-tick events during hidden resim and final frames. | Finds duplicate visible effects and gameplay-affecting presentation leaks. |
| Transport log | Send frame, arrival frame, delivery frame, sequence, absolute input frame, fault id, and payload hash. | Aligns local network behavior with gameplay correction. |

## Artifacts

Each automated run should leave enough data to replay the exact failure:

- `manifest.json`: SC6 build, mod build, loaded gameplay-affecting mods,
  scenario hash, input hash, rollback config hash, fault config hash, topology,
  OS, GPU mode, and environment notes;
- `scenario.json`: characters, stage, costumes, round state, start frame,
  seed, and setup notes;
- `input_expanded.jsonl`: absolute per-frame input stream after all ranges and
  holds are expanded;
- `baseline.jsonl`: per-frame no-delay oracle records;
- `faulted.jsonl`: per-frame prediction, rollback, correction, and hash records;
- `faults.jsonl`: generated fault schedule and delivery results;
- `snapshots.jsonl`: snapshot creation, restore, and lifetime validation records;
- `transport.jsonl`: local shim or process-to-process packet records;
- `side_effects.jsonl`: hidden-resim and final-frame event ledger;
- `compare.json`: first divergent frame, nearby context, and failed gates;
- `summary.txt`: human-readable result and reproduction command.

## Pass/fail gates

Use gates that fail loudly. Silent divergence is the most expensive outcome.

| Gate | Pass condition |
|---|---|
| Baseline stability | Repeating the no-delay baseline produces the same frame count, consumed inputs, RNG states, and gameplay hashes. |
| Immediate restore | Restoring snapshot `S` and hashing before any new frame advances produces the same gameplay state or a documented manifest-equivalent state. |
| Resim equality | Restoring frame `N` and resimulating to `N + K` matches the original no-delay hashes for `K = 1, 2, 8, 15, 60` in tested scenarios. |
| Correction equivalence | Delayed or mispredicted remote inputs inside the rollback window correct to the no-delay baseline. |
| Over-limit policy | Remote inputs arriving beyond the rollback window trigger the configured stall, resync, desync, or refusal path instead of silent divergence. |
| Input ownership | The consumed cache cell metadata matches the rollback controller's intended absolute frame and slot. |
| Thread ownership | Cache writes happen at the game-thread boundary chosen by the lab, not from a network receive thread. |
| Side-effect control | Hidden resim frames do not emit visible side effects, or each escaped event is explicitly deduped and logged. |
| Reproducibility | A failure capsule reruns to the same first divergent frame from a clean checkout and fixed manifest. |
| Resource budget | Snapshot memory, correction time, queue length, and log volume stay within configured limits. |

## What cannot be proven locally

Local tests are necessary, but they do not close the online-risk list.

| Cannot prove locally | Required follow-up |
|---|---|
| Real Steam relay and NAT behavior | Real online sessions across different networks and route types. |
| Remote machine scheduling and render load | Tests on varied CPUs, GPUs, storage, graphics settings, and background load. |
| Long-session player behavior | Soak tests with real inputs, pauses, rematches, disconnects, and lobby transitions. |
| Matchmaking policy safety | Separate policy tests and player-facing diagnostics, not just rollback hashes. |
| Cross-round rollback support | Dedicated lifecycle tests for KO, round start/end, replay reset, actor teardown, and rematch boundaries. |
| Mod ecosystem compatibility | Manifest handshake, gameplay-data hashes, and real mismatched-mod refusal tests. |
| Stock protocol sufficiency | A transport investigation that shows absolute frames, confirmations, hashes, and correction policy can be carried reliably. |

## Recommended path

1. Build parser/comparator CI and artifact schemas.
2. Capture stable no-delay baselines for short active-round scenarios.
3. Add in-process virtual peers and deterministic fault schedules.
4. Prove immediate restore and resim equality at `K = 1, 2, 8, 15, 60`.
5. Add prediction/correction and side-effect gates.
6. Move the same protocol behind a loopback shim.
7. Run two local processes only after one-process tests are stable.
8. Add VM, sandbox, or host network emulation only to answer specific isolation
   or routing questions.
9. Treat real online testing as the final integration phase, with its own
   artifacts and player-facing diagnostics.

## Avoid these shortcuts

- Do not treat visual similarity as determinism.
- Do not compare only health, timer, or position.
- Do not trust frame-low packet tags as absolute frame identity.
- Do not mutate live input cache cells from a receive thread.
- Do not count a quiet idle-frame restore as proof for hitstop, wall contact,
  VFX-heavy frames, or round transitions.
- Do not treat a passing one-machine transport test as proof of Steam relay,
  NAT, or remote player conditions.
