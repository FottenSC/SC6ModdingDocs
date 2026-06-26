# Battle Message System

> **Verification status.** Everything below is *directly verified* in the
> Ghidra project against `SoulcaliburVI.exe` (image base `0x140000000`). Every
> address on this page corresponds to a function or data symbol that has been
> renamed and plate-commented in Ghidra. Items marked **Unverified** describe
> what I have *not* found in the binary — read those sections as gaps, not
> conclusions.

> **Note on display strings.** The actual on-screen text ("Counter Hit",
> "Back Escape", "Lethal Hit", etc.) is **localised via `Game.locres`** — none
> of those user-visible strings appear in `SoulcaliburVI.exe` as ASCII or
> UTF-16, so grepping the binary for "Back Escape" turns up nothing. The
> binary holds only the enum *names* (e.g. `EMS_ThrowEscapeB`) and the
> reflection metadata that ties an enum value to its localisation key. The
> mapping from `EMS_ThrowEscapeB` to "Back Escape" lives in `Game.locres`
> inside the game pak — extract that file (e.g. with [UnrealLocres]) to read
> the actual display strings.
>
> [UnrealLocres]: https://github.com/akintos/UnrealLocres
>
> Best educated guess at the localisation, based on enum naming and SC6
> community parlance:
>
> | Enum | Likely localised text |
> |---|---|
> | `EMS_ThrowEscapeA` (0x1A) | *Front Escape* (or *A Escape*) — broke an A-button throw |
> | `EMS_ThrowEscapeB` (0x1B) | **Back Escape** (or *B Escape*) — broke a B-button throw |
> | `EMS_AThrow` (0x1E) | *A Throw* (forward A-button throw command) |
> | `EMS_BThrow` (0x1F) | *B Throw* (forward B-button throw command) |
> | `EMS_UThrow` (0x20) | *U Throw* — most likely back-throw / unbreakable from-behind |
>
> This mapping is **not verified from binary** — it's inferred from naming.
> Confirm against `Game.locres`.

The "Battle Message" system is the on-screen banner that flashes during a fight
when something noteworthy happens (e.g. *Counter Hit*, *Punish Attack*, *Wall
Hit*, *Back Escape*, *Lethal Hit*, *Critical Edge*). Its reflection layer is
split across three pieces:

1. **`ELuxBattleMessage`** — UEnum listing every message type the HUD can show.
2. **`FLuxBattleMessageParam`** — UScriptStruct; the payload carried by a
   message (type id, owning player, an integer "Value").
3. **`ULuxBattleMessageReceiverInterface`** — UInterface declaring the two
   UFunctions that deliver a message: `OnReceiveMessage` and
   `SendMessageToOtherLevel`.

Two C++ broadcast helpers walk the actor tree and call the interface UFunction
on every receiver; one Native UFunction wrapper exposes the broadcast to
Blueprint.

---

## ELuxBattleMessage — verified enum values

The enum is declared in `/Script/LuxorGame` with underlying type `uint8`. It
has 39 named entries (numeric values `0..0x26`), extracted directly from
`UEnum_ELuxBattleMessage_RegisterValues @ 0x140984920`:

| Value | Name | Value | Name |
|------:|------|------:|------|
| 0x00 | `EMS_Combo` | 0x14 | `EMS_Revenge` |
| 0x01 | `EMS_BreakAttack` | 0x15 | `EMS_AdrenalineRush` |
| 0x02 | `EMS_UnBlockable` | 0x16 | `EMS_WallHit` |
| 0x03 | `EMS_ReversalEdge` | 0x17 | `EMS_Stun` |
| 0x04 | `EMS_PunishAttack` | 0x18 | `EMS_GuardBurst` |
| 0x05 | `EMS_SitAttack` | 0x19 | `EMS_Ukemi` |
| 0x06 | `EMS_WhileRisingAttack` | **0x1A** | **`EMS_ThrowEscapeA`** |
| 0x07 | `EMS_SimultaneousAttack` | **0x1B** | **`EMS_ThrowEscapeB`** |
| 0x08 | `EMS_8WayRunAttack` | 0x1C | `EMS_WeaponSkill` |
| 0x09 | `EMS_ReversalEdgeCrush` | 0x1D | `EMS_FoodEffect` |
| 0x0A | `EMS_GuardImpactCrush` | 0x1E | `EMS_AThrow` |
| 0x0B | `EMS_AttackCounter` | 0x1F | `EMS_BThrow` |
| 0x0C | `EMS_BreakCounter` | 0x20 | `EMS_UThrow` |
| 0x0D | `EMS_RunCounter` | 0x21 | `EMS_TorophyBraveEdge` |
| 0x0E | `EMS_ImpactCounter` | 0x22 | `EMS_TorophyCannon` |
| 0x0F | `EMS_LethalHit` | 0x23 | `EMS_TorophyShadow` |
| 0x10 | `EMS_CriticalEdge` | 0x24 | `EMS_SoulAttack` |
| 0x11 | `EMS_SoulCharge` | 0x25 | `EMS_MightyImpact` |
| 0x12 | `EMS_GuardImpact` | 0x26 | `ELuxBattleMessage_MAX` |
| 0x13 | `EMS_ReverseImpact` | | |

