import XCTest
@testable import UWBBumpTest

/// The design system's pure maths (Design/ScallopGeometry.swift): the MD3
/// shape formula, the shared-badge morph, and its timing. Foundation only, so
/// these also run off a Mac (they were first run with swift-corelibs-xctest on
/// Linux).
final class DesignTests: XCTestCase {

    private let angles = stride(from: 0.0, to: 2 * Double.pi, by: 0.01).map { $0 }

    func testCircleIsRadiusOneEverywhere() {
        for a in angles {
            XCTAssertEqual(ScallopForm.circle.radius(at: a), 1, accuracy: 1e-12)
        }
    }

    func testScallopRadiusStaysBetweenValleyAndLobe() {
        for form in [ScallopForm.cookie, .clover, .sunny, .flower] + ScallopGeometry.badgeForms {
            for a in angles {
                let r = form.radius(at: a)
                XCTAssertLessThanOrEqual(r, 1 + 1e-12)
                XCTAssertGreaterThanOrEqual(r, 1 - form.depth - 1e-12)
            }
        }
    }

    func testFormulaMatchesTheSite() {
        // web/src/shapes.ts: r = 50 * (1 - depth * (1 - cos(lobes * t)) / 2)
        let t = 0.3
        let site = 50 * (1 - 0.1 * (1 - cos(9 * t)) / 2)
        XCTAssertEqual(ScallopForm.cookie.radius(at: t) * 50, site, accuracy: 1e-12)
    }

    /// Regression: the mockup's morph shrank mid-way because points travelled
    /// in straight lines (with a rotation baked in). A radial blend can never
    /// dip below the smaller of the two forms' valleys at any angle.
    func testBlendedMorphNeverShrinksBelowEitherForm() {
        let forms = ScallopGeometry.badgeForms
        for i in forms.indices {
            let a = forms[i], b = forms[(i + 1) % forms.count]
            let floor = min(1 - a.depth, 1 - b.depth)
            for t in stride(from: 0.0, through: 1.0, by: 0.05) {
                for theta in angles {
                    let r = ScallopGeometry.blendedRadius(a, b, t: t, theta: theta)
                    XCTAssertGreaterThanOrEqual(r, floor - 1e-12, "form \(i) t \(t) θ \(theta)")
                    XCTAssertLessThanOrEqual(r, 1 + 1e-12)
                }
            }
        }
    }

    func testBlendEndpointsAreTheForms() {
        let a = ScallopForm.cookie, b = ScallopForm.clover
        for theta in angles {
            XCTAssertEqual(ScallopGeometry.blendedRadius(a, b, t: 0, theta: theta), a.radius(at: theta), accuracy: 1e-12)
            XCTAssertEqual(ScallopGeometry.blendedRadius(a, b, t: 1, theta: theta), b.radius(at: theta), accuracy: 1e-12)
        }
        // Out-of-range t is clamped.
        XCTAssertEqual(ScallopGeometry.blendedRadius(a, b, t: 2, theta: 0.4), b.radius(at: 0.4), accuracy: 1e-12)
    }

    func testBadgeLoopIsPointFourOfTheSite() {
        // Site: 4 morphs of 1.4s + 0.9s holds ≈ 9.2s. App runs at 0.4x.
        XCTAssertEqual(ScallopGeometry.badgeLoop, 23, accuracy: 0.01)
    }

    func testBadgePhaseHoldsThenMorphs() {
        let loop = 23.0, forms = ScallopGeometry.badgeForms
        let segment = loop / Double(forms.count)

        let start = ScallopGeometry.badgePhase(elapsed: 0, loop: loop)
        XCTAssertEqual(start.from, forms[0])
        XCTAssertEqual(start.to, forms[1])
        XCTAssertEqual(start.t, 0, accuracy: 1e-12)

        // Still holding at 30% of the first segment (hold is 40%).
        XCTAssertEqual(ScallopGeometry.badgePhase(elapsed: segment * 0.3, loop: loop).t, 0, accuracy: 1e-12)

        // Almost at the end of the segment, nearly fully morphed.
        XCTAssertGreaterThan(ScallopGeometry.badgePhase(elapsed: segment * 0.999, loop: loop).t, 0.99)

        // Next segment starts from the next form.
        let second = ScallopGeometry.badgePhase(elapsed: segment * 1.01, loop: loop)
        XCTAssertEqual(second.from, forms[1])
        XCTAssertEqual(second.to, forms[2])

        // The last form morphs back to the first, and the loop wraps.
        let last = ScallopGeometry.badgePhase(elapsed: segment * 3.5, loop: loop)
        XCTAssertEqual(last.from, forms[3])
        XCTAssertEqual(last.to, forms[0])
        XCTAssertEqual(ScallopGeometry.badgePhase(elapsed: loop + 0.1, loop: loop).from, forms[0])
    }

    func testBadgePhaseEaseIsMonotonicWithinASegment() {
        let loop = 23.0, segment = loop / 4
        var previous = -1.0
        for step in 0...200 {
            let t = ScallopGeometry.badgePhase(elapsed: segment * Double(step) / 201, loop: loop).t
            XCTAssertGreaterThanOrEqual(t, previous - 1e-12)
            XCTAssertTrue((0...1).contains(t))
            previous = t
        }
    }

    func testRotationIsOneTurnPerLoop() {
        XCTAssertEqual(ScallopGeometry.badgeRotation(elapsed: 0, loop: 23), 0, accuracy: 1e-9)
        XCTAssertEqual(ScallopGeometry.badgeRotation(elapsed: 11.5, loop: 23), 180, accuracy: 1e-9)
        XCTAssertEqual(ScallopGeometry.badgeRotation(elapsed: 23 + 5.75, loop: 23), 90, accuracy: 1e-9)
    }

    func testInterestsCycleEveryHold() {
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 0, count: 3, hold: 4), 0)
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 3.9, count: 3, hold: 4), 0)
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 4.1, count: 3, hold: 4), 1)
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 8.5, count: 3, hold: 4), 2)
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 12.5, count: 3, hold: 4), 0)
        // One interest never cycles; no interests never crash.
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 99, count: 1, hold: 4), 0)
        XCTAssertEqual(ScallopGeometry.cycleIndex(elapsed: 99, count: 0, hold: 4), 0)
    }

    func testPointsStartAtTwelveOClockInsideTheBox() {
        let size = 200.0
        let pts = ScallopGeometry.points(size: size) { ScallopForm.cookie.radius(at: $0) }
        XCTAssertEqual(pts.count, 180)
        XCTAssertEqual(pts[0].x, 100, accuracy: 1e-9)
        XCTAssertEqual(pts[0].y, 0, accuracy: 1e-9)   // top centre, radius 1 on a lobe
        for p in pts {
            XCTAssertTrue((0...size).contains(p.x) && (0...size).contains(p.y))
        }
    }
}
