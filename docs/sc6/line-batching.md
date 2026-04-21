# Drawing 3D Debug Lines (ULineBatchComponent)

How to draw arbitrary 3D lines from a mod without fighting with UMG widgets or trying to hook
the stripped `DrawDebugLine` path.

!!! tip "TL;DR"
    `UWorld` owns three `ULineBatchComponent` instances that are fully functional in SC6's
    Shipping build. Append `FBatchedLine` entries directly to the `BatchedLines` `TArray`
    at `ULineBatchComponent +0x808` using the game's own `GMalloc`. One of the three
    components — `ForegroundLineBatcher` — renders without depth test, i.e. always on top,
    which is the natural choice for a debug overlay.

## Why this is the right path

The UE4 debug-draw helpers you'd reach for first are **stripped from shipping**:

- `UKismetSystemLibrary::DrawDebugLine` — UFunction is registered but its native handler is
  not bound. Calling it from reflection is a silent no-op.
- `DrawDebugBox` — only the UFunction *constructor* (`Z_Construct_UFunction_DrawDebugBox`)
  survives; the actual implementation is gone via `UE_BUILD_SHIPPING`.
- `ULuxTraceDataAsset::bDebugDrawTraceFrame` — three UPROPERTY bools exist but no code reads
  them. See [Trace / Hitbox System](trace-system.md#debug-draw-flags-stripped-in-shipping).

The `ULineBatchComponent` pipeline is a **different story**:

- `UWorld::Exec("FLUSHPERSISTENTDEBUGLINES")` routes to `ULineBatchComponent::Flush`. That
  path is live code in shipping — the component has real state and real renderers.
- `FBatchedLine` is registered as a live `UScriptStruct`.
- The component's scene proxy rasterises `BatchedLines` every frame.

So drawing a line reduces to: get a `ULineBatchComponent*`, append an `FBatchedLine` to its
`BatchedLines` array, and the engine does the rest.

## UWorld's three batchers

Every `UWorld` owns three of them, all reachable via fixed offsets:

| Offset | Name | Behaviour |
|--------|------|-----------|
| `+0x40` | `LineBatcher` | Depth-tested; entries normally cleared per frame |
| `+0x48` | `PersistentLineBatcher` | Depth-tested; entries persist until `FLUSHPERSISTENTDEBUGLINES` |
| `+0x50` | `ForegroundLineBatcher` | **No depth test, always on top** |

For an always-visible debug overlay, use `ForegroundLineBatcher`. The other two are useful
if you explicitly want the lines to occlude or persist across frames.

```cpp
auto* world = any_uobject->GetWorld();           // any UObject works
auto** slot = reinterpret_cast<UObject**>(
    reinterpret_cast<uint8_t*>(world) + 0x50);   // ForegroundLineBatcher
auto* foreground_batcher = *slot;                // ULineBatchComponent*
```

> source: `Z_Construct_UClass_UWorld @ 0x1428a5b90` registers the three UProperties with
> `size=8` (pointer) at offsets `0x40` / `0x48` / `0x50`.

## ULineBatchComponent layout

Only the `BatchedLines` array matters for drawing. Confirmed via the `Flush` function:

| Offset | Type | Name |
|--------|------|------|
| `+0x808` | `FBatchedLine*` | `BatchedLines.Data` |
| `+0x810` | `int32` | `BatchedLines.Num` |
| `+0x814` | `int32` | `BatchedLines.Max` |
| `+0x818` | `FBatchedPoint*` | `BatchedPoints.Data` |
| `+0x820` | `int32` | `BatchedPoints.Num` |
| `+0x824` | `int32` | `BatchedPoints.Max` |
| `+0x830` | `FBatchedMesh*` | `BatchedMeshes.Data` |
| `+0x838` | `int32` | `BatchedMeshes.Num` |
| `+0x83C` | `int32` | `BatchedMeshes.Max` |
| total class size | | `0x850` |

> source: `ULineBatchComponent::Flush @ 0x141d774c0` zeroes `+0x810 / +0x820 / +0x838` and
> reallocates the three data arrays at `+0x808 / +0x818 / +0x830`.

## FBatchedLine

Per-line POD, 0x34 (52) bytes:

```cpp
struct FBatchedLine {
    FVector      Start;              // +0x00 — 3 × float
    FVector      End;                // +0x0C — 3 × float
    FLinearColor Color;              // +0x18 — 4 × float (RGBA)
    float        Thickness;          // +0x28
    float        RemainingLifeTime;  // +0x2C
    uint8_t      DepthPriority;      // +0x30 — ESceneDepthPriorityGroup
    uint8_t      _pad[3];            // +0x31..+0x33 (natural align to 4)
};
static_assert(sizeof(FBatchedLine) == 0x34, "layout guard");
```

!!! warning "Alignment trap when defining similar structs in your mod"
    Don't use a `uint64_t` for an opaque 8-byte field in a UE4 param-block struct (for
    example `ReceiveGetWeaponTip`'s `inEvent`). A `uint64_t` forces `alignof = 8` on the
    whole struct and the compiler pads `sizeof` up to the next 8-byte boundary — which
    won't match UE4's 4-byte-packed layout. Use `uint8_t[8]` instead so `alignof` stays
    at 4.

> source: `Z_Construct_UScriptStruct_FBatchedLine @ 0x1425cfcd0` registers the struct as
> `"BatchedLine"` with `size = 0x34`.

## Allocator compatibility

The array at `+0x808` was allocated by the game's own `FMemory::Malloc`, which is a thin
wrapper over `GMalloc` (at `DAT_1441971c8`):

```text
FMemory::Realloc(ptr, size, align)
  -> (*GMalloc)->vtable[0x18](GMalloc, ptr, size, align)   // FMalloc::Realloc
```

UE4SS exposes the same `GMalloc` symbol (`RC::Unreal::GMalloc`, an `FMalloc**`). Using
that to grow / reallocate the array is safe — when the component's own `Flush` later tries
to free the buffer, it calls the same `FMalloc::Realloc` on the same instance and sees a
normal allocation header.

```cpp
#include <Unreal/FMemory.hpp>
using RC::Unreal::GMalloc;
void reserveAtLeast(TArrHdr* arr, int32_t needed_count) {
    if (arr->Max >= needed_count) return;
    int32_t new_max = (arr->Max == 0) ? 64
                                      : (needed_count + (needed_count / 4) + 16);
    arr->Data = (*GMalloc)->Realloc(
        arr->Data,
        static_cast<size_t>(new_max) * sizeof(FBatchedLine),
        alignof(FBatchedLine));
    arr->Max = new_max;
}
```

## The scene-proxy dirty problem

`ULineBatchComponent::MarkRenderStateDirty()` is what tells UE4 the scene proxy needs a
rebuild to pick up new `BatchedLines`. Two problems:

- It's not a UFunction (not reachable by reflection).
- The C++ symbol isn't exported and may be inlined.

If you append to `BatchedLines` but never mark dirty, the scene proxy keeps drawing stale
data. Three workable mitigations:

1. **Short lifetime trick (recommended).** Append every line with
   `RemainingLifeTime = 0.05f .. 0.10f`. The component's own `TickComponent` runs the
   lifetime sweep every frame; when a line expires it removes it and internally calls
   `MarkRenderStateDirty`. If you re-append every frame you stay in a steady state where
   the proxy is being rebuilt constantly and always has fresh data. One-to-three frame
   delay on overlay toggle-off (lines finish their lifetime naturally).
2. **Toggle component visibility.** `USceneComponent::SetVisibility(bNewVisibility,
   bPropagateToChildren)` is a UFunction — calling it with the current state flips an
   internal dirty flag. Slightly hacky; not empirically verified as sufficient.
3. **Locate `MarkRenderStateDirty` via vtable pattern scan.** It's a virtual on
   `UActorComponent` with a known position (offset varies by UE version). More work, more
   reliable. Not needed in practice — option 1 works.

## Minimal example

POD type aliases:

```cpp
struct FVec3     { float X, Y, Z; };
struct FLinColor { float R, G, B, A; };
struct TArrHdr   { void* Data; int32_t Num; int32_t Max; };
struct FBatchedLine {
    FVec3     Start;
    FVec3     End;
    FLinColor Color;
    float     Thickness;
    float     RemainingLifeTime;
    uint8_t   DepthPriority;
    uint8_t   _pad[3];
};
```

One-time priming (call with any UObject — a cockpit widget, a chara, anything with a world):

```cpp
RC::Unreal::UObject* foreground_batcher = nullptr;
void prime(RC::Unreal::UObject* pivot) {
    auto* world = pivot->GetWorld();
    if (!world) return;
    auto** slot = reinterpret_cast<RC::Unreal::UObject**>(
        reinterpret_cast<uint8_t*>(world) + 0x50);
    foreground_batcher = *slot;
}
```

Per-frame append:

```cpp
constexpr float kLifetime = 0.10f;
void drawLine(const FVec3& a, const FVec3& b, const FLinColor& col, float thickness) {
    if (!foreground_batcher) return;
    auto* arr = reinterpret_cast<TArrHdr*>(
        reinterpret_cast<uint8_t*>(foreground_batcher) + 0x808);
    reserveAtLeast(arr, arr->Num + 1);
    auto* entry = static_cast<FBatchedLine*>(arr->Data) + arr->Num;
    entry->Start             = a;
    entry->End               = b;
    entry->Color             = col;
    entry->Thickness         = (thickness > 0.0f) ? thickness : 1.0f;
    entry->RemainingLifeTime = kLifetime;
    entry->DepthPriority     = 0;
    entry->_pad[0] = entry->_pad[1] = entry->_pad[2] = 0;
    arr->Num += 1;
}
```

Call `drawLine` from any game-thread hook (e.g. a `CockpitBase_C::Update` pre-hook) for
every line you want visible on the current frame. The component's tick does the rest.

## Key binary addresses (SC6 Steam, image base `0x140000000`)

| Symbol | RVA | Description |
|---|---|---|
| `Z_Construct_UClass_UWorld` | `0x2A5B90` | Registers the three LineBatcher UProperties (`+0x40`, `+0x48`, `+0x50`). |
| `Z_Construct_UClass_ULineBatchComponent` | `0x25C9590` | Class size `0x850`; confirms the layout. |
| `Z_Construct_UScriptStruct_FBatchedLine` | `0x25CFCD0` | Confirms 0x34-byte struct. |
| `ULineBatchComponent::Flush` | `0x1D774C0` | Zeros `Num` at `+0x810 / +0x820 / +0x838`; confirms `BatchedLines.Data` at `+0x808`. |
| `UWorld::Exec("FLUSHPERSISTENTDEBUGLINES")` | `0x21B9ED0` | Routes to `ULineBatchComponent::Flush` on `UWorld+0x48`; proves the pipeline is live in shipping. |
| `GMalloc` (data) | `DAT_0x1971C8` | The `FMalloc**` used by both the game and UE4SS. |
| `FMemory::Realloc` | `0xD51430` | Thin wrapper over `GMalloc::vtable[0x18]`. |
