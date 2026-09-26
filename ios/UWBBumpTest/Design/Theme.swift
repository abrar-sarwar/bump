import SwiftUI

/// The BUMP design system: colours, type, spacing. One source of truth.
///
/// Derived from the brand reference (warm ivory ground, wide blue uppercase
/// wordmark, deep navy text). The purple outlines and grey chrome in the
/// reference screenshots are Canva's editor UI, not brand, and are not used.

// MARK: - Colour

enum BumpColor {
    /// Warm ivory page background.
    static let background = Color(hex: 0xFFF9F0)
    /// The wordmark / brand blue. Light and friendly — decorative use only.
    static let brand = Color(hex: 0x73A9F5)
    /// Deeper blue for filled buttons. #73A9F5 behind white text is only ~2.4:1,
    /// which fails WCAG AA, so filled controls use this instead (~5:1 on white).
    static let action = Color(hex: 0x2F6FD0)
    /// Primary text.
    static let navy = Color(hex: 0x183555)
    /// Muted blue-grey secondary text (~4.9:1 on the ivory background).
    static let secondaryText = Color(hex: 0x5A7290)
    /// Raised surfaces.
    static let surface = Color.white
    /// Very pale blue fill for chips, wells and inactive states.
    static let paleBlue = Color(hex: 0xEAF1FD)
    static let hairline = Color(hex: 0xE3DCCF)
    static let positive = Color(hex: 0x2E7D5B)
    static let warning = Color(hex: 0xB4761F)
    static let negative = Color(hex: 0xB03A3A)
    /// Warm tone used ONLY inside the two-phones illustration, echoing the
    /// orange phone in the reference photograph. Not a general brand colour.
    static let illustrationWarm = Color(hex: 0xF0955A)
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

// MARK: - Type

enum BumpFont {
    /// The wordmark: heavy and wide, approximating the reference lettering with
    /// the system font since no licensed brand font ships with the repo.
    /// Fixed size on purpose — it is a logo, not body copy — but it stays inside
    /// a `minimumScaleFactor` so it never clips at large accessibility sizes.
    static func wordmark(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black).width(.expanded)
    }

    // Everything below is Dynamic Type relative, so it scales with the user's
    // text-size setting.
    static let screenTitle = Font.system(.largeTitle, weight: .bold)
    static let sectionTitle = Font.system(.title3, weight: .semibold)
    static let body = Font.system(.body)
    static let bodyEmphasis = Font.system(.body, weight: .semibold)
    static let caption = Font.system(.footnote)
    static let button = Font.system(.body, weight: .semibold)
    static let mono = Font.system(.caption2, design: .monospaced)
}

// MARK: - Spacing

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Standard screen gutter.
    static let gutter: CGFloat = 20
    static let corner: CGFloat = 16
    static let cornerLarge: CGFloat = 24
}
