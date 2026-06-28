# Recipe: DotVanisher spectator timeout grace

**Goal**: understand and reproduce the DotVanisher fix for false spectator
disconnects during slow online match loads.

**Requires**: SoulCalibur VI on Steam, UE4SS, PolyHook 2 through the UE4SS C++
mod toolchain, and the verified SC6 Steam executable build targeted by the
mod.

DotVanisher is a standalone UE4SS C++ DLL. It is not HorseMod, does not depend
on HorseMod, and does not install any HorseMod hook stack. The HorseMod work is
only relevant as the reverse-engineering investigation that identified the host
spectator timeout path.

## What problem it fixes

SC6 lets other lobby members watch a match as spectators. During the transition
from lobby to battle, the host tracks pending watch spectators while the match
assets load. The player match can still be healthy, but the host-side watch
queue has its own timeout. On slow storage, slow CPUs, or heavier stages, that
timer can expire before the spectator finishes the load. When it expires,
vanilla SC6 performs watch-end cleanup and spectators get kicked out of the
load, even though the two players continue normally.

DotVanisher does not make loading faster. It gives the host watch queue more
time. While the host has a small, valid number of pending spectators, the mod
keeps the vanilla watch timeout timer from accumulating for up to 90 seconds.
After that bounded grace window, it stops touching the timer and the original
game cleanup is allowed to run.

## Targeted vanilla path

The single hook target is:

```text
HandleHostTickWatchEventQueues @ SoulcaliburVI.exe+0x2E613A0
```

The mod treats the first argument as a host watch/event state object and uses
three verified fields:

| Offset | Type | Meaning |
|---:|---|---|
| `+0xB0` | pointer | Pending watch spectator list pointer. |
| `+0xB8` | `int64` | Pending watch spectator count. |
| `+0xC0` | `float` | Host watch timeout timer. |

The detoured function signature in the mod is:

```cpp
using OriginalFn = bool(__fastcall*)(uint8_t* pHostSysState, float flDeltaSeconds);
```

DotVanisher runs before the original tick body, optionally adjusts
`pHostSysState+0xC0`, then forwards to the original trampoline.

## Core constants

The behavior is intentionally narrow and build-pinned:

```cpp
constexpr uintptr_t kHandleHostTickWatchEventQueuesRva = 0x2E613A0;
constexpr ptrdiff_t kWatchListPointerOffset = 0xB0;
constexpr ptrdiff_t kWatchCountOffset = 0xB8;
constexpr ptrdiff_t kWatchTimeoutTimerOffset = 0xC0;
constexpr int64_t kMaxReasonableWatchCount = 16;
constexpr uint64_t kGraceMs = 90'000;
constexpr float kMaxDeltaCompensationSeconds = 120.0f;
```

The `16` spectator-count ceiling is a sanity guard, not a lobby feature limit
claim. If the count is negative or implausibly large, the mod assumes the
structure interpretation is wrong for this call and leaves vanilla behavior
untouched.

## Hook installation

UE4SS loads the mod and calls `DotVanisher::Mod::on_unreal_init()`. From there:

1. `GetModuleHandleW(L"SoulcaliburVI.exe")` resolves the game image base.
2. The hook target is computed as `image_base + 0x2E613A0`.
3. The mod verifies the game binary before installing the detour.
4. `PLH::x64Detour` installs an entry detour and stores the trampoline.
5. Future calls to the host watch tick enter `WatchTimeoutHook::detour`.

The binary verification is deliberately strict:

| Check | Purpose |
|---|---|
| `SoulcaliburVI.exe` file size equals `71,737,344` bytes | Rejects obvious wrong builds. |
| Full executable SHA-256 matches the expected hash | Rejects unsupported patch levels or edited binaries. |
| First 32 target-function bytes match the expected prologue | Rejects hook conflicts or unexpected code layout at the exact target. |

The v0.1.0 guard values are:

```text
exe_sha256 =
  f8904e4b04bca3b47bc52a683f6190365d2eb89ee8f44f8072759e9c5e04a553

target_prologue =
  48 8B C4 48 89 58 10 48 89 70 18 48 89 78 20 55
  41 54 41 55 41 56 41 57 48 8D 6C 24 90 48 81 EC
```

Only after all three checks pass does DotVanisher patch the function. If any
check fails, the hook is disabled and the mod logs an error instead of trying
to run against an unknown binary.

## Timer suppression logic

Every detoured tick follows this shape:

```text
DotVanisher detour
  -> read pending watch list, count, and timeout timer with SEH guards
  -> if the pending-watch state is valid, maybe write a compensated timer value
  -> call the original HandleHostTickWatchEventQueues trampoline
  -> return the original bool result
```

The important detail is that the write happens before the vanilla function
runs. Vanilla code is expected to add the current frame delta to the timer
during its own tick. DotVanisher writes a small negative value first:

```cpp
float timer_compensation_for_delta(float flDeltaSeconds) noexcept
{
    const float delta = observed_positive_delta(flDeltaSeconds);
    return -(std::min)(delta, kMaxDeltaCompensationSeconds);
}
```

For ordinary positive frame deltas, that means the original function adds the
same delta back and the timer lands near zero instead of continuing to grow
toward the watch timeout threshold. Non-finite or negative deltas are treated
as `0.0f`, and huge deltas are capped at 120 seconds so the mod never writes an
unbounded negative timer.

This is a soft timeout deferral, not a skip of the original function. The
original tick still runs every frame and can still process normal watch queue
state, explicit spectator departures, cancellation, and cleanup once the grace
window expires.

## Pending-watch epochs

DotVanisher does not apply one global 90-second timer forever. It groups work
into pending-watch epochs.

An epoch starts when all of these are true:

