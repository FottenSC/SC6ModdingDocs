# Global Hooks (ProcessEvent / Tick / LoadMap / …)

UE4SS lets a C++ mod install engine-level callbacks that fire for every invocation of a
named entry point — `UObject::ProcessEvent`, `UEngine::Tick`, `LoadMap`, etc. Unlike the
per-UFunction script hooks you register with [`RegisterHook`](hooks.md), these sit below
the VM and see *every* call. They're invaluable for diagnostics ("which UFunctions fire
during this one game action?") and for intercepting BP-implementable events whose
per-UFunction post-callback doesn't run.

This page covers the pattern, the API, and the lifecycle gotcha that makes "Restart All
Mods" crash in practice.

## When to use a global hook vs a per-UFunction hook

| Want to… | Use |
|---|---|
| Run code when a specific named UFunction is called | `UObjectGlobals::RegisterHook(path, pre, post, data)` — [hooks.md](hooks.md) |
| Run code when *any* UFunction is called, filtered by predicate | `Hook::RegisterProcessEventPreCallback` |
| Observe the **post** state of a BP-implementable event | `Hook::RegisterProcessEventPostCallback` (per-UFunction post-callbacks don't fire for BP events) |
| Hook `UEngine::Tick` for idle / per-frame work | `Hook::RegisterEngineTickPreCallback` |
| Hook `BeginPlay` / `EndPlay` / `LoadMap` globally | same family of `Register*Callback` helpers |

!!! note "Per-UFunction post-hooks silently fail for BlueprintImplementableEvents"
    When the game calls a `Receive*`-style event, UE4SS's BP-event path fires the *pre*
    callback but skips the *post*. A global `ProcessEvent` post-hook intercepts at the
    engine level and **does** fire for BP events — reads the `parms` block after
    dispatch, sees whatever the BP body wrote. See the ReceiveGetWeaponTip case in
    [Trace System](../sc6/trace-system.md#receivegetweapontip-promising-looking-dead-end)
    for a concrete SC6 example — even though the hook works, the BP side is never
    implemented, so captured data is always zero.

## API surface (v3.0+, non-deprecated)

```cpp
#include <Unreal/Hooks/Hooks.hpp>
#include <Unreal/Hooks/GlobalCallbackId.hpp>
#include <Unreal/Hooks/CallbackIterationData.hpp>
namespace Hook = RC::Unreal::Hook;
```

Register the callback and stash its `GlobalCallbackId` so you can unregister later:

```cpp
Hook::FCallbackOptions opts;
opts.OwnerModName = STR("MyMod");
opts.HookName     = STR("PESpy.Pre");
opts.bReadonly    = true;
Hook::GlobalCallbackId id = Hook::RegisterProcessEventPreCallback(
    [](Hook::TCallbackIterationData<void>& /*iter*/,
       RC::Unreal::UObject* ctx, RC::Unreal::UFunction* fn, void* parms) {
        // … fires for every ProcessEvent, before dispatch.
    },
    opts);
```

On mod teardown:

```cpp
Hook::UnregisterCallback(id);
```

The `post` variant has the same signature. For read-only observers set `bReadonly = true`
so UE4SS can parallel-invoke other callbacks without extra sync.

!!! warning "Don't use the deprecated overloads"
    There's a one-argument overload (`RegisterProcessEventPreCallback(ProcessEventCallback)`)
    that returns `void`. It's tagged deprecated for a reason: **there's no returned ID, so
    you can't unregister it**. On "Restart All Mods" your callback stays wired to the
    engine and fires into freed memory. Always use the two-argument form with
    `FCallbackOptions`.

## The "Restart All Mods" lifecycle gotcha

UE4SS destroys and re-constructs C++ mods when the user invokes "Restart All Mods". If
your mod registered global hooks with the deprecated API — or forgot to unregister them
on the non-deprecated API — the old lambdas keep running, capturing `this` into the
now-freed mod instance. Next `ProcessEvent` → access violation.

### Symptoms

- `Restart All Mods` crashes the game immediately, or on the first UFunction call after.
- `UE4SS.log` ends at your mod's destructor entry (or never prints any destructor line)
  and no crash dump is produced.
- Replacing your mod's DLL while the game is running "used to work" but now crashes.

### The fix, step by step

1. **Switch to the non-deprecated API.** Store the `GlobalCallbackId` returned by
   `Register*Callback` in a member.
2. **Add an `uninstall()` method.** Idempotent; called from the mod's destructor *before*
   any members it uses are destroyed.
3. **Never capture `this` in the callback lambda.** Capture is lexically simple but it
   puts the lifetime guarantee on *you*, and you can't guarantee it against reload. Use
   a static `std::atomic<Self*>` instead.
4. **Order operations carefully in `uninstall()`.** Clear the static pointer first so any
   in-flight callback sees null and no-ops; then call `UnregisterCallback`.

### Safe template — class skeleton

```cpp
class MyGlobalPeObserver {
    static inline std::atomic<MyGlobalPeObserver*> s_instance{nullptr};
    Hook::GlobalCallbackId m_id = Hook::ERROR_ID;
    bool m_installed = false;
public:
    ~MyGlobalPeObserver() { uninstall(); }
    void install();
    void uninstall();
private:
    void on_pe(UObject*, UFunction*, void*);
};
```

### Safe template — install

```cpp
void MyGlobalPeObserver::install() {
    if (m_installed) return;
    m_installed = true;
    s_instance.store(this, std::memory_order_release);
    Hook::FCallbackOptions opts;
    opts.OwnerModName = STR("MyMod");
    opts.HookName     = STR("PEObserver.Pre");
    opts.bReadonly    = true;
    m_id = Hook::RegisterProcessEventPreCallback(
        [](Hook::TCallbackIterationData<void>&,
           UObject* ctx, UFunction* fn, void* parms) {
            if (auto* self = s_instance.load(std::memory_order_acquire))
                self->on_pe(ctx, fn, parms);
        },
        opts);
}
```

### Safe template — uninstall

```cpp
void MyGlobalPeObserver::uninstall() {
    if (!m_installed) return;
    s_instance.store(nullptr, std::memory_order_release);  // must be first
    if (m_id != Hook::ERROR_ID) {
        Hook::UnregisterCallback(m_id);
        m_id = Hook::ERROR_ID;
    }
    m_installed = false;
}
```

## Pattern: the "ProcessEvent spy" (diagnostic)

When you don't know *which* UFunction a game action is routing through, arm a global PE
pre-hook that logs each **unique** `(UClass, UFunction)` pair it sees exactly once. Do
the action, grep the log.

Cheap dedup key — XOR the class pointer and function pointer, both stable for their
lifetimes:

```cpp
uint64_t key = (reinterpret_cast<uintptr_t>(ctx ? ctx->GetClassPrivate() : nullptr) << 1)
             ^ reinterpret_cast<uintptr_t>(fn);
```

Insert into a mutex-guarded `std::unordered_set<uint64_t>`; log on first-seen.

Workflow:

1. Arm the spy (hotkey, ImGui checkbox — anything).
2. Stand idle 1–2 seconds while the log fills with "baseline" calls.
3. Disarm, then arm again **without clearing** (the dedup set persists).
4. Perform the game action you're investigating.
5. Any fresh `[spy]` lines between the second arm and disarm are UFunctions **unique to
   that action** — breadcrumbs pointing at the right native code.

## Pattern: post-hook for BP events with out-params

BlueprintImplementableEvents show up in your global post-hook with `parms` pointing at
the post-BP-execution param block. Cast to the known layout (check size from the
UFunction's `Z_Construct_UFunction_…` in Ghidra), filter by function name on first match
to cache the UFunction pointer, and accumulate samples.

```cpp
struct ReceiveFooParams {
    uint8_t _in_args[8];   // input, opaque
    FVector outA;          // +0x08
    FVector outB;          // +0x14
    bool    bReturnValue;  // +0x20
};
```

```cpp
void on_pe_post(Hook::TCallbackIterationData<void>&,
                UObject* ctx, UFunction* fn, void* parms) {
    if (fn != m_cached_fn) {
        if (fn->GetName() == STR("ReceiveFoo")) m_cached_fn = fn;
        else return;
    }
    auto* p = static_cast<const ReceiveFooParams*>(parms);
    // read p->outA, p->outB after BP has written them
}
```

!!! info "If the BP body was never overridden"
    You'll see `parms` arrive with all-zero out fields. That's not a bug in your hook; it
    means no BP subclass implements the event. UE4's default-empty implementation writes
    nothing. A real-world SC6 example: `ReceiveGetWeaponTip` on
    `ALuxBattleWeaponEventHandler` fires every frame during attacks but SC6 characters
    don't override it — you get zeros. See the WeaponEventHandler entry under
    [Game Structures](../sc6/structures.md#aluxbattleweaponeventhandler).

## Performance considerations

- When the spy's `m_active` flag is **false**, the callback is a single atomic load +
  return. Negligible cost in a modern engine. Leave it installed; arm/disarm from UI.
- When active, each callback takes a short mutex for the dedup set. UE4's `ProcessEvent`
  traffic is in the tens of thousands of calls per second; you'll see a measurable
  framerate dip while armed. That's fine for a diagnostic tool.
- Filtered post-hooks (that do real work on a *specific* function only) bail with one
  pointer comparison for the 99.99% of calls that don't match — effectively free.

## See also

- [Hooks & Events](hooks.md) — per-UFunction `RegisterHook` (the other kind).
- [Reflection Gotchas](reflection-gotchas.md) — when a UFunction is reachable from native
  C++ but not from Lua reflection.
- [Drawing 3D Debug Lines](../sc6/line-batching.md) — a concrete "other" path that
  doesn't rely on any hook at all once you have the pointer.
