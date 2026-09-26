import SwiftUI

// MARK: - Wordmark

/// The BUMP wordmark. `.hero` on the welcome screen, `.compact` everywhere else.
struct Wordmark: View {
    enum Size { case hero, compact }
    var size: Size = .compact

    var body: some View {
        Text("BUMP")
            .font(BumpFont.wordmark(size == .hero ? 68 : 22))
            .foregroundStyle(BumpColor.brand)
            .kerning(size == .hero ? -1 : 0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.5)          // never clip at large text sizes
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("BUMP")
    }
}

// MARK: - Buttons

/// Shared geometry for the M3 button family. Buttons are pills that morph to a
/// squarer shape while pressed (M3 Expressive shape morphing), with a 10%
/// state layer of the content colour on top.
enum ButtonMetrics {
    enum Size { case small, medium }

    static func height(_ size: Size) -> CGFloat { size == .small ? 40 : 52 }
    static func padding(_ size: Size) -> CGFloat { size == .small ? 16 : 24 }
    static func restRadius(_ size: Size) -> CGFloat { Radius.full }
    static func pressedRadius(_ size: Size) -> CGFloat { size == .small ? Radius.medium : Radius.large }
}

private struct ButtonChrome<Fill: ShapeStyle>: View {
    let configuration: ButtonStyle.Configuration
    let size: ButtonMetrics.Size
    let fill: Fill
    let content: Color
    var stroke: Color? = nil
    var fullWidth: Bool = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let pressed = configuration.isPressed
        let radius = pressed ? ButtonMetrics.pressedRadius(size) : ButtonMetrics.restRadius(size)
        configuration.label
            .font(size == .small ? BumpFont.labelLarge : BumpFont.titleMedium)
            .foregroundStyle(isEnabled ? content : BumpColor.onSurface.opacity(StateLayer.disabledContent))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, ButtonMetrics.padding(size))
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(minHeight: ButtonMetrics.height(size))
            .background {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(fill) : AnyShapeStyle(BumpColor.onSurface.opacity(StateLayer.disabledContainer)))
                    .overlay {
                        if pressed {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .fill(content.opacity(StateLayer.pressed))
                        }
                    }
                    .overlay {
                        if let stroke {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(isEnabled ? stroke : BumpColor.onSurface.opacity(StateLayer.disabledContainer), lineWidth: 1)
                        }
                    }
            }
            .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
            .animation(reduceMotion ? nil : Motion.spatialFast, value: pressed)
            .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Filled button: the one primary action on a screen.
struct PrimaryButtonStyle: ButtonStyle {
    var size: ButtonMetrics.Size = .medium
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, size: size,
                     fill: BumpColor.primary, content: BumpColor.onPrimary, fullWidth: fullWidth)
    }
}

/// Tonal button: secondary actions. A destructive role turns it red-tonal.
struct SecondaryButtonStyle: ButtonStyle {
    var size: ButtonMetrics.Size = .medium
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        let destructive = configuration.role == .destructive
        ButtonChrome(configuration: configuration, size: size,
                     fill: destructive ? BumpColor.negativeContainer : BumpColor.secondaryContainer,
                     content: destructive ? BumpColor.negative : BumpColor.onSecondaryContainer,
                     fullWidth: fullWidth)
    }
}

/// Outlined button: low-emphasis, sits on any surface.
struct OutlinedButtonStyle: ButtonStyle {
    var size: ButtonMetrics.Size = .medium
    var fullWidth: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        ButtonChrome(configuration: configuration, size: size,
                     fill: Color.clear, content: BumpColor.primary,
                     stroke: BumpColor.outline, fullWidth: fullWidth)
    }
}

/// Text button: the quietest action. Sized to a 40pt tap target.
struct TextButtonStyle: ButtonStyle {
    var tint: Color = BumpColor.primary
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(BumpFont.labelLarge)
            .foregroundStyle(isEnabled ? tint : BumpColor.onSurface.opacity(StateLayer.disabledContent))
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            .background(
                Capsule().fill(tint.opacity(configuration.isPressed ? StateLayer.pressed : 0))
            )
            .contentShape(Capsule())
            .animation(Motion.effectsFast, value: configuration.isPressed)
    }
}

