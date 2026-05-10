# Replay System

How SC6 records and plays back a match. Critically: **a "frozen" replay is not
the same as a frozen training match** — replay viewing has at least seven
independent tick paths that keep advancing chara state, the round timer,
recorded-input cursors, and animation. Stopping `LuxBattle_PerFrameTick`
alone (the simulation-core entry point) leaves all of them running.

All addresses absolute (image base `0x140000000`).

## At a glance

### The replay master clock and what advances it

`ALuxBattleFrameInputLog +0x3A4` is the per-match **master clock** — a
plain `int32` that increments once per UE4 frame in a normal match.
`ALuxBattleManager`'s simulation loop reads it as `delta = master - lastApplied`
and runs `delta` iterations of input/round-state catch-up. Two sibling
functions write to it with identical semantics; both must be gated to
truly pin the clock:

| Site | Function | INC at | Dispatcher | What it does |
|------|----------|--------|------------|---------------|
| **R1** | `LuxBattleChara_VTable648_TickAndAdvanceReplayClock` | `+0x2A` | unconditional | `inc dword [rbx+0x3A4]` after three vtable sub-tick calls |
| **R2** | `LuxBattleChara_VTable648_TickAndAdvanceReplayClock_GatedBy4404` | `+0x33` | `cmp byte [rcx+0x4404], 0` then unconditional INC | live-tick path for the same clock |

The two functions exist because they sit on different vtable slots and
fire from different parents. The INC instruction is identical in both:
`FF 83 A4 03 00 00` (`inc dword [rbx+0x3A4]`).

### The seven tick paths to halt for a frozen replay

Verified in HorseMod's gate stack. Each is a separate Actor::Tick chain
that drives chara/replay/round state independently of `PerFrameTick`:

| Site | Function | RVA | Drives |
|------|----------|-----|--------|
| **9** | `LuxBattle_PerFrameTick` | `0x1402DBC60` | The simulation core. Hit detection, MoveVM, frame counter, position integration. |
| **11** | `LuxBattleChara_Tick_AdvanceReplayFrame_OrLocal` | `0x1403F8410` | **Primary replay-input leak.** In replay mode dispatches `vtable[0x6A8]` (Stage 2/3 input pipeline) and `vtable[0x6C8]` (chara replay-state writer). Pushes the recorded input into the chara's active slot every UE4 frame. |
| **20** | `LuxActor_Tick_CallVtable5f8` (`ALuxBattleFrameInputLog::TickActor`) | `0x1403FBDF0` | InputLog actor's tick. Dispatches `vtable[0x5F8]` → counter advance at `InputLog+0x3AC`, Stage 2/3 input dispatch, master-clock INC sibling. |
| **21** | `LuxBattleManager_Tick_MainStateMachine_At1461` | `0x1403FBF30` | BM main state machine. Calls `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState` (the catch-up loop) and the round-over check. |
| **21b** | `ALuxBattleManager_Update_Impl` | `0x140437590` | BM tick that drives `BattleTime` / `BattleSystemTime` FName timers. The round timer. |
| **22** | `ALuxBattleChara_TickActor` | `0x1403D0590` | Chara base TickActor — Maegami hair, weapon mesh anim, SC charge gauge, parent-class actor tick. Long anim montages play out via this path even with sim frozen. |
| **22b** | `ALuxDemoHumanActor_TickActor` | `0x1404865B0` | Derived class. Inherits `ALuxBattleChara`. Used for **match-replay cinematic playback**. Body runs anim-track playback BEFORE tail-calling super, so Site 22 alone doesn't catch it. |
| **22c** | `APreviewHumanActor_TickActor` | `0x140486C60` | Sibling of 22b (menu chara previews / cinematic paths). |

### The TimeDilation bypass — why VMFreezeByte alone fails replay

