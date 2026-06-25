# Hooks & Events

UE4SS Lua hooks observe UFunction dispatch. In SC6 that is useful for
Blueprint-visible events, engine lifecycle calls, and high-level game helpers.
It is not a general native detour system: if SC6 calls a C++ `_Impl` directly,
or if the target is not a UFunction, `RegisterHook` will not see it.

## `RegisterHook`

`RegisterHook` returns two IDs. Keep both if you plan to unregister the hook.
For `/Script/...` UFunction paths, the second callback is pre-call and the
optional third callback is post-call. For `/Game/...` Blueprint paths, UE4SS
treats the second callback as the post-call callback and ignores the third.
The target UFunction must already exist in memory when you register it; stable
`/Script/...` classes are much easier to hook at Lua startup than content
Blueprints that load later.

```lua
local Hooks = {}

local function RememberHook(path, pre, post)
    local preId, postId = RegisterHook(path, pre, post)
    Hooks[path] = { preId = preId, postId = postId }
end
```

SC6 use case: hook the engine controller restart as a safe moment to drop stale
cached battle wrappers and re-resolve the live match objects.

```lua
local function IsLive(obj)
    return obj ~= nil and obj:IsValid()
end

local function FirstLive(className)
    local objects = FindAllOf(className)
    if not objects then return nil end

    for _, obj in pairs(objects) do
        if IsLive(obj) then return obj end
    end

    return nil
end

RememberHook("/Script/Engine.PlayerController:ClientRestart",
    function(pc)
        if IsLive(pc) then
            print("[sc6] ClientRestart pre: " .. pc:GetFullName() .. "\n")
        end
    end,
    function()
        ExecuteInGameThread(function()
            local bm = FirstLive("LuxBattleManager")
            if IsLive(bm) then
                print("[sc6] rebound BattleManager: " .. bm:GetFullName() .. "\n")
            end
        end)
    end)
```

