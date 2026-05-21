# SoulCalibur VI Internals

Reverse-engineering reference for SoulCalibur VI (Steam, monolithic
`SoulcaliburVI.exe`, UE4 4.17–4.21).

## Binary identity

| Field | Value |
|-------|-------|
| Image base | `0x140000000` |
| Module | `SoulcaliburVI.exe` (monolithic — no separate `LuxorGame.dll`) |
| Source-path prefix in strings | `D:\dev\sc6\UE4_Steam\LuxorProto\Source\LuxorGame\...` |
| Internal codename | **Luxor** (first-party classes are `ALux*` / `ULux*` / `FLux*`) |
| Engine version | 4.17–4.21 (verify via `[PS] Found EngineVersion: 4.XX` in `UE4SS.log`) |
| Recommended UE4SS build | `LessEqual421` (covers any ≤ 4.21) |

## Pages

| Page | Covers |
|------|--------|
| [Game Structures](structures.md) | Class layouts, field offsets, struct index. **Start here for "where is X?".** |
| [Battle Manager](battle-manager.md) | `ALuxBattleManager` slot map, UFunctions, DataTable config tree, `SetBattlePause`. |
| [Hitbox System](hitbox-system.md) | KHit linked lists — the live hit-detection pipeline (strikes, kicks, hurtboxes, pushboxes, grabs). |
| [Reaction System](reaction-system.md) | **Post-hit** state machine — yarare dispatch, 80-id reaction table, gate-family taxonomy, knockdown camera, throw-react. |
| [Trace System](trace-system.md) | `FLuxCapsule` + `ALuxTraceManager` — the **visual** weapon-trail / sword-swoosh VFX (not hit detection). |
| [Stage System](stage-system.md) | Master enum table, stage-code routing, DLC gating, `LuxBattleStageInfoTableRow`, two-tier collision, custom-stage mod pipeline. |
| [Movement System](movement.md) | Per-character step / 8WR table, conditions that modify step performance (hitstop, Soul Charge, face flip, state index). |
| [Battle Message System](messages.md) | `ELuxBattleMessage` enum, `FLuxBattleMessageParam` struct, `ULuxBattleMessageReceiverInterface`, broadcast dispatchers, modder-feasibility notes. |
| [Replay System](replay-system.md) | Per-frame replay tick chain, master clock at `FrameInputLog+0x3A4`, the seven Actor::Tick paths a freeze must halt, `TimeDilation` fall-through that bypasses `VMFreezeByte`. |
| [Leaderboards & Online](leaderboards.md) | Steam leaderboards (`Characterboard`, `RankmatchWorld/Asia/...`), BNED Cosmos Channel telemetry, building an external API client. |
| [Move System](move-system.md) | Command-script bytecode VM, opcode dispatch, IF predicates. |
| [Audio System](audio-system.md) | CRI ADX2 middleware + `UAtomComponent`, MoveVM-to-cue routing via `g_pLuxVfxDispatcher`, DramaticVoice triggers, weapon-SE bank routing, DLC ACB folder map, PartsSE / costume-part SE. |
| [CPU / AI System](ai-cpu-system.md) | Per-frame AI tick chain, frame-input output target, `HgCpuDirect*` SubVM framework, personality / difficulty data, training-mode UFunction API. |
| [Character Data](character-data.md) | Style ids, DataTable asset paths, move-list display schema. |
| [Drawing 3D Debug Lines](line-batching.md) | `ULineBatchComponent` recipe — the one live debug-draw path. |
| [Dev / Debug Hooks](dev-debug-hooks.md) | Inventory of developer-facing hooks: what works, what's stripped. |

## Quick-find: where do I look for X?

