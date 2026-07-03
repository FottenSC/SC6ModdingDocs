# Browser Replay Display Feasibility Investigation

**Goal**: decide how realistic it is to display an SC6 replay in a web
browser, now that HorseMod can open replay links from the browser into the
game.

**Evidence source**: Ghidra MCP analysis of `SoulcaliburVI.exe`, existing SC6
replay docs, and local HorseMod implementation context under `E:/myMods`.
Ghidra remains authoritative for native symbols, offsets, and replay-launch
control flow; local code is supporting implementation evidence.

## Verdict

The practical path is **browser launches or controls a native renderer**, then
the browser displays either a generated video or a local/remote video stream.

A true browser-native SoulCalibur VI replay player is not currently feasible.
SC6 replay files are deterministic match recordings, not video files. They
need SC6's native Lux battle simulation, assets, animation graphs, camera,
stage collision, replay player, and UE4 runtime to turn the input stream into
frames. Rebuilding that in WebAssembly would be closer to porting or
reimplementing the game than adding a web viewer.

Recommended product ladder:

| Tier | Result | Feasibility | Recommendation |
|---:|---|---|---|
| 0 | Browser "Open in game" button using `sc6replay://play` | Done / high | Keep as the baseline. |
| 1 | Browser replay page with metadata, players, inputs, rounds, generated timeline, and "open locally" status | High | Build next; no gameplay renderer required. |
| 2 | Local companion display: browser triggers local SC6/HorseMod, native helper captures or streams the game view back to the browser | Medium | Best interactive route for users who own the game. |
| 3 | Server/worker render farm that turns a replay into MP4/HLS video | Medium | Best shareable web route; expensive and operationally sensitive. |
| 4 | WebAssembly "stripped-down SC6" | Very low | Treat as a research fantasy until source/license/runtime blockers change. |
| 5 | Clean-room WebGL gameplay renderer | Very low for exact replay, medium for abstract visualization | Useful only as a non-authoritative visualizer. |

## What "display in browser" can mean

These are different products:

| Product | What the browser shows | Needs native SC6? | Interactive? |
|---|---|---:|---:|
| Local open link | Browser opens installed SC6 into replay viewing | Yes, on user PC | Yes, in game window |
| Metadata viewer | Match info, inputs, rounds, timeline, download/open buttons | No for basic metadata; maybe server parser for first pass | Timeline only |
| Local stream | The local game view captured and streamed to the page | Yes, on user PC | Potentially yes |
| Hosted video | Pre-rendered MP4/HLS for a replay | Yes, on render worker | Video scrub only |
| Browser-native sim | WebAssembly/WebGL reproduces the match | Would require a port/reimplementation | Yes in theory |

The first three can reuse the existing browser-launch work. The last one is
the one that looks simple as a phrase and enormous as an engineering project.

## Current browser-to-game path

HorseMod already has the core local bridge:

- `HorseReplayLauncher.exe` handles `sc6replay://play` links.
- The launcher validates `ugc` and `url` query parameters, only accepting the
  production archive host `https://api-replay.horseface.no/api/replays/<ugc>/file`
  or local development hosts.
- It downloads the replay, caps it at 64 MB, and validates the downloaded file
  as a native `ULX1` replay container.
- It writes the replay to `HorseMod/Saved/ReplayFiles/REPLAY_<ugc>.bin`.
- If SC6 is not running, it starts the game, including Thunderstore profile
  launch arguments when needed.
- If SC6 is running, it writes `HorseMod/Saved/replay_file_start_request.json`
  with `timeline_generation_mode: "lux-no-render-force"`.
- A loopback status server listens on `127.0.0.1:54475/status` and returns
  install/version/protocol/game-running/launch-mode state to approved browser
  origins.

Game-side service code in `ReplayScrub` polls that start-request file on the
game thread. It waits for Replay presence, an active `LuxBattleManager`, and a
readable/playing `LuxBattleReplayPlayer`; when auto-generation is armed, it
waits until the no-render timeline is complete before reporting success.

That means the browser side already has a usable local renderer orchestration
primitive. It just does not yet have a way to show the rendered frames inside
the page.

## Ghidra-backed native replay-launch facts

The native path supports the same conclusion: SC6 already knows how to turn a
replay entry into battle setup state, but the authoritative renderer is the
native game.

