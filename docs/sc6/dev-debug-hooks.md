# Dev / Debug Hooks Left in Shipping

Inventory of developer-facing debug code that survived into the SC6 Steam build, and which
hooks still work vs. which are skeletons with bodies stripped.

## At a glance

**Works:**

- [`ULineBatchComponent`](line-batching.md) — full renderer, three live instances on `UWorld`.
- `AHUD::AddDebugText` (`0x141E70410`) — live UFunction with a real body; pushes into
  `AHUD +0x3E0 DebugTextList` consumed by the HUD canvas every frame.
- `LuxMoveVM_ExecuteAndDumpOpcode` writes a debug-trace buffer at `vmCtx+0x2A28` every tick.
  The write side is live; nothing reads the buffer in shipping. Use it as a free signal
  source for opcode traces and render through your own overlay.

**Doesn't work (reflection metadata only, native body stripped):**

- `UKismetSystemLibrary::DrawDebugLine` (UFunction `0x142558090`) — silent no-op.
- `DrawDebugBox` (UFunction `0x142552640`) — silent no-op.
- `ULuxTraceDataAsset::bDebugDrawTrace*` — three UPROPs at `+0x50` bitfield, zero consumers.
- `ULuxDevBattleHUDSetting` (7 bools) / `ULuxDevBattleSubtitleSetting` (1 bool) — UClasses
  register but property names appear once each (in their own `Z_Construct_UClass`); no native
  C++ reader. Likely consumed by Blueprint graphs in pak chunks, not by the exe.
- Only one `Lux.*` CVar exists: `Lux.Trace.ParallelUpdate` (performance toggle, not debug).

## The `ULuxDev*Setting` classes

Three UClasses with the `LuxDev` prefix are registered at startup. Two are under a `DevOnly`
category — the third is a false positive (it's a regular user-facing setting that happens to
share the naming convention).

### `ULuxDevBattleHUDSetting`  (category `DevOnly`)

- Package: `/Script/LuxorGame`
- `Z_Construct_UClass` @ `0x14091e060` · `StaticClass` @ `0x140914f10` · UClass cache `DAT_14414c5e0`
- Seven `BoolProperty` fields, stored as a bitfield. Offsets are the property order
  `Z_Construct` registers them in:

    | Bit | Name | Likely meaning |
    |-----|------|----------------|
    | `0x01` | `WinningCountVisible` | round counter pips |
    | `0x02` | `StageBGMVisible` | stage BGM identifier overlay |
    | `0x04` | `ShortReplayIconVisible` | training / short-replay watermark |
    | `0x08` | `TrainingOptionVisible` | training mode options panel |
    | `0x10` | `NoticeVisible` | notice / toast text |
    | `0x20` | `AnnounceVisible` | announcer subtitle string |
    | `0x40` | `CockpitVisible` | HUD cockpit / frame chrome |

### `ULuxDevBattleSubtitleSetting`  (category `DevOnly`)

- Package: `/Script/LuxorGame`
- `Z_Construct_UClass` @ `0x1409b13e0` · `StaticClass` @ `0x1409a93a0` · UClass cache `DAT_14414e728`
- One `BoolProperty`: `SubtitleVisible`. Separate from the HUD class because the subtitle system
  has its own rendering stack.

### `ULuxDevSessionChannelSetting`  (category `GameUserSettings`, **not** `DevOnly`)

- Package: `/Script/LuxorSessionUtil` (different module from the other two)
- `Z_Construct_UClass` @ `0x142e20170` · `StaticClass` @ `0x142e1f720` · UClass cache `DAT_1443ffd08`
- One numeric property: `mChannel` (size-0x78 registration, i.e. `IntProperty` / `ByteProperty`).
- **Not** a debug class despite the `LuxDev` prefix — this is the user-facing online matchmaking
  channel selector. Ignore it for hitbox / debug work.

### Are they live in shipping?

No, but not in the sense that matters for a mod author. The UClasses themselves register and
get a CDO. The *property names* (e.g. `WinningCountVisible`) appear exactly once in the binary —
inside the `Z_Construct_UClass` function itself. That means **no native C++ code reads these
flags** at runtime.

If they do anything at all, it's through Blueprint graphs that live in the pak chunks and bind
these properties to UMG widget visibility. Those graphs were not inlined into the shipping exe.

Practical consequence for a mod: you can set the booleans via `GEngine->GetDefaultObject(UClass*)`
all day and it will change nothing visible. The path to HUD element visibility is through the
UMG widget tree, not through these settings.

## `ULuxTraceDataAsset::bDebugDrawTrace*`  — three dead bools

`ULuxTraceDataAsset` exposes three `BoolProperty` debug flags stored as a bitfield at `+0x50`:

| Bit | Name |
|-----|------|
| `0x01` | `bDebugDrawTraceFrame` |
| `0x02` | `bDebugDrawTraceKeyFrame` |
| `0x04` | `bDebugDrawTraceVelocity` |

`Z_Construct_UProperties_ULuxTraceDataAsset` @ `0x140c0cf60` · UClass cache `DAT_144159b60`.

