//
//  MetabolicCalculatorView.swift
//  THERMOAI — Views/Calculator
//
//  Purpose: Interactive "what-if" calculator comparing all three BMR equations,
//           TDEE by activity, TEF for a sample macro intake, goal targets, and
//           a plain-language explanation of formulas and limitations.
//           Independent of saved data (pure engine usage).
//  Dependencies: SwiftUI, Charts, Core/Calculation/NutritionEngine.swift
//

import SwiftUI
import Charts

struct MetabolicCalculatorView: View {
    @State private var sex: BiologicalSex = .male
    @State private var age: Double = 30
    @State private var height: Double = 178
    @State private var weight: Double = 80
    @State private var bodyFat: Double = 20
    @State private var useBodyFat = true
    @State private var activity: ActivityLevel = .moderate
    @State private var goal: WeightGoal = .lose
    @State private var rate: Double = 0.5

    private var input: MetabolicInput? {
        try? MetabolicInput(weightKg: weight, heightCm: height, ageYears: Int(age), sex: sex,
                            bodyFatPercent: useBodyFat ? bodyFat : nil, activity: activity)
    }

    private struct FormulaResult: Identifiable { let id: BMRFormula; let value: Double }

    private var comparisons: [FormulaResult] {
        guard let input else { return [] }
        var list = [FormulaResult(id: .mifflinStJeor, value: NutritionEngine.mifflinStJeor(input)),
                    FormulaResult(id: .harrisBenedictRevised, value: NutritionEngine.harrisBenedictRevised(input))]
        if let k = try? NutritionEngine.katchMcArdle(input) { list.append(FormulaResult(id: .katchMcArdle, value: k)) }
        return list
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                inputsCard
                if let input {
                    bmrComparison
                    resultCard(input)
                    tefCard(input)
                } else {
                    ErrorBanner(message: "Adjust inputs: adults 18–100, height 50–272 cm, weight 20–400 kg.")
                }
                methodology
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .thermoScreen()
        .navigationTitle("Calculator")
    }

    private var inputsCard: some View {
        ThermoCard {
            VStack(spacing: Theme.Spacing.sm) {
                Picker("Sex", selection: $sex) { ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                slider("Age", $age, 18...100, "yr", 0)
                slider("Height", $height, 120...220, "cm", 0)
                slider("Weight", $weight, 35...250, "kg", 1)
                Toggle("Body fat known", isOn: $useBodyFat).foregroundStyle(Theme.Colors.textSecondary)
                if useBodyFat { slider("Body fat", $bodyFat, 3...60, "%", 0) }
                Picker("Activity", selection: $activity) {
                    ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
                }
                .foregroundStyle(Theme.Colors.textSecondary)
                Picker("Goal", selection: $goal) { ForEach(WeightGoal.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.segmented)
                if goal != .maintain { slider("Rate", $rate, 0.1...1.0, "kg/wk", 2) }
            }
        }
    }

    private func slider(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ unit: String, _ digits: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text("\(value.wrappedValue, specifier: "%.\(digits)f") \(unit)")
                    .font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
            }
            Slider(value: value, in: range, step: digits == 0 ? 1 : pow(10, -Double(digits)))
        }
    }

