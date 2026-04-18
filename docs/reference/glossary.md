# Glossary

| Term | Meaning |
|---|---|
| **AOB** | Array-of-bytes signature. A pattern UE4SS scans for at startup to locate engine functions. |
| **BP / Blueprint** | Unreal's visual scripting. Packaged as `.uasset`/`.uexp`. |
| **CDO** | Class Default Object. The template UObject Unreal uses to spawn new instances of a class. |
| **DataTable** | Unreal asset holding rows of a USTRUCT schema. Common for move/parameter data. |
| **exec trampoline** | The `execFoo_ClassName` function UE4 generates for each BP-callable UFunction. Reads params off the VM stack and calls the C++ `_Impl`. UE4SS hooks on the UFunction fire here. |
| **FLuxCapsule** | SC6's collision primitive for both hitboxes and hurtboxes. 80 bytes, holds two bone-local endpoints. Lives on `ULuxBattleMoveProvider`, not on any trace asset. See [Trace System](../sc6/trace-system.md). |
| **FName** | Unreal's interned string type, 8 bytes, used for identifiers. |
| **Impl** | The C++ body of a UFunction (e.g. `ALuxBattleChara::GetTracePosition_Impl`). The game often calls Impls directly, bypassing the exec trampoline — in which case `RegisterHook` on the UFunction name never fires. |
| **MoveProvider** | `ULuxBattleMoveProvider` — the per-chara asset that holds the current move's hit/hurt capsules. Accessed via `chara+0x388` in SC6 native code. |
| **Pak / PAK** | Packaged content archive. SC6 reads game content from `.pak` files. |
| **Pose / PoseSelector** | An int identifying which skeletal pose to sample. In SC6 UFunctions it's effectively the player index (0 = P1, 1 = P2). |
| **Trace** | SC6's internal word for *hitbox*. The "trace system" is the hitbox / weapon-trail system collectively. |
| **UE4SS** | Unreal Engine 4/5 Scripting System — injects Lua/BP modding into UE games. |
| **UFunction** | A reflected Unreal function, hookable from Lua via `RegisterHook`. |
| **UObject** | Root base class of Unreal's reflection system. |
| **UStruct** | Reflected C++ struct. |
