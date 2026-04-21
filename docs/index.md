---
title: SoulCalibur VI Modding Docs
---

# SoulCalibur VI Modding Docs

Reverse-engineering notes for **SoulCalibur VI**, written primarily as a
knowledge base for AI coding agents working on mods via
[UE4SS](https://github.com/UE4SS-RE/RE-UE4SS) (Unreal Engine 4/5 Scripting System).

Pages are auto-generated from Ghidra analysis of the shipping Steam binary
(class layouts, function RVAs, struct offsets, UFunction trampolines) and
cross-checked against live UE4SS runtime introspection. Content is dense
and offset-accurate with explicit source citations — optimised for machine
readers but still readable to humans.

!!! warning "Unofficial"
    This project is **not** affiliated with BANDAI NAMCO or the UE4SS maintainers.
    Mod at your own risk — never mod files online and keep clean backups of your game.

## What you'll find here

<div class="grid cards" markdown>

-   :material-rocket-launch: **[Getting Started](getting-started/index.md)**

    Install UE4SS into SoulCalibur VI and load your first Lua mod.

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

</div>

## Quick links

- UE4SS upstream: <https://github.com/UE4SS-RE/RE-UE4SS>
- SoulCalibur VI on Steam: <https://store.steampowered.com/app/544750/>