SC6 Blueprint diagnostic example, using the battle HUD path already shown in
[Battle Message System](../sc6/messages.md#path-c-blueprint-message-router).
Register this only after you have verified `BP_BattleHUDManager_C` is loaded in
the current mode; it observes the route if that BP handler is active, and it
does not send HUD messages by itself.

```lua
RememberHook("/Game/HUD/Battle/BP_BattleHUDManager.BP_BattleHUDManager_C:OnReceiveMessage",
    function(self)
        if IsLive(self) then
            print("[sc6] battle HUD received a message\n")
        end
    end)
```

UE4SS exposes UFunction arguments as hook parameters. Depending on the argument
type, you may need to unwrap with `param:get()` before inspection and write with
`param:set(value)` only after verifying the parameter layout. For simple
lifecycle hooks, it is often safer to ignore the raw params and re-find the SC6
object you need on the game thread.

## `NotifyOnNewObject`

Use `NotifyOnNewObject` when object construction is the event you care about:
BattleManager spawn, fighter spawn, or a subsystem actor appearing after a mode
transition. The class path must already exist; these SC6 class paths are
documented in [Game Structures](../sc6/structures.md):

```lua
NotifyOnNewObject("/Script/LuxorGame.LuxBattleManager", function(bm)
    ExecuteInGameThread(function()
        if IsLive(bm) then
            print("[sc6] new BattleManager: " .. bm:GetFullName() .. "\n")
        end
    end)
end)

NotifyOnNewObject("/Script/LuxorGame.LuxBattleChara", function(chara)
    ExecuteInGameThread(function()
        if IsLive(chara) then
            print("[sc6] new BattleChara: " .. chara:GetFullName() .. "\n")
        end
    end)
end)
```

Keep construction callbacks narrow. Register once per class and fan out from
inside that one callback; do not install duplicate `NotifyOnNewObject` handlers
for the same class from multiple helper functions. Avoid broad
`/Script/Engine.Actor` notifications in normal SC6 mods unless you are doing a
short diagnostic run.

Construction does not mean "fully initialized". Re-check `:IsValid()` and any
nested properties later before calling UFunctions on the object.

## Threading

Hook callbacks run inside engine activity. Keep them short:

- set a Lua flag,
- copy plain scalar data,
- schedule UObject work with `ExecuteInGameThread`,
- return.

Do not scan every `LuxBattleChara`, walk large object arrays, or call several
reflected UFunctions directly inside a hot hook. For per-frame or frequently
fired UFunctions, queue work and rate-limit your logging.

```lua
local pendingBattleRefresh = false

local function RefreshBattleStateSoon()
    if pendingBattleRefresh then return end
    pendingBattleRefresh = true

    ExecuteInGameThread(function()
        pendingBattleRefresh = false
        local bm = FirstLive("LuxBattleManager")
        if IsLive(bm) then
            print("[sc6] refreshed battle state from " .. bm:GetFullName() .. "\n")
        end
    end)
end
```

## Lifecycle and restart gotchas

If your script toggles hooks at runtime, unregister with the exact path and both
IDs returned by `RegisterHook`:

```lua
local ids = Hooks["/Script/Engine.PlayerController:ClientRestart"]
if ids then
    UnregisterHook("/Script/Engine.PlayerController:ClientRestart", ids.preId, ids.postId)
    Hooks["/Script/Engine.PlayerController:ClientRestart"] = nil
end
```

Practical SC6 rules:

- Register stable `/Script/...` hooks at script load. For later-loaded
  `/Game/...` Blueprint hooks, register once when the class is known loaded, not
  from a callback that can fire many times.
- Treat "Restart All Mods" as a fresh Lua run. Rebuild hook IDs and object
  caches; do not reuse IDs or UObject wrappers saved by a previous run.
- Re-find battle objects after `ClientRestart`, map load, rematch, replay exit,
  and mode transitions.

!!! warning "Native-hook-only restart hazard"
    C++ global hooks are different from Lua `RegisterHook`. If a native UE4SS
    mod registers `ProcessEvent`, `Tick`, or `LoadMap` callbacks, it must store
    the returned `GlobalCallbackId` and unregister on teardown. Otherwise
    "Restart All Mods" can leave callbacks pointing at freed C++ mod state.
    See [Global Hooks](global-hooks.md#the-restart-all-mods-lifecycle-gotcha).

## When Lua hooks are not enough

Use Lua `RegisterHook` when the call flows through `ProcessEvent` and the
UFunction metadata is good enough for UE4SS. Use a native UE4SS plugin, global
`ProcessEvent` observer, or direct memory path when one of these SC6 boundaries
applies:

| SC6 target | Why Lua hook is insufficient | Better path |
|---|---|---|
| Direct `_Impl` calls | Native callers can bypass the UFunction trampoline, so `RegisterHook` never fires. | Native detour or C++ UE4SS plugin. |
| Weapon-trace `Active` / `Inactive` / `GetTracePosition` | Documented reflection caveat; `GetTracePosition` is stale on the shipping build. | Native trace-system hook or raw structure read. |
| `ReceiveGetWeaponTip` | The BP event fires, but SC6 ships no overriding BP body; observed out-params stay zero. | Do not use as weapon endpoint data. Inspect KHit or trace internals instead. |
| BP events with required post out-params | Per-UFunction Lua hooks may not see reliable post state for BlueprintImplementableEvents. | C++ global `ProcessEvent` post-hook. |
| Replay freeze, rollback, frame-step gates | These need native tick gates and clock gates, not reflected UFunction hooks. | Native hooks documented in [Replay System](../sc6/replay-system.md). |
| Debug line drawing | `UKismetSystemLibrary::DrawDebugLine` is reflected but no-ops in SC6 shipping. | [ULineBatchComponent path](../sc6/line-batching.md). |

For unknown call flow, first use the diagnostic pattern in
[Global Hooks](global-hooks.md#pattern-the-processevent-spy-diagnostic) to find
which UFunctions actually fire during the SC6 action you are testing.

!!! warning "AOB drift across game patches"
    When SC6 is patched, UE4SS may need refreshed AOB signatures for its core
    scan. If all hooks stop firing after a game update, update UE4SS before
    debugging your Lua script.
