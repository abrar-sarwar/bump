import SwiftUI

/// The BUMP design system: colour roles, shape, type, spacing and motion.
/// One source of truth, organised the way Material Design 3 organises tokens
/// (colour roles + tonal surfaces, a shape scale, a type scale, spring motion)
/// but rendered with native SwiftUI on the existing BUMP palette: warm ivory
/// ground, the light wordmark blue, deep navy ink.

// MARK: - Colour roles

enum BumpColor {

    // Brand / primary -----------------------------------------------------

    /// The wordmark blue. Decorative use: wordmark, illustration, rings.
    static let brand = Color(hex: 0x73A9F5)
    /// `primary`: filled controls, active indicators, links. ~5:1 on white.
    static let primary = Color(hex: 0x2F6FD0)
    static let onPrimary = Color.white
    /// `primaryContainer`: tonal buttons, selected chips, hero cards.
    static let primaryContainer = Color(hex: 0xDCE9FD)
    static let onPrimaryContainer = Color(hex: 0x0E2F5E)

    // Secondary (navy family, used for quiet emphasis) ----------------------

    static let secondary = Color(hex: 0x4E657F)
    static let secondaryContainer = Color(hex: 0xE2EAF4)
    static let onSecondaryContainer = Color(hex: 0x16304D)

    // Tertiary (the warm accent from the orange phone) ----------------------

    static let tertiary = Color(hex: 0xA8501E)
    static let tertiaryContainer = Color(hex: 0xFFDCC8)
    static let onTertiaryContainer = Color(hex: 0x4A1E05)
    /// The warm phone in the illustration. Kept under its historic name.
    static let illustrationWarm = Color(hex: 0xF0955A)

    // Surfaces (tonal layering replaces shadows) -----------------------------

    /// `surface`: the warm ivory page ground.
    static let surface = Color(hex: 0xFFF9F0)
    static let surfaceContainerLowest = Color.white
    static let surfaceContainerLow = Color(hex: 0xFFFCF7)
    static let surfaceContainer = Color(hex: 0xF8F2E8)
    static let surfaceContainerHigh = Color(hex: 0xF2EBDF)
    static let surfaceContainerHighest = Color(hex: 0xEBE3D5)
    /// `onSurface`: primary text.
    static let onSurface = Color(hex: 0x183555)
    /// `onSurfaceVariant`: secondary text (~4.9:1 on ivory).
    static let onSurfaceVariant = Color(hex: 0x5A7290)
    static let outline = Color(hex: 0x8B99AD)
    static let outlineVariant = Color(hex: 0xE3DCCF)
    /// Inverse surface for snackbars / tooltips.
    static let inverseSurface = Color(hex: 0x1E2A3A)
    static let inverseOnSurface = Color(hex: 0xF4F0E8)

    // Semantic --------------------------------------------------------------

    static let positive = Color(hex: 0x2E7D5B)
    static let positiveContainer = Color(hex: 0xD7F0E3)
    static let warning = Color(hex: 0xB4761F)
    static let warningContainer = Color(hex: 0xFFEBCC)
    static let negative = Color(hex: 0xB03A3A)
    static let negativeContainer = Color(hex: 0xFADADA)

    // Legacy aliases (older call sites) ------------------------------------

    static let background = surface
    static let action = primary
    static let navy = onSurface
    static let secondaryText = onSurfaceVariant
    static let paleBlue = primaryContainer
    static let hairline = outlineVariant
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - State layers

/// Material state-layer opacities, applied as an overlay of the content colour.
enum StateLayer {
    static let hover: Double = 0.08
    static let focus: Double = 0.10
    static let pressed: Double = 0.10
    static let dragged: Double = 0.16
    /// Disabled controls: 38% content on a 12% container.
    static let disabledContent: Double = 0.38
    static let disabledContainer: Double = 0.12
}

// MARK: - Shape

/// The M3 shape scale. `full` is a capsule.
enum Radius {
    static let extraSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let largeIncreased: CGFloat = 20
    static let extraLarge: CGFloat = 28
    static let extraLargeIncreased: CGFloat = 32
    static let full: CGFloat = 999
}

// MARK: - Type

/// M3 type roles, expressed as Dynamic Type styles so they scale with the
/// user's text size. Display and headline use the rounded design: the same
/// friendliness as the wordmark, without shipping a font.
enum BumpFont {
    /// The wordmark: heavy and wide. Fixed size on purpose: it is a logo, not
    /// body copy, but always inside a `minimumScaleFactor`.
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded)
    }

    static let displayLarge = Font.system(.largeTitle, design: .rounded, weight: .bold)
    static let displaySmall = Font.system(.title, design: .rounded, weight: .bold)
    static let headlineLarge = Font.system(.title, design: .rounded, weight: .bold)
    static let headlineMedium = Font.system(.title2, design: .rounded, weight: .bold)
    static let headlineSmall = Font.system(.title3, design: .rounded, weight: .semibold)
    static let titleLarge = Font.system(.title3, design: .rounded, weight: .semibold)
    static let titleMedium = Font.system(.body, weight: .semibold)
    static let titleSmall = Font.system(.subheadline, weight: .semibold)
    static let bodyLarge = Font.system(.body)
    static let bodyMedium = Font.system(.subheadline)
    static let bodySmall = Font.system(.footnote)
    static let labelLarge = Font.system(.subheadline, weight: .semibold)
    static let labelMedium = Font.system(.footnote, weight: .semibold)
    static let labelSmall = Font.system(.caption, weight: .semibold)
    static let mono = Font.system(.caption2, design: .monospaced)

    // Legacy aliases (older call sites)
    static let screenTitle = headlineLarge
    static let sectionTitle = titleLarge
    static let body = bodyLarge
    static let bodyEmphasis = titleMedium
    static let caption = bodySmall
    static let button = labelLarge
}

// MARK: - Spacing

enum Space {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let sm: CGFloat = 12
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Standard screen gutter.
    static let gutter: CGFloat = 20
    static let corner: CGFloat = Radius.large
    static let cornerLarge: CGFloat = Radius.extraLarge
}

// MARK: - Motion

/// M3 Expressive motion: spatial springs move things, effects springs change
/// colour and opacity without overshoot. Every animated view still checks
/// Reduce Motion before using these.
enum Motion {
    /// Spatial, default. Layout and position changes.
    /// (M3 Expressive: stiffness 380, damping 0.8 → response ≈ 0.32 s.)
    static let spatial = Animation.spring(response: 0.38, dampingFraction: 0.8)
    /// Spatial, fast. Presses and small movements (stiffness 800, damping 0.6).
    static let spatialFast = Animation.spring(response: 0.24, dampingFraction: 0.62)
    /// Spatial, slow. Large hero moves (stiffness 200, damping 0.8).
    static let spatialSlow = Animation.spring(response: 0.5, dampingFraction: 0.8)
    /// Expressive: visible overshoot for celebratory moments (the reveal).
    static let expressive = Animation.spring(response: 0.5, dampingFraction: 0.6)
    /// Effects, default. Colour and opacity; never overshoots (stiffness 1600).
    static let effects = Animation.spring(response: 0.2, dampingFraction: 1)
    static let effectsFast = Animation.spring(response: 0.12, dampingFraction: 1)

    /// M3 "emphasized" easing, for the rare curve-based animation.
    static let emphasized = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.5)
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
}
