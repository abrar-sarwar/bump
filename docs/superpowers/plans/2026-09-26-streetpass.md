# StreetPass Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Detect when two BUMP phones pass within close Ultra Wideband range while both apps are foregrounded, and surface a lightweight in-app teaser (at most one mutual interest) that hands off into the existing, unmodified bump-confirm flow.

**Architecture:** A new, self-contained `Service/StreetPass/` subsystem — its own MultipeerConnectivity service, its own `NISession`-per-peer ranging, a pure per-peer encounter-decision state machine, a thin orchestrator, and a notifier — wired into `RootView` alongside the existing `BumpEngine`, without modifying `BumpEngine`, `PeerTransport`, or `RangingService` at all.

**Tech Stack:** Swift, SwiftUI, MultipeerConnectivity, NearbyInteraction (`NISession`), UserNotifications, XCTest.

**Spec:** `docs/superpowers/specs/2026-09-26-streetpass-design.md`

## Global Constraints

- iOS 17.0 deployment target (already the project setting — do not change it).
- No backend endpoints, server-side encounter tracking, or remote matching.
- No persisted StreetPass encounter history — everything is in-memory and clears on backgrounding/disconnect.
- No new entitlements, no `UIBackgroundModes` — StreetPass is foreground-only for this iteration (locked-phone detection is explicitly deferred).
- Never reveal more than one mutual interest, and never invent one when there are none.
- Never send a full profile before both people explicitly bump (StreetPass's own ambient payload is smaller than `SharedProfile`: no bio, no experiences/goals, no evidence text).
- A system notification is only ever scheduled when the app is not active at the moment of a qualifying encounter; while foregrounded, the custom in-app sheet is the only UI (no redundant system banner).
- "Bump them" hands off to `engine.startNearby()` (the existing `BumpEngine` API) and nothing else — the actual pairing still goes through the existing, unmodified physical-tap-to-confirm pipeline. Do not touch `BumpEngine`'s proposal/confirm/exchange logic.
- This project uses Xcode's synchronized file groups (`PBXFileSystemSynchronizedRootGroup`) for both the `UWBBumpTest` and `BumpTests` folders — any new `.swift` file placed inside them is picked up automatically. No `project.pbxproj` edits are needed for new files.
- All commands below run from the `ios/` directory.

---

### Task 1: `InterestMatcher` gains an `[Interest]`-based overload

**Files:**
- Modify: `ios/UWBBumpTest/Service/InterestMatcher.swift:19-53`
- Modify: `ios/BumpTests/LogicTests.swift` (append to `InterestMatcherTests`, after line 304, before the closing `}` of the class)

**Interfaces:**
- Produces: `InterestMatcher.overlap(_ mine: [Interest], _ theirs: [Interest], limit: Int = 3) -> [SharedHighlight]` — used by `StreetPassEngine` in Task 8. The existing `overlap(_ a: SharedProfile, _ b: SharedProfile, limit:)` keeps its exact signature and behavior, now implemented in terms of the new overload.

- [ ] **Step 1: Write the failing tests**

Add these three methods inside `InterestMatcherTests` (in `ios/BumpTests/LogicTests.swift`), right before the class's closing `}` on line 305:

```swift
    func testInterestArrayOverlapMatchesSharedProfileOverlap() {
        let mine = ["Jazz", "Photography"].compactMap { InterestCatalog.canonical(from: $0) }
        let theirs = ["Jazz", "Climbing"].compactMap { InterestCatalog.canonical(from: $0) }
        let out = InterestMatcher.overlap(mine, theirs, limit: 1)
        XCTAssertEqual(out.map(\.interestID), ["jazz"])
    }

    func testInterestArrayOverlapNeverExceedsLimit() {
        let labels = ["Jazz", "Photography", "Climbing", "Baking", "Chess"]
        let mine = labels.compactMap { InterestCatalog.canonical(from: $0) }
        XCTAssertEqual(InterestMatcher.overlap(mine, mine, limit: 1).count, 1)
    }

    func testInterestArrayOverlapEmptyWhenNoOverlap() {
        let mine = [InterestCatalog.canonical(from: "Jazz piano")!]
        let theirs = [InterestCatalog.canonical(from: "Bouldering")!]
        XCTAssertTrue(InterestMatcher.overlap(mine, theirs, limit: 1).isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/InterestMatcherTests`
Expected: build failure — `overlap(_:_:limit:)` on two `[Interest]` arrays doesn't exist yet.

- [ ] **Step 3: Implement the overload**

Replace the existing `overlap` function (`ios/UWBBumpTest/Service/InterestMatcher.swift`, lines 19-53) with:

```swift
    static func overlap(_ a: SharedProfile, _ b: SharedProfile, limit: Int = 3) -> [SharedHighlight] {
        overlap(a.interests, b.interests, limit: limit)
    }

    /// Same grounded-overlap logic, taking raw interest lists directly — lets a
    /// caller compute overlap without constructing a SharedProfile just to
    /// hold an interest list. StreetPass's ambient peer payload is not a
    /// SharedProfile (it carries no bio, no experiences/goals, no evidence).
    static func overlap(_ mine: [Interest], _ theirs: [Interest], limit: Int = 3) -> [SharedHighlight] {
        // Index by canonical id, keeping the user's own wording as evidence.
        let mineByID = index(mine)
        let theirsByID = index(theirs)

        let sharedIDs = Set(mineByID.keys).intersection(theirsByID.keys)
        guard !sharedIDs.isEmpty else { return [] }

        // Suppress a broad category when one of its specific children matched,
        // including custom interests that belong to it ("Jazz piano" → Music).
        let matchedParents: Set<String> = Set(sharedIDs.compactMap { id in
            guard let interest = mineByID[id], interest.specificity == 2 else { return nil }
            return interest.parent
        })

        let highlights: [SharedHighlight] = sharedIDs.compactMap { id -> SharedHighlight? in
            guard let mine = mineByID[id], let theirs = theirsByID[id] else { return nil }
            if matchedParents.contains(id) { return nil }
            return SharedHighlight(
                interestID: id,
                statement: statement(for: mine),
                yourEntry: mine.label,
                theirEntry: theirs.label,
                specificity: mine.specificity
            )
        }

        return highlights
            .sorted {
                if $0.specificity != $1.specificity { return $0.specificity > $1.specificity }
                return $0.interestID < $1.interestID     // stable, so both phones agree
            }
            .prefix(limit)
            .map { $0 }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/InterestMatcherTests`
Expected: all `InterestMatcherTests` PASS (existing tests plus the three new ones).

- [ ] **Step 5: Commit**

```bash
git add ios/UWBBumpTest/Service/InterestMatcher.swift ios/BumpTests/LogicTests.swift
git commit -m "Add InterestMatcher overload for raw interest arrays"
```

---

### Task 2: `StreetPassConfig` + `StreetPassEncounterGate`

**Files:**
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassConfig.swift`
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassEncounterGate.swift`
- Create: `ios/BumpTests/StreetPassTests.swift`

**Interfaces:**
- Produces: `StreetPassConfig` (struct, `Equatable`, all fields have defaults) — consumed by `StreetPassEngine` (Task 8), `StreetPassTransport` (Task 5), `StreetPassRanging` (Task 6).
- Produces: `StreetPassEncounterGate` (struct) with `init(proximityThreshold:consecutiveReadingsRequired:exitHysteresisMargin:cooldown:)` and `mutating func feed(distance: Double, now: TimeInterval) -> Verdict`, where `Verdict` is `.qualified | .accumulating(Int) | .suppressedByCooldown | .awaitingExit | .idle` — consumed by `StreetPassEngine` (Task 8).

Note: the design spec names this verdict case `.cooldown`; this plan uses `.suppressedByCooldown` instead, for consistency with `SpikeGate.Verdict.suppressedByCooldown` (the exact pattern this gate mirrors). Cosmetic only — applied consistently throughout.

- [ ] **Step 1: Create the config file**

```swift
import Foundation

/// Centralized, adjustable tunables for the StreetPass ambient-encounter
/// pipeline — one place to tune, not magic numbers scattered through
/// delegate callbacks. Mirrors RangingService.Config / PairingMatcher.Config.
struct StreetPassConfig: Equatable {
    /// Distance below this counts toward a qualifying encounter. Experimental,
    /// not proof of a deliberate pass.
    var proximityThreshold: Double = 0.5
    /// Consecutive sub-threshold readings required before an encounter
    /// qualifies. Debounces a single noisy reading.
    var consecutiveReadingsRequired: Int = 3
    /// The peer's distance must exceed proximityThreshold + this margin
    /// before the gate can rearm for another encounter with them.
    var exitHysteresisMargin: Double = 0.5
    /// Minimum time between two qualifying encounters with the same peer,
    /// even after rearming.
    var cooldown: TimeInterval = 30
    /// Practical cap on simultaneous StreetPass ranging sessions, independent
    /// of RangingService.maxConcurrentPeers so the two subsystems never
    /// contend for whatever ceiling the hardware actually has.
    var maxConcurrentPeers: Int = 3
    /// A measurement older than this is stale and must not be used.
    var measurementFreshness: TimeInterval = 1.5
}
```

- [ ] **Step 2: Write the failing tests**

Create `ios/BumpTests/StreetPassTests.swift`:

```swift
import XCTest
@testable import UWBBumpTest

// MARK: - Encounter gate

final class StreetPassEncounterGateTests: XCTestCase {

    private func gate(threshold: Double = 0.5, readings: Int = 3, margin: Double = 0.5,
                       cooldown: TimeInterval = 30) -> StreetPassEncounterGate {
        StreetPassEncounterGate(proximityThreshold: threshold, consecutiveReadingsRequired: readings,
                                exitHysteresisMargin: margin, cooldown: cooldown)
    }

    func testRequiresConsecutiveSubThresholdReadingsBeforeQualifying() {
        var g = gate()
        XCTAssertEqual(g.feed(distance: 0.4, now: 0), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.1), .accumulating(2))
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.2), .qualified)
    }

    func testASingleFarReadingResetsTheConsecutiveCount() {
        var g = gate()
        XCTAssertEqual(g.feed(distance: 0.4, now: 0), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.1), .accumulating(2))
        XCTAssertEqual(g.feed(distance: 0.6, now: 0.2), .idle, "one far reading breaks the run")
        XCTAssertEqual(g.feed(distance: 0.4, now: 0.3), .accumulating(1), "must restart, not resume")
    }

    func testQualifiesOnceThenRequiresClearExitBeforeRefiring() {
        var g = gate(readings: 2, cooldown: 0)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.1), .qualified)
        // Sustained proximity must not refire.
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.2), .awaitingExit)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.3), .awaitingExit)
        // Within the hysteresis band (above threshold, not past the margin): still no rearm.
        XCTAssertEqual(g.feed(distance: 0.7, now: 0.4), .awaitingExit)
        // Clearly past threshold + margin (0.5 + 0.5 = 1.0): rearms.
        XCTAssertEqual(g.feed(distance: 1.1, now: 0.5), .idle)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.6), .accumulating(1))
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.7), .qualified)
    }

    func testCooldownSuppressesARequalificationEvenAfterRearming() {
        var g = gate(readings: 1, cooldown: 10)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0), .qualified)
        // Threshold 0.5 + margin 0.5 = 1.0: 1.1 clearly clears it, 0.9 would not.
        XCTAssertEqual(g.feed(distance: 1.1, now: 1), .idle, "rearm")
        XCTAssertEqual(g.feed(distance: 0.3, now: 2), .suppressedByCooldown)
        XCTAssertEqual(g.feed(distance: 1.1, now: 3), .idle, "rearm again")
        XCTAssertEqual(g.feed(distance: 0.3, now: 11), .qualified, "past cooldown, a clean rearm can qualify again")
    }

    func testFreshGateAfterSimulatedDisconnectHasNoMemoryOfThePreviousEncounter() {
        var g = gate(readings: 1, cooldown: 30)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0), .qualified)
        // Peer disconnects; StreetPassEngine discards this gate entirely
        // rather than carrying cooldown state across a reconnect.
        g = gate(readings: 1, cooldown: 30)
        XCTAssertEqual(g.feed(distance: 0.3, now: 0.1), .qualified,
                       "a fresh gate for a reconnected peer must not be suppressed by the old cooldown")
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/StreetPassEncounterGateTests`
Expected: build failure — `StreetPassEncounterGate` doesn't exist yet.

- [ ] **Step 4: Implement `StreetPassEncounterGate`**

Create `ios/UWBBumpTest/Service/StreetPass/StreetPassEncounterGate.swift`:

```swift
import Foundation

/// Per-peer StreetPass encounter decision, pulled out so it is fully
/// unit-testable without NearbyInteraction. Same shape as SpikeGate:
/// consecutive-reading debounce, hysteresis rearm, and a cooldown, but
/// distance-based (qualifies BELOW a threshold) rather than acceleration-based.
struct StreetPassEncounterGate: Equatable {
    var proximityThreshold: Double
    var consecutiveReadingsRequired: Int
    var exitHysteresisMargin: Double
    var cooldown: TimeInterval

    private var consecutiveCount = 0
    private var armed = true
    private var lastQualifiedAt: TimeInterval = -.greatestFiniteMagnitude

    enum Verdict: Equatable {
        /// Fires once per encounter, when the debounce requirement is met.
        case qualified
        /// Still accumulating consecutive sub-threshold readings.
        case accumulating(Int)
        /// Debounce requirement met, but suppressed by cooldown.
        case suppressedByCooldown
        /// Below rearm, waiting to clearly exit past the hysteresis margin.
        case awaitingExit
        /// Above threshold and already rearmed; nothing pending.
        case idle
    }

    init(proximityThreshold: Double, consecutiveReadingsRequired: Int = 3,
         exitHysteresisMargin: Double = 0.5, cooldown: TimeInterval = 30) {
        self.proximityThreshold = proximityThreshold
        self.consecutiveReadingsRequired = consecutiveReadingsRequired
        self.exitHysteresisMargin = exitHysteresisMargin
        self.cooldown = cooldown
    }

    mutating func feed(distance: Double, now: TimeInterval) -> Verdict {
        if distance <= proximityThreshold {
            guard armed else { return .awaitingExit }
            consecutiveCount += 1
            guard consecutiveCount >= consecutiveReadingsRequired else {
                return .accumulating(consecutiveCount)
            }
            armed = false
            consecutiveCount = 0
            guard now - lastQualifiedAt >= cooldown else { return .suppressedByCooldown }
            lastQualifiedAt = now
            return .qualified
        }
        // Above threshold: a single far reading breaks a run of near ones,
        // and rearming requires clearly exceeding the hysteresis margin.
        consecutiveCount = 0
        if distance > proximityThreshold + exitHysteresisMargin {
            armed = true
        }
        return armed ? .idle : .awaitingExit
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/StreetPassEncounterGateTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/UWBBumpTest/Service/StreetPass/StreetPassConfig.swift \
        ios/UWBBumpTest/Service/StreetPass/StreetPassEncounterGate.swift \
        ios/BumpTests/StreetPassTests.swift
git commit -m "Add StreetPassConfig and the pure StreetPassEncounterGate state machine"
```

---

### Task 3: `StreetPassPeerProfile` model + `StreetPassWire` protocol

**Files:**
- Create: `ios/UWBBumpTest/Model/StreetPassPeerProfile.swift`
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassWireProtocol.swift`
- Modify: `ios/BumpTests/StreetPassTests.swift` (append)

**Interfaces:**
- Consumes: `Interest` (`ios/UWBBumpTest/Model/Interest.swift`).
- Produces: `StreetPassPeerProfile` (`Codable, Equatable, Sendable`, fields `id: String`, `displayName: String`, `avatarThumbnail: Data?`, `interests: [Interest]`, capped at `StreetPassPeerProfile.maxInterests`) — consumed by `StreetPassEngine` (Task 8) and `StreetPassWire.Body.hello`.
- Produces: `StreetPassWire` enum with `Envelope`, `Body` (`.hello(profile: StreetPassPeerProfile)`, `.discoveryToken(Data)`), `encode(_:) throws -> Data`, `decode(_:) throws -> Envelope`, `WireError` — consumed by `StreetPassTransport` (Task 5) and `StreetPassEngine` (Task 8).

Note: the design spec described this payload as `interestIDs: [String]`. This plan uses `interests: [Interest]` (the full struct, still capped small) instead — bare canonical ids would silently lose custom, catalog-less interests (e.g. "competitive duck herding" normalizes to an id not present in `InterestCatalog.byID`), breaking mutual-interest matching for exactly the kind of interest the app's evidence-preservation design cares most about. `SharedProfile` already sends full `[Interest]` for the same reason — this keeps the two payloads consistent. The `Interest` struct itself carries no sensitive/private data (id, label, parent, specificity, custom flag only — no evidence text), so this does not widen what StreetPass reveals.

- [ ] **Step 1: Create the model**

Create `ios/UWBBumpTest/Model/StreetPassPeerProfile.swift`:

```swift
import Foundation

/// The ambient StreetPass broadcast payload: what one phone tells any nearby
/// StreetPass peer about itself, before any mutual confirmation. Deliberately
/// smaller than `SharedProfile` — no bio, no experiences/goals, no evidence.
struct StreetPassPeerProfile: Codable, Equatable, Sendable {
    /// Transient, session-scoped identity. Never a stable user id.
    var id: String
    var displayName: String
    /// Small square JPEG, same bounding discipline as ProfilePhoto. Optional.
    var avatarThumbnail: Data?
    /// Full Interest structs (not bare canonical ids), capped small, so a
    /// custom catalog-less interest still round-trips correctly for
    /// mutual-interest matching.
    var interests: [Interest]

    static let maxInterests = 5

    init(id: String, displayName: String, avatarThumbnail: Data? = nil, interests: [Interest]) {
        self.id = id
        self.displayName = displayName
        self.avatarThumbnail = avatarThumbnail
        self.interests = Array(interests.prefix(Self.maxInterests))
    }
}
```

- [ ] **Step 2: Write the failing tests**

Append to `ios/BumpTests/StreetPassTests.swift`:

```swift

// MARK: - Peer profile

final class StreetPassPeerProfileTests: XCTestCase {
    func testInterestListIsCappedAtFive() {
        let seven = (1...7).map { Interest(id: "i\($0)", label: "I\($0)") }
        let profile = StreetPassPeerProfile(id: "p#1", displayName: "Sam", interests: seven)
        XCTAssertEqual(profile.interests.count, 5)
        XCTAssertEqual(profile.interests.map(\.id), ["i1", "i2", "i3", "i4", "i5"])
    }
}

// MARK: - StreetPass wire protocol

final class StreetPassWireTests: XCTestCase {
    func testRoundTrip() throws {
        let profile = StreetPassPeerProfile(id: "p#1", displayName: "Sam",
                                            interests: [InterestCatalog.byID["jazz"]!])
        let data = try StreetPassWire.encode(.hello(profile: profile))
        let envelope = try StreetPassWire.decode(data)
        guard case .hello(let decoded) = envelope.body else { return XCTFail("wrong body") }
        XCTAssertEqual(decoded, profile)
        XCTAssertEqual(envelope.v, StreetPassWire.version)
    }

    func testDiscoveryTokenRoundTrip() throws {
        let bytes = Data([0x01, 0x02, 0x03])
        let data = try StreetPassWire.encode(.discoveryToken(bytes))
        let envelope = try StreetPassWire.decode(data)
        guard case .discoveryToken(let decoded) = envelope.body else { return XCTFail("wrong body") }
        XCTAssertEqual(decoded, bytes)
    }

    func testOversizeFrameIsRejectedBeforeDecoding() {
        let junk = Data(repeating: 0x41, count: StreetPassWire.maxFrame + 1)
        XCTAssertThrowsError(try StreetPassWire.decode(junk)) { error in
            XCTAssertEqual(error as? StreetPassWire.WireError, .tooLarge(junk.count))
        }
    }

    func testMalformedJSONDoesNotCrash() {
        XCTAssertThrowsError(try StreetPassWire.decode(Data([0x7B, 0x00, 0xFF])))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/StreetPassWireTests -only-testing:BumpTests/StreetPassPeerProfileTests`
Expected: build failure — `StreetPassWire` doesn't exist yet.

- [ ] **Step 4: Implement `StreetPassWire`**

Create `ios/UWBBumpTest/Service/StreetPass/StreetPassWireProtocol.swift`:

```swift
import Foundation

/// Versioned message envelope for the StreetPass ambient-discovery transport.
/// Deliberately separate from `Wire` — StreetPass has no room/coordinator
/// concept and only ever carries the small teaser payload, never a full
/// SharedProfile. Same idempotency/bounding discipline as `Wire`.
enum StreetPassWire {
    static let version = 1
    /// Small on purpose: this payload is a teaser, capped avatar and
    /// interests, never a full profile.
    static let maxFrame = 16 * 1024

    struct Envelope: Codable {
        var v: Int = StreetPassWire.version
        var id: String = UUID().uuidString
        var body: Body
    }

    enum Body: Codable {
        /// Either direction, sent once a direct link is established.
        case hello(profile: StreetPassPeerProfile)
        /// Either direction. Archived NIDiscoveryToken bytes.
        case discoveryToken(Data)
    }

    static func encode(_ body: Body) throws -> Data {
        let data = try JSONEncoder().encode(Envelope(body: body))
        guard data.count <= maxFrame else { throw WireError.tooLarge(data.count) }
        return data
    }

    static func decode(_ data: Data) throws -> Envelope {
        guard data.count <= maxFrame else { throw WireError.tooLarge(data.count) }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.v == version else { throw WireError.badVersion(envelope.v) }
        return envelope
    }

    enum WireError: Error, LocalizedError, Equatable {
        case tooLarge(Int)
        case badVersion(Int)

        var errorDescription: String? {
            switch self {
            case .tooLarge(let n): return "StreetPass message too large (\(n) bytes)."
            case .badVersion(let v):
                return "This phone speaks StreetPass protocol v\(StreetPassWire.version); the other sent v\(v)."
            }
        }
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/StreetPassWireTests -only-testing:BumpTests/StreetPassPeerProfileTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/UWBBumpTest/Model/StreetPassPeerProfile.swift \
        ios/UWBBumpTest/Service/StreetPass/StreetPassWireProtocol.swift \
        ios/BumpTests/StreetPassTests.swift
git commit -m "Add StreetPassPeerProfile model and the StreetPassWire protocol"
```

---

### Task 4: `StreetPassEncounter` model + `StreetPassNotifier` copy builder

**Files:**
- Create: `ios/UWBBumpTest/Model/StreetPassEncounter.swift`
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassNotifier.swift`
- Modify: `ios/BumpTests/StreetPassTests.swift` (append)

**Interfaces:**
- Produces: `StreetPassEncounter` (`Identifiable, Equatable`, fields `id: String`, `displayName: String`, `avatarThumbnail: Data?`, `mutualInterestStatement: String?`) — consumed by `StreetPassEngine` (Task 8), `StreetPassSheet` (Task 9), `StreetPassNotifier`.
- Produces: `StreetPassNotifier.copy(for: StreetPassEncounter) -> (title: String, body: String)` — pure, consumed by the live notifier added in Task 7.

- [ ] **Step 1: Create the encounter model**

Create `ios/UWBBumpTest/Model/StreetPassEncounter.swift`:

```swift
import Foundation

/// A single StreetPass encounter, ephemeral and in-memory only — never
/// persisted, never logged to disk. Cleared on dismiss or peer disconnect.
struct StreetPassEncounter: Identifiable, Equatable {
    /// The peer's transient StreetPass transport id.
    let id: String
    let displayName: String
    let avatarThumbnail: Data?
    /// The one grounded, shared interest to tease, already phrased by
    /// InterestMatcher (e.g. "You're both into jazz piano."). nil when there
    /// is no mutual interest — never invented, never substituted.
    let mutualInterestStatement: String?
}
```

- [ ] **Step 2: Write the failing tests**

Append to `ios/BumpTests/StreetPassTests.swift`:

```swift

// MARK: - Notifier copy

final class StreetPassNotifierTests: XCTestCase {
    private func encounter(mutual: String? = nil) -> StreetPassEncounter {
        StreetPassEncounter(id: "p#1", displayName: "Sam", avatarThumbnail: nil,
                            mutualInterestStatement: mutual)
    }

    func testBaseCopyIsAlwaysPresentAndSecondLineEmptyWithNoMutualInterest() {
        let copy = StreetPassNotifier.copy(for: encounter())
        XCTAssertEqual(copy.title, "hey, this person just walked by you. bump them?")
        XCTAssertEqual(copy.body, "")
    }

    func testSecondLineIsTheExactMutualInterestStatementWhenPresent() {
        let copy = StreetPassNotifier.copy(for: encounter(mutual: "You're both into jazz piano."))
        XCTAssertEqual(copy.body, "You're both into jazz piano.")
    }

    func testNeverInventsAnInterestLine() {
        XCTAssertFalse(StreetPassNotifier.copy(for: encounter()).body.contains("both"))
    }
}
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/StreetPassNotifierTests`
Expected: build failure — `StreetPassNotifier` doesn't exist yet.

- [ ] **Step 4: Implement the pure copy builder**

Create `ios/UWBBumpTest/Service/StreetPass/StreetPassNotifier.swift`:

```swift
import Foundation

/// Builds StreetPass notification/sheet copy. Pure and synchronous, so the
/// exact wording is unit-testable without UNUserNotificationCenter. The live
/// UNUserNotificationCenter wrapper is added alongside this in a later task.
enum StreetPassNotifier {
    static func copy(for encounter: StreetPassEncounter) -> (title: String, body: String) {
        let title = "hey, this person just walked by you. bump them?"
        return (title, encounter.mutualInterestStatement ?? "")
    }
}
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:BumpTests/StreetPassNotifierTests`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add ios/UWBBumpTest/Model/StreetPassEncounter.swift \
        ios/UWBBumpTest/Service/StreetPass/StreetPassNotifier.swift \
        ios/BumpTests/StreetPassTests.swift
git commit -m "Add StreetPassEncounter model and the pure StreetPassNotifier copy builder"
```

---

### Task 5: `StreetPassTransport` (MultipeerConnectivity)

**Files:**
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassTransport.swift`
- Modify: `ios/UWBBumpTest/Info.plist`

**Interfaces:**
- Consumes: `StreetPassConfig` (Task 2), `StreetPassWire`, `StreetPassPeerProfile` (Task 3), the module-level `SeenMessages` struct (already defined in `ios/UWBBumpTest/Service/WireProtocol.swift`, not nested inside `Wire`), the `String.trimmed()` extension (`ios/UWBBumpTest/Model/Interest.swift`).
- Produces: `@MainActor final class StreetPassTransport: NSObject, ObservableObject` with `var config: StreetPassConfig`, `func start(displayName: String)`, `func stop()`, `func send(_ body: StreetPassWire.Body, to peerID: String)`, `var myID: String`, `@Published var connectedPeerIDs: Set<String>`, callbacks `var onMessage: ((_ from: String, _ envelope: StreetPassWire.Envelope) -> Void)?`, `var onPeerJoined: ((String) -> Void)?`, `var onPeerLeft: ((String) -> Void)?`, `var onLog: ((String) -> Void)?` — consumed by `StreetPassEngine` (Task 8).

This is a framework-glue class wrapping `MultipeerConnectivity` delegate callbacks, following the exact same pattern as the existing (untested-by-XCTest) `PeerTransport.swift`. Per this repo's established convention, framework-glue classes like this are validated by a successful build plus manual on-hardware testing, not by XCTest — the Simulator has no radio to exercise these delegate paths, and `RangingService.swift`/`PeerTransport.swift`/`MotionDetector.swift` have no direct unit tests either, for the same reason. All the decision logic this class depends on (`StreetPassEncounterGate`, `StreetPassWire`, `StreetPassPeerProfile`) is already independently tested in Tasks 2-3.

- [ ] **Step 1: Implement `StreetPassTransport`**

Create `ios/UWBBumpTest/Service/StreetPass/StreetPassTransport.swift`:

```swift
import Foundation
import MultipeerConnectivity

/// Ambient StreetPass peer discovery, fully separate from `PeerTransport`.
/// There is no room code and no coordinator: any two phones advertising this
/// service connect to each other automatically, bounded by
/// `config.maxConcurrentPeers`. This is a deliberately different trust model
/// from `PeerTransport`, which never connects to an unscoped stranger —
/// StreetPass's entire purpose is ambient discovery of anyone else running
/// BUMP.
@MainActor
final class StreetPassTransport: NSObject, ObservableObject {

    /// 1–15 chars, lowercase ASCII/digits/hyphen, matching NSBonjourServices
    /// in Info.plist exactly.
    nonisolated static let serviceType = "bump-streetpass"

    @Published private(set) var connectedPeerIDs: Set<String> = []
    var config = StreetPassConfig()

    var onMessage: ((_ from: String, _ envelope: StreetPassWire.Envelope) -> Void)?
    var onPeerJoined: ((String) -> Void)?
    var onPeerLeft: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    private var myPeerID: MCPeerID!
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peersByID: [String: MCPeerID] = [:]
    private var invited: Set<MCPeerID> = []
    private var seen = SeenMessages()

    var myID: String { myPeerID?.displayName ?? "" }

    func start(displayName: String) {
        stop()
        let suffix = String(UUID().uuidString.prefix(4))
        let safeName = String(displayName.trimmed().prefix(24))
        myPeerID = MCPeerID(displayName: "\(safeName.isEmpty ? "Someone" : safeName)#\(suffix)")

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv

        let brw = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        browser = brw

        log("StreetPass transport up (\(myPeerID.displayName))")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session?.disconnect(); session = nil
        peersByID.removeAll(); invited.removeAll()
        connectedPeerIDs = []
    }

    func send(_ body: StreetPassWire.Body, to peerID: String) {
        guard let session, let peer = peersByID[peerID], session.connectedPeers.contains(peer) else { return }
        do {
            try session.send(try StreetPassWire.encode(body), toPeers: [peer], with: .reliable)
        } catch {
            log("StreetPass send failed: \(error.localizedDescription)")
        }
    }

    private func log(_ s: String) { onLog?(s) }

    private func refreshConnected() {
        guard let session else { connectedPeerIDs = []; return }
        connectedPeerIDs = Set(session.connectedPeers.map(\.displayName))
    }
}

// MARK: - MCSessionDelegate

extension StreetPassTransport: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.peersByID[peerID.displayName] = peerID
                self.refreshConnected()
                self.log("StreetPass connected: \(peerID.displayName)")
                self.onPeerJoined?(peerID.displayName)
            case .notConnected:
                self.invited.remove(peerID)
                self.refreshConnected()
                self.log("StreetPass disconnected: \(peerID.displayName)")
                self.onPeerLeft?(peerID.displayName)
            case .connecting:
                self.log("StreetPass connecting: \(peerID.displayName)")
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let envelope = try StreetPassWire.decode(data)
                guard self.seen.accept(envelope.id) else { return }
                self.onMessage?(peerID.displayName, envelope)
            } catch {
                self.log("StreetPass bad frame from \(peerID.displayName): \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_ s: MCSession, didReceive: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - Browsing

extension StreetPassTransport: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.peersByID[peerID.displayName] = peerID
            guard let session = self.session, !session.connectedPeers.contains(peerID),
                  !self.invited.contains(peerID) else { return }
            guard session.connectedPeers.count < self.config.maxConcurrentPeers else {
                self.log("StreetPass at the \(self.config.maxConcurrentPeers)-peer cap; not inviting \(peerID.displayName)")
                return
            }
            // Deterministic lead avoids two crossing invitations, same trick
            // PeerTransport uses for its direct-link handshake.
            guard self.myPeerID.displayName < peerID.displayName else { return }
            self.invited.insert(peerID)
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.log("StreetPass lost sight of \(peerID.displayName)") }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.log("StreetPass browse failed: \(error.localizedDescription)") }
    }
}

// MARK: - Advertising

extension StreetPassTransport: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            guard let session = self.session else { return invitationHandler(false, nil) }
            let atCap = session.connectedPeers.count >= self.config.maxConcurrentPeers
            if atCap {
                self.log("StreetPass at cap, refused \(peerID.displayName)")
                invitationHandler(false, nil)
            } else {
                self.peersByID[peerID.displayName] = peerID
                invitationHandler(true, session)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.log("StreetPass advertise failed: \(error.localizedDescription)") }
    }
}
```

- [ ] **Step 2: Add the StreetPass Bonjour services to Info.plist**

In `ios/UWBBumpTest/Info.plist`, find the existing `NSBonjourServices` array:

```xml
	<key>NSBonjourServices</key>
	<array>
		<string>_bump-uwb._tcp</string>
		<string>_bump-uwb._udp</string>
	</array>
```

Replace it with:

```xml
	<key>NSBonjourServices</key>
	<array>
		<string>_bump-uwb._tcp</string>
		<string>_bump-uwb._udp</string>
		<string>_bump-streetpass._tcp</string>
		<string>_bump-streetpass._udp</string>
	</array>
```

- [ ] **Step 3: Verify the project still builds**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ios/UWBBumpTest/Service/StreetPass/StreetPassTransport.swift ios/UWBBumpTest/Info.plist
git commit -m "Add StreetPassTransport (separate MultipeerConnectivity service)"
```

---

### Task 6: `StreetPassRanging` (NearbyInteraction)

**Files:**
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassRanging.swift`

**Interfaces:**
- Consumes: `StreetPassConfig` (Task 2).
- Produces: `@MainActor final class StreetPassRanging: NSObject, ObservableObject` with `var config: StreetPassConfig`, `@Published var isSupported: Bool`, `@Published var measurements: [String: Measurement]`, `func prepareSession(for peerID: String) -> Data?`, `func acceptToken(_ data: Data, from peerID: String)`, `func endSession(for peerID: String)`, `func stopAll()`, `func pauseAll()`, `func resumeAll()`, `var onMeasurement: ((_ peerID: String, _ distance: Double) -> Void)?`, `var onLog: ((String) -> Void)?` — consumed by `StreetPassEngine` (Task 8).

Same framework-glue rationale as Task 5: this mirrors `RangingService.swift`'s existing, unit-untested pattern exactly. It gets its own class (not a generalized/shared `RangingService`) so its concurrent-peer cap and pause/resume lifecycle stay fully independent of the room-based ranging pipeline — deliberate duplication of a proven pattern, not a shared abstraction neither side needs yet.

- [ ] **Step 1: Implement `StreetPassRanging`**

Create `ios/UWBBumpTest/Service/StreetPass/StreetPassRanging.swift`:

```swift
import Foundation
import NearbyInteraction

/// UWB ranging for StreetPass peers. Same lifecycle discipline as
/// RangingService (one NISession per peer, capability checked at runtime,
/// pause/resume across backgrounding, stale-measurement expiry), kept as its
/// own class with its own cap so StreetPass never contends with the
/// active-bump pipeline's RangingService.maxConcurrentPeers ceiling.
@MainActor
final class StreetPassRanging: NSObject, ObservableObject {

    struct Measurement: Equatable {
        let peerID: String
        let distance: Double?      // metres; nil means UNKNOWN, never 0
        let at: Date
        var age: TimeInterval { Date().timeIntervalSince(at) }
    }

    @Published private(set) var isSupported = false
    @Published private(set) var measurements: [String: Measurement] = [:]
    var config = StreetPassConfig()

    var onMeasurement: ((_ peerID: String, _ distance: Double) -> Void)?
    var onLog: ((String) -> Void)?

    private var sessions: [String: NISession] = [:]
    private var peerForSession: [ObjectIdentifier: String] = [:]
    private var peerTokens: [String: NIDiscoveryToken] = [:]
    private var staleTimer: Timer?

    override init() {
        super.init()
        isSupported = NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    @discardableResult
    func prepareSession(for peerID: String) -> Data? {
        guard isSupported else { return nil }
        guard sessions.count < config.maxConcurrentPeers || sessions[peerID] != nil else {
            log("StreetPass at the \(config.maxConcurrentPeers)-peer ranging limit; not ranging \(peerID)")
            return nil
        }
        let session = sessions[peerID] ?? makeSession(for: peerID)
        guard let token = session.discoveryToken else { return nil }
        return try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    private func makeSession(for peerID: String) -> NISession {
        let session = NISession()
        session.delegate = self
        session.delegateQueue = .main
        sessions[peerID] = session
        peerForSession[ObjectIdentifier(session)] = peerID
        startStaleTimer()
        return session
    }

    func acceptToken(_ data: Data, from peerID: String) {
        guard isSupported,
              let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
        else {
            log("StreetPass could not decode token from \(peerID)")
            return
        }
        peerTokens[peerID] = token
        let session = sessions[peerID] ?? makeSession(for: peerID)
        session.run(NINearbyPeerConfiguration(peerToken: token))
        log("StreetPass ranging \(peerID)")
    }

    func endSession(for peerID: String) {
        if let session = sessions.removeValue(forKey: peerID) {
            peerForSession[ObjectIdentifier(session)] = nil
            session.invalidate()
        }
        peerTokens[peerID] = nil
        measurements[peerID] = nil
        if sessions.isEmpty { stopStaleTimer() }
    }

    func stopAll() {
        sessions.values.forEach { $0.invalidate() }
        sessions.removeAll(); peerForSession.removeAll()
        peerTokens.removeAll(); measurements.removeAll()
        stopStaleTimer()
    }

    func pauseAll() {
        sessions.values.forEach { $0.pause() }
        measurements.removeAll()
    }

    func resumeAll() {
        for (peerID, session) in sessions {
            guard let token = peerTokens[peerID] else { continue }
            session.run(NINearbyPeerConfiguration(peerToken: token))
        }
    }

    private func startStaleTimer() {
        guard staleTimer == nil else { return }
        staleTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireStale() }
        }
    }

    private func stopStaleTimer() { staleTimer?.invalidate(); staleTimer = nil }

    private func expireStale() {
        measurements = measurements.filter { $0.value.age <= config.measurementFreshness }
    }

    private func log(_ s: String) { onLog?(s) }
}

// MARK: - NISessionDelegate

extension StreetPassRanging: NISessionDelegate {

    nonisolated func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)],
                  let object = nearbyObjects.first else { return }
            let distance = object.distance.map(Double.init)
            self.measurements[peerID] = Measurement(peerID: peerID, distance: distance, at: Date())
            if let distance { self.onMeasurement?(peerID, distance) }
        }
    }

    nonisolated func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject],
                             reason: NINearbyObject.RemovalReason) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)] else { return }
            self.measurements[peerID] = nil
            switch reason {
            case .peerEnded:
                self.endSession(for: peerID)
            case .timeout:
                if let token = self.peerTokens[peerID] { session.run(NINearbyPeerConfiguration(peerToken: token)) }
            @unknown default: break
            }
        }
    }

    nonisolated func sessionWasSuspended(_ session: NISession) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)] else { return }
            self.measurements[peerID] = nil
        }
    }

    nonisolated func sessionSuspensionEnded(_ session: NISession) {
        Task { @MainActor in
            guard let peerID = self.peerForSession[ObjectIdentifier(session)],
                  let token = self.peerTokens[peerID] else { return }
            session.run(NINearbyPeerConfiguration(peerToken: token))
        }
    }

    nonisolated func session(_ session: NISession, didInvalidateWith error: Error) {
        Task { @MainActor in
            if let peerID = self.peerForSession[ObjectIdentifier(session)] {
                self.measurements[peerID] = nil
                self.sessions[peerID] = nil
                self.peerTokens[peerID] = nil
            }
            self.peerForSession[ObjectIdentifier(session)] = nil
        }
    }
}
```

- [ ] **Step 2: Verify the project still builds**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ios/UWBBumpTest/Service/StreetPass/StreetPassRanging.swift
git commit -m "Add StreetPassRanging (independent NISession-per-peer lifecycle)"
```

---

### Task 7: `StreetPassNotifier` live wrapper (UNUserNotificationCenter)

**Files:**
- Modify: `ios/UWBBumpTest/Service/StreetPass/StreetPassNotifier.swift`

**Interfaces:**
- Produces (added to the existing `StreetPassNotifier` enum): `static func requestAuthorizationIfNeeded()`, `static func notify(_ encounter: StreetPassEncounter)` — consumed by `StreetPassEngine` (Task 8).

No stale-payload tap handling is implemented here: this architecture is fully stateless (Task 8's `stop()` clears all StreetPass state on backgrounding), so there is nothing meaningful to reconstruct from a notification's `userInfo` on tap — the OS already brings the app to the foreground on tap with no extra code, and if the peer is still physically nearby, a fresh discovery/ranging cycle naturally re-qualifies and shows the sheet again. Building a `UNUserNotificationCenterDelegate` here would be speculative code for a deep link the chosen architecture doesn't need.

- [ ] **Step 1: Add the live wrapper**

Append to `ios/UWBBumpTest/Service/StreetPass/StreetPassNotifier.swift` (after the `enum StreetPassNotifier { ... }` block, same file):

```swift

import UserNotifications

extension StreetPassNotifier {
    /// Requests notification permission once, lazily — only when StreetPass
    /// actually starts, not at app launch.
    static func requestAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Schedules an immediate local notification. StreetPassEngine only
    /// calls this when the app is not active at the moment of a qualifying
    /// encounter — while foregrounded, the custom in-app sheet is the only
    /// UI, with no redundant system banner.
    static func notify(_ encounter: StreetPassEncounter) {
        let (title, body) = copy(for: encounter)
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Minimal, temporary payload: the peer's transient transport id only.
        content.userInfo = ["streetPassPeerID": encounter.id]
        let request = UNNotificationRequest(
            identifier: "streetpass-\(encounter.id)-\(UUID().uuidString)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
```

- [ ] **Step 2: Verify the project still builds**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Run the full test suite to confirm nothing regressed**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: all existing tests plus the new `StreetPassNotifierTests` still PASS.

- [ ] **Step 4: Commit**

```bash
git add ios/UWBBumpTest/Service/StreetPass/StreetPassNotifier.swift
git commit -m "Add the live UNUserNotificationCenter wrapper to StreetPassNotifier"
```

---

### Task 8: `StreetPassEngine`

**Files:**
- Create: `ios/UWBBumpTest/Service/StreetPass/StreetPassEngine.swift`

**Interfaces:**
- Consumes: `Store` (`ios/UWBBumpTest/Service/Store.swift`), `StreetPassTransport` (Task 5), `StreetPassRanging` (Task 6), `StreetPassEncounterGate`/`StreetPassConfig` (Task 2), `StreetPassPeerProfile`/`StreetPassWire` (Task 3), `StreetPassEncounter`/`StreetPassNotifier` (Tasks 4 & 7), `InterestMatcher.overlap(_:_:limit:)` (Task 1), `Interest`/`InterestCatalog` (`Model/Interest.swift`).
- Produces: `@MainActor final class StreetPassEngine: ObservableObject` with `init(store: Store)`, `let transport: StreetPassTransport`, `let ranging: StreetPassRanging`, `@Published private(set) var pendingEncounter: StreetPassEncounter?`, `func start()`, `func stop()`, `func handleScenePhase(_ scenePhase: ScenePhase)`, `func dismissPendingEncounter()` — consumed by `RootView` (Task 9).

This orchestrator is deliberately thin: every real decision lives in `StreetPassEncounterGate` and `InterestMatcher`, already unit-tested. Like `BumpEngine` itself, it has no dedicated XCTest coverage — exercising it would require mocking `MultipeerConnectivity`/`NearbyInteraction`, which this codebase does not do anywhere (verify by build success plus the manual two-phone procedure in Task 10).

Known, accepted limitation: `handleMeasurement` drops a `.qualified` verdict silently if `peerProfiles[peer]` isn't populated yet (the `.hello` message hasn't arrived). Since the gate has already latched at that point, that specific encounter is lost rather than deferred, and won't re-fire until the peer exits and re-enters range. In practice `.hello` and the discovery token are sent together the instant a peer connects (`peerJoined`), and NI session setup is normally slower than that round-trip, so this window is narrow — but it is a real, unaddressed race, not a guarantee. Not worth adding buffering/retry machinery for a demo-scope feature; documented here rather than silently absorbed.

- [ ] **Step 1: Implement `StreetPassEngine`**

Create `ios/UWBBumpTest/Service/StreetPass/StreetPassEngine.swift`:

```swift
import Foundation
import SwiftUI

/// Orchestrates the StreetPass ambient-encounter pipeline: transport
/// discovery -> UWB ranging -> per-peer encounter gate -> mutual-interest
/// teaser -> in-app sheet, or (only if backgrounded at that instant) a local
/// notification. Every real decision lives in StreetPassEncounterGate and
/// InterestMatcher; this class only wires them together. Foreground-only —
/// stops and clears all state the moment the app leaves .active, mirroring
/// BumpEngine's own scene-phase policy. Nothing here is persisted.
@MainActor
final class StreetPassEngine: ObservableObject {

    @Published private(set) var pendingEncounter: StreetPassEncounter?

    let transport = StreetPassTransport()
    let ranging = StreetPassRanging()

    private let store: Store
    private let config = StreetPassConfig()
    private var gates: [String: StreetPassEncounterGate] = [:]
    private var peerProfiles: [String: StreetPassPeerProfile] = [:]
    private var isActive = false
    private var isAppActive = true

    init(store: Store) {
        self.store = store
        transport.config = config
        ranging.config = config
        wireUp()
    }

    private func wireUp() {
        transport.onPeerJoined = { [weak self] peer in self?.peerJoined(peer) }
        transport.onPeerLeft = { [weak self] peer in self?.peerLeft(peer) }
        transport.onMessage = { [weak self] from, envelope in self?.handle(envelope.body, from: from) }
        ranging.onMeasurement = { [weak self] peer, distance in self?.handleMeasurement(peer, distance) }
    }

    func start() {
        guard !isActive, store.profile.isComplete else { return }
        isActive = true
        transport.start(displayName: store.profile.displayName)
        StreetPassNotifier.requestAuthorizationIfNeeded()
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        transport.stop()
        ranging.stopAll()
        gates.removeAll()
        peerProfiles.removeAll()
        pendingEncounter = nil
    }

    func handleScenePhase(_ scenePhase: ScenePhase) {
        switch scenePhase {
        case .active:
            isAppActive = true
            guard store.profile.isComplete else { return }
            if !isActive { start() } else { ranging.resumeAll() }
        case .background, .inactive:
            isAppActive = false
            stop()
        @unknown default: break
        }
    }

    func dismissPendingEncounter() {
        pendingEncounter = nil
    }

    // MARK: Wiring

    private func peerJoined(_ peer: String) {
        transport.send(.hello(profile: myPeerProfile()), to: peer)
        if let token = ranging.prepareSession(for: peer) {
            transport.send(.discoveryToken(token), to: peer)
        }
    }

    private func peerLeft(_ peer: String) {
        ranging.endSession(for: peer)
        gates[peer] = nil
        peerProfiles[peer] = nil
        if pendingEncounter?.id == peer { pendingEncounter = nil }
    }

    private func handle(_ body: StreetPassWire.Body, from peer: String) {
        switch body {
        case .hello(let profile):
            peerProfiles[peer] = profile
        case .discoveryToken(let data):
            ranging.acceptToken(data, from: peer)
        }
    }

    private func handleMeasurement(_ peer: String, _ distance: Double) {
        var gate = gates[peer] ?? StreetPassEncounterGate(
            proximityThreshold: config.proximityThreshold,
            consecutiveReadingsRequired: config.consecutiveReadingsRequired,
            exitHysteresisMargin: config.exitHysteresisMargin,
            cooldown: config.cooldown)
        let verdict = gate.feed(distance: distance, now: ProcessInfo.processInfo.systemUptime)
        gates[peer] = gate

        guard verdict == .qualified, let profile = peerProfiles[peer] else { return }
        let mutual = InterestMatcher.overlap(store.profile.interests, profile.interests, limit: 1).first
        let encounter = StreetPassEncounter(id: peer, displayName: profile.displayName,
                                            avatarThumbnail: profile.avatarThumbnail,
                                            mutualInterestStatement: mutual?.statement)
        pendingEncounter = encounter
        // Only the narrow app-not-active window gets a system notification —
        // while foregrounded, setting pendingEncounter above is enough to
        // show the custom sheet; no redundant banner.
        if !isAppActive {
            StreetPassNotifier.notify(encounter)
        }
    }

    private func myPeerProfile() -> StreetPassPeerProfile {
        StreetPassPeerProfile(id: transport.myID, displayName: store.profile.displayName,
                              avatarThumbnail: store.profile.photo,
                              interests: store.profile.interests)
    }
}
```

- [ ] **Step 2: Verify the project still builds**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
git add ios/UWBBumpTest/Service/StreetPass/StreetPassEngine.swift
git commit -m "Add StreetPassEngine orchestrator"
```

---

### Task 9: `StreetPassSheet` view + `RootView` wiring + demo mode

**Files:**
- Create: `ios/UWBBumpTest/View/StreetPassSheet.swift`
- Modify: `ios/UWBBumpTest/View/RootView.swift`
- Modify: `ios/UWBBumpTest/View/DemoMode.swift`

**Interfaces:**
- Consumes: `StreetPassEngine` (Task 8), `StreetPassEncounter` (Task 4), `Avatar`/`StatusPill`/`BumpFont`/`BumpColor`/`Space`/button styles (`ios/UWBBumpTest/Design/Components.swift`, `Theme.swift`), `BumpEngine.startNearby()` (existing, unchanged).
- Produces: `StreetPassSheet: View` with `init(encounter: StreetPassEncounter, onBumpThem: () -> Void, onNotNow: () -> Void)`; a new `DemoMode.streetpass` case; `RootView` now owns and starts a `StreetPassEngine`.

- [ ] **Step 1: Create the sheet view**

Create `ios/UWBBumpTest/View/StreetPassSheet.swift`:

```swift
import SwiftUI

/// The StreetPass teaser: shown as soon as a nearby encounter qualifies,
/// while the app is foregrounded. Never a full profile — just enough to be
/// curious, and at most one mutual interest.
struct StreetPassSheet: View {
    let encounter: StreetPassEncounter
    var onBumpThem: () -> Void
    var onNotNow: () -> Void

    var body: some View {
        VStack(spacing: Space.l) {
            Avatar(name: encounter.displayName, size: 96, photo: encounter.avatarThumbnail)
                .padding(.top, Space.m)

            VStack(spacing: Space.s) {
                Text("hey, this person just walked by you.")
                    .font(BumpFont.body)
                    .foregroundStyle(BumpColor.secondaryText)
                    .multilineTextAlignment(.center)
                Text("Bump them?")
                    .font(BumpFont.screenTitle)
                    .foregroundStyle(BumpColor.navy)
            }

            if let statement = encounter.mutualInterestStatement {
                StatusPill(text: statement, tone: .good)
            }

            VStack(spacing: Space.s) {
                Button("Bump them", action: onBumpThem)
                    .buttonStyle(.bumpPrimary)
                Button("Not now", action: onNotNow)
                    .buttonStyle(.bumpSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Space.gutter)
        .accessibilityElement(children: .contain)
    }
}

#Preview {
    ZStack {
        BumpColor.background.ignoresSafeArea()
        StreetPassSheet(
            encounter: .init(id: "demo#0002", displayName: "Priya (demo)", avatarThumbnail: nil,
                             mutualInterestStatement: "You're both into photography."),
            onBumpThem: {}, onNotNow: {}
        )
    }
}
```

- [ ] **Step 2: Wire `StreetPassEngine` and the sheet into `RootView`**

In `ios/UWBBumpTest/View/RootView.swift`, replace lines 3-19 (the property declarations through the end of `init()`):

```swift
struct RootView: View {
    @StateObject private var store: Store
    @StateObject private var engine: BumpEngine
    @StateObject private var streetPassEngine: StreetPassEngine
    @Environment(\.scenePhase) private var scenePhase

    @State private var stage: Stage
    /// DEBUG demo only: a pre-seeded onboarding model with sample data.
    @State private var demoOnboarding: OnboardingModel?

    enum Stage { case welcome, onboarding, main }

    init() {
        let store = Store()
        _store = StateObject(wrappedValue: store)
        _engine = StateObject(wrappedValue: BumpEngine(store: store))
        _streetPassEngine = StateObject(wrappedValue: StreetPassEngine(store: store))
        _stage = State(initialValue: store.profile.isComplete ? .main : .welcome)
    }
```

Then, in the `.main` case of `content` (currently lines 44-53), add the sheet modifier to the `TabView`:

```swift
            case .main:
                TabView {
                    BumpScreen(engine: engine, store: store)
                        .tabItem { Label("Bump", systemImage: "hand.tap.fill") }
                    ConnectionsScreen(store: store)
                        .tabItem { Label("Connections", systemImage: "person.2.fill") }
                    YouScreen(store: store, engine: engine)
                        .tabItem { Label("You", systemImage: "person.crop.circle") }
                }
                .tint(BumpColor.action)
                .sheet(item: streetPassSheetBinding) { encounter in
                    StreetPassSheet(
                        encounter: encounter,
                        onBumpThem: {
                            streetPassEngine.dismissPendingEncounter()
                            engine.startNearby()
                        },
                        onNotNow: { streetPassEngine.dismissPendingEncounter() }
                    )
                }
```

Then, in the modifier chain right after `.onChange(of: scenePhase) { _, phase in engine.handleScenePhase(phase) }` (currently line 57), add:

```swift
        .onChange(of: scenePhase) { _, phase in
            engine.handleScenePhase(phase)
            streetPassEngine.handleScenePhase(phase)
        }
        .onChange(of: stage) { _, newStage in
            if newStage == .main { streetPassEngine.start() }
        }
```

(this replaces the single existing `.onChange(of: scenePhase) { _, phase in engine.handleScenePhase(phase) }` line with the two-line version above, and adds the new `.onChange(of: stage)` block right after it)

Finally, add this computed property inside `RootView`, near the other private members (e.g. right after `applyDemoIfRequested()`):

```swift
    private var streetPassSheetBinding: Binding<StreetPassEncounter?> {
        Binding(
            get: { streetPassEngine.pendingEncounter },
            set: { if $0 == nil { streetPassEngine.dismissPendingEncounter() } }
        )
    }
```

- [ ] **Step 3: Add a StreetPass demo case**

In `ios/UWBBumpTest/View/DemoMode.swift`, change the `DemoMode` enum's case list (currently lines 12-19):

```swift
enum DemoMode: String {
    case onboarding, ready, confirm, reveal, connections, you, tools, home, tutorial
    case onboardingIntro = "onboardingintro"
    case onboardingQuestion = "onboardingquestion"
    case onboardingCard = "onboardingcard"
    case timedOut = "timedout"
    case ambiguous
    case unsupported
    case streetpass
```

Then, add a `demoSet` helper for `StreetPassEngine` next to the existing `BumpEngine` one at the bottom of the file (currently lines 45-52):

```swift
#if DEBUG
extension BumpEngine {
    /// Force a UI state for screenshots. DEBUG only, never called at runtime.
    func demoSet(_ phase: Phase, members: [Wire.Member] = []) {
        applyDemo(phase: phase, members: members)
    }
}

extension StreetPassEngine {
    /// Force a pending encounter for screenshots. DEBUG only, never called
    /// at runtime — real encounters only ever come from StreetPassRanging.
    func demoSet(_ encounter: StreetPassEncounter) {
        pendingEncounter = encounter
    }
}
#endif
```

Then, in `RootView.applyDemoIfRequested()` (in `RootView.swift`), add a case to the `switch demo` block, right before the existing `case .connections, .you, .tools, .home, .tutorial:` line:

```swift
        case .streetpass:
            store.profile = PreviewFixtures.profile; stage = .main
            streetPassEngine.demoSet(.init(id: "demo#0002", displayName: "Priya (demo)",
                                           avatarThumbnail: nil,
                                           mutualInterestStatement: "You're both into photography."))
```

- [ ] **Step 4: Verify the project still builds**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Manually inspect the sheet in the Simulator**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build`, then boot the Simulator and run:

```bash
xcrun simctl launch booted com.jaredberesford.uwbbumptest -BumpDemo streetpass
```

Expected: the app opens straight to the Bump tab with the StreetPass sheet presented over it, showing "Priya (demo)", the "hey, this person just walked by you. Bump them?" copy, and the "You're both into photography." pill. Tapping "Bump them" dismisses the sheet (the DEBUG demo profile has no real nearby peer, so `startNearby()` will simply show "Looking for people nearby…", which is expected in this fixture-only path).

- [ ] **Step 6: Commit**

```bash
git add ios/UWBBumpTest/View/StreetPassSheet.swift ios/UWBBumpTest/View/RootView.swift ios/UWBBumpTest/View/DemoMode.swift
git commit -m "Add StreetPassSheet, wire StreetPassEngine into RootView, add demo mode"
```

---

### Task 10: Full verification + README

**Files:**
- Modify: `ios/README.md`

**Interfaces:** None — this task only runs verification and documents what was built.

- [ ] **Step 1: Run the full test suite**

Run: `xcodebuild test -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
Expected: every existing test still passes, plus all new `StreetPass*Tests` and the three new `InterestMatcherTests` methods.

- [ ] **Step 2: Run a full device-generic build (Debug and Release)**

Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`
Run: `xcodebuild -project UWBBumpTest.xcodeproj -scheme UWBBumpTest -destination 'generic/platform=iOS' -configuration Release CODE_SIGNING_ALLOWED=NO build`
Expected: `BUILD SUCCEEDED` for both.

- [ ] **Step 3: Document StreetPass in `ios/README.md`**

Add a new `## StreetPass` section to `ios/README.md`, right after the existing `## Rooms, pairing and crowded rooms` section (before `## Privacy`):

```markdown
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
```

- [ ] **Step 4: Commit**

```bash
git add ios/README.md
git commit -m "Document StreetPass in ios/README.md"
```

---

## Plan self-review notes

- **Spec coverage:** every component in the spec's Architecture section (§1-10) maps to a task above; the data-flow, error-handling, and testing sections are covered by Tasks 2-9's implementations and tests respectively. Two deliberate deviations from the spec's shorthand are called out explicitly where they occur: `StreetPassPeerProfile.interests: [Interest]` instead of `interestIDs: [String]` (Task 3, correctness rationale), and the `Verdict` case name `.suppressedByCooldown` instead of `.cooldown` (Task 2, cosmetic).
- **Placeholder scan:** no TBDs; every code step is complete, runnable code.
- **Type consistency:** `StreetPassEncounter.mutualInterestStatement`, `StreetPassPeerProfile.interests`, `StreetPassWire.Body` cases, `StreetPassConfig` field names, and `StreetPassEngine`/`StreetPassTransport`/`StreetPassRanging`'s public API are used identically across Tasks 2-9.

**Subagent review pass (post-write):** a dedicated review subagent checked this plan against the real repository state before execution. It confirmed clean: the `PBXFileSystemSynchronizedRootGroup` claim (verified directly in `project.pbxproj` — no exceptions scope out a new `Service/StreetPass/` subfolder), every referenced file/line and API signature (all match the real source verbatim), the `StreetPassTransport`/`StreetPassRanging` MultipeerConnectivity/NearbyInteraction usage against the existing `PeerTransport`/`RangingService` patterns, the `bump-streetpass` service-type length (exactly 15 chars, Apple's ceiling — zero margin, noted), and that no non-goal (entitlements, persistence, background modes, touching `BumpEngine`/`PeerTransport`/`RangingService` internals) is violated. It found and this plan now fixes one real bug: two of the five `StreetPassEncounterGateTests` in Task 2 originally fed `distance: 0.9` to test rearming past `proximityThreshold + exitHysteresisMargin` (0.5 + 0.5 = 1.0) — 0.9 does not clear that boundary, so both tests would have failed against the plan's own implementation. Both now use `1.1`, hand-traced correct against the implementation. The custom `streetPassSheetBinding` in Task 9 (rather than a direct `$streetPassEngine.pendingEncounter` projection) was confirmed necessary, not a bug — `pendingEncounter` is `private(set)`, so a cross-file two-way binding wouldn't compile otherwise.
