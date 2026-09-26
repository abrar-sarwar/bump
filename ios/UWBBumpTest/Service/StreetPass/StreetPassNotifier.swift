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
