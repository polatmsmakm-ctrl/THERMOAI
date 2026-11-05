//
//  Controls.swift
//  THERMOAI — DesignSystem/Components
//
//  Purpose: Buttons, stat tiles, section headers, chips, numeric fields and
//           the reusable error banner.
//  Dependencies: SwiftUI, DesignSystem/Theme.swift
//

import SwiftUI

// MARK: - Buttons

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(isEnabled ? AnyShapeStyle(Theme.Gradients.heat) : AnyShapeStyle(Theme.Colors.surfaceHighlight))
                    .shadow(color: Theme.Colors.accent.opacity(isEnabled ? 0.35 : 0), radius: 14, y: 6)
            }
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typography.headline)
            .foregroundStyle(Theme.Colors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Colors.surfaceHighlight)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .strokeBorder(Theme.Colors.stroke)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle { static var thermoPrimary: PrimaryButtonStyle { .init() } }
extension ButtonStyle where Self == SecondaryButtonStyle { static var thermoSecondary: SecondaryButtonStyle { .init() } }

/// Primary button that swaps its label for a spinner while loading.
struct LoadingButton: View {
    let title: String
    var systemImage: String? = nil
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().tint(.white)
                } else if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
        }
        .buttonStyle(.thermoPrimary)
        .disabled(isLoading)
        .sensoryFeedback(.impact(weight: .light), trigger: isLoading)
    }
}

// MARK: - Stat tile

struct StatTile: View {
    let title: String
    let value: String
    var unit: String = ""
    var systemImage: String
    var tint: Color = Theme.Colors.accent
    var footnote: String? = nil

    var body: some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Label(title, systemImage: systemImage)
                    .font(Theme.Typography.overline)
                    .foregroundStyle(tint)
                    .textCase(.uppercase)
                    .tracking(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(Theme.Typography.metric)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText())
                    if !unit.isEmpty {
                        Text(unit).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                if let footnote {
                    Text(footnote).font(.caption2).foregroundStyle(Theme.Colors.textTertiary).lineLimit(2)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.Typography.title2).foregroundStyle(Theme.Colors.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            Spacer()
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(Theme.Typography.callout.weight(.semibold))
                    .foregroundStyle(Theme.Colors.accent)
            }
        }
    }
}

// MARK: - Chips

struct SelectableChip: View {
    let title: String
    var systemImage: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(Theme.Typography.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isSelected ? Color.black : Theme.Colors.textPrimary)
            .background(
                Capsule().fill(isSelected ? AnyShapeStyle(Theme.Gradients.heat) : AnyShapeStyle(Theme.Colors.surfaceHighlight))
            )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Fields

/// Labelled decimal input with unit suffix.
struct NumericField: View {
    let title: String
    @Binding var value: Double
    var unit: String
    var precision: Int = 1

    var body: some View {
        HStack {
            Text(title).foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            TextField(title, value: $value, format: .number.precision(.fractionLength(0...precision)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Theme.Typography.metricSmall)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(maxWidth: 110)
            Text(unit).foregroundStyle(Theme.Colors.textTertiary).frame(width: 36, alignment: .leading)
        }
        .padding(.vertical, 4)
    }
}

/// Styled text field for forms on dark surfaces.
struct ThermoTextField: View {
    let title: String
    @Binding var text: String
    var systemImage: String
    var isSecure = false

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage).foregroundStyle(Theme.Colors.textTertiary).frame(width: 20)
            Group {
                if isSecure { SecureField(title, text: $text) } else { TextField(title, text: $text) }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).fill(Theme.Colors.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous).strokeBorder(Theme.Colors.stroke))
    }
}

// MARK: - Error banner

struct ErrorBanner: View {
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.Colors.warning)
            Text(message).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textPrimary)
            Spacer(minLength: 0)
            if let retry {
                Button("Retry", action: retry).font(Theme.Typography.callout.weight(.semibold))
            }
        }
        .padding(Theme.Spacing.md)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.Colors.warning.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm).strokeBorder(Theme.Colors.warning.opacity(0.3)))
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Confidence pill for AI estimates.
struct ConfidenceBadge: View {
    let confidence: Double
    private var label: String { confidence >= 0.75 ? "High" : confidence >= 0.5 ? "Medium" : "Low" }
    private var color: Color { confidence >= 0.75 ? Theme.Colors.success : confidence >= 0.5 ? Theme.Colors.warning : Theme.Colors.danger }

    var body: some View {
        Label("\(label) confidence", systemImage: "sparkles")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.14)))
    }
}
