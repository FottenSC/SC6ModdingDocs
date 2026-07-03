---
title: Recent Changes
---

# Recent Changes

This page is a human-readable changelog. It groups related documentation work
by topic and date instead of mirroring every Git commit one-for-one.

For audit detail, use the current branch history:

```bash
git log --date=short --pretty=format:"%h%x09%ad%x09%s" -30
```

## 2026-07-03 - PlayFab Party Practical Latency Estimates

### Changed

- Added cautious Norway-to-America and Norway-to-Japan PlayFab Party relay
  estimates, including Azure Norway East inter-region P50 sanity checks,
  realistic median-RTT improvement ranges, and guidance to judge routes by
  p95/p99 jitter, loss, stalls, late inputs, and rollback pressure instead of
  average ping alone.
- Documented the relay-only baseline tradeoff: safer peer-IP privacy and a
  more controlled test path, but potentially worse latency than a good direct
  route.

## 2026-07-03 - PlayFab Party Route-Quality Clarification

### Changed

- Clarified the PlayFab Party relay cookbook to distinguish unavoidable
  physical propagation latency from avoidable routing overhead, ISP
  hairpinning, congestion, jitter, loss, NAT trouble, and route instability.
- Made the Party framing less dismissive by explaining how QoS measurement,
  selected Azure regions/backbone paths, transparent relay behavior, session
  policy, and optional direct-peer mode could plausibly improve bad routes while
  preserving the requirement to measure against good direct and Steam Datagram
  Relay paths.

## 2026-07-03 - PlayFab Party Netcode Relay Revision

### Changed

- Reframed the netcode relay cookbook around PlayFab/PlayFab Party as the lead
  managed transport and control-plane candidate, covering QoS measurement,
  region selection, transparent cloud relay, optional direct peer policy, and
  TURN-like fallback behavior.
- Demoted raw Azure VM/VMSS relay infrastructure to a lower-level custom
  data-plane fallback, while preserving the caveats that relays cannot beat the
  speed-of-light floor, cannot outperform good direct peering by default, and
  still require native transport ownership.
- Updated the Cookbook index and MkDocs navigation label to match the
  PlayFab-focused framing.

## 2026-07-03 - Azure-Backed Netcode Relay Investigation

### Added

- Added a documentation-only cookbook investigation for whether an Azure-backed
  UDP relay could improve America-Europe SC6 online route quality, covering
  speed-of-light limits, why relays cannot beat good direct peering, stock
  SC6/Steam transport ownership risks, Azure VM/container relay candidates,
  PlayFab/Party and signaling options, Azure Relay/Web PubSub limitations,
  TURN-like fallback behavior, telemetry, prototype phases, privacy/ToS
  boundaries, and decision criteria.

### Changed

- Linked the Azure relay investigation from the Cookbook index and MkDocs
  navigation.

## 2026-07-03 - Single-Machine Rollback Testing Cookbook

### Added

- Added a practical cookbook page for automated SC6 online/rollback netcode
  testing on one machine, covering in-process virtual peers,
  baseline-vs-faulted harnesses, loopback shims, two local game processes,
  VM/sandbox isolation, Windows network emulation, Steam/relay limitations,
  replay/log-driven tests, parser/comparator CI, fault injection,
  instrumentation, artifacts, pass/fail gates, and what local tests cannot
  prove.

### Changed

- Linked the new rollback testing cookbook from the Cookbook index and MkDocs
  navigation.

## 2026-07-01 - Ghidra Validation Pass

### Changed

- Replaced stale `FUN_*` references for character-select menu builders,
  pause-delegate metadata, camera pose writers, weapon-tip event dispatch, and
  move-bank event-tree setup with confirmed Ghidra symbol names.
- Added the reflected `FLuxBattleOptionParam` layout and clarified that its
  `InputDelayFrame` property does not drive the live `FrameInputLog+0x390`
  online-input delay path.
- Clarified that `FLuxMoveCommandPlayer` is represented as a sparse Ghidra
  struct applied at `g_LuxMoveVM_CommandPlayerArray`.

## 2026-07-01 - Rollback Testing and Diagnostics Expansion

### Added

- Expanded the rollback netcode cookbook with a local automated test topology,
  harness components, config matrix, scripted/headless run tiers, reproducible
  artifacts, pass/fail gates, and the limits of local testing versus real online
  play.
- Added player-facing jitter-first connection diagnostics guidance covering
  rolling RTT, jitter, loss, stalls, rollback pressure, cautious likely-cause
  warnings, honest UI wording, and privacy-safe telemetry.

## 2026-06-28 - DotVanisher Cookbook Recipe

### Added

- Added a standalone DotVanisher cookbook article explaining the host spectator
  timeout issue, the `HandleHostTickWatchEventQueues` detour, binary/prologue
  guard checks, pending-watch epoch tracking, 90-second grace behavior,
  packaging layout, verification logs, and troubleshooting notes.
- Linked the DotVanisher recipe from the Cookbook index and MkDocs navigation.

## 2026-06-26 - Native Hook Documentation Cleanup

