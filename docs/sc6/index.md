# SoulCalibur VI Internals

Reverse-engineering reference for SoulCalibur VI (Steam, monolithic
`SoulcaliburVI.exe`, Unreal Engine 4.17.2).

## Binary identity

| Field | Value |
|-------|-------|
| Image base | `0x140000000` |
| Module | `SoulcaliburVI.exe` (monolithic — no separate `LuxorGame.dll`) |
| Source-path prefix in strings | `D:\dev\sc6\UE4_Steam\LuxorProto\Source\LuxorGame\...` |
| Internal codename | **Luxor** (first-party classes are `ALux*` / `ULux*` / `FLux*`) |
| Engine version | Unreal Engine 4.17.2 |

## Pages

| Page | Covers |
|------|--------|
| [Game Structures](structures.md) | Class layouts, field offsets, struct index. **Start here for "where is X?".** |
| [Battle Manager](battle-manager.md) | `ALuxBattleManager` slot map, UFunctions, DataTable config tree, `SetBattlePause`. |
| [Hitbox System](hitbox-system.md) | KHit linked lists — the live hit-detection pipeline (strikes, kicks, hurtboxes, pushboxes, grabs). |
| [Reaction System](reaction-system.md) | **Post-hit** state machine — yarare dispatch, 80-id reaction table, gate-family taxonomy, knockdown camera, throw-react. |
| [Trace System](trace-system.md) | `FLuxCapsule` + `ALuxTraceManager` — the **visual** weapon-trail / sword-swoosh VFX (not hit detection). |
| [Stage System](stage-system.md) | Master enum table, stage-code routing, DLC gating, `LuxBattleStageInfoTableRow`, collision storage, custom-stage mod pipeline. |
| [Character and Stage Selection Menus](selection-menus.md) | Character-select roster builders, selected/decided setup keys, stage picker inputs, arcade/mission stage resolvers, and custom-character submenu feasibility. |
| [Movement System](movement.md) | Per-character step / 8WR table, conditions that modify step performance (hitstop, Soul Charge, face flip, state index). |
| [Battle Message System](messages.md) | `ELuxBattleMessage` enum, `FLuxBattleMessageParam` struct, `ULuxBattleMessageReceiverInterface`, broadcast dispatchers, modder-feasibility notes. |
| [Replay System](replay-system.md) | Per-frame replay tick chain, master clock at `FrameInputLog+0x3A4`, Site 9 plus seven Actor::Tick gates for replay freeze, `TimeDilation` fall-through that bypasses `VMFreezeByte`. |
| [Leaderboards & Online](leaderboards.md) | Steam leaderboards (`Characterboard`, `RankmatchWorld/Asia/...`), BNED Cosmos Channel telemetry, building an external API client. |
| [Online Matchmaking](online-matchmaking.md) | `ULuxorSessionHub` create/find helpers, player-room and ranked-match session metadata, repeated-result filtering, rematch-data caveats. |
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
| "How do character select and map select menus work?" | [Character and Stage Selection Menus](selection-menus.md) |
| "Can the custom-character submenu select modded stages?" | [Character and Stage Selection Menus: Custom-character submenu as a stage selector](selection-menus.md#custom-character-submenu-as-a-stage-selector) |
| "Where does match setup copy stage/rules/player tables into the BattleManager?" | [Battle Manager: Battle launcher startup path](battle-manager.md#battle-launcher-startup-path) |
| "Why do some stages roll more often in random?" | [Stage System: Random-pool bias](stage-system.md#random-pool-bias) |
| "How do I read character usage / ranked-match data outside the game?" | [Leaderboards & Online](leaderboards.md) |
| "What's the difference between rank id, rank point, and style id?" | [Leaderboards & Online: ranking internals](leaderboards.md#ranking-internals) |
| "How does matchmaking search rooms or handle repeated ranked results?" | [Online Matchmaking](online-matchmaking.md) |
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
| "How do I drive the training-mode dummy from a mod?" | [CPU / AI System: Training-mode UFunctions](ai-cpu-system.md#training-mode-ufunctions) — 11 live UFunctions with native bodies. |
| "Does AI tick during replay viewing?" | [CPU / AI System: Replay behavior](ai-cpu-system.md#replay-behavior-summary) — yes, but the AI's output is silently discarded by the replay decoder. |
| "How do I draw a debug line?" | [Drawing 3D Debug Lines](line-batching.md) |
| "How do I pause the game?" | [Battle Manager: `SetBattlePause`](battle-manager.md#pause-inspection-bp-api-uluxbattlefunctionlibrary) |
| "How do I freeze a *replay* (not just a training match)?" | [Replay System](replay-system.md#replay-freeze-gates) — `SetBattlePause` and `VMFreezeByte` both leak in replay viewing; needs Site 9 plus the seven Actor::Tick gate stack. |
| "Why does my freeze release as a fast-forward burst in replay viewing?" | [Replay System: SimulationLoop catch-up](replay-system.md#simulationloop-catch-up) — master clock keeps advancing during freeze, `delta` accumulates, drains in one tick on release. |
| "How do I scrub / seek inside a match replay?" | [Replay System: seeking status](replay-system.md#replay-seeking-status) — Lux replay round navigation is verified; DemoNetDriver seek exists but is not the default SC6 replay scrub path. |
| "What's the format of SC6's replay input stream?" | [Replay System: Lux input replay opcodes](replay-system.md#lux-input-replay-opcodes) — 3-byte opcode records expanded into 8-byte `{frame,cursor,p1,p2}` records. |
| "What's the relationship between Lux replays and DemoNetDriver?" | [Replay System: replay backends](replay-system.md#replay-backends-present-in-the-binary) — SC6 replay-menu evidence points to Lux replay/player/input-log code; DemoNetDriver is present UE engine code but not validated as the SC6 replay authority. |
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
    - **verified** — read directly from Ghidra decompile or live runtime memory/introspection probes. Trust.
    - **unverified** — plausible but not directly confirmed. Don't build on without checking.
    - **stale on this build** — present in the binary but not on the live codepath. Don't use.
    - `> source:` blockquote — points at the authoritative Ghidra address/function.
    - `!!! warning` admonition — known landmine, layout error, or correction.

For cross-cutting lookups across all SC6 pages, see
[Reference: Symbol Index](../reference/symbol-index.md).

## Reflected-call caveat

Some live UFunctions were registered with the short `UE4_RegisterClass` variant
(no `Ex`), so their parameter UProperty metadata is missing. Notable cases:
`ALuxBattleChara::Active` / `Inactive` / `GetTracePosition`. Treat those as
native `_Impl` call or lower-level data-hook targets instead of reflected-call
APIs.