/// Icon button: 48pt tap target, circular state layer.
struct IconButtonStyle: ButtonStyle {
    var tint: Color = BumpColor.onSurfaceVariant
    var filled: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(tint)
            .frame(width: 44, height: 44)
            .background(
                Circle().fill(filled ? BumpColor.surfaceContainerHigh : .clear)
                    .overlay(Circle().fill(tint.opacity(configuration.isPressed ? StateLayer.pressed : 0)))
            )
            .contentShape(Circle())
            .animation(Motion.effectsFast, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var bumpPrimary: PrimaryButtonStyle { PrimaryButtonStyle() }
    static func bumpPrimary(_ size: ButtonMetrics.Size, fullWidth: Bool = true) -> PrimaryButtonStyle {
        PrimaryButtonStyle(size: size, fullWidth: fullWidth)
    }
}
extension ButtonStyle where Self == SecondaryButtonStyle {
    static var bumpSecondary: SecondaryButtonStyle { SecondaryButtonStyle() }
    static func bumpSecondary(_ size: ButtonMetrics.Size, fullWidth: Bool = true) -> SecondaryButtonStyle {
        SecondaryButtonStyle(size: size, fullWidth: fullWidth)
    }
}
extension ButtonStyle where Self == OutlinedButtonStyle {
    static var bumpOutlined: OutlinedButtonStyle { OutlinedButtonStyle() }
    static func bumpOutlined(_ size: ButtonMetrics.Size, fullWidth: Bool = true) -> OutlinedButtonStyle {
        OutlinedButtonStyle(size: size, fullWidth: fullWidth)
    }
}
extension ButtonStyle where Self == TextButtonStyle {
    static var bumpText: TextButtonStyle { TextButtonStyle() }
    static func bumpText(_ tint: Color) -> TextButtonStyle { TextButtonStyle(tint: tint) }
}
extension ButtonStyle where Self == IconButtonStyle {
    static var bumpIcon: IconButtonStyle { IconButtonStyle() }
    static func bumpIcon(_ tint: Color, filled: Bool = false) -> IconButtonStyle { IconButtonStyle(tint: tint, filled: filled) }
}

// MARK: - Fields

/// M3 filled text field: tonal container, floating label, bottom indicator
/// that thickens and turns primary on focus. Same call signature as before.
struct BumpField: View {
    let label: String
    var placeholder: String = ""
    var axis: Axis = .horizontal
    /// Visible line range for a vertical field.
    var lines: ClosedRange<Int>? = nil
    @Binding var text: String

    @FocusState private var focused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var floating: Bool { focused || !text.isEmpty }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: Radius.medium, style: .continuous)
                .fill(BumpColor.surfaceContainerHighest)

            // Floating label
            Text(label)
                .font(floating ? BumpFont.bodySmall : BumpFont.bodyLarge)
                .foregroundStyle(focused ? BumpColor.primary : BumpColor.onSurfaceVariant)
                .padding(.horizontal, Space.m)
                .padding(.top, floating ? 8 : 18)
                .allowsHitTesting(false)

            // The placeholder is drawn here, not by the TextField, so it and
            // the floating label are driven by the same state and never overlap.
            if floating && text.isEmpty && !placeholder.isEmpty {
                Text(placeholder)
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurfaceVariant.opacity(0.55))
                    .padding(.horizontal, Space.m)
                    .padding(.top, 26)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }

            TextField("", text: $text, axis: axis)
                .lineLimit(lines ?? 1...(axis == .vertical ? 8 : 1))
                .font(BumpFont.bodyLarge)
                .foregroundStyle(BumpColor.onSurface)
                .tint(BumpColor.primary)
                .textInputAutocapitalization(axis == .horizontal ? .words : .sentences)
                .focused($focused)
                .padding(.horizontal, Space.m)
                .padding(.top, 26)
                .padding(.bottom, 10)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(focused ? BumpColor.primary : BumpColor.outline.opacity(0.6))
                .frame(height: focused ? 2 : 1)
                .padding(.horizontal, 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Radius.medium, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { focused = true }
        .animation(reduceMotion ? nil : Motion.effects, value: floating)
        .animation(reduceMotion ? nil : Motion.effects, value: focused)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }
}

