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
- Ran a broad cleanup pass across cookbook, reference, UE4SS, and SC6 pages.

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
