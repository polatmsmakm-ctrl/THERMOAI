//
//  Theme.swift
//  THERMOAI — DesignSystem
//
//  Purpose: Design tokens — colour, typography, spacing, radii, motion — for the
//           premium dark "thermal" look: deep charcoal surfaces with orange→amber heat.
//  Dependencies: SwiftUI, UIKit
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: Colours

    enum Colors {
        /// Near-black charcoal with a faint warm undertone.
        static let background = Color(hex: 0x0D0E11)
        static let backgroundElevated = Color(hex: 0x15171C)
        static let surface = Color(hex: 0x1B1E24)
        static let surfaceHighlight = Color(hex: 0x252932)
        static let stroke = Color.white.opacity(0.07)

        static let textPrimary = Color(hex: 0xF5F3EF)
        static let textSecondary = Color(hex: 0xA6A3A0)
        static let textTertiary = Color(hex: 0x6E6C6A)

        /// Signature heat accents.
        static let accent = Color(hex: 0xFF7A1A)       // ember orange
        static let accentAmber = Color(hex: 0xFFB020)  // amber
        static let accentDeep = Color(hex: 0xE2471B)   // deep flame

        /// Macro identity colours (warm-harmonised, distinguishable for colour-blind users by luminance).
        static let protein = Color(hex: 0xFF8A4C)
        static let carbs = Color(hex: 0xFFC857)
        static let fat = Color(hex: 0xC5A3FF)
        static let fiber = Color(hex: 0x7ED3A7)

        static let success = Color(hex: 0x5ED39A)
        static let warning = Color(hex: 0xFFB020)
        static let danger = Color(hex: 0xFF5A5F)
    }

    enum Gradients {
        static let heat = LinearGradient(colors: [Colors.accentDeep, Colors.accent, Colors.accentAmber],
                                         startPoint: .bottomLeading, endPoint: .topTrailing)
        static let heatAngular = AngularGradient(colors: [Colors.accentDeep, Colors.accent, Colors.accentAmber, Colors.accentDeep],
                                                 center: .center)
        static let ambientGlow = RadialGradient(colors: [Colors.accent.opacity(0.22), .clear],
                                                center: .top, startRadius: 0, endRadius: 420)
        static let cardSheen = LinearGradient(colors: [Color.white.opacity(0.06), Color.white.opacity(0.0)],
                                              startPoint: .top, endPoint: .bottom)
    }

    // MARK: Typography (SF Pro Rounded for numbers, SF Pro for text — Dynamic Type aware)

    enum Typography {
        static let hero = Font.system(size: 44, weight: .bold, design: .rounded)
        static let title = Font.system(.title, design: .rounded).weight(.bold)
        static let title2 = Font.system(.title2, design: .rounded).weight(.semibold)
        static let headline = Font.system(.headline, design: .default).weight(.semibold)
        static let body = Font.system(.body)
        static let callout = Font.system(.callout)
        static let caption = Font.system(.caption).weight(.medium)
        static let overline = Font.system(.caption2, design: .default).weight(.semibold)
        static let metric = Font.system(.title2, design: .rounded).weight(.bold).monospacedDigit()
        static let metricSmall = Font.system(.headline, design: .rounded).weight(.semibold).monospacedDigit()
    }

    // MARK: Layout

    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 12
        static let md: CGFloat = 20
        static let lg: CGFloat = 28
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.55, dampingFraction: 0.82)
        static let ring = Animation.spring(response: 1.1, dampingFraction: 0.85)
        static let quick = Animation.snappy(duration: 0.25)
    }

    // MARK: UIKit bridging

    @MainActor
    static func applyUIKitAppearance() {
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [
            .foregroundColor: UIColor(Colors.textPrimary),
            .font: UIFont.systemFont(ofSize: 34, weight: .bold).rounded,
        ]
        nav.titleTextAttributes = [.foregroundColor: UIColor(Colors.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
        UINavigationBar.appearance().compactAppearance = nav
    }
}

// MARK: - Helpers

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

extension UIFont {
    var rounded: UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: pointSize)
    }
}
