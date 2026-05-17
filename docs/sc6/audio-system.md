# Audio System

How SC6 plays sounds. The short version: **the audio middleware is
CRI ADX2 / ATOMCRAFT** (not Wwise, not FMOD), the **audio thread runs
independently of `Actor::Tick`**, and `MoveVM` bytecode drives every
in-battle sound through either a per-character event-cue scheduler or a
per-move audio-palette tween. Voice-cue tables, weapon-SE bank routing,
and DramaticVoice persona triggers are all UDataAsset-driven.

All addresses absolute (image base `0x140000000`).

## Middleware identification

| Evidence | Confirms |
|---|---|
| `.acb` file paths in strings (e.g. `Sound/_resource/SE/Weapon/CS_NNN_M.acb`, `Sound/_resource/Voice/JP/Character_Voice/J_VO_CV_NNN_OPTION.acb`) | CRI Atom Cue Binary format |
| String vocabulary: `VoiceCueID`, `VoiceCueSheet`, `CueSheet`, `VoiceCueIDConvTable` | CRI ADX2 / ATOMCRAFT API surface |
| 0x150-byte singleton manager owning sheet table + cue-id → instance-id map | CRI Atom Manager pattern |
| `criAtomEx`-style player API (cue id + sheet key → voice instance handle) | ADX2 player object |

> **No Wwise**: no `AK*` symbols, no `.bnk` files. No FMOD: no `FMOD_*` strings. CRI ships an Unreal plugin (`UAtomComponent` — not the stock UE `UAudioComponent`) for the in-world emitter binding. UE owns the spatialization transform; CRI owns the mixer.

## High-level architecture

```text
MoveVM bytecode (per-move authored, per-frame)
│
├── opcode 0x3A  ──► LuxMoveVM_DispatchEffectOp @ 0x140376B20
│                    └── LuxMoveVM_TriggerAudioPaletteCallback @ 0x1403693D0
│                        └── writes FLuxAudioPaletteTween at chara+0x971A8..+0x971B8
│                            (audio-mix parameter lerp — does NOT play any sound)
│
└── anim-notify / "secondary action stack" entries
    └── Event Cue Scheduler at chara+0x95750
        └── LuxMoveVM_TickCharaEventCueScheduler @ 0x14038BD60
            └── LuxMoveVM_SecondaryActionStackOp(chara+0x95788, ...)
                └── LuxAudio_FireSoundCue_ViaVfxDispatcher @ 0x1403110B0
                    └── g_pLuxVfxDispatcher.vtable[0x38]   (sound submit slot)
                        └── LuxAudio_PlayCueIdByByte @ 0x140550900
                            ├── LuxAudio_GetCriAtomManagerSingleton @ 0x140547D60
                            ├── LuxAudio_ResolveCueSheetEntryByKey  @ 0x140547210
                            └── LuxAudio_RegisterActiveVoiceInstance @ 0x14054F8B0
                                └── CRI ADX2 player (independent audio thread)

UE side (mute / spatialization only — CRI's Unreal plugin):
    chara->vftable[0x138]() → animSubObj+0x140 audioBindings
        → walk children for first with `+0x30` set
            → UAtomComponent (vftable[0xA08] = active toggle)
```

> source: function plates at `0x1403693D0`, `0x140550900`, `0x14054F8B0`, `0x140547D60`, `0x140547210`, `0x14038BD60`, `0x1403110B0`.

## Thread model — what runs where

