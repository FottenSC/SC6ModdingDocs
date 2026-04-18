# SoulCalibur VI Internals

Game-specific notes: class paths, structures, and useful entry points discovered while modding.

## Pages

- [Game Structures](structures.md)
- [Character Data](character-data.md)
- [Battle Manager](battle-manager.md)
- [Trace / Hitbox System](trace-system.md)

## Engine version

SoulCalibur VI ships on **Unreal Engine 4.17**. Confirm against your copy's UE4SS log:

```text
[PS] Found EngineVersion: 4.17
```

This affects which UE4SS release you should use and which UObject layouts are valid. For 4.17 the
`LessEqual421` build definition (added in UE4SS 3.1.0 dev) is the correct target if you build
UE4SS yourself — the public v3.0.1 release works for most things but has alignment edge cases on
pre-4.21 engines.

> source: in-game `UE4SS.log` banner on any SC6 launch.

## Binary identity

- Image base: `0x140000000`
- Module: `SoulcaliburVI.exe` (monolithic; no separate `LuxorGame.dll`)
- Source-path prefix baked into strings: `D:\dev\sc6\UE4_Steam\LuxorProto\Source\LuxorGame\...`
- Internal project codename: **Luxor** — all first-party classes are `ALux*` / `ULux*` / `FLux*`.