| Question | Page |
|----------|------|
| "Where is `chara+0xNNN`?" | [Game Structures: ALuxBattleChara](structures.md#aluxbattlechara) |
| "How do hitboxes / hit detection work?" | [Hitbox System](hitbox-system.md) |
| "What happens AFTER a hit lands — stun, launch, knockdown, ringout?" | [Reaction System](reaction-system.md) — yarare dispatch + per-id Tick handler family. |
| "What's the yarare-id taxonomy (0x1F = launcher, 0x1E = knockdown, etc.)?" | [Reaction System: EYarareReactionId](reaction-system.md#eyararereactionid-per-vm-slot-reaction-id) |
| "How does the knockdown camera work?" | [Reaction System: Knockdown camera](reaction-system.md#knockdown-camera-adjacent-state-machine) |
| "How do weapon trails / sword swooshes work?" | [Trace System](trace-system.md) |
| "How far does each character step?" | [Movement System](movement.md) |
| "What changes how well a character moves?" | [Movement System: verified levers](movement.md#what-changes-movement-verified-levers-only) |
| "How do I add / replace a stage?" | [Stage System](stage-system.md) |
| "Why do some stages roll more often in random?" | [Stage System: Random-pool bias](stage-system.md#random-pool-bias) |
| "How do I read character usage / ranked-match data outside the game?" | [Leaderboards & Online](leaderboards.md) |
| "What's the difference between rank id, rank point, and style id?" | [Leaderboards & Online: ranking internals](leaderboards.md#ranking-internals) |
| "How do I tell if my mod is running in an online match?" | [Leaderboards & Online: detection](leaderboards.md#detection-is-this-match-online) — call `ALuxBattleManager_CheckOnlineSessionActive @ 0x1403F2590` or read `FrameInputLog+0x4400` |
| "How does opponent input get into the game during online play?" | [Leaderboards & Online: per-frame input chain](leaderboards.md#per-frame-input-chain-channel-5) — Steam P2P → push deque → drain → per-slot cache at `FrameInputLog+0x3C0` |
| "How does the on-screen *Counter Hit* / *Punish Attack* / *Throw Escape* banner work?" | [Battle Message System](messages.md) |
| "Can I show a custom HUD banner from a mod?" | [Battle Message System: Modder feasibility](messages.md#modder-feasibility-can-we-send-our-own-messages) |
| "Where's the move VM?" | [Move System](move-system.md) |
| "How does the game play sounds? Wwise / FMOD / CRI?" | [Audio System](audio-system.md) — CRI ADX2 / ATOMCRAFT. |
| "Where do weapon SE / character voice `.acb` files live?" | [Audio System: weapon SE bank routing](audio-system.md#weapon-se-bank-routing) and [per-character voice ACB maps](audio-system.md#per-character-voice-acb-maps). |
| "How do DramaticVoice / story-mode voice triggers work?" | [Audio System: DramaticVoice](audio-system.md#3-dramaticvoice-story-persona). |
| "Why are my custom-costume footsteps / cloth silent?" | [Audio System: PartsSE](audio-system.md#costume-part-se-partsse-partsbreak) — costume parts have their own cue trigger family. |
| "Why does my fast-forward UX flood the player with overlapping voices?" | [Audio System: thread model](audio-system.md#thread-model-what-runs-where) — burst-playback warning + mitigations. |
| "How does the CPU opponent decide what to do?" | [CPU / AI System](ai-cpu-system.md) — AI emits frame inputs, not MoveVM commands; selected by personality + condition vector. |
| "How do I drive the training-mode dummy from a mod?" | [CPU / AI System: Training-mode UFunctions](ai-cpu-system.md#training-mode-ufunctions) — 11 live UFunctions, all UE4SS-reflectable. |
| "Does AI tick during replay viewing?" | [CPU / AI System: Replay behavior](ai-cpu-system.md#replay-behavior-summary) — yes, but the AI's output is silently discarded by the replay decoder. |
| "How do I draw a debug line?" | [Drawing 3D Debug Lines](line-batching.md) |
| "How do I pause the game?" | [Battle Manager: `SetBattlePause`](battle-manager.md#pause-inspection-bp-api-uluxbattlefunctionlibrary) |
| "How do I freeze a *replay* (not just a training match)?" | [Replay System](replay-system.md) — `SetBattlePause` and `VMFreezeByte` both leak in replay viewing; needs the seven-site Actor::Tick gate stack. |
| "Why does my freeze release as a fast-forward burst in replay viewing?" | [Replay System: SimulationLoop catch-up](replay-system.md#simulationloop-catch-up) — master clock keeps advancing during freeze, `delta` accumulates, drains in one tick on release. |
| "How do I scrub / seek inside a match replay?" | [Replay System: scrubbing](replay-system.md#scrubbing-a-match-replay-udemonetdrivergototimeinseconds) — UE4's native `UDemoNetDriver::GotoTimeInSeconds` is intact; CVar `demo.GotoTimeInSeconds` exposes it too. |
| "What's the difference between training replays and match replays?" | [Replay System: two subsystems](replay-system.md#two-replay-subsystems) — training = custom Lux input pipeline; match-replay menu = UE4 `UDemoNetDriver`. |
| "What does `ULuxDevBattleHUDSetting` do?" | [Dev / Debug Hooks](dev-debug-hooks.md) |
| "What's the move-data DataTable schema?" | [Character Data](character-data.md) |

## Conventions used on these pages

- All addresses are **absolute** with image base `0x140000000` unless explicitly RVA.
- `chara+0xNNN` always means relative to `ALuxBattleChara*`.
- `vmCtx+0xNNN` always means relative to `FLuxMoveCommandPlayer*` (the per-chara VM slot).
- `BM+0xNNN` always means relative to `ALuxBattleManager*`.
- `InputLog+0xNNN` always means relative to `ALuxBattleFrameInputLog*`.
- Struct sizes given as both decimal and `0x` hex where useful.
- **Status markers** applied consistently:
    - **verified** — read directly from Ghidra decompile or live UE4SS introspection. Trust.
    - **unverified** — plausible but not directly confirmed. Don't build on without checking.
    - **stale on this build** — present in the binary but not on the live codepath. Don't use.
    - `> source:` blockquote — points at the authoritative Ghidra address/function.
    - `!!! warning` admonition — known landmine, layout error, or correction.

For cross-cutting lookups across all SC6 pages, see
[Reference: Symbol Index](../reference/symbol-index.md).

## UE4SS reflection caveat

Some live UFunctions can't be called from UE4SS Lua reflection. They were registered
with the short `UE4_RegisterClass` variant (no `Ex`), so their parameter UProperty
metadata is missing — and UE4SS misreports the failure as
*"Tried calling a member function but the UObject instance is nullptr"*. Notable
cases: `ALuxBattleChara::Active` / `Inactive` / `GetTracePosition`. Inherited
`AActor` UFunctions (e.g. `K2_GetActorLocation`) still work. See
[UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md).
