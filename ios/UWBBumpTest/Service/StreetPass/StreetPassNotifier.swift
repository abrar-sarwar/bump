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
