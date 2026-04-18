# Cookbook

Short, copy-pasteable recipes. Each recipe should be self-contained: what it does, the code, and a
"verify it works" step.

!!! tip "Adding a recipe"
    Create a new `.md` file in this folder, add it to `nav:` in `mkdocs.yml`, and follow the template below.

## Recipe template

```markdown
# Recipe: <Title>

**Goal**: one-sentence description of what the user ends up with.

**Requires**: UE4SS version, any other mods, dumper output, etc.

## Code

```lua
-- your snippet
```

## How it works

Short explanation of the hook/UObject used.

## Verify

1. Launch the game.
2. Expected log line / visual result.
```
