import SwiftUI
import UIKit

// Ported from ios-mockup/components.css + ui.js. Each type names the mockup
// piece it mirrors and, where it came from the marketing site, the web class.
// Existing signatures (Wordmark, BumpField, InterestChip, Card, StatusPill,
// Avatar, Screen, SectionHeading, …) are unchanged so every view compiles.

// MARK: - Wordmark

/// The BUMP wordmark: the Horizon ARTWORK from the site (Assets "Wordmark"),
/// never set in a font. Template-rendered so it can go white on blue.
struct Wordmark: View {
    enum Size { case hero, compact }
    var size: Size = .compact
    var white = false

    private var width: CGFloat { size == .hero ? 300 : 84 }

    var body: some View {
        Group {
            if UIImage(named: "Wordmark") != nil {
                Image("Wordmark")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            } else {
                // Only if the asset is missing from the bundle.
                Text("BUMP")
                    .font(.system(size: size == .hero ? 64 : 22, weight: .black).width(.expanded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .foregroundStyle(white ? Color.white : BumpColor.brand)
        .frame(maxWidth: width)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("BUMP")
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Frosted surface (the site's .folk-card)

/// A white gradient, a bright top edge, a hairline and stacked soft shadows.
struct FrostedBackground<S: Shape>: View {
    var shape: S
    var raised = false

    var body: some View {
        shape
            .fill(LinearGradient(colors: [Color.white.opacity(0.92), Color.white.opacity(0.78)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(BumpColor.hairline, lineWidth: 0.5))
            .overlay(shape.stroke(LinearGradient(colors: [Color.white, Color.white.opacity(0)],
                                                 startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: BumpColor.ink.opacity(raised ? 0.07 : 0.04), radius: raised ? 9 : 5, x: 0, y: raised ? 8 : 4)
            .shadow(color: BumpColor.ink.opacity(raised ? 0.08 : 0.05), radius: raised ? 20 : 12, x: 0, y: raised ? 18 : 10)
    }
}

extension View {
    /// Frosted rounded rectangle behind the view.
    func frostedCard(cornerRadius: CGFloat = Space.corner, raised: Bool = false) -> some View {
        background(FrostedBackground(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous), raised: raised))
    }

    /// Frosted capsule behind the view (a very large radius clamps to a capsule).
    func frostedCapsule(raised: Bool = false) -> some View {
        background(FrostedBackground(shape: Capsule(style: .continuous), raised: raised))
    }
}

// MARK: - Buttons

/// Primary = the site's md-filled-button: a blue pill, at a phone CTA's height.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.button)
            .foregroundStyle(isEnabled ? BumpColor.onPrimary : BumpColor.faint)
            .frame(maxWidth: .infinity, minHeight: Space.buttonHeight)
            .padding(.horizontal, Space.l)
            .background(Capsule(style: .continuous).fill(isEnabled ? BumpColor.primary : BumpColor.track))
            .shadow(color: BumpColor.primary.opacity(isEnabled && !configuration.isPressed ? 0.22 : 0), radius: 10, x: 0, y: 8)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(BumpMotion.standard, value: configuration.isPressed)
    }
}

/// Secondary = a frosted pill.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.button)
            .foregroundStyle(isEnabled ? BumpColor.navy : BumpColor.faint)
            .frame(maxWidth: .infinity, minHeight: Space.buttonHeight)
            .padding(.horizontal, Space.l)
            .frostedCapsule(raised: configuration.isPressed)
            .opacity(isEnabled ? 1 : 0.6)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(BumpMotion.standard, value: configuration.isPressed)
    }
}

/// Tonal = primary container, for a calmer action inside a card.
struct TonalButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.button)
            .foregroundStyle(BumpColor.onPrimaryContainer)
            .frame(maxWidth: .infinity, minHeight: Space.buttonHeight)
            .padding(.horizontal, Space.l)
            .background(Capsule(style: .continuous).fill(BumpColor.primaryContainer))
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var bumpPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var bumpSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}
extension ButtonStyle where Self == TonalButtonStyle {
    static var bumpTonal: TonalButtonStyle { TonalButtonStyle() }
}

/// A button title with a trailing SF Symbol, like the site's "See how it works →".
struct TrailingIconLabel: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: Space.s) {
            Text(title)
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
        }
    }
}

/// The site's square back-to-top button: frosted (or dark), 40pt, r12.
struct SquareIconButton: View {
    let systemImage: String
    var label: String
    var dark = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(dark ? Color.white : BumpColor.navy)
                .frame(width: 40, height: 40)
                .background {
                    if dark {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(BumpColor.ink)
                    } else {
                        FrostedBackground(shape: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Text helpers

/// The site's eyebrow ("SCROLL TO BUMP"): small, uppercase, letter-spaced.
struct Eyebrow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(BumpFont.eyebrow)
            .tracking(Tracking.eyebrow)
            .textCase(.uppercase)
            .foregroundStyle(BumpColor.secondaryText)
    }
}

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

/// Screen title: Archivo ExtraBold, tight tracking.
struct ScreenTitle: View {
    let text: String
    var alignment: TextAlignment = .leading
    init(_ text: String, alignment: TextAlignment = .leading) {
        self.text = text
        self.alignment = alignment
    }

    var body: some View {
        Text(text)
            .font(BumpFont.screenTitle)
            .tracking(Tracking.title)
            .foregroundStyle(BumpColor.navy)
            .multilineTextAlignment(alignment)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Fields

/// A frosted white field with a small label above it.
struct BumpField: View {
    let label: String
    var placeholder: String = ""
    var axis: Axis = .horizontal
    var lines: ClosedRange<Int>? = nil
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !label.isEmpty {
                Text(label)
                    .font(BumpFont.captionEmphasis)
                    .foregroundStyle(BumpColor.secondaryText)
                    .padding(.leading, Space.xs)
            }
            TextField(placeholder, text: $text, axis: axis)
                .lineLimit(lines ?? 1...(axis == .vertical ? 8 : 1))
                .font(BumpFont.body)
                .foregroundStyle(BumpColor.navy)
                .tint(BumpColor.primary)
                .textInputAutocapitalization(axis == .horizontal ? .words : .sentences)
                .padding(.horizontal, Space.m)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(Color.white)
                        .shadow(color: BumpColor.ink.opacity(0.05), radius: 12, x: 0, y: 10)
                        .shadow(color: BumpColor.ink.opacity(0.04), radius: 5, x: 0, y: 4)
                )
                .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(BumpColor.hairline, lineWidth: 0.5))
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Interest chip (the site's .tag)

/// Grey pill; selected is blue with a check (the site's shared tag).
struct InterestChip: View {
    let title: String
    var selected: Bool = false
    var removable: Bool = false
    var action: (() -> Void)?

    var body: some View {
        let content = HStack(spacing: 4) {
            if selected && !removable {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
            }
            Text(title)
            if removable {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
        }
        .font(selected ? BumpFont.captionEmphasis : BumpFont.captionMedium)
        .foregroundStyle(selected ? BumpColor.onPrimary : BumpColor.secondaryText)
        .padding(.leading, selected && !removable ? 10 : 14)
        .padding(.trailing, removable ? 10 : 14)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(selected ? BumpColor.primary : BumpColor.track))
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

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

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

// MARK: - Cards

/// A frosted card (the site's .folk-card).
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frostedCard()
    }
}

/// Pastel washes for bentos (the site's --folk-wash-*).
enum Wash {
    case sky, lilac, peach, mint

    @ViewBuilder var background: some View {
        switch self {
        case .sky:
            ZStack {
                Color(hex: 0xF3F5F8)
                EllipticalGradient(colors: [Color(hex: 0xD7EBFB), Color(hex: 0xD7EBFB, opacity: 0)],
                                   center: UnitPoint(x: 0.5, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.62)
            }
        case .lilac:
            ZStack {
                Color(hex: 0xF3F4F8)
                EllipticalGradient(colors: [Color(hex: 0xE6DCFA), Color(hex: 0xE6DCFA, opacity: 0)],
                                   center: UnitPoint(x: 0.1, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.6)
                EllipticalGradient(colors: [Color(hex: 0xD9ECFB), Color(hex: 0xD9ECFB, opacity: 0)],
                                   center: UnitPoint(x: 1, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.65)
            }
        case .peach:
            ZStack {
                Color(hex: 0xF4F4F7)
                EllipticalGradient(colors: [Color(hex: 0xF8E0D4), Color(hex: 0xF8E0D4, opacity: 0)],
                                   center: UnitPoint(x: 0.3, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.62)
                EllipticalGradient(colors: [Color(hex: 0xECE0F5), Color(hex: 0xECE0F5, opacity: 0)],
                                   center: UnitPoint(x: 1, y: 0.9), startRadiusFraction: 0, endRadiusFraction: 0.65)
            }
        case .mint:
            ZStack {
                Color(hex: 0xF3F5F8)
                EllipticalGradient(colors: [Color(hex: 0xC9F1EA), Color(hex: 0xC9F1EA, opacity: 0)],
                                   center: UnitPoint(x: 0.2, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.6)
                EllipticalGradient(colors: [Color(hex: 0xDFE2FB), Color(hex: 0xDFE2FB, opacity: 0)],
                                   center: UnitPoint(x: 1, y: 1), startRadiusFraction: 0, endRadiusFraction: 0.65)
            }
        }
    }
}

/// A pastel panel with an icon label (the site's .folk-bento).
struct Bento<Content: View>: View {
    var wash: Wash = .sky
    var label: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if let label {
                HStack(spacing: Space.s) {
                    if let systemImage {
                        Image(systemName: systemImage).font(.system(size: 14, weight: .semibold))
                    }
                    Text(label).font(BumpFont.captionEmphasis)
                }
                .foregroundStyle(BumpColor.secondaryText)
            }
            content
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wash.background.clipShape(RoundedRectangle(cornerRadius: Space.cornerLarge, style: .continuous)))
        .overlay(RoundedRectangle(cornerRadius: Space.cornerLarge, style: .continuous).stroke(BumpColor.hairline, lineWidth: 0.5))
        .shadow(color: BumpColor.ink.opacity(0.05), radius: 15, x: 0, y: 10)
    }
}

// MARK: - Status

enum StatusTone { case neutral, active, good, warn, bad

    var color: Color {
        switch self {
        case .neutral: return BumpColor.outline
        case .active:  return BumpColor.primary
        case .good:    return BumpColor.positive
        case .warn:    return BumpColor.warning
        case .bad:     return BumpColor.negative
        }
    }
}

/// A grey track pill with a status dot (the site's .walkby__status).
struct StatusPill: View {
    let text: String
    var tone: StatusTone = .neutral

    var body: some View {
        HStack(spacing: Space.s) {
            Circle().fill(tone.color).frame(width: 8, height: 8)
            Text(text)
                .font(BumpFont.captionEmphasis)
                .foregroundStyle(BumpColor.secondaryText)
        }
        .padding(.leading, 11)
        .padding(.trailing, 13)
        .padding(.vertical, 6)
        .background(Capsule().fill(BumpColor.track))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

// MARK: - Orbs and avatars (the site's .folk-orb)

/// The glossy sphere that holds an icon or a letter.
struct Orb<Content: View>: View {
    var size: CGFloat = 44
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(
                Circle().fill(RadialGradient(
                    gradient: Gradient(stops: [
                        .init(color: Color.white, location: 0),
                        .init(color: Color(hex: 0xEEF1F4), location: 0.46),
                        .init(color: Color(hex: 0xD6DCE3), location: 1),
                    ]),
                    center: UnitPoint(x: 0.34, y: 0.28), startRadius: 0, endRadius: size * 0.8))
            )
            .overlay(Circle().stroke(BumpColor.hairline, lineWidth: 0.5))
            .overlay(Circle().stroke(LinearGradient(colors: [Color.white, Color.clear], startPoint: .top, endPoint: .center), lineWidth: 1))
            .shadow(color: BumpColor.ink.opacity(0.12), radius: 7, x: 0, y: 6)
    }
}

/// An orb holding an SF Symbol.
struct IconOrb: View {
    let systemImage: String
    var size: CGFloat = 44
    var tint: Color = BumpColor.primary

    var body: some View {
        Orb(size: size) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(tint)
        }
        .accessibilityHidden(true)
    }
}

/// A profile photo when there is one, otherwise an orb with a coloured letter
/// (the site's .person__avatar). Blue letter = you, orange = them.
struct Avatar: View {
    let name: String
    var size: CGFloat = 56
    var tint: Color = BumpColor.primary
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
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .shadow(color: BumpColor.ink.opacity(0.12), radius: 7, x: 0, y: 6)
            } else {
                Orb(size: size) {
                    Text(initials)
                        .font(BumpFont.archivo(Archivo.bold, size * 0.4, relativeTo: .body))
                        .foregroundStyle(tint)
                        .minimumScaleFactor(0.5)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Rows (the site's .folk-chip)

/// A frosted pill row: leading orb, a text column, optional trailing view.
/// `block` = a taller, less round card for multi-line rows.
struct RowPill<Lead: View, Content: View, Trail: View>: View {
    var block: Bool
    let lead: Lead
    let content: Content
    let trail: Trail

    init(block: Bool = false,
         @ViewBuilder lead: () -> Lead,
         @ViewBuilder content: () -> Content,
         @ViewBuilder trail: () -> Trail) {
        self.block = block
        self.lead = lead()
        self.content = content()
        self.trail = trail()
    }

    var body: some View {
        HStack(alignment: block ? .top : .center, spacing: 12) {
            lead
            VStack(alignment: .leading, spacing: 2) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
            trail
        }
        .padding(.leading, block ? 12 : 10)
        .padding(.trailing, block ? 14 : 16)
        .padding(.vertical, block ? 12 : 10)
        .background(FrostedBackground(shape: RoundedRectangle(cornerRadius: block ? 22 : 100, style: .continuous)))
    }
}

extension RowPill where Trail == EmptyView {
    init(block: Bool = false, @ViewBuilder lead: () -> Lead, @ViewBuilder content: () -> Content) {
        self.init(block: block, lead: lead, content: content, trail: { EmptyView() })
    }
}

/// Text styles for a RowPill's column.
enum RowText {
    static func title(_ s: String) -> some View {
        Text(s).font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
            .fixedSize(horizontal: false, vertical: true)
    }
    static func subtitle(_ s: String) -> some View {
        Text(s).font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
    static func faint(_ s: String) -> some View {
        Text(s).font(BumpFont.caption2).foregroundStyle(BumpColor.faint)
    }
}

// MARK: - Pill tabs (the site's .folk-pills)

/// A grey track with the chosen option as a raised white pill.
struct PillTabs<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                let on = option.value == selection
                Button {
                    withAnimation(BumpMotion.standard) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(BumpFont.captionEmphasis)
                        .foregroundStyle(on ? BumpColor.navy : BumpColor.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if on {
                                Capsule().fill(Color.white)
                                    .shadow(color: BumpColor.ink.opacity(0.1), radius: 1.5, x: 0, y: 1)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(3)
        .background(Capsule().fill(BumpColor.track))
    }
}

// MARK: - Chat bubbles (the site's .float-bubble)

/// The bubble's shape: a tail corner at the bottom on the speaker's side.
struct BubbleShape: Shape {
    var isMe: Bool
    func path(in rect: CGRect) -> Path {
        UnevenRoundedRectangle(topLeadingRadius: 20,
                               bottomLeadingRadius: isMe ? 20 : 6,
                               bottomTrailingRadius: isMe ? 6 : 20,
                               topTrailingRadius: 20,
                               style: .continuous).path(in: rect)
    }
}

/// One bubble, sized to its text. Them = frosted, me = brand blue.
struct BubbleBody<Content: View>: View {
    var isMe = false
    @ViewBuilder var content: Content

    var body: some View {
        content
            .font(BumpFont.body)
            .foregroundStyle(isMe ? BumpColor.onPrimary : BumpColor.navy)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background {
                if isMe {
                    BubbleShape(isMe: true).fill(BumpColor.primary)
                        .shadow(color: BumpColor.primary.opacity(0.28), radius: 10, x: 0, y: 8)
                } else {
                    FrostedBackground(shape: BubbleShape(isMe: false))
                }
            }
    }
}

/// A bubble placed in a conversation: aligned to its side, with an optional
/// small "who" line above it.
struct ChatBubble<Content: View>: View {
    var isMe = false
    var who: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: isMe ? .trailing : .leading, spacing: 2) {
            if let who {
                Text(who)
                    .font(BumpFont.caption2)
                    .foregroundStyle(BumpColor.faint)
                    .padding(.horizontal, 6)
            }
            BubbleBody(isMe: isMe) { content }
        }
        .padding(isMe ? .leading : .trailing, 36)
        .frame(maxWidth: .infinity, alignment: isMe ? .trailing : .leading)
    }
}

extension ChatBubble where Content == Text {
    init(_ text: String, isMe: Bool = false, who: String? = nil) {
        self.init(isMe: isMe, who: who) { Text(text) }
    }
}

/// Decorative lines, verbatim from the site's hero floaters
/// (web/src/components/HeroFloaters.tsx). Fictional; never presented as data.
enum FloaterLine {
    static let lecture = "we’ve sat next to each other in lecture all semester"
    static let film = "wait you shoot 35mm too??"
    static let mixer = "3 hours at this mixer and i’ve asked “what’s your major” 11 times"
}

/// A tilted bubble laid over some art, like the site's hero floaters.
struct Floater: Identifiable {
    let id = UUID()
    var text: String
    var isMe = false
    var alignment: Alignment
    var offset: CGSize = .zero
    var rotation: Double = 0
}

extension View {
    /// Lays decorative tilted bubbles over this view. Hidden from VoiceOver.
    func floaters(_ items: [Floater]) -> some View {
        overlay {
            ZStack {
                ForEach(items) { f in
                    BubbleBody(isMe: f.isMe) {
                        Text(f.text).font(BumpFont.caption)
                    }
                    .frame(maxWidth: 210)
                    .rotationEffect(.degrees(f.rotation))
                    .offset(f.offset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: f.alignment)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// MARK: - Toast (the site's .walkby__notice)

/// An app tile, a title and a line, and an optional trailing view.
struct Toast<Trail: View>: View {
    let systemImage: String
    let title: String
    var message: String? = nil
    @ViewBuilder var trail: Trail

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(BumpColor.onPrimary)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(BumpColor.primary))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(BumpFont.bodyEmphasis).foregroundStyle(BumpColor.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if let message {
                    Text(message).font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trail
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frostedCard(cornerRadius: 20)
        .accessibilityElement(children: .combine)
    }
}

extension Toast where Trail == EmptyView {
    init(systemImage: String, title: String, message: String? = nil) {
        self.init(systemImage: systemImage, title: title, message: message) { EmptyView() }
    }
}

// MARK: - Shapes

/// One MD3 scallop form as a Shape (see ScallopGeometry.swift).
struct ScallopShape: Shape {
    var form: ScallopForm
    func path(in rect: CGRect) -> Path {
        ScallopPath.make(in: rect) { form.radius(at: $0) }
    }
}

/// A blend between two forms, `t` from 0 (from) to 1 (to).
struct BlendedScallop: Shape {
    var from: ScallopForm
    var to: ScallopForm
    var t: Double

    var animatableData: Double {
        get { t }
        set { t = newValue }
    }

    func path(in rect: CGRect) -> Path {
        ScallopPath.make(in: rect) { ScallopGeometry.blendedRadius(from, to, t: t, theta: $0) }
    }
}

enum ScallopPath {
    static func make(in rect: CGRect, radius: (Double) -> Double) -> Path {
        let side = min(rect.width, rect.height)
        let originX = rect.midX - side / 2
        let originY = rect.midY - side / 2
        let points = ScallopGeometry.points(size: Double(side), radius: radius)
        var path = Path()
        for (i, p) in points.enumerated() {
            let point = CGPoint(x: originX + CGFloat(p.x), y: originY + CGFloat(p.y))
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Morphing blob + shared badge (the site's SharedBadge.tsx)

/// A pale circle with a darker MD3 shape inside that morphs through the badge
/// forms and turns, content fixed on top. Holds still under Reduce Motion.
struct MorphingBlob<Content: View>: View {
    var size: CGFloat = 200
    var loop: Double = BumpMotion.badgeLoop
    var container: Color = BumpColor.primaryContainer
    var form: Color = BumpColor.primary
    /// Receives seconds elapsed, so content can animate in step with the shape.
    @ViewBuilder var content: (Double) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: reduceMotion)) { context in
            let elapsed = reduceMotion ? 0 : context.date.timeIntervalSince(start)
            let phase = ScallopGeometry.badgePhase(elapsed: elapsed, loop: loop)
            ZStack {
                Circle().fill(container)
                BlendedScallop(from: phase.from, to: phase.to, t: phase.t)
                    .fill(form)
                    .rotationEffect(.degrees(ScallopGeometry.badgeRotation(elapsed: elapsed, loop: loop)))
                    .padding(size * 0.07)
                content(elapsed)
            }
            .frame(width: size, height: size)
        }
    }
}

/// "You both share this": the morphing blob with the text on top. With several
/// interests it cycles through them, one every `BumpMotion.badgeInterestHold`
/// seconds. The morph runs at 0.4x the site's speed.
struct SharedBadge: View {
    var kicker: String
    var interests: [String]
    var size: CGFloat = 200
    var loop: Double = BumpMotion.badgeLoop
    var container: Color = BumpColor.primaryContainer
    var form: Color = BumpColor.primary
    var onForm: Color = BumpColor.onPrimary
    /// Scale in from small with a spring when it appears.
    var popIn = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        MorphingBlob(size: size, loop: loop, container: container, form: form) { elapsed in
            let index = ScallopGeometry.cycleIndex(elapsed: elapsed, count: interests.count,
                                                   hold: BumpMotion.badgeInterestHold)
            VStack(spacing: 4) {
                Text(kicker)
                    .font(BumpFont.archivo(Archivo.semibold, size * 0.048, relativeTo: .caption))
                    .opacity(0.85)
                ZStack {
                    ForEach(interests.indices, id: \.self) { i in
                        Text(interests[i])
                            .font(BumpFont.archivo(Archivo.bold, size * 0.092, relativeTo: .title2))
                            .multilineTextAlignment(.center)
                            .opacity(i == index ? 1 : 0)
                            .offset(y: i == index ? 0 : 6)
                    }
                }
                .animation(.easeInOut(duration: 0.5), value: index)
            }
            .foregroundStyle(onForm)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: size * 0.64)
        }
        .scaleEffect(popIn && !appeared ? 0.4 : 1)
        .opacity(popIn && !appeared ? 0 : 1)
        .onAppear {
            guard popIn, !reduceMotion else { appeared = true; return }
            withAnimation(.spring(response: 0.55, dampingFraction: 0.6)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kicker): \(interests.joined(separator: ", "))")
    }
}

// MARK: - Backdrop (the site's HeroBackdrop)

/// Dot grid fading in from the edges, plus faint MD3 outline shapes and a
/// glyph or two. Texture only: never hit-testable, hidden from VoiceOver.
struct Backdrop: View {
    enum Style { case hero, soft }
    var style: Style = .hero

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                if style == .hero {
                    Canvas { ctx, size in
                        let step: CGFloat = 22
                        var y: CGFloat = step / 2
                        while y < size.height {
                            var x: CGFloat = step / 2
                            while x < size.width {
                                ctx.fill(Path(ellipseIn: CGRect(x: x - 1.1, y: y - 1.1, width: 2.2, height: 2.2)),
                                         with: .color(BumpColor.primary.opacity(0.16)))
                                x += step
                            }
                            y += step
                        }
                    }
                    .mask {
                        EllipticalGradient(gradient: Gradient(stops: [
                            .init(color: .clear, location: 0.3),
                            .init(color: .black, location: 1),
                        ]), center: .center, startRadiusFraction: 0, endRadiusFraction: 0.7)
                    }

                    ScallopShape(form: .cookie)
                        .stroke(BumpColor.primary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 170, height: 170)
                        .position(x: 45, y: h * 0.06 + 85)
                    ScallopShape(form: .flower)
                        .fill(BumpColor.tertiary.opacity(0.06))
                        .frame(width: 190, height: 190)
                        .position(x: w + 35, y: h * 0.86 - 95)
                    ScallopShape(form: .clover)
                        .stroke(BumpColor.secondary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 110, height: 110)
                        .position(x: w - 73, y: h * 0.12 + 55)
                    Image(systemName: "hand.wave.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(BumpColor.primary.opacity(0.11))
                        .rotationEffect(.degrees(-12))
                        .position(x: w * 0.7, y: h * 0.15)
                } else {
                    ScallopShape(form: .cookie)
                        .stroke(BumpColor.primary.opacity(0.18), lineWidth: 1.5)
                        .frame(width: 150, height: 150)
                        .position(x: w + 25, y: h * 0.04 + 75)
                    ScallopShape(form: .clover)
                        .fill(BumpColor.secondary.opacity(0.06))
                        .frame(width: 120, height: 120)
                        .position(x: 16, y: h * 0.8)
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Two phones illustration

/// The two drawn phones, brand blue and the orange phone, drifting together.
/// Deliberately NOT the site's hand photographs. Suppressed under Reduce Motion.
struct PhonesIllustration: View {
    var animated: Bool = false
    /// Resting further apart, for "not bumped yet" states.
    var apart: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var closed = false

    private let baseGap: CGFloat = 64

    private var offset: CGFloat {
        if apart { return 2 }
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
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: closed)
        .onAppear { if animated && !reduceMotion { closed = true } }
        .accessibilityHidden(true)
    }

    private func phone(fill: Color) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(fill)
            .frame(width: 78, height: 140)
            .overlay(alignment: .topLeading) {
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

// MARK: - Progress

/// Onboarding progress: one rounded segment per step, filled in primary.
struct SegmentedProgress: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<total, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? BumpColor.primary : BumpColor.track)
                    .frame(height: 5)
            }
        }
        .animation(BumpMotion.standard, value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(current + 1) of \(total)")
    }
}

/// An MD3 checkbox in a 40pt touch target.
struct BumpCheckbox: View {
    let checked: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(checked ? BumpColor.primary : Color.clear)
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(checked ? Color.clear : BumpColor.outline, lineWidth: 2)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BumpColor.onPrimary)
            }
        }
        .frame(width: 20, height: 20)
        .frame(width: 40, height: 40)
        .contentShape(Rectangle())
    }
}

// MARK: - Screen scaffold

/// Every screen sits on the surface with consistent gutters and safe areas,
/// optionally over the site's backdrop.
struct Screen<Content: View>: View {
    var backdrop: Backdrop.Style? = nil
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            BumpColor.background.ignoresSafeArea()
            if let backdrop {
                Backdrop(style: backdrop).ignoresSafeArea()
            }
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
