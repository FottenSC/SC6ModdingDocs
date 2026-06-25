# Global Hooks (ProcessEvent / Tick / LoadMap / …)

UE4SS lets a C++ mod install engine-level callbacks that fire on every invocation of a
named entry point — `UObject::ProcessEvent`, `UEngine::Tick`, `LoadMap`, and the like.
Unlike the per-UFunction script hooks you register with [`RegisterHook`](hooks.md), these
sit below the VM and see *every* call. They're invaluable for diagnostics ("which
UFunctions fire during this one game action?") and for intercepting BP-implementable
events whose per-UFunction post-callback never runs.

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

### SC6 bridge decision guide

Use the smallest bridge that can observe or change the thing you care about:

| Need | First choice | Escalate when |
|---|---|---|
| Call a documented battle helper, read an actor transform, or react to a stable reflected UFunction | UE4SS Lua reflection / `RegisterHook` | The call fails because SC6 omitted parameter metadata, or the game calls the native `_Impl` directly. |
| Discover which reflected events fire for one menu or battle action | Short-lived global `ProcessEvent` spy | The event never appears in the spy log, which means the path is probably native or not UFunction-dispatched. |
| Read post-dispatch out-params from a BlueprintImplementableEvent | Global `ProcessEvent` post-hook | The BP body is not implemented in SC6, so the hook fires but out fields remain unchanged. |
| Freeze, step, or replay-control battle simulation | Native tick/clock gates | Lua or global `UEngine::Tick` polling sees frames too late and misses native catch-up paths. |
| Override AI frame input or suppress audio side effects during hidden frames | Native hook at the documented subsystem boundary | A reflected function only configures high-level state and does not own the per-frame write. |

