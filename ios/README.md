# BUMP — native iOS MVP

Meet someone. Find your overlap.

Two people tap phones, confirm each other, and get the specific things they
actually have in common plus grounded talking points. **No account, and no API
key in the app.** Bumping, matching and the partner-only profile exchange run on
the phones in the room. The voice intro, Grok profile drafting and Grok talking
points go through the BUMP server ([`backend/`](../backend/README.md)) to xAI,
only after the person allows it, and for talking points only when **both**
people allowed it. If the server can't be reached, the app falls back to
on-phone suggestions and labels them.

This evolved from the Nearby Interaction spike that used to live here. The
working `NISession` / `NINearbyPeerConfiguration` / MultipeerConnectivity code
was kept and refactored into `RangingService` and `PeerTransport`; the old
`UWBExperiment`/`ContentView` test dashboard is gone, and its instrumentation now
lives behind **You ▸ Testing tools**. The earlier Node + Socket.io web spike has
been removed from the tree; it is still in git history at commit `278d2e0` if the
matching algorithm or the browser `devicemotion` work is ever needed again.

---

## The journey

Create a profile → join or host an event → tap **Ready to bump** → bump phones →
both confirm → shared interests + a conversation opener → save the connection.

| Screen | What it does |
|---|---|
| **Welcome** | Hero wordmark, one action. |
| **Onboarding** | Name → spoken intro (≤ 45 s, or type) → up to 3 follow-ups → an editable card you approve. See [Onboarding](#onboarding-pre). Profile editor still available later from You. |
| **Bump** | Home with **Start bumping** (automatic nearby room, no codes), a first-run tour of how bumping works, "Tap your phones together" with who's nearby, all the error states, manual pick. Event codes live behind "Have an event code?". |
| **Confirm partner** | "Did you bump with X?" — both sides must confirm before anything is exchanged. |
| **Reveal** | Up to three grounded shared interests with evidence, one opener, save. |
| **Connections** | Locally saved people, detail view, swipe to delete, empty state. |
| **You** | Edit profile, permission/capability status, link to Testing tools. |

## Architecture

Each box is one file, with a real boundary between them.

```
View/            SwiftUI screens only. No sensors, no sockets.
Design/          Theme.swift (colour/type/spacing) + Components.swift
Model/           Profile, SharedProfile, SavedConnection, Interest catalogue
Service/
  MotionDetector   CoreMotion → SpikeGate
  SpikeGate        pure threshold/rearm/cooldown state machine (unit-tested)
  RangingService   NISession per peer, bounded, attributed
  PeerTransport    MultipeerConnectivity, encrypted, swappable
  WireProtocol     versioned + bounded + idempotent messages
  PairingMatcher   pure matching algorithm (unit-tested)
  InterestMatcher  grounded overlap (unit-tested)
  TalkingPointMatcher  shared vs complementary candidates, each backed by both cards
  ConversationService  Grok (via bump-api) → Foundation Models → deterministic
  BumpAPI          client for bump-api + shared grounding checks
  OnboardingModel  the Pre-phase state machine (cancellation, fallbacks)
  IntroRecorder    45 s mic capture, interruptions, silence detection
  LocalDrafter     on-phone drafting + questions (local-only / fallback)
  BumpEngine       the state machine that wires the above together
  Store            local JSON persistence
```

## Build and run

Requires **Xcode 26+**. Deployment target is **iOS 17.0** — chosen so the app runs
on any phone the team has. Nearby Interaction needs iOS 16+, and the optional
on-device AI needs iOS 26, so **neither the newest iPhone nor the newest OS is
required**; both degrade cleanly.

```bash
open ios/UWBBumpTest.xcodeproj

# compile check, no signing, no device
xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest \
  -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# unit tests (simulator)
xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Signing is already set: team `56KWU9QP85`, bundle id
`com.jaredberesford.uwbbumptest`, automatic signing. The display name is **BUMP**;
the target and bundle id are deliberately unchanged so existing provisioning
keeps working. A teammate using their own Apple ID changes only
`PRODUCT_BUNDLE_IDENTIFIER` and `DEVELOPMENT_TEAM`.

### Installing on two phones

1. Connect iPhone, **Trust This Computer**.
2. Settings ▸ Privacy & Security ▸ **Developer Mode** on (the phone restarts).
3. Select the phone as the run destination, ⌘R.
4. If it won't launch: Settings ▸ General ▸ **VPN & Device Management** ▸ Trust.
5. Grant **Nearby Interaction**, **Local Network** and **Motion** when prompted.
6. Repeat on the second phone.

Free provisioning expires after 7 days — rebuild from Xcode. That is an account
limit, not a bug.

### Running the full journey on two phones

1. Both phones: finish onboarding (name, speak or type an intro, approve the
   card). Give them at least one interest in common, or the reveal will
   correctly say you share nothing. For Grok talking points, both must allow
   cloud processing and at least one must reach a bump-api with a key
   (You ▸ Cloud processing shows the status).
2. Both phones: Bump tab → **Start bumping**. Each joins the shared "nearby"
   room, or becomes its coordinator if nobody is hosting yet; if two start at
   once, the one with the higher transient id steps down and joins the other.
   Wait for "1 person nearby".
3. Tap the phones together, back to back, once.
4. Both see "Did you bump with …?" → **Confirm & share interests** on both.
5. Reveal appears on both with the same shared interests and the same opener.
6. **Save connection** → it shows up under Connections.

## Detection

**Motion is the gesture. UWB is the evidence about *which* peer.**

- `MotionDetector` reads `CMDeviceMotion.userAcceleration`, which is in **g** with
  gravity already removed, and converts explicitly to m/s² (× 9.80665). The web
  experiment's 12 m/s² threshold came from a hand-rolled high-pass over
  `accelerationIncludingGravity` in a browser at a different sample rate and is
  **not** transferable — the native default (20 m/s²) was set independently and
  still needs tuning on hardware. 50 Hz, off the UI thread, stopped when you leave
  ready or background the app.
- `SpikeGate` does threshold crossing, rearm below 0.5× threshold, and a 1.5 s
  cooldown, on a monotonic clock (`CMDeviceMotion.timestamp`, seconds since boot).
- `RangingService` runs one `NISession` per peer, keyed so a measurement can only
  ever be attributed to the peer whose session produced it. Capability is checked
  at runtime — `supportsPreciseDistanceMeasurement` does **not** imply
  `supportsDirectionMeasurement`, and "iPhone 11 or newer" guarantees neither.
  Missing distance stays `nil` (never 0), measurements expire after 1.5 s, and
  suspension/invalidation/peer-removal/permission-denial are all handled.
  **Direction is never required** — a valid distance is sufficient evidence.
- ~0.15 m is an **experimental proximity threshold, not proof the phones
  touched**, and is adjustable in Testing tools.
- Motion and UWB do **not** have to fire in the same callback. The coordinator
  correlates them over a bounded interval (`uwbFreshness`, default 1.5 s).
- Motion-only / UWB-only / Combined modes are all retained in Testing tools.

## Onboarding (Pre)

1. **Name.**
2. **Introduce yourself** — record up to 45 s, or **Type instead**. Before
   anything is uploaded, a one-time card explains that the recording, typed text
   and answers go to the BUMP server and on to xAI, and offers **Keep everything
   on this phone** (typing only; suggestions come from the phone). States:
   asking for mic permission, denied (→ Settings / Type instead), recording with
   countdown and level meter, interrupted (call/Siri), too short, silent,
   uploading, transcribing, drafting, and every failure with a retry. The
   transcript is shown for correction before drafting.
3. **Up to three follow-ups**, one at a time, skip any. Grok is asked not to
   repeat anything already said; the phone's fallback questions only ask about a
   broad category if nothing specific in it was mentioned.
4. **Your Bump card** — name, bio, and interests / experiences / goals. Each
   suggestion shows the exact words it came from and who suggested it (Grok, your
   phone, or you). Check/uncheck to decide what's shared, edit, remove, add, or
   browse the catalogue. Only checked items are saved; transcript and answers
   are dropped.

Rules enforced in `OnboardingModel`: a newer request cancels the older one and
late responses are ignored (including after leaving the screen); every cloud
call has a hard deadline; Grok failing (not configured, offline, timeout,
invalid output) falls back to the on-phone drafter with a calm notice, and
nothing local is ever labelled Grok. Facts must quote the user's words
(word-bounded, checked on the server **and** in Swift). Nothing is inferred from
the voice itself — only the transcript text is analysed, and sensitive
categories (health, religion, ethnicity, …) are never auto-suggested.

**Catalogue:** 12 broad topics people actually talk about (Music, Coffee, Food
& drink, Sports & fitness, Gaming, Movies & TV, Collecting, Outdoors, Tech, Art &
design, Books & stories, Travel), each opening into common variations
(Collecting: vinyl, figures, trading cards, sneakers, rocks & minerals…; Coffee:
espresso, pour-over, cold brew…). Browsing shows the topics first; picking one
opens its variations underneath. A topic and its variations never match as
"shared"; they become complementary talking points. Synonyms are equivalents
only ("coffee" is not "espresso", "jazz" is not "jazz piano"). Niche or older
interests ("Jazz piano", "Bouldering") stay in the person's own words with a
parent topic, so they still match each other and still feed complementary
points.

**Profile photo:** optional, from the system photo picker (no photo-library
permission). Cropped square, resized and compressed to ≤ 30 KB so it fits one
wire frame. Part of the card, so only a confirmed partner receives it; never
sent to the BUMP server or xAI. Incoming photos over 40 KB or not decodable
are dropped.

**Style:** no em dashes in app copy; Grok is told not to use them and the
server and app both replace any that slip through.

## Grok and the BUMP server

The app talks only to `bump-api` (see its [README](../backend/README.md) and
[CONTRACT](../backend/CONTRACT.md)). Server URL: build setting
`BUMP_API_BASE_URL` (default `http://localhost:8787`, fine for the Simulator),
overridable at runtime in **You ▸ Testing tools ▸ BUMP server**, which also has
a health check.

**On a physical iPhone, `localhost` is the phone itself.** Run bump-api on your
Mac, find the Mac's LAN address (`ipconfig getifaddr en0`, e.g.
`192.168.1.20`), and enter `http://192.168.1.20:8787` in Testing tools — phone
and Mac on the same Wi-Fi. Plain http works for LAN IPs and `.local` names
(`NSAllowsLocalNetworking`); the phone may ask for Local Network permission
(already used for bumping).

