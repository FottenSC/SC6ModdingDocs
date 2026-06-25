# Reflection Gotchas

Things that look like UE4SS bugs but are actually the game binary doing something unusual. If your
symptoms on SC6 match one of the cases below, the cause is here — stop trying to fix your Lua.

## Triage before changing Lua

Separate reflection failures into common buckets before rewriting the call site:

| Symptom | Likely bucket | First check |
|---|---|---|
| Wrapper is `nil` or `:IsValid()` is false after a load, rematch, replay exit, or menu transition | Dead or stale UObject wrapper | Re-resolve on the game thread; do not reuse cached BattleManager/chara wrappers across transitions. |
| Receiver methods like `GetFullName` work, but a parameterized SC6 UFunction fails with `UObject instance is nullptr` | Missing UProperty metadata | Check whether the class used the short registration path and whether an inherited engine UFunction can provide the data instead. |
| A `RegisterHook` never fires, but Ghidra shows a real native body | Native `_Impl` or non-UFunction path | Use a global `ProcessEvent` spy to prove whether the UFunction dispatches; if it does not, use a native hook or direct bridge. |
| The call returns a default value without error | Wrong receiver/context or mode | Check static `WorldContextObject` parameters and confirm the current SC6 mode actually owns the object you found. |

Runtime-validation boundary: the docs can identify recurring SC6 failure
patterns, but the active object set and call path still need to be checked on
the build, stage, character, menu state, and replay/training mode you are
testing.

## "Tried calling a member function but the UObject instance is nullptr"

The single most misleading UE4SS error you'll see when modding SC6. The message implies the
receiver is dead, but in practice UE4SS **emits it for any null pointer encountered inside the
UFunction dispatch path** — including a null entry found while walking the UFunction's UProperty
children list to marshal parameters.

### How to recognise it

- `chara:SomeParamlessUFunction()` works.
- `chara:TheExactSameUFunction(someArg)` fails with the above.
- `chara:GetFullName()` and `chara:GetClass()` both work on the same wrapper.

If all three hold, the UObject is alive. The error is about **missing UProperty metadata on the
UFunction's parameters**, not about the receiver.

### Why it happens

Epic's UE4 class registration macros emit a Z-constructor that calls `UE4_RegisterClassEx` — the
extended form that wires up the class's properties callback. A game that hand-rolls its class
registration can instead use the shorter `UE4_RegisterClass(ClassInfo, Name, Size, CRC)` variant,
which skips the property callback entirely. The class still works for the game's own VM (exec
trampolines are wired through a separate path), but it has **no UProperty metadata for UE4SS to
iterate**.

SC6's `ALuxBattleChara` is registered this way. Its three UFunctions (`Active`, `Inactive`,
`GetTracePosition`) all take parameters, and all three fail from UE4SS Lua for this reason.
Inherited AActor UFunctions like `K2_GetActorLocation` keep working because Epic registers
`AActor` normally.

### Diagnosing it

Pick a parameterless UFunction from the problem class and call it. If it works, the cause is
almost certainly missing metadata rather than a dead object. In Ghidra, open the class's
`__StaticClass` symbol and check which registrar it calls:

```c
// Good — full metadata, all UFunctions callable from Lua
UE4_RegisterClassEx(ClassInfo, L"ClassName", Ctor, Size, Flags, ...,
                    &propertySetupCallback,        // <-- this is the key
                    ...);

// Bad — UFunctions with params cannot be marshalled from Lua
UE4_RegisterClass(ClassInfo, L"ClassName", Size, CRC);
```

If the class uses the short form, its own UFunctions with parameters are off-limits to UE4SS Lua.
Inherited UFunctions from parents registered with the extended form are still fine.

### Workarounds (in order of reliability)

1. **Inherit the call.** If the data you want is exposed via a parent-class UFunction (e.g.
   `K2_GetActorLocation`, `GetComponentsByClass`), use that path.
