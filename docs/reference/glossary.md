# Glossary

| Term | Meaning |
|---|---|
| **AOB** | Array-of-bytes signature. A pattern UE4SS scans for at startup to locate engine functions. |
| **BP / Blueprint** | Unreal's visual scripting. Packaged as `.uasset`/`.uexp`. |
| **CDO** | Class Default Object. The template UObject Unreal uses to spawn new instances of a class. |
| **DataTable** | Unreal asset holding rows of a USTRUCT schema. Common for move/parameter data. |
| **FName** | Unreal's interned string type, 8 bytes, used for identifiers. |
| **Pak / PAK** | Packaged content archive. SC6 reads game content from `.pak` files. |
| **UE4SS** | Unreal Engine 4/5 Scripting System — injects Lua/BP modding into UE games. |
| **UFunction** | A reflected Unreal function, hookable from Lua via `RegisterHook`. |
| **UObject** | Root base class of Unreal's reflection system. |
| **UStruct** | Reflected C++ struct. |
