# Drawing 3D Debug Lines (ULineBatchComponent)

The one live debug-draw path in SC6 Shipping: `UWorld`'s three `ULineBatchComponent`
instances. Append `FBatchedLine` entries to the `BatchedLines` `TArray` at component
`+0x808` and the engine renders them every frame.

## At a glance

- **Use** `ForegroundLineBatcher` at `UWorld+0x50` — no depth test, always on top.
- **Append** to `ULineBatchComponent+0x808 BatchedLines` (`{Data, Num, Max}` at
  `+0x808/+0x810/+0x814`).
- **Allocate** through the game's `GMalloc` (`DAT_0x1971C8`); `FMemory::Realloc` at `0xD51430`.
- **Mark dirty** with `UActorComponent::MarkRenderStateDirty @ 0x1D4E910` after the append,
  or rely on the lifetime-sweep auto-dirty (set `RemainingLifeTime ≈ 0.1f` per entry and the
  component's tick will re-mark itself a few frames later).

## What's stripped vs what's live

| Path | Status |
|------|--------|
| `UKismetSystemLibrary::DrawDebugLine` | UFunction registered (`0x142558090`), exec handler unbound — silent no-op |
| `DrawDebugBox` | UFunction constructor only (`Z_Construct_UFunction_DrawDebugBox @ 0x142552640`); implementation gone via `UE_BUILD_SHIPPING` |
| `ULuxTraceDataAsset::bDebugDrawTrace*` | UPROPERTY metadata only; zero consumers |
| **`UWorld::Exec("FLUSHPERSISTENTDEBUGLINES")` → `ULineBatchComponent::Flush`** | **Live in shipping.** Routes through the component as expected. |
| `FBatchedLine` UScriptStruct | Live |
| Scene proxy `BatchedLines` rasterisation | Live, every frame |

For the full inventory of dev-left-behind hooks (including `ULuxDev*Setting` classes and
the per-tick move-VM debug text buffer), see [Dev / Debug Hooks](dev-debug-hooks.md).

## UWorld's three batchers

Every `UWorld` owns three of them, all reachable via fixed offsets:

| Offset | Name | Behaviour |
|--------|------|-----------|
| `+0x40` | `LineBatcher` | Depth-tested, per-frame |
| `+0x48` | `PersistentLineBatcher` | Depth-tested; entries persist until `FLUSHPERSISTENTDEBUGLINES` |
| `+0x50` | `ForegroundLineBatcher` | **No depth test, always on top** |

For an always-visible debug overlay, use `ForegroundLineBatcher`. The other two are useful
if you explicitly want the lines to occlude or persist across frames.

!!! warning "Depth-tested batchers are mostly useless for hit-volume overlays"
    The two depth-tested slots (`+0x40` / `+0x48`) sound appealing — "draw the lines but
    let geometry occlude them" — but in SC6 character meshes and stage geometry are
    **always closer to the camera** than the bone-attached hit volumes you're trying to
    draw. The result is that hitbox / hurtbox lines disappear behind characters,
    weapons, and props for most of every match. HorseMod tried exposing the depth-tested
    slot as a `Default` UI option and ended up hiding it again because the overlay was
    only visible for the few frames per round when nothing was between the camera and
    the chara. **`ForegroundLineBatcher` (`+0x50`) is the only practical choice** for an
    always-visible hitbox overlay.

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

`UActorComponent::MarkRenderStateDirty()` is what tells UE4 the scene proxy needs a
rebuild to pick up new `BatchedLines`. It's not a UFunction (not reachable by
reflection), but the C++ implementation **is not inlined** in SC6 shipping — it lives
at a known address and can be called directly.

> **Location:** `UActorComponent::MarkRenderStateDirty @ 0x141d4e910`
> (RVA `0x1D4E910`). Ghidra had this mis-labeled as
> `UActorComponent_ConditionalRegisterComponentInternal`; the body matches the
> canonical UE4 pattern — gate on `RegistrationState == RS_REGISTERED` (bits 0x3 at
> `UActorComponent+0x188`), set `bRenderStateDirty` (bit 0x20 at `+0x188`), then
> call `MarkForNeededEndOfFrameRecreate @ 0x141d4e7b0`. Confirmed by the xref from
> `USceneComponent::SetVisibility @ 0x141dad60a` which calls it unconditionally.

If you append to `BatchedLines` but never mark dirty, the scene proxy keeps drawing
stale data. Four workable mitigations, in roughly descending order of reliability:

1. **Direct call to `MarkRenderStateDirty` (recommended).** After your per-frame
   appends, call the function above on the batcher pointer. No UFunction lookup, no
   vtable scan — just a plain function pointer at a fixed RVA.

    ```cpp
    using MarkRenderStateDirty_t = void(__fastcall*)(void* component);
    static auto MarkRenderStateDirty = reinterpret_cast<MarkRenderStateDirty_t>(
        reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr)) + 0x1D4E910);

    drawLine(...);          // possibly many
    MarkRenderStateDirty(foreground_batcher);
    ```

2. **Short lifetime trick.** Append every line with `RemainingLifeTime = 0.05f ..
   0.10f`. The component's own `TickComponent` runs the lifetime sweep every frame;
   when a line expires it removes it and internally calls `MarkRenderStateDirty` (the
   same function at `0x141d4e910`) via `Flush` at the end of the sweep. If you
   re-append every frame you stay in a steady state where the proxy is being rebuilt
   constantly and always has fresh data. One-to-three frame delay on overlay
   toggle-off (lines finish their lifetime naturally). Works without any direct
   function-pointer binding.
3. **Toggle component visibility.** `USceneComponent::SetVisibility(bNewVisibility,
   bPropagateToChildren)` is a UFunction that calls `MarkRenderStateDirty` as its
   tail path (confirmed by the xref from `SetVisibility` to `0x141d4e910`). Slightly
   hacky but UFunction-only.
4. **Locate `MarkRenderStateDirty` via vtable pattern scan.** Engine-version-robust
   fallback; not needed for SC6 since option 1 gives a direct address.

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
| `UActorComponent::MarkRenderStateDirty` | `0x1D4E910` | Sets `bRenderStateDirty` (bit 0x20 at `+0x188`) and queues an end-of-frame proxy rebuild. Call directly after appending to `BatchedLines`. |
| `UActorComponent::MarkForNeededEndOfFrameRecreate` | `0x1D4E7B0` | Tail-called from `MarkRenderStateDirty`; do not call directly. |
| `UWorld::Exec("FLUSHPERSISTENTDEBUGLINES")` | `0x21B9ED0` | Routes to `ULineBatchComponent::Flush` on `UWorld+0x48`; proves the pipeline is live in shipping. |
| `GMalloc` (data) | `DAT_0x1971C8` | The `FMalloc**` used by both the game and UE4SS. |
| `FMemory::Realloc` | `0xD51430` | Thin wrapper over `GMalloc::vtable[0x18]`. |
