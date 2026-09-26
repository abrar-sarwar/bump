import XCTest
@testable import UWBBumpTest

/// Contract check: the real `BumpAPIClient` against a real, locally running
/// `bump-api`. That server should point at a FAKE xAI (not live Grok) so the
/// test is free and deterministic. SKIPPED unless configured:
///
///     TEST_RUNNER_BUMP_API_TEST_URL=http://localhost:8788 \
///     TEST_RUNNER_BUMP_API_NOKEY_URL=http://localhost:8789 \
///     xcodebuild test ... -only-testing:BumpTests/ContractTests
///
/// (xcodebuild forwards `TEST_RUNNER_`-prefixed variables to the test process.)
final class ContractTests: XCTestCase {

    private func client(_ key: String) throws -> BumpAPIClient {
        guard let raw = ProcessInfo.processInfo.environment[key], let client = BumpAPIClient.resolve(override: raw) else {
            throw XCTSkip("\(key) not set — contract test skipped (see file header).")
        }
        return client
    }

    func testHealth() async throws {
        let health = try await client("BUMP_API_TEST_URL").health()
        XCTAssertTrue(health.ok)
        XCTAssertTrue(health.grokConfigured)
    }

    func testDraftFollowupAndPointsDecodeAndValidate() async throws {
        let api = try client("BUMP_API_TEST_URL")
        let text = "I play jazz piano and I'm into coffee."

        let draft = try await api.draft(transcript: text)
        XCTAssertEqual(draft.generator.provider, "xai")
        let facts = Grounding.facts(draft.facts, groundedIn: text, limit: 12)
        XCTAssertTrue(facts.contains { $0.text == "Jazz piano" })
        XCTAssertFalse(facts.contains { $0.text == "Skydiving" }, "server should already have dropped it")
        XCTAssertNotNil(Grounding.question(draft.question, notIn: []))

        let follow = try await api.followup(known: [(.interest, "Jazz piano")], asked: ["What kind of jazz do you play?"],
                                            answer: "Mostly standards, in a trio")
        XCTAssertEqual(follow.facts.first?.source, "a trio")

        let mine = SharedProfile(displayName: "A", bio: "", interests: [InterestCatalog.byID["climbing"]!])
        let theirs = SharedProfile(displayName: "B", bio: "", interests: [InterestCatalog.byID["climbing"]!])
        let insight = await ConversationService.makeInsight(mine: mine, theirs: theirs, cloud: api)
        XCTAssertEqual(insight.openerSource, .grok)
        XCTAssertEqual(insight.talkingPoints.map(\.id), ["shared:climbing"], "invented id dropped end to end")
    }

    func testTranscribeRoundTrip() async throws {
        let api = try client("BUMP_API_TEST_URL")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("contract-\(UUID()).m4a")
        try Data(repeating: 0x42, count: 2048).write(to: file)   // the fake doesn't decode audio
        defer { try? FileManager.default.removeItem(at: file) }
        let uploaded = expectation(description: "upload finished")
        let result = try await api.transcribe(fileURL: file) { uploaded.fulfill() }
        await fulfillment(of: [uploaded], timeout: 5)
        XCTAssertFalse(result.transcript.isEmpty)
    }

    func testMissingKeyMapsToNotConfigured() async throws {
        let api = try client("BUMP_API_NOKEY_URL")
        do {
            _ = try await api.draft(transcript: "hello there")
            XCTFail("expected not configured")
        } catch {
            XCTAssertEqual(error as? BumpAPIError, .notConfigured)
        }
    }

    func testUnreachableServerMapsToOffline() async throws {
        let api = BumpAPIClient(baseURL: URL(string: "http://127.0.0.1:9")!)
        do {
            _ = try await api.health()
            XCTFail("expected offline")
        } catch {
            XCTAssertEqual(error as? BumpAPIError, .offline)
        }
    }
}
