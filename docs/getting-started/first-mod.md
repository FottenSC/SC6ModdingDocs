# Your First Mod

Goal: get a Lua mod that prints a line to the UE4SS console every time the game reaches the main menu.

## 1. Scaffold the mod folder

Inside `…\Win64\Mods\`, create:

```
Mods/
└── HelloSC6/
    ├── enabled.txt          (empty file — presence = enabled)
    └── Scripts/
        └── main.lua
```

## 2. Enable it in `mods.txt`

Open `Mods\mods.txt` and add a line:

```
HelloSC6 : 1
```

The `1` means enabled.

## 3. Write the Lua

=== "main.lua"

    ```lua
    -- Mods/HelloSC6/Scripts/main.lua
    local ModName = "HelloSC6"

    print(("[%s] loaded"):format(ModName))

    -- Fires once the first UWorld is ready.
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(PC)
        print(("[%s] PlayerController ClientRestart"):format(ModName))
    end)
    ```

## 4. Launch and verify

1. Start SoulCalibur VI.
2. Watch the UE4SS console — you should see `[HelloSC6] loaded` early, then the `ClientRestart` line once you're past the splash/title.

!!! tip "Hot reload"
    UE4SS can re-run Lua mods without restarting the game. The exact hotkey is configurable in
    `UE4SS-settings.ini` (look for `[Hotkeys]`) and has changed between releases — check your
    copy's ini rather than assuming a default.

## Next

- Learn the API: [UE4SS Framework → Lua API Overview](../ue4ss/lua-api.md)
- Hook more events: [UE4SS Framework → Hooks & Events](../ue4ss/hooks.md)
