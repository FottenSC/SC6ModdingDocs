# PlayFab Party Netcode Relay Investigation

**Goal**: decide whether a PlayFab/PlayFab Party-backed transport can improve
SC6 online play between America and Europe by measuring route quality, choosing
sessions/regions more deliberately, using transparent cloud relay where useful,
and optionally falling back to direct peer or a custom relay path.

**Evidence source**: the existing
[Rollback Netcode Feasibility Investigation](rollback-netcode-investigation.md),
[Automated Rollback Netcode Testing on One Machine](automated-rollback-netcode-testing.md),
and current PlayFab/Azure/Steam service documentation checked on 2026-07-03.
This page is documentation-only. It does not implement or recommend redirecting
stock SC6 traffic until the transport boundary is actually owned and measured.

## Verdict

PlayFab Party is the better lead candidate than a raw Azure VM relay if the goal
is a managed game-networking path with QoS measurement, region selection,
session control, transparent cloud relay, and optional direct peer connectivity.
Treat it as a **measured route-quality and connectivity fallback**, not as a
speed-of-light bypass.

The important split is physical propagation latency versus avoidable path
overhead. PlayFab Party cannot make transatlantic packets propagate faster than
the fiber distance allows. It can plausibly reduce the avoidable part of a bad
route: poor ISP peering, route hairpinning through distant transit, congestion,
queueing jitter, packet loss, NAT trouble, or unstable direct connectivity.
Party's useful claim is that QoS measurement, selected Azure regions, Azure
backbone paths, transparent cloud relay, session policy, and optional direct
peer mode can sometimes choose a better route than the one the peers would get
by default.

Party still cannot make a good direct peer or Steam Datagram Relay route faster
just by inserting a cloud relay in the middle. It only has a chance to help when
at least one of these is true:

- the direct ISP path is bad, congested, or hairpinned through poor transit;
- Steam Datagram Relay chooses a worse path than the measured Party route for
  this pair;
- direct peer connectivity is unreliable and Party's relay path provides lower
  jitter, less loss, or fewer burst stalls even with similar median RTT;
- Party QoS data helps pick a better hosted region before the match starts;
- the project owns a custom/native transport boundary and can choose direct,
  Steam/SDR, Party relay, or custom relay per match.

The biggest blocker is still not PlayFab or Azure. It is transport ownership.
The rollback investigation shows that stock SC6 online packets are tiny
input-cache packets inside the existing Steam/online path. If the mod cannot
replace or wrap the fight-input transport at a game-thread-safe boundary,
PlayFab Party cannot transparently redirect stock SC6/Steam traffic in a clean
way.

Practical verdict:

| Question | Current answer |
|---|---|
| Can PlayFab Party reduce unavoidable US<->EU propagation delay? | No. The physical propagation floor remains. |
| Can Party reduce avoidable route overhead or instability? | Plausibly. QoS-selected regions, Azure backbone/relay paths, session policy, and optional direct peer mode can avoid some ISP hairpinning, congestion, jitter, loss, or NAT failures. |
| Can Party beat bad direct peering or a bad SDR route? | Sometimes, but only if measured end-to-end jitter/loss/RTT and gameplay metrics improve. |
| Can this work with stock SC6 transport unchanged? | Unproven and unlikely. Treat stock Steam transport as not redirectable until proven otherwise. |
| Lead candidate | PlayFab Party as a managed transport/QoS/session experiment, if native integration is possible. |
| Primary useful Party features | QoS measurement, region selection, transparent cloud relay, optional direct peer mode, and TURN-like fallback behavior. |
| Best custom data-plane fallback | A small custom UDP relay on Azure VMs/VMSS, only if Party cannot satisfy protocol, latency, platform, cost, or integration needs. |
| Best control-plane candidates | PlayFab services first; otherwise a small HTTPS service, Azure Functions, Web PubSub, or Azure Relay for signaling/allocation/telemetry only. |
| Services to avoid for fight-input UDP | Azure Relay Hybrid Connections and Azure Web PubSub; they are HTTP/WebSocket-style services, not raw UDP game relays. |
| First prototype | Out-of-game Party/QoS route measurement plus a local rollback transport shim, before touching real ranked/online SC6 sessions. |

## Latency math

For a fighting game, median ping is not enough. A stable 90 ms RTT can feel
better than a 75 ms route with 40 ms jitter bursts, but the physical floor still
matters.

Separate the latency budget into two buckets:

- **Physical propagation**: the unavoidable time for the signal to cross the
  real distance through fiber and access networks. Party, SDR, a custom Azure
  relay, and direct peer mode all share this floor.
- **Avoidable overhead**: routing detours, ISP hairpinning, congested peering,
  queues, retransmission-like stalls above UDP, jitter, loss, NAT fallback
  behavior, and bad region/session choices. Party can plausibly improve this
  bucket when its QoS-selected relay or direct path is better than the default
  peer path.

Rough lower bounds:

| Path | Physical reality |
|---|---|
| US East Coast to Western Europe | Roughly 5,500 to 6,500 km great-circle distance. In fiber, one-way propagation alone is roughly 28 to 33 ms before routing, switching, access networks, and queues. A best-case RTT floor is roughly 55 to 65 ms. |
| Central US to Western Europe | Longer than East Coast, commonly pushing the physical floor toward the 70 ms+ RTT range before overhead. |
| US West Coast to Western Europe | Much longer path; a sub-80 ms RTT is not realistic. |

At 60 fps, one frame is `16.67 ms`:

| RTT | Frame equivalent |
|---:|---:|
| 66 ms | 4.0 frames |
| 83 ms | 5.0 frames |
| 100 ms | 6.0 frames |
| 133 ms | 8.0 frames |

For any single cloud relay, whether Party-managed or custom-hosted, an
application-level ping through the relay is approximately:

```text
relay_rtt ~= client_a_to_relay_rtt + client_b_to_relay_rtt
```

For a two-region custom relay path where each player uses a nearby Azure region
and the relay servers forward over the Azure backbone:

```text
relay_rtt ~= client_a_to_region_a_rtt
          + azure_region_a_to_region_b_rtt
          + client_b_to_region_b_rtt
```

That formula is why a relay is not automatically faster than direct play. A
good direct or SDR path usually wins because it avoids extra relay legs. Party
or a custom relay can still win when the default path is inefficient enough that
the measured relay legs are better, or when lower jitter, lower loss, fewer
burst stalls, or more reliable session connectivity justify a similar or
slightly higher median RTT.

Party QoS and Azure's public inter-region latency tables are useful sanity
checks, not player-route guarantees. Azure's 2026-07-02 public inter-region
latency dataset lists P50 RTTs from Azure internal probes; for example, East US
to West Europe is in the high 80 ms range, and East US to North Europe / UK
South is in the mid-to-high 70 ms range. Residential-player-to-cloud legs must
be added on top.

### Practical estimate: Norway to America/Japan

For a Norway-based player asking how much PlayFab Party cloud relay might
improve connections to America or Japan, the cautious answer is: it can improve
bad routes, but it cannot beat physical lower bounds. A relay only helps when
it removes avoidable overhead such as poor ISP peering, hairpinning, congestion,
loss, or queueing jitter. If the existing direct/Steam route is already close
to the physical floor, adding a Party relay leg can tie or lose.

Azure's public inter-region P50 RTT tables are useful as sanity checks for the
cloud-backbone part of the path, not as promises for residential players. Around
the 2026-07 public data, Norway East to candidate destination regions is roughly:

| Azure inter-region path | Public P50 RTT sanity check | Practical meaning |
|---|---:|---|
| Norway East to East US | ~95 to 100 ms | US East is the most plausible America-side case where Party/Azure routing might reduce a bad residential route. |
| Norway East to West US | ~148 to 155 ms | US West has much less room for a relay to feel like a ping improvement because the physical distance and cloud backbone leg are already large. |
| Norway East to Japan East/West | ~240 to 245 ms | Japan is unlikely to get a large median-RTT win; the main possible benefit is steadier jitter/loss behavior. |

Residential access adds overhead on both sides: Wi-Fi, local ISP routing,
peering, last-mile congestion, cable/fiber path length, home router queues, and
the player's distance from the chosen Azure/Party region. The real application
RTT is the cloud sanity check plus both player-to-cloud legs and any service or
queueing overhead.

Likely improvement ranges for Norway-based testing:

| Route class | Cautious Party relay expectation |
|---|---|
| Norway to US East | Common bad-route improvement target. Expect `0` to `30 ms` median RTT improvement in typical poor-peering cases; `40` to `60+ ms` only when the original path is severely hairpinned, congested, or otherwise pathological. |
| Norway to US West | Less likely to improve median RTT. Expect `0` to `30 ms` at most unless the baseline route is obviously broken; stability may matter more than average ping. |
| Norway to Japan | Usually `0` to `30 ms` median RTT improvement, and often no median-ping win at all. The more realistic win is lower p95/p99 jitter, fewer loss bursts, fewer stalls, or smoother late-input behavior. |