`ENUM_MAX` (the C++-side trailing entry) appears in the `.rdata` strings at
`0x1432723d8`, next to `ELuxBattleMessage_MAX` (the UEnum-style trailing entry
at `0x14338f940`). Both are reflection bookkeeping; only `ELuxBattleMessage_MAX`
is in the registered value list.

The string `"Torophy"` (sic) in the trophy-prefixed entries is a transliteration
from the Japanese トロフィー. It is what appears in the binary and is the actual
identifier used in the source.

### Where the enum lives in Ghidra

| Symbol | Address |
|--------|---------|
| `UEnum_ELuxBattleMessage_StaticEnum` | `0x140978320` |
| `UEnum_ELuxBattleMessage_RegisterValues` | `0x140984920` |
| `Z_RegisterEnum_ELuxBattleMessage` | `0x14016b720` |
| Cached UEnum* | `DAT_14414e008` |
| Namespace strings (no xref) | `.rdata 0x143270bc8 .. 0x143272380` |

A Ghidra-side enum named `ELuxBattleMessage` (size 1 byte) has been created with
all 39 values.

---

## FLuxBattleMessageParam — verified struct

A UScriptStruct registered in `/Script/LuxorGame` as `LuxBattleMessageParam`. It
is the payload of every battle-message UFunction call.

**Reflection metadata (from `UScriptStruct_LuxBattleMessageParam_StaticStruct`
at `0x14097a860`):**

| Field | Value |
|-------|-------|
| Native size | `0x0c` (12 bytes) |
| Alignment | 4 |
| Cached UScriptStruct* | `DAT_14414e010` |

**Field layout** — verified by reading
`Z_Construct_UScriptStruct_LuxBattleMessageParam @ 0x140992430`. Properties are
added to the reflection layer in declaration order, and the struct size of `0xc`
with alignment `4` constrains the layout to:

```c
struct FLuxBattleMessageParam      // 0x0c bytes
{
    int32_t              Value;        // +0x00  IntProperty
    int32_t              PlayerIndex;  // +0x04  IntProperty
    ELuxBattleMessage    Type;         // +0x08  ByteProperty + UEnum
    uint8_t              _pad[3];      // +0x09  to round to align(4)
};
```

The Ghidra struct has been created as `FLuxBattleMessageParam` with these three
fields (the trailing 3-byte pad is implicit from align(4)).

**Caveat — what `Value` actually holds.** The reflection layer types it as
`int32`, but I have *not* verified what callers stash in it. From the enum
names, plausible guesses are:

- For `EMS_Combo`, the combo hit count.
- For `EMS_WallHit` / `EMS_LethalHit` etc., `0` or a flag.
- For trophy-prefixed entries, a counter.

These are guesses. Don't rely on them without checking the firing site for the
specific message you care about.

### Where the struct lives in Ghidra

| Symbol | Address |
|--------|---------|
| `UScriptStruct_LuxBattleMessageParam_StaticStruct` | `0x14097a860` |
| `Z_Construct_UScriptStruct_LuxBattleMessageParam` | `0x140992430` |
| `Z_RegisterPackage_LuxBattleMessageParam` | `0x14016bc20` |
| `Z_RegisterDynamicCpp_LuxBattleMessageParam` | `0x140975440` |

---

## ULuxBattleMessageReceiverInterface — verified UInterface

A UInterface registered in `/Script/LuxorGame`. It declares two `UFUNCTION`
entries, both of which take a struct parameter named `Message`:

```cpp
UINTERFACE(MinimalAPI, Blueprintable)
class ULuxBattleMessageReceiverInterface : public UInterface { /* … */ };

class ILuxBattleMessageReceiverInterface
{
    GENERATED_IINTERFACE_BODY()

    UFUNCTION(BlueprintNativeEvent, BlueprintCallable, Category="Battle|Message")
    void OnReceiveMessage(const /* struct */& Message);

    UFUNCTION(BlueprintCallable, Category="Battle|Message")
    void SendMessageToOtherLevel(const /* struct */& Message);
};
```

