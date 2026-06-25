# CPU / AI System

How the CPU opponent decides what to do, and how training-mode dummies are
driven. The short version: **the AI emits frame inputs** — not direct MoveVM
commands — so it sits one layer above the move VM and feeds the same input
buffer the human controller writes to. Difficulty and personality select which
`HgCpuDirect*` SubVM module ticks. Tutorial drills use the **same framework**
as live AI, only with scripted Tick bodies.

All addresses absolute (image base `0x140000000`).

## TL;DR

| Question | Answer |
|---|---|
| Where does AI tick? | `LuxMoveVM_SelectMoveCommandContinuation @ 0x1402E5470` inside `LuxBattle_PerFrameTick` |
| What does AI output? | A 32-bit input-command word written to the per-slot sched state — the same field a human controller writes through `LuxBattle_TickCharaInput` |
| Does AI tick during replay viewing? | Yes — but the replay decoder overwrites `chara+0x2150` before consumption, so the AI's choice is silently discarded |
| Does the WorldTickGate freeze gate AI? | **Yes, automatically** — Site 9 (`LuxBattle_PerFrameTick`) is the parent of the entire AI tick chain |
| Are tutorials a separate AI? | No — same `HgCpuDirect*` SubVM framework, just with scripted Tick bodies instead of personality-picked ones |
| Can a mod drive the training dummy? | Yes — 11 UFunctions on the training-mode actor, all UE4SS-reflectable |

## Per-frame call chain

```text
LuxBattle_PerFrameTick @ 0x1402DBC60         (gated by WorldTickGate Site 9)
└── LuxMoveVM_ScheduleCharaMoveForTick @ 0x1402E52D0    (per-chara, before input read)
    ├── (moveId == 2)    LuxMoveVM_TickPickAndDispatchReaction @ 0x1402DEF50
    │                    (yarare / hit-reaction classifier — NOT strategic AI)
    │
    └── (otherwise)      LuxMoveVM_SelectMoveCommandContinuation @ 0x1402E5470
                         └── pSubVM->vtable[+0x10]() = HgCpuDirectXXX::Tick
                             (chooses input → writes pSubVM+0x08)
                         then vtable[+0x28] OnTickPost
                         then vtable[+0x30] OnTickFinalize
                         then vtable[+0x38] OnTickMoveChange (if move changed)
```

> source: function plates at `0x1402DBC60`, `0x1402E52D0`, `0x1402E5470`,
> landmark plate at `0x1402F7370` (`LuxBattleChara_GetAIStateTableField`).

## AI output = frame input

Each SubVM `Tick` writes a 32-bit input command word to `pSubVM+0x08`. That word
propagates into the per-slot sched state at `&DAT_144715408 + slot*0x60`; the
DEFAULT branch of `LuxBattle_TickCharaInput @ 0x140312510` then reads it and
writes `chara+0x2150` / `+0x2158` as that frame's raw input — exactly where a
human controller writes.

For **special moves** (cmd id `0x69`), the AI bypasses the input layer: it writes
the move id to `&DAT_144715430 + slot*0x18 + cmd` and two `uint16` params to
`&DAT_144715448`, then commits via
`LuxMoveVM_SchedState_CommitCommandSlot @ 0x1402E5660`.

!!! info "Replay determinism"
    Because the AI emits frame inputs, replays are bit-deterministic from the
    input stream alone — no AI snapshot needed. During replay viewing the AI
    keeps ticking, but the replay decoder overwrites `chara+0x2150` before
    consumption, so the AI's output is silently discarded. See
    [replay-system.md](replay-system.md).

## Difficulty / personality

The chara's `BattleAISetting.Personality` FName keys a row in the chara-record
data table at `chara+0x97250`. The row either carries a `"PSNL"` 4-cc tag
(custom personality data) or falls back to the 32-byte default block at
`_DAT_143E84F10`.

| Step | Where | What |
|---|---|---|
| Base weights | `chara+0x948..+0x964` | 32-byte weight block — written by `LuxBattle_InitCpuPersonalityData @ 0x140364950` |
| Live bank | `chara+0x968..+0x984` | Mirrored copy for per-frame compute. Refreshed by `LuxBattle_RefreshCpuPersonalityData @ 0x140364BC0` |
| Condition vector | `chara+0x220` | 15 × `uint16` per-frame combat conditions (HP fraction, distance bucket, opp move state, ring proximity, etc.) |
| Per-slot rows | `chara+0x230` (stride `0x12`) | One row for each of the 8 personality slots |
| Compute | — | `LuxBattle_ComputePersonalityActionWeights @ 0x140394FE0` — `weight * condition_vec[col]` summed into an 81-entry action-id histogram; top 8 kept |
| Pick array | `chara+0x988..+0xBA0` | The 8 chosen action ids per slot. Per-frame Tick samples one via the VM RNG |
| Per-round refresh | — | `LuxBattle_ComputeAllPersonalitySlots @ 0x140395320` |

