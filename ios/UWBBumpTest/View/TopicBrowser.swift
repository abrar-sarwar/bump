import SwiftUI

/// Browse interests the way a conversation goes: start broad, then narrow.
/// The topics come first; tapping one selects it and opens its variations
/// right underneath ("Coffee" → Espresso, Pour-over, Cold brew…). Picking a
/// variation is optional; the broad topic alone is a perfectly good answer.
struct TopicBrowser: View {
    let isSelected: (Interest) -> Bool
    let toggle: (Interest) -> Void

    /// Topics opened by hand, so a topic stays open after it's deselected.
    @State private var opened: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            FlowLayout {
                ForEach(InterestCatalog.groups, id: \.category.id) { group in
                    InterestChip(title: group.category.label, selected: isSelected(group.category)) {
                        tapTopic(group.category, children: group.children)
                    }
                }
            }

            ForEach(InterestCatalog.groups.filter { isOpen($0.category, $0.children) }, id: \.category.id) { group in
                VStack(alignment: .leading, spacing: Space.s) {
                    Text("\(group.category.label): anything more specific?")
                        .font(BumpFont.caption)
                        .foregroundStyle(BumpColor.secondaryText)
                    FlowLayout {
                        ForEach(group.children) { interest in
                            InterestChip(title: interest.label, selected: isSelected(interest)) {
                                toggle(interest)
                                Haptics.tap()
                            }
                        }
                    }
                }
                .padding(Space.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frostedCard()
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: opened)
    }

    private func isOpen(_ topic: Interest, _ children: [Interest]) -> Bool {
        opened.contains(topic.id) || isSelected(topic) || children.contains(where: isSelected)
    }

    private func tapTopic(_ topic: Interest, children: [Interest]) {
        toggle(topic)
        if isSelected(topic) { opened.insert(topic.id) } else if !children.contains(where: isSelected) { opened.remove(topic.id) }
        Haptics.tap()
    }
}