| Component | Thread | Frozen by `g_LuxBattle_VMFreezeByte`? |
|---|---|---|
| CRI ADX2 player (sample mix, voice output) | **own audio thread** | **no** — in-flight voices keep playing |
| MoveVM event cue scheduler @ chara+0x95750 | game thread (`LuxBattle_PerFrameTick`) | **yes** — gated by `LuxMoveVM_GetTimeDilationScalar` |
| `LuxAudio_PlayCueIdByByte` cue submission | game thread (called from scheduler) | yes (transitively) |
| `UAtomComponent` mute / active toggle (CRI's UE plugin) | game thread | no |
| `Audio_RandomTick @ 0x140399B70` | game thread | unverified — sits outside the simulation loop |

> **Implication for any "pause" feature**: freezing the simulation (e.g. via `VMFreezeByte`) stops *new* cue submission but does not silence voices already in flight. To silence them, either mute per-chara via `UAtomComponent::vftable[0xA08]`, or duck the relevant CRI bus via `SoundBusDackingData`.

!!! warning "Fast-forward burst-playback"
    If you let the simulation race forward at high time-dilation
    (e.g. a "fast skip" UX), several frames' worth of cue triggers
    collapse into a single tick and the CRI player gets a burst of
    overlapping voices. Two mitigations: (a) gate the body of
    `LuxAudio_FireSoundCue_ViaVfxDispatcher @ 0x1403110B0` while
    fast-forwarding, or (b) set `UAtomComponent::vftable[0xA08] = false`
    on every chara before the burst.

## Two paths from MoveVM to audio

### Path A — Audio palette tween (opcode `0x3A`)

Per-move-scripted scalar lerp for an audio-mix parameter (volume / duck
level / palette cross-fade). **Does not play sound.**

```c
// LuxMoveVM_TriggerAudioPaletteCallback @ 0x1403693D0
void LuxMoveVM_TriggerAudioPaletteCallback(
    longlong pChara,
    float    flTargetValue,   // lerp target
    int      nFrameCount,     // 0 = snap, >0 = lerp over N dilated frames
    uint     dwPaletteId      // palette bank id (dispatcher pre-writes 1)
);
```

State written to `chara+0x971A8..+0x971B8` (struct `FLuxAudioPaletteTween`):

| Offset | Field | Type |
|---|---|---|
| `+0x971A8` | `dwPaletteId` | `uint`  — palette bank id |
| `+0x971AC` | `nFramesLeft` | `int`   — dilated-frame countdown |
| `+0x971B0` | `flCurrentValue` | `float` — read by downstream mix |
| `+0x971B4` | `flTargetValue` | `float` |
| `+0x971B8` | `flDeltaPerFrame` | `float` — `(target − current) / frames` |

### Path B — Sound cue submission (event-scheduler)

The actual sound-playback path. The MoveVM-scripted "event cue scheduler"
struct at `chara+0x95750` is ticked every dilated frame and dispatches
two kinds of entries:

| Entry type | Field `+0x28` | Dispatch |
|---|---|---|
| Sound cue | `< 0` | `LuxMoveVM_SecondaryActionStackOp(chara+0x95788, chara, argA, argB)` |
| Anim-notify event | `≥ 0` | `LuxMoveVM_SecondaryActionStackPush(chara+0x95788, chara, type, count−1)` |

The sound-cue port at `chara+0x95788` ultimately reaches the CRI player
through `LuxAudio_PlayCueIdByByte`. The scheduler clock at
`chara+0x95750+0x38` advances by `LuxMoveVM_GetTimeDilationScalar(chara)`,
so hitstop or freeze stalls the schedule.

> source: `LuxMoveVM_TickCharaEventCueScheduler @ 0x14038BD60` plate.

## Voice families — three distinct selection drivers

Three independent voice systems, picked from different sources:

### 1. Per-move battle voice (the bulk of in-battle audio)

Authored in the move bytecode itself. The cue id is part of the move
script and fires from the event cue scheduler at the scripted frame.
Selection is fully **contextual** (move + chara state at cue time).

### 2. Ranked-match flavor voice

`ALuxBattleChara_SelectAndPlaySound_Ranked @ 0x1403C8950` picks a byte
cue id from one of three pools based on a time-derived hash:

| Condition | Pool global |
|---|---|
| Not ranked-eligible | `DAT_144145E60` |
| Round-ready, non-ranked | `DAT_144145E70` |
| Round-ready **and** Ranked Match | `DAT_144145E80` |

The hash seed is `FPaths_GameLogDir()` (the digits in the log-file path),
so the pick is **non-deterministic across runs**, replay playbacks
included. These are pre- and post-round flavor lines only — they do not
affect gameplay.

### 3. DramaticVoice (story persona)

`ULuxDramaticVoiceDataAsset` (registration at `0x140161AD0`). Each persona
is keyed by a `DramaticVoiceID` resolved per battle at battle-setup time
from the active battle-rule DataTable:

```c
// ResolveDramaticVoiceID_FromBattleSetting @ 0x1405F2910
//   1. If PlayerLeft.UseAssistor → return -1 (no dramatic voice)
//   2. Else read PlayerLeft.DramaticVoiceID
//   3. Else read PlayerRight.DramaticVoiceID
//   4. Default -1
```

Once the persona is chosen, individual lines are triggered **contextually**
during the match by events on the `ELuxBattleDramaticVoiceTriggerType` enum:

```c
enum class ELuxBattleDramaticVoiceTriggerType : uint8 {
    Reply                    = 0,
    BattleStart              = 1,
    BattleTime               = 2,
    PlayerLife               = 3,
    PlayerWin                = 4,
    ReversalEdge             = 5,
    ReversalEdgeStart        = 6,
    ReversalEdgeMove         = 7,
    ReversalEdgeWin          = 8,
    CriticalEdge             = 9,
    SoulCharge               = 10,
    ChangeMood               = 11,
    ChangeMotion             = 12,
    CriticalEdgeHit          = 13,
    MissionBattleStartCount  = 14,
    MissionPlayerWin         = 15,
    MissionCriticalEdge      = 16,
    ENUM_MAX                 = 17,
};
```

> source: enum string list at `0x143379400 – 0x14337A130`.

DramaticVoice IDs are recorded in the replay header, so dramatic-voice
playback is **deterministic** across replay viewing (same persona, same
trigger conditions, same cue choices).

## Chara offset map — audio state on `ALuxBattleChara`

| Offset | What | Owning function |
|---|---|---|
| `+0x394` | u32 audio active/mute bitfield. Bit 0 = should-play gate, Bit 1 = force-active, Bit 2 = force-mute, Bit 3 = always-active | `LuxBattleChara_SyncAudioActiveState_FromBattleFlags @ 0x140438980` |
| `+0x95750` | Event cue scheduler struct (timing, trigger list at `+0x70`, side-byte at `chara+0x23C`) | `LuxMoveVM_TickCharaEventCueScheduler @ 0x14038BD60` |
| `+0x95788` | Secondary action stack (the sound-cue submit port) | scheduler + dispatcher case `0x3A` |
| `+0x971A8..+0x971B8` | `FLuxAudioPaletteTween` — opcode `0x3A` lerp state | `LuxMoveVM_TriggerAudioPaletteCallback @ 0x1403693D0` |
| `+0x971E8` | **Visual** palette controller (NOT audio — name collision warning) | |

!!! warning "Bit 0 of chara+0x394 is audio-only"
    Flipping bit 0 of `chara+0x394` mutes the chara's voice but does
    **not** pause world simulation. A long-standing "Game Pause" CE
    cheat hooks this site and gets confused by the partial effect. The
    real world-tick pause is `g_LuxBattle_VMFreezeRecord.bVMFreezeByte`
    via [movement.md](movement.md#timedilation-system-verified) /
    [replay-system.md](replay-system.md).

## VFX + Audio dispatcher (`g_pLuxVfxDispatcher`)

Despite the "Vfx" name, `g_pLuxVfxDispatcher` is the **unified VFX + audio
event sink** — the convergence point for every per-frame side-effect MoveVM
bytecode emits. Both VFX spawns and CRI cue submissions route through its
vtable.

Relevant slots:

| Slot | Role |
|---|---|
| `vt[0x30]` | End-of-life cleanup A (called when a cue's owning effect retires) |
| `vt[0x38]` | **Sound cue submit** — bridge from MoveVM cue scheduler to `LuxAudio_PlayCueIdByByte` |
| `vt[0x40]` | End-of-life cleanup B |
| `vt[0x70]` | **Audio palette change** — applies the `FLuxAudioPaletteTween` value to the mixer |

`LuxAudio_GetCriAtomManagerSingleton @ 0x140547D60` has **201 callers**;
nearly every audio path passes through it. If you're hooking the audio
layer at a single chokepoint, that's the one.

## CRI middleware functions (the playback layer)

| Function | Address | Role |
|---|---|---|
| `LuxAudio_GetCriAtomManagerSingleton` | `0x140547D60` | Lazy-init singleton: 0x150-byte CRI manager, thread-once gate at `DAT_1441492F0`, owner of all loaded `.acb` sheets and active voice instances. **201 callers** — chokepoint. |
| `LuxAudio_ResolveCueSheetEntryByKey` | `0x140547210` | Sheet entry lookup (critical-section guarded, ref-counted). Sheet table at `manager+0x08`, count at `manager+0x10`, lock at `manager+0x28`. |
| `LuxAudio_RegisterActiveVoiceInstance` | `0x14054F8B0` | Plays a cue. Generates a non-zero, non-colliding random instance id (`rand()` — non-deterministic) and inserts it into the player's active-voice TMap. Returns the new instance id, or `0xFFFFFFFF` on failure. |
| `LuxAudio_PlayCueIdByByte` | `0x140550900` | Main byte-cue dispatcher. Looks up active player at `manager+0xA8`, resolves the active sheet context at `manager+0xA0`, and submits to `LuxAudio_RegisterActiveVoiceInstance`. |
| `LuxAudio_PlayCueIdByByteThunk` | `0x1405509A0` | Trivial thunk; loses the instance-id return value. |
| `LuxAudio_FireSoundCue_ViaVfxDispatcher` | `0x1403110B0` | Bridge from MoveVM cue scheduler → `g_pLuxVfxDispatcher.vt[0x38]` → CRI. Useful gate point for burst-playback mitigation. |

## DataTable-driven config lookups

A family of FName-keyed `TMap` lookups inside the audio-config UObject.
All share the same probe pattern (FName ctor → `FUN_14089BE30` TMap
probe → return `+8` payload pointer of match):

| Function | FName key | Holds |
|---|---|---|
| `LuxAudio_LookupVoiceCueIDConvTable` @ `0x140425610` | `VoiceCueIDConvTable` | Generic voice-cue-id → CRI cue id remap |
| `LuxAudio_LookupDramaticVoiceData` @ `0x140422930` | `DramaticVoiceData` | Root table mapping DramaticVoiceID → `ULuxDramaticVoiceDataAsset` |
| `LuxAudio_LookupVoiceConvTable_Creation` @ `0x140422170` | `Creation_VoiceConvTable` | Character-creation voice picker |
| `LuxAudio_LookupVoiceConvTable_B5NPC` @ `0x140421740` | `B5NPC_VoiceConvTable` | B5-stage NPC voices |
| `LuxAudio_LookupVoiceConvTable_DV08` @ `0x1404224A0` | `DV08_VoiceConvTable` | Dramatic Voice scenario 08 |
| `LuxAudio_LookupVoiceConvTable_DV17` @ `0x140422620` | `DV17_VoiceConvTable` | Dramatic Voice scenario 17 |
| `LuxAudio_LookupVoiceConvTable_DV56` @ `0x1404227A0` | `DV56_VoiceConvTable` | Dramatic Voice scenario 56 |
| `LuxAudio_LookupSoundBusDackingData` @ `0x140423F40` | `SoundBusDackingData` | CRI REACT-DUCKING bus matrix (`Dacking` = Japanese romaji for "ducking") |
| `LuxAudio_LookupStageMaterialSoundTable` @ `0x1404247B0` | `StageMaterialSoundTable` | Stage-material → foley cue map (concrete / sand / grass / wood / metal …) |
| `LuxAudio_LookupWeaponBankIdTable` @ `0x140425B80` | `WeaponBankIdTable` | (SoulChargeType, bone hash) → weapon-SE bank id |

## Weapon SE bank routing

`LuxObject_GetWeaponBankId_BySoulChargeAndBone @ 0x140425D00` resolves
the bank id used to pick the correct `CS_NNN_M.acb`. Lookup chain:

1. From the chara, deref `+0x20 → sub-object`, then `+0x1E0` (main weapon)
   or `+0x1E8` (alt weapon) based on the bone-slot argument.
2. Read the bone hash byte at descriptor `+0x159` (or `+0x150+0x28` if
   indirected).
3. `FString_Printf("%03X", SoulChargeType)` → FName → `WeaponBankIdTable` row.
4. Read the bank id u32 at `row+0x08+bone_hash*4`.

### DLC weapon `.acb` index map

`LuxObject_CreateAsyncLoader_WeaponSoundACB_RegisterAndAppend @ 0x14042C130`
builds the path `Sound/_resource/SE/Weapon/CS_%03X_%d.acb` (SoulCharge type
in hex, weapon bank id in decimal) and overrides the base folder for DLC
SoulCharge types:

| `SoulChargeType` | Folder prefix |
|---|---|
| `0x09` | `DLC/13/Sound/_resource/SE/Weapon/` |
| `0x17` | `DLC/06/Sound/_resource/SE/Weapon/` |
| `0x22` | `DLC/11/Sound/_resource/SE/Weapon/` |
| `0x28` | `DLC/07/Sound/_resource/SE/Weapon/` |
| `0x30` | `DLC/04/Sound/_resource/SE/Weapon/` |
| `0x60` | `DLC/01/Sound/_resource/SE/Weapon/` |
| `0x61` | `DLC/09/Sound/_resource/SE/Weapon/` |
| `0x13` | base game, but remapped to `0x11` |
| anything else | base game `Sound/_resource/SE/Weapon/` |

Useful when you ship a custom weapon and need its SE bank to load
correctly without owning the DLC slot.

## Per-character voice ACB maps

Character voice files follow
`Sound/_resource/Voice/{JP,US}/Character_Voice/{J,E}_VO_CV_NNN_OPTION.acb`
where `NNN` is the char id in hex. Most characters use a generic per-id
setup; a few (e.g. char ID `0x60`) get their own per-char init function
that inserts the map keys explicitly:

```c
// LuxActor_InitCharacterVoice_Char060_AudioMaps @ 0x14040EB40
// key 0x400004 → "Sound/_resource/Voice/JP/Character_Voice/J_VO_CV_060_OPTION.acb"
// key 0x400005 → "Sound/_resource/Voice/US/Character_Voice/E_VO_CV_060_OPTION.acb"
```

`ULuxCeBankManager` (`StaticClass` accessors at `0x1409A59D0` and
`0x1409A92C0`, UClass slot at `DAT_14414F080`) owns the runtime registry
of loaded character-voice and weapon-SE ACBs.

## Enshutsu (cinematic) voice subsystem

"Enshutsu" (演出 = staging / production) is the cinematic-voice path
used for win poses, pre-round banter, and story-mode lines. Distinct from
in-battle move audio.

| Function | Address | Role |
|---|---|---|
| `LuxVoice_AddVoiceItemsForPose` | `0x14038D350` | Reads the per-chara `ENST`-magic blob at `chara+0x28`, indexes by (poseId, animType), and emits N voice items. |
| `LuxVoice_GetItemCountForAnimType` | `0x14038D550` | Nested switch returning 1, 3, or 0 voice-item count for (animType, voiceCategory). |
| `LuxVoice_EnshutsuHeader_AddVoiceItem` | `0x14038BC40` | Allocates a 32-byte VoiceItem, ref-counts it, and appends to the EnshutsuHeader effect list. |
| `LuxVoice_AllocItemRefCountWrapper` | `0x14038D650` | 24-byte `std::_Ref_count<VoiceItem>` allocator. |
| `LuxVoice_EnshutsuHeader_VoiceItem_ScalarNewDtor` | `0x14038C470` | MSVC scalar deleting dtor. |
| `LuxVoice_RegisterCompiledInScriptStruct_FLuxVoiceTableRawAsset` | `0x140174C10` | UHT-generated `FLuxVoiceTableRawAsset` UScriptStruct registration. |

The per-(animType, category) variant count that `GetItemCountForAnimType`
returns determines which categories get triple variants (taunt / hit
reaction / round-win) versus a single deterministic line.

## Creation-mode voice editing

Two config UObjects:

| Symbol | Address | UClass slot |
|---|---|---|
| `ULuxCreationVoiceEditWindowConfig` | `0x140176790` | `DAT_144150708` |
| `ULuxCreationVoiceTypeSelectWindowConfig` | `0x1401767C0` | `DAT_144150730` |

The TypeSelect window picks a voice parent (shout / scream / panic /
…); the Edit window tunes parameters within the chosen type. Selections
are mapped through `Creation_VoiceConvTable` to CRI cue ids.

## UE-side: `UAtomComponent` bridge

CRI ships an Unreal plugin whose in-world emitter component is
**`UAtomComponent`** (NOT the stock UE `UAudioComponent`). UE owns the
spatialization transform; the AtomComponent forwards the cue submission
to the CRI player. The path from chara to the live component:

```c
LuxAudio_ResolveCharaAudioComponentSlot @ 0x1404265D0:
    obj = this->vftable[0x138]()             // animSubObj / skeletal-mesh holder
    children = *(obj + 0x140)                // audioBindings — AttachChildren-like
    audioComp = FUN_141E4F210(children, 0)   // walk for first child with +0x30 set
    return  FUN_142049490(audioComp)         // checks AtomComponent +0x500
                                             // (active / bAutoActivate)
```

`UAtomComponent::vftable[0xA08]` is the mute / active toggle. See
`LuxBattleChara_SyncAudioActiveState_FromBattleFlags @ 0x140438980` for
the canonical call site.

## Cue sheet types and other audio enums

`ELuxCueSheetType` (sheet key indexed against the manager's sheet table
at `manager+0x08`):

```c
enum class ELuxCueSheetType : uint32 {
    ESCS_CMN                = 0,
    ESCS_GROUND             = 1,
    ESCS_BACK_GROUND        = 2,
    ESCS_FOLEY              = 3,
    ESCS_PLAYER_ONE_WEAPON  = 4,
    ESCS_PLAYER_TWO_WEAPON  = 5,
    ESCS_VO_CMN             = 6,
    ESCS_PLAYER_ONE         = 7,
    ESCS_PLAYER_TWO         = 8,
    ESCS_DRAMATIC_VOICE     = 9,
    ESCS_PLAYER_ONE_OPTION  = 10,
    ESCS_PLAYER_TWO_OPTION  = 11,
    ESCS_MAX                = 12,
};
```

`ELuxVoiceBankType` — which voice-acb slot a runtime cue resolves to:

```c
enum class ELuxVoiceBankType : uint32 {
    EVB_Common          = 0,
    EVB_Character1P     = 1,
    EVB_Character2P     = 2,
    EVB_CharacterOption1P = 3,   // DLC/option voice (e.g. char 060)
    EVB_CharacterOption2P = 4,
    EVB_MAX             = 5,
};
```

`ELuxVoiceLanguage` — selects between the `J_VO_CV_*` and `E_VO_CV_*`
ACB families:

```c
enum class ELuxVoiceLanguage : uint8 { JA = 0, EN = 1, MAX = 2 };
```

`ELuxBattleDramaticVoiceTriggerType` is documented above under
[DramaticVoice](#3-dramaticvoice-story-persona).

## Costume-part SE (`PartsSE` / `PartsBreak`)

Per-costume-part SE is a cue family separate from the chara's main
voice and SE: each clothing or equipment part registers its own cue
triggers, which fire on motion events (swing, walk, jump landing, …)
and on costume-break states. The enums:

```c
enum class ELuxPartsSEType : uint32 {
    SwingKick      = 0,
    Walk           = 1,
    Run            = 2,
    Jump           = 3,
    TouchDown      = 4,
    Other          = 5,
    SwingWeapon    = 6,
    ReversalEdge   = 7,
    MAX            = 8,
};

enum class ELuxPartsSECategory : uint32 {
    None       = 0,
    Waist      = 1,
    Mantle     = 2,
    Arm        = 3,
    Leg        = 4,
    Accessory  = 5,
    Footwear   = 6,
    MAX        = 7,
};

enum class ELuxPartsSEAcsType : uint32 { S = 0, L = 1, MAX = 2 };
                                        // small (light cloth) vs large (heavy)

enum class ELuxPartsBreak : uint32 {
    NULL_  = 0,
    HIGH   = 1,    // outermost layer broken
    MID    = 2,
    LOW    = 3,    // innermost / fully destroyed
    MAX    = 4,
};
```

Modder relevance: PartsSE is the system to tune when a custom outfit
sounds wrong — silent footsteps, missing cloth swing, no break cue when
the costume shatters. Define the SE triggers in the costume part asset,
referencing the correct `ELuxPartsSEType` for each animation event.

## Replay determinism

Audio is **not** part of the deterministic simulation. The simulation
itself is bit-exact across replays (frame counter, MoveVM state, hit
detection), but the audio output may vary:

| Source | Effect | Affects gameplay? |
|---|---|---|
| `rand()` in `LuxAudio_RegisterActiveVoiceInstance` | Instance-handle ids differ per run. | No — handle only used to stop/modify the same voice later. |
| `rand()` in `Audio_RandomTick @ 0x140399B70` (when `*DAT_1441456F0 > 0`) | Per-frame audio-mix RNG scalar differs. | No — mixer modulation only. |
| `FPaths_GameLogDir()` seed in `SelectAndPlaySound_Ranked` | Ranked-match flavor pool pick differs. | No — flavor lines. |
| MoveVM-scripted move cues | Deterministic from MoveVM state. | — |
| DramaticVoice triggers | Deterministic (persona id is in replay header). | — |

> Replay viewing keeps the audio thread running normally. See
> [replay-system.md](replay-system.md) for the world-tick freeze story
> and why `VMFreezeByte` does not silence in-flight voices.

## Where to hook for audio mods

| Goal | Hook |
|---|---|
| Mute a specific chara | `UAtomComponent::vftable[0xA08]` on the chara's audio component (via `LuxAudio_ResolveCharaAudioComponentSlot @ 0x1404265D0`) |
| Mute all in-battle SE/voice | Set `bit 2` of `chara+0x394` (force-mute) on every chara |
| Gate all CRI cue submission at a single point | Hook `LuxAudio_GetCriAtomManagerSingleton @ 0x140547D60` (201 callers) or `LuxAudio_FireSoundCue_ViaVfxDispatcher @ 0x1403110B0` (cue-only chokepoint) |
| Mitigate fast-forward burst-playback | Gate body of `LuxAudio_FireSoundCue_ViaVfxDispatcher` OR toggle `UAtomComponent::vftable[0xA08] = false` before the burst |
| Replace a weapon SE | Drop in `Sound/_resource/SE/Weapon/CS_NNN_M.acb` matching the SoulChargeType + bank id (or the DLC-folder variant) |
| Replace a character voice | Drop in `Sound/_resource/Voice/{JP,US}/Character_Voice/{J,E}_VO_CV_NNN_OPTION.acb` |
| Add a new dramatic voice persona | Add row to the `DramaticVoiceData` DataTable; assign a new `DramaticVoiceID`; surface in the battle-rule DataTable as `PlayerLeft.DramaticVoiceID` |
| Fix custom-costume silence (no footsteps / cloth) | Wire up `ELuxPartsSEType` cues on each costume part asset; set the right `ELuxPartsSECategory` |
| Duck the SE/voice bus | Write a `SoundBusDackingData` config DataTable row targeting the bus you want, then call into the CRI player to activate it |

## Function quick reference

| Symbol | Address | Page |
|---|---|---|
| `LuxMoveVM_TriggerAudioPaletteCallback` | `0x1403693D0` | This page (Path A) |
| `LuxMoveVM_TickCharaEventCueScheduler` | `0x14038BD60` | This page (Path B) |
| `LuxMoveVM_DispatchEffectOp` | `0x140376B20` | [move-system.md](move-system.md) |
| `LuxAudio_PlayCueIdByByte` | `0x140550900` | This page (CRI middleware) |
| `LuxAudio_RegisterActiveVoiceInstance` | `0x14054F8B0` | This page (CRI middleware) |
| `LuxAudio_GetCriAtomManagerSingleton` | `0x140547D60` | This page (CRI middleware) |
| `LuxAudio_ResolveCueSheetEntryByKey` | `0x140547210` | This page (CRI middleware) |
| `ALuxBattleChara_SelectAndPlaySound_Ranked` | `0x1403C8950` | This page (voice families) |
| `ResolveDramaticVoiceID_FromBattleSetting` | `0x1405F2910` | This page (DramaticVoice) |
| `LuxBattleChara_SyncAudioActiveState_FromBattleFlags` | `0x140438980` | This page (chara offsets) |
| `LuxAudio_ResolveCharaAudioComponentSlot` | `0x1404265D0` | This page (UAtomComponent bridge) |
| `LuxAudio_FireSoundCue_ViaVfxDispatcher` | `0x1403110B0` | This page (VFX+Audio dispatcher) |
| `LuxObject_GetWeaponBankId_BySoulChargeAndBone` | `0x140425D00` | This page (weapon SE) |
| `LuxAudio_CreateAsyncLoader_WeaponSoundACB` | `0x14042C130` | This page (DLC ACB map) |
| `LuxAudio_InitVoiceAcbMap_Char060` | `0x14040EB40` | This page (per-character ACB maps) |
| `LuxAudio_OnCharaPartUnregister_RecordReplayIfActive` | `0x140427DF0` | Replay capture of audio state on chara teardown |
| `RegisterCompiledInClass_ULuxDramaticVoiceDataAsset` | `0x140161AD0` | This page (DramaticVoice) |
| `ULuxCeBankManager_StaticClass` | `0x1409A59D0` / `0x1409A92C0` | This page (CeBankManager) |
