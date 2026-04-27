# Character Data

Runtime asset paths for character / style / move data.

## At a glance

- **Style id** — short per-character string (e.g. `001`, `006`). Reused across `RP_*`,
  `RegularThumbnail_*`, `DA_TraceColorPallet`, `DA_MoveListTable_<StyleId>`, etc.
- **Move-list display data**: pak-loaded `DA_MoveListTable_<StyleId>.uasset` →
  [`FLuxBattleMoveListTableRow`](move-system.md#fluxbattlemovelisttablerow-0x88-bytes).
  **Text only — no frame data.**
- **Move-list gameplay data**: native command-script bytecode in the move provider.
  See [Move System](move-system.md).
- **Anti-tamper status**: no gates confirmed; pak-loaded so disk edits need a pak
  injection workflow. Runtime edits via `BattleManager.ConfigTable` (`+0x50`) are safe.

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

## Editing safety

- **Pak-loaded DataTables** (above): no anti-tamper gates confirmed, but disk edits need
  a pak-injection workflow — UE4SS `HookProperty` won't help.
- **Runtime config** at `BattleManager+0x50` (`ConfigTable`): always safe — see the
  [DataTable path tree](battle-manager.md#lux-datatable-path-tree).
- **`ChangeBattleLife`** UFunction is the recommended path for per-player life scaling;
  prefer it over patching `WeaponAttackTypeTable`.