### Talking points (During)

`TalkingPointMatcher` builds up to 8 **verified candidates**: *shared* (the same
interest, or identical experience/goal, in both approved cards) and
*complementary* (different interests in the same family, e.g. jazz ↔ jazz
piano; or one person's goal meeting the other's interest/experience). The model
only phrases these; ids, kinds and evidence come from our candidates, and
unknown ids, non-questions and anything mentioning scores/percentages are
dropped. 0–4 points; no overlap means no claims.

Exactly one phone generates and sends the result, so both phones match; the
partner flips "you/them" evidence on receipt. Partners exchange a two-boolean
`PartnerCaps` (`cloudConsent`, `grokReady`) on the direct link only — never to
the room. If **both** consented, the phone that can reach Grok generates (lowest
id if both); otherwise the coordinator's original Apple-Intelligence-aware pick
stands. So Grok availability no longer depends on Apple Intelligence. The whole
generation is capped at ~9 s: Grok (7 s) → Apple Intelligence with whatever
remains → deterministic templates, each labelled with its real source.

Wire protocol is now **v2**; a v1 phone gets the existing "both phones need the
same app version" message.

## Rooms, pairing and crowded rooms

One phone hosts the room and coordinates. Guests connect to it; the host's own
bumps go through the **same** pipeline as everyone else's.