The UFunction flag bits read from
`Z_Construct_UFunction_OnReceiveMessage @ 0x140aa5050` (`0x8020800`) and
`Z_Construct_UFunction_SendMessageToOtherLevel @ 0x140aa5270` (`0x4020401`) are
consistent with **BlueprintNativeEvent** and **Native + BlueprintCallable**
respectively. I have not cross-referenced every individual `EFunctionFlags`
bit, so treat the BP-event annotations above as *probable*, not certain.

### Why `Message` isn't typed `FLuxBattleMessageParam` in the reflection layer

In `Z_Construct_UFunction_OnReceiveMessage` the `Message` parameter is created
via `FUN_1408df7e0(0x78, …)` (the FStructProperty constructor), but the struct
class it points at is **not** hard-bound to `FLuxBattleMessageParam` — it is a
generic FStructProperty.

That matches the observed usage: the existing in-engine callers pass **any
struct or wstring buffer** through this interface. Specifically,
`LuxBattle_BroadcastMessageToActorAndOwners` is invoked from the
character-creation menu code (`FUN_1406ffa80`, `FUN_1406a0a40`, etc.) carrying
`wstring`-style payloads such as `"ChangeChromaKeyColor%f,%f,%f"`,
`"ChangeSituation*"`, and `"DisplayPoseInfo"` — *not* `FLuxBattleMessageParam`.

So `OnReceiveMessage` is **a generic Lux message bus**: it *can* carry
`FLuxBattleMessageParam` but is not restricted to it. Whether the on-screen
`ELuxBattleMessage` HUD banners fire through this same bus or through a
different path is **unverified** — see the Unverified section below.

### Where the interface lives in Ghidra

| Symbol | Address |
|--------|---------|
| `Z_Construct_UClass_ULuxBattleMessageReceiverInterface` | `0x140a993f0` |
| `Z_Construct_UFunction_OnReceiveMessage` | `0x140aa5050` |
| `Z_Construct_UFunction_SendMessageToOtherLevel` | `0x140aa5270` |
| Cached UClass* (interface) | `DAT_144153a80` |
| Cached UFunction* (`OnReceiveMessage`) | `DAT_144153a70` |
| Cached UFunction* (`SendMessageToOtherLevel`) | `DAT_144153a78` |
| Cached FName "OnReceiveMessage" | `DAT_144153040` |
| `Init_FName_OnReceiveMessage` | `0x1401829e0` |

---

## Dispatch — verified

There is one shared dispatcher and two broadcast helpers.

### `ILuxBattleMessageReceiver_Execute_OnReceiveMessage` — `0x140a98140`

```cpp
void ILuxBattleMessageReceiver_Execute_OnReceiveMessage(UObject* receiver, const void* Message)
{
    char paramBuf[20];                          // CDataManager_Impl_InitSlot
    CDataManager_Impl_InitSlot(paramBuf);
    FUN_1408dfa90(paramBuf, Message);           // copy struct/buffer into slot
    UFunction* fn = FUN_140f6e0e0(receiver,     // UObject::FindFunctionChecked
                                  fname_OnReceiveMessage);
    receiver->vtable[0x1f8](receiver, fn, paramBuf); // UObject::ProcessEvent
    FMemory_FreeViaGMalloc(paramBuf);
}
```

This is the only place in the binary that loads the cached `OnReceiveMessage`
FName (`DAT_144153040`). Vtable index `0x1f8` is `UObject::ProcessEvent`. Every
battle-message delivery in the game passes through this function.

### `LuxBattle_BroadcastToSiblingActors` — `0x1403cc980`

Walks the level the actor lives in and calls `Execute_OnReceiveMessage` on
**every actor in the same level that implements
`ULuxBattleMessageReceiverInterface`**, skipping the caller itself.

```cpp
void LuxBattle_BroadcastToSiblingActors(AActor* self, const void* Message)
{
    ULevel* level = self->vtable[0x138](self);  // GetLevel/GetWorld
    TArray<AActor*> actors;
    FUN_1421bb820(level, &actors);              // collect actors
    for (AActor* actor : actors) {
        if (actor != self
            && implements_interface(actor, ULuxBattleMessageReceiverInterface)) {
            ILuxBattleMessageReceiver_Execute_OnReceiveMessage(actor, Message);
        }
    }
}
```

