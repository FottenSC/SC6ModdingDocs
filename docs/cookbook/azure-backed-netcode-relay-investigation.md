# Azure-Backed Netcode Relay Investigation

**Goal**: decide whether an Azure-backed relay could improve SC6 online play
between America and Europe by carrying fight-input traffic over a better route
or by reducing jitter/loss.

**Evidence source**: the existing
[Rollback Netcode Feasibility Investigation](rollback-netcode-investigation.md),
[Automated Rollback Netcode Testing on One Machine](automated-rollback-netcode-testing.md),
and current Azure/Steam/PlayFab service documentation checked on 2026-07-03.
This page is documentation-only. It does not implement or recommend redirecting
stock SC6 traffic until the transport boundary is actually owned and measured.

## Verdict

An Azure relay is worth investigating as a **route-quality fallback**, not as a
magic ping reducer.

It cannot beat the speed-of-light floor between North America and Europe. It
also cannot make a good direct peer route faster just by inserting a cloud VM in
the middle. A relay only has a chance to help when at least one of these is
true:

- the direct ISP path is bad, congested, or hairpinned through poor transit;
- Steam Datagram Relay chooses a worse path than an Azure route for this pair;
- direct peer connectivity is unreliable and the relay provides lower jitter,
  less loss, or fewer burst stalls even with similar median RTT;
- the project owns a custom transport and can choose direct, Steam/Party, or
  Azure per match.

The biggest blocker is not Azure. It is transport ownership. The rollback
investigation shows that stock SC6 online packets are tiny input-cache packets
inside the existing Steam/online path. If the mod cannot replace or wrap the
fight-input transport at a game-thread-safe boundary, an Azure relay cannot
transparently redirect stock SC6/Steam traffic in a clean way.

Practical verdict:

| Question | Current answer |
|---|---|
| Can Azure reduce unavoidable US<->EU propagation delay? | No. Any relay adds at least one extra hop. |
| Can Azure beat bad direct peering? | Sometimes, but only if measured end-to-end jitter/loss/RTT improves. |
| Can this work with stock SC6 transport unchanged? | Unproven and unlikely. Treat stock Steam transport as not redirectable until proven otherwise. |
| Best Azure data-plane candidate | Custom UDP relay on Azure VMs/VMSS, with Azure Load Balancer only if scaling needs it. |
| Best control-plane candidates | PlayFab/Party, Web PubSub, Azure Functions, or a small custom HTTPS service for signaling, allocation, auth, and telemetry. |
| Services to avoid for fight-input UDP | Azure Relay Hybrid Connections and Azure Web PubSub; they are HTTP/WebSocket-style services, not raw UDP game relays. |
| First prototype | Out-of-game UDP route measurement plus a local rollback transport shim, before touching real ranked/online SC6 sessions. |

## Latency math

For a fighting game, median ping is not enough. A stable 90 ms RTT can feel
better than a 75 ms route with 40 ms jitter bursts, but the physical floor still
matters.

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

For a single midpoint relay, an application-level ping through the relay is
approximately:

```text
relay_rtt ~= client_a_to_relay_rtt + client_b_to_relay_rtt
```

For a two-region relay path where each player uses a nearby Azure edge region
and the relay servers forward over the Azure backbone:

```text
relay_rtt ~= client_a_to_region_a_rtt
          + azure_region_a_to_region_b_rtt
          + client_b_to_region_b_rtt
```

That formula is why a relay usually loses against a good direct route. It wins
only if the direct route is worse than the sum of the relay legs, or if jitter
and loss are low enough to justify a similar median RTT.

Azure's own public inter-region latency table is a useful sanity check, not a
player-route guarantee. The 2026-07-02 dataset lists P50 inter-region RTTs from
Azure internal probes; for example, East US to West Europe is in the high
80 ms range, and East US to North Europe / UK South is in the mid-to-high
70 ms range. Residential-player-to-Azure legs must be added on top.