For SC6 and rollback-style experiments, measure the route by its gameplay
pressure, not by average ping alone. The route report should prioritize p95/p99
jitter, packet loss, burst loss, stalls, late inputs, prediction age, rollback
depth, and over-window input arrivals. A Party route with the same median RTT
can still be better if it removes frame-sized spikes; a Party route with a
lower average ping can still be worse if it creates burst stalls.

Disabling direct peer connectivity and forcing Party cloud relay is a useful
privacy-safe baseline because it avoids exposing peer IPs and makes the path
more controlled. That same setting can lose to a good direct path, so the
baseline should be treated as a safety/stability comparison, not as the
automatic fastest mode.

## Relation to SC6 rollback work

The relay question depends on the rollback investigation in three ways:

- Stock SC6 online play is delay/catch-up based. A better transport can reduce
  instability, but it does not create rollback.
- A useful custom transport still needs absolute frame ids, confirmations,
  prediction age, state hashes, queue policy, and desync policy. The stock
  3-byte packet hot paths are not enough for a full rollback protocol.
- Input cache writes must happen at a game-thread-owned boundary. Do not write
  `FLuxReplayInputCacheEntry` cells from a network receive thread.

So the Party prototype should be treated as a transport experiment layered after
the local rollback lab proves deterministic restore/resimulation and input
ownership.

## Candidate approaches

### PlayFab Party as the lead transport candidate

PlayFab Party is the managed path that best matches the clarified goal. It is
not "a VM inside Azure"; it is a game-networking library/service shape that can
provide cloud relay paths, QoS measurements, region selection, authentication
and session concepts, and optional direct peer connectivity.

Shape:

```text
SC6 native transport hook
  -> mod-owned Party transport adapter
  -> PlayFab Party network in selected region
  -> transparent cloud relay, or optional direct peer path
  -> peer Party transport adapter
  -> game-thread input boundary
```

Minimum integration requirements:

- load and drive the Party library from a native component that can run beside
  SC6 safely;
- establish title/user authentication and Party network/session lifecycle;
- encode the mod's frame-aware input protocol into Party endpoint messages;
- decide whether direct peer connectivity is disabled, optional, or opt-in;
- record Party QoS and observed message delivery metrics per session;
- route final input writes through the same game-thread boundary required by
  the rollback work.

Minimum fight-input payload metadata stays the same as a custom UDP protocol:

- protocol version and packet type;
- sequence id and send timestamp;
- absolute input frame;
- prediction/confirmation markers;
- payload hash/checksum;
- optional state-hash metadata where the rollback lab supports it.

Benefits:

- QoS measurements can inform region selection before the match starts.
- QoS-selected Azure relay paths may avoid bad ISP peering, distant hairpinning,
  or congested direct routes for some player pairs.
- Azure backbone routing between selected regions can be more stable than the
  default residential-transit path, but this must be measured per route.
- Transparent cloud relay can hide peer IPs when direct peer mode is disabled.
- Session policy can decide when relay, direct peer, or another measured route
  is allowed instead of treating connectivity as an accidental side effect.
- Direct peer connectivity can be tested as an optional performance mode when
  both players accept the IP disclosure tradeoff.
- Session/auth/control concerns are more game-oriented than a generic VM relay.

Limits:

- Party is not a transparent redirector for stock SC6 or Steam packets.
- Party does not bypass the physical propagation floor between continents.
- Party still needs native integration, lifecycle handling, and failure policy.
- Party relay may be slower than Steam Datagram Relay or a good direct route.
- Direct peer mode changes the privacy/security model because peer IP
  disclosure may be involved.
- The project must still own rollback/input semantics above the transport.

### PlayFab as control plane without Party data plane

If Party's data path is unsuitable, PlayFab can still be useful as a control
plane:

- create match/session ids;
- exchange relay or Party network tokens;
- collect QoS samples and candidate region lists;
- choose direct vs Party relay vs SDR-visible path vs custom relay;
- publish telemetry and failure summaries;
- gate opt-in direct peer policy.

That control plane should not carry per-frame fight inputs. Keep fight-input
delivery on a transport designed and measured for low-latency packet flow.

### Direct-peer optional mode

