# Character and Stage Selection Menus

How SC6 builds the character-select and map-select menu data, where those
choices land in battle setup, and what that means for adding more menu options.

All addresses are absolute (image base `0x140000000`).

## At a glance

The menus are not one monolithic native system. They are a set of small native
LuxDataTable builders plus Blueprint UI widgets:

| Menu layer | Native evidence | What it controls |
|---|---|---|
| Character-select roster | `BuildCharaSelectRosterTable @ 0x1405D3870` | Menu rows for playable style ids (`cid`) and display loc IDs. |
| Selected/decided battle setup defaults | `LuxBattleSetup_BuildSelectedCharaCodeDataTable @ 0x14057FB70`, `LuxBattleSetup_BuildDecidedCharaCodeDataTable @ 0x140590BD0` | Transient selected character, custom-character tab/index, selected color/weapon, and `SelectedStageCode` keys. |
| Normal stage list | `GetStageCodes_BuildMasterList @ 0x140640890`, `GetStageCodesIfAvailable_FilterByDLCChunks @ 0x1406409F0` | Stage-code list exposed to the stage picker and random stage pool. |
| Final battle launch | `ULuxUIBattleLauncher::Start @ 0x1405EEB50`, `ApplyBattleSettingDataTableToBattleManager @ 0x140594EB0` | Copies `StageSetting.StageCode` and player setup into `ALuxBattleManager.ConfigTable`. |
| Arcade/mission stage resolver | `GetStageCodeFromArcadeRegulationSetting @ 0x1405BB200` | Reads `StageCount` and returns a `VersusStage` from arcade regulation data. Not the normal map-select list. |

The important distinction is **menu options** vs **battle setup values**:

| Thing | Meaning |
|---|---|
| `SelectedStageCode` | Menu/battle-setup key used by setup tables. Defaults to `RND` in the selected table and `STG015_R` in the decided table. |
| `StageSetting.StageCode` | Final launch key consumed by the battle manager and stage preload path. This is the value to rewrite for a stage redirect. |
| `SelectedCreationTab_*` / `SelectedCreationCharaSelectedIndex_*` | Custom-character menu state. These select CAS tab/slot indices, not stages. |

## Character-Select Roster

`BuildCharaSelectRosterTable @ 0x1405D3870` builds a transient LuxDataTable of
`(display loc ID, cid)` pairs. It emits one header/filter row plus 28 playable
character rows.

The `cid` is the three-hex style id used by paths like `hdr<cid>.khd`,
`Content/Style/<cid>/`, and `ID_CMD_<cid>_*`. It is not the same thing as
`ELuxCharacter`, `ELuxFightStyle`, or the on-screen roster position.

