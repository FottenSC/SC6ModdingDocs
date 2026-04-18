# Installing UE4SS into SoulCalibur VI

!!! info "Stub page"
    This page is a stub. Expand it with exact folder names, version notes, and troubleshooting
    as the project matures. See [Contributing](../contributing.md).

## 1. Download UE4SS

Grab the latest **zDEV** or release zip from the [UE4SS releases page](https://github.com/UE4SS-RE/RE-UE4SS/releases).

## 2. Locate the game's `Win64` folder

The default Steam path is:

```
C:\Program Files (x86)\Steam\steamapps\common\SOULCALIBUR VI\SoulcaliburVI\Binaries\Win64\
```

## 3. Extract UE4SS

Extract the contents of the zip **into that `Win64` folder**, so the following files sit next to the game's `.exe`:

- `dwmapi.dll` (the proxy loader)
- `UE4SS.dll`
- `UE4SS-settings.ini`
- `Mods/` folder

## 4. First launch

Launch the game. On first load you should see:

- A console window titled **UE4SS**
- A `UE4SS.log` file next to the dll
- Any default mods (e.g. `BPModLoaderMod`, `shared`) listed as *enabled*

## Troubleshooting

- **No console appears** — ensure `GuiConsoleEnabled = 1` in `UE4SS-settings.ini`.
- **Game crashes on boot** — try the non-dev build of UE4SS; some AOBs (array-of-bytes scans) can miss on a new game patch.
- **DLL not loading** — verify the proxy DLL name matches what the game loads; `dwmapi.dll` is the usual default.

Next: [Your First Mod](first-mod.md).