    private var bmrComparison: some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "BMR by equation", subtitle: "kcal/day at complete rest")
                Chart(comparisons) { r in
                    BarMark(x: .value("kcal", r.value), y: .value("Formula", r.id.title))
                        .foregroundStyle(Theme.Gradients.heat)
                        .cornerRadius(6)
                        .annotation(position: .trailing) {
                            Text("\(Int(r.value))").font(.caption.monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
                        }
                }
                .chartXAxis(.hidden)
                .chartYAxis { AxisMarks { _ in AxisValueLabel().foregroundStyle(Theme.Colors.textSecondary) } }
                .frame(height: CGFloat(comparisons.count) * 52)
            }
        }
    }

    private func resultCard(_ input: MetabolicInput) -> some View {
        let formula: BMRFormula = useBodyFat ? .katchMcArdle : .mifflinStJeor
        let p = NutritionEngine.profile(for: input, formula: formula, goal: goal, rateKgPerWeek: rate)
        return GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(Int(p.targetCalories))").font(Theme.Typography.hero).foregroundStyle(Theme.Colors.textPrimary)
                        .contentTransition(.numericText(value: p.targetCalories))
                    Text("kcal/day target").foregroundStyle(Theme.Colors.textSecondary)
                }
                if p.wasClampedToSafetyFloor {
                    Label("Raised to the \(Int(NutritionEngine.safetyFloor(for: sex))) kcal safety minimum.", systemImage: "shield.lefthalf.filled")
                        .font(.caption).foregroundStyle(Theme.Colors.warning)
                }
                Grid(alignment: .leading, horizontalSpacing: Theme.Spacing.lg, verticalSpacing: 6) {
                    row("BMR (\(p.formula.title))", "\(Int(p.bmr)) kcal")
                    row("TDEE (×\(String(format: "%.3g", activity.multiplier)))", "\(Int(p.tdee)) kcal")
                    row(p.dailyEnergyDelta <= 0 ? "Daily deficit" : "Daily surplus", "\(Int(abs(p.dailyEnergyDelta))) kcal")
                    row("Protein / Carbs / Fat", "\(Int(p.macros.proteinG)) / \(Int(p.macros.carbsG)) / \(Int(p.macros.fatG)) g")
                    row("BMI", String(format: "%.1f · %@", p.bmi, p.bmiCategory.rawValue))
                    row("Lean body mass", String(format: "%.1f kg%@", p.leanBodyMassKg, p.leanMassIsEstimated ? " (est.)" : ""))
                }
            }
        }
    }

    private func tefCard(_ input: MetabolicInput) -> some View {
        let p = NutritionEngine.profile(for: input, formula: .mifflinStJeor, goal: goal, rateKgPerWeek: rate)
        let tef = NutritionEngine.thermicEffect(proteinG: p.macros.proteinG, carbsG: p.macros.carbsG, fatG: p.macros.fatG)
        return ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: "Thermic effect of food", subtitle: "If you eat exactly your macro targets")
                EnergyStackBar(segments: [
                    .init(label: "Protein", value: tef.protein, color: Theme.Colors.protein),
                    .init(label: "Carbs", value: tef.carbohydrate, color: Theme.Colors.carbs),
                    .init(label: "Fat", value: tef.fat, color: Theme.Colors.fat),
                ])
                Text("≈ \(Int(tef.total)) kcal (\(Int(tef.total / max(p.targetCalories, 1) * 100))% of intake) spent digesting food.")
                    .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private var methodology: some View {
        ThermoCard {
            DisclosureGroup("Formulas & limitations") {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Mifflin-St Jeor: 10W + 6.25H − 5A + 5 (men) / −161 (women)")
                    Text("Harris-Benedict (1984): 88.362 + 13.397W + 4.799H − 5.677A (men); 447.593 + 9.247W + 3.098H − 4.330A (women)")
                    Text("Katch-McArdle: 370 + 21.6 × lean body mass")
                    Text("TDEE = BMR × activity factor (1.2–1.9). Activity factors already include average TEF, so TEF is shown for insight and not added again.")
                    Text("TEF: protein 25%, carbohydrate 7.5%, fat 2% of their energy.")
                    Text("1 kg body-mass change ≈ 7,700 kcal. Real change slows as metabolism adapts.")
                    Text("Equations estimate population averages (±10% typical error). Not validated for pregnancy, under-18s or medical conditions. Not medical advice.")
                        .foregroundStyle(Theme.Colors.warning)
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, Theme.Spacing.xs)
            }
            .tint(Theme.Colors.accent)
            .foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
            Text(value).font(Theme.Typography.callout.monospacedDigit().weight(.semibold)).foregroundStyle(Theme.Colors.textPrimary)
        }
    }
}
