# SoulCalibur VI Internals

Game-specific notes: class paths, structures, and useful entry points discovered while modding.

## Pages

- [Game Structures](structures.md)
- [Character Data](character-data.md)
- [Battle Manager](battle-manager.md)
- [Trace / Hitbox System](trace-system.md)

## Engine version

SoulCalibur VI ships on an Unreal Engine 4.x release in the **4.17-to-4.21** window — always
confirm against your own copy's UE4SS log, which prints the detected version on startup:

```text
[PS] Found EngineVersion: 4.XX
```

Whatever number shows up there is authoritative for your build — Steam / console patches have
been known to bump minor versions, and "which 4.x" changes which UObject memory layout and which
UE4SS release is safest. The UE4SS `LessEqual421` build definition covers any version ≤ 4.21, so
it is the correct build target for SC6 whether the log reports 4.17 or 4.21. The public v3.0.1
release works for most read/write patterns but has known alignment edge cases on pre-4.21
engines; prefer a dev build if you hit odd UStruct misreads.

> source: in-game `UE4SS.log` banner on any SC6 launch.

## Binary identity

- Image base: `0x140000000`
- Module: `SoulcaliburVI.exe` (monolithic; no separate `LuxorGame.dll`)
- Source-path prefix baked into strings: `D:\dev\sc6\UE4_Steam\LuxorProto\Source\LuxorGame\...`
- Internal project codename: **Luxor** — all first-party classes are `ALux*` / `ULux*` / `FLux*`.
