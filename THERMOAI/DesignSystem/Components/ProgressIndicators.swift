//
//  ProgressIndicators.swift
//  THERMOAI — DesignSystem/Components
//
//  Purpose: Animated progress visuals — the hero calorie ring, compact macro
//           rings and linear macro bars. All respect Reduce Motion.
//  Dependencies: SwiftUI, DesignSystem/Theme.swift
//

import SwiftUI

/// Large animated calorie ring with heat gradient and over-budget state.
struct CalorieRing: View {
    let consumed: Double
    let target: Double
    var lineWidth: CGFloat = 20

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    private var progress: Double { target > 0 ? consumed / target : 0 }
    private var remaining: Double { target - consumed }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surfaceHighlight, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: min(animatedProgress, 1))
                .stroke(Theme.Gradients.heatAngular, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: Theme.Colors.accent.opacity(0.45), radius: 12)

            // Overflow lap in red when over target.
            if animatedProgress > 1 {
                Circle()
                    .trim(from: 0, to: min(animatedProgress - 1, 1))
                    .stroke(Theme.Colors.danger, style: StrokeStyle(lineWidth: lineWidth * 0.55, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            VStack(spacing: 2) {
                Text(abs(remaining), format: .number.precision(.fractionLength(0)))
                    .font(Theme.Typography.hero)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: remaining))
                Text(remaining >= 0 ? "kcal left" : "kcal over")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(remaining >= 0 ? Theme.Colors.textSecondary : Theme.Colors.danger)
                    .textCase(.uppercase)
                    .tracking(1.5)
            }
        }
        .padding(lineWidth / 2)
        .onAppear { animate() }
        .onChange(of: progress) { _, _ in animate() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calories")
        .accessibilityValue("\(Int(consumed)) of \(Int(target)) kilocalories, \(Int(abs(remaining))) \(remaining >= 0 ? "remaining" : "over")")
    }

    private func animate() {
        if reduceMotion { animatedProgress = progress } else {
            withAnimation(Theme.Motion.ring) { animatedProgress = progress }
        }
    }
}

/// Compact ring for one macro.
struct MacroRing: View {
    let title: String
    let value: Double
    let target: Double
    let color: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animated: Double = 0

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            ZStack {
                Circle().stroke(color.opacity(0.15), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(animated, 1))
                    .stroke(color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))")
                    .font(Theme.Typography.metricSmall)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.numericText(value: value))
            }
            .frame(width: 64, height: 64)
            VStack(spacing: 0) {
                Text(title).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textPrimary)
                Text("/ \(Int(target)) g").font(.caption2).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .onAppear { update() }
        .onChange(of: value) { _, _ in update() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value)) of \(Int(target)) grams")
    }

    private func update() {
        let p = target > 0 ? value / target : 0
        if reduceMotion { animated = p } else { withAnimation(Theme.Motion.ring) { animated = p } }
    }
}

/// Linear macro bar with label and value.
struct MacroBar: View {
    let title: String
    let value: Double
    let target: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(Int(value)) / \(Int(target)) g")
                    .font(Theme.Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.15))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: geo.size.width * min(target > 0 ? value / target : 0, 1))
                        .animation(Theme.Motion.spring, value: value)
                }
            }
            .frame(height: 8)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Brand mark: a stylised flame inside a heat ring.
struct ThermoLogo: View {
    var size: CGFloat = 44
    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Gradients.heat)
                .shadow(color: Theme.Colors.accent.opacity(0.6), radius: size * 0.3)
            Image(systemName: "flame.fill")
                .font(.system(size: size * 0.48, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