## Relation to SC6 rollback work

The relay question depends on the rollback investigation in three ways:

- Stock SC6 online play is delay/catch-up based. A relay can reduce transport
  instability, but it does not create rollback.
- A useful custom transport still needs absolute frame ids, confirmations,
  prediction age, state hashes, queue policy, and desync policy. The stock
  3-byte packet hot paths are not enough for a full rollback protocol.
- Input cache writes must happen at a game-thread-owned boundary. Do not write
  `FLuxReplayInputCacheEntry` cells from a network receive thread.

So the relay prototype should be treated as a transport experiment layered
after the local rollback lab proves deterministic restore/resimulation and
input ownership.

## Candidate Azure approaches

### Regional UDP relay on Azure VMs or VMSS

This is the most realistic data-plane option.

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

Minimum relay behavior:

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

Containers are plausible for packaging the relay binary, but the Azure product
choice matters.

| Service | Fit for fight-input relay |
|---|---|
| Azure Container Instances | Possible for small UDP experiments; its container group schema allows TCP or UDP ports. Validate public IP stability, restart behavior, observability, and cold-start impact before relying on it. |
| Azure Container Apps | Poor fit for raw UDP. Its ingress model is HTTP and TCP, with WebSocket/gRPC under HTTP, not UDP. Useful for control-plane APIs, not fight-input packets. |
| AKS | Possible but heavy for the first prototype. Consider only after VM/ACI tests prove the relay helps and operational scale matters. |

For a fighting-game relay, predictable process scheduling and stable network
behavior matter more than container convenience. Start with VMs unless there is
a strong operational reason not to.

### PlayFab Party, matchmaking, or signaling

PlayFab Party is a candidate if the project is willing to integrate a new
library-level transport. Party can use cloud relay paths, can optionally attempt
direct peer connectivity on supported platforms, and exposes QoS measurements
for region selection. That is relevant to the exact problem this page is
asking about.

Limits:

- it is not a transparent redirector for stock SC6 online packets;
- it would need native integration and session/auth handling;
- direct peer mode can expose peer IP addresses, which is a security/privacy
  tradeoff;
- cloud relay mode may be safer but still needs measured latency against
  Steam/SDR/direct/custom Azure routes.

PlayFab or a custom HTTPS/WebSocket service can also be used only as a
control plane:

- create match/session ids;
- exchange relay tokens;
- report candidate regions and QoS samples;
- choose direct vs Azure relay vs fallback;
- publish telemetry and failure summaries.

That control plane should not carry per-frame fight inputs.

### Azure Relay and Azure Web PubSub

These are not good data-plane choices for SC6 fight-input traffic.

Azure Relay Hybrid Connections are based on HTTP and WebSockets. Azure Web
PubSub is a managed WebSocket/pub-sub service. Both can be useful for signaling,
dashboards, test orchestration, support tools, or route-selection control
messages. They should not be used as the real-time UDP input stream unless the
goal is only a diagnostic prototype that intentionally measures how bad that
shape is.

Do not put a rollback input stream through WebSocket just because the service
is convenient. The stock and rollback paths need low-overhead, frame-aware,
loss/jitter-aware delivery.

### TURN-like fallback

A custom Azure relay can behave like a game-specific TURN fallback:

1. Try direct/custom P2P if the mod owns a safe transport and policy allows it.
2. If direct fails or route quality is poor, allocate a regional relay.
3. Keep the peer identities hidden from each other where possible.
4. Expire the allocation at match end or after inactivity.
5. Continue measuring direct and relay candidates out of band so the session can
   choose the best route before round start.

This is useful for NAT and route stability. It is not automatically faster than
direct play, and it is not a substitute for rollback determinism.

## Architecture

Separate the control plane from the data plane.

