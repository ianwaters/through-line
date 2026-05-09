import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// MARK: - Dynamic colour helper

extension Color {
    /// Build a Color that switches automatically between light and dark variants.
    static func dynamic(light: Color, dark: Color) -> Color {
        #if canImport(UIKit)
        return Color(UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
        #elseif canImport(AppKit)
        return Color(NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark]) != nil
            return isDark ? NSColor(dark) : NSColor(light)
        })
        #endif
    }
}

// MARK: - Editorial Notebook palette

extension Color {
    /// Warm cream "paper" background — main surface
    static let paper = Color.dynamic(
        light: Color(red: 0.962, green: 0.949, blue: 0.918),
        dark:  Color(red: 0.094, green: 0.094, blue: 0.110)
    )

    /// A slightly deeper paper for cards / inset surfaces
    static let paperDeep = Color.dynamic(
        light: Color(red: 0.929, green: 0.910, blue: 0.860),
        dark:  Color(red: 0.137, green: 0.137, blue: 0.157)
    )

    /// Primary text — deep ink
    static let ink = Color.dynamic(
        light: Color(red: 0.106, green: 0.106, blue: 0.122),
        dark:  Color(red: 0.945, green: 0.937, blue: 0.910)
    )

    /// Secondary text
    static let inkSoft = Color.dynamic(
        light: Color(red: 0.290, green: 0.290, blue: 0.322),
        dark:  Color(red: 0.741, green: 0.722, blue: 0.682)
    )

    /// Tertiary / muted text
    static let inkMuted = Color.dynamic(
        light: Color(red: 0.529, green: 0.525, blue: 0.502),
        dark:  Color(red: 0.529, green: 0.518, blue: 0.494)
    )

    /// Whisper hairline — borders, dividers
    static let inkHairline = Color.dynamic(
        light: Color.black.opacity(0.08),
        dark:  Color.white.opacity(0.10)
    )

    /// House accent — burnt sienna / terracotta
    static let editorialAccent = Color.dynamic(
        light: Color(red: 0.722, green: 0.357, blue: 0.243),
        dark:  Color(red: 0.812, green: 0.451, blue: 0.318)
    )

    // MARK: Status palette (refined)

    static let editorialRed = Color.dynamic(
        light: Color(red: 0.784, green: 0.259, blue: 0.227),
        dark:  Color(red: 0.898, green: 0.376, blue: 0.341)
    )

    static let editorialAmber = Color.dynamic(
        light: Color(red: 0.839, green: 0.486, blue: 0.176),
        dark:  Color(red: 0.910, green: 0.580, blue: 0.275)
    )

    static let editorialMustard = Color.dynamic(
        light: Color(red: 0.776, green: 0.627, blue: 0.286),
        dark:  Color(red: 0.867, green: 0.722, blue: 0.408)
    )

    static let editorialNavy = Color.dynamic(
        light: Color(red: 0.239, green: 0.353, blue: 0.502),
        dark:  Color(red: 0.420, green: 0.537, blue: 0.722)
    )

    static let editorialSage = Color.dynamic(
        light: Color(red: 0.361, green: 0.549, blue: 0.353),
        dark:  Color(red: 0.490, green: 0.667, blue: 0.482)
    )

    static let editorialPlum = Color.dynamic(
        light: Color(red: 0.486, green: 0.349, blue: 0.561),
        dark:  Color(red: 0.620, green: 0.482, blue: 0.690)
    )
}

// MARK: - Typography

extension Font {
    /// New York display serif. Use for hero moments and section headlines.
    static func editorialDisplay(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Italic editorial serif. For captions, body previews, attributions.
    static func editorialItalic(_ size: CGFloat = 14) -> Font {
        .system(size: size, weight: .regular, design: .serif).italic()
    }

    /// Eyebrow label — small caps, letter-spaced. Sits above headlines.
    static let eyebrow: Font = .system(size: 11, weight: .semibold, design: .default).smallCaps()

    /// Refined number font with monospaced digits.
    static func editorialNumeric(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .serif).monospacedDigit()
    }
}

// MARK: - Modifiers

extension View {
    /// A subtle eyebrow header (small caps, letter-spaced).
    func eyebrowStyle(tint: Color = .inkMuted) -> some View {
        self
            .font(.eyebrow)
            .tracking(2)
            .foregroundStyle(tint)
    }

    /// Hairline divider matching the editorial palette.
    func editorialDivider() -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.inkHairline)
                .frame(height: 0.5)
        }
    }
}
