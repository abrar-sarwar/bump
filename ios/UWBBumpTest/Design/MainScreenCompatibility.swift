import SwiftUI

// Controls used by the new main-branch screens. They use this branch's Archivo,
// colour roles and frosted surfaces so the added behavior fits the existing UI.

enum ButtonSize { case small, medium }

extension ButtonStyle where Self == SecondaryButtonStyle {
    static func bumpSecondary(_ size: ButtonSize) -> SecondaryButtonStyle { SecondaryButtonStyle() }
}

struct OutlinedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.captionEmphasis)
            .foregroundStyle(BumpColor.primary)
            .frame(minHeight: 44)
            .padding(.horizontal, Space.m)
            .background(Capsule().strokeBorder(BumpColor.outline, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == OutlinedButtonStyle {
    static func bumpOutlined(_ size: ButtonSize) -> OutlinedButtonStyle { OutlinedButtonStyle() }
}

struct TextButtonStyle: ButtonStyle {
    var tint: Color = BumpColor.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.captionEmphasis)
            .foregroundStyle(tint)
            .frame(minHeight: 44)
            .padding(.horizontal, Space.s)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}

extension ButtonStyle where Self == TextButtonStyle {
    static var bumpText: TextButtonStyle { TextButtonStyle() }
    static func bumpText(_ tint: Color) -> TextButtonStyle { TextButtonStyle(tint: tint) }
}

struct IconButtonStyle: ButtonStyle {
    var tint: Color = BumpColor.primary
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background {
                if filled { Circle().fill(BumpColor.primary) }
                else { FrostedBackground(shape: Circle()) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

extension ButtonStyle where Self == IconButtonStyle {
    static var bumpIcon: IconButtonStyle { IconButtonStyle() }
    static func bumpIcon(_ tint: Color, filled: Bool = false) -> IconButtonStyle {
        IconButtonStyle(tint: tint, filled: filled)
    }
}

struct LoadingIndicator: View {
    var size: CGFloat = 20
    var body: some View {
        ProgressView().tint(BumpColor.primary).frame(width: size, height: size)
    }
}

struct ListGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View { Card(padding: 0) { VStack(spacing: 0) { content } } }
}

struct NavigationRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.65 : 1)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(BumpColor.faint)
    }
}

struct BumpSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]

    var body: some View {
        HStack(spacing: Space.xs) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                Button { selection = option.0 } label: {
                    Text(option.1)
                        .font(BumpFont.captionEmphasis)
                        .foregroundStyle(selection == option.0 ? BumpColor.onPrimary : BumpColor.secondaryText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Capsule().fill(selection == option.0 ? BumpColor.primary : BumpColor.track))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == option.0 ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(4)
        .frostedCapsule()
    }
}

struct InfoNotice: View {
    let text: String
    var icon = "info.circle.fill"
    var tone: StatusTone = .neutral

    var body: some View {
        HStack(alignment: .top, spacing: Space.s) {
            Image(systemName: icon).foregroundStyle(tone.color)
            Text(text).font(BumpFont.caption).foregroundStyle(BumpColor.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Wash.sky.background.clipShape(RoundedRectangle(cornerRadius: Space.corner)))
    }
}