| Layer | Responsibility | Candidate Azure services |
|---|---|---|
| Data plane | Per-frame UDP input transport, relay allocation, packet forwarding, route health, abuse limits. | Azure VMs/VMSS first; Azure Load Balancer only for scale/HA; ACI only for narrow experiments. |
| Control plane | Auth/session ids, relay tokens, region list, route-test orchestration, match policy. | PlayFab, small HTTPS API, Azure Functions, Web PubSub, or Azure Relay. |
| Telemetry plane | Aggregate route metrics, failure capsules, dashboards, support bundles. | Application Insights / Log Analytics style pipeline, or simple blob/JSONL artifacts for early tests. |
| Game integration | Input ownership, prediction/confirmation, state hashes, rollback/stall policy. | Native SC6 mod hooks; not an Azure responsibility. |

Recommended first topology:

```text
player A mod/harness
  -> direct UDP test to player B harness
  -> UDP test to Azure candidate regions

player B mod/harness
  -> direct UDP test to player A harness
  -> UDP test to Azure candidate regions

control service
  -> collects p50/p95/p99 RTT, jitter, loss, burst loss, reorder
  -> chooses direct or relay for this test session

Azure UDP relay VM
  -> forwards only session-tokened packets
  -> logs aggregate metrics and packet metadata, not raw inputs
```

Do not start by trying to intercept an encrypted or opaque Steam transport.
Start with an out-of-game UDP echo and a mod-owned loopback transport shim that
uses the same metrics and packet schema planned for the real rollback protocol.

## Region strategy

Candidate initial regions:

| Region | Why test it |
|---|---|
| East US / East US 2 | Best first guess for US East Coast to Europe. Also a likely midpoint for many US players. |
| North Europe / UK South / West Europe | Good European candidates for EU players and US East routes. |
| Central US | Useful when the American player is not near the East Coast. |
| West US / West US 2 | Useful for West Coast players, but do not expect Europe latency miracles. |

Measure these per player pair:

- direct peer RTT/jitter/loss where available;
- client A to each Azure region;
- client B to each Azure region;
- relay end-to-end through each single region;
- optional two-region relay path if there is evidence Azure backbone helps;
- Steam/SDR-visible metrics if the game or Steam APIs expose them cleanly.

Choose direct by default. Choose Azure only when the measured route is clearly
better for the current pair and region.

## Prototype plan

### Phase 0: define the claim

Write down the exact hypothesis before deploying anything:

```text
For America-Europe pairs with unstable direct/Steam routing, an Azure relay
can reduce p95/p99 jitter, burst loss, or over-window late inputs enough to
improve SC6 match quality, even if median RTT is unchanged or slightly worse.
```

This avoids optimizing for a headline ping number that does not matter in
gameplay.

### Phase 1: out-of-game route measurement

Build no SC6 hooks yet. Use a small UDP echo/relay harness between real test
machines and Azure candidate regions.

Record:

- direct peer RTT if both peers can receive UDP;
- A-to-region and B-to-region RTT;
- A-to-B through one relay region;
- A-to-B through two Azure regions, only if implemented;
- p50/p95/p99 RTT;
- jitter in milliseconds and 60 fps frame units;
- packet loss, burst loss, reorder, duplicate count, and queue delay;
- local ISP/ASN only if explicitly opted in for support data.

Run each sample long enough to catch bursts. A 10-second ping test is not
enough; use at least 5 to 10 minute windows for route decisions and longer
soak tests for claims.

### Phase 2: local transport shim

Reuse the automated rollback testing page's loopback shim idea. Put the relay
protocol behind a local shim before using Azure:

- absolute input frame id;
- sequence id and send timestamp;
- prediction/confirmation markers;
- payload hash/checksum;
- state-hash side channel where the rollback lab supports it;
- deterministic fault injection for delay, jitter, loss, reorder, duplicates,
  and corruption.

This phase proves protocol behavior without cloud noise.

### Phase 3: one-region Azure relay MVP

Deploy one relay VM in the most promising region. Keep it boring:

- one relay process;
- one UDP port range;
- one HTTPS control endpoint for allocations and health;
- short-lived session tokens;
- per-session packet counters and aggregate metrics;
- no raw input or payload logging;
- hard rate limits per session and per source.

Pass condition: the same fault and route metrics from the local shim still line
up with gameplay/input logs when packets traverse the Azure relay.

### Phase 4: multi-region route selection

Add region choice only after one-region tests are useful.

Selection should compare:

- direct route;
- each single-region relay;
- optional two-region Azure backbone route;
- rolling jitter/loss, not only median RTT;
- cost and regional capacity.

Do not switch routes mid-round in the first version. Select before the match or
between rounds, then hold the route stable unless the current route fails badly
enough to justify a reconnect/resync policy.

### Phase 5: SC6 online experiment

Only after local rollback determinism and the transport shim are stable:

1. Run unranked/lab sessions only.
2. Require identical SC6/mod/build manifests.
3. Keep the stock SC6 online path disabled or bypassed for the test transport
   unless the stock path integration has been proven safe.
4. Compare direct/custom transport vs Azure relay using identical scripted
   input scenarios first, then real inputs.
5. Treat desync, over-window late input, or route-switch failure as hard test
   failures.

## Instrumentation

Use frame-aware metrics. Network logs must align with gameplay logs from the
rollback testing page.

| Log | Include | Why |
|---|---|---|
| Route probe | Pair id, candidate route, region, p50/p95/p99 RTT, jitter, loss, burst loss, reorder, duplicates, sample count, window duration. | Chooses route based on quality, not guesswork. |
| Relay packet log | Session id hash, packet sequence, input frame, arrival timestamp, forward timestamp, source leg, destination leg, packet size, payload hash. | Separates server processing from network delay without storing raw inputs. |
| Input history | Intended input, consumed input, predicted/confirmed bit, absolute frame, slot, arrival frame. | Shows whether network delivery improved actual game input ownership. |
| Rollback pressure | Rollback depth, prediction age, correction count, over-window late inputs, stalls, desync hashes. | Converts network quality into gameplay impact. |
| Stock-path comparison | Existing SC6/Steam-visible ping/stall counters where safely observable, including `BM+0x1638` stall behavior. | Compares Azure against the path players actually use today. |
| Cost/ops | VM size, region, egress, CPU, packets/sec, active sessions, dropped packets, process restarts. | Prevents a technically good route from becoming an unsustainable service. |

Telemetry should report rolling windows. Store raw debug traces only in local or
explicit opt-in support bundles.

## Risks

| Risk | Consequence | Mitigation |
|---|---|---|
| Speed-of-light floor | Relay cannot make US<->EU faster than physical distance allows. | Publish route-quality criteria and refuse to claim impossible ping reductions. |
| Stock transport ownership | The mod may not be able to redirect SC6/Steam traffic cleanly. | Build only against a mod-owned transport boundary; stop if that boundary does not exist. |
| Steam Datagram Relay already helps | Azure might be worse than SDR for many users. | Measure direct, SDR-visible, and Azure candidates before choosing a route. |
| Extra hop increases median RTT | Better jitter can still come with worse average ping. | Decide using p95/p99 jitter/loss and rollback pressure, not median RTT alone. |
| NAT/firewall behavior | Some peers may not receive direct UDP or may have unstable mappings. | Use the relay as fallback, keep keepalives explicit, and test varied home networks. |
| Abuse and DDoS | A public UDP relay can be attacked or used to amplify traffic. | Session tokens, packet size limits, no reflection behavior, rate limits, source validation, and short allocation lifetimes. |
| Privacy | IPs, session ids, or input streams could identify players or reveal gameplay data. | Minimize logs, hash session ids, avoid raw inputs, keep support bundles opt-in. |
| Cost | Inter-region egress and always-on VMs can become expensive. | Prototype with small quotas, shut down idle relays, and add cost gates before public tests. |
| Route instability | Best region can change by time of day or ISP event. | Re-measure per session and keep historical aggregates separate from live route choice. |
| Legal/ToS uncertainty | Redirecting or intercepting stock online traffic may be unacceptable. | Keep tests unranked/opt-in, do not bypass Steam auth or DRM, and require a legal review before any public service. |