The seed list is documented in detail on
[Character Data: BuildCharaSelectRosterTable](character-data.md#buildcharaselectrostertable-select-roster).

Direct native callers observed so far:

| Caller | Call site | Role |
|---|---:|---|
| `FUN_1405CDF70` | `0x1405CE099` | Builds a `LuxSEMPlayerMenuCompanionsListItem` menu data table. |
| `FUN_1405D3070` | `0x1405D324C` | Builds a player-menu weapon/list submenu using `LuxSEMPlayerMenuWeaponListItem`. |
| `FUN_1405D4E20` | `0x1405D4FEC` | Variant of the player-menu weapon/list submenu builder with extra command/delete parameters. |
| `FUN_140C84E60` | `0x140C84E81` | UFunction/exec-style wrapper that commits the roster table directly. |

Modding implication: adding a row here can make a character appear in this menu
data, but it does **not** create a full playable character by itself. The battle
side still needs a valid style id, move provider data, profile/thumbnail/UI data,
weapons, availability, and whatever downstream setup expects for that mode.

## Selected Battle-Setup Keys

`LuxBattleSetup_BuildSelectedCharaCodeDataTable @ 0x14057FB70` and
`LuxBattleSetup_BuildDecidedCharaCodeDataTable @ 0x140590BD0` build the transient
selection-state tables used by `LuxBattleSetup`.

Both builders emit the same key schema:

| Key | Role |
|---|---|
| `SelectedCharaCode_L` / `_R` | Current highlighted character/style id for left/right player. |
| `DecidedCharaCode_L` / `_R` | Confirmed character/style id for left/right player. |
| `SelectedStageCode` | Selected stage code before launch. |
| `SelectedCharaCodeWithCasual` | Extra character-code field used by casual/custom-character paths. |
| `SelectedCreationTab_L` / `_R` | Custom-character tab for each side. |
| `SelectedCreationCharaSelectedIndex_L` / `_R` | Custom-character slot/index for each side. |
| `SelectedColor_L` / `_R` | Costume color selection. |
| `SelectedWeapon_L` / `_R` | Weapon selection value; initialized as null in these builders. |
| `PrevPlayerSide` | Previous side marker, initialized to `UNK`. |

Default values differ:

| Builder | Stage default | Character defaults |
|---|---|---|
| `LuxBattleSetup_BuildSelectedCharaCodeDataTable` | `RND` | left `00C`, right `062` |
| `LuxBattleSetup_BuildDecidedCharaCodeDataTable` | `STG015_R` | left `00C`, right `062` |

These are LuxDataTable values, not reflected UObject properties. A mod that wants
to redirect the selected stage can hook the menu setter, a LuxDataTable write, or
the later battle-launch copy and rewrite `SelectedStageCode` / `StageSetting.StageCode`.

## Normal Stage Select

The stage picker is driven by stage-code lists rather than a hardcoded native UI
array.

| Function | Role |
|---|---|
| `GetStageCodes_BuildMasterList @ 0x140640890` | Builds the master stage-code list from `g_LuxStage_MasterEnumStringTable`, filtering `_T` anomaly variants out of the random pool. |
| `GetStageCodesIfAvailable_FilterByDLCChunks @ 0x1406409F0` | Filters the master list by DLC/chunk availability. |
| `IsValidStageCodeStr_LookupInMasterEnum @ 0x140647230` | Validates a stage code against the master enum table. |
| `ResolveStageCodeToAssetPath @ 0x140641840` | Converts a stage code to a `/Game/Stage/...` or DLC asset path for Blueprint/helper callers. |
| `ULuxUIBattleLauncher::GetBattleStageCode @ 0x1405B0C60` | Reads `StageSetting.StageCode`, defaulting to `STG001` if missing. |

The normal native stage load path is more permissive than the UI. As documented
in [Stage System: Adding a wholly new stage](stage-system.md#adding-a-wholly-new-stage),
the battle load path ultimately uses the string in `StageSetting.StageCode` as a
map primary asset name. The normal UI, however, can still call validation helpers
that expect the code to exist in the master enum.

Practical modding paths:

| Goal | Required hook/data work |
|---|---|
| Replace one stock stage | No menu work. Replace the stock `.umap` / data assets for an existing code. |
| Hidden custom stage redirect | Rewrite `StageSetting.StageCode` after the menu picks, before `ApplyBattleSettingDataTableToBattleManager` kicks preload. |
| Custom stage in normal stage-select UI | Append a row to `g_LuxStage_MasterEnumStringTable` and inject/add a picker row in the Blueprint/menu data. |
| Custom stage in random pool | Append a substring-safe code to the master enum; `GetStageCodes_BuildMasterList` and DLC filtering will then see it. |

Safe custom stage codes should avoid the DLC-routing substrings documented in
[Stage System: Stage code to path resolution](stage-system.md#stage-code-path-resolution):
`014`, `_V`, `016`, `006_R`, `011_R`, `015`, `017`, and `018`.

## Arcade And Mission Stage Selection

Not every stage choice comes from the normal stage picker.

`GetStageCodeFromArcadeRegulationSetting @ 0x1405BB200` is exposed through the
reflected wrapper `execGetStageCodeFromArcadeRegulationSetting @ 0x140C81270`.
It reads an arcade regulation LuxDataTable and returns a stage code:

1. Read `Difficulty` from the input setting table.
2. Resolve the arcade regulation table through the move provider.
3. Read `StageCount` from the input setting table.
4. Index `BattleSettings[StageCount].VersusStage`.
5. If the row/string is missing or `CheckIsStageChunkAvailable` rejects the code,
   return `STG001`.

Adjacent helpers:

| Function | Role |
|---|---|
| `MakeEnemySettingFromArcadeRegulationSetting @ 0x1405C4190` | Builds enemy AI/chara settings from the same arcade regulation table. It consumes `StageCount` and `VersusCharas`, but does not select stages. |
| `MakeRandomMission_BuildBattleSettingTable @ 0x1405C8A20` | Worker for reflected `MakeRandomMission`; copies `StageSetting.StageCode`, misspelled `StageSetting.Anomary`, and `StageSetting.ExtraParam` into a mission/battle-setting payload. |

These are useful if you are changing arcade, mission, or random-battle flows.
They are not the normal versus stage-select option list.

## Custom-Character Submenu As A Stage Selector

The custom-character submenu does not natively select stages. The selection-state
keys it owns are custom-character keys:

```text
SelectedCreationTab_L
SelectedCreationTab_R
SelectedCreationCharaSelectedIndex_L
SelectedCreationCharaSelectedIndex_R
SelectedCharaCodeWithCasual
```

Those fields are independent from `SelectedStageCode` and `StageSetting.StageCode`.

Could a mod use that submenu to select modded stages? **Yes, as a UI hack, not as
an existing native feature.** The cleanest version is:

1. Let the custom-character submenu supply a tab/index choice.
2. Hook the menu decision or battle-launch path.
3. Map `(tab, selectedIndex)` to a custom stage code such as `STG_MOD_A`.
4. Rewrite `StageSetting.StageCode` before `ULuxUIBattleLauncher::Start` or before
   `ApplyBattleSettingDataTableToBattleManager @ 0x140594EB0` starts preloading.

This avoids needing the normal stage picker to display the custom code. It also
means the submenu is no longer semantically selecting only custom characters, so
the mod must prevent user confusion and avoid breaking any code that expects the
same tab/index to mean a real creation slot.

For a real stage menu, use a dedicated Blueprint/UI hook instead of overloading
the custom-character submenu.

## Can We Add More Options?

Yes, but the cost depends on which menu you mean.

| Menu | Feasibility | Hard part |
|---|---|---|
| Character select | Possible to add menu rows by patching/hooking the roster table, but not enough for a complete new character. | Supplying a valid style id and all downstream character data. |
| Normal stage select | Feasible. The stage load path is string-based and can load mounted map primary assets. | Getting the Blueprint picker/master enum to accept and display the new code. |
| Arcade/mission stage lists | Feasible by editing/hooking the regulation LuxDataTable data or the resolver helpers. | Keeping DLC/chunk gating and mission assumptions valid. |
| Custom-character submenu stage picker | Feasible as a mod-controlled redirect UI. | It is not native stage-selection state; you must map the custom-character index to `StageSetting.StageCode` yourself. |

For custom stages, the least invasive testing path remains a late rewrite of
`StageSetting.StageCode`. The more polished path is master-enum append plus UI
picker injection.

## Key Native Functions

| Function | Address | Menu relevance |
|---|---:|---|
| `GetStageCodeFromArcadeRegulationSetting` | `0x1405BB200` | Reads `StageCount` and returns the arcade/mission `VersusStage`, falling back to `STG001`. |
| `MakeEnemySettingFromArcadeRegulationSetting` | `0x1405C4190` | Consumes the same arcade regulation row and builds enemy character/AI setup. |
| `MakeRandomMission_BuildBattleSettingTable` | `0x1405C8A20` | Worker for `MakeRandomMission`; copies `StageSetting.StageCode` into the mission battle-setting payload. |
| `execGetStageCodeFromArcadeRegulationSetting` | `0x140C81270` | Reflected UFunction wrapper for arcade/mission stage-code lookup. |
| `execMakeEnemySettingFromArcadeRegulationSetting` | `0x140C82840` | Reflected UFunction wrapper for arcade enemy-setting construction. |
| `execMakeRandomMission` | `0x140C83520` | Reflected UFunction wrapper for random mission battle-setting construction. |
