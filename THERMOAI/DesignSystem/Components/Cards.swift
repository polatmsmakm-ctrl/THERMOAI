//
//  Cards.swift
//  THERMOAI — DesignSystem/Components
//
//  Purpose: Surface containers — solid ThermoCard and selective GlassCard
//           (glassmorphism reserved for hero/overlay content only).
//  Dependencies: SwiftUI, DesignSystem/Theme.swift
//

import SwiftUI

/// Standard elevated surface used for most content.
struct ThermoCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                    .fill(Theme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .fill(Theme.Gradients.cardSheen)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                            .strokeBorder(Theme.Colors.stroke, lineWidth: 1)
                    )
            }
    }
}

/// Frosted glass surface with a warm inner glow. Use sparingly (hero, overlays).
struct GlassCard<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.lg
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .fill(Theme.Gradients.ambientGlow.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                            .strokeBorder(
                                LinearGradient(colors: [Color.white.opacity(0.18), Theme.Colors.accent.opacity(0.18), .clear],
                                               startPoint: .topLeading, endPoint: .bottomTrailing),
                                lineWidth: 1)
                    )
                    .shadow(color: Theme.Colors.accent.opacity(0.12), radius: 30, y: 12)
            }
    }
}

/// Screen background: charcoal with a soft heat bloom at the top.
struct ThermoBackground: View {
    var body: some View {
        ZStack {
            Theme.Colors.background
            Theme.Gradients.ambientGlow
                .blur(radius: 40)
                .offset(y: -120)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Applies the standard THERMO screen background.
    func thermoScreen() -> some View {
        background(ThermoBackground())
            .scrollContentBackground(.hidden)
    }
}
