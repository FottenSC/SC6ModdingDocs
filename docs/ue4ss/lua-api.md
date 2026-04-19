# Lua API Overview

!!! info "Stub"
    Expand with concrete SC6 examples as we find them.

## Core globals

| Symbol | Purpose |
|---|---|
| `print(msg)` | Log to UE4SS console and `UE4SS.log` |
| `FindFirstOf("ClassName")` | First live instance of a UClass |
| `FindAllOf("ClassName")` | Array of live instances |
| `StaticFindObject("/Script/...")` | Lookup by full object path |
| `RegisterHook(path, fn)` | Pre/post hook a UFunction |
| `NotifyOnNewObject(path, fn)` | Fires each time a new UObject of that class is constructed |
| `ExecuteInGameThread(fn)` | Marshal onto the game thread — required for most UObject calls |

## Reading/writing properties

```lua
local pc = FindFirstOf("PlayerController")
if pc:IsValid() and pc.Pawn:IsValid() then
    local loc = pc.Pawn:K2_GetActorLocation()
    print(("location: %.1f %.1f %.1f"):format(loc.X, loc.Y, loc.Z))
end
```

Always null-check each link in the chain with `:IsValid()` before dereferencing — `pc.Pawn` can
be `nil` during level transitions even when the PlayerController itself is alive. Don't try to
test for a UFunction's existence with `pc.Pawn.K2_GetActorLocation and …`: UE4SS resolves
UFunction accessors lazily via `__index`, so that field read never returns `nil` on a live
wrapper, and the guard always passes.