2. **C++ UE4SS plugin.** Call the `_Impl` directly by RVA. Bypasses reflection entirely:
   ```cpp
   using Fn = bool(__fastcall*)(void*, char, uint32_t, FVector*, FVector*);
   auto fn = reinterpret_cast<Fn>(imageBase + 0xD0BB0);
   FVector hilt{}, tip{};
   fn(chara, slot, pose, &hilt, &tip);
   ```
   About 30 lines of code; exposes results back to Lua via `RegisterCustomEvent`.
3. **Raw memory walk.** Read struct fields directly via offsets mapped in Ghidra. Tedious,
   but no reflection required — useful when the data is simple (flat POD).
4. **UE4SS dev build (3.1.0+).** Not yet tagged. May ship improvements for `LessEqual421`
   alignment on older UE4 runtimes, including SC6's UE 4.17.2. Worth trying, not guaranteed to fix.

### What doesn't work

- **Retrying with different UFunction argument shapes.** Plain tables, `nil`, FVectors returned
  from a working UFunction, dotted-vs-colon calls — all five variants produce the same error on
  SC6. The metadata gap is in the UFunction's UProperty list, not the call site.
- **`RegisterHook` on the UFunction.** Fires when the VM dispatches via `ProcessEvent`. If the
  game's own code calls the `_Impl` directly (as SC6 does for `GetTracePosition`), the hook
  never fires.

## Safe object discovery across SC6 transitions

SC6's menus, stage loads, rematches, training reset flows, and replay exits can
replace battle actors without restarting UE4SS. A cached wrapper can be non-nil
and still point at an object that is no longer the active match object.

Use object discovery as a refresh step, not as a one-time bootstrap:

