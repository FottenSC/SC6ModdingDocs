# Glossary

| Term | Meaning |
|---|---|
| **AOB** | Array-of-bytes signature. A pattern UE4SS scans for at startup to locate engine functions. |
| **BP / Blueprint** | Unreal's visual scripting. Packaged as `.uasset`/`.uexp`. |
| **CDO** | Class Default Object. The template UObject Unreal uses to spawn new instances of a class. |
| **DataTable** | Unreal asset holding rows of a USTRUCT schema. Common for move/parameter data. |
| **exec trampoline** | The `execFoo_ClassName` function UE4 generates for each BP-callable UFunction. Reads params off the VM stack and calls the C++ `_Impl`. UE4SS hooks on the UFunction fire here. |
| **FLuxCapsule** | SC6's collision primitive for both hitboxes and hurtboxes. 80 bytes; only the tail (`+0x30 .. +0x4F`) carries data — two `(BoneId, LocalOffset[3])` endpoints plus a `CapsuleType` tag. Capsules live in a container at `MoveProvider +0x30` as `FLuxCapsule**` / count, not directly on the provider and not on any trace asset. See [Trace System](../sc6/trace-system.md). |
| **FName** | Unreal's interned string type, 8 bytes, used for identifiers. |
| **Impl** | The C++ body of a UFunction (e.g. `ALuxBattleChara::GetTracePosition_Impl`). The game often calls Impls directly, bypassing the exec trampoline — in which case `RegisterHook` on the UFunction name never fires. |
| **MoveProvider** | `ULuxBattleMoveProvider` — the per-chara asset that holds the current move's hit/hurt capsules. Accessed via `chara+0x388` in SC6 native code. |
| **Pak / PAK** | Packaged content archive. SC6 reads game content from `.pak` files. |
| **Pose / PoseSelector** | The `uint32` argument that `ALuxBattleChara::GetBoneTransformForPose` and `GetTracePosition_Impl` take to pick *which* evaluated skeletal pose to sample. Callers in the shipping binary pass small integers (0 and 1 are the values observed from `GetTracePositionForPlayer`), and the values line up with per-player pose slots, but the parameter itself is a pose selector, not a player index — they just happen to coincide for the `PlayerRight` / `PlayerLeft` pair. |
| **Trace** | SC6's internal word for the **visual weapon trail / swoosh / particle FX** on a swing — *not* a hitbox. `ALuxTraceManager` drives traces; it has no role in hit resolution. Hitboxes are `FLuxCapsule` on the `MoveProvider`. The two systems only share an `AttackTag` so a move script can turn both on at once. |
| **TraceManager** | `ALuxTraceManager`. The visual-trail actor on a chara (chara+0x458). Owns `EffectSlotA/B` particle components, a `ULuxTraceComponent` for trail rendering, and a `KindIndex` picking the visual style. Does not own, store, or resolve hitboxes. |
| **UE4SS** | Unreal Engine 4/5 Scripting System — injects Lua/BP modding into UE games. |
| **UFunction** | A reflected Unreal function, hookable from Lua via `RegisterHook`. |
| **UObject** | Root base class of Unreal's reflection system. |
| **UStruct** | Reflected C++ struct. |
| **ULineBatchComponent** | UE4's debug-line rendering component. `UWorld` owns three instances at offsets `+0x40` (depth-tested), `+0x48` (persistent), `+0x50` (foreground / always on top). Appending `FBatchedLine` to its `BatchedLines` array at `+0x808` is the canonical path for mod-drawn 3D debug overlays in a shipping build. See [Drawing 3D Debug Lines](../sc6/line-batching.md). |
| **FBatchedLine** | 0x34-byte POD consumed by `ULineBatchComponent` — `Start` + `End` `FVector`s, `FLinearColor`, `Thickness`, `RemainingLifeTime`, `DepthPriority`. The unit of work for debug-line rendering in shipping SC6. |
| **ForegroundLineBatcher** | The `ULineBatchComponent*` at `UWorld+0x50`. Its scene proxy renders without depth test, so lines always appear on top of world geometry. The recommended batcher for a hitbox overlay — see [Drawing 3D Debug Lines](../sc6/line-batching.md). |
| **ALuxBattleWeaponEventHandler** | Native class that fires `ReceiveGetWeaponTip` as a BlueprintImplementableEvent during SC6 attacks. No SC6 character subclass overrides the event, so every observed call arrives with all-zero out-params — a dead path. Documented in [Game Structures](../sc6/structures.md#aluxbattleweaponeventhandler) so future passes don't rediscover the same null. |
| **ReceiveGetWeaponTip** | A BlueprintImplementableEvent on `ALuxBattleWeaponEventHandler`. Fires every frame during attacks; returns zeros because no BP override ships in SC6. Not a usable data source. See [Trace / Hitbox System](../sc6/trace-system.md#receivegetweapontip-a-promising-looking-dead-end). |
| **GlobalCallbackId** | The `uint64_t` handle returned by the non-deprecated `RC::Unreal::Hook::Register*Callback` overloads. Required to call `Hook::UnregisterCallback(id)` on mod teardown so global callbacks don't outlive their mod instance. See [Global Hooks](../ue4ss/global-hooks.md). |
| **ProcessEvent spy** | Diagnostic pattern: install a global `Hook::RegisterProcessEventPreCallback`, log each unique `(UClass, UFunction)` observed exactly once. Lets you answer "which UFunctions fire during this one action?" without speculation. See [Global Hooks](../ue4ss/global-hooks.md). |
| **GMalloc** | UE4's global `FMalloc*` pointer (shipping SC6: `DAT_1441971C8`). Thread-safe heap allocator shared by `FMemory::Malloc/Realloc/Free` and UE4SS's `RC::Unreal::GMalloc`. A mod that wants to grow a game-owned `TArray` must use this same allocator — otherwise the component's later `Flush` frees a buffer the CRT allocated and corrupts the heap. |