Same story as the HUD settings: registered as UPROPERTies, zero consumers. The draw-trace
paths were compiled out. See [Trace / Hitbox System](trace-system.md#debug-draw-flags-stripped-in-shipping)
for the surrounding context on how `TracePartsDataAssetList` is used for the live VFX overlays.

## UE4 built-in `DrawDebug*` UFunctions

Reflection registration for the standard UE4 debug helpers survives, but their native exec
thunks are not bound:

| Symbol | Address | State |
|--------|---------|-------|
| `Z_Construct_UFunction_UKismetSystemLibrary_DrawDebugLine` | `0x142558090` | UFunction reflected, no `execDrawDebugLine` bound |
| `Z_Construct_UFunction_DrawDebugBox` | `0x142552640` | Same — reflection only |

Calling either from UE4SS reflection lands on an unbound exec slot — silent no-op at best,
crash at worst. This is the universal result of building UE4 with `ENABLE_DRAW_DEBUG = 0`,
which `UE_BUILD_SHIPPING` implies by default.

The actionable workaround is [ULineBatchComponent](line-batching.md). Its rendering path is
fully live in shipping, and `UWorld` hands you three ready-made instances — one of which
draws without depth test, which is what you actually want for a hitbox overlay.

## `AHUD::AddDebugText` — a live overlay pathway

Unlike the `DrawDebug*` helpers, the HUD's per-actor debug-text system is not stripped:

- `AHUD::AddDebugText` @ `0x141e70410` — real function body, not a reflection stub.
- `AHUD::DebugTextList` at `AHUD + 0x3E0` — TArray of pending debug labels, consumed by the
  HUD canvas each frame.

This is the fallback path for text-style overlays (damage numbers, frame advantage, move
names, etc.) when you don't want to spawn your own UMG widget. It won't draw lines or boxes —
only text anchored to an actor — but the plumbing is intact and the HUD already walks the
array in its `DrawHUD` pass.

## `LuxMoveVM_ExecuteAndDumpOpcode` — the dead per-tick debug text

The move-execution VM writes a human-readable debug string to a 128-byte buffer every tick:

- VM context layout: 12 332 bytes total (`FLuxMoveCommandPlayer` VM frame)
- Debug text buffer: `char[128]` at `vmCtx + 0x2A28` (10 792 decimal) — documented as `pDebugTextBuf`
- Format strings found inline: `"ATK:power=%x range=%7.3fm"`, `"ATB:combo=%x yarare=%x"`,
  and similar opcode traces.

The function *writes* the buffer on every move-VM tick in shipping. But an xref scan finds
**no consumer** — nothing in the shipping binary reads the buffer and rasterises it to a
surface. It's a dead pipe: the write side was kept, the display side was dropped.

For a mod this is still useful as a **signal source**, not a display path. You can read the
same buffer at `vmCtx + 0x2A28` via your own pointer and render it through your own overlay
(UMG text or ULineBatchComponent-hosted billboard). You get the dev's pre-formatted frame
trace without having to decode opcodes yourself.

## The only `Lux.*` CVar in shipping

One — and only one — console variable uses the `Lux.` namespace:

```text
Lux.Trace.ParallelUpdate     @ 0x14335b290
```

No `Lux.Battle.*`, no `Lux.Debug.*`, no `Lux.Move.*`, no `Lux.HUD.*`. This is consistent with
the overall picture: the dev CVar surface was cleaned before ship. The one survivor is a
performance toggle, not a debug toggle.

## Summary — what's actually useful to a mod

| Hook | Status | Use it? |
|------|--------|---------|
| `ULineBatchComponent` (line-batching.md) | **Live, full renderer** | Yes — first-choice path for hitbox overlays |
| `AHUD::AddDebugText` | **Live, real body** | Yes — per-actor text labels |
| `LuxMoveVM_ExecuteAndDumpOpcode` buffer | Write-only, dead display | Read it for free move-trace text; render yourself |
| `ULuxDevBattleHUDSetting` bools | Reflection only, BP consumers not in exe | No — flipping bits does nothing native |
| `ULuxDevBattleSubtitleSetting.SubtitleVisible` | Same | No |
| `ULuxTraceDataAsset::bDebugDrawTrace*` | UPROPERTY only, no native reader | No |
| `UKismetSystemLibrary::DrawDebugLine` | Reflection only, no exec handler | No — silent no-op |
| `Z_Construct_UFunction_DrawDebugBox` | Reflection only, no exec handler | No |
| `Lux.Trace.ParallelUpdate` CVar | Live toggle | Only for trace parallelism; not a debug switch |

If the goal is to see hit capsules on screen, go directly to
[Drawing 3D Debug Lines](line-batching.md). Everything else in this document is either
misleading reflection metadata or a write-only log buffer.

## Key binary addresses (SC6 Steam, image base `0x140000000`)

| Symbol | RVA | Notes |
|--------|-----|-------|
| `Z_Construct_UClass_ULuxDevBattleHUDSetting` | `0x91E060` | 7 BoolProperty bitfield under `DevOnly` |
| `ULuxDevBattleHUDSetting::StaticClass` | `0x914F10` | Returns UClass cache at `DAT_14414c5e0` |
| `RegisterCompiledInClass_ULuxDevBattleHUDSetting` | `0x161A70` | Startup registrar |
| `Z_Construct_UClass_ULuxDevBattleSubtitleSetting` | `0x9B13E0` | 1 BoolProperty `SubtitleVisible` |
| `ULuxDevBattleSubtitleSetting::StaticClass` | `0x9A93A0` | UClass cache `DAT_14414e728` |
| `Z_Construct_UClass_ULuxDevSessionChannelSetting` | `0x2E20170` | `mChannel` — **not** a debug class |
| `Z_Construct_UProperties_ULuxTraceDataAsset` | `0xC0CF60` | Registers the three `bDebugDrawTrace*` bools |
| `Z_Construct_UFunction_UKismetSystemLibrary_DrawDebugLine` | `0x2558090` | Reflection only, exec handler stripped |
| `Z_Construct_UFunction_DrawDebugBox` | `0x2552640` | Same |
| `AHUD::AddDebugText` | `0x1E70410` | **Live** — real body, writes into `AHUD +0x3E0` DebugTextList |
| `LuxMoveVM_ExecuteAndDumpOpcode` | (see [move-system.md](move-system.md)) | Writes `pDebugTextBuf` at `vmCtx+0x2A28` |
