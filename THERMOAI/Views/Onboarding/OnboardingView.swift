//
//  OnboardingView.swift
//  THERMOAI — Views/Onboarding
//
//  Purpose: Five-step onboarding: welcome → body → activity → goal → review
//           (live BMR/TDEE/macro preview) with optional Apple Health import.
//  Dependencies: SwiftUI, SwiftData, ViewModels/OnboardingViewModel.swift
//

import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @State private var vm: OnboardingViewModel?
    @State private var healthEnabled = false

    var body: some View {
        Group {
            if let vm { content(vm) } else { Color.clear }
        }
        .onAppear {
            if vm == nil { vm = OnboardingViewModel(health: env.health) }
        }
    }

    @ViewBuilder
    private func content(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm
        VStack(spacing: 0) {
            // Progress header
            HStack(spacing: 6) {
                ForEach(OnboardingViewModel.Step.allCases, id: \.self) { step in
                    Capsule()
                        .fill(step.rawValue <= vm.step.rawValue ? AnyShapeStyle(Theme.Gradients.heat) : AnyShapeStyle(Theme.Colors.surfaceHighlight))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.md)

            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    switch vm.step {
                    case .welcome: welcome(vm)
                    case .body: bodyStep(vm)
                    case .activity: activityStep(vm)
                    case .goal: goalStep(vm)
                    case .review: reviewStep(vm)
                    }
                    if let msg = vm.validationMessage ?? vm.errorMessage { ErrorBanner(message: msg) }
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
                .id(vm.step)
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .scrollDismissesKeyboard(.interactively)

            // Footer
            HStack(spacing: Theme.Spacing.sm) {
                if vm.step != .welcome {
                    Button("Back") { withAnimation(Theme.Motion.spring) { vm.back() } }
                        .buttonStyle(.thermoSecondary)
                        .frame(maxWidth: 120)
                }
                Button(vm.step == .review ? "Start THERMO AI" : "Continue") {
                    if vm.step == .review { finish(vm) } else { withAnimation(Theme.Motion.spring) { vm.next() } }
                }
                .buttonStyle(.thermoPrimary)
                .disabled(!vm.canAdvance)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 560)
        }
        .thermoScreen()
    }

    // MARK: Steps

    private func welcome(_ vm: OnboardingViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            ThermoLogo(size: 64).padding(.top, Theme.Spacing.xl)
            Text("Your metabolism,\ndecoded.")
                .font(Theme.Typography.hero)
                .foregroundStyle(Theme.Colors.textPrimary)
            Text("We'll calculate your BMR, total daily energy expenditure and the thermic effect of what you eat — then build targets around your goal.")
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
            GlassCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Label("Import from Apple Health", systemImage: "heart.fill")
                        .font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Prefill height, weight and body fat, and sync meals and weigh-ins.")
                        .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                    Button {
                        Task {
                            await vm.importFromHealth()
                            healthEnabled = vm.errorMessage == nil
                        }
                    } label: {
                        if vm.isImporting { ProgressView() } else { Text(healthEnabled ? "Connected ✓" : "Connect") }
                    }
                    .buttonStyle(.thermoSecondary)
                    .disabled(vm.isImporting || healthEnabled)
                }
            }
        }
    }

    private func bodyStep(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            stepTitle("About you", "Used only to calculate your metabolic rate.")
            ThermoTextField(title: "First name (optional)", text: $vm.displayName, systemImage: "person")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(BiologicalSex.allCases) { sex in
                    SelectableChip(title: sex.title, isSelected: vm.sex == sex) { vm.sex = sex }
                }
            }
            ThermoCard {
                VStack(spacing: Theme.Spacing.sm) {
                    DatePicker("Birth date", selection: $vm.birthDate,
                               in: ...Calendar.current.date(byAdding: .year, value: -18, to: .now)!,
                               displayedComponents: .date)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Divider().overlay(Theme.Colors.stroke)
                    NumericField(title: "Height", value: $vm.heightCm, unit: "cm", precision: 0)
                    Divider().overlay(Theme.Colors.stroke)
                    NumericField(title: "Weight", value: $vm.weightKg, unit: "kg")
                    Divider().overlay(Theme.Colors.stroke)
                    Toggle("I know my body fat %", isOn: Binding(
                        get: { vm.bodyFatPercent != nil },
                        set: { vm.bodyFatPercent = $0 ? 20 : nil }))
                        .foregroundStyle(Theme.Colors.textSecondary)
                    if vm.bodyFatPercent != nil {
                        NumericField(title: "Body fat",
                                     value: Binding(get: { vm.bodyFatPercent ?? 20 }, set: { vm.bodyFatPercent = $0 }),
                                     unit: "%")
                    }
                }
            }
        }
    }

    private func activityStep(_ vm: OnboardingViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            stepTitle("Activity level", "Your typical week, outside of logged workouts.")
            ForEach(ActivityLevel.allCases) { level in
                Button { withAnimation(Theme.Motion.quick) { vm.activity = level } } label: {
                    ThermoCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.title).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                                Text(level.detail).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Text("×\(level.multiplier, specifier: "%.3g")")
                                .font(Theme.Typography.metricSmall)
                                .foregroundStyle(vm.activity == level ? Theme.Colors.accent : Theme.Colors.textTertiary)
                            Image(systemName: vm.activity == level ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(vm.activity == level ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .strokeBorder(vm.activity == level ? Theme.Colors.accent : .clear, lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: vm.activity)
            }
        }
    }

    private func goalStep(_ vm: OnboardingViewModel) -> some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            stepTitle("Your goal", "We'll set a sustainable daily energy target.")
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(WeightGoal.allCases) { goal in
                    SelectableChip(title: goal.title, systemImage: goal.symbol, isSelected: vm.goal == goal) { vm.goal = goal }
                }
            }
            if vm.goal != .maintain {
                ThermoCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        NumericField(title: "Target weight", value: $vm.targetWeightKg, unit: "kg")
                        VStack(alignment: .leading) {
                            Text("Rate: \(vm.rateKgPerWeek, specifier: "%.2f") kg / week")
                                .font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                            Slider(value: $vm.rateKgPerWeek, in: 0.1...(vm.goal == .lose ? 1.0 : 0.5), step: 0.05)
                            Text("≈ \(Int(vm.rateKgPerWeek * NutritionEngine.kcalPerKgBodyMass / 7)) kcal/day \(vm.goal == .lose ? "deficit" : "surplus")")
                                .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                }
            }
        }
    }

    private func reviewStep(_ vm: OnboardingViewModel) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            stepTitle("Your metabolic profile", "You can fine-tune everything later in Settings.")
            if let p = vm.preview {
                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Daily target").font(Theme.Typography.overline).foregroundStyle(Theme.Colors.accentAmber).textCase(.uppercase)
                        Text("\(Int(p.targetCalories)) kcal").font(Theme.Typography.hero).foregroundStyle(Theme.Colors.textPrimary)
                        if p.wasClampedToSafetyFloor {
                            Text("Raised to a safe minimum intake.").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.warning)
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Theme.Spacing.sm) {
                    StatTile(title: "BMR", value: "\(Int(p.bmr))", unit: "kcal", systemImage: "bolt.heart.fill", footnote: p.formula.title)
                    StatTile(title: "TDEE", value: "\(Int(p.tdee))", unit: "kcal", systemImage: "flame.fill")
                    StatTile(title: "BMI", value: String(format: "%.1f", p.bmi), systemImage: "figure", footnote: p.bmiCategory.rawValue)
                    StatTile(title: "Lean mass", value: String(format: "%.1f", p.leanBodyMassKg), unit: "kg",
                             systemImage: "figure.strengthtraining.traditional", footnote: p.leanMassIsEstimated ? "Estimated (Boer)" : "From body fat")
                }
                ThermoCard {
                    VStack(spacing: Theme.Spacing.sm) {
                        MacroBar(title: "Protein", value: p.macros.proteinG, target: p.macros.proteinG, color: Theme.Colors.protein)
                        MacroBar(title: "Carbs", value: p.macros.carbsG, target: p.macros.carbsG, color: Theme.Colors.carbs)
                        MacroBar(title: "Fat", value: p.macros.fatG, target: p.macros.fatG, color: Theme.Colors.fat)
                    }
                }
            }
        }
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.Typography.title).foregroundStyle(Theme.Colors.textPrimary)
            Text(subtitle).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func finish(_ vm: OnboardingViewModel) {
        guard let userID = env.auth.currentUserID else { return }
        do {
            try vm.complete(in: context, userID: userID, healthEnabled: healthEnabled)
            Task { await env.sync?.syncNow() }
        } catch {
            vm.errorMessage = "Couldn't save your profile: \(error.localizedDescription)"
        }
    }
}