The coordinator stamps each bump with **its own monotonic clock on arrival**.
Timestamps from different phones are never subtracted from each other — their
clocks are not synchronized — and network latency genuinely blurs arrival order.

The algorithm (`PairingMatcher`, all of it unit-tested):

1. Age out anything older than `timeout` (2.5 s) → explicit timeout, never a
   hanging spinner.
2. Buffer for 250 ms before committing, so a closer later arrival can still win.
3. Candidates = different participants within the `window` (500 ms, configurable).
4. Rank: **UWB-corroborated pairs first**, then smallest arrival gap.
5. **Ambiguity:** if a rival pair shares exactly one member and is within
   `ambiguityMargin` (50 ms) at the same evidence level, reject everything
   involved. We never guess.
6. Otherwise commit and loop, so two separated pairs both match.

Never self-pairs, never reuses a bump, one active proposal per participant,
idempotent on duplicate/delayed messages, and cleans up on decline, timeout,
disconnect or room change.

**We never connect to the first discovered phone.** Discovery is scoped to the
event code, identities are transient (`Name#XXXX`, regenerated per session), and
the only thing advertised is a display name and the room code.

### Documented limits

| Limit | Value | Why |
|---|---|---|
| Phones per room | **8** | `MCSession`'s documented maximum. Shown on screen as "n of 8 phones". |
| Simultaneous ranging sessions | **4** | Nearby Interaction publishes no hard number and it varies by hardware. We cap it rather than pretend a room of 50 can be ranged. |

