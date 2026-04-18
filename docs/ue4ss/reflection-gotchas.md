# Reflection Gotchas

Things that look like UE4SS bugs but are actually the game binary doing something unusual. If you
hit one of these on SC6, the symptoms match what's described here — don't keep fighting your Lua.

## "Tried calling a member function but the UObject instance is nullptr"

The single most misleading UE4SS error you'll see when modding SC6. The message suggests the
receiver is dead, but in practice it's **emitted for any null pointer encountered inside the
UFunction dispatch path** — including a null entry while UE4SS walks the UFunction's UProperty
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
registration can use the shorter `UE4_RegisterClass(ClassInfo, Name, Size, CRC)` variant, which
skips the property callback entirely. The class still works for the game's own VM (exec trampolines
are wired through a separate path) but has **no UProperty metadata for UE4SS to iterate**.

SC6's `ALuxBattleChara` is registered this way. Its three UFunctions (`Active`, `Inactive`,
`GetTracePosition`) all take parameters, and all three fail from UE4SS Lua for this reason.
Inherited AActor UFunctions like `K2_GetActorLocation` keep working because Epic registers
`AActor` normally.

### Diagnosing it

Pick a UFunction that takes no params from the problem class and call it. If it works, it's
almost certainly a metadata-missing issue rather than a live-object issue. In Ghidra, open the
class's `__StaticClass` symbol and check which registrar it calls:

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
   (pre-4.21) alignment that could change behaviour here. Worth trying, not guaranteed to fix.

### What doesn't work

- **Retrying with different UFunction argument shapes.** Plain tables, `nil`, FVectors returned
  from a working UFunction, dotted-vs-colon calls — all five variants produce the same error on
  SC6. The metadata gap is in the UFunction's UProperty list, not the call site.
- **`RegisterHook` on the UFunction.** Fires when the VM dispatches via `ProcessEvent`. If the
  game's own code calls the `_Impl` directly (as SC6 does for `GetTracePosition`), the hook
  never fires.

## `FindFirstOf` vs `BattleCharaArray[i]`

Both return a usable wrapper for a chara in most cases. But **TArray-element wrappers** (`bm.BattleCharaArray[i]`)
have looser ties to `GUObjectArray` than wrappers returned by `FindAllOf` / `FindFirstOf`. On
class hierarchies that already have marginal reflection metadata, the TArray-element path can
trip extra UE4SS validation that the global-iteration path avoids.

If your UFunction call fails on `bm.BattleCharaArray[i]`, try `FindAllOf("LuxBattleChara")[i]`
first before assuming it's a different problem.

## Static UFunctions with `WorldContextObject`

A surprising number of `ALuxBattleManager` UFunctions (e.g. `IsBattlePlaying`,
`GetBattleManager`) are registered as **static with a `WorldContextObject` parameter**.
Calling `bm:IsBattlePlaying()` on an instance receiver does *not* automatically bind the
instance as the world context — UE4SS passes `nullptr` for that param, the Impl short-circuits
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