SC6 examples: BattleManager setup helpers and launcher flow are often good
reflection targets; see [Battle Manager](../sc6/battle-manager.md#key-ufunctions-call-via-reflection)
and the [battle launcher startup path](../sc6/battle-manager.md#battle-launcher-startup-path).
AI input ownership, replay freeze, and audio cue suppression are native-boundary
problems; see [CPU / AI System](../sc6/ai-cpu-system.md#where-to-hook-for-ai-mods),
[Replay System](../sc6/replay-system.md#replay-freeze-gates), and
[Audio System](../sc6/audio-system.md#fast-forward-rollback-side-effect-gating).

!!! note "Per-UFunction post-hooks silently fail for BlueprintImplementableEvents"
    When the game calls a `Receive*`-style event, UE4SS's BP-event path fires the *pre*
    callback but skips the *post*. A global `ProcessEvent` post-hook intercepts at the
    engine level and **does** fire for BP events — it reads the `parms` block after
    dispatch and sees whatever the BP body wrote. See the ReceiveGetWeaponTip case in
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
    that returns `void`. It's deprecated for a reason: **it returns no ID, so you can't
    unregister it**. On "Restart All Mods" the callback stays wired to the engine and
    fires into freed memory. Always use the two-argument form with `FCallbackOptions`.

## The "Restart All Mods" lifecycle gotcha

UE4SS destroys and re-constructs C++ mods when the user invokes "Restart All Mods". If
your mod registered global hooks with the deprecated API — or used the non-deprecated API
but forgot to unregister them — the old lambdas keep running, with `this` still captured
into the now-freed mod instance. The next `ProcessEvent` then faults with an access
violation.

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
3. **Never capture `this` in the callback lambda.** Capturing it is lexically simple, but
   it makes the lifetime *your* responsibility — and you can't guarantee that lifetime
   against a reload. Use a static `std::atomic<Self*>` instead.
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

When you don't know *which* UFunction a game action routes through, arm a global PE
pre-hook that logs each **unique** `(UClass, UFunction)` pair exactly once. Perform the
action, then grep the log.

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
3. Disarm, then arm again **without clearing** — the dedup set persists.
4. Perform the game action you're investigating.
5. Any fresh `[spy]` lines between the second arm and disarm are UFunctions **unique to
   that action** — breadcrumbs pointing at the right native code.

### SC6 filtering discipline

`ProcessEvent` sees menu widgets, controller events, battle actors, components,
and Blueprint library calls. Treat every callback as hostile until it passes a
cheap filter:

1. Check that `fn` and `ctx` are non-null before touching names or classes.
2. Prefer pointer identity after first discovery. String/name checks are fine
   while arming the spy; once the target UFunction is known, cache its pointer
   and bail on `fn != cached`.
3. If you need a class filter, cache the `UClass*` or a precomputed class-name
   decision. Do not walk ancestry or build strings on every call.
4. Avoid UObject discovery inside the callback. Set a flag or append a small
   scalar record, then resolve `LuxBattleManager`, charas, or helper CDOs from a
   slower game-thread task.
5. Rate-limit logs. A one-line log inside a broad PE hook can dominate the
   frame before the actual diagnostic cost shows up.

For SC6 battle work, record enough context to separate modes: full object name,
UFunction name, whether a live `LuxBattleManager` exists, and the current
high-level mode if your mod already tracks it. Runtime-validation boundary:
this page documents the filter shape, not a guaranteed list of UFunctions for
every menu, character, or DLC state. Confirm the actual call path on the build
you are testing.

## Pattern: post-hook for BP events with out-params

BlueprintImplementableEvents arrive at your global post-hook with `parms` pointing at the
param block as it stands after BP execution. Cast it to the known layout (get the size
from the UFunction's `Z_Construct_UFunction_…` in Ghidra), filter by function name and
cache the UFunction pointer on the first match, then accumulate samples.

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

## UObject lifetime across map and menu transitions

SC6 rebuilds battle actors aggressively. Returning to character select, loading
a stage, rematching, exiting replay viewing, or receiving `ClientRestart` can
leave an old UObject wrapper looking non-null while the object graph under it is
no longer the active match graph.

Global hooks make that easier to miss because they keep firing across the whole
process lifetime. Apply these rules to native hook state:

- Do not keep `ALuxBattleManager*`, `ALuxBattleChara*`, training actors, replay
  actors, or `UAtomComponent*` pointers as long-lived truth. Keep class paths,
  object names for logging, stable IDs, and your own plain state; re-resolve
  live UObjects after transitions.
- Treat `LoadMap`, `BeginPlay`, `EndPlay`, `ClientRestart`, rematch, and replay
  exit as cache-invalidation boundaries. If your bridge cannot positively prove
  the cached pointer still belongs to the active world, drop it.
- A valid outer object does not make child pointers valid. Re-check every
  UObject hop before calling into BattleManager subsystems, chara state, audio
  components, or replay actors.
- Construction callbacks are early. A newly observed BattleManager or chara may
  not have all subsystem slots populated until later in the mode flow.

The Lua-facing version of these rules lives in
[Lua API Overview](lua-api.md#minimal-safety-helpers) and
[Hooks & Events](hooks.md#lifecycle-and-restart-gotchas). Native hooks should
follow the same model: observe transition, clear caches, then reacquire only
when the target object passes the current-mode checks your mod needs.

## Performance considerations

- When the spy's `m_active` flag is **false**, the callback is just an atomic load and a
  return — negligible cost in a modern engine. Leave it installed and arm/disarm from UI.
- When active, each callback takes a short mutex for the dedup set. UE4's `ProcessEvent`
  traffic runs to tens of thousands of calls per second, so you'll see a measurable
  framerate dip while armed. That's acceptable for a diagnostic tool.
- Filtered post-hooks — those that do real work on one *specific* function — bail after a
  single pointer comparison for the 99.99% of calls that don't match, so they're
  effectively free.
- `UEngine::Tick` callbacks are per-frame, not per-simulation-frame. In SC6,
  replay catch-up, training playback, AI input, MoveVM, VFX, and audio side
  effects can advance through native subsystem paths that a global engine tick
  only observes from the outside. Use tick callbacks for UI polling, deferred
  cleanup, and coarse diagnostics; use the documented native gates for replay
  freeze and frame-step work.
- Never scan `GUObjectArray`, `FindAllOf`-equivalent object sets, or every
  `LuxBattleChara` from a hot tick. Cache the need to refresh, run the lookup at
  a bounded cadence, and stop once the current transition settles.

!!! warning "Tick hooks are not SC6 simulation ownership"
    A global engine tick hook is convenient, but it is not the owner of SC6's
    battle frame. Replay tools need the gate stack in
    [Replay System](../sc6/replay-system.md#replay-freeze-gates); pause tools
    should start with [Battle Manager](../sc6/battle-manager.md#pausing-the-simulation-gates-not-dt-multiply).
    Audio and AI side effects have their own native boundaries.

## See also

- [Hooks & Events](hooks.md) — per-UFunction `RegisterHook` (the other kind).
- [Reflection Gotchas](reflection-gotchas.md) — when a UFunction is reachable from native
  C++ but not from Lua reflection.
- [Drawing 3D Debug Lines](../sc6/line-batching.md) — a concrete "other" path that
  doesn't rely on any hook at all once you have the pointer.
- [Battle Manager](../sc6/battle-manager.md), [Replay System](../sc6/replay-system.md),
  [CPU / AI System](../sc6/ai-cpu-system.md), and
  [Audio System](../sc6/audio-system.md) — SC6 subsystem boundaries where a
  native hook may be the correct bridge.
