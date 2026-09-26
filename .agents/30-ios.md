# ios/ — the BUMP app (the actual product)

Swift + SwiftUI. **Requires a Mac with Xcode 26+ and two physical iPhones.**
Not buildable from this WSL/Windows machine — treat `ios/` as read-only context
unless you are on the Mac. Deployment target iOS 17. UWB and on-device AI are
both optional and degrade cleanly. The Simulator cannot validate UWB or motion.

`open ios/UWBBumpTest.xcodeproj` then follow `ios/README.md` for signing.

**UI design work happens in `ios-mockup/` first** (the human has no Mac). It is an
HTML version of every screen and state, restyled in the marketing site's
language with the brand kept (details, history and traps: `31-ios-mockup.md`).
`tokens.css` keeps the `Theme.swift` names, `screens.js` keeps the Swift copy and
names each view's file. The site-style redesign has been ported to Swift but
has not been built with Xcode. If you
change a Swift view's layout or copy, update the mockup too, or the two drift.

`main` now adds automatic nearby listening, a server relay fallback, StreetPass,
Live Activities, and a notifications feed. The local merge into
`ios-mockup-vis-charan` preserves the site-style SwiftUI screens and adds those
behaviors. Build and inspect the merged app on a Mac before treating the UI or
two-phone flow as verified.

## Server URL on test phones

The backend runs on a Mac for phone tests. `20-backend.md` has the two-terminal
server and Cloudflare quick tunnel commands. The tunnel URL changes on restart.
The app's default is `BUMP_API_BASE_URL` in
`ios/UWBBumpTest.xcodeproj/project.pbxproj`, with separate Debug and Release
values. `Info.plist` exposes it as `BumpAPIBaseURL`. Keep the current default
unless the human asks to update it. If the tunnel changes, put the new HTTPS
URL in **both** build configurations, check its `/healthz` response has
`"grokConfigured":true` and `"relay":true`, then rebuild and reinstall the
app. For a test without rebuilding, set the Server URL override in **Testing
tools on each phone**.

As of this local merge, both build settings read `http://localhost:8787`.
That address points to the phone itself on a physical iPhone; use the tunnel
URL or the Server URL override for two-phone tests.

## The journey

Create a profile → BUMP automatically listens for nearby phones → bump phones →
both confirm → shared interests + a conversation opener → save the connection.

| Screen | What it does |
|---|---|
| Welcome | hero wordmark, one action |
| Onboarding | name → spoken intro (≤45 s, or type) → up to 3 follow-ups → an editable card you approve |
| Bump | Automatic nearby listening, first-run tour, readiness status, nearby list, error states, manual pick. Event codes behind "Have an event code?" |
| StreetPass | A nearby teaser card for a qualifying encounter; full overlap still requires a confirmed bump. |
| Notifications | Local feed of bumps and passers-by. |
| Confirm partner | "Did you bump with X?" — both sides must confirm before anything is exchanged |
| Reveal | up to three grounded shared interests with evidence, one opener, save |
| Connections | locally saved people, detail, swipe to delete, empty state |
| You | edit profile, permission/capability status, link to Testing tools |

## Architecture — one file per box, real boundaries

```
View/    SwiftUI screens only. No sensors, no sockets.
Design/  Theme.swift (colour/type/spacing) + Components.swift
Model/   Profile, SharedProfile, SavedConnection, Interest catalogue
Service/
  MotionDetector       CoreMotion → SpikeGate
  SpikeGate            pure threshold/rearm/cooldown state machine (unit-tested)
  RangingService       NISession per peer, bounded, attributed
  PeerTransport        MultipeerConnectivity or server relay, swappable
  StreetPass/          ambient encounter transport, ranging and gate
  LiveActivityController  bounded background session status
  WireProtocol         versioned + bounded + idempotent messages
  PairingMatcher       pure matching algorithm (unit-tested)
  InterestMatcher      grounded overlap (unit-tested)
  TalkingPointMatcher  shared vs complementary, each backed by both cards
  ConversationService  Grok (via bump-api) → Foundation Models → deterministic
  BumpAPI              client for bump-api + shared grounding checks
  OnboardingModel      the Pre-phase state machine (cancellation, fallbacks)
  IntroRecorder        45 s mic capture, interruptions, silence detection
  LocalDrafter         on-phone drafting + questions (local-only / fallback)
```

Tests in `ios/BumpTests/` include `ContractTests`, `LogicTests`,
`OnboardingTests`, `DesignTests`, and `StreetPassTests`.

## The central honesty constraint

**Motion tells a phone *that* it was tapped, not *who* tapped it.**

The coordinator pairs bumps by its own arrival times. When several people bump
at the same instant that genuinely cannot identify partners, so BUMP
**rejects rather than guesses**, and offers a manual pick which is recorded
honestly *as a manual pick*. UWB distance is much stronger evidence about
*which* peer, when available.

The number that decides whether this works in a crowded room is the
**rejection rate**, reported separately from accuracy in `RESULTS.md` —
rejecting everything would otherwise look like perfect accuracy. That data does
not exist yet.

## Instrumentation

Live acceleration, live UWB distance, pairing sliders, event log, diagnostics
export — all behind **You ▸ Testing tools**, deliberately kept out of the
normal flow.

## Status

The merged iOS app has not been built or type checked in Xcode. Swift syntax
parses on Linux; backend tests pass separately. Earlier UI code was inspected
in the Simulator and on one iPhone. **The merged two-phone flow is unproven.**

## History

Evolved from a Nearby Interaction spike. The working `NISession` /
`NINearbyPeerConfiguration` / MultipeerConnectivity code was kept and refactored
into `RangingService` and `PeerTransport`. An earlier Node + Socket.io browser
experiment was removed from the tree; it is still in git history at commit
`278d2e0` if the matching algorithm or browser `devicemotion` work is needed.
