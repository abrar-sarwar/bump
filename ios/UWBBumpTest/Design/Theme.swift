import SwiftUI

/// The BUMP design system: colour, type, spacing. One source of truth.
///
/// Ported from `ios-mockup/tokens.css`, which follows the marketing site
/// (`web/`) with the brand kept exactly: the wordmark is artwork (never a
/// font), type is Archivo, colour is the site's Material 3 scheme generated
/// from the wordmark ink (seed #70AAF9), and cards use the site's frosted
/// card language. The older names (`navy`, `paleBlue`, …) are kept so every
/// view keeps compiling; they now point at the new values.

// MARK: - Colour

enum BumpColor {
    // MD3 roles, light scheme (web/src/styles/tokens.css).
    static let primary = Color(hex: 0x155FA9)
    static let onPrimary = Color.white
    static let primaryContainer = Color(hex: 0xD4E3FF)
    static let onPrimaryContainer = Color(hex: 0x001C3A)
    static let secondary = Color(hex: 0x545F71)
    static let tertiary = Color(hex: 0x6D5676)
    static let error = Color(hex: 0xBA1A1A)
    static let errorContainer = Color(hex: 0xFFDAD6)
    static let surfaceMD = Color(hex: 0xFDFCFF)
    static let onSurface = Color(hex: 0x1A1C1E)
    static let onSurfaceVariant = Color(hex: 0x43474E)
    static let outline = Color(hex: 0x74777F)
    static let outlineVariant = Color(hex: 0xC3C6CF)
    static let surfaceContainerHighest = Color(hex: 0xE3E2E6)

    /// Slate ink the site's cards use for dark accents (its back-to-top button).
    static let ink = Color(hex: 0x1F2A2F)
    /// Grey pill track: tags, pill tabs, status pills (ink at 6%).
    static let track = Color(hex: 0x1F2A2F, opacity: 0.06)
    /// Faint tertiary text (on-surface at 45%).
    static let faint = Color(hex: 0x1A1C1E, opacity: 0.45)

    // Brand reference: artwork only, never chrome.
    /// The wordmark ink. Decorative only.
    static let brand = Color(hex: 0x70AAF9)
    /// The orange phone. Illustration, and "the other person".
    static let illustrationWarm = Color(hex: 0xF0955A)

    // The names the views already use, repointed.
    static let background = surfaceMD
    static let action = primary
    static let navy = onSurface
    static let secondaryText = onSurfaceVariant
    static let surface = Color.white
    static let paleBlue = track
    static let hairline = Color(hex: 0x1F2A2F, opacity: 0.08)
    static let positive = Color(hex: 0x2E7D5B)
    static let warning = Color(hex: 0x8A5A00)
    static let negative = error
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Type

/// Archivo, bundled in `Fonts/` and registered in Info.plist (UIAppFonts).
///
/// The static files carry the PostScript names below (their internal family
/// is "Archivo SemiBold" at every weight, so we address faces by PostScript
/// name rather than family + weight). If a face ever fails to load, SwiftUI
/// falls back to the system font, so text still renders.
enum Archivo {
    static let regular = "ArchivoSemiBold-Regular"      // 400
    static let medium = "ArchivoSemiBold-Medium"        // 500
    static let semibold = "ArchivoSemiBold-SemiBold"    // 600
    static let bold = "ArchivoSemiBold-Bold"            // 700
    static let extraBold = "ArchivoSemiBold-ExtraBold"  // 800
}

enum BumpFont {
    /// Archivo at a size that scales with Dynamic Type relative to `style`.
    static func archivo(_ face: String, _ size: CGFloat, relativeTo style: Font.TextStyle) -> Font {
        .custom(face, size: size, relativeTo: style)
    }

    /// Headings run heavy and tight, like the site's (800, -0.025em).
    static let screenTitle = archivo(Archivo.extraBold, 31, relativeTo: .largeTitle)
    static let display = archivo(Archivo.extraBold, 40, relativeTo: .largeTitle)
    static let sectionTitle = archivo(Archivo.bold, 20, relativeTo: .title3)
    static let body = archivo(Archivo.regular, 16, relativeTo: .body)
    static let bodyEmphasis = archivo(Archivo.semibold, 16, relativeTo: .body)
    static let caption = archivo(Archivo.regular, 14, relativeTo: .subheadline)
    static let captionEmphasis = archivo(Archivo.semibold, 14, relativeTo: .subheadline)
    static let captionMedium = archivo(Archivo.medium, 14, relativeTo: .subheadline)
    static let caption2 = archivo(Archivo.medium, 12, relativeTo: .caption)
    static let button = archivo(Archivo.semibold, 16, relativeTo: .body)
    /// The site's "SCROLL TO BUMP" line: uppercase, letter-spaced. Pair with
    /// `.textCase(.uppercase)` and `.tracking(Tracking.eyebrow)`.
    static let eyebrow = archivo(Archivo.semibold, 12.5, relativeTo: .caption)
    static let mono = Font.system(.caption2, design: .monospaced)
}

/// Letter spacing, in points at the base size.
enum Tracking {
    static let title: CGFloat = -0.8      // -0.025em at 31pt
    static let eyebrow: CGFloat = 2.0     // 0.16em at 12.5pt
}

// MARK: - Spacing & shape

enum Space {
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 16
    static let l: CGFloat = 24
    static let xl: CGFloat = 32
    static let xxl: CGFloat = 48

    /// Standard screen gutter.
    static let gutter: CGFloat = 20
    /// Frosted card corner.
    static let corner: CGFloat = 18
    /// Bento corner (the site's --folk-radius-bento).
    static let cornerLarge: CGFloat = 22
    /// Primary / secondary button height.
    static let buttonHeight: CGFloat = 54
}

// MARK: - Motion

enum BumpMotion {
    /// MD3 standard easing, cubic-bezier(0.2, 0, 0, 1).
    static let standard = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.3)
    /// MD3 emphasized decelerate, cubic-bezier(0.05, 0.7, 0.1, 1).
    static let emphasizedIn = Animation.timingCurve(0.05, 0.7, 0.1, 1, duration: 0.5)
    /// Shared badge timing lives with its maths (ScallopGeometry, testable).
    static let badgeLoop: Double = ScallopGeometry.badgeLoop
    static let badgeInterestHold: Double = ScallopGeometry.badgeInterestHold
}