Direct peer can be valuable when both players have good peering and the project
accepts the privacy tradeoff. It should be a policy choice, not an accidental
side effect.

Recommended policy:

1. Default to Party cloud relay or the existing Steam path for privacy-safe
   testing.
2. Offer direct peer only as an explicit opt-in experiment.
3. Measure direct, Party relay, and any custom relay candidate before match
   start.
4. Prefer direct only when it clearly wins on p95/p99 jitter, burst loss, and
   gameplay/input metrics.
5. Fall back to relay when NAT, firewall, or route quality makes direct play
   unstable.

This is TURN-like behavior at the game-policy level: direct when safe and good,
relay when direct is unavailable or bad.

### Custom Azure UDP relay fallback

A regional UDP relay on Azure VMs or VMSS is no longer the lead recommendation.
Use it only when Party cannot satisfy a concrete requirement, such as:

- unsupported platform/runtime constraints for this modding environment;
- packet behavior or timing control that Party cannot expose;
- need to compare raw UDP against Party and Steam/SDR in controlled tests;
- operational or cost constraints that make a small custom relay preferable;
- a future rollback transport that needs a custom server data plane.

Shape:

```text
SC6 native transport hook
  -> local mod UDP protocol
  -> Azure relay allocation in selected region
  -> relay forwards to peer allocation
  -> peer mod UDP protocol
  -> game-thread input boundary
```

Use a VM first. Move to VM Scale Sets only after a single relay is useful and
the operations problem is real. Azure Load Balancer can handle TCP/UDP flows to
VM or VMSS backends and preserve a low-level layer-4 shape, but it does not
understand game sessions or packets. Session ownership, packet validation,
abuse control, and route selection stay in the relay service.

Minimum custom relay behavior:

- allocate a session with two authenticated endpoints;
- bind both players to one relay instance for the session;
- forward only expected UDP packets for that session token;
- include sequence id, protocol version, packet type, absolute input frame,
  send timestamp, payload hash/checksum, and optional state-hash metadata in
  the mod protocol;
- measure server processing time separately from network RTT;
- expose health and telemetry through HTTPS, not through the fight-input UDP
  path.

This is not a transparent proxy for the stock Steam path. It assumes a custom
or wrapped transport where the mod controls the payload boundary.

### Containers

Containers are plausible for packaging a custom relay binary, but the Azure
product choice matters. This is a fallback/custom-data-plane topic, not the
primary PlayFab Party path.

| Service | Fit for fight-input relay |
|---|---|
| Azure Container Instances | Possible for small UDP experiments; its container group schema allows TCP or UDP ports. Validate public IP stability, restart behavior, observability, and cold-start impact before relying on it. |
| Azure Container Apps | Poor fit for raw UDP. Its ingress model is HTTP and TCP, with WebSocket/gRPC under HTTP, not UDP. Useful for control-plane APIs, not fight-input packets. |
| AKS | Possible but heavy for the first prototype. Consider only after Party and VM/ACI tests prove a custom relay helps and operational scale matters. |

For a fighting-game relay, predictable process scheduling and stable network
behavior matter more than container convenience. Start with PlayFab Party for
managed transport experiments. Start with VMs if and only if the project needs a
custom UDP relay.

### Azure Relay and Azure Web PubSub

These are not good data-plane choices for SC6 fight-input traffic.

Azure Relay Hybrid Connections are based on HTTP and WebSockets. Azure Web
PubSub is a managed WebSocket/pub-sub service. Both can be useful for signaling,
dashboards, test orchestration, support tools, or route-selection control
messages. They should not be used as the real-time input stream unless the goal
is only a diagnostic prototype that intentionally measures how bad that shape
is.

Do not put a rollback input stream through WebSocket just because the service is
convenient. The stock and rollback paths need low-overhead, frame-aware,
loss/jitter-aware delivery.

## Architecture

Separate game integration, route policy, control plane, and data plane.

