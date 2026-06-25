# Lua API Overview

This page covers the UE4SS Lua surface that is useful for SC6 runtime mods:
finding live battle objects, checking wrapper validity, calling reflected
UFunctions, and keeping UObject work on the game thread. It is not a complete
UE4SS reference; use the upstream docs for API signatures and this page for
SC6-specific usage boundaries.

## Core globals

| Symbol | SC6 use |
|---|---|
| `print(msg)` | Log to the UE4SS console and `UE4SS.log`. |
| `FindFirstOf("LuxBattleManager")` | Find one live non-default instance by short class name. UE4SS strips the native `A` / `U` prefix, so use `"LuxBattleChara"`, not `"ALuxBattleChara"`. |
| `FindAllOf("LuxBattleChara")` | Iterate live fighters when instance names change between matches. Returns `nil` when none exist. |
| `StaticFindObject("/Script/...")` | Find already-loaded classes, CDOs, and other named non-instance objects. Use this for documented CDO paths, not for transient fighters. |
| `RegisterHook(path, pre, post)` | Hook a UFunction dispatch. See [Hooks & Events](hooks.md). |
| `UnregisterHook(path, preId, postId)` | Remove a hook you registered dynamically. Store both IDs returned by `RegisterHook`. |
| `NotifyOnNewObject(path, fn)` | Observe construction of SC6 classes such as `/Script/LuxorGame.LuxBattleManager`. See [Hooks & Events](hooks.md#notifyonnewobject). |
| `ExecuteInGameThread(fn)` | Queue UObject reads/writes and UFunction calls onto the game thread. |

## Minimal safety helpers

Use one guard for both `nil` and dead UObject wrappers. This keeps chained reads
from turning a level transition into a Lua error.

```lua
local function IsLive(obj)
    return obj ~= nil and obj:IsValid()
end

local function FirstLive(className)
    local objects = FindAllOf(className)
    if not objects then return nil end

    for _, obj in pairs(objects) do
        if IsLive(obj) then
            return obj
        end
    end

    return nil
end
```

SC6 battle actors are rebuilt as matches and menus load. Cache class names,
paths, or your own small state, but re-resolve `LuxBattleManager` and
`LuxBattleChara` before touching them.

```lua
ExecuteInGameThread(function()
    local bm = FirstLive("LuxBattleManager")
    if not IsLive(bm) then
        print("[sc6] no live BattleManager\n")
        return
    end

    print("[sc6] BattleManager: " .. bm:GetFullName() .. "\n")
end)
```

## `IsValid` chains

Check every UObject hop before dereferencing the next one. During loading,
rematch, replay exit, or controller restart, an outer object can stay alive
while a child pointer is temporarily empty.

```lua
ExecuteInGameThread(function()
    local pc = FindFirstOf("PlayerController")
    if not IsLive(pc) then return end

    local pawn = pc.Pawn
    if not IsLive(pawn) then return end

    local loc = pawn:K2_GetActorLocation()
    print(("[sc6] pawn at %.1f %.1f %.1f\n"):format(loc.X, loc.Y, loc.Z))
end)
```

For active fighters, prefer a fresh `FindAllOf("LuxBattleChara")` pass over a
stale wrapper saved from an earlier round:

```lua
ExecuteInGameThread(function()
    local charas = FindAllOf("LuxBattleChara")
    if not charas then return end

    for _, chara in pairs(charas) do
        if IsLive(chara) then
            local loc = chara:K2_GetActorLocation()
            print(("[sc6] %s at %.1f %.1f %.1f\n")
                :format(chara:GetFullName(), loc.X, loc.Y, loc.Z))
        end
    end
end)
```

Do not test for a UFunction's existence with
`if chara.K2_GetActorLocation then ... end`. UE4SS resolves reflected members
through `__index`, so that field read can produce a callable wrapper even when
the eventual call is not safe. Guard the receiver and call the function you
intend to use.

## Reflected UFunction calls

Call reflected UFunctions with `:` so UE4SS supplies the UObject receiver. Keep
the call on the game thread, and pass explicit world-context objects for SC6
static helper functions.

The documented SC6 battle helper CDO is
`/Script/LuxorGame.Default__LuxBattleFunctionLibrary`. Its `IsBattlePlaying`,
`GetBattleManager`, `SetBattlePause`, and related helpers take a
`WorldContextObject`; do not rely on the receiver being used as that context.

```lua
local BattleLibPath = "/Script/LuxorGame.Default__LuxBattleFunctionLibrary"

ExecuteInGameThread(function()
    local bm = FirstLive("LuxBattleManager")
    local battleLib = StaticFindObject(BattleLibPath)

    if not IsLive(bm) or not IsLive(battleLib) then
        print("[sc6] battle helpers unavailable\n")
        return
    end

    local playing = battleLib:IsBattlePlaying(bm)
    print("[sc6] IsBattlePlaying = " .. tostring(playing) .. "\n")
end)
```

For an inspection pause, the Lua call shape is the same reflected-call pattern:

```lua
ExecuteInGameThread(function()
    local bm = FirstLive("LuxBattleManager")
    local battleLib = StaticFindObject(BattleLibPath)
    if not IsLive(bm) or not IsLive(battleLib) then return end

    local pauseType = 0 -- SC6 pause-type byte; verify before using a different mode.
    battleLib:SetBattlePause(true, pauseType, bm)
end)
```

### Reflection boundaries

Not every reflected SC6 function is callable from Lua:

- The weapon-trace `Active`, `Inactive`, and `GetTracePosition` path is
  documented as a Lua-reflection caveat in [Reflection Gotchas](reflection-gotchas.md)
  and [Trace System](../sc6/trace-system.md#calling-the-trace-ufunctions-from-lua).
  Do not use it as the model for normal Lua UFunction calls.
- `GetTracePosition` is also marked stale on the shipping build, so a successful
  call would not make it a reliable hitbox or weapon-tip source.
- `UKismetSystemLibrary::DrawDebugLine` is reflected but has no live exec body
  in SC6 shipping. Use [Drawing 3D Debug Lines](../sc6/line-batching.md) instead.

When a UFunction fails with
`Tried calling a member function but the UObject instance is nullptr`, first
check [Reflection Gotchas](reflection-gotchas.md). In SC6 that message can mean
missing parameter metadata, not a dead receiver.

## Game-thread marshalling

Treat `ExecuteInGameThread` as the boundary around UObject work. This is useful
even when the current callback usually runs during engine dispatch, because it
keeps heavy lookup and reflected calls in one predictable place.

```lua
local function LogBattleStateSoon(reason)
    ExecuteInGameThread(function()
        local bm = FirstLive("LuxBattleManager")
        if not IsLive(bm) then
            print("[sc6] " .. reason .. ": no BattleManager\n")
            return
        end

        local battleLib = StaticFindObject(BattleLibPath)
        if IsLive(battleLib) then
            print(("[sc6] %s: playing=%s\n")
                :format(reason, tostring(battleLib:IsBattlePlaying(bm))))
        end
    end)
end
```

Do as little as possible outside that closure: set booleans, enqueue work, or
copy plain Lua data. Do not keep raw UObject wrappers from async callbacks and
assume they will still be valid later.

## Practical SC6 rules

- Re-find `LuxBattleManager` and `LuxBattleChara` after match load, restart, or
  replay/menu transitions.
- Prefer inherited engine UFunctions such as `K2_GetActorLocation` for basic
  actor inspection; they have normal metadata even when first-party SC6 classes
  have reflection gaps.
- Pass explicit world context to `ULuxBattleFunctionLibrary` helpers.
- Use `RegisterHook` for UFunctions that actually dispatch through
  `ProcessEvent`. For direct native `_Impl` calls, use a C++ UE4SS plugin,
  global hook, or raw-memory path instead.