For a bigger event, run several small rooms. This is surfaced in the UI, not
hidden.

### When it can't decide

"A few people bumped at once — try again," with an optional **Pick someone
instead** flow. A manual pick is recorded as `manualSelection` and is **never**
counted as a hardware-detected bump — the reveal and the saved connection both
say "Picked manually".

Current honest limitation: the manual picker only works on the **hosting** phone.
A guest is told so plainly rather than being given a button that quietly fails.

## StreetPass

An ambient, foreground-only proximity teaser, fully separate from the main
bump pipeline described above.

- Runs automatically once a profile is complete and the app is foregrounded
  — no toggle. Uses its own MultipeerConnectivity service
  (`_bump-streetpass._tcp`/`._udp`), not the room/coordinator transport above,
  and auto-connects to any nearby StreetPass peer rather than requiring a
  shared room code.
- Each connected peer gets its own `NISession` (`StreetPassRanging`, capped at
  3 concurrent peers, independent of the main pipeline's cap of 4).
  `StreetPassEncounterGate` requires several consecutive sub-threshold
  readings before an encounter qualifies, then latches until the peer clearly
  moves away (hysteresis) and a per-peer cooldown has elapsed.
- On a qualifying encounter: at most one mutual interest is computed
  (`InterestMatcher.overlap(..., limit: 1)`) and a teaser is shown — never a
  full profile. While the app is foregrounded this is a custom in-app sheet;
  a local notification is only scheduled in the narrow case where the app
  was not active at that instant.
- "Bump them" hands off into the existing nearby-room flow
  (`engine.startNearby()`) — the actual pairing still goes through the same,
  unmodified physical-tap-to-confirm pipeline everyone else uses.
- **Locked-phone detection is out of scope for this iteration.** Real UWB
  peer-to-peer ranging cannot run while the app is backgrounded on stock iOS
  — there is no background API for phone-to-phone `NISession` ranging.
  StreetPass is entirely foreground-only; nothing is persisted, and all
  state clears when the app leaves the foreground.

```bash
xcrun simctl launch <sim-id> com.jaredberesford.uwbbumptest -BumpDemo streetpass
```

## Privacy

- Full interest profiles go **only to the confirmed partner, only after both
  confirm**, over a direct encrypted link. The coordinator never sees them. Two
  guests open a direct MultipeerConnectivity link on demand for this.
- What a partner receives is `SharedProfile`: name, bio, approved interests,
  approved experiences/goals. Never the evidence quotes, transcript, answers,
  drafts, or the cloud preference (a test asserts this). The only cloud-related
  data a partner sees is the two `PartnerCaps` booleans.
- Cloud processing is **opt-in** (`privacy.json`, separate from the profile).
  Undecided or "keep on this phone" → no request is made at all (tested).
- Audio: recorded to the temp directory, deleted after transcription, discard or
  re-record; bump-api holds it in memory only and never logs bodies. Grok calls
  use `store: false`. xAI's docs say API requests are retained up to 30 days for
  auditing by default; we have **not** verified xAI's retention of STT audio.
- The room only ever sees `{id, displayName, supportsUWB}` — a unit test asserts
  no interests or bio can leak into that type.
- Diagnostics exports exclude profile content, interests, bios and raw discovery
  tokens.

## On-device AI (fallback)

`ConversationService` computes the *facts* in Swift first (`InterestMatcher`),
then asks Apple's on-device model only to *phrase* them.

- Compiled with `#if canImport(FoundationModels)` and gated at runtime on
  `SystemLanguageModel.default.availability`, so unsupported devices and older
  OSes just work.
- The model gets only the confirmed shared interests — no names, no bios. User
  text is passed as **data** inside delimited tags, never as instructions.
- Output is structured (`@Generable`) and **validated**: if the model grounds its
  question in an interest that is not in both profiles, it is rejected. Refusals,
  guardrail trips, unloaded models and a 12 s timeout all fall through.
- The fallback is deterministic, built from the real overlap, and labelled
  **"Suggested question"**. A template is never presented as an AI result — the
  UI shows which produced it.
- Exactly one participant generates (an AI-capable one is preferred), then sends
  the result to the partner, so **both phones show the same thing**. Retries are
  idempotent on the proposal id.
- No rarity claims anywhere. We have no population data, so the UI says "Specific
  things you share" and states plainly that ranking is by specificity, not rarity.

## Testing tools

**You ▸ Testing tools.** Detection mode, live acceleration and last spike, motion
threshold/cooldown sliders, peer/session status, live distance and direction
availability, measurement age, pairing window/ambiguity/buffer sliders, a
bounded timestamped event log, reset, and **Export diagnostics** through the
native share sheet.

Deliberately kept out of the normal flow — no raw sensor numbers appear on the
Bump screen.

### Demo mode

DEBUG builds only, by explicit launch argument. Every demo screen wears a
**"DEMO DATA — not a real person or measurement"** badge and the fixture people
are named "(demo)".

```bash
xcrun simctl launch <sim-id> com.jaredberesford.uwbbumptest -BumpDemo reveal
# onboarding | onboardingintro | onboardingquestion | onboardingcard
# ready | confirm | reveal | connections | timedout | ambiguous | unsupported
```

---

## What was actually verified

| Check | Result |
|---|---|
| Device build (`generic/platform=iOS`, Debug + Release) | **BUILD SUCCEEDED**, 0 errors, 0 warnings |
| Simulator build | **BUILD SUCCEEDED** |
| Unit tests (Simulator, network MOCKED) | **89 pass, 0 fail, 4 skipped** (93 total; the 4 skipped are the contract tests below) |
| Contract tests: real `BumpAPIClient` ↔ real `bump-api` ↔ **fake** xAI | **5/5 pass** (run by hand, see `BumpTests/ContractTests.swift`) |
| `bump-api` tests (fake xAI, no network) | **41/41 pass** |
| Live xAI (Grok + speech-to-text) | **Not run** — no key in this environment. See `bump-api` README → smoke test |
| `CFBundleIdentifier` in the built app | `com.jaredberesford.uwbbumptest` ✓ |
| `CFBundleExecutable` | `UWBBumpTest`, and the file exists and is a real Mach-O ✓ |
| Unresolved `$(...)` placeholders in the built plist | **0** ✓ |
| `Info.plist` copied as a stray resource? | No — appears once, as the bundle plist ✓ |
| Asset catalog compiled in | `Assets.car` + app icons present ✓ |
| Bonjour entries match the code | `_bump-uwb._tcp` / `._udp` ↔ `PeerTransport.serviceType` ✓ |
| Privacy strings | Nearby Interaction, Local Network, Motion, Microphone — all meaningful ✓ |
| ATS | `NSAllowsLocalNetworking` only (LAN / `.local` http to bump-api); no arbitrary loads ✓ |
| Entitlements | None needed; none added (no background modes) ✓ |
| Screens inspected in the Simulator | Welcome, ready, confirm, reveal (with talking points), connections, timed-out, ambiguous; onboarding name / transcript review / question / card via `-BumpDemo onboardingintro|onboardingquestion|onboardingcard` (sample data, DEMO badge) |
| Not inspected in the Simulator | Live recording, real upload/transcribe, the consent card tapped through by hand (covered by unit tests, not by eye) |

**Not verified:** anything requiring two physical iPhones. See below.

### Test coverage

Motion cooldown/rearm/units · measurement freshness and attribution · matching
window boundaries · closest-pair selection · three ambiguous simultaneous bumps ·
two separate pairs in one room · duplicate events and idempotent re-delivery ·
self-pairing and lockout · timeout-once · disconnect cleanup · interest
normalization, synonyms, specificity ranking and truthful evidence · no-overlap
produces no claims · AI fallback labelling · wire version/size/malformed-frame
rejection · roster carries no interests · local save/load/delete idempotency ·
manual selection never recorded as a detected bump.

Added for Pre/During (all mocked): coffee ≠ espresso, jazz ≠ jazz piano, broad ≠
specific, removed synonyms stay removed · word-bounded grounding, ungrounded and
duplicate facts dropped, score/percentage questions rejected · local drafter
(longest match, goals/experiences keep their words, no repeat questions, cap 3)
· shared vs complementary candidates, goal↔experience, neutral templates,
evidence mirroring · Grok result validated + labelled, malformed/score/slow Grok
falls back within budget with one try, generator choice needs both consents and
is symmetric · onboarding: Grok happy path, skip free text, skip a question,
edit + uncheck controls what's saved, missing key / offline / no server /
timeout / malformed → on-phone fallback with notice, local-only and undecided
never call the server, leaving cancels and late responses are ignored, answers
survive back/forward, ≤ 3 questions, back from the card never lands on an empty
step · old profile / connection / settings JSON still load, shared card carries
no evidence or preferences, wire v2 caps round-trip.

---

## Still pending on physical hardware

Nothing below has been measured. The simulator cannot validate **any** of it —
there is no UWB radio and no real accelerometer.

1. Two supported iPhones, full journey end to end.
2. **20+ intentional bumps**, outcomes recorded individually.
3. Gentle bumps; different holding angles.
4. Walking and normal handling with no intentional bumps (false-trigger rate).
5. Four phones, two intended pairs bumping simultaneously.
6. Bystanders nearby running the app.
7. One-sided motion (only one phone feels it).
8. UWB unavailable, and UWB stale.
9. A body blocking line of sight.
10. Rejection ("Not this person") and cancellation on both sides.
11. Backgrounding and returning; reconnect.
12. **Host disconnect** → rejoin / re-host path.
13. AI available and unavailable, on the same pair.
14. **Grok talking points on two phones:** both allow cloud → both show the
    identical Grok result; one local-only → no `/v1/talking-points` in the
    bump-api log and both show the same fallback; bump-api stopped mid-event →
    fallback within ~9 s on both.
15. **Voice onboarding on a real phone:** mic permission prompt and denial,
    a phone call mid-recording, a noisy room, airplane mode (→ on-phone draft).
16. Existing installs: upgrade a phone with a saved profile and connections;
    both still load (unit-tested with old JSON, not on hardware).

Record in `../RESULTS.md`: intended matches, **wrong-person proposals**,
ambiguous/rejected, timeouts, missed bumps, false triggers per device-minute,
time to confirmation, UWB reliability, and how often manual selection was needed.
Report the rejection rate separately — an app that rejects everything has zero
wrong matches and is useless.

### Known risk from the earlier spike

Ranging appeared to stop a couple of seconds into a close approach. If Nearby
Interaction drops out below ~10 cm, the 0.15 m trigger may sit under what the
hardware can resolve, and UWB would corroborate *fewer* bumps than hoped. The app
degrades correctly if so — motion still matches, and the proposal just says
"Matched by motion" instead of "motion + UWB" — but **measure this first**, at a
steady 1 m, before trusting any combined-mode number.

## Reference

- [Nearby Interaction](https://developer.apple.com/documentation/nearbyinteraction) · [`NISession.deviceCapabilities`](https://developer.apple.com/documentation/nearbyinteraction/nisession/devicecapabilities) · [`NINearbyObject.direction`](https://developer.apple.com/documentation/nearbyinteraction/ninearbyobject/direction)
- [MultipeerConnectivity](https://developer.apple.com/documentation/multipeerconnectivity) · [`MCSession`](https://developer.apple.com/documentation/multipeerconnectivity/mcsession) (peer limit)
- [Core Motion `CMDeviceMotion.userAcceleration`](https://developer.apple.com/documentation/coremotion/cmdevicemotion/useracceleration)
- [Foundation Models](https://developer.apple.com/documentation/foundationmodels) · [`SystemLanguageModel`](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
- [`NSBonjourServices`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsbonjourservices) · [Enabling Developer Mode](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)
