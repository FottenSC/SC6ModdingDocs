# Trace / Hitbox System

SC6 calls its hitboxes "traces" internally. Every attack's hit window, visual weapon trail, and
hit-detection volume is driven by the trace system. This page maps the classes, ownership chain,
and the data the game actually collides against.

!!! warning "Naming"
    Despite the name, **`ALuxTraceManager` is not the hitbox owner** — it's a thin actor that
    wraps a `ULuxTraceComponent`. The *real* runtime state lives on `ULuxTraceComponent`. The
    *real* capsule geometry lives on the chara's `MoveProvider`, not on any trace asset.

## Ownership chain

```text
ALuxBattleChara                 (chara+0x388) -> ULuxBattleMoveProvider (hit capsules live here)
    ├ +0x3A8  ULuxTraceComponent*            (the renderable / active-trace table)
    └ +0x458  ALuxTraceManager*              (thin wrapper; receives UFunction calls)
                   ├ +0x388  MoveProvider back-ref
                   ├ +0x398  UParticleSystemComponent* EffectSlotA
                   ├ +0x3A0  UParticleSystemComponent* EffectSlotB
                   ├ +0x3A8  ULuxTraceComponent*  (same kind of component)
                   └ +0x400  int32  KindIndex     (ELuxTraceKindId)
```

> source: Ghidra reversing of `ALuxTraceManager_ActivateTrace_Impl @ 1408d5d10` and
> `ALuxBattleManager_Update_Impl @ 140437590`.

## Classes that matter

| Class | Purpose | Size |
|---|---|---:|
| `ALuxBattleChara` | A fighter on stage. Declares the `Active` / `Inactive` / `GetTracePosition` UFunctions. | 0x568 |
| `ALuxTraceManager` | Wrapper actor — `ActivateTrace(mode, chara, mesh, kind)` + per-tick `Update(x, y)` stick-axis feed. | 0x408 |
| `ULuxTraceComponent` | The ticking component. Holds the `ActiveTraces` TArray and spawns `ALuxTraceMeshActor` for rendering. | 0x4B0 |
| `ALuxTraceMeshActor` | Child actor that actually renders the trail (via a procedural mesh component). | — |
| `ULuxTracePartsDataAsset` | Visual asset (curves, material params). Not involved in collision. | — |

## UFunctions exposed on `ALuxBattleChara`

Only **three** UFunctions are reflected on this class:

| UFunction | Impl | exec trampoline | Notes |
|---|---|---|---|
| `Active(FTraceActiveParam)` | `1408cd940` | `140c3da20` | Opens an attack-slot tag (1..9) into the per-chara hash at `+0x3B0 / +0x3F0`. |
| `Inactive(FTraceInactiveParam)` | `1408d1420` | `140c3fd00` | Closes it; starts the trail fade. |
| `GetTracePosition(byte, int32, out FVector, out FVector)` | `1408d0bb0` | `140c3f9b0` | Returns bone-relative world coords of a capsule by type. |

> source: Ghidra exec-function enumeration of the `ALuxBattleChara` class.

`Active` takes a 48-byte `FTraceActiveParam` but **only the first byte matters for hit logic** —
it's the `AttackTag`. The remaining 47 bytes configure the *visual* trail only.

```cpp
struct FTraceActiveParam { // 0x30
    uint8    AttackTag;     // +0x00 — the only field Active_Impl reads
    uint32   Flags;         // +0x04 — visual
    // ... cosmetic fields through +0x2C
};
```

## Hit detection model

**SC6 does not use UE4 physics sweeps or overlaps.** An exhaustive scan of `LuxorGame`-prefixed
functions shows zero calls into `Sweep*`, `ComponentOverlap*`, or `GameTraceChannel` paths. All
trace references to `Sweep` / `Overlap` live in engine code called by other systems (character
movement, navmesh).

The collision resolver walks analytical capsule-vs-capsule tests each tick:

1. For each chara's active attack-slot tag (from the slot hash populated by `Active_Impl`),
2. Pull the attacker's `MoveProvider` capsule table (set by the move script) and filter by
   `FLuxCapsule.CapsuleType == tag`,
3. Resolve each matching capsule's two endpoints (bone + local offset → world space),
4. Compare against the opponent's hurtbox capsule list in the same move-provider structure.

No `ECollisionChannel`. No physics scene. Deterministic by design — this is what makes rollback
netcode work.

## FLuxCapsule

