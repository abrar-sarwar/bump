import SwiftUI

// MARK: - Wordmark

/// The BUMP wordmark. `.hero` on the welcome screen, `.compact` everywhere else.
struct Wordmark: View {
    enum Size { case hero, compact }
    var size: Size = .compact

    var body: some View {
        Text("BUMP")
            .font(BumpFont.wordmark(size == .hero ? 68 : 24))
            .foregroundStyle(BumpColor.brand)
            .kerning(size == .hero ? -1 : 0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)          // never clip at large text sizes
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("BUMP")
    }
}

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.button)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                    .fill(BumpColor.action)
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.button)
            .foregroundStyle(BumpColor.navy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                    .fill(BumpColor.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                            .strokeBorder(BumpColor.hairline, lineWidth: 1)
                    )
            )
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var bumpPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var bumpSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Fields

struct BumpField: View {
    let label: String
    var placeholder: String = ""
    var axis: Axis = .horizontal
    /// Visible line range for a vertical field. Applied to the text field only,
    /// so the label never reserves extra lines.
    var lines: ClosedRange<Int>? = nil
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(label)
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.secondaryText)
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(lines ?? 1...(axis == .vertical ? 8 : 1))
                .font(BumpFont.body)
                .foregroundStyle(BumpColor.navy)
                .textInputAutocapitalization(axis == .horizontal ? .words : .sentences)
                .padding(.horizontal, Space.m)
                .padding(.vertical, 13)
                .background(
                    RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                        .fill(BumpColor.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Space.corner, style: .continuous)
                                .strokeBorder(BumpColor.hairline, lineWidth: 1)
                        )
                )
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Interest chip

struct InterestChip: View {
    let title: String
    var selected: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = Text(title)
            .font(BumpFont.caption)
            .foregroundStyle(selected ? .white : BumpColor.navy)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(selected ? BumpColor.action : BumpColor.paleBlue)
            )
            .fixedSize(horizontal: false, vertical: true)

        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        } else {
            content.accessibilityLabel(title)
        }
    }
}

/// Simple wrapping layout for chips. Avoids a rigid grid, which the brand
/// direction explicitly steers away from.
struct FlowLayout: Layout {
    var spacing: CGFloat = Space.s

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += rowHeight + spacing; rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Card

struct Card<Content: View>: View {
    var padding: CGFloat = Space.m
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Space.cornerLarge, style: .continuous)
                    .fill(BumpColor.surface)
            )
    }
}

// MARK: - Status

enum StatusTone { case neutral, active, good, warn, bad

    var color: Color {
        switch self {
        case .neutral: return BumpColor.secondaryText
        case .active:  return BumpColor.action
        case .good:    return BumpColor.positive
        case .warn:    return BumpColor.warning
        case .bad:     return BumpColor.negative
        }
    }
}

struct StatusPill: View {
    let text: String
    var tone: StatusTone = .neutral

    var body: some View {
        HStack(spacing: Space.s) {
            Circle().fill(tone.color).frame(width: 8, height: 8)
            Text(text)
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.navy)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(BumpColor.paleBlue))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

// MARK: - Avatar

/// A profile photo when there is one, otherwise initials. Photos come from the
/// system photo picker, which needs no photo-library permission.
struct Avatar: View {
    let name: String
    var size: CGFloat = 56
    var tint: Color = BumpColor.brand
    /// Profile photo, if the person added one. Falls back to initials.
    var photo: Data? = nil

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first(where: \.isLetter) }.map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var body: some View {
        Group {
            if let photo, let image = UIImage(data: photo) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(tint.opacity(0.22))
                    .overlay(
                        Text(initials)
                            .font(.system(size: size * 0.38, weight: .bold))
                            .foregroundStyle(BumpColor.navy)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Two phones illustration

/// A native illustration of two phones meeting, standing in for the brand
/// photograph (no licensed image ships with the repo). When `animated` is true
/// the phones drift together — suppressed under Reduce Motion.
struct PhonesIllustration: View {
    var animated: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var closed = false

    /// Base gap between the two phones; each one slides inward by `offset`, so
    /// the visible gap is `baseGap - 2 * offset` and never goes negative.
    private let baseGap: CGFloat = 64

    private var offset: CGFloat {
        guard animated, !reduceMotion else { return animated ? 24 : 16 }
        return closed ? 26 : 4
    }

    var body: some View {
        HStack(spacing: baseGap) {
            phone(fill: BumpColor.brand)
                .rotationEffect(.degrees(-12))
                .offset(x: offset)
            phone(fill: BumpColor.illustrationWarm)
                .rotationEffect(.degrees(12))
                .offset(x: -offset)
        }
        .frame(height: 150)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: closed)
        .onAppear { if animated && !reduceMotion { closed = true } }
        .accessibilityHidden(true)
    }

    private func phone(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fill)
            .frame(width: 78, height: 140)
            .overlay(alignment: .topLeading) {
                // camera plateau, echoing the reference photo
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .overlay {
                        HStack(spacing: 3) {
                            Circle().fill(fill.opacity(0.55)).frame(width: 9, height: 9)
                            Circle().fill(fill.opacity(0.55)).frame(width: 9, height: 9)
                        }
                    }
                    .padding(9)
            }
    }
}

// MARK: - Screen scaffold

/// Every screen sits on the ivory ground with consistent gutters and safe areas.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, Space.gutter)
                    .padding(.vertical, Space.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Section heading

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(BumpFont.sectionTitle)
                .foregroundStyle(BumpColor.navy)
            if let subtitle {
                Text(subtitle)
                    .font(BumpFont.caption)
                    .foregroundStyle(BumpColor.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