| Function | Address | Relevant finding |
|---|---:|---|
| `HandleReplayFileRequestNative` | `0x1405EA1F0` | Handles `ULuxReplayListContainer::RequestReplayFile`. `NewReplay` uses the online replay-file interface; `BattleLog` and `MyReplay` load local ULX1 blobs through the replay save object. Local entries dispatch ready event code `2` only when `dwReplayVersion > 42`; failure/not-ready dispatches event code `6`. |
| `ApplyReplayToBattleSetupNative` | `0x14053C700` | Reads `ULuxGameInstance+0x140` for the current battle setup, bails if `BattleSetup+0x238` is set, then copies `ReplaySaveObject+0x40` replay setup snapshot state into the battle setup. |
| `HandleApplyReplayToBattleSetupExec` | `0x140A8CD80` | UE4 exec wrapper now typed as `void(ULuxGameInstance_Partial*, FFrame_Partial*)`; advances `FFrame+0x20 pCode` and tail-calls `ApplyReplayToBattleSetupNative`. |
| `GetNextNonZeroSequenceId` | `0x140D24030` | Former `FUN_140d24030`; returns a process-wide non-zero sequence/cookie id and advances `g_qwNextSequenceId`. Used by replay request callback setup and broader UE4 async/task paths. |
| `LuxReplay_DecodeInputPackets_FromFile` | `0x1403ED310` | Expands SC6's packed replay input records into decoded frame/input records. |
| `ALuxBattleReplayPlayer_Tick_CopyRoundResetSnapshotAndSetMoveState4` | `0x140435C20` | Handles replay round navigation by copying a `0xC0` round-start snapshot into BattleManager state and setting move state `4`. |
| `LuxBattleManager_Tick_SimulationLoop_UpdateInputAndRoundState` | `0x1403FE520` | Consumes replay/input-log master-clock deltas and advances battle simulation state. |

The important design implication: opening a replay is not only "load bytes."
The native flow touches replay-save objects, battle setup, round reset state,
input-log clocks, BattleManager state, and scene transitions. A browser viewer
that bypasses this would have to recreate all of that.

## Option A: pure WebAssembly SC6

This is the idea of "a stripped down version of SoulCalibur that runs on Web
Assembly."

Verdict: **not feasible for this project as currently scoped**.

Reasons:

- SC6 is a proprietary Windows x64 UE4.17.2 shipping game. There is no source
  project to compile with Emscripten.
- A replay file contains deterministic inputs and match metadata, not rendered
  frames. It still needs native gameplay code, animation code, cooked assets,
  stage data, camera logic, and UE object lifecycle.
- UE4's historical HTML5 path was for source UE projects. It does not turn a
  retail Windows build into a legal or practical browser build.
- SC6 depends on platform/runtime pieces that do not map cleanly to a browser:
  Steam interfaces, Windows file paths, DirectX-oriented renderer assumptions,
  middleware assets, and cooked content layout.
- Even if the binary translation problem were solved, distributing enough game
  code/assets for a browser viewer would create licensing problems.

This path only becomes realistic if one of these impossible-looking inputs
changes:

1. Source access and redistribution rights exist.
2. A clean-room engine/gameplay reimplementation becomes the project.
3. The web viewer is explicitly allowed to be approximate rather than
   authoritative.

## Option B: clean-room browser visualizer

This means parsing the replay and drawing a simplified WebGL/Three.js match
viewer without using the native game.

Verdict: **useful for abstract tools, not for faithful replay playback**.

Feasible pieces:

- Replay metadata: players, characters, stage, date, ranks, region.
- Input timeline: decoded per-frame P1/P2 inputs.
- Round markers and rough duration.
- A 2D/low-fidelity "input theater" that moves tokens or stick diagrams.
- Links into frame data, move lists, or annotations.

Hard or impractical pieces:

- Exact movement, hit reactions, camera, animation, wall/ring interaction,
  collision, VFX, and timing.
- Character customization and stage visuals.
- Deterministic sync with SC6's native Lux battle simulation.

This is a good companion product for analysis and discovery, but it should be
labelled as a replay inspector, not "the replay."

## Option C: server-side video rendering

This is the idea of "a machine that quickly renders a video of the match."

Verdict: **feasible, but not cheap**. This is the best route for shareable
browser playback where viewers do not have SC6 installed.

High-level flow:

```text
browser replay page
  -> queue render job for UGC/replay id
  -> worker downloads replay bytes
  -> worker launches or reuses a warmed SC6 + HorseMod instance
  -> HorseMod opens the replay and waits for active playback
  -> optional lux-no-render timeline pass validates/labels the match
  -> worker captures visible rendered frames while replay plays
  -> encode MP4/HLS/WebM
  -> browser displays normal video
```

What can be reused:

- `sc6replay://play` validation rules and replay download shape.
- `replay_file_start_request.json` orchestration.
- Replay presence/runtime readiness checks.
- `lux-no-render-force` timeline generation for metadata, seek maps, and
  validation.
- Existing strict replay seek/watch tests as regression gates.

What cannot be skipped:

- If the output is video, the game still has to render frames. No-render mode
  is useful for timeline generation, but it cannot produce pixels.
- A worker needs Windows, GPU or GPU partitioning, a display/capture path, SC6,
  HorseMod, Steam/account handling, and robust cleanup after crashes.
- Video render speed is likely bounded by real rendering cost. Fast no-render
  timeline generation does not imply fast video capture.

Implementation sketch:

1. Start local first. Build a single-machine render CLI in `E:/myMods` that
   takes a replay path and writes `out.mp4`.
2. Reuse the existing replay-file start request format to open the replay.
3. Wait for `active replay playback observed` or `generated timeline ready`.
4. Capture the SC6 window/backbuffer using Desktop Duplication, OBS/FFmpeg,
   NVENC/AMF, or an in-process D3D hook.
