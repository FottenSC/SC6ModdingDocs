# Export SC6 `.mot` animations to Blender

**Goal**: turn one clip from an extracted SC6 `chrXXX.mot` bank into a baked
Blender Action on the matching character armature, without confusing the raw
authored motion with the game's final IK- and overlay-adjusted pose.

**Requires**: a legally extracted SC6 installation, the matching character
skeletal mesh and skeleton, Blender, a UE4 skeletal-mesh exporter, and either
an HgMotion decoder or a runtime matrix-capture hook.

!!! warning "There is not yet a one-click SC6 MOT importer"
    `.mot` is Lux/HgMotion data, not an Unreal `AnimSequence` and not the
    unrelated `.mot` formats used by other games. FModel, UE Viewer, and a
    generic Blender `.mot` add-on do not decode it. The practical tool boundary
    is a small SC6 converter plus an optional Blender front end; the difficult
    part is the converter, not Blender's file-picker UI.

The HorseMod repository contains the current
[motion-bank parser](https://github.com/FottenSC/HorseMod/blob/main/tools/moveset_parser/luxformats.py)
and
[reference Huffman/root decoder](https://github.com/FottenSC/HorseMod/blob/main/tools/moveset_parser/hgmotion_reference.py).
They are evidence-backed starting points, not a complete skeleton solver or a
Blender importer.

## Choose what to export

The word "animation" can mean three different outputs in SC6. Pick one before
writing code because they require different inputs.

| Target | What it contains | Required source | Recommended use |
|---|---|---|---|
| Authored MOT sample | The local transforms produced by the selected HgMotion clip | `.mot`, matching merged reference-pose data, logical-channel mapping, and body-profile scaling | Editing and studying authored motion |
| Final gameplay pose | The pose after reference values, hierarchy, IK, retracking, overlays, and later skeleton work | Runtime capture, or a reimplementation of the entire native pose pipeline | Highest-fidelity Blender playback |
| Root curve only | Selector `0x16` translation/facing output | `.mot` and the known Huffman/channel decoder | Movement plots and an early converter milestone |

For a first useful exporter, capture the final gameplay matrices at runtime and
bake them. In parallel, use that capture as the oracle for the offline `.mot`
decoder. A `.mot`-only result must be labelled **authored MOT sample**, not
"the exact in-game animation."

## Why `.mot` alone is insufficient

`LuxBattleChara_SolveBonePose @ 0x1402EDB90` does much more than sample a clip.
It combines up to four ordered motion slots with persistent decoded state,
reference transforms, authored defaults, controller/retracking values, scale,
spine solving, two-bone IK, and signed parent mappings. It also obtains its
reference values from a merged, layered `FLuxMoveDataEntry` bank rather than
from the `.mot` file.

The initialization path confirms the dependency:

```text
LuxBattleChara_LoadMovesetEntries_BonesAndJapaneseVtb @ 0x140312040
  merges base and PARTS/NMD3 move-data layers

LuxBattleChara_InitBoneRefPositions @ 0x1402EA810
  builds reference vectors and FK metadata from the merged 0x70-byte entries

LuxBattleChara_RescaleBoneSizePositions @ 0x1402E9F90
  applies body-profile upper/lower scale and recomputes IK lengths

LuxBattleChara_SolveBonePose @ 0x1402EDB90
  samples MOT slots, applies reference values, hierarchy, spine solving, and IK

LuxMoveVM_EvaluateBonePose @ 0x1402F0F20
  applies the active clip and its nine signed logical-transform mappings

LuxSkeleton_UpdateBoneTransforms @ 0x14034B8D0
  performs later blending, auxiliary constraints, and spring/collision work
```

Therefore, copying one `.nmd` file beside one `.mot` is not a complete offline
input set. Either reproduce the merge and rescale path or capture the already
resolved runtime matrices.

## Export the matching model and armature

SC6 is an Unreal Engine 4.17.2 game. For character `001`, the principal model
and skeleton packages are:

```text
/Game/Chara/001/r_all_001
/Game/Chara/001/r_all_001_Skeleton
```

Replace `001` with the character/style id being decoded. Export the
`SkeletalMesh` with a CUE4Parse-based tool such as
[FModel](https://github.com/4sval/FModel/wiki/Getting-Started). FModel can save
skeletal models as PSK; current releases also expose newer mesh formats. For
PSK, install the maintained
[PSK/PSA Blender extension](https://github.com/DarklightGames/io_scene_psk_psa),
then use **File -> Import -> Unreal PSK**.

Preserve these properties:

- all bones, including apparently non-deforming or controller bones;
- original bone names and parent relationships;
- the imported bind pose;
- the model import's axis and unit conversion.

Do not rebuild or auto-reorient the armature after importing it. PSK has no
declared unit system, so record any scale selected during import. The animation
converter must apply the same conversion.

FModel's animation tab does not solve this step: SC6's `.mot` clips are raw
battle files and are not `AnimSequence` exports.

## Extract and split the motion bank

The character bank normally appears at:

```text
/Game/Battle/mot/chrXXX.mot
```

Shared banks also exist, including `chr000.mot` and `chr0FF.mot`. The packed
motion id used by `LuxMoveVM_InitMotionPlayback @ 0x140300400` selects a bank
with `(id >> 12) & 0xF` and a clip with `id & 0x7FF`; do not assume every move
uses the character-local bank.

The outer bank is little-endian:

```text
+0x00  u32          motion_count
+0x04  u32          reserved; zero in shipped banks
+0x08  u32[count]   absolute file offsets
```

There is no guaranteed `count + 1` end offset. Repeated offsets mean multiple
clip ids resolve to the same payload. For every non-final distinct offset, the
next greater offset is a safe outer bound. EOF is only an upper bound for the
last distinct offset because native code derives the clip's internal regions
without an outer size.

This minimal splitter preserves aliases:

```python
from pathlib import Path
import struct


def read_mot_bank(path: Path) -> tuple[bytes, list[int]]:
    raw = path.read_bytes()
    if len(raw) < 8:
        raise ValueError("MOT is smaller than its header")
    count, reserved = struct.unpack_from("<II", raw, 0)
    if reserved != 0:
        raise ValueError(f"unexpected reserved dword: 0x{reserved:X}")
    table_end = 8 + count * 4
    if table_end > len(raw):
        raise ValueError("MOT offset table exceeds the file")
    offsets = list(struct.unpack_from(f"<{count}I", raw, 8))
    if offsets != sorted(offsets):
        raise ValueError("MOT offsets are not monotonic")
    if any(offset < table_end or offset >= len(raw) for offset in offsets):
        raise ValueError("MOT offset is outside the data area")
    return raw, offsets


def clip_upper_bound(raw: bytes, offsets: list[int], clip_id: int) -> bytes:
    start = offsets[clip_id]
    end = next((value for value in offsets[clip_id + 1:] if value > start), len(raw))
    return raw[start:end]
```

Use the move bank's animation id when available instead of choosing an offset
by eye. Repeated offsets are aliases; treating the earlier entries as zero-byte
clips changes the bank's semantics.

## Implement the HgMotion decoder

The following stages are required for an offline authored-pose export.

### 1. Parse the clip header

The native sampler consumes at least these fields:

| Clip offset | Field | Use |
|---:|---|---|
| `+0x00` | `u16 frame_count` | Logical duration |
| `+0x02` | encoded decoded-word count | Native code shifts it right once |
| `+0x04` | `u32 flags` | Sampling rate, table selection, precision, and other behavior |
| `+0x08` | channel-presence descriptor | Controls which selector-stream entries consume words |
| `+0x1C` | frame-group size/offset data | Locates compressed eight-frame groups |

`LuxMotion_SampleKeyframeTransforms @ 0x1402E7780` applies half- or
quarter-rate flags before selecting encoded keyframes. Bake the result at the
logical 60 Hz timeline; do not mistake fewer encoded keyframes for a shorter
animation.

### 2. Decode the frame words

`LuxMotion_DecodeHuffmanKeyframeData @ 0x1402E71E0` works in eight-frame
groups. Each group begins from signed 16-bit base words. Later frames apply
Huffman-coded, second-order accumulated deltas. A pose sampled between encoded
frames needs both the current and next word arrays.

Match the native 16-bit wrapping behavior. Reject a stream that reads outside
the clip's established internal region; the game itself assumes trusted data
and does not provide the bounds checks an exporter needs.

### 3. Walk the selector stream and interpolate

`LuxMotion_BlendKeyframeTransforms @ 0x1402E79C0` walks a fixed selector stream
and the clip's presence mask. Flag bit `0x8000` chooses the alternate stream.
The default shipped stream addresses 32 logical transforms; the alternate
stream addresses 22.

Important selector roles confirmed in the native switch include:

| Selector | Confirmed role |
|---:|---|
| `0x02`, `0x19` | quaternion rotation forms |
| `0x03`, `0x1A` | translation forms |
| `0x13` | scale |
| `0x16` | logical root transform plus a facing side channel |
| `0x15` | marker/control selector; it does not advance like a normal bone transform |
| `0x14`, `0x17`, `0x18` | auxiliary scratch vectors consumed by later pose/IK work |

Do not turn every selector into a Blender bone. In particular, the auxiliary
selectors publish solver inputs, and the root/control selectors have special
cursor behavior. Blend rotations as quaternions and use the same current/next
fraction that the native sampler computes.

### 4. Supply defaults and solve the logical hierarchy

Inactive channels retain reference/default data. The native decoded scratch
area also persists between ordered motion-slot samples, so clearing every
channel before every layer is not native-equivalent.

For an authored-pose export, reproduce:

1. the merged base plus PARTS/NMD3 reference entries;
2. the character body-profile rescaling;
3. default rotation, translation, and scale for absent channels;
4. the default or alternate logical-channel mapping;
5. parent composition into model-space matrices.

Stop here only if the result is intentionally an authored sample. Spine IK,
analytic limb IK, retracking/controllers, overlays, and later skeleton updates
are separate fidelity stages.

## Normalize matrices for Blender

Do not send the game's raw 16 floats directly to `mathutils.Matrix`. First
normalize the native row/column convention, then transfer the deformation onto
the imported Blender bind pose. This avoids depending on the visual direction
of Blender's edit-bone tails.

For column-vector matrices, the model-space deformation is:

```text
D_game = pose_game @ inverse(rest_game)
pose_blender = C @ D_game @ inverse(C) @ rest_blender
```

`C` is the exact axis/unit conversion used for the model import. SC6's battle
space uses X/Z as the ground plane and Y as vertical. The confirmed Lux-to-UE
position conversion is:

```text
UE(X, Y, Z) = Lux(X, Z, Y) * 100
```

If the Blender model remains in UE centimeters, preserve that scale. If the
model was converted to meters, fold the same factor into `C`. Test a known
forward-moving root clip before applying a guessed sign flip.

For the interchange step below, output **Blender armature-space,
column-vector matrices** after this normalization. Store the 16 values as four
JSON rows.

## Write the neutral animation file

A small JSON boundary is easier to debug than a Blender add-on and keeps the
HgMotion decoder independent of Blender:

```json
{
  "schema": "sc6-armature-matrices-v1",
  "action": "chr001_clip_0123",
  "fps": 60,
  "matrix_space": "blender_armature",
  "frames": [
    {
      "frame": 0,
      "bones": {
        "root": [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]
      }
    }
  ]
}
```

Requirements for this contract:

- each frame contains the same set of exported bone names;
- every matrix is already in Blender armature space;
- matrices contain scale; do not silently discard it;
- samples use logical 60 Hz frames, including the final frame;
- bone names, not array order alone, bind samples to the armature.

## Bake the JSON into a Blender Action

Select the imported armature, open Blender's **Scripting** workspace, paste the
following script, set `JSON_PATH`, and run it. The core bake was smoke-tested
headlessly with Blender 5.1.

```python
from pathlib import Path
import json

import bpy
from mathutils import Matrix


JSON_PATH = Path(r"C:\sc6-export\chr001_clip_0123.json")


def matrix_from_rows(values):
    if len(values) != 16:
        raise ValueError(f"expected 16 matrix values, got {len(values)}")
    return Matrix(tuple(values[row * 4:(row + 1) * 4] for row in range(4)))


armature = bpy.context.object
if armature is None or armature.type != "ARMATURE":
    raise RuntimeError("select the target SC6 armature before running the script")

payload = json.loads(JSON_PATH.read_text(encoding="utf-8"))
if payload.get("schema") != "sc6-armature-matrices-v1":
    raise ValueError("unsupported animation schema")
if payload.get("matrix_space") != "blender_armature":
    raise ValueError("matrices must already be in Blender armature space")

samples = payload["frames"]
if not samples:
    raise ValueError("animation contains no frames")

keyed_names = set(samples[0]["bones"])
for sample in samples:
    if set(sample["bones"]) != keyed_names:
        raise ValueError("every frame must contain the same exported bones")
missing = sorted(keyed_names - set(armature.pose.bones.keys()))
if missing:
    raise KeyError(f"bones missing from selected armature: {missing}")

depth = {}
for bone in armature.data.bones:
    value = 0
    parent = bone.parent
    while parent is not None:
        value += 1
        parent = parent.parent
    depth[bone.name] = value
pose_bones = sorted(armature.pose.bones, key=lambda bone: depth[bone.name])

scene = bpy.context.scene
scene.render.fps = int(payload["fps"])
armature.animation_data_create()
action = bpy.data.actions.new(payload["action"])
armature.animation_data.action = action

for pose_bone in pose_bones:
    pose_bone.rotation_mode = "QUATERNION"

for sample in samples:
    frame = int(sample["frame"])
    scene.frame_set(frame)

    # Non-exported bones remain at rest and still follow animated parents.
    for pose_bone in pose_bones:
        pose_bone.matrix_basis.identity()

    # Parent-first assignment because the JSON matrices are armature-space.
    for pose_bone in pose_bones:
        values = sample["bones"].get(pose_bone.name)
        if values is not None:
            pose_bone.matrix = matrix_from_rows(values)

    for name in sorted(keyed_names):
        pose_bone = armature.pose.bones[name]
        pose_bone.keyframe_insert("location", frame=frame, group=name)
        pose_bone.keyframe_insert("rotation_quaternion", frame=frame, group=name)
        pose_bone.keyframe_insert("scale", frame=frame, group=name)

scene.frame_start = min(int(sample["frame"]) for sample in samples)
scene.frame_end = max(int(sample["frame"]) for sample in samples)
scene.frame_set(scene.frame_start)
print(f"Baked {action.name}: {len(samples)} frames, {len(keyed_names)} bones")
```

The script keys every integer frame, which preserves the sampled pose at 60 Hz.
If a later tool emits sparse keys, explicitly choose linear translation/scale
interpolation and quaternion-safe rotation interpolation rather than accepting
Bezier defaults.

## Runtime-capture route

Runtime capture is both the shortest high-fidelity exporter and the validation
oracle for an offline decoder.

Choose the hook point based on the target:

| Capture point | What it proves |
|---|---|
| Immediately after `LuxMotion_BlendKeyframeTransforms` | Raw selector output; useful while debugging the decoder |
| After `LuxBattleChara_SolveBonePose` / `LuxMoveVM_EvaluateBonePose` | Core resolved battle pose, hierarchy, and IK state at that stage |
| After `LuxSkeleton_UpdateBoneTransforms` | Later visible/collision skeleton state including additional constraints and secondary work |

Capture the matching rest matrices once, then record each desired bone's
model-space pose matrix at one sample per battle tick. Include the UE skeleton
bone index and resolved bone name in the capture. The game publishes a
collision-visible matrix bank, but array position alone is not a portable
Blender binding.

For deterministic capture, freeze or replay a known input sequence, record the
selected packed motion id and playback frame, and avoid mixing samples from
different ring-buffer generations.

## Verify the export

Use native runtime matrices as the acceptance test, not visual similarity.

1. Confirm the bank count, reserved dword, and every offset before decoding.
2. Confirm that aliased clip ids resolve to identical payload starts.
3. Decode frame 0, a non-zero frame inside an eight-frame group, a group
   boundary, and the final logical frame.
4. Check every quaternion is finite and close to unit length after decoding.
5. Check absent channels reproduce the correct merged and rescaled reference
   values instead of zero transforms.
6. Compare root, pelvis, one hand, one foot, and one auxiliary/weapon bone
   against captured model-space matrices at the same integer playback frames.
7. Compare deformation matrices after the deliberate axis/unit conversion;
   do not hide a transpose or scale error with a loose positional tolerance.
8. In Blender, scrub the first and final frame and ensure neither snaps to an
   unkeyed rest pose.

An offline MOT sample is acceptable when the selector output and intended
reference/hierarchy stages match. It is not a final-pose match if the remaining
error comes from deliberately omitted IK, retracking, overlays, or spring work.

## Current decoder coverage

A local audit of 31 extracted `chr*.mot` banks found 33,717 table slots. After
collapsing repeated offsets to range-bearing payloads, 16,157 distinct ranges
were tested. The current reference decoder accepted 16,028 clip headers and
decoded first/last compressed word streams for 15,821 of them.

This is **not** 15,821 complete Blender animations. It only demonstrates broad
coverage of the outer header and Huffman word stage. The remaining failures
include long-duration headers rejected by conservative heuristics, unresolved
group boundaries, and streams that exceed the currently inferred internal
region. Full-pose selector mapping, merged defaults, hierarchy, and runtime
comparison remain required.

All accepted clips in this corpus selected the default channel table; the
native bit-15 alternate path still has to be implemented and tested because it
exists in code even when the sampled files do not exercise it.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| Every clip begins with nonsense | Offset table read from `+0x04` | Skip the reserved dword and begin at `+0x08`. |
| One of several repeated offsets becomes empty | Immediate-next offset used as its end | Bound all aliases by the next **greater** distinct offset. |
| Model imports but `.mot` is invisible to FModel | `.mot` is not a UE `AnimSequence` | Extract it as a raw file and use the SC6 HgMotion decoder. |
| Animation is 100 times too large or small | Model and motion used different unit conversions | Reuse the model import's exact scale in matrix conversion `C`. |
| Ground plane and height are swapped | Lux axes were treated as UE/Blender axes | Apply `UE(X,Y,Z) = Lux(X,Z,Y) * 100`, then the model import's UE-to-Blender conversion. |
| Limbs bend correctly but hands/feet drift | IK/retracking/reference stages were omitted | Label it authored-only, or capture/reimplement the later native stages. |
| Bones twist although positions look close | Raw game matrices were assigned to Blender bones | Transfer the deformation through game and Blender bind matrices. |
| Root moves but the body stays in rest pose | Only selector `0x16` is decoded | Complete the selector stream, defaults, mapping, and hierarchy. |
| Final pose differs during hair/cloth motion | Capture happened before later skeleton updates | Capture after the stage whose result is actually needed. |

## Native evidence

| Function | Evidence used by this recipe |
|---|---|
| `LuxMoveVM_InitMotionPlayback @ 0x140300400` | Bank/clip packed-id split and the `+0x08` motion-offset table |
| `LuxMotion_DecodeHuffmanKeyframeData @ 0x1402E71E0` | Eight-frame groups and accumulated Huffman deltas |
| `LuxMotion_SampleKeyframeTransforms @ 0x1402E7780` | Frame-rate flags, current/next decode, clamping, and interpolation |
| `LuxMotion_BlendKeyframeTransforms @ 0x1402E79C0` | Selector streams, channel masks, special selectors, and local-transform output |
| `LuxBattleChara_SolveBonePose @ 0x1402EDB90` | Ordered MOT layers, reference/default data, hierarchy, spine solve, and IK |
| `LuxMoveVM_EvaluateBonePose @ 0x1402F0F20` | Active-motion application and nine signed logical-transform mappings |
| `LuxBattleChara_InitBoneRefPositions @ 0x1402EA810` | Reference vectors come from merged move-data entries, not `.mot` |
| `LuxBattleChara_RescaleBoneSizePositions @ 0x1402E9F90` | Body-profile scaling changes reference positions and IK lengths |
| `LuxSkeleton_UpdateBoneTransforms @ 0x14034B8D0` | Later blending, constraints, spring/collision work, and published skeleton state |

## Do we need a Blender add-on?

No for the first version. Keep the implementation in three testable layers:

```text
SC6 bank/clip parser + pose solver
              -> named armature-space matrices
              -> JSON or glTF
              -> Blender bake/import
```

Once the decoder passes runtime-matrix comparisons, wrapping it as a Blender
extension is modest UI work. Building the add-on first does not reduce the
reverse-engineering work and makes automated decoder tests harder to run.

## Related

- [On-disk battle data files](../sc6/on-disk-files.md#mot-motion-files)
- [Move System](../sc6/move-system.md)
- [Structures](../sc6/structures.md)
- [HorseMod motion-bank parser](https://github.com/FottenSC/HorseMod/blob/main/tools/moveset_parser/luxformats.py)
- [HorseMod HgMotion reference decoder](https://github.com/FottenSC/HorseMod/blob/main/tools/moveset_parser/hgmotion_reference.py)
