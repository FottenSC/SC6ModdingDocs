# Character Data

Runtime asset paths for character / style / move data.

## At a glance

- **Style id** — short per-character string (e.g. `001`, `006`). Also called `cid`.
  Reused across `RP_*`, `RegularThumbnail_*`, `DA_TraceColorPallet`,
  `DA_MoveListTable_<StyleId>`, etc. Id↔name table: [Character roster](#character-roster).
- **Move-list display data**: pak-loaded `DA_MoveListTable_<StyleId>.uasset` →
  [`FLuxBattleMoveListTableRow`](move-system.md#fluxbattlemovelisttablerow-0x88-bytes).
  Localised text + per-hit class / effect tags — **no frame data**; see
  [Move-list text and metadata](#move-list-text-and-metadata).
- **Move-list gameplay data**: native command-script bytecode in the move provider.
  See [Move System](move-system.md).
- **On-disk binary files**: `.khd` move bank + `.mot` motion table + `.dtp` AI table
  + `.dat` hit-volume streams. File-to-struct map: [On-disk Battle Files](on-disk-files.md).
- **Anti-tamper status**: no gates confirmed; pak-loaded so disk edits need a pak
  injection workflow. Runtime edits via `BattleManager.ConfigTable` (`+0x50`) are safe.

## Character roster

The **style id** (`cid` — a 3-hex-digit string) keys every per-character
asset: `Battle/hdr/hdr<cid>.khd`, `Content/Style/<cid>/`, the move-list
localization keys `ID_CMD_<cid>_*`, and the name key `ID_CMN_Char_D_<cid>`.
It is **not** the character-select order, and **not** the `ELuxFightStyle`
enum used by leaderboard metadata — that is a separate numbering (see
[Leaderboards: character style IDs](leaderboards.md#character-style-ids)).

| cid | Character | Source |
|-----|-----------|--------|
| `001` | Mitsurugi | base |
| `002` | Seong Mi-na | base |
| `003` | Taki | base |
| `004` | Maxi | base |
| `005` | Voldo | base |
| `006` | Sophitia | base |
| `007` | Siegfried | base |
| `009` | Hwang | DLC13 |
| `00b` | Ivy | base |
| `00c` | Kilik | base |
| `00d` | Xianghua | base |
| `00f` | Yoshimitsu | base |
| `011` | Nightmare | base |
| `012` | Astaroth | base |
| `013` | Inferno | boss — not in the select roster |
| `014` | Cervantes | base |
| `015` | Raphael | base |
| `016` | Talim | base |
| `017` | Cassandra | DLC6 |
| `022` | Setsuka | DLC11 |
| `023` | Tira | base |
| `024` | Zasalamel | base |
| `028` | Hilde | DLC7 |
| `030` | Amy | DLC4 |
| `060` | 2B | DLC2 |
| `061` | Haohmaru | DLC9 |
| `062` | Grøh | base |
| `064` | Azwel | base |
| `065` | Geralt | base |

> Source: select-roster rows from `BuildCharaSelectRosterTable @ 0x1405D3870`
> (the exe's own name-key↔cid roster), cross-checked against the
> `ID_CMN_Char_D_<cid>` localization keys. `013` is a known non-select
> boss / AI slot from localization and runtime-condition strings; it is not
> emitted by `BuildCharaSelectRosterTable`.

- `base` = data ships on-disc with plain `ID_CMN_Char_D_<cid>` keys;
  `DLC<N>` = shipped in a DLC pak with `ID_DLC<N>_*` keys.
- `023` Tira ships on-disc but the character itself is purchase-gated.
- The DLC7/9/11 cid↔name pairings (Hilde / Haohmaru / Setsuka) were
  resolved from per-character moveset data; `BuildCharaSelectRosterTable`
  alone leaves those three unlabelled.
- cids outside this list (`000` / `0FF` shared-motion slots, the
  Create-a-Soul slot, etc.) are not playable roster characters.

## `BuildCharaSelectRosterTable` select roster

`BuildCharaSelectRosterTable @ 0x1405D3870` builds the transient
character-select roster `LuxDataTable`. Each row is a `(locTextId, cid)`
pair. The `cid` is the 3-hex style id used by `hdr<cid>.khd`,
`Content/Style/<cid>/`, and `ID_CMD_<cid>_*` move-list keys. The function
does **not** emit numeric `ELuxCharacter` / `ELuxFightStyle` ids; keep those
separate from cids.

The literal seed table is 29 rows: one menu/header row plus 28 character rows.
If a `MoveProvider` is available, the function then keeps the header row and
intersects the character rows with `FUN_140638290 @ 0x140638290`, the shared
runtime-available cid filter. If no game-flow / world context is available,
the helper copies the input list and the literal seed rows remain unfiltered.

| Seed row | locTextId | cid | Character / meaning | Notes |
|---:|---|---|---|---|
| 0 | `ID_SYS_SEM_MENU_0207` | `ALL` | Menu header / all filter | Not a fighter row |
| 1 | `ID_CMN_Char_D_001` | `001` | Mitsurugi | base |
| 2 | `ID_CMN_Char_D_002` | `002` | Seong Mi-na | base |
| 3 | `ID_CMN_Char_D_003` | `003` | Taki | base |
| 4 | `ID_CMN_Char_D_004` | `004` | Maxi | base |
| 5 | `ID_CMN_Char_D_005` | `005` | Voldo | base |
| 6 | `ID_CMN_Char_D_006` | `006` | Sophitia | base |
| 7 | `ID_CMN_Char_D_007` | `007` | Siegfried | base |
| 8 | `ID_CMN_Char_D_00B` | `00b` | Ivy | base |
| 9 | `ID_CMN_Char_D_00C` | `00c` | Kilik | base |
| 10 | `ID_CMN_Char_D_00D` | `00d` | Xianghua | base |
| 11 | `ID_CMN_Char_D_00F` | `00f` | Yoshimitsu | base |
| 12 | `ID_CMN_Char_D_011` | `011` | Nightmare | base |
| 13 | `ID_CMN_Char_D_012` | `012` | Astaroth | base |
| 14 | `ID_CMN_Char_D_014` | `014` | Cervantes | base |
| 15 | `ID_CMN_Char_D_015` | `015` | Raphael | base |
| 16 | `ID_CMN_Char_D_016` | `016` | Talim | base |
| 17 | `ID_CMN_Char_D_023` | `023` | Tira | on-disc, purchase-gated |
| 18 | `ID_CMN_Char_D_024` | `024` | Zasalamel | base |
| 19 | `ID_CMN_Char_D_062` | `062` | Grøh | base |
| 20 | `ID_CMN_Char_D_064` | `064` | Azwel | base |
| 21 | `ID_CMN_Char_D_065` | `065` | Geralt | base / guest |
| 22 | `ID_DLC2_CMN_Char_D_060` | `060` | 2B | DLC2 |
| 23 | `ID_DLC4_CMN_Char_D_030` | `030` | Amy | DLC4 |
| 24 | `ID_DLC6_CMN_Char_D_017` | `017` | Cassandra | DLC6 |
| 25 | `ID_DLC7_CMN_Char_D_028` | `028` | Hilde | DLC7 |
| 26 | `ID_DLC9_CMN_Char_D_061` | `061` | Haohmaru | DLC9 |
| 27 | `ID_DLC11_CMN_Char_D_022` | `022` | Setsuka | DLC11 |
| 28 | `ID_DLC13_CMN_Char_D_009` | `009` | Hwang | DLC13 |

The cid seed list, in emitted order, is:

```text
001, 002, 003, 004, 005, 006, 007, 00b, 00c, 00d, 00f, 011,
012, 014, 015, 016, 023, 024, 062, 064, 065, 060, 030, 017,
028, 061, 022, 009
```

Excluded by construction:

| cid / id | Meaning | Evidence |
|---|---|---|
| `013` | Inferno / boss / AI slot | `ID_CMN_Char_D_013` and `RUNTIME_CHAR_013_AVAILABLE` exist elsewhere, but the select roster seed skips it. |
| `066` | non-select runtime style id | `RUNTIME_CHAR_066_AVAILABLE` and `ID_CMN_Char_E_066` exist, but there is no select-roster display row. |
| `000`, `0FF` | shared/common motion slots | on-disk pseudo-style ids, not character-select rows. |
| `ELuxCharacter::ELC_EDGEMASTER`, `ELuxFightStyle::EFS_EDGEMASTER` | enum-only Edgemaster ids | enum strings exist, but no cid row is seeded here. |

Direct code callers of the table builder:

| Caller | Call site | Observed role |
|---|---:|---|
| `FUN_1405CDF70` | `0x1405CE099` | Builds a `LuxSEMPlayerMenuCompanionsListItem` menu data table. |
| `FUN_1405D3070` | `0x1405D324C` | Builds a player-menu weapon/list submenu using `LuxSEMPlayerMenuWeaponListItem`. |
| `FUN_1405D4E20` | `0x1405D4FEC` | Variant of the player-menu weapon/list submenu builder with extra command/delete parameters. |
| `FUN_140C84E60` | `0x140C84E81` | UFunction/exec-style wrapper that commits the roster table directly. |

No direct battle-launch / battle-setup caller xrefs this table. Treat it as UI
menu data, not as the authoritative battle setup whitelist. The validity filter
flows the other direction: `BuildCharaSelectRosterTable` consumes the shared
runtime-available cid helper to prune menu rows, while battle setup uses its own
launch-data path described in [Battle Manager](battle-manager.md#battle-launcher-startup-path).

## DataTable asset paths

Style data is keyed on the style id string. Paths are `printf`-formatted in `.rdata`:

| Purpose | Path format | Row struct |
|---|---|---|
| Move list per style | `/Game/Style/<StyleId>/DA_MoveListTable_<StyleId>.DA_MoveListTable_<StyleId>` | `FLuxBattleMoveListTableRow` |
| Move categories per style | `/Game/Style/<StyleId>/DA_MoveCategoryTable_<StyleId>.DA_MoveCategoryTable_<StyleId>` | — |
| Global weapon-attack classification | `/Game/Common/DataAsset/WeaponAttackTypeTable.WeaponAttackTypeTable` | `FLuxBattleCharaWeaponAttackTypeTable` |
| Regular profile (character meta) | `/Game/Chara/RegularProfile/RP_<Id>.RP_<Id>` | — |
| Regular thumbnail | `/Game/Chara/Thumbnail/RegularThumbnail_<Id>.RegularThumbnail_<Id>` | — |
| Trace color palette per chara | `/Game/Chara/<Id>/VFX/Trace/DA_TraceColorPallet.DA_TraceColorPallet` | — |
| Battle chara color | `/Game/UI/GameFlow/GameScenes/BattleSetup/DB_BattleCharaColorData.DB_BattleCharaColorData` | — |

> Source: format strings at `0x143307270`, `0x1433071D0`, `0x143276B20`, `0x1432F3950`,
> `0x1433008A0`, `0x14335B320`, `0x143300EE0`.

## Move-list text and metadata

`DA_MoveListTable_<cid>` is the UE4 DataTable behind the in-game move
list — one row per move, keyed `"1"`..`"N"`, where the key number is the
move's `MoveListID`. Row struct:
[`FLuxBattleMoveListTableRow`](move-system.md#fluxbattlemovelisttablerow-0x88-bytes).

Its six `*TextID` fields are **localization key ids**, not display text.
They resolve through `Game.archive` / `Game.locres` using this convention:

> `ID_CMD_<cid>_<NNNN>_<field>`, where **`NNNN` = `MoveListID × 10`**,
> zero-padded to 4 digits. e.g. Mitsurugi `MoveListID 16` → key prefix
> `ID_CMD_001_0160_` → `_name` = "Heaven Cannon", `_command` = "3B".

Two row fields carry move metadata **directly** (not via localization):

| Field | Content |
|-------|---------|
| `AttributeTag` | Per-**hit** attack-class sequence, dot-separated. Tokens `H` / `M` / `L` / `SM` / `SL` (High / Mid / Low / Special-Mid / Special-Low). `"M.M.M"` = a 3-hit move, all mid. This is the game's own per-hit class — a single `.khd` attack cell cannot express a multi-hit sequence. |
| `EffectTag` | Move-property tokens, dot-separated: `LH` Lethal Hit · `BA` Break Attack · `GI` Guard Impact · `UA` Unblockable · `RE` Reversal Edge · `TH` Throw · `SC` Soul Charge · `SS` Stance Shift · `SGF`/`SGH`/`SGQ` Soul-Gauge requirement (Full/Half/Quarter). |

For the question "what class and properties does the game assign this
move", `AttributeTag` + `EffectTag` are the authoritative source. Deriving
the class from a single resolved attack cell's `wAttackFlags` is
unreliable — see [Hitbox System: Attack flags](hitbox-system.md#attack-flags).

Companion DataTables: `DA_MovePlayData_<cid>` enumerates the moves shown
in the list and joins each to its `MoveListID`; `DA_MoveCategoryTable_<cid>`
maps each move to one of the 11 movelist categories.

## `ELuxWeaponAttackType`

Used by the `WeaponAttackTypeTable` row to classify each attack's sound / VFX set:

| Value | Name |
|---|---|
| — | `WAT_SlashSharp` |
| — | `WAT_SlashSlightlySharp` |
| — | `WAT_SlashHeavy` |
| — | `WAT_SlightlySmash` |
| — | `WAT_Smash` |

(Numeric ordering not confirmed — strings live at `0x143273658`–`0x143273B28`.)

## Move dispatch path

`ALuxBattleManager::PlayMove(PlayerIndex, MoveTableIndex, MoveIndex)` walks:

```text
chara    = BM.PlayerCharas[PlayerIndex]              // BM +0x390 [PlayerIndex]
table    = chara.MoveTables[MoveTableIndex]          // FMoveTable, 0x10 bytes
entry    = &table.data[MoveIndex]                    // MoveEntry*, 0x18 bytes stride
PlayMoveDirect(BM, PlayerIndex, &entry->def)         // = &entry + 0x8 (MoveDef* slot)
```

The `entry + 0x8` arithmetic in `PlayMove_Impl` disassembly is just `&entry->def` —
`MoveId id` occupies the first 8 bytes of each `MoveEntry`, `MoveDef* def` is at `+0x8`.

See [Battle Manager](battle-manager.md) for the rest of the dispatch pipeline.

## Command-input table

How the engine matches a motion input (`236A`, `22B`, a stance string) to
a move each frame — separate from both the move-list display data and the
per-slot move bytecode. Most command / motion-input moves are recognised
here, not in slot bytecode.

A 13-pointer "command directory" is bound to **both** chara slots by
`LuxBattle_BindCommandDirectoryToCharaSlots @ 0x1402DA5B0` (a UE4 UFunction,
sourced from the per-character `CP_<cid>.uasset`). Directory entry `[3]` is
the command table; its pointer lands at `chara+0x971D8`.

The table is the same offset-table container as `.mot` / `.dtp` files:

```c
struct FLuxCommandTableHeader {   // 12 bytes, at *(chara+0x971D8)
    uint entry_count;
    uint entries_offset;          // -> FLuxCommandEntry[]
    uint motion_records_offset;   // -> FLuxCommandMotionRecord[]
};
struct FLuxCommandEntry {         // 8 bytes
    ushort motion_record_index;
    ushort step_count;            // motion records chained for this command
    ushort field4, field6;        // not read by the matcher
};
struct FLuxCommandMotionRecord {  // 8 bytes
    short  outer_iter_count;      // input-history steps to scan
    short  alt_iter_count;
    ushort test_code_a;           // input gate — must pass
    ushort test_code_b;           // input gate — must pass
};
```

`test_code` is a 16-bit gate — the high nibble selects which input-history
field to test, the low 12 bits are the operand. The input-history ring is
at `chara+0x2190` (stride `0xC`). Matched by
`LuxBattle_EvaluateMoveTransitionConditions @ 0x140312F80`.

The directory pointer is **shared** by both fighters; per-character
routing is a `ushort` remap array at `chara+0x331A` that translates a
generic command id into this character's table index before lookup.

> Source: full layout in the `LuxBattle_BindCommandDirectoryToCharaSlots`
> plate comment.

## Editing safety

- **Pak-loaded DataTables** (above): no anti-tamper gates confirmed, but disk edits need
  a pak-injection workflow — UE4SS `HookProperty` won't help.
- **Runtime config** at `BattleManager+0x50` (`ConfigTable`): always safe — see the
  [DataTable path tree](battle-manager.md#lux-datatable-path-tree).
- **`ChangeBattleLife`** UFunction is the recommended path for per-player life scaling;
  prefer it over patching `WeaponAttackTypeTable`.
