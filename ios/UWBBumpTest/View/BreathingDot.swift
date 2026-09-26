import SwiftUI

/// A small dot that breathes while BUMP is listening. Subtle on purpose: the
/// screen should feel alive without competing with the phone illustration.
/// Static under Reduce Motion.
struct BreathingDot: View {
    var color: Color = BumpColor.positive
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var wide = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .scaleEffect(reduceMotion ? 1 : (wide ? 1.35 : 0.9))
            .opacity(reduceMotion ? 1 : (wide ? 1 : 0.65))
            .animation(reduceMotion ? nil
                       : .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                       value: wide)
            .onAppear { if !reduceMotion { wide = true } }
            .accessibilityHidden(true)
    }
}