`g_LuxBattle_VMFreezeRecord.bVMFreezeByte` (the canonical "hitstop" lever
documented in [movement.md](movement.md#timedilation-system-verified)) is
**bypassed** by `LuxMoveVM_GetTimeDilationScalar @ 0x14030A8C0` for normal-play
characters in replay viewing — see
[TimeDilation fall-through paths](#timedilation-fall-through-paths-bypasses-vmfreezebyte) below.
A complete replay freeze needs an entry-RET on `GetTimeDilationScalar` that
returns 0.0 unconditionally, *plus* the seven Actor::Tick gates above.

---

## Per-frame chain (replay viewing)

Once per UE4 frame, replay-watching state advances along **all** of these
paths in parallel. Numbers are not strict ordering — UE4 dispatches actor
ticks based on tick-group / depends-on; what matters is that each one is
reached *every* frame regardless of `PerFrameTick`.

```text
UE4 World tick
├── Site 9  — LuxBattle_PerFrameTick                       (simulation core)
│            └── TickCharaMainSimulation × N charas
│                  └── MoveVM, hit detection, integrator, frame counter
│
├── Site 20 — LuxActor_Tick_CallVtable5f8                  (FrameInputLog)
│            └── vtable[0x5F8] → counter advance @ InputLog+0x3AC
│                + Stage 2/3 input dispatch
│                + sibling that calls into Site R1/R2
│
├── Site 11 — LuxBattleChara_Tick_AdvanceReplayFrame_OrLocal (per chara)
│            ├── REPLAY mode  → vtable[0x6A8]  (Stage 2/3 pipeline)
│            │                  vtable[0x6C8]  (chara replay-state writer)
│            └── LIVE mode    → local input dispatch
│
├── Site 22{,b,c} — Chara TickActor variants               (per chara)
│                  └── anim playback, hair, weapon mesh, SC gauge
│
├── Site 21  — BM_Tick_MainStateMachine_At1461             (BattleManager)
│            ├── LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState
│            │     loop: while (master_clock - last_applied > 0)
│            │       ├── apply recorded input from InputLog ring
│            │       ├── advance round state machine
│            │       └── INC nFrameAdvanceCounter
│            └── round-over check
│
└── Site 21b — ALuxBattleManager_Update_Impl               (BM round timer)
              └── BattleTime / BattleSystemTime FName timers (TickTimerHandle)
```

Both R1 (`0x1403E1FC0`) and R2 (`0x1403E2000`) — the master-clock INC
functions — are reached as sub-ticks under one of the above. R2's prologue
checks `cmp byte [rcx+0x4404], 0` (the InputLog double-tick guard) before
running its body; R1 is unconditional.

## `ALuxBattleFrameInputLog` field map (replay-relevant)

Verified offsets used by the replay tick chain. Full struct in
[Game Structures](structures.md#aluxbattleframeinputlog-17428-bytes).

| Offset | Type | Name | Set/read by |
|-------:|------|------|-------------|
| `+0x39C` | `uint32` | `dwPlaybackCursor` | written by Site 20 chain |
| `+0x3A0` | `int32` | `nLastFrameID` | written by Site 20 chain |
| **`+0x3A4`** | `int32` | **`nMasterClock`** | **INC'd by R1 / R2 every UE4 frame.** Read as `delta = master - lastApplied` by `SimulationLoop_UpdateInputAndRoundState`. |
| `+0x3A8` | `void*` | `pRecordedFrameBuffer` | array of `FLuxRecordedFrame` (192 B each) |
| `+0x3AC` | `int32` | (counter) | INC'd via `vtable[0x5F8]` from Site 20. Sub-tick advance counter. |
| `+0x3B0` | `int32` | `nTotalRecordedFrames` | |
| **`+0x4404`** | `bool` | **`bDoubleTickGuard`** | **Per-frame re-entrancy gate.** R2 checks this; Site 11 also gates on `cmp dword [rcx+0x4400], 0` (a wider guard at +0x4400). |
| `+0x4410` | `int32` | `nDrainCursor` | |

The ring at `+0x3A8 → FLuxRecordedFrame[]` is sized for ~90 frames
(17 KB / 192 B ≈ 90.7). At 60 fps that's ≈ 1.5 s of recorded input —
enough to bridge a tick-rate hiccup without dropping frames, not enough
to seek arbitrarily far into the past in a single drain.

## SimulationLoop catch-up

`LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState @ 0x1403FE520`
is the consumer side. Sketch:

```text
delta = InputLog.nMasterClock - InputLog.nLastApplied
while (delta-- > 0):
    apply one frame of recorded input from the ring buffer
    advance round-state machine
    INC nFrameAdvanceCounter
    drain one InputLog frame entry
```

This is why a naive freeze that pauses `PerFrameTick` but lets the master
clock advance produces a **fast-forward burst** on unfreeze: the master
clock has been climbing the whole time, `delta` accumulates, and on
unfreeze the loop runs `delta` iterations *in a single BM tick*.

The HorseMod fix is to pin `nMasterClock` itself via the R1/R2 INC gates
([`Horse::ReplayClockGate`](#horsemod-gate-stack-summary) below), so
`delta` cannot grow during freeze and the catch-up loop stays a no-op.

## TimeDilation fall-through paths (bypasses `VMFreezeByte`)

`LuxMoveVM_GetTimeDilationScalar @ 0x14030A8C0` is the per-chara time-scale
multiplier consulted by every dt-scaled integrator (position, MoveVM advance,
anim montage, hit detection, etc.). It has **four return paths**, only one
of which honours `bVMFreezeByte`:

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

                // PATH B — normal play. Honours VMFreezeByte.
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

### Why this matters for replay viewing

In replay watching the chara's match-state byte at `+0x19EC` is **2**
(normal play) — even though inputs come from a recorded file, the state
byte stays 2 the entire time. For P1 (`charaKindByte == 0`), the entry
gate evaluates to `(2 != 2) || (0 != 0 && ...)` = `FALSE`, so Path A/B
is skipped and the function falls through to `chara+0x3500` (normally
`1.0f`). Setting `bVMFreezeByte = 1` does **nothing** for P1 in this
state — UE4 anim instances scale by the engine's tick dilation, so the
replay continues advancing.

The HorseMod fix is an entry-RET trampoline that returns `0.0f` whenever
the freeze policy slot is 0, irrespective of the chara's match-state
byte ([`Horse::TimeDilationGate`](#horsemod-gate-stack-summary)).

> **Why hit-stop / super-freeze still work in stock SC6**: the engine
> writes `chara+0x3510` to a negative value during super-flash (Path A)
> or transitions chara state out of `2` during cinematics (Path B), so
> the VMFreezeByte path actually executes. Plain `bVMFreezeByte = 1` from
> a mod, with the chara still in state==2 and `+0x3510` non-negative,
> never reaches a path that consults the byte.

## Stage 2/3 input pipeline (vtable[0x6A8] / [0x6C8])

`Site 11 (LuxBattleChara_Tick_AdvanceReplayFrame_OrLocal)` dispatches
two vtable slots in REPLAY mode:

| Slot | Role | Effect |
|-----:|------|--------|
| `vtable[0x6A8]` | Stage 2/3 input pipeline | Walks the InputLog frame buffer and pushes the next recorded input bitmask into the chara's input ring |
| `vtable[0x6C8]` | Chara replay-state writer | Writes recorded chara state into `+0x39C/+0x3A0/+0x3A8/etc.` (the per-chara replay-state fields) |

`LuxBattleChara_ReplayPlayback_PushInputsToActiveSlots @ 0x1403F6600` is
the actual Stage-3 push function. It drains the InputLog ring into
`chara+0x3C0..` (active-input slot), one entry per UE4 frame.

This is the path that produces the visible "stepping shows held inputs"
symptom: if the master clock keeps advancing during freeze, the InputLog
ring fills with buffered inputs, then on unfreeze the push function
empties the entire ring in one tick — visible as the chara mashing
buttons.

## HorseMod gate stack summary

| Component | Hooks | Role |
|-----------|-------|------|
| `Horse::WorldTickGate` | Site 9 | Owns the policy slot. RET on PerFrameTick when slot=0; consume one credit when slot>0. |
| `Horse::ReplayClockGate` | INC at `R1+0x2A`, INC at `R2+0x33` | Skip the master-clock INC when policy=0. Keeps `delta=0` so SimulationLoop's catch-up loop is a no-op during freeze. |
| `Horse::ActorTickGate` | Sites 11, 20, 21, 21b, 22, 22b, 22c | Entry-RET on each Actor::Tick prologue when policy=0. Halts the six tick chains that aren't covered by Site 9. |
| `Horse::TimeDilationGate` | `LuxMoveVM_GetTimeDilationScalar @ 0x14030A8C0` entry | Force return `0.0f` (XORPS XMM0; RET) when policy=0. Bypasses the function's state==2 fall-through that would otherwise return `chara+0x3500` ≈ 1.0. |

The four gates share a single `int32_t` policy slot:

| Slot value | Meaning |
|-----------:|---------|
| `0`        | Frozen — every gated path bails (bare RET). |
| `> 0`      | Step credits — gated paths run; PerFrameTick consumes one credit per observed run. |
| `< 0`      | Treated as "always run" (defensive equivalent of native; sibling gates never write negative). |

Only `WorldTickGate` decrements credits — sibling gates read the slot
and never modify it. This avoids tick-order off-by-one bugs (e.g. if
sibling A ran first and dec'd 1→0, sibling B in the same UE4 frame
would see 0 and bail, even though the credit was for "this frame").

The "Native" mode (mod disabled) is achieved by leaving every BytePatch
disabled — there is no policy-slot-driven "always run" mode in normal
operation.

## Code references

| Symbol | RVA | Role |
|---|---|---|
| `LuxBattle_PerFrameTick` | `0x1402DBC60` | Site 9. Simulation core entry. |
| `LuxBattleChara_Tick_AdvanceReplayFrame_OrLocal` | `0x1403F8410` | Site 11. Per-chara replay-frame advance. |
| `LuxActor_Tick_CallVtable5f8` | `0x1403FBDF0` | Site 20. `ALuxBattleFrameInputLog::TickActor` — dispatches `vtable[0x5F8]`. |
| `LuxBattleManager_Tick_MainStateMachine_At1461` | `0x1403FBF30` | Site 21. BM main state-machine tick + simulation-loop call. |
| `ALuxBattleManager_Update_Impl` | `0x140437590` | Site 21b. BM round-timer driver. |
| `ALuxBattleChara_TickActor` | `0x1403D0590` | Site 22. Base chara TickActor. |
| `ALuxDemoHumanActor_TickActor` | `0x1404865B0` | Site 22b. Replay cinematic chara TickActor (derived). |
| `APreviewHumanActor_TickActor` | `0x140486C60` | Site 22c. Menu preview chara TickActor (derived). |
| `LuxBattleChara_VTable648_TickAndAdvanceReplayClock` | `0x1403E1FC0` | Site R1. INC at `+0x2A` (`inc dword [rbx+0x3A4]`). |
| `LuxBattleChara_VTable648_TickAndAdvanceReplayClock_GatedBy4404` | `0x1403E2000` | Site R2. INC at `+0x33`, gated by `+0x4404`. |
| `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState` | `0x1403FE520` | Catch-up loop consumer. Reads `delta = master - lastApplied`. |
| `LuxBattleChara_ReplayPlayback_PushInputsToActiveSlots` | `0x1403F6600` | Stage-3 push: drains InputLog ring into chara active-input slot. |
| `LuxMoveVM_GetTimeDilationScalar` | `0x14030A8C0` | Per-chara time scale. Four return paths; only Path B honours `bVMFreezeByte`. |
| `g_LuxBattle_VMFreezeRecord` | `0x1448462D0` | 64-byte record. `bVMFreezeByte` at `+0x00`, `flBaseAlpha` at `+0x04`. |

## Practical notes for mods

- **Freezing a replay is not freezing a training match.** A "pause" that
  works in training (e.g. `bVMFreezeByte=1` alone, or `SetBattlePause`)
  will visibly leak in replay viewing — chara anims keep playing, the
  round timer drains, the replay auto-advances.
- **`SetBattlePause` keeps six handlers running by design** (see
  [`OnBattleTickWhenPaused`](battle-manager.md#onbattletickwhenpaused-what-still-ticks-during-setbattlepausetrue)).
  One of those is `ALuxBattleFrameInputLog @ BM+0x478` — i.e. SC6's own
  pause path *intentionally* keeps the replay-cursor handler alive.
- **The seven Actor::Tick sites are not exhaustive** for every conceivable
  freeze use case. They cover the paths that drive *gameplay-relevant*
  state. UMG widget Tick, particle/Niagara render time, audio, and
  non-battle actors continue regardless. For full pause semantics
  including UI, use UE4's `bGamePaused`.
- **Step credits drain one per `PerFrameTick` run, not per UE4 frame.**
  If a UE4 frame fires multiple gated paths in any order, all of them
  see the same policy value for the entire frame — no off-by-one drift.
  This is why decrement is owned exclusively by Site 9.