### Changed

- Removed the legacy scripting/reflection API pages from the docs navigation and
  site tree.
- Reworked SC6 and cookbook cross-links so runtime guidance points at native DLL
  hooks, direct `_Impl` calls, runtime probes, and native `ProcessEvent`
  diagnostics instead of scripting API helpers.
- Updated the README, homepage, glossary, cookbook template, and MkDocs metadata
  to describe the project as native modding and reverse-engineering documentation.

## 2026-06-26 - Practical Cookbook and Runtime Hooking Pass

### Added

- Expanded SC6-specific runtime-hooking notes for live object discovery,
  reflected helper boundaries, `ProcessEvent` filtering, map/menu transition
  invalidation, and native-boundary escalation.
- Expanded the wholly-new custom-stage cookbook into a fuller implementation
  checklist covering stage-code selection, pak layout, load-path routing,
  picker integration, metadata/collision validation, troubleshooting, and online
  desync risks.
- Added practical CPU/training-dummy guidance for scripted SubVM drills,
  training-mode UFunction usage, native frame-input overrides, and runtime
  verification.
- Added practical audio-modding guidance for ACB/cue-sheet routing, weapon SE,
  voice replacement, costume-part SE relevance, stage foley, muting/ducking, and
  fast-forward/rollback side-effect gating.

