---
title: SoulCalibur VI Modding Docs
---

# SoulCalibur VI Modding Docs

Reverse-engineering notes for **SoulCalibur VI**, written primarily as a
knowledge base for AI coding agents working on mods via
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (Unreal Engine 4/5 Scripting System).

Pages are auto-generated from Ghidra analysis of the shipping Steam binary
(class layouts, function RVAs, struct offsets, UFunction trampolines) and
cross-checked against live UE4SS runtime introspection. The content is dense,
offset-accurate, and carries explicit source citations — optimised for machine
readers but still readable by humans.

!!! warning "Unofficial"
    This project is **not** affiliated with BANDAI NAMCO or the UE4SS maintainers.
    Mod at your own risk — never mod files online and keep clean backups of your game.

## For AI agents — start here

If you're an AI agent reading these docs to answer a specific question or
make an edit, this is the navigation contract:

1. **Have a symbol/address/offset?** Go to [Symbol Index](reference/symbol-index.md)
   first — it has a "how to find a fact" cheat sheet plus the highest-frequency
   lookups in one page.
2. **Have a topic?** Use [the Pages table below](#what-youll-find-here), or
   for SC6 internals specifically the [SC6 quick-find](sc6/index.md#quick-find-where-do-i-look-for-x).
3. **Need to verify a claim before acting on it?** Re-check it against Ghidra
   via the `mcp__ghidra-mcp__*` tools. The `> source:` blockquote on each
   claim points at the function whose decompile/plate is authoritative.
   Every claim is marked **verified**, **unverified**, or **stale on this
   build** — honour those markers.
4. **Adding new info?** Match the structure of nearby content (tables, not
   prose, where possible) and add a `> source:` line. See the
   [Contributing rules of thumb](contributing.md#rules-of-thumb-for-ai-agents).

### Search patterns that always work

| Looking for ... | Grep this |
|---|---|
| A function address | `0x140xxxxxx` (image base = `0x140000000`) |
| A `chara+0xN` use | `chara\+0x` or `+0xN` in the structures / topic page |
| A `BM+0xN` slot | search [Battle Manager: BM subsystem layout](sc6/battle-manager.md#battlemanager-subsystem-layout) |
| A `vmCtx+0xN` field | search [Move System: VM scratch layout](sc6/move-system.md#vm-opcode-scratch-layout-offsets-on-g_luxmovevm_commandplayerarrayslot) |
| An opcode (`0x40002`, `0x50008`, ...) | [Move System: opcode quick reference](sc6/move-system.md#opcode-quick-reference) |
| A KHit list head (`+0x44478`, `+0x44498`, `+0x444B8`) | [Hitbox System](sc6/hitbox-system.md) |
| A struct's size or layout | [Game Structures](sc6/structures.md) is canonical |
| A status word (`verified`, `unverified`, `stale on this build`) | grep `docs/sc6/*.md` |

## What you'll find here

<div class="grid cards" markdown>

-   :material-code-braces: **[UE4SS Framework](ue4ss/index.md)**

    Lua API, hooks, UObject reflection, and dumper usage.

-   :material-sword-cross: **[SoulCalibur VI Internals](sc6/index.md)**

    Game-specific structures, character data, and notable functions.

-   :material-book-open-variant: **[Cookbook](cookbook/index.md)**

    Copy-pasteable recipes: modifying move data, swapping meshes, hot-reload loops.

-   :material-library: **[Reference](reference/index.md)**

    Glossary, addresses, and cross-cutting reference material.

-   :material-handshake: **[Contributing](contributing.md)**

    How to add a new page — designed so humans *and* AI agents can contribute.

-   :material-history: **[Recent Changes](recent-changes.md)**

    Current branch change history pulled from Git commits.

</div>

## Quick links

- UE4SS upstream: <https://github.com/UE4SS-RE/RE-UE4SS>
- SoulCalibur VI on Steam: <https://store.steampowered.com/app/544750/>
