//
//  ProgressDashboardView.swift
//  THERMOAI — Views/Progress
//
//  Purpose: Health analytics — range picker, weight trend chart, calorie
//           history, adaptive vs estimated TDEE, body composition and weigh-ins.
//           (Named to avoid clashing with SwiftUI.ProgressView.)
//  Dependencies: SwiftUI, SwiftData, ViewModels/ProgressViewModel.swift, DesignSystem/Components/Charts.swift
//

import SwiftUI
import SwiftData

struct ProgressDashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<FoodEntry> { !$0.isSoftDeleted }) private var entries: [FoodEntry]
    @Query(filter: #Predicate<WeightEntry> { !$0.isSoftDeleted }, sort: \WeightEntry.recordedAt, order: .reverse)
    private var weights: [WeightEntry]

    @State private var vm: ProgressViewModel
    @State private var showWeighIn = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: ProgressViewModel(health: env.health))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Picker("Range", selection: $vm.range) {
                        ForEach(ProgressViewModel.Range.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    if let a = vm.analytics, let profile = profiles.first {
                        statsGrid(a)
                        ThermoCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeader(title: "Weight", subtitle: "Dots: weigh-ins · Line: smoothed trend",
                                              actionTitle: "Log") { showWeighIn = true }
                                if a.trend.count >= 2 {
                                    WeightTrendChart(points: a.trend, goalKg: profile.targetWeightKg)
                                } else {
                                    Text("Log at least two weigh-ins to see your trend.")
                                        .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                                }
                            }
                        }
                        ThermoCard {
                            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                                SectionHeader(title: "Calories", subtitle: "Drag to inspect a day")
                                CalorieHistoryChart(days: a.intake, target: MetricsCalculator.metabolicProfile(profile: profile, weights: weights)?.targetCalories ?? 0)
                            }
                        }
                        compositionCard(profile)
                        weighInList
                    }
                }
                .padding(Theme.Spacing.md)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .thermoScreen()
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showWeighIn = true } label: { Image(systemName: "scalemass.fill") }
                        .accessibilityLabel("Log weight")
                }
            }
            .sheet(isPresented: $showWeighIn) {
                WeighInSheet(vm: vm, exportToHealth: profiles.first?.healthKitEnabled ?? false)
                    .presentationDetents([.medium])
                    .presentationBackground(Theme.Colors.backgroundElevated)
            }
        }
        .task(id: "\(vm.range.rawValue)-\(entries.count)-\(weights.count)") { recompute() }
    }

    private func recompute() {
        guard let profile = profiles.first else { return }
        withAnimation(Theme.Motion.spring) { vm.refresh(profile: profile, entries: entries, weights: weights) }
    }

    private func statsGrid(_ a: ProgressViewModel.Analytics) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: sizeClass == .regular ? 4 : 2)
        return LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
            StatTile(title: "Avg intake", value: a.averageCalories.map { "\(Int($0))" } ?? "—", unit: "kcal", systemImage: "fork.knife")
            StatTile(title: "Weekly rate", value: a.weeklyRateKg.map { String(format: "%+.2f", $0) } ?? "—", unit: "kg",
                     systemImage: "arrow.up.arrow.down", tint: Theme.Colors.accentAmber)
            StatTile(title: "Est. TDEE", value: a.estimatedTDEE.map { "\(Int($0))" } ?? "—", unit: "kcal",
                     systemImage: "function", footnote: "From equations")
            StatTile(title: "Observed TDEE", value: a.adaptiveTDEE.map { "\(Int($0))" } ?? "—", unit: "kcal",
                     systemImage: "waveform.path.ecg", tint: Theme.Colors.success,
                     footnote: a.adaptiveTDEE == nil ? "Needs 14+ days of data" : "From your intake & weight")
        }
    }

    private func compositionCard(_ profile: UserProfile) -> some View {
        let weight = MetricsCalculator.currentWeightKg(weights) ?? 0
        let measuredBF = MetricsCalculator.currentBodyFat(profile: profile, weights: weights)
        let bf = measuredBF ?? NutritionEngine.estimatedBodyFatPercent(weightKg: max(weight, 20), heightCm: profile.heightCm, sex: profile.sex)
        let lean = NutritionEngine.leanBodyMass(weightKg: weight, bodyFatPercent: bf)
        let bmi = NutritionEngine.bmi(weightKg: weight, heightCm: profile.heightCm)
        return ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Body composition", subtitle: measuredBF == nil ? "Body fat estimated (Boer formula)" : "From your measurements")
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.success.gradient)
                            .frame(width: geo.size.width * (1 - bf / 100))
                        RoundedRectangle(cornerRadius: 6).fill(Theme.Colors.accentAmber.gradient)
                    }
                }
                .frame(height: 18)
                HStack {
                    compositionStat("Lean mass", String(format: "%.1f kg", lean), Theme.Colors.success)
                    Spacer()
                    compositionStat("Fat mass", String(format: "%.1f kg", weight - lean), Theme.Colors.accentAmber)
                    Spacer()
                    compositionStat("BMI", String(format: "%.1f", bmi), Theme.Colors.textPrimary,
                                    detail: NutritionEngine.bmiCategory(bmi).rawValue)
                }
                Text("BMI doesn't distinguish muscle from fat and is a population screening tool, not a diagnosis.")
                    .font(.caption2).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private func compositionStat(_ title: String, _ value: String, _ color: Color, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.Typography.metricSmall).foregroundStyle(color)
            Text(detail ?? title).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var weighInList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Weigh-ins")
            ForEach(weights.prefix(10)) { w in
                ThermoCard(padding: Theme.Spacing.sm) {
                    HStack {
                        Text(w.recordedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                        Spacer()
                        if let bf = w.bodyFatPercent {
                            Text(String(format: "%.1f%%", bf)).font(.caption).foregroundStyle(Theme.Colors.textTertiary)
                        }
                        Text(String(format: "%.1f kg", w.weightKg)).font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) { vm.delete(w, in: context) }
                }
            }
        }
    }
}

private struct WeighInSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: ProgressViewModel
    let exportToHealth: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.lg) {
                ThermoCard {
                    VStack {
                        NumericField(title: "Weight", value: $vm.newWeight, unit: "kg")
                        Divider().overlay(Theme.Colors.stroke)
                        NumericField(title: "Body fat (optional)",
                                     value: Binding(get: { vm.newBodyFat ?? 0 }, set: { vm.newBodyFat = $0 > 0 ? $0 : nil }),
                                     unit: "%")
                    }
                }
                if let error = vm.errorMessage { ErrorBanner(message: error) }
                Button("Save weigh-in") {
                    vm.errorMessage = nil
                    vm.logWeight(in: context, exportToHealth: exportToHealth)
                    if vm.errorMessage == nil { dismiss() }
                }
                .buttonStyle(.thermoPrimary)
                Spacer()
            }
            .padding(Theme.Spacing.md)
            .navigationTitle("Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
