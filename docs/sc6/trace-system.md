# Trace / Hitbox System

SC6's "trace" system and its hitbox system are two different things that sit next to each other
on the chara. This page covers both, because move scripts drive them in lockstep — but don't
confuse them.

!!! danger "This page was rewritten 2026-04-21 after runtime layout verification"
    Earlier versions of this page claimed `chara+0x388` held a
    `ULuxBattleMoveProvider*` and that the `FLuxCapsule` array was
    reached through `chara+0x388 → +0x30 → +0x30 / +0x38`. **That is
    wrong on the shipping Steam build.**

    - `chara+0x388` is actually `CharaMesh0` — a `USkeletalMeshComponent*`
      written by `ALuxCharaActorBase_Constructor @ 0x140440FB0` as
      `param_1[0x71] = CharaMesh0`. See
      [`ALuxBattleChara` layout in Structures](structures.md#aluxbattlechara)
      for the verified runtime table.
    - `Z_Construct_UClass_ULuxBattleMoveProvider` and the literal string
      `"LuxBattleMoveProvider"` are **absent** from the shipping binary.
      The class either never shipped under that name or is C++-only
      (no UE4 reflection).
    - `ALuxTraceManager::GetTracePosition_Impl @ 0x1408D0BB0` (the
      function that used to walk the capsule array) is therefore **stale
      code** on this build — it still reads `this+0x388 → +0x30 →
      +0x30 / +0x38`, but on real charas it ends up walking a skeletal
      mesh component's internal slots and returning garbage / false.

    The real per-move hit data on this build is still being located;
    current best guess is it lives on `ALuxBattleMoveCommandPlayer` at
    `BattleManager+0x4C0`. The `FLuxCapsule` struct layout documented
    below (0x50 bytes, header + bone-pair endpoints) is still correct —
    what changed is **where the array of capsule pointers lives**.

!!! warning "Naming — `TraceManager` is not the hitbox system"
    **`ALuxTraceManager` is literally "the traces" — the visual weapon trails / swooshes /
    particle effects.** It owns `EffectSlotA/B` (particle systems), a `ULuxTraceComponent`
    (renderable trail component), and a `KindIndex` (`ELuxTraceKindId`, the visual style). It
    does **not** own, store, or resolve hitboxes.

    The two systems share the same `AttackTag` (1..9) as a coordination key so a move script can
    turn on the visual trail and open the corresponding capsule's hit window in one call, but
    they are otherwise independent. `ALuxBattleChara::Active` opens the hit slot in the per-chara
    slot hash (`+0x3B0 / +0x3F0`); `ALuxTraceManager::ActivateTrace` spawns the trail. Either can
    fire without the other.

## Ownership chain (verified on 2026-04-19 Steam build)

```text
ALuxBattleChara
    ├ +0x168  USceneComponent*          CustomRoot0           (chara actor root)
    │
    ├ +0x388  USkeletalMeshComponent*   CharaMesh0            (body mesh; NOT MoveProvider)
    ├ +0x390  USkeletalMeshComponent*   WeaponMesh0           (weapon mesh; NOT Opponent)
    │
    ├ +0x3A8  ULuxTraceComponent*       (often null at spawn; created lazily by
    │                                    ActivateTrace / Setup if missing)
    │
    ├ +0x3B0  FActiveAttackSlot[]       hit-slot hash (keyed by AttackTag 1..9)
    │        +0x3F0/+0x3F8 hash bucket base / count
    │
    ├ +0x448  UBoxComponent*            TestCollision         (query-only box volume)
    │
    ├ +0x458  ALuxTraceManager*         VISUAL ONLY — weapon-trail / FX driver
    │               ├ +0x388  UObject*                     (TraceDataAsset on this build)
    │               ├ +0x398  UParticleSystemComponent*    EffectSlotA
    │               ├ +0x3A0  UParticleSystemComponent*    EffectSlotB
    │               ├ +0x3A8  ULuxTraceComponent*          (trail renderer)
    │               └ +0x400  int32                        KindIndex (ELuxTraceKindId)
    │
    ├ +0x1438 UObject*                  cached MoveComponent (lazy; empty on this build —
    │                                    see note below)
    │
    └ +0x973E8 ALuxBattleChara*         Opponent             (the other side's chara —
                                         read by LuxMoveVM_CheckRangeOrDistance and
                                         CheckAngleOrGeometry)
```

The per-chara hit geometry (`FLuxCapsule` array) is **not** reachable through any of the
fields listed above on this build. Earlier RE passes that thought `chara+0x388 → capsule
container` was the route were misled by a stale function
(`ALuxTraceManager::GetTracePosition_Impl`) that still encodes the old layout but silently
fails on live charas. See the note at the top of this page.

> sources: `ALuxCharaActorBase_Constructor @ 0x140440FB0`,
> `ALuxBattleChara_Constructor @ 0x1403AB8D0`,
> `ALuxTraceManager_ActivateTrace_Impl @ 0x1408D5D10`,
> `ALuxBattleManager_Update_Impl @ 0x140437590`,
> `LuxMoveVM_CheckRangeOrDistance @ 0x140365140`.

## Classes that matter

| Class | Purpose | Size |
|---|---|---:|
| `ALuxBattleChara` | A fighter on stage. Declares the `Active` / `Inactive` / `GetTracePosition` UFunctions. | 0x568 |
| `ULuxBattleMoveProvider` | **Legacy / absent.** Class name does not resolve in the shipping binary — no `Z_Construct_UClass_*` and no matching string (also checked: `"LuxBattleMoveProvider"`, `"LuxBattleMoveComponent"`, `"MoveProvider"` — all missing). Functions that still encode the old layout — `ALuxTraceManager::GetTracePosition_Impl @ 0x1408D0BB0`, `LuxMoveProviderRef_Get @ 0x14045FC70`, `LuxMoveProviderRef_GetSubProvider @ 0x140467FE0` — are **stale code** on this build. Their callers pass `chara+0x388`, which is now `CharaMesh0`, not a MoveProvider. | — |
| `FLuxCapsule` | **Hit system.** One entry per hit/hurt capsule endpoint pair; tagged by `CapsuleType` matching `AttackTag`. Layout unchanged, but the container that holds the `FLuxCapsule**` array has moved — still being located. | 0x50 |
| `ALuxTraceManager` | **Visual only.** Wrapper actor that drives the weapon trail / FX — `ActivateTrace(mode, chara, mesh, kind)` + per-tick `Update(x, y)` stick-axis feed. Not consulted by hit resolution. | 0x408 |
| `ULuxTraceComponent` | **Visual only.** Ticking component that holds the `ActiveTraces` TArray and spawns `ALuxTraceMeshActor` for rendering. | 0x4B0 |
| `ALuxTraceMeshActor` | **Visual only.** Child actor that actually renders the trail (via a procedural mesh component). | — |
| `ULuxTracePartsDataAsset` | **Visual only.** Curves, material params. Not involved in collision. | — |
| `ALuxBattleMoveCommandPlayer` | Command-script VM host at `BattleManager+0x4C0`. Registered name `"BattleMoveCommandPlayer"` via `Z_Construct_UClass_ALuxBattleMoveCommandPlayer @ 0x140953780`. Exposes 5 UFunctions (`GetMovePlayParam`, `IsPlaying`, `PlayMove`, `PlayMoveDirect`, `StopMove`) plus 5 reflected UPROPERTYs (`PlayData`, `Request`, `RequestInfo`, `PlayState`, `PlayStateInfo` at `+0x390..+0x3D0`). Current best guess for where the live `FLuxCapsule` data actually lives on this build — see the [`ULuxBattleMoveProvider` investigation note](structures.md#aluxbattlechara) in Structures. | — |

## UFunctions exposed on `ALuxBattleChara`

Only **three** UFunctions are reflected on this class:

| UFunction | Impl | exec trampoline | Notes |
|---|---|---|---|
| `Active(FTraceActiveParam)` | `1408cd940` | `140c3da20` | Opens an attack-slot tag (1..9) into the per-chara hash at `+0x3B0 / +0x3F0`. |
| `Inactive(FTraceInactiveParam)` | `1408d1420` | `140c3fd00` | Closes it; starts the trail fade. |
| `GetTracePosition(byte, int32, out FVector, out FVector)` | `1408d0bb0` | `140c3f9b0` | **Stale on this build** — see [note at top of page](#trace--hitbox-system). Ghidra symbol: `ALuxTraceManager_GetTracePosition_Impl` (misnamed; wants a chara, not a TraceManager). Returns `false` for every real chara pointer on the shipping build because it looks at `chara+0x388` (which is `CharaMesh0` now, not a MoveProvider). |

> source: Ghidra exec-function enumeration of the `ALuxBattleChara` class.

`Active` takes a 48-byte (`0x30`) `FTraceActiveParam` but **only the first byte matters for hit
logic** — it's the `AttackTag`. The remaining 47 bytes configure the *visual* trail only.

```cpp
struct FTraceActiveParam {  // sizeof == 0x30 (48 bytes)
    uint8    AttackTag;      // +0x00 — the only field Active_Impl reads for hit resolution
    uint32   Flags;          // +0x04 — visual
    // ... cosmetic fields through +0x2C (trail tint FLinearColor at +0x1C)
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
hurtbox. **The struct layout is confirmed; the container that holds the `FLuxCapsule**` array
is not yet located on this build.**

The stale `GetTracePosition_Impl` function still encodes the historical walk:

```text
(stale on this build)
chara (+0x388)  ->  "MoveProvider"         (+0x388 is CharaMesh0 on the real chara)
                         +0x30   -> capsule container              (FLuxCapsuleContainer, 0x40 bytes)
                                       +0x30  -> FLuxCapsule**     (data ptr)
                                       +0x38  -> int32             (Num)
                                       +0x3C  -> int32             (Max)
```

On the shipping build, traversing this chain from a real `ALuxBattleChara*` lands inside a
skeletal mesh component's slots, not a capsule container, and the function returns `false`.
On a `ALuxTraceManager*` (the class the Ghidra symbol is actually named after) it lands on a
`ULuxTraceDataAsset` and walks the visual `TracePartsDataAssetList` — which also has a
`CapsuleType`-shaped byte at `+0x30` but represents a trace-parts kind id, not a hit tag. The
docs' older "first match wins" semantic was correct for the old container but is not reachable
here.

### `FLuxCapsuleContainer` (0x40 bytes)

| Offset | Type | Name | Notes |
|-------:|------|------|-------|
| +0x00..+0x2F | — | internal header | unread by `GetTracePosition` |
| +0x30 | `FLuxCapsule**` | `Data` | pointer to array-of-pointer |
| +0x38 | `int32` | `Num` | element count |
| +0x3C | `int32` | `Max` | allocator capacity |

### `FLuxCapsule` (0x50 bytes)

```cpp
struct FLuxCapsule {         // 80 bytes (confirmed size)
    uint8  header[48];       // +0x00 .. +0x2F — game-internal header, never read by GetTracePosition
    uint8  CapsuleType;      // +0x30  key: matched against Active() tag (1..9)
    uint8  BoneId_A;         // +0x31  8-bit bone index (remapped via LuxSkeletalBoneIndex_Remap)
    // +0x32 .. +0x33 pad
    float  LocalOffset_A[3]; // +0x34  bone-local position (pre UE unit scale; see below)
    uint8  BoneId_B;         // +0x40  second bone id
    // +0x41 .. +0x43 pad
    float  LocalOffset_B[3]; // +0x44  second local offset
    // sizeof == 0x50 — struct ends at +0x50 exclusive
};
```

There is **no visual-parts-asset pointer inside the capsule** — an earlier pass guessed a field
at `+0x50`, but `GetTracePosition_Impl` never reads past `+0x4F`, and the Ghidra type layout caps
the struct at 80 bytes. Visual data lives on the trace component's kind data-asset, not on each
capsule.

> source: `FLuxCapsule` type in the Ghidra data-type manager (80 bytes),
> `ALuxTraceManager_GetTracePosition_Impl` at `0x1408D0BB0` (reads only `+0x30 .. +0x4F`,
> but the caller-side walk is stale — see note at top of page).

The world-space endpoint is computed the same way by the game, every frame:

```text
bone = LuxSkeletalBoneIndex_Remap(BoneId)
T    = ALuxBattleChara_GetBoneTransformForPose(this, PoseSelector, bone)   // FTransform
off  = LocalOffset * g_LuxCmToUEScale * T.Scale                             // internal-units -> UE cm
World = T.Rot * off + T.Pos                                                 // quat rotate + translate
```

`g_LuxCmToUEScale @ 0x143E8A418` holds the scaling constant. Despite the symbol name, the
observed value is **`10.0f`** (bit pattern `0x41200000`), not the `100.0f` an older pass of
these docs claimed. The 10x factor suggests `LocalOffset` is stored in millimetres — or
a similar decimetre-scaled internal unit — so that `offset_internal * 10 = offset_cm`,
which is UE4's native unit.

## `ELuxTraceKindId` (trace visual kinds)

`ULuxTraceComponent` stores the active kind in `+0x498 KindIndexCopy` (int32).
The enum has >30 entries. Selected examples (full list via Ghidra strings
`0x14335A7B0`+):

| Symbol | Meaning |
|---|---|
| `TRC_KIND_NONE` | no trail |
| `TRC_KIND_AUTO` | engine-driven default |
| `TRC_KIND_NORMAL` / `TRC_KIND_NORMAL_S` | default swing trail (S = short) |
| `TRC_KIND_TUBE` / `TRC_KIND_LINE` | geometry variants |
| `TRC_KIND_THUNDER` / `TRC_KIND_WIND` / `TRC_KIND_FLAME` / `TRC_KIND_LIGHT` | elemental |
| `TRC_KIND_SPARK` / `TRC_KIND_FIRE_S` | short-lived VFX |
| `TRC_KIND_P*` (e.g. `TRC_KIND_PFLAME`, `PFLAME_L`, `PSMOKE`, `PBURN`, `PLIGHT`, `PDUST`, `PAURA`, `PTHUNDER`, `PWIND`) | particle-only trails (no mesh); `_L` = large variant |
| `TRC_KIND_LIGHTSABER` | Yoda / Maxi? variant (unconfirmed) |
| `TRC_KIND_KICK` | kick-attack trail |
| `TRC_KIND_ULTIMATE_EDGE` / `TRC_KIND_ULTIMATE_CALIBUR` | super/reversal trails |

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
    See [UE4SS Reflection Gotchas](../ue4ss/reflection-gotchas.md) for the full diagnosis.

    Do not bother with the `GetTracePosition_Impl` workaround from earlier versions of this
    page — the function is stale on this build and returns `false` for every real chara
    pointer. A raw-memory walk of `chara+0x388 → +0x30` lands inside a skeletal mesh
    component, not a capsule array. Until the live capsule container is located, the only
    working surface for reading real hit geometry is indirect (move-script side effects /
    `ProcessEvent` spies on post-hit BP notifications).

## `ReceiveGetWeaponTip` — a promising-looking dead end

SC6 registers a BlueprintImplementableEvent called `ReceiveGetWeaponTip` on
`ALuxBattleWeaponEventHandler`. In a `ProcessEvent` spy log it fires every frame during
attacks — including ranged moves like Cervantes's gun where `GetTracePosition` is silent
— so it *looks* like a universal "give me the weapon endpoint" query.

It isn't. **No SC6 character's Blueprint subclass overrides the event.** A global
`ProcessEvent` post-hook shows every call arriving with `outRoot == outTip == (0,0,0)` and
`bReturnValue == 0`. The native caller (`ALuxBattleManager::GetTracePositionForPlayer @
0x1403F4960`) calls the event first, ignores the result regardless, and falls through to
`ALuxBattleChara::GetTracePosition_Impl` unconditionally. The event exists only as a BP
extension point that no one shipped an implementation for.

See [`ALuxBattleWeaponEventHandler` in Structures](structures.md#aluxbattleweaponeventhandler)
for the UFunction layout and the wrapper-call chain. Documented explicitly so future RE
passes don't lose an afternoon chasing it.

## Empirical capsule-type ranges

The `CapsuleType` byte at `FLuxCapsule +0x30` is matched against the `AttackTag` passed to
`GetTracePosition`. The plate comment on `Z_Construct_UFunction_...GetTracePosition`
documents the *valid* range as 1..9 based on one caller's usage (`SlotIdx + 1`), but a
training-mode scan that iterates `InTracePartsId` values from 1 to 64 empirically sees
many more types populated:

- **Types that fire immediately when the overlay turns on, with characters standing idle**:
  e.g. 1, 2, 3, 15, 18, 21, 24, 27. Shared hilt points across 1/2/3 suggest anchored body
  segments (shoulder joints, arm / leg / torso rigs). These are very likely **hurtboxes**
  — always-on body capsules.
- **Types that fire only during the active frames of an attack**: these are the attack
  capsules proper. Which numeric values get used varies per character and per move.

So the canonical attack-tag range 1..9 only reflects one code path; the full capsule
system uses a wider type space. A mod that wants to visualise everything should scan at
least 1..31, possibly up to 1..63.

!!! info "Catalogue these by watching the log"
    HorseMod's `GetTracePosition` scan logs each `InTracePartsId` the first time it ever
    returns true for a given player in a session. Do a move in training mode, then
    `grep 'first active capsule' UE4SS.log` to see which tag numbers your character's
    attacks activate. The per-character map emerges after a few reps.

## What's still unfound

- **The live `FLuxCapsule` container on this build.** The struct layout (0x50) is confirmed;
  the legacy `chara+0x388 → +0x30` walk is stale because `+0x388` is now `CharaMesh0`. The
  most promising candidate is `ALuxBattleMoveCommandPlayer*` at `BattleManager+0x4C0` (see
  [Battle Manager subsystems](battle-manager.md#battlemanager-subsystem-layout)). Walk its
  fields for an 8-byte aligned pointer to an 0x40-byte container whose `+0x30..+0x3C`
  matches `FLuxCapsuleContainer` (data, num, max) — that's the find.
- **The hit-resolution function.** The page above describes what it *must* look like
  (capsule-vs-capsule tests on whatever the live container ends up being). The exact native
  function doing the tests hasn't been located yet. Candidates in a `ProcessEvent` spy
  during a confirmed hit: `TO_DamageInfo_C::OnDamage` and `CockpitBase_C::OnVitalGaugeEvent`
  — both post-hit signals — should be walked back in Ghidra to their native callers to find
  the resolver.
- **Projectile-style attacks** like Cervantes's pistol. `GetTracePosition` was never reliable
  for these even before it went stale, and `ReceiveGetWeaponTip` is dead. Either these use
  a much higher tag, a completely different entry point, or are resolved via a native path
  that bypasses the chara's UFunction surface entirely. Open question.
- **`FLuxCapsule` radius.** The stale `GetTracePosition_Impl` only reads the two endpoints;
  the "capsule" geometry implies a radius but no field for it has been located in the
  80-byte struct. Likely lives on the `TracePartsDataAsset` or a sibling struct the live
  container points at.

## Key binary addresses (SC6 Steam, image base `0x140000000`)

| Symbol | RVA | Description |
|---|---|---|
| `ALuxTraceManager_GetTracePosition_Impl` | `0x8D0BB0` | **Stale on this build** — Ghidra symbol name doesn't match its signature (takes a chara, not a TraceManager). Reads `this+0x388 → +0x30` which is no longer a capsule container. Returns `false` for every real chara. |
| `execGetTracePosition_ALuxBattleChara` | `0xC3F9B0` | VM trampoline that dispatches to `ALuxTraceManager_GetTracePosition_Impl`. |
| `ALuxBattleChara_Active_Impl` | `0x8CD940` | Opens attack slot. |
| `ALuxBattleChara_Inactive_Impl` | `0x8D1420` | Closes attack slot. |
| `ALuxTraceManager_ActivateTrace_Impl` | `0x8D5D10` | Lazy-creates TraceComponent, spawns trail. |
| `ULuxTraceComponent_BeginTrace` | `0x8D5FF0` | Populates `ActiveTraces[]` from kind data asset. |
| `ULuxTraceComponent_StartTrace` | `0x8D8C40` | `SetActive(true)` — flips rendering on. |
| `ALuxBattleChara_GetBoneTransformForPose` | `0x462760` | `(chara, pose, boneIdx) → FTransform`. |
| `LuxSkeletalBoneIndex_Remap` | `0x898140` | 8-bit internal idx → UE skeleton bone idx. |
| `ALuxBattleManager_GetTracePositionForPlayer` | `0x3F4960` | BM helper that wraps `GetTracePosition` by `(playerIdx, slot)`; inherits the same stale behaviour. |

Offsets are RVA — add the runtime image base (found in your UE4SS log) to get absolute addresses.
