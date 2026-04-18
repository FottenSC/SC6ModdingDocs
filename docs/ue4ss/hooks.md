# Hooks & Events

UE4SS lets Lua intercept engine calls at the UFunction level.

## `RegisterHook`

```lua
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(PC)
    -- runs before the original
    print("ClientRestart fired")
end)
```

The callback receives the UObject arguments in order. Return values can be read via the hook API
on post-call hooks (see [UE4SS docs](https://docs.ue4ss.com/)).

## `NotifyOnNewObject`

```lua
NotifyOnNewObject("/Script/Engine.PlayerController", function(PC)
    print("new PlayerController: " .. PC:GetFullName())
end)
```

## Threading

Most property access must happen on the game thread. Wrap work from async callbacks:

```lua
ExecuteInGameThread(function()
    -- safe to touch UObjects here
end)
```

!!! warning "AOB drift across game patches"
    When SC6 is patched, UE4SS may need refreshed AOB signatures for its core scan. If hooks stop firing
    after a patch, update UE4SS before debugging your script.
