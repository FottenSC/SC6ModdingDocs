# Cookbook

Short, copy-pasteable recipes. Each one is self-contained: what it does, the code, and a
"verify it works" step.

!!! tip "Adding a recipe"
    Create a new `.md` file in this folder, add it to `nav:` in `mkdocs.yml`, and follow the template below.

## Investigations

- [Rollback Netcode Feasibility Investigation](rollback-netcode-investigation.md) -
  Ghidra-backed decision record for SC6's online input path, snapshot state,
  replay reuse, and a minimal rollback prototype plan.

## Native DLL recipes

- [DotVanisher spectator timeout grace](dotvanisher.md) - standalone UE4SS
  hook that gives pending host-side watch spectators a bounded grace window
  during slow match loads.

## Recipe template

```markdown
# Recipe: <Title>

**Goal**: one-sentence description of what the user ends up with.

**Requires**: native hook framework or injector, any other mods, Ghidra/dumper output, etc.

## Code

```cpp
// your snippet
```

## How it works

Short explanation of the hook/UObject used.

## Verify

1. Launch the game.
2. Expected log line / visual result.
```