```c
enum class ELuxBattleAIDifficulty : uint8 {
    Tutorial = 0, Easy = 1, Normal = 2, Hard = 3,
    VeryHard = 4, Legendary = 5, ENUM_MAX = 6,
};

enum class ELuxBattleAITendency : uint8 {
    Standard = 0, Offense = 1, Defense = 2,
    GuardBreak = 3, Run = 4, ENUM_MAX = 5,
};
```

> source: RTTI strings at `0x1433A3B20..0x1433A3D70` (difficulty),
> `0x1433A30F0..0x1433A3230` (tendency).

## HgCpuDirect SubVM framework

Behavior modules are 0x70-byte `CCpuDirectCommand`-derived objects. There are
100+ derived classes, one per behavior pattern (standing guard, ring-edge
attack, revenge counter, AllGuardCount tracking, and so on). Base layout:

| Offset | Field | Purpose |
|---|---|---|
| `+0x00` | `vftable` | Polymorphic Tick / OnTickPost / Finalize / OnTickMoveChange dispatch |
| `+0x08` | `dwInputCmd` | The AI output — read by `LuxBattle_TickCharaInput` |
| `+0x10`, `+0x18` | `pChara`, `pOpp` | P1 and P2 chara pointers |
| `+0x30..+0x58` | counters | Timers and state counters |
| `+0x58` | `flReactionTimer` | `-1.0f` sentinel = no pending reaction |
| `+0x60` | `pSchedState` | Back-pointer to the owning `FLuxMoveSchedState` |
| `+0x68..+0x74` | per-derived state | Class-specific storage |

The factory that picks which derived class to install per chara is
`LuxMoveVM_CreateCpuDirectState @ 0x1402E26A0` — it switches on personality +
condition vector and constructs the appropriate SubVM.

## Tutorial scripts use the same framework

The 16 `HgCpuDirectTutorial*_Init` functions at `0x1402E4CF0..0x1402E51D0`
construct *scripted* CCpuDirectCommand-derived SubVMs, one per drill
(`ApproachBG`, `BB_Guard`, `Stun`, `ReversalEdgeMax`, `66AB`, `4AorAG`, `4KB`,
`3B`, `AirControl`, `GuardImpact3B`, `1AReverseImpact`, and so on). Their Tick
bodies emit fixed input sequences instead of consulting personality or condition.

**Implication**: there is no "tutorial input replayer" separate from the AI. To
record a custom CPU behavior, attaching a scripted SubVM through this framework
is the lowest-friction path.

## Practical recipe: scripted CPU drill boundaries

Use a scripted `HgCpuDirect*`-style SubVM only when the dummy needs native,
frame-perfect behavior that is more than a pre-recorded input stream: reacting
to distance, move state, ring position, or a drill-specific success/fail flag.
For simple canned sequences, prefer the training-mode UFunctions below. For
external bot logic that owns every frame, prefer the `LuxBattle_TickCharaInput`
override recipe below.

### What the boundary guarantees

| Boundary | Practical meaning |
|---|---|
| SubVM output | A scripted drill should emit the same 32-bit frame-input command at `pSubVM+0x08` that stock AI emits. The downstream MoveVM still decides whether that input starts a move. |
| MoveVM boundary | Do not treat a CPU drill as a direct move-lane editor. Move selection, transition timing, hit reactions, and active lane state belong to the [Move System](move-system.md). |
| Replay boundary | A scripted SubVM can tick during replay viewing, but replay input can still replace the final raw input before consumption. See [Replay System](replay-system.md). |
| UE4SS boundary | Installing or replacing a SubVM is native-code work, not a Lua reflection call. UE4SS reflection is useful for training UFunctions; custom SubVM construction needs a C++ plugin/detour path. |

### Conservative implementation checklist

1. Mirror the tutorial pattern first: construct a `CCpuDirectCommand`-derived
   object, initialize the known base fields, and let the existing dispatcher call
   `Tick`, `OnTickPost`, `OnTickFinalize`, and `OnTickMoveChange`.
2. Keep custom drill state inside verified per-derived storage or an external
   native side table keyed by the owning chara/sched-state pointer. Do not assume
   a wider class layout just because one tutorial class has spare-looking bytes.