// MARK: - Chips

/// M3 filter chip: 32pt tall, small radius, outlined at rest, tonal with a
/// leading check when selected. `trailingIcon` turns it into a removable chip.
struct InterestChip: View {
    let title: String
    var selected: Bool = false
    var trailingIcon: String? = nil
    var action: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let content = HStack(spacing: 6) {
            if selected && trailingIcon == nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .transition(.scale.combined(with: .opacity))
            }
            Text(title)
                .font(BumpFont.labelLarge)
                .lineLimit(1)
            if let trailingIcon {
                Image(systemName: trailingIcon)
                    .font(.system(size: 11, weight: .bold))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(selected ? BumpColor.onSecondaryContainer : BumpColor.onSurfaceVariant)
        .padding(.leading, selected && trailingIcon == nil ? 10 : 14)
        .padding(.trailing, trailingIcon == nil ? 14 : 10)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: Radius.small + 2, style: .continuous)
                .fill(selected ? BumpColor.secondaryContainer : BumpColor.surfaceContainerLowest)
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.small + 2, style: .continuous)
                        .strokeBorder(selected ? .clear : BumpColor.outlineVariant, lineWidth: 1)
                )
        )
        .animation(reduceMotion ? nil : Motion.spatialFast, value: selected)

        if let action {
            Button(action: action) { content }
                .buttonStyle(ChipPressStyle())
                .accessibilityLabel(title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        } else {
            content.accessibilityLabel(title)
        }
    }
}

private struct ChipPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : Motion.spatialFast, value: configuration.isPressed)
    }
}

/// Simple wrapping layout for chips.
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

// MARK: - Cards

/// M3 card variants. Depth comes from tonal layering first; `elevated` adds
/// one soft shadow because the ivory ground is very close to white.
enum CardStyle {
    case elevated, filled, outlined, primaryTonal, tertiaryTonal

    var fill: Color {
        switch self {
        case .elevated: return BumpColor.surfaceContainerLowest
        case .filled: return BumpColor.surfaceContainerHigh
        case .outlined: return BumpColor.surface
        case .primaryTonal: return BumpColor.primaryContainer
        case .tertiaryTonal: return BumpColor.tertiaryContainer
        }
    }
}

struct Card<Content: View>: View {
    var style: CardStyle = .elevated
    var padding: CGFloat = Space.m
    var radius: CGFloat = Radius.largeIncreased
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(style.fill)
                    .overlay {
                        if style == .outlined {
                            RoundedRectangle(cornerRadius: radius, style: .continuous)
                                .strokeBorder(BumpColor.outlineVariant, lineWidth: 1)
                        }
                    }
                    .shadow(color: style == .elevated ? BumpColor.onSurface.opacity(0.06) : .clear,
                            radius: 10, x: 0, y: 3)
            )
    }
}

// MARK: - List groups

/// A rounded container of list items with hairline dividers between them.
struct ListGroup<Content: View>: View {
    var style: CardStyle = .elevated
    @ViewBuilder var content: Content

    var body: some View {
        Card(style: style, padding: 0) {
            _VariadicView.Tree(DividedLayout()) { content }
        }
    }
}

private struct DividedLayout: _VariadicView_MultiViewRoot {
    @ViewBuilder
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                child
                if child.id != children.last?.id {
                    Divider().overlay(BumpColor.outlineVariant).padding(.leading, 68)
                }
            }
        }
    }
}

/// M3 list item: leading icon in a tonal circle, headline + supporting text,
/// optional trailing view. 56–72pt tall.
struct ListRow<Trailing: View>: View {
    let icon: String
    var iconTint: Color = BumpColor.primary
    var iconContainer: Color = BumpColor.primaryContainer
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    init(icon: String, iconTint: Color = BumpColor.primary, iconContainer: Color = BumpColor.primaryContainer,
         title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.icon = icon; self.iconTint = iconTint; self.iconContainer = iconContainer
        self.title = title; self.subtitle = subtitle; self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 40, height: 40)
                .background(Circle().fill(iconContainer))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BumpFont.titleMedium)
                    .foregroundStyle(BumpColor.onSurface)
                if let subtitle {
                    Text(subtitle)
                        .font(BumpFont.bodyMedium)
                        .foregroundStyle(BumpColor.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.s)
            trailing
        }
        .padding(.horizontal, Space.m)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
        .accessibilityElement(children: .combine)
    }
}