| Layer | Responsibility | Lead candidate | Fallback/custom option |
|---|---|---|---|
| Data plane | Per-frame input message transport, relay/direct behavior, route health, abuse limits. | PlayFab Party endpoint messages over transparent cloud relay, with optional direct peer mode. | Custom UDP relay on Azure VMs/VMSS; Azure Load Balancer only for scale/HA; ACI only for narrow experiments. |
| Control plane | Auth/session ids, relay or Party tokens, region list, route-test orchestration, match policy. | PlayFab services and Party network/session lifecycle. | Small HTTPS API, Azure Functions, Web PubSub, or Azure Relay for signaling only. |
| QoS plane | Region latency samples, candidate route comparison, route-quality history. | Party QoS measurements plus in-session Party message telemetry. | Custom UDP probes to Azure regions and peer endpoints. |
| Telemetry plane | Aggregate route metrics, failure capsules, dashboards, support bundles. | PlayFab telemetry where appropriate plus local/support artifacts. | Application Insights / Log Analytics style pipeline, or simple blob/JSONL artifacts for early tests. |
| Game integration | Input ownership, prediction/confirmation, state hashes, rollback/stall policy. | Native SC6 mod hooks; not a PlayFab responsibility. | Same. |

Recommended first topology:

```text
player A Party/mod harness
  -> Party QoS samples
  -> Party endpoint-message test through selected region
  -> optional direct-peer test only if explicitly enabled

player B Party/mod harness
  -> Party QoS samples
  -> Party endpoint-message test through selected region
  -> optional direct-peer test only if explicitly enabled

route policy
  -> compares Party relay, optional Party direct, direct UDP baseline,
     Steam/SDR-visible metrics where safely observable, and custom relay only
     if implemented

local rollback transport shim
  -> uses the same frame-aware packet schema planned for real SC6 integration
```

Do not start by trying to intercept an encrypted or opaque Steam transport.
Start with an out-of-game Party/native harness and a mod-owned loopback
transport shim that use the same metrics and packet schema planned for the real
rollback protocol.

## Region strategy

Party's QoS measurements should drive region selection. The region list below
is only a starting set for America-Europe testing and sanity checks.

| Region | Why test it |
|---|---|
| East US / East US 2 | Best first guess for US East Coast to Europe. Also a likely midpoint for many US players. |
| North Europe / UK South / West Europe | Good European candidates for EU players and US East routes. |
| Central US | Useful when the American player is not near the East Coast. |
| West US / West US 2 | Useful for West Coast players, but do not expect Europe latency miracles. |

Measure these per player pair:

- Party QoS results for candidate regions;
- Party endpoint-message RTT/jitter/loss through the selected network region;
- Party connection mode where observable, such as relay vs direct peer;
- direct peer RTT/jitter/loss where available and explicitly allowed;
- Steam/SDR-visible metrics if the game or Steam APIs expose them cleanly;
- custom Azure relay RTT/jitter/loss only if a custom relay is being evaluated.

Choose the current best measured route for the pair. Do not assume Party is
better just because it is managed, and do not assume a VM is better just because
it is manually controlled.

## Prototype plan

### Phase 0: define the claim

Write down the exact hypothesis before integrating anything:

```text
For America-Europe pairs with unstable direct/Steam routing, PlayFab Party can
reduce avoidable route overhead, p95/p99 jitter, burst loss, connection
failures, or over-window late inputs enough to improve SC6 match quality, even
though the physical propagation floor is unchanged and median RTT may be
unchanged or slightly worse.
```

This avoids optimizing for a headline ping number that does not matter in
gameplay.

### Phase 1: out-of-game Party and route measurement

Build no SC6 hooks yet. Use a small native Party harness between real test
machines, and keep a direct UDP echo/probe harness as a baseline where possible.

Record:

- Party QoS measurements for candidate regions;
- selected Party region and network/session setup result;
- Party endpoint-message RTT, p50/p95/p99, jitter, loss, burst loss, reorder,
  duplicate count, and queue delay;
- whether the path is relay or direct peer where the API exposes it;
- direct peer RTT if both peers can receive UDP and the test explicitly allows
  IP disclosure;
- Steam/SDR-visible route quality if safely observable;
- custom Azure relay measurements only if there is already a concrete custom
  data-plane question;
- local ISP/ASN only if explicitly opted in for support data.

Run each sample long enough to catch bursts. A 10-second ping test is not
enough; use at least 5 to 10 minute windows for route decisions and longer soak
tests for claims.

### Phase 2: local transport shim

Reuse the automated rollback testing page's loopback shim idea. Put the
frame-aware protocol behind a local abstraction before using it in SC6:

- absolute input frame id;
- sequence id and send timestamp;
- prediction/confirmation markers;
- payload hash/checksum;
- state-hash side channel where the rollback lab supports it;
- route mode field, such as direct, Party relay, Party direct, SDR-visible, or
  custom relay;
