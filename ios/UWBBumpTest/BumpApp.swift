import SwiftUI

/// BUMP — meet someone, find your overlap.
///
/// Bumping, matching and the profile exchange run on the phones in the room.
/// The voice intro, Grok drafting and talking points go
/// through the BUMP server (`backend/`), only with the user's permission.
/// Evolved from the `uwb-ios` Nearby Interaction spike.
@main
struct BumpApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