Related commit: [`7868995`](https://github.com/FottenSC/SC6ModdingDocs/commit/7868995)

## 2026-06-26 - Stage Collision Replacement Notes

### Added

- Expanded the stage replacement cookbook with practical collision-layer guidance
  for visual `BodySetup` collision, breakable wall/barrier actors, the fixed
  scbattle barrier block, and paired `J_StgHitChkData` raw hit-data blobs.
- Added a community exploration workflow for testing wall collision changes,
  donor hit-data swaps, and possible extra breakable wall experiments without
  implying that actor placement alone creates deterministic wall cells.

## 2026-06-25 - Rollback Netcode Feasibility Investigation

### Added

- Added a Cookbook investigation page for rollback netcode feasibility, grounded
  in Ghidra MCP evidence from SC6's online input, replay, simulation, RNG, and
  snapshot paths.
- Added a practical minimal prototype plan for validating deterministic
  restore/resimulation locally under `E:/myMods`.
- Added a testing methodology and fault-injection plan for proving or falsifying
  rollback feasibility, including instrumentation, pass/fail criteria, and
  offline HorseMod versus native online-transport test boundaries.

### Changed

- Linked the new rollback investigation from the Cookbook navigation and index.
- Documented why `InputDelay+0x390` is not the live online delay control, where
  delay/catch-up is actually enforced, and why native hooks are required beyond
  a scripting/reflection-only control layer.

## 2026-06-25 - Home Changelog and Hitbox Documentation Pass

### Added

- Added this Recent Changes page under the Home tab and linked it from the landing page.
- Added repository instructions that make changelog maintenance part of the commit workflow.
- Added KHit overlay guidance for reading native world buffers instead of reconstructing collision geometry from render-pose helpers.

### Changed

- Converted Recent Changes from a raw commit table into this curated changelog format, grouped by documentation area and date range.
- Reworked the hitbox documentation around active attack cells, opponent cell copies, active-frame phase bytes, and damage / reaction gates.
- Clarified that `chara+0x44048` is the defender-side opponent active-cell copy and `chara+0x44058` is the chara's own current attack cell.
- Expanded hurtbox mask notes for opcode `0x13AC`, including the inverted disable-mask behavior.
- Added practical overlay predicates for attack visibility, active-frame state, Lane 2 alternate masks, and classifier-addressable hurtbox slots.
- Refined selection menu coverage and linked it into the SC6 docs navigation.
- Expanded the reference glossary with more cross-cutting SC6 terms.
- Documented replay and stage revisions that connect launcher setup, battle settings, on-disk files, and stage system internals.

Related commits: [`6fdd40c`](https://github.com/FottenSC/SC6ModdingDocs/commit/6fdd40c), [`3bb903c`](https://github.com/FottenSC/SC6ModdingDocs/commit/3bb903c), [`087b406`](https://github.com/FottenSC/SC6ModdingDocs/commit/087b406), [`6548416`](https://github.com/FottenSC/SC6ModdingDocs/commit/6548416), [`782fca2`](https://github.com/FottenSC/SC6ModdingDocs/commit/782fca2)

## 2026-06-24 - Stage, Replay, and Character Select Expansion

### Added

- Added character select roster-table notes and symbol-index entries.
- Added stage raw asset path coverage for cookbook workflows and SC6 internals references.
- Added stage collision, launcher, and replay-path documentation across the stage system, replay system, structures, and cookbook pages.

### Changed

- Expanded stage settings and actor-list notes with more concrete structure references.
- Cross-linked stage replacement and custom-stage cookbook pages with the lower-level stage system docs.
- Updated reference and SC6 index pages so the new stage and replay facts are easier to find.

Related commits: [`b4a2611`](https://github.com/FottenSC/SC6ModdingDocs/commit/b4a2611), [`daef294`](https://github.com/FottenSC/SC6ModdingDocs/commit/daef294), [`4d9af8d`](https://github.com/FottenSC/SC6ModdingDocs/commit/4d9af8d), [`8dfabfa`](https://github.com/FottenSC/SC6ModdingDocs/commit/8dfabfa)

## 2026-05-22 to 2026-05-21 - Trace and Leaderboard Follow-Up

### Added

- Added trace-slot and battle dependency graph notes.
- Added leaderboard rank internals and rank icon table documentation, including S1 / S2 handling.

### Changed

- Linked trace-system facts back into Battle Manager and leaderboard references where those systems intersect.

Related commits: [`114a7a9`](https://github.com/FottenSC/SC6ModdingDocs/commit/114a7a9), [`b667618`](https://github.com/FottenSC/SC6ModdingDocs/commit/b667618), [`c79c08c`](https://github.com/FottenSC/SC6ModdingDocs/commit/c79c08c)

## 2026-05-17 to 2026-05-10 - Navigation, Cleanup, and Replay Page

### Added

- Added the replay-system page and surfaced it in SC6 navigation.
- Added Ghidra-audited fixes across replay, battle manager, hitbox, movement, message, stage, structures, and trace docs.

### Changed

- Optimized the site layout for AI-agent navigation with stronger landing pages, quick-find links, and reference paths.
- Ran a broad cleanup pass across cookbook, reference, runtime-hooking, and SC6 pages.

Related commits: [`d8561dc`](https://github.com/FottenSC/SC6ModdingDocs/commit/d8561dc), [`9330f21`](https://github.com/FottenSC/SC6ModdingDocs/commit/9330f21), [`e3edce0`](https://github.com/FottenSC/SC6ModdingDocs/commit/e3edce0)

## 2026-04-29 to 2026-04-27 - Stage System, KHit, and Trace Split

### Added

- Added stage system and leaderboard docs.
- Added KHit hit-resolution pipeline documentation, dev/debug hooks, and clearer machine-readable framing.
- Split hit detection from weapon-trail VFX by moving KHit material into Hitbox System and keeping visual trace content in Trace System.

### Changed

- Expanded `FLuxMoveBankCell` layout notes and cross-referenced them from move and hitbox docs.
- Clarified which systems are gameplay collision, visual trace rendering, and debug-line rendering.

Related commits: [`8a347d8`](https://github.com/FottenSC/SC6ModdingDocs/commit/8a347d8), [`194a6c6`](https://github.com/FottenSC/SC6ModdingDocs/commit/194a6c6), [`ae6c3cd`](https://github.com/FottenSC/SC6ModdingDocs/commit/ae6c3cd)

## 2026-04-21 - Verification and Agent Framing

### Changed

- Reframed the README and home page around AI-agent use of the docs.
- Verified and tightened claims across Battle Manager, Move System, Structures, Trace System, and debug-line documentation.

Related commit: [`da0912f`](https://github.com/FottenSC/SC6ModdingDocs/commit/da0912f)

## 2026-04-19 - Core SC6 Internals Foundation

### Added

- Added Battle Manager and DataTable config-tree documentation.
- Added Move VM opcode, stance, hit-model, and export-path documentation.
- Added global hooks, line batching, and broader structures / glossary coverage.

### Fixed

- Corrected early BattleManager and `FLuxCapsule` field interpretations.
- Clarified that TraceManager is visual-only and not the gameplay hitbox system.

### Changed

- Switched the Cloudflare Pages build to `uv` to reduce deploy time.

Related commits: [`9beead7`](https://github.com/FottenSC/SC6ModdingDocs/commit/9beead7), [`28ee5a4`](https://github.com/FottenSC/SC6ModdingDocs/commit/28ee5a4), [`9e0fb13`](https://github.com/FottenSC/SC6ModdingDocs/commit/9e0fb13), [`66ab8d2`](https://github.com/FottenSC/SC6ModdingDocs/commit/66ab8d2), [`6cae3bf`](https://github.com/FottenSC/SC6ModdingDocs/commit/6cae3bf), [`54510e4`](https://github.com/FottenSC/SC6ModdingDocs/commit/54510e4), [`b9684e1`](https://github.com/FottenSC/SC6ModdingDocs/commit/b9684e1), [`ae1f834`](https://github.com/FottenSC/SC6ModdingDocs/commit/ae1f834)

## 2026-04-18 - Project Scaffold and Local Preview

### Added

- Added the initial MkDocs Material documentation scaffold.
- Added `.gitignore` coverage, Windows local-preview helper script, and Cloudflare Workers static-assets configuration.

Related commits: [`18f235a`](https://github.com/FottenSC/SC6ModdingDocs/commit/18f235a), [`ee25aeb`](https://github.com/FottenSC/SC6ModdingDocs/commit/ee25aeb), [`1580ba5`](https://github.com/FottenSC/SC6ModdingDocs/commit/1580ba5), [`cb9dfbc`](https://github.com/FottenSC/SC6ModdingDocs/commit/cb9dfbc)
