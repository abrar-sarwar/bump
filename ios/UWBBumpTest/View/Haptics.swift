import UIKit

/// Restrained haptics: only at moments that actually matter.
enum Haptics {
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
    static func warn() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