/// A row that pushes somewhere: trailing chevron, pressed state layer.
struct NavigationRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(BumpColor.onSurface.opacity(configuration.isPressed ? StateLayer.pressed : 0))
            .animation(Motion.effectsFast, value: configuration.isPressed)
    }
}

struct Chevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(BumpColor.outline)
    }
}

// MARK: - Segmented buttons

/// M3 segmented button group: connected pills, selected segment tonal with a
/// check. Replaces the system segmented picker.
struct BumpSegmented<T: Hashable>: View {
    @Binding var selection: T
    let options: [(T, String)]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = option.0 == selection
                Button {
                    withAnimation(reduceMotion ? nil : Motion.spatialFast) { selection = option.0 }
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        if selected {
                            Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                .transition(.scale.combined(with: .opacity))
                        }
                        Text(option.1).font(BumpFont.labelLarge).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selected ? BumpColor.onSecondaryContainer : BumpColor.onSurface)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(selected ? BumpColor.secondaryContainer : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
                if index < options.count - 1 {
                    Rectangle().fill(BumpColor.outline).frame(width: 1, height: 40)
                }
            }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(BumpColor.outline, lineWidth: 1))
    }
}

// MARK: - Status

enum StatusTone { case neutral, active, good, warn, bad

    var color: Color {
        switch self {
        case .neutral: return BumpColor.onSurfaceVariant
        case .active:  return BumpColor.primary
        case .good:    return BumpColor.positive
        case .warn:    return BumpColor.warning
        case .bad:     return BumpColor.negative
        }
    }

    var container: Color {
        switch self {
        case .neutral: return BumpColor.surfaceContainerHigh
        case .active:  return BumpColor.primaryContainer
        case .good:    return BumpColor.positiveContainer
        case .warn:    return BumpColor.warningContainer
        case .bad:     return BumpColor.negativeContainer
        }
    }
}

/// Assist-chip-shaped status. Tonal container in the tone's colour.
struct StatusPill: View {
    let text: String
    var tone: StatusTone = .neutral
    var icon: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .bold))
            } else {
                Circle().fill(tone.color).frame(width: 8, height: 8)
            }
            Text(text)
                .font(BumpFont.labelMedium)
                .lineLimit(2)
        }
        .foregroundStyle(tone == .neutral ? BumpColor.onSurface : tone.color)
        .padding(.horizontal, 12)
        .frame(minHeight: 32)
        .background(Capsule().fill(tone.container))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Status: \(text)")
    }
}

// MARK: - Avatar

/// A profile photo when there is one, otherwise initials on a tonal disc.
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
                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                            .foregroundStyle(BumpColor.onSurface)
                    )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

// MARK: - Loading indicator

/// M3 Expressive loading indicator: a soft rounded polygon that breathes and
/// turns. Replaces the generic spinner. Static under Reduce Motion.
struct LoadingIndicator: View {
    var size: CGFloat = 28
    var tint: Color = BumpColor.primary
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        LobedShape(lobes: 6, amplitude: reduceMotion ? 0.14 : (phase ? 0.22 : 0.08))
            .fill(tint)
            .frame(width: size, height: size)
            .rotationEffect(.degrees(reduceMotion ? 0 : (phase ? 360 : 0)))
            .animation(reduceMotion ? nil : .linear(duration: 2.2).repeatForever(autoreverses: false), value: phase)
            .onAppear { if !reduceMotion { phase = true } }
            .accessibilityLabel("Loading")
    }
}

