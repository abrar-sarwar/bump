import Foundation

/// The MD3 shape vocabulary, as maths. Same formula as the marketing site
/// (`web/src/shapes.ts` scallop) and the mockup (`ios-mockup/shapes.js`):
///
///     r(θ) = 1 - depth · (1 - cos(lobes · θ)) / 2
///
/// 9 / 0.1 is MD3's "cookie", 4 / 0.35 its "clover", 12 / 0.06 "sunny",
/// 6 / 0.2 "flower"; depth 0 is a circle.
///
/// Foundation only (no SwiftUI), so it is unit-testable anywhere. `ScallopShape`
/// in Components.swift turns it into a SwiftUI `Shape`.
struct ScallopForm: Equatable, Sendable {
    var lobes: Double
    var depth: Double

    static let circle = ScallopForm(lobes: 0, depth: 0)
    static let cookie = ScallopForm(lobes: 9, depth: 0.1)
    static let clover = ScallopForm(lobes: 4, depth: 0.35)
    static let sunny = ScallopForm(lobes: 12, depth: 0.06)
    static let flower = ScallopForm(lobes: 6, depth: 0.2)

    /// Normalised radius (0...1) at angle θ.
    func radius(at theta: Double) -> Double {
        1 - depth * (1 - cos(lobes * theta)) / 2
    }
}

enum ScallopGeometry {
    /// The site's shared badge loops in ~9.2s (4 morphs of 1.4s + 0.9s
    /// holds, one full turn). The app runs it at 0.4x that speed.
    static let badgeLoop: Double = 9.2 / 0.4
    /// Each shared interest shows for this long before the next.
    static let badgeInterestHold: Double = 4

    /// The shared badge's morph sequence: the site's SharedBadge forms (soft
    /// pentagon, cookie, clover, soft heptagon) with SHALLOWER lobes, so the
    /// shape never pinches in on the text it carries.
    static let badgeForms: [ScallopForm] = [
        ScallopForm(lobes: 5, depth: 0.1),
        ScallopForm(lobes: 9, depth: 0.07),
        ScallopForm(lobes: 4, depth: 0.14),
        ScallopForm(lobes: 7, depth: 0.08),
    ]

    /// Radius of a morph between two forms at `t` (0...1).
    ///
    /// Blends RADII along the same angle rather than moving points in a
    /// straight line. Point-to-point blending, especially with a rotation baked
    /// in, makes points cut chords across the shape so it visibly shrinks
    /// mid-morph (a bug the mockup hit). Radial blending keeps the outline
    /// between the two forms at every step.
    static func blendedRadius(_ a: ScallopForm, _ b: ScallopForm, t: Double, theta: Double) -> Double {
        let t = min(max(t, 0), 1)
        return a.radius(at: theta) * (1 - t) + b.radius(at: theta) * t
    }

    /// Where in the badge loop we are, as (from, to, eased t).
    ///
    /// The loop visits each form in turn, holding on each for `hold` of its
    /// segment and morphing for the rest, with an ease-in-out (the site uses
    /// sine.inOut) on the morph.
    static func badgePhase(elapsed: Double,
                           loop: Double,
                           forms: [ScallopForm] = badgeForms,
                           hold: Double = 0.4) -> (from: ScallopForm, to: ScallopForm, t: Double) {
        precondition(!forms.isEmpty && loop > 0)
        let segment = loop / Double(forms.count)
        let position = elapsed.truncatingRemainder(dividingBy: loop)
        let wrapped = position < 0 ? position + loop : position
        let index = min(Int(wrapped / segment), forms.count - 1)
        let local = (wrapped - Double(index) * segment) / segment   // 0...1
        let raw = local <= hold ? 0 : (local - hold) / (1 - hold)
        let eased = (1 - cos(raw * .pi)) / 2                        // sine in-out
        return (forms[index], forms[(index + 1) % forms.count], eased)
    }

    /// Turn of the badge in degrees: one full turn per loop.
    static func badgeRotation(elapsed: Double, loop: Double) -> Double {
        let r = elapsed.truncatingRemainder(dividingBy: loop) / loop * 360
        return r < 0 ? r + 360 : r
    }

    /// Which of `count` items shows at `elapsed`, each held for `hold` seconds.
    static func cycleIndex(elapsed: Double, count: Int, hold: Double) -> Int {
        guard count > 0, hold > 0 else { return 0 }
        let i = Int(floor(elapsed / hold)) % count
        return i < 0 ? i + count : i
    }

    /// Points of a (possibly blended) scallop in a `size` × `size` box,
    /// starting at 12 o'clock. `samples` points, closed by the caller.
    static func points(size: Double, samples: Int = 180,
                       radius: (Double) -> Double) -> [(x: Double, y: Double)] {
        let half = size / 2
        return (0..<max(samples, 3)).map { i in
            let theta = Double(i) / Double(max(samples, 3)) * 2 * .pi
            let r = half * radius(theta)
            let a = theta - .pi / 2
            return (half + r * cos(a), half + r * sin(a))
        }
    }
}
