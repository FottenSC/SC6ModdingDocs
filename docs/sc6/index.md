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
| [Trace System](trace-system.md) | `FLuxCapsule` + `ALuxTraceManager` — the **visual** weapon-trail / sword-swoosh VFX (not hit detection). |
| [Stage System](stage-system.md) | Master enum table, stage-code routing, DLC gating, `LuxBattleStageInfoTableRow`, two-tier collision, custom-stage mod pipeline. |
| [Leaderboards & Online](leaderboards.md) | Steam leaderboards (`Characterboard`, `RankmatchWorld/Asia/...`), BNED Cosmos Channel telemetry, building an external API client. |
| [Move System](move-system.md) | Command-script bytecode VM, opcode dispatch, IF predicates. |
| [Character Data](character-data.md) | Style ids, DataTable asset paths, move-list display schema. |
| [Drawing 3D Debug Lines](line-batching.md) | `ULineBatchComponent` recipe — the one live debug-draw path. |
| [Dev / Debug Hooks](dev-debug-hooks.md) | Inventory of developer-facing hooks: what works, what's stripped. |

## Quick-find: where do I look for X?

| Question | Page |
|----------|------|
| "Where is `chara+0xNNN`?" | [Game Structures: ALuxBattleChara](structures.md#aluxbattlechara) |
| "How do hitboxes / hit detection work?" | [Hitbox System](hitbox-system.md) |
| "How do weapon trails / sword swooshes work?" | [Trace System](trace-system.md) |
| "How do I add / replace a stage?" | [Stage System](stage-system.md) |
| "Why do some stages roll more often in random?" | [Stage System: Random-pool bias](stage-system.md#random-pool-bias) |
| "How do I read character usage / ranked-match data outside the game?" | [Leaderboards & Online](leaderboards.md) |
| "Where's the move VM?" | [Move System](move-system.md) |
| "How do I draw a debug line?" | [Drawing 3D Debug Lines](line-batching.md) |
| "How do I pause the game?" | [Battle Manager: `SetBattlePause`](battle-manager.md#pause-inspection-bp-api-uluxbattlefunctionlibrary) |
| "What does `ULuxDevBattleHUDSetting` do?" | [Dev / Debug Hooks](dev-debug-hooks.md) |
| "What's the move-data DataTable schema?" | [Character Data](character-data.md) |

## Conventions used on these pages

- All addresses are **absolute** with image base `0x140000000` unless explicitly RVA.
- `chara+0xNNN` always means relative to `ALuxBattleChara*`.
- `vmCtx+0xNNN` always means relative to `FLuxMoveCommandPlayer*` (the per-chara VM slot).
- `BM+0xNNN` always means relative to `ALuxBattleManager*`.
- Struct sizes given as both decimal and `0x` hex where useful.

## UE4SS reflection caveat

Some live UFunctions can't be called from UE4SS Lua reflection because they were registered
with the short `UE4_RegisterClass` variant (no `Ex`) — UFunction parameter UProperty
metadata is missing, and UE4SS misreports this as
*"Tried calling a member function but the UObject instance is nullptr"*. Notable
occurrences: `ALuxBattleChara::Active` / `Inactive` / `GetTracePosition`. Inherited
`AActor` UFunctions (e.g. `K2_GetActorLocation`) still work. See
[UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md).
