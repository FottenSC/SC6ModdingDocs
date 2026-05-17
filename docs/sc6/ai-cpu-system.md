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

## Replay behavior summary

| Scenario | AI ticks? | Effect |
|---|---|---|
| Live play vs CPU | Yes | AI's input written to `chara+0x2150`, consumed as that frame's input |
| Replay viewing (match replay) | Yes | AI ticks, but replay decoder overwrites `chara+0x2150` first — AI's choice silently discarded |
| Training mode (dummy in PLAYBACK) | Yes | Recorded inputs win over AI in `LuxBattle_TickCharaInput`; AI's choice discarded |
| WorldTickGate freeze | **No** | Site 9 on `LuxBattle_PerFrameTick` is upstream of the entire AI tick chain — no separate gate needed |

## Where to hook for AI mods

| Goal | Hook |
|---|---|
| Drive training dummy programmatically | Call the 11 UFunctions above via UE4SS Lua reflection |
| Override an AI's input each frame | Hook `LuxBattle_TickCharaInput @ 0x140312510` and write your own value to `chara+0x2150` before it returns (replay decoder uses the same primitive) |
| Replace a CPU behavior wholesale | Patch the SubVM at the per-slot sched state — either patch `LuxMoveVM_CreateCpuDirectState` to construct your derived class, or swap the vftable pointer at `pSubVM+0x00` post-construct |
| Add a scripted CPU drill | Mirror the `HgCpuDirectTutorial*_Init` pattern: construct a 0x70-byte CCpuDirectCommand-derived object with your Tick body and install at the sched-state SubVM slot |
| Freeze AI during a custom pause | None needed — gate `LuxBattle_PerFrameTick` (see [replay-system.md](replay-system.md)); AI tick is downstream |

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