- deterministic fault injection for delay, jitter, loss, reorder, duplicates,
  and corruption.

This phase proves protocol behavior without cloud noise and keeps PlayFab
integration from becoming entangled with rollback correctness.

### Phase 3: PlayFab Party relay MVP

Use Party as the first real cloud data-plane experiment.

Start conservatively:

- create one Party network/session for a two-player test;
- select the region from Party QoS results;
- disable direct peer connectivity at first if the goal is to measure the
  transparent relay path and avoid IP disclosure;
- send only the frame-aware test payload over Party endpoint messages;
- log aggregate route metrics and packet metadata, not raw inputs;
- expire sessions quickly and handle reconnect/failure cases explicitly.

Pass condition: Party message delivery metrics line up with the local transport
shim's gameplay/input logs, and Party improves at least one real problem route
without causing desyncs or unsafe transport-thread writes.

### Phase 4: optional direct peer mode and fallback policy

Add direct peer only after the relay-only Party path is understood.

Selection should compare:

- existing direct/Steam behavior where observable;
- Party transparent relay;
- Party direct peer when both players opt in;
- custom Azure relay only if being evaluated;
- rolling jitter/loss and rollback pressure, not only median RTT;
- privacy, abuse, cost, and regional capacity.

Do not switch routes mid-round in the first version. Select before the match or
between rounds, then hold the route stable unless the current route fails badly
enough to justify a reconnect/resync policy.

### Phase 5: custom Azure UDP relay fallback

Only build this if Party fails a concrete requirement or the project needs a
controlled raw-UDP comparison.

Keep it boring:

- one relay VM in the most promising measured region;
- one relay process;
- one UDP port range;
- one HTTPS control endpoint for allocations and health;
- short-lived session tokens;
- per-session packet counters and aggregate metrics;
- no raw input or payload logging;
- hard rate limits per session and per source.

Pass condition: the custom relay beats or complements Party/SDR/direct for a
specific measured problem, not just a theoretical architecture preference.

### Phase 6: SC6 online experiment

Only after local rollback determinism and the transport shim are stable:

1. Run unranked/lab sessions only.
2. Require identical SC6/mod/build manifests.
3. Keep the stock SC6 online path disabled or bypassed for the test transport
   unless the stock path integration has been proven safe.
4. Compare direct/custom transport vs Party relay vs optional direct peer using
   identical scripted input scenarios first, then real inputs.
5. Treat desync, over-window late input, unsafe thread writes, or route-switch
   failure as hard test failures.

## Instrumentation

Use frame-aware metrics. Network logs must align with gameplay logs from the
rollback testing page.

| Log | Include | Why |
|---|---|---|
| Party QoS log | Pair id, candidate region, measured latency, sample count, measurement time, selected region. | Chooses Party regions based on measured quality, not guesswork. |
| Route probe | Pair id, candidate route, region, p50/p95/p99 RTT, jitter, loss, burst loss, reorder, duplicates, sample count, window duration. | Compares Party relay/direct, Steam/SDR-visible paths, and any custom relay candidates. |
| Party message log | Session id hash, route mode, packet sequence, input frame, send timestamp, receive timestamp, packet size, payload hash, delivery/failure status. | Connects Party transport behavior to gameplay impact without storing raw inputs. |
| Custom relay packet log | Session id hash, packet sequence, input frame, arrival timestamp, forward timestamp, source leg, destination leg, packet size, payload hash. | Separates server processing from network delay if a custom relay fallback is tested. |
| Input history | Intended input, consumed input, predicted/confirmed bit, absolute frame, slot, arrival frame. | Shows whether network delivery improved actual game input ownership. |
| Rollback pressure | Rollback depth, prediction age, correction count, over-window late inputs, stalls, desync hashes. | Converts network quality into gameplay impact. |
| Stock-path comparison | Existing SC6/Steam-visible ping/stall counters where safely observable, including `BM+0x1638` stall behavior. | Compares Party against the path players actually use today. |
| Cost/ops | Party usage/cost signals, VM size where applicable, region, egress, CPU, packets/sec, active sessions, dropped packets, process restarts. | Prevents a technically good route from becoming an unsustainable service. |

Telemetry should report rolling windows. Store raw debug traces only in local or
explicit opt-in support bundles.

## Risks