3. Emit ordinary frame-input commands unless you have explicitly chosen the
   special-move route. The special route uses command id `0x69` and the
   scheduler commit path documented above, so its params need per-character
   runtime validation.
4. Preserve the stock chara/opponent/sched-state pointers. If a drill swaps the
   SubVM after `LuxMoveVM_CreateCpuDirectState`, verify those back-pointers before
   the first tick.
5. Add an escape path that restores the stock factory choice or clears the drill
   when the match restarts. Battle objects are rebuilt across rematch and menu
   transitions, so stale SubVM pointers are not reusable.
6. Test under pause, frame-step, training playback, and replay viewing. The
   scripted SubVM may tick while another source wins the final input, and that is
   expected behavior rather than proof that the SubVM failed.

### Use the simpler layer when it fits

| Goal | Better layer |
|---|---|
| "Block after this recorded string" | Training recording/playback UFunctions |
| "Press this command every frame while a condition is true" | Native frame-input override |
| "Run a tutorial-style drill with counters and branchy native state" | Scripted `HgCpuDirect*` SubVM |
| "Force a move for presentation or move-list tooling" | BattleManager / MoveCommandPlayer UFunctions; see [battle-manager.md](battle-manager.md#key-ufunctions-call-via-reflection) and [move-system.md](move-system.md#actor-class-aluxbattlemovecommandplayer) |

## Training-mode UFunctions

The training-mode actor exposes 11 UFunctions — all with live native bodies, all
UE4SS-reflectable. They are the easiest hook for any "drive the dummy
programmatically" mod (record-and-replay, frame-trap setup, combo-trial scripts):

| UFunction | Address | What |
|---|---|---|
| `StartRecording` | `0x1402D3C70` | Begin recording the human player's inputs |
| `StartPlayback` | `0x1402D3D20` | Begin playback of the last recorded stream |
| `StopAndReset` | `0x1402D3D00` | Stop recording or playback and clear the stream |
| `GetMode` | `0x1402D3DA0` | Returns `ELuxTrainingDummyMode` |
| `QueueCommand_Slot0` | `0x1402D3E20` | Queue a raw input command on slot 0 |
| `QueueCommand_AtSlot` | `0x1402D3E50` | Queue a raw input command on arbitrary slot |
| `GetCurrentCommand_Slot0` | `0x1402D3E30` | Peek the current queued command on slot 0 |
| `GetCurrentCommand_AtSlot` | `0x1402D3F20` | Peek the current queued command on arbitrary slot |
| `QueueSpecialMove1Param` | `0x1402D3F90` | Queue a special-move (id `0x69`) command with one parameter |
| `QueueSpecialMove2Param` | `0x1402D4000` | Queue a special-move command with two parameters |
| `ResetGlobalState` | `0x1402DA520` | Reset the training-mode globals at `&DAT_144715430` / `&DAT_144715448` queues |

```c
enum class ELuxTrainingDummyMode : uint32 {
    OFF       = 0,
    RECORDING = 1,
    PLAYBACK  = 2,
};

enum class ELuxTrainingScrubMode : uint32 {
    OFF     = 0,
    FORWARD = 1,
    REWIND  = 2,
};
```

## Practical recipe: drive the training dummy

Use the training-mode UFunction surface when the goal is a programmable dummy,
not a new CPU personality. This keeps the mod above the native AI SubVM layer and
uses the same training queues the game already knows how to record, play back,
and clear. For UE4SS call mechanics, use the normal reflected-call safety rules
in [UE4SS Lua API](../ue4ss/lua-api.md#reflected-ufunction-calls) and keep the
[reflection caveats](../ue4ss/reflection-gotchas.md) nearby when a parameterized
call fails.

### Pick the smallest control surface

| Need | Prefer | Notes |
|---|---|---|
| Replay a human-recorded setup | `StartRecording` / `StartPlayback` / `StopAndReset` | Best for quick training-lab automation because the game captures the same frame-input stream it later consumes. |
| Feed a known raw input command | `QueueCommand_Slot0` or `QueueCommand_AtSlot` | Use after you have validated the 32-bit command word at runtime. This page does not define the bit packing. |
| Force a special-move command | `QueueSpecialMove1Param` / `QueueSpecialMove2Param` | Native route for command id `0x69`; parameters are move-specific and should be treated as runtime-validated data, not portable constants. |
| Clear a wedged queue | `StopAndReset`, then `ResetGlobalState` | `ResetGlobalState` clears the special-move globals as well as the normal training queue state. |

### Safe call order

1. Enter a live Training match and re-resolve the live training-mode actor after
   every rematch, character change, or return from replay/menu flow. The
   BattleManager's training subsystem slots are mapped in
   [battle-manager.md](battle-manager.md#training-mode-managers).
2. Call `StopAndReset` before switching from recording to queued commands, or
   from special-move commands back to normal input playback.
3. Use `GetMode` as the state check after `StartRecording`, `StartPlayback`, and
   `StopAndReset`; do not infer the mode only from your mod's last call.
4. For command queues, queue a minimal known action first, then confirm the same
   value appears through `GetCurrentCommand_*` before building a longer script.
5. For special moves, validate both the visible move transition and the queued
   params in one training session before assuming they survive character,
   stance, or weapon changes.
6. If the dummy does not move, check whether playback/recording won the same
   frame over the CPU output. The training playback path can discard live AI
   choices in `LuxBattle_TickCharaInput`, exactly like replay input does.

!!! note "No portable Lua snippet here"
    The UFunctions are reflectable, but this page intentionally does not provide
    hard-coded UE4SS Lua calls or raw command words. Resolve the live UObject and
    parameter metadata in your runtime environment, then use the call pattern
    documented in the UE4SS pages above.

## Replay behavior summary

| Scenario | AI ticks? | Effect |
|---|---|---|
| Live play vs CPU | Yes | AI's input written to `chara+0x2150`, consumed as that frame's input |
| Replay viewing (match replay) | Yes | AI ticks, but replay decoder overwrites `chara+0x2150` first — AI's choice silently discarded |
| Training mode (dummy in PLAYBACK) | Yes | Recorded inputs win over AI in `LuxBattle_TickCharaInput`; AI's choice discarded |
| WorldTickGate freeze | **No** | Site 9 on `LuxBattle_PerFrameTick` is upstream of the entire AI tick chain — no separate gate needed |

## Practical recipe: override frame input

Use this when the mod needs a hard per-frame input override, such as a bot that
reacts to the opponent in real time, a deterministic punish trainer, or a test
harness that should ignore the stock CPU choice. This is a **native hook job**:
`LuxBattle_TickCharaInput @ 0x140312510` is not a UFunction, so UE4SS
`RegisterHook` is the wrong tool. Use a native UE4SS plugin, global detour, or
equivalent code hook; the UE4SS hook boundary is summarized in
[hooks.md](../ue4ss/hooks.md#when-lua-hooks-are-not-enough).

### Override checklist

1. Decide whether this is a soft override or a hard override. A soft override
   can use training-mode queues above. A hard override writes the final
   `chara+0x2150` frame-input value after the game has selected the frame's
   source input.
2. Instrument one side first. Log the value produced by the AI SubVM
   (`pSubVM+0x08`), the scheduler copy, and the final `chara+0x2150` value for
   a few frames before writing anything.
3. Place the write late enough that the source picker has already run. In live
   CPU play that source is usually the AI path; in replay viewing and training
   playback the recorded-input path can overwrite the AI output before the move
   system consumes it. The replay overwrite is the same determinism rule
   described in [replay-system.md](replay-system.md#lux-input-replay-opcodes).
4. Keep the override to one frame at a time. Recompute or re-copy the command
   every tick instead of assuming the previous value will be held for you.
5. Treat `chara+0x2158` as part of the raw-input pair until its exact role for
   your scenario is verified. If your override only changes `+0x2150`, log
   `+0x2158` across held inputs, releases, and simultaneous button presses so
   edge/hold behavior is not accidentally broken.
6. Verify the downstream move result through the MoveVM rather than only the
   input value. The move system page documents the scheduler and active move
   lanes that are useful for "did this input become the expected move?" checks:
   [move-system.md](move-system.md).

### Priority traps

| Symptom | Likely cause | Check |
|---|---|---|
| Value is written, but the dummy follows the recording | Training playback wins later in `LuxBattle_TickCharaInput` | Disable playback or move the native write after the playback source write. |
| Value is written during replay, but the character follows the replay file | Replay decoder overwrote the live AI/override value | Confirm whether the session is replay viewing; see [Replay System](replay-system.md). |
| First frame works, held direction/button does not | Hold/edge state is split across the raw-input pair | Compare `+0x2150` and `+0x2158` while holding and releasing a known input. |
| Move starts one frame late | Hook is before the final source write or after the move consumer | Add frame counters around `LuxBattle_TickCharaInput` and the MoveVM scheduler path. |

## Where to hook for AI mods

| Goal | Hook |
|---|---|
| Drive training dummy programmatically | Call the 11 UFunctions above via UE4SS Lua reflection |
| Override an AI's input each frame | Hook `LuxBattle_TickCharaInput @ 0x140312510` and write your own value to `chara+0x2150` before it returns (replay decoder uses the same primitive) |
| Replace a CPU behavior wholesale | Patch the SubVM at the per-slot sched state — either patch `LuxMoveVM_CreateCpuDirectState` to construct your derived class, or swap the vftable pointer at `pSubVM+0x00` post-construct |
| Add a scripted CPU drill | Mirror the `HgCpuDirectTutorial*_Init` pattern: construct a 0x70-byte CCpuDirectCommand-derived object with your Tick body and install at the sched-state SubVM slot |
| Freeze AI during a custom pause | None needed — gate `LuxBattle_PerFrameTick` (see [replay-system.md](replay-system.md)); AI tick is downstream |

## Runtime verification checklist

Before calling a dummy/CPU mod "working", verify the layer you think is in
control is actually the final input source for the frame.

| Check | What to verify |
|---|---|
| Live object resolution | Re-find the BattleManager, charas, and training actor after rematch/menu transitions. Follow the UObject validity rules in [UE4SS Lua API](../ue4ss/lua-api.md#minimal-safety-helpers). |
| Mode state | `GetMode` agrees with the intended `OFF` / `RECORDING` / `PLAYBACK` state before and after the test action. |
| Input source priority | In one instrumented run, compare the SubVM output, scheduler copy, and final `chara+0x2150` value for the same side/frame. This catches replay and training playback overwrites. |
| Raw-input pair behavior | For held inputs and releases, compare both `chara+0x2150` and `chara+0x2158`; do not assume a single dword covers every edge/hold case. |
| Move-system effect | Confirm the expected move or state change in the MoveVM layer, not only the raw input write. Use the active-lane and scheduler notes in [move-system.md](move-system.md). |
| Replay/training separation | Repeat the same test in live training, dummy playback, and replay viewing if the mod supports all three. The final input owner changes by mode; this is expected. |
| Pause/frame-step behavior | If the mod interacts with pause or stepping, test both `SetBattlePause` and native tick gates. BattleManager pause semantics and replay freeze gates are documented in [battle-manager.md](battle-manager.md#pausing-the-simulation-gates-not-dt-multiply) and [replay-system.md](replay-system.md#replay-freeze-gates). |
| Reset path | Stop playback, clear queued commands, restart the round, and confirm no stale SubVM pointer, queued command, or special-move param survives unintentionally. |

Good evidence is a short trace that ties one frame together: selected source
input -> final raw input -> MoveVM-visible move/state result. If any link in
that chain is inferred rather than observed, label the mod behavior as
runtime-validated only for the scenarios you actually tested.

## Function quick reference

| Symbol | Address | Page |
|---|---|---|
| `LuxBattleChara_GetAIStateTableField` (landmark) | `0x1402F7370` | This page |
| `LuxMoveVM_ScheduleCharaMoveForTick` | `0x1402E52D0` | This page (tick chain) |
| `LuxMoveVM_SelectMoveCommandContinuation` | `0x1402E5470` | This page (tick chain) |
| `LuxBattle_TickCharaInput` | `0x140312510` | This page (frame-input target) |
| `LuxMoveVM_SchedState_CommitCommandSlot` | `0x1402E5660` | This page (special-move bypass) |
| `LuxMoveVM_CreateCpuDirectState` | `0x1402E26A0` | This page (SubVM factory) |
| `LuxBattle_InitCpuPersonalityData` | `0x140364950` | This page (personality) |
| `LuxBattle_RefreshCpuPersonalityData` | `0x140364BC0` | This page (personality) |
| `LuxBattle_ComputeAllPersonalitySlots` | `0x140395320` | This page (personality) |
| `LuxBattle_ComputePersonalityActionWeights` | `0x140394FE0` | This page (personality) |
| `LuxTrainingDummy_StartRecording` | `0x1402D3C70` | This page (training mode) |
| `LuxTrainingDummy_StartPlayback` | `0x1402D3D20` | This page (training mode) |
| `LuxTrainingDummy_QueueCommand_AtSlot` | `0x1402D3E50` | This page (training mode) |
| `LuxTrainingDummy_QueueSpecialMove1Param` | `0x1402D3F90` | This page (training mode) |
| `LuxMoveVM_TickPickAndDispatchReaction` | `0x1402DEF50` | [move-system.md](move-system.md) (yarare classifier) |