- `pHostSysState` is non-null.
- `pHostSysState+0xB8` is between `1` and `16`.
- The watch fields can be read safely.
- There is no current epoch, or the host-state pointer changed, or the pending
  watch-list pointer changed.

An epoch ends when the watch count becomes zero, the host-state pointer becomes
null, a guarded read or write fails, the count becomes unreasonable, the hook is
uninstalled, or a different watch-list pointer starts a new epoch.

During an epoch the mod records:

| Field | Why it is tracked |
|---|---|
| Start time from `GetTickCount64()` | Enforces the 90-second grace limit. |
| Host-state pointer | Detects a different host state. |
| Watch-list pointer | Detects a different pending spectator list. |
| Last pending count | Included in summary and expiry logs. |
| Max observed frame delta | Helps diagnose stalls during loading. |
| Max observed timer value before the write | Shows how close vanilla behavior got to timing out. |

For the first 90 seconds of an epoch, the hook writes the compensated timeout
timer before calling the original function. Once elapsed time reaches
`90,000 ms`, DotVanisher logs a warning and stops writing to the timer. At that
point vanilla timeout cleanup resumes.

## Memory-safety choices

The hook reads and writes live game memory, so the implementation is cautious:

| Guard | Behavior |
|---|---|
| SEH-wrapped reads and writes | Bad pointers or unmapped fields do not crash the process from the hook. |
| One-shot warning logs | Repeated read/write/range failures do not spam the log every frame. |
| Count range check | Unexpected structure values fail closed to vanilla behavior. |
| Trampoline null check | If PolyHook did not provide a trampoline, the detour returns `false` instead of calling garbage. |
| RAII uninstall | The `WatchTimeoutHook` destructor unhooks and clears epoch state. |

The default failure mode is to leave SC6's original timeout behavior intact.
That matters because this hook runs on an online host path.

## What DotVanisher does not touch

DotVanisher is not a netcode rewrite. It does not alter:

| System | Reason |
|---|---|
| Player input packets | The mod never hooks channel-5 input send, receive, or drain code. |
| BattleSync messages | The mod does not rewrite channel-6 spectator `Move` or handshake payloads. |
| Player match state | The two active players continue through the normal vanilla load and battle path. |
| Stage assets | The mod does not mount paks, redirect stages, or change AssetManager routing. |
| Lobby UI | No ImGui, no settings page, no picker changes. |
| Spectator leave/cancel commands | Explicit exits still flow through the original watch/event handling. |

The only live field it writes is the host watch timeout timer at
`pHostSysState+0xC0`, and only while a valid pending-watch epoch is inside its
90-second grace period.

## Build and package shape

The CMake target is a shared library:

```cmake
set(TARGET DotVanisher)

add_library(${TARGET} SHARED
    dllmain.cpp
)

target_link_libraries(${TARGET} PUBLIC
    UE4SS
    bcrypt
)
```

`bcrypt` is used for SHA-256 verification. PolyHook comes from the UE4SS C++
mod environment. The local build script produces:

```text
..\build_cmake_LessEqual421__Shipping__Win64\DotVanisher\DotVanisher.dll
```

For a manual UE4SS install, the DLL is deployed as `main.dll`:

```text
<game>\Binaries\Win64\ue4ss\Mods\DotVanisher\
  enabled.txt
  dlls\
    main.dll
```

The Thunderstore package uses the same runtime shape under a `mod/` folder:

```text
manifest.json
README.md
icon.png
mod/
  enabled.txt
  dlls/
    main.dll
```

Its package dependency is `Thunderstore-unreal_shimloader-1.1.7`, which supplies
the UE4SS loader path for compatible mod managers.

## Verify

1. Install DotVanisher as its own UE4SS mod, not inside HorseMod.
2. Launch SC6 with the targeted Steam executable build.
3. Check the UE4SS log for:

   ```text
   [DotVanisher] target binary verified
   [DotVanisher] spectator timeout hook installed
   ```

4. Host a lobby with spectators and load into a match that previously caused
   spectator disconnects.
5. During a pending spectator load, expect an epoch-start log:

   ```text
   [DotVanisher] spectator timeout epoch started
   ```

6. If spectators finish loading before 90 seconds, expect an epoch-ended
   summary when the pending watch count reaches zero.
7. If a spectator remains pending past 90 seconds, expect:

   ```text
   [DotVanisher] spectator timeout grace expired
   ```

   After that line, vanilla cleanup is allowed again.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| No DotVanisher log lines | UE4SS did not load the mod | Check the `ue4ss/Mods/DotVanisher/dlls/main.dll` path and `enabled.txt`. |
| `unsupported SoulcaliburVI.exe size` | Wrong game build | Use the supported Steam executable or update the mod constants after verifying the new build. |
| `unsupported SoulcaliburVI.exe SHA-256` | Edited or unsupported binary | Do not force the hook; re-audit the target function first. |
| `target prologue mismatch` | Wrong patch level or another hook already changed the target bytes | Resolve hook order/conflict and verify the new prologue before enabling. |
| `unreasonable watch count` | The state pointer or offsets do not match the expected structure | Treat this as an unsupported build until the host watch state is re-identified. |
| Spectators still leave after about 90 seconds | Grace window expired | This is intentional; the mod defers false early timeouts but does not keep dead watch entries forever. |
| Players disconnect or desync | Likely unrelated to DotVanisher | The mod does not touch player input sync or battle simulation; investigate online transport separately. |

## Related

- [Leaderboards & Online: in-match netplay](../sc6/leaderboards.md#in-match-netplay-the-per-frame-input-ring)
  for SC6 online channel context.
- [Replay System](../sc6/replay-system.md) for separate replay-watch timing
  concepts that DotVanisher does not hook.