| Risk | Consequence | Mitigation |
|---|---|---|
| Speed-of-light floor | Party or any relay cannot make US<->EU packets propagate faster than physical distance allows. | Frame the claim around reducing avoidable routing overhead, jitter, loss, and connection failures; refuse to claim impossible propagation reductions. |
| Stock transport ownership | The mod may not be able to redirect SC6/Steam traffic cleanly. | Build only against a mod-owned transport boundary; stop if that boundary does not exist. |
| Native Party integration | The SDK may be hard to initialize, authenticate, drive, or ship safely inside this modding environment. | Start with an external native harness, then integrate only after lifecycle and failure behavior are known. |
| Steam Datagram Relay already helps | Party might be worse than SDR for many users. | Measure direct, SDR-visible, and Party candidates before choosing a route. |
| Extra hop increases median RTT | Better jitter can still come with worse average ping. | Decide using p95/p99 jitter/loss and rollback pressure, not median RTT alone. |
| Direct peer IP disclosure | Optional direct mode may expose peer IP information. | Default to relay, make direct peer explicit/opt-in, and document the tradeoff. |
| NAT/firewall behavior | Some peers may not receive direct UDP or may have unstable mappings. | Use relay as fallback, keep keepalives explicit where applicable, and test varied home networks. |
| Abuse and DDoS | Any public relay or direct mode can be attacked or abused. | Use PlayFab/Party auth/session controls where possible; for custom relays use session tokens, packet limits, source validation, and short lifetimes. |
| Privacy | IPs, session ids, route data, or input streams could identify players or reveal gameplay data. | Minimize logs, hash session ids, avoid raw inputs, keep support bundles opt-in. |
| Cost | Party usage, inter-region egress, and custom VMs can become expensive. | Prototype with quotas, shut down custom relays when idle, and add cost gates before public tests. |
| Route instability | Best region can change by time of day or ISP event. | Re-measure per session and keep historical aggregates separate from live route choice. |
| Legal/ToS uncertainty | Redirecting or replacing stock online traffic may be unacceptable. | Keep tests unranked/opt-in, do not bypass Steam auth or DRM, and require a legal review before any public service. |

## Privacy and ToS boundaries

Keep the prototype conservative:

- Do not capture or upload raw SC6 input streams as routine telemetry.
- Do not log public IP addresses in long-term analytics unless a user explicitly
  provides a support bundle.
- Hash peer/session ids with a per-session salt or omit them.
- Treat local adapter type, ISP, ASN, and country as optional support context,
  not matchmaking policy.
- Disclose when a session uses PlayFab Party relay, Party direct peer, Steam
  routing, or a custom relay.
- Make Party direct peer mode explicit because it may change IP-disclosure
  behavior.
- Do not use any relay to bypass Steam authentication, matchmaking ownership,
  region locks, DRM, or SC6 online policy.
- Do not intercept encrypted Steam traffic and claim it is a supported
  transport. Own the transport boundary or stop.

This page is not legal advice. It is a technical risk list for deciding whether
a prototype is safe enough to run.

## Decision criteria

Use explicit gates before moving from lab to real online tests.

### Continue if

- direct/Steam routes for real America-Europe test pairs show recurring jitter,
  loss, connection failures, or route spikes that affect rollback pressure or
  stalls;
- Party QoS and endpoint-message tests identify a relay region or direct-peer
  policy that improves p95/p99 jitter, burst loss, prediction age, rollback
  depth, stalls, or over-window late inputs;
- median RTT is no worse than direct/SDR by a small agreed margin, or the
  jitter/loss improvement is large enough to justify the tradeoff;
- the mod owns a safe game-thread transport boundary;
- Party native integration can be initialized, driven, shut down, and recovered
  without destabilizing SC6;
- privacy, direct-peer policy, abuse controls, and cost limits are in place.

### Stop or defer if

- Party only improves a synthetic ping test and not gameplay/input metrics;
- direct/SDR is already better for most target pairs;
- the only viable approach is transparent interception of stock Steam traffic;
- native Party integration cannot be made safe inside or beside SC6;
- route selection requires mid-round switching before rollback/resync policy is
  solved;
- logging or operations would collect more player data than the project needs;
- PlayFab/Party cost or custom Azure cost per active match is not acceptable.

Suggested numeric starting gates:

| Metric | Continue threshold |
|---|---|
| p95/p99 jitter | Party or the selected route reduces spikes by at least one 60 fps frame on problem routes. |
| Burst loss | Party or the selected route cuts burst-loss events by at least half on measured bad routes. |
| Median RTT | Selected route is within roughly 5 to 10 ms of direct/SDR, unless jitter/loss wins are large. |
| Rollback pressure | Fewer over-window late inputs or fewer stalls under identical scripted input tests. |
| Integration stability | Party setup, teardown, reconnect, and error paths do not crash or corrupt SC6 sessions. |
| Privacy policy | Direct peer mode is disabled by default or explicitly opt-in with the IP-disclosure tradeoff documented. |
| Operations | Sessions survive rate limits, reconnects, idle expiry, and process restarts without silent packet misdelivery. |

Treat these numbers as first-pass gates. Real thresholds should be tuned from
SC6 rollback logs, not from cloud network charts alone.

## External service facts to re-check

These service facts are current as of 2026-07-03 and should be re-checked
before spending money or publishing a public relay:

- [PlayFab Party overview](https://learn.microsoft.com/en-us/xbox/playfab/multiplayer/networking/)
  describes Party as multiplayer networking with transparent cloud relay,
  selectable Azure regions, direct peer functionality, authentication/encryption,
  and background QoS measurements.
- [PlayFab Party features](https://learn.microsoft.com/en-us/xbox/playfab/multiplayer/networking/party-features)
  describe the cross-platform mesh as transparent cloud relay or selected Azure
  regions, with direct peer connectivity as an alternative.
- [PlayFab Party QoS measurements](https://learn.microsoft.com/en-us/gaming/playfab/multiplayer/networking/concepts-regions)
  support region selection based on measured latency for Party networks.
- [PlayFab Party direct peer connectivity](https://learn.microsoft.com/en-us/xbox/playfab/multiplayer/networking/concepts-direct-peer-connectivity)
  explains how direct peer connections can be enabled and what tradeoffs to
  evaluate.
- [PartyNetworkConfiguration](https://learn.microsoft.com/en-us/gaming/playfab/multiplayer/networking/reference/structs/partynetworkconfiguration)
  documents direct peer configuration and notes that devices can opt out of IP
  address disclosure and direct connection attempts through their local mask.
- [PartyDeviceConnectionType](https://learn.microsoft.com/en-us/xbox/playfab/multiplayer/networking/reference/enums/partydeviceconnectiontype)
  distinguishes relay-server communication from direct peer connections.
- [List Party QoS Servers](https://learn.microsoft.com/en-us/rest/api/playfab/multiplayer/multiplayer-server/list-party-qos-servers)
  exposes Party QoS server metadata through the PlayFab Multiplayer REST API.
- [Steam Datagram Relay](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay)
  already exists to relay game traffic over Valve's network and can improve
  routing for some players, so any Party or custom Azure route must beat or
  complement it in measured SC6 sessions.
- [Azure network round-trip latency statistics](https://learn.microsoft.com/en-us/azure/networking/azure-network-latency)
  publish P50 inter-region RTTs from Azure internal probes. They are useful for
  planning, not a guarantee for residential-player routes.
- [Azure Load Balancer](https://learn.microsoft.com/en-us/azure/load-balancer/load-balancer-overview)
  supports TCP and UDP flows for VM/VMSS backends at layer 4.
- [Azure Container Instances YAML](https://learn.microsoft.com/en-us/azure/container-instances/container-instances-reference-yaml)
  exposes port protocol as TCP or UDP for container groups.
- [Azure Container Apps ingress](https://learn.microsoft.com/en-us/azure/container-apps/ingress-overview)
  is HTTP/TCP-oriented, not raw UDP.
- [Azure Relay Hybrid Connections](https://learn.microsoft.com/en-us/azure/azure-relay/relay-what-is-it)
  are based on HTTP and WebSockets.
- [Azure Web PubSub](https://learn.microsoft.com/en-us/azure/azure-web-pubsub/overview)
  is a WebSocket/pub-sub service for real-time messaging, not a UDP game relay.

## Decision

Prototype PlayFab Party first as a measured managed transport/control option
for a mod-owned SC6 input transport.

Do not market it as removing America-Europe propagation latency. The honest
claim to test is that Party might reduce avoidable route inefficiency and
produce a steadier route, better session/region selection, or a safer relay
fallback for some bad direct/Steam pairs. If the mod cannot own the SC6 input
transport boundary, if Party cannot be integrated safely, or if Party does not
improve frame-aware route quality in real tests, stop at documentation and local
diagnostics. Build a raw Azure VM/VMSS relay only as a lower-level custom
data-plane fallback with a specific measured reason.