/// r(θ) = R · (1 + a·cos(kθ)), a "cookie" outline.
struct LobedShape: Shape {
    var lobes: Int
    var amplitude: CGFloat
    var animatableData: CGFloat {
        get { amplitude } set { amplitude = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let base = min(rect.width, rect.height) / 2 / (1 + amplitude)
        var path = Path()
        let steps = 120
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let r = base * (1 + amplitude * cos(CGFloat(lobes) * t))
            let p = CGPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.closeSubpath()
        return path
    }
}

// MARK: - Two phones illustration

/// A native illustration of two phones meeting. When `animated` is true the
/// phones drift together, suppressed under Reduce Motion.
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
            BumpColor.surface.ignoresSafeArea()
            ScrollView {
                content
                    .padding(.horizontal, Space.gutter)
                    .padding(.top, Space.l)
                    // The tab bar floats over the content, so long screens need
                    // room to scroll clear of it. Without this the last section
                    // of a screen like Testing tools can never be reached.
                    .padding(.bottom, Space.l + 96)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// MARK: - Headings

/// M3 large top-app-bar title, drawn inside the scroll so it moves with content.
struct PageTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(BumpFont.displaySmall)
                .foregroundStyle(BumpColor.onSurface)
            if let subtitle {
                Text(subtitle)
                    .font(BumpFont.bodyLarge)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeading: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(BumpFont.titleLarge)
                .foregroundStyle(BumpColor.onSurface)
            if let subtitle {
                Text(subtitle)
                    .font(BumpFont.bodyMedium)
                    .foregroundStyle(BumpColor.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small uppercase label above a group, M3 "label-medium" style.
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(BumpFont.labelSmall)
            .kerning(0.8)
            .foregroundStyle(BumpColor.onSurfaceVariant)
    }
}

// MARK: - Navigation bar

/// M3 navigation bar: 80pt, tonal container, an active pill indicator that
/// springs between destinations.
struct BumpTabBar: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case bump, connections, you
        var id: Int { rawValue }
        var label: String {
            switch self { case .bump: return "Bump"; case .connections: return "Connections"; case .you: return "You" }
        }
        var icon: String {
            switch self { case .bump: return "hand.tap"; case .connections: return "person.2"; case .you: return "person.crop.circle" }
        }
        var filledIcon: String { icon + ".fill" }
    }

    @Binding var selection: Tab
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Tab.allCases) { tab in
                let selected = tab == selection
                Button {
                    guard !selected else { return }
                    withAnimation(reduceMotion ? nil : Motion.spatial) { selection = tab }
                    Haptics.tap()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            if selected {
                                Capsule()
                                    .fill(BumpColor.secondaryContainer)
                                    .matchedGeometryEffect(id: "indicator", in: indicator)
                            }
                            Image(systemName: selected ? tab.filledIcon : tab.icon)
                                .font(.system(size: 20, weight: .medium))
                                .symbolRenderingMode(.monochrome)
                                .scaleEffect(selected ? 1 : 0.96)
                        }
                        .frame(width: 64, height: 32)
                        Text(tab.label)
                            .font(selected ? BumpFont.labelMedium : BumpFont.labelMedium.weight(.medium))
                    }
                    .foregroundStyle(selected ? BumpColor.onSecondaryContainer : BumpColor.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.label)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .background(BumpColor.surfaceContainer.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Divider().overlay(BumpColor.outlineVariant.opacity(0.6)) }
    }
}

// MARK: - Bottom action bar

/// Actions pinned above the home indicator, on the page ground.
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: Space.xs) { content }
            .padding(.horizontal, Space.gutter)
            .padding(.top, Space.sm)
            .padding(.bottom, Space.s)
            .background(BumpColor.surface.ignoresSafeArea(edges: .bottom))
    }
}

// MARK: - Notice

/// Inline informational banner, tonal.
struct NoticeText: View {
    let text: String
    var icon: String = "info.circle.fill"
    var tone: StatusTone = .warn
    var body: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            Image(systemName: icon).foregroundStyle(tone.color).padding(.top, 1)
            Text(text).font(BumpFont.bodyMedium).foregroundStyle(BumpColor.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.large, style: .continuous).fill(tone.container))
        .accessibilityElement(children: .combine)
    }
}