There is exactly **one** caller in the binary:
`execLuxBattle_BroadcastToSiblingActors` at `0x140abe260` — the Native
UFunction handler that exposes the broadcast to Blueprint.

### `LuxBattle_BroadcastMessageToActorAndOwners` — `0x14053d380`

Two-phase variant that hits the target actor first, then walks
`level->OwnedActors[]` and dispatches to every owned actor that implements the
interface. Frees the message buffer at the end.

13 callers in the binary. The confirmed callers are mostly
**character-creation menu** code (`FUN_1406ffa80`, `FUN_1406a0a40`,
`FUN_1406a2a10`, `FUN_1406a3280`, `FUN_1406a98f0`, `FUN_14073c530`,
`FUN_140c03e00`), and they pass `wstring` payloads, not
`FLuxBattleMessageParam`. Those are not battle-HUD messages — they are
creation-menu state events that happen to ride the same interface.

### Where the dispatchers live in Ghidra

| Symbol | Address | Purpose |
|--------|---------|---------|
| `ILuxBattleMessageReceiver_Execute_OnReceiveMessage` | `0x140a98140` | The single ProcessEvent call site |
| `LuxBattle_BroadcastToSiblingActors` | `0x1403cc980` | Broadcast to siblings (skips self) |
| `LuxBattle_BroadcastMessageToActorAndOwners` | `0x14053d380` | Target + level owners |
| `execLuxBattle_BroadcastToSiblingActors` | `0x140abe260` | BP-callable wrapper |

---

## ALuxBattleHUDManager — the renderer

The actual HUD class is registered in Ghidra at `0x140160810`
(`ALuxBattleHUDManager_StaticClass`).

| Field | Value |
|-------|-------|
| Short name (in `/Script/LuxorGame`) | `LuxBattleHUDManager` |
| Native C++ class size | `0x3c0` |
| Hash | `0x4b72d1ff` |
| Cached UClass* | `DAT_14414c648` |
| StaticClass thunk | `ALuxBattleHUDManager_StaticClass @ 0x140160810` |
| Z_Construct_UClass | `Z_Construct_UClass_ALuxBattleHUDManager @ 0x1409149d0` |
| Package register | `Z_RegisterPackage_ALuxBattleHUDManager @ 0x140161830` |

Source path strings (proof of file name):

```
D:\dev\sc6\UE4_Steam\LuxorProto\Source\LuxorGame\Battle\HUD\LuxBattleHUDManager.cpp
```

A debug-log format string `"BattleMessage(%s): "` lives at `0x143276258` in the
same `.rdata` block. Ghidra's wide-string xref index did not recover the
reference site, so the *exact* C++ function that emits this log is not yet
identified in this project. The file name strongly implies that
`ALuxBattleHUDManager` has a `LogTempBattleMessage`-style macro that fires
per-message and prints the enum entry name (`%s` → `UEnum::GetNameStringByValue`
on `ELuxBattleMessage`). **Unverified** — the call site has not been decompiled.

---

## What's *not* verified yet

These items were investigated but not pinned down. They are potential
follow-ups, not conclusions.

### Where `ELuxBattleMessage` values are *fired*

I did not isolate a single C++ function that builds a `FLuxBattleMessageParam`
on the stack, sets `Type = EMS_ThrowEscapeA / EMS_LethalHit / etc.`, and
broadcasts it.

What I tried:

- `search_byte_patterns` for `C6 44 24 ?? 1A` (`mov byte [rsp+disp8], 0x1A`)
  finds only **3 sites** in the entire binary, none in obvious throw-escape
  paths. `0x1A` is `EMS_ThrowEscapeA`.
- xrefs to `LuxBattle_BroadcastMessageToActorAndOwners` are all in
  character-creation-menu code, *not* in battle hit-resolution code.
- xrefs to `LuxBattle_BroadcastToSiblingActors` come only from its Native exec
  wrapper (Blueprint dispatch), so the Blueprint-side callers aren't visible.
- Direct xrefs to the `FLuxBattleMessageParam` UScriptStruct cached pointer
  (`DAT_14414e010`) are only the construction code, not callers.

So one of the following is true:

1. The HUD banners are dispatched from Blueprint (the `BP_BattleHUD_*` widget)
   rather than from C++ — meaning the firing side lives in a `.uasset` BP, not
   in this binary.
2. The HUD banners use a *different* dispatch path not yet found (e.g. a direct
   member-function call on `ALuxBattleHUDManager` rather than a broadcast).
