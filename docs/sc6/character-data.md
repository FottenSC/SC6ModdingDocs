# Character Data

Where the game actually loads character / style / move data from at runtime.

## DataTable asset paths

Every style (= character fighting moveset) is looked up via two parallel DataTables
keyed on the style id string. The paths are `printf`-formatted in `.rdata`:

| Purpose | Path format | Row struct |
|---|---|---|
| Move list per style | `/Game/Style/<StyleId>/DA_MoveListTable_<StyleId>.DA_MoveListTable_<StyleId>` | `FLuxBattleMoveListTableRow` |
| Move categories per style | `/Game/Style/<StyleId>/DA_MoveCategoryTable_<StyleId>.DA_MoveCategoryTable_<StyleId>` | — |
| Global weapon-attack classification | `/Game/Common/DataAsset/WeaponAttackTypeTable.WeaponAttackTypeTable` | `FLuxBattleCharaWeaponAttackTypeTable` |
| Regular profile (character meta) | `/Game/Chara/RegularProfile/RP_<Id>.RP_<Id>` | — |
| Regular thumbnail | `/Game/Chara/Thumbnail/RegularThumbnail_<Id>.RegularThumbnail_<Id>` | — |
| Trace color palette per chara | `/Game/Chara/<Id>/VFX/Trace/DA_TraceColorPallet.DA_TraceColorPallet` | — |
| Battle chara color | `/Game/UI/GameFlow/GameScenes/BattleSetup/DB_BattleCharaColorData.DB_BattleCharaColorData` | — |

> source: format strings at `0x143307270`, `0x1433071D0`, `0x143276B20`, `0x1432F3950`,
> `0x1433008A0`, `0x14335B320`, `0x143300EE0`.

The `<StyleId>` / `<Id>` placeholder is a short per-character string (e.g. `001`,
`006`). The same id is re-used across the RegularProfile / Thumbnail / Trace
palette lookups.

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

## Move dispatch runtime path

`ALuxBattleManager::PlayMove(PlayerIndex, MoveTableIndex, MoveIndex)` walks:

```text
chara    = BM.PlayerCharas[PlayerIndex]
table    = chara.MoveTables[MoveTableIndex]          // FMoveTable, 0x10 bytes
entry    = table[MoveIndex]                          // MoveEntry, 0x18 bytes
def      = entry.def                                 // -> FMoveDef*
PlayMoveDirect(BM, PlayerIndex, def)                 // queues on MoveCommandPlayer
```

The `MoveEntry` indexing inside a `FMoveTable` starts at `+0x8` of the entry's
backing struct (that's where `def` sits). See
[Battle Manager & DataTable Config Tree](battle-manager.md) for full details.

## Safe-to-edit vs anti-tamper

!!! warning "Not yet reversed"
    No anti-tamper gates have been confirmed on any of the above DataTables, but
    they are loaded at startup from cooked pak chunks — so **editing them on disk
    requires a pak-injection workflow**, not UE4SS `HookProperty`. Runtime edits
    via `BattleManager.ConfigTable` (at `+0x50`) are always safe: they're live
    config, not pak content.

    The `PlayerParam.Gauge.LifeInit` / `LifeMax` write path (see
    `ChangeBattleLife_Impl`) is explicitly exposed as a UFunction. If you need
    per-player life scaling for a mod, prefer that over patching the
    `WeaponAttackTypeTable`.