## Privacy and ToS boundaries

Keep the prototype conservative:

- Do not capture or upload raw SC6 input streams as routine telemetry.
- Do not log public IP addresses in long-term analytics unless a user explicitly
  provides a support bundle.
- Hash peer/session ids with a per-session salt or omit them.
- Treat local adapter type, ISP, ASN, and country as optional support context,
  not matchmaking policy.
- Disclose when a session uses an Azure relay.
- Do not use the relay to bypass Steam authentication, matchmaking ownership,
  region locks, DRM, or SC6 online policy.
- Do not intercept encrypted Steam traffic and claim it is a supported
  transport. Own the transport boundary or stop.

This page is not legal advice. It is a technical risk list for deciding whether
a prototype is safe enough to run.

## Decision criteria

Use explicit gates before moving from lab to real online tests.

### Continue if

- direct/Steam routes for real America-Europe test pairs show recurring jitter,
  loss, or route spikes that affect rollback pressure or stalls;
- an Azure route reduces p95/p99 jitter or burst loss enough to lower
  prediction age, rollback depth, stalls, or over-window late inputs;
- median RTT is no worse than direct by a small agreed margin, or the jitter/loss
  improvement is large enough to justify the tradeoff;
- the mod owns a safe game-thread transport boundary;
- privacy, abuse controls, and cost limits are in place.

### Stop or defer if

- the relay only improves a synthetic ping test and not gameplay/input metrics;
- direct/SDR is already better for most target pairs;
- the only viable approach is transparent interception of stock Steam traffic;
- route selection requires mid-round switching before rollback/resync policy is
  solved;
- logging or operations would collect more player data than the project needs;
- Azure cost per active match is not acceptable.

Suggested numeric starting gates:

| Metric | Continue threshold |
|---|---|
| p95/p99 jitter | Relay reduces spikes by at least one 60 fps frame on problem routes. |
| Burst loss | Relay cuts burst-loss events by at least half on measured bad routes. |
| Median RTT | Relay is within roughly 5 to 10 ms of direct, unless jitter/loss wins are large. |
| Rollback pressure | Fewer over-window late inputs or fewer stalls under identical scripted input tests. |
| Stability | No unexplained desyncs across long unranked soak tests. |
| Operations | Relay survives rate limits, reconnects, idle expiry, and process restarts without silent packet misdelivery. |

Treat these numbers as first-pass gates. Real thresholds should be tuned from
SC6 rollback logs, not from cloud network charts alone.

## External service facts to re-check

These service facts are current as of 2026-07-03 and should be re-checked
before spending money or publishing a public relay:

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
- [PlayFab Party direct peer connectivity](https://learn.microsoft.com/en-us/xbox/playfab/multiplayer/networking/concepts-direct-peer-connectivity)
  can use transparent cloud relay paths and optional direct peer connectivity,
  with IP-disclosure tradeoffs for direct mode.
- [PlayFab Party QoS measurements](https://learn.microsoft.com/en-us/xbox/playfab/multiplayer/networking/concepts-regions)
  support region selection based on measured latency.
- [Steam Datagram Relay](https://partner.steamgames.com/doc/features/multiplayer/steamdatagramrelay)
  already exists to relay game traffic over Valve's network and can improve
  routing for some players, so any Azure route must beat or complement it in
  measured SC6 sessions.

## Decision

Prototype the relay only as a measured fallback for a mod-owned transport.

Do not market it as "better America-Europe ping." The honest claim to test is
that Azure might produce a steadier route for some bad direct/Steam pairs. If
the mod cannot own the SC6 input transport boundary, or if Azure does not
improve frame-aware route quality in real tests, stop at documentation and
local diagnostics.