- Prefer the `FindAllOf` plus `:IsValid()` helper pattern from
  [Lua API Overview](lua-api.md#minimal-safety-helpers) when reacquiring
  `LuxBattleManager`, `LuxBattleChara`, training actors, or replay actors.
- Use `StaticFindObject` for stable classes, CDOs, and documented helper objects,
  not for transient fighters or per-match BattleManager instances.
- Treat `NotifyOnNewObject` as a construction signal. It is useful for clearing
  stale caches or scheduling a later refresh, but the object may not be fully
  initialized inside the construction callback.
- Re-check every UObject hop. A live PlayerController does not guarantee a live
  pawn; a live BattleManager wrapper does not guarantee every subsystem slot is
  populated during transition.
- Log `GetFullName()` during diagnostics, but do not use name strings alone as
  proof that an object belongs to the current battle. Confirm the mode through a
  known helper or through the subsystem state your mod already validates.

For slot identity, BattleManager-owned arrays are still the authoritative shape
to investigate; see the [BattleManager subsystem layout](../sc6/battle-manager.md#battlemanager-subsystem-layout).
For call safety, a fresh global object search can avoid a UE4SS wrapper path
that is stricter than the one used for array elements, as described below.

## `FindFirstOf` vs `BattleCharaArray[i]`

In most cases both return a usable wrapper for a chara. But **TArray-element wrappers**
(e.g. `bm.BattleCharaArray[i]`) and **`FindAllOf` / `FindFirstOf` results** reach the wrapped
UObject through different UE4SS code paths, and those paths validate the object against
`GUObjectArray` with different strictness before letting you call anything on it. On class
hierarchies with marginal reflection metadata (see above), the TArray-element path can trip checks
that the global-iteration path quietly skips, producing the same `nullptr` error even though the
object is alive.

If your UFunction call fails on `bm.BattleCharaArray[i]`, try `FindAllOf("LuxBattleChara")[i]`
first before assuming it's a different problem. (UE4SS strips the `A` / `U` prefix from native
class names when matching, so the right string is `"LuxBattleChara"`, not `"ALuxBattleChara"`.)

Runtime-validation boundary: `FindAllOf` ordering is not a player-slot contract.
Use it to recover a callable wrapper or inspect live objects; use BattleManager
state when player side, replay owner, or training dummy identity matters.

## When UE4SS Lua is enough vs a native bridge

UE4SS Lua is usually enough when the target is a reflected UFunction with
complete parameter metadata, the call runs through `ProcessEvent`, and the mod
only needs high-level state changes or inspection.

Escalate to a native UE4SS plugin, global hook, or direct memory/native hook
when the boundary is below reflection:

| SC6 task | Lua/reflection status | Better bridge |
|---|---|---|
| Battle helper calls such as battle-state queries or pause helpers | Good fit when called on the game thread with an explicit world context | Lua reflection; see [Battle Manager](../sc6/battle-manager.md#key-ufunctions-call-via-reflection). |
| Weapon trace `Active` / `Inactive` / `GetTracePosition` | Parameter metadata gap on `ALuxBattleChara`; `GetTracePosition` is also stale on the shipping build | Native trace-system path or raw structure read. |
| Discovering whether one menu action emits a UFunction | Lua hook may work after the path is known, but discovery needs broader visibility | Short-lived global `ProcessEvent` spy; see [Global Hooks](global-hooks.md#pattern-the-processevent-spy-diagnostic). |
| Replay freeze, frame step, or catch-up suppression | Not a reflected-call problem | Native gate stack; see [Replay System](../sc6/replay-system.md#replay-freeze-gates). |
| AI frame input override | Reflected training helpers can configure state, but final per-frame input ownership is native | Native hook boundary; see [CPU / AI System](../sc6/ai-cpu-system.md#where-to-hook-for-ai-mods). |
| Audio cue suppression during hidden frames | Reflection can inspect some UE-side objects, but cue submission is a native side effect | Native audio gate; see [Audio System](../sc6/audio-system.md#fast-forward-rollback-side-effect-gating). |

## Static UFunctions with `WorldContextObject`

A surprising number of `ALuxBattleManager` UFunctions (e.g. `IsBattlePlaying`,
`GetBattleManager`) are registered as **static with a `WorldContextObject` parameter**.
Calling `bm:IsBattlePlaying()` on an instance receiver does *not* automatically bind that
instance as the world context — UE4SS passes `nullptr` for the parameter, the Impl short-circuits
to `false`, and the gate silently closes.

Always pass an explicit world-context when the exec trampoline reads one:

```lua
-- Broken — nullptr WorldContext, always returns false
local playing = bm:IsBattlePlaying()

-- Correct — pass the manager itself (or any UObject with a world)
local playing = bm:IsBattlePlaying(bm)
```

You can tell which style a function uses by looking at the exec trampoline in Ghidra: if the
first `UFunction_ReadParam_ObjectProperty` call targets a `UObject*` local before anything
else, it's taking a WorldContext.

## Reflection call pitfalls checklist

Before treating a Lua failure as a UE4SS bug, check the call boundary:

- Use `:` for instance calls so UE4SS supplies the receiver. Use the documented
  CDO or helper object when the function is actually static or library-style.
- Pass explicit `WorldContextObject` parameters for SC6 helpers that read one.
  Instance-call syntax does not fill that hidden-looking parameter for you.
- Keep UObject work on the game thread. Async callbacks and hot hooks should
  schedule the reflected call rather than walking object graphs directly.
- Do not test reflected function availability with a field read such as
  `if obj.SomeFunction then`. UE4SS can manufacture a callable wrapper before
  the eventual marshalled call proves safe.
- Do not guess parameter shapes, default arguments, out-param layouts, enum
  widths, or struct alignment. Use the UE4SS dump, Ghidra exec trampoline, and
  live runtime logging to validate the exact call. If the metadata is missing,
  changing Lua table shapes will not repair it.
- Treat return values that look like safe defaults as suspicious when the native
  trampoline reads a world context or mode gate. `false`, `0`, or an empty
  result can mean "wrong context", not "the feature is disabled."
- Re-resolve transient UObjects after map/menu transitions before calling any
  reflected function on them, even if a cached wrapper still passes a shallow
  nil check.

## See also

- [Lua API Overview](lua-api.md) — supported SC6 Lua lookup, validity, and
  reflected-call patterns.
- [Hooks & Events](hooks.md) — per-UFunction hook behavior and Lua lifecycle
  rules.
- [Global Hooks](global-hooks.md) — native `ProcessEvent` and tick bridge
  guidance when reflection is not the right layer.