The geometry primitive for everything in the trace system. One per attacker endpoint, one per
hurtbox. Lives in a `TArray<FLuxCapsule*>` at `MoveProvider +0x30 -> +0x30` (data ptr) / `+0x38` (count).

```cpp
struct FLuxCapsule {         // 80 bytes
    uint8  header[48];       // game-internal header
    uint8  CapsuleType;      // +0x30  key: matched against Active() tag (1..9)
    uint8  BoneId_A;         // +0x31  8-bit bone index (remapped via LuxSkeletalBoneIndex_Remap)
    float  LocalOffset_A[3]; // +0x34  bone-local position (cm, pre UE unit scale)
    uint8  BoneId_B;         // +0x40  second bone id
    float  LocalOffset_B[3]; // +0x44  second local offset
    ULuxTracePartsDataAsset* VisualPartsAsset;  // +0x50  visual only
};
```

> source: `FLuxCapsule` struct mapped in Ghidra against
> `ALuxBattleChara::GetTracePosition_Impl` at `1408d0bb0`.

The world-space endpoint is computed the same way by the game, every frame:

```text
bone = LuxSkeletalBoneIndex_Remap(BoneId)
T    = ALuxBattleChara_GetBoneTransformForPose(this, PoseSelector, bone)   // FTransform
off  = LocalOffset * 100.0f * T.Scale                                       // cm -> UE units
World = T.Rot * off + T.Pos                                                 // quat rotate + translate
```

The `* 100.0f` is the game-wide cm→UE scaling constant at `DAT_143e8a418`.

## Debug-draw flags (stripped in shipping)

`ULuxTraceDataAsset` declares three UPROPERTY bools:

- `bDebugDrawTraceFrame`
- `bDebugDrawTraceKeyFrame`
- `bDebugDrawTraceVelocity`

They exist as UPROPERTY metadata (registered at `140c0cf60`), but an exhaustive xref scan of the
Steam shipping binary finds **zero consumers** — the debug-draw paths were compiled out via
`UE_BUILD_SHIPPING`. Setting these flags does nothing in release. You have to draw debug lines
yourself (`UKismetSystemLibrary::DrawDebugLine` is not stripped).

## Calling the trace functions from Lua

!!! warning "Reflection limitation"
    `ALuxBattleChara::Active`, `Inactive`, and `GetTracePosition` cannot be called from UE4SS
    Lua reflection in the current public UE4SS builds. The class was registered with the short
    `UE4_RegisterClass` variant instead of `UE4_RegisterClassEx`, so its UFunction parameter
    UProperty metadata is missing — UE4SS surfaces this as the misleading
    *"Tried calling a member function but the UObject instance is nullptr"* error on any call
    that takes arguments. Inherited AActor UFunctions like `K2_GetActorLocation` still work.
    See [UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md) for the full diagnosis
    and viable workarounds (C++ plugin calling `GetTracePosition_Impl` at `1408d0bb0` directly,
    or raw-memory walk of the capsule table).

## Key binary addresses (SC6 Steam, image base `0x140000000`)

| Symbol | RVA | Description |
|---|---|---|
| `ALuxBattleChara_GetTracePosition_Impl` | `0x8D0BB0` | Resolves `(CapsuleType, Pose) → Hilt, Tip`. |
| `execGetTracePosition_ALuxBattleChara` | `0xC3F9B0` | VM trampoline. |
| `ALuxBattleChara_Active_Impl` | `0x8CD940` | Opens attack slot. |
| `ALuxBattleChara_Inactive_Impl` | `0x8D1420` | Closes attack slot. |
| `ALuxTraceManager_ActivateTrace_Impl` | `0x8D5D10` | Lazy-creates TraceComponent, spawns trail. |
| `ULuxTraceComponent_BeginTrace` | `0x8D5FF0` | Populates `ActiveTraces[]` from kind data asset. |
| `ULuxTraceComponent_StartTrace` | `0x8D8C40` | `SetActive(true)` — flips rendering on. |
| `ALuxBattleChara_GetBoneTransformForPose` | `0x462760` | `(chara, pose, boneIdx) → FTransform`. |
| `LuxSkeletalBoneIndex_Remap` | `0x898140` | 8-bit internal idx → UE skeleton bone idx. |
| `ALuxBattleManager_GetTracePositionForPlayer` | `0x3F4960` | BM helper wrapping GetTracePosition by `(playerIdx, slot)`. |

Offsets are RVA — add the runtime image base (found in your UE4SS log) to get absolute addresses.
