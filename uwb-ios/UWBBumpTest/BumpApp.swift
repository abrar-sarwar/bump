import SwiftUI

/// BUMP — meet someone, find your overlap.
///
/// Bumping, matching and the profile exchange run on the phones in the room,
/// with no account. Optional cloud features (voice intro, Grok drafting and
/// talking points) go through our own `bump-api` server only with the user's
/// permission. Evolved from the `uwb-ios` Nearby Interaction spike.
@main
struct BumpApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
