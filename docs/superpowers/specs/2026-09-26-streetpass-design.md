# StreetPass — design spec

Date: 2026-09-26
Branch: `feat/streetpass`
Status: approved for planning

## Goal

StreetPass detects when two compatible BUMP users pass within close Ultra
Wideband proximity of each other and surfaces a lightweight teaser
encouraging them to go bump. It is a stateless, local-first, self-contained
iOS demo feature: no backend endpoints, no server-side encounter tracking, no
persistent StreetPass history, no remote user lookup, no backend matching, no
databases, no new authentication.

Copy (approximate, following the app's existing tone — no em dashes):

> hey, this person just walked by you. bump them?
> you both like photography   *(only when exactly one mutual interest exists — never invented, never more than one, omitted entirely when there are none)*

Never reveals a full profile before both people explicitly bump.

## Decisions made during brainstorming

These were resolved through discussion before this spec was written; they are
constraints, not options to revisit during implementation:

1. **Locked-phone detection is explicitly out of scope for this iteration.**
   Ultra Wideband peer-to-peer ranging (`NISession`/`NearbyInteraction`)
   cannot run while the app is backgrounded on stock iOS — there is no
   background API for phone-to-phone NI ranging (unlike MFi/accessory NI,
   which needs an entitlement Apple does not grant to consumer peer-to-peer
   apps). Building "UWB while locked" is not achievable regardless of
   architecture. The user explicitly chose to defer this ("completely ignore
   implementing streetpass while locked, we will deal with it later") rather
   than build the Bluetooth-presence fallback that would be needed for a true
   locked-phone signal.
2. **StreetPass scanning is always-on while the app is foregrounded** (once
   the user has a complete profile) — no separate on/off toggle for this
   iteration.
3. **StreetPass uses its own, separate MultipeerConnectivity service**
   (`bump-streetpass`), fully isolated from the existing room/coordinator
   transport (`PeerTransport`, service `bump-uwb`). It auto-connects to any
   nearby StreetPass peer — no room code, no scoping — which is a
   deliberately different trust model from `PeerTransport`'s "never connect
   to the first discovered phone" rule, and is exactly why it needs its own
   transport rather than reusing the existing one.
4. **The foreground UX is a custom in-app sheet/card**, not the system
   notification banner. A system local notification is only fired when the
   app is not active at the moment of a qualifying encounter (the narrow
   transition-window case, e.g. the user locks the phone a moment after the
   encounter began); it is not a substitute for true locked-phone detection,
   which is deferred per (1).
5. **Tapping "Bump them" routes into the existing nearby-room flow**
   (`engine.startNearby()`) rather than auto-selecting the peer via manual
   pick or building a bespoke direct-confirm path. `proposeManually` only
   works for the room coordinator today, and StreetPass should not inherit
   that limitation. The user still completes the existing, unmodified,
   already-tested physical-tap-to-confirm pipeline afterward — StreetPass is
   a heads-up that this person is worth going to bump, not an automatic
   pairing bypass.
6. **"Compatible" means simply "another nearby device running BUMP with a
   complete profile."** No compatibility filtering algorithm is introduced.

## Non-goals (explicit)

- No backend endpoints, server-side encounter tracking, or remote matching.
- No persistent StreetPass encounter history (nothing is written to disk;
  everything lives in memory for the session and resets naturally on peer
  disconnect or process termination, same as the rest of the app's in-memory
  bump state).
- No new entitlements, no `UIBackgroundModes`.
- No Bluetooth-only presence fallback for the locked-phone case (deferred).
- No changes to `PeerTransport`, `RangingService`, `BumpEngine`'s room and
  pairing logic, or the confirm/exchange/reveal pipeline. StreetPass hands
  off into that pipeline unchanged.

## Architecture

New files, all under `ios/UWBBumpTest/Service/StreetPass/` unless noted,
mirroring the existing `Service/` convention (small, single-purpose,
framework code kept thin around pure/testable logic):

### 1. `StreetPassConfig.swift`
Centralized tunables, analogous to `RangingService.Config` /
`PairingMatcher.Config`:
- `proximityThreshold: Double` (metres) — experimental, adjustable.
- `consecutiveReadingsRequired: Int` — debounces a single noisy reading.
- `exitHysteresisMargin: Double` — the peer must clearly exceed
  `proximityThreshold + exitHysteresisMargin` before the gate can rearm.
- `cooldown: TimeInterval` — minimum time between two triggers for the same
  peer even after rearming.
- `maxConcurrentPeers: Int` (e.g. 3) — independent from
  `RangingService.maxConcurrentPeers` (4), so the two subsystems never
  contend for whatever practical ranging-session ceiling the hardware has.
- `measurementFreshness: TimeInterval` — same purpose as
  `RangingService.Config.freshness`.

### 2. `StreetPassPeerProfile.swift` (Model)
The ambient broadcast payload — deliberately smaller than `SharedProfile`
since it crosses the wire to any nearby stranger's phone before any mutual
confirmation:
```swift
struct StreetPassPeerProfile: Codable, Equatable, Sendable {
    let id: String            // transient, session-scoped, not a stable user id
    let displayName: String
    let avatarThumbnail: Data? // small, reuses ProfilePhoto-style bounding
    let interestIDs: [String] // canonical ids only, capped (e.g. 5)
}
```
No bio, no experiences/goals, no evidence text, no cloud-processing
preference — those remain partner-only, post-confirmation, exactly as today.

### 3. `StreetPassTransport.swift`
MultipeerConnectivity wrapper, new and separate from `PeerTransport`:
- Service type `bump-streetpass` (new `NSBonjourServices` entries:
  `_bump-streetpass._tcp` / `._udp`).
- Advertises and browses continuously while running.
- Auto-invites/accepts **any** discovered StreetPass peer, bounded by
  `maxConcurrentPeers` (refuses beyond the cap, mirroring
  `RangingService.prepareSession`'s cap behavior) — no room code, no
  scoping, unlike `PeerTransport`.
- Once connected, exchanges `StreetPassPeerProfile` and an archived
  `NIDiscoveryToken` over a small, versioned, bounded envelope (same shape
  as `Wire`: version tag, unique id for idempotent duplicate-drop, frame size
  cap) — a new, separate enum, not an extension of `Wire.Body`.

### 4. `StreetPassRanging.swift`
One `NISession` per connected peer. Same lifecycle pattern as
`RangingService` (pause on background, resume on foreground, invalidate and
clean up on disconnect/suspension, stale-measurement expiry, capability
checked at runtime via `NISession.deviceCapabilities`). Kept as its own
class rather than generalizing `RangingService` — deliberate, to avoid
risking regressions in the existing, well-tested bump ranging pipeline for
the sake of a shared abstraction neither side actually needs yet.

### 5. `StreetPassEncounterGate.swift`
Pure, unit-testable per-peer state machine, no framework dependency —
same shape as `SpikeGate`:
```swift
struct StreetPassEncounterGate {
    // config: threshold, consecutiveReadingsRequired, exitHysteresisMargin, cooldown
    mutating func feed(distance: Double, now: TimeInterval) -> Verdict
    // Verdict: .qualified, .accumulating(count), .cooldown, .awaitingExit, .idle
}
```
Semantics:
- Requires `consecutiveReadingsRequired` consecutive readings
  `<= proximityThreshold` before qualifying (debounces a single noisy blip).
- Fires `.qualified` once per encounter (latches).
- Cannot fire again until the peer's distance clearly exceeds
  `proximityThreshold + exitHysteresisMargin` (hysteresis) — sustained
  standing-still proximity does not refire.
- Even after rearming, `cooldown` suppresses an immediate refire.
- Caller supplies a monotonic `now`, exactly like `SpikeGate`.

### 6. `StreetPassEngine.swift`
`@MainActor final class StreetPassEngine: ObservableObject`, thin
orchestrator (not a "God object" — every actual decision lives in the pieces
above):
- Owns one `StreetPassTransport`, one `StreetPassRanging`, and a
  `[String: StreetPassEncounterGate]` keyed by peer id.
- `@Published private(set) var pendingEncounter: StreetPassEncounter?`
- Starts only when the user's profile is complete **and** the app is
  active; pauses ranging when the app leaves `.active` while keeping the
  transport connection and each peer's gate (cooldown/latch) state alive —
  mirrors `BumpEngine.handleScenePhase`'s existing foreground-only policy
  (see **Backgrounding** below). That state resets only on a real peer
  disconnect or process termination.
- On a gate's `.qualified` verdict: computes
  `InterestMatcher.overlap(mine: [Interest], theirs: [Interest], limit: 1)`
  and sets `pendingEncounter`.
- On peer disconnect: removes that peer's gate, ranging session, and
  clears `pendingEncounter` if it belonged to that peer.
- `StreetPassEncounter` (new, ephemeral, in-memory only, never persisted):
  ```swift
  struct StreetPassEncounter: Identifiable, Equatable {
      let id: String            // peer's transient id
      let displayName: String
      let avatarThumbnail: Data?
      let mutualInterestLabel: String?   // at most one, nil if none
  }
  ```

### 7. `InterestMatcher.swift` — small addition
Add an overload:
```swift
static func overlap(_ mine: [Interest], _ theirs: [Interest], limit: Int = 3) -> [SharedHighlight]
```
The existing `overlap(_ a: SharedProfile, _ b: SharedProfile, limit:)` calls
this new overload internally. Non-breaking: existing signature, behavior,
and tests are untouched. This lets StreetPass compute the single-interest
teaser without fabricating a dummy `SharedProfile`.

### 8. `StreetPassNotifier.swift`
Thin `UNUserNotificationCenter` wrapper:
- Requests notification authorization once, the first time
  `StreetPassEngine` starts (lazily, not at app launch).
- Pure copy-building function (testable without `UNUserNotificationCenter`):
  ```swift
  static func copy(for encounter: StreetPassEncounter) -> (title: String, body: String)
  ```
- **Only actually schedules a system notification when the app is not
  active** at the moment of qualification. When active, `StreetPassEngine`
  sets `pendingEncounter` directly and the UI shows the custom sheet — no
  redundant banner-then-sheet double delivery.
- `UNUserNotificationCenterDelegate.didReceive` handles a tap: brings the app
  to the foreground normally; if the peer is still tracked in
  `StreetPassEngine`, `pendingEncounter` is (re)populated fresh from current
  state — never from stale data cached in the notification payload.

### 9. `View/StreetPassSheet.swift`
New view, styled like `ConfirmPartnerView`: avatar + display name, the fixed
teaser copy, the optional single mutual-interest line, two actions:
- **"Bump them"** → `engine.startNearby()` (the existing `BumpEngine`
  nearby-room flow) and dismiss the sheet. The user then completes the
  existing, unmodified physical-tap-to-confirm pipeline.
- **"Not now"** → dismiss only; the gate stays latched (per hysteresis) so
  it won't immediately refire for the same peer.

### 10. `RootView` wiring
`RootView` owns a `@StateObject var streetPassEngine: StreetPassEngine`
alongside the existing `BumpEngine`, starts it once `stage == .main` and the
profile is complete, and ties its lifecycle to the same
`.onChange(of: scenePhase)` handler. Presents
`.sheet(item: $streetPassEngine.pendingEncounter) { StreetPassSheet(...) }`
at the root level so it can appear over any tab.

## Data flow

```
App active + profile complete
  -> StreetPassTransport (separate service, auto-connect to any nearby StreetPass peer, capped)
      -> exchange StreetPassPeerProfile + NIDiscoveryToken over the direct link
      -> StreetPassRanging -> distance readings -> StreetPassEncounterGate[peerID]
          -> .qualified -> InterestMatcher.overlap(mine, theirs, limit: 1)
              -> StreetPassEngine.pendingEncounter
                  -> foreground: StreetPassSheet (custom in-app card)
                  -> backgrounded at that instant: local notification (best-effort transition-window case only)
  -> "Bump them" -> engine.startNearby() (existing nearby room), dismiss sheet
       -> user proceeds with the existing, unmodified physical-tap-to-confirm pipeline
  -> "Not now" -> dismiss; gate stays latched until hysteresis/disconnect clears it
```

## Error handling / edge cases

- **Peer disconnects** at any point: its gate, ranging session, and (if
  relevant) `pendingEncounter` are cleared immediately. No lingering state,
  no persisted trace.
- **Device without UWB support**: `StreetPassRanging` reports unsupported at
  init (same `NISession.deviceCapabilities` check `RangingService` already
  does); StreetPass simply never triggers on that device. No Bluetooth-only
  fallback is added (explicitly deferred, decision 1).
- **Backgrounding**: `StreetPassEngine` pauses ranging (`StreetPassRanging.pauseAll()`)
  the moment `scenePhase` leaves `.active`, matching what `BumpEngine` actually
  does — `BumpEngine.handleScenePhase` only pauses its own ranging and stops
  motion sensing on `.background`/`.inactive`; it never disconnects its room
  transport. StreetPass follows the same shape: the transport connection and
  each peer's `StreetPassEncounterGate` state (cooldown/latch) stay alive
  through a transient `.inactive` (a momentary system interruption — an
  incoming call, Control Center, the app switcher — is not a real departure
  from foreground use), so a brief interruption cannot cause a peer already
  in range to trigger a duplicate encounter. State only truly resets when a
  peer disconnects or the process itself is suspended/terminated by iOS,
  consistent with "resetting only after the peer has clearly moved away or
  disconnected."
- **Notification tap after a cold relaunch**: the app just opens normally.
  Since nothing is persisted, if the peer happens to still be in range the
  gate re-evaluates fresh (starting its consecutive-reading count over) —
  it does not replay a stale cached encounter.
- **Over the concurrent-peer cap**: additional discovered peers are refused
  connection until a slot frees up (mirrors `RangingService`'s existing
  cap-refusal behavior), rather than silently dropping an existing session.

## Testing

- `StreetPassEncounterGateTests` — consecutive-reading requirement, hysteresis
  rearm boundary, cooldown suppression, one-trigger-per-encounter, reset on
  simulated disconnect. Pure, no hardware, same style as `SpikeGateTests`.
- `InterestMatcher` — a test asserting the new `[Interest]` overload never
  returns more than `limit` highlights and correctly returns empty for no
  overlap (zero/one/many-collapsed-to-one).
- `StreetPassNotifier.copy(for:)` — pure function test: base copy always
  present; second line present only when `mutualInterestLabel != nil`; never
  more than the one interest line.

## Out of scope for this iteration (explicitly deferred)

- True locked-phone / background detection (needs a Bluetooth-presence
  fallback + background modes entitlement — a materially different,
  lower-fidelity signal than UWB; deferred per decision 1).
- A Testing-tools panel for StreetPass tuning (the existing `TestingToolsScreen`
  pattern would be the natural home if this becomes needed later).
- Any backend involvement whatsoever.