5. Encode at fixed 60 fps; store timeline metadata next to the video.
6. Measure cold start, warm start, real-time factor, average output size, and
   failure rate.
7. Only then decide whether a worker pool is worth it.

Good first target:

| Target | Pass condition |
|---|---|
| 30-second clip from a known replay | Browser can request a job and play the resulting MP4. |
| One full replay on a warm local worker | Render succeeds without manual input and produces correct round order. |
| Queue of 10 replays | No stuck SC6 processes, corrupted captures, or wrong replay/video pairing. |

Kill criteria:

- Full-match render regularly takes much longer than real time on available
  hardware.
- Steam/game licensing makes hosted rendering unacceptable.
- Worker isolation is too fragile to run unattended.
- Rendered video cannot be paired reliably with the requested replay id.

## Option D: local browser stream from the installed game

This keeps the user-owned game as the renderer but shows the picture in the
browser.

Verdict: **feasible for installed users, and probably the best interactive
browser experience**.

Possible designs:

| Design | Notes |
|---|---|
| Native helper captures game window and serves WebRTC/WebSocket video on localhost | Browser page becomes a remote-control surface for local SC6. |
| HorseMod in-process backbuffer capture | Lower latency and better frame accuracy, but higher crash/blast radius. |
| External OBS/FFmpeg/desktop-duplication helper | Easier to prototype; less integrated. |
| Browser page controls native game via local HTTP status/control API | Extends the current `127.0.0.1:54475/status` idea from status-only to status plus stream/control. |

This route avoids hosted redistribution problems because the user supplies the
installed game and assets. It still needs security work:

- Keep CORS allowlists strict.
- Bind only to loopback.
- Require an explicit local install/permission step.
- Never accept arbitrary replay download URLs.
- Avoid exposing file paths or player private data beyond the local page.

## Option E: hybrid timeline plus clips

This is likely the most useful near-term product:

1. The browser page always shows metadata, inputs, rounds, and "open in game."
2. A local user can generate a no-render timeline quickly.
3. A local or hosted worker can render short clips on demand:
   round start, KO, selected time range, or bookmarked moments.
4. Full-match video is optional and queued.

This gives web value before solving full hosted playback. It also matches the
existing HorseMod strengths: replay seek, no-render timeline generation, and
native replay launch automation.

## Recommended roadmap

### Phase 1: replay page without pixels

- Show install/game status via `127.0.0.1:54475/status`.
- Provide `Open in SC6` using `sc6replay://play`.
- Display replay metadata already available from the archive/leaderboard row.
- Add a server-side replay parser if browser parsing is delayed.
- Show a clear state when HorseMod is missing, game is not running, or profile
  launch is required.

### Phase 2: local capture prototype

- Add a developer-only CLI that opens a replay and captures a fixed 30-second
  MP4.
- Use the existing replay-file start request instead of adding a second launch
  mechanism.
- Record runtime evidence: replay id, start time, active playback observed,
  timeline generated or skipped, capture FPS, encode FPS, output path.
- Run the strict replay seek/watch regression after capture-path changes.

### Phase 3: local browser stream

- Add a localhost stream endpoint or WebRTC helper.
- Keep browser controls small: play/open, status, maybe seek once native seek is
  stable for the selected replay.
- Treat stream/control permissions like a local device permission, not a public
  web API.

### Phase 4: hosted video worker

- Container/VM image with SC6 + HorseMod + Steam prerequisites.
- Warm worker pool if cold start is too slow.
- Job queue with one replay per isolated worker slot.
- MP4/HLS output, thumbnails, JSON timeline sidecar, logs, and crash dumps.
- Strict retention policy for videos and player-identifying metadata.

### Phase 5: optional abstract visualizer

- Decode replay input into a browser timeline.
- Add input diagrams and round markers.
- Add frame-data links and annotations.
- Do not market it as exact gameplay playback.

## Open questions to answer with prototypes

| Question | How to test |
|---|---|
| How fast can a warm native worker produce a full-match video? | Run 20 known replays through a local capture CLI; record real-time factor. |
| Can no-render generation produce enough timeline metadata for web overlays? | Compare normal vs `lux-no-render` oracle data using existing replay tests. |
| Can a worker seek reliably to clip start points before recording? | Use generated timeline tags plus native replay seek; reject clips on seek validation failure. |
| Is capture stable in background/minimized sessions? | Test Desktop Duplication, OBS, and in-process capture under locked/unfocused desktop conditions. |
| What is legally acceptable for hosted rendering? | Decide before building a public worker pool. Local-only rendering can proceed independently. |
| Can replay metadata be parsed safely in the browser? | First document exact `ULX1` container boundaries, then implement a bounded parser with fuzz tests. |

## Decision

Do **not** pursue a WebAssembly SC6 port as the main plan. Keep the native game
as the authoritative renderer.

Build the browser product in this order:

1. Better browser replay page around the existing `sc6replay://play` bridge.
2. Metadata/input/timeline display.
3. Local capture/stream prototype.
4. Hosted render-to-video only after local capture proves speed and stability.

That path gives a useful browser replay experience without pretending the
browser can cheaply become SC6.