3. The firing site is in C++ but loads `EMS_ThrowEscapeA` via something other
   than a 1-byte stack write (e.g. a `mov` from a register sourced from an enum
   lookup).

Until that is resolved, *how* a custom HUD banner should be triggered cannot be
stated with certainty.

### `Value` field semantics

Typed as `int32` in reflection. Whether it is a hit count, a damage number, a
flag, or a context-specific tag varies per message type. **Unverified.**

### "BattleMessage(%s)" log call site

The format string exists at `0x143276258`, but Ghidra's wide-string xref
analyzer did not pick up the call site. Manual byte-pattern searches for the
address bytes and for a `lea r??, [rip+disp32]` pattern produced no hit. This is
**likely recoverable** by re-running Ghidra's "Auto Analyze" with wide-string
xref detection re-enabled, or by manually computing `disp32 = 0x143276258 - rip`
— neither was done in this session.

### Whether `ALuxBattleHUDManager` implements `ULuxBattleMessageReceiverInterface`

The class size (`0x3c0`) is large enough to host the interface vtable thunk,
and the class name strongly implies it. This has not been confirmed from the
`Z_Construct_UClass_ALuxBattleHUDManager` body. **Unverified.**

---

## Modder feasibility — can we send our own messages?

### Path A — broadcast through the interface (most likely workable)

Build an `FLuxBattleMessageParam` on the stack and call
`LuxBattle_BroadcastToSiblingActors` directly from a native hook:

```cpp
// addr = 0x1403cc980 (LuxBattle_BroadcastToSiblingActors)
using FnBroadcast = void (*)(AActor* self, FLuxBattleMessageParam* msg);

FLuxBattleMessageParam m{};
m.Value       = 1;
m.PlayerIndex = 0;
m.Type        = 0x1A;   // EMS_ThrowEscapeA

reinterpret_cast<FnBroadcast>(0x140000000 + 0x3cc980)(myActor, &m);
```

`myActor` must live in the same `ULevel` as the HUD; otherwise `GetLevel()`
returns a different level from the HUD's owning level and the broadcast never
reaches it. In a battle, any `ALuxBattleChara*` or the `ALuxBattleManager`
should work.

**Caveats:**

- This fires `OnReceiveMessage` only on actors that **implement
  `ULuxBattleMessageReceiverInterface`**. Whether `ALuxBattleHUDManager`
  implements that interface is **unverified**; if it does not, this will not
  show the banner.
- The `Message` UFunction param is a generic FStructProperty, and the
  receiver's BP/native handler dictates how the buffer is interpreted. So even
  if the HUD receives the call, it may expect a `FString` payload (per the
  creation-menu observation) rather than `FLuxBattleMessageParam`. **Test
  before shipping.**

### Path B — direct call on the HUD (more reliable but unverified entry point)

If we identify the C++ method on `ALuxBattleHUDManager` that *takes a
`FLuxBattleMessageParam` and pushes it onto the visible queue*, we can call
that method directly. That entry point is where `EMS_*` values would normally
flow internally.

That method has not been located yet (see Unverified).

### Path C — native `ProcessEvent` diagnostic

If the HUD is implemented partially in `BP_BattleHUDManager.uasset`, the
firing path is the `OnReceiveMessage` BP event handler. A temporary native
detour on `UObject::ProcessEvent` can filter for that UFunction and dump the
receiver plus parameter buffer while you trigger a known message.

This does not *send* messages — it intercepts whatever path is already in use.
Useful for verifying which struct type the HUD actually expects.

---

## Reverse-engineering checklist for the next pass

1. Open `Z_Construct_UClass_ALuxBattleHUDManager @ 0x1409149d0` in Ghidra and
   list every registered UFunction. If one is `OnReceiveMessage`, the HUD does
   implement the interface. If one is named `ShowMessage`, `SetMessage`,
   `PostMessage`, or similar, that is the direct entry point (Path B above).
2. Use a `lea r??, [rip+disp32]` search to locate the call site for
   `0x143276258` (`"BattleMessage(%s): "`) — almost certainly a
   `UE_LOG(LogBattle, …)` inside `ALuxBattleHUDManager::SetMessage` or similar.
3. If neither step identifies the firing path, install a temporary native
   `UObject::ProcessEvent` detour and filter for `OnReceiveMessage` while
   triggering a throw escape in a training-room match. The captured `params`
   buffer reveals both the struct layout the HUD actually receives and which
   actor is calling.
