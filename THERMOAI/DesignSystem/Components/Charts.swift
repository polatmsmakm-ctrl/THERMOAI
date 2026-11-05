//
//  Charts.swift
//  THERMOAI — DesignSystem/Components
//
//  Purpose: Interactive Swift Charts used across Dashboard and Progress:
//    • CalorieHistoryChart — bars vs target rule, scrub to inspect a day
//    • WeightTrendChart    — raw weigh-ins + smoothed trend line, scrub to inspect
//    • MacroDonutChart     — energy share of protein / carbs / fat
//  Dependencies: SwiftUI, Charts, DesignSystem/Theme.swift, Core/Analytics
//

import SwiftUI
import Charts

// MARK: - Calorie history

struct CalorieHistoryChart: View {
    let days: [DailyTotals]
    let target: Double
    var height: CGFloat = 200

    @State private var selectedDate: Date?

    private var selected: DailyTotals? {
        guard let selectedDate else { return nil }
        return days.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDate) }
    }

    var body: some View {
        Chart {
            ForEach(days) { day in
                BarMark(x: .value("Day", day.day, unit: .day), y: .value("Calories", day.calories))
                    .foregroundStyle(day.calories > target * 1.05 ? AnyShapeStyle(Theme.Colors.danger.gradient)
                                                                   : AnyShapeStyle(Theme.Gradients.heat))
                    .cornerRadius(5)
                    .opacity(selected == nil || selected?.day == day.day ? 1 : 0.35)
            }
            if target > 0 {
                RuleMark(y: .value("Target", target))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("Target \(Int(target))").font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                    }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.day, unit: .day))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: selected.day.formatted(.dateTime.weekday(.abbreviated).day().month()),
                                     value: "\(Int(selected.calories)) kcal",
                                     detail: "P \(Int(selected.proteinG)) · C \(Int(selected.carbsG)) · F \(Int(selected.fatG))")
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: days.count > 14 ? 7 : 1)) { _ in
                AxisValueLabel(format: days.count > 14 ? .dateTime.day().month(.abbreviated) : .dateTime.weekday(.narrow))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.Colors.stroke)
                AxisValueLabel().foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(height: height)
        .sensoryFeedback(.selection, trigger: selectedDate)
        .accessibilityLabel("Daily calories chart")
    }
}

// MARK: - Weight trend

struct WeightTrendChart: View {
    let points: [TrendPoint]
    var goalKg: Double?
    var height: CGFloat = 220

    @State private var selectedDate: Date?

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        return points.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var yDomain: ClosedRange<Double> {
        let values = points.flatMap { [$0.raw, $0.trend] } + (goalKg.map { [$0] } ?? [])
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        return (lo - 1.5)...(hi + 1.5)
    }

    var body: some View {
        Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", yDomain.lowerBound), yEnd: .value("Trend", p.trend))
                    .foregroundStyle(LinearGradient(colors: [Theme.Colors.accent.opacity(0.28), .clear],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Date", p.date), y: .value("Trend", p.trend))
                    .foregroundStyle(Theme.Gradients.heat)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", p.date), y: .value("Weight", p.raw))
                    .foregroundStyle(Theme.Colors.textSecondary.opacity(0.6))
                    .symbolSize(18)
            }
            if let goalKg {
                RuleMark(y: .value("Goal", goalKg))
                    .foregroundStyle(Theme.Colors.success.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .bottom, alignment: .trailing) {
                        Text("Goal").font(.caption2).foregroundStyle(Theme.Colors.success)
                    }
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.date))
                    .foregroundStyle(Theme.Colors.textTertiary.opacity(0.4))
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        ChartTooltip(title: selected.date.formatted(date: .abbreviated, time: .omitted),
                                     value: String(format: "%.1f kg", selected.raw),
                                     detail: String(format: "Trend %.1f kg", selected.trend))
                    }
            }
        }
        .chartYScale(domain: yDomain)
        .chartXSelection(value: $selectedDate)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated)).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Theme.Colors.stroke)
                AxisValueLabel().foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .frame(height: height)
        .accessibilityLabel("Weight trend chart")
    }
}

// MARK: - Macro donut

struct MacroDonutChart: View {
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    private struct Slice: Identifiable { let id: String; let kcal: Double; let color: Color }

    private var slices: [Slice] {
        [Slice(id: "Protein", kcal: proteinG * 4, color: Theme.Colors.protein),
         Slice(id: "Carbs", kcal: carbsG * 4, color: Theme.Colors.carbs),
         Slice(id: "Fat", kcal: fatG * 9, color: Theme.Colors.fat)]
    }

    private var total: Double { slices.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        Chart(slices) { s in
            SectorMark(angle: .value("kcal", max(s.kcal, total == 0 ? 1 : 0)),
                       innerRadius: .ratio(0.68), angularInset: 2)
                .foregroundStyle(total == 0 ? Theme.Colors.surfaceHighlight : s.color)
                .cornerRadius(4)
        }
        .chartBackground { _ in
            VStack(spacing: 0) {
                Text(total == 0 ? "—" : "\(Int(proteinG * 4 / max(total, 1) * 100))%")
                    .font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                Text("protein").font(.caption2).foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityLabel("Macronutrient energy split")
    }
}

// MARK: - Tooltip

struct ChartTooltip: View {
    let title: String
    let value: String
    var detail: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
            Text(value).font(.caption.weight(.bold).monospacedDigit()).foregroundStyle(Theme.Colors.textPrimary)
            if let detail { Text(detail).font(.caption2).foregroundStyle(Theme.Colors.textTertiary) }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(.ultraThinMaterial))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.Colors.stroke))
    }
}
