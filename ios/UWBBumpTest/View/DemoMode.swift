import SwiftUI

/// Demo mode for simulator UI work and screenshots.
///
/// DEBUG builds only, and only when explicitly asked for with a launch argument:
///
///     xcrun simctl launch <sim> com.jaredberesford.uwbbumptest -BumpDemo reveal
///
/// Every demo screen wears a visible DEMO badge and the fixture people are named
/// so they cannot be mistaken for real nearby phones. Nothing here produces a
/// real sensor reading, a real peer connection, or a saved physical-test result.
enum DemoMode: String {
    case onboarding, ready, confirm, reveal, connections, you, tools, home, tutorial
    case onboardingIntro = "onboardingintro"
    case onboardingQuestion = "onboardingquestion"
    case onboardingCard = "onboardingcard"
    case timedOut = "timedout"
    case ambiguous
    case unsupported
    case streetpass

    static var active: DemoMode? {
        #if DEBUG
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-BumpDemo"), index + 1 < args.count else { return nil }
        return DemoMode(rawValue: args[index + 1].lowercased())
        #else
        return nil          // never reachable in a Release build
        #endif
    }
}

/// A badge the demo screens carry so demo data is never mistaken for live data.
struct DemoBadge: View {
    var body: some View {
        Text("DEMO DATA: not a real person or measurement")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .background(BumpColor.warning)
            .accessibilityLabel("Demo data. Not a real person or measurement.")
    }
}

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
        applyDemo(encounter: encounter)
    }
}
#endif
