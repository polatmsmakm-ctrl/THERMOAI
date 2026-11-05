//
//  NutritionAnalytics.swift
//  THERMOAI — Core/Analytics
//
//  Purpose: Pure analytics over logged data — daily totals, streaks, weight
//           trend smoothing and adaptive (observed) TDEE. No SwiftData/UI imports,
//           so it is unit-testable with plain value types.
//  Dependencies: Foundation, Core/Calculation/NutritionEngine.swift
//

import Foundation

/// Value snapshot of a food entry (decouples analytics from SwiftData).
struct IntakeSample: Sendable, Equatable {
    let date: Date
    let calories: Double
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
}

struct WeightSample: Sendable, Equatable {
    let date: Date
    let weightKg: Double
}

struct DailyTotals: Sendable, Equatable, Identifiable {
    var id: Date { day }
    let day: Date
    var calories: Double = 0
    var proteinG: Double = 0
    var carbsG: Double = 0
    var fatG: Double = 0

    var tef: TEFBreakdown { NutritionEngine.thermicEffect(proteinG: proteinG, carbsG: carbsG, fatG: fatG) }
}

struct TrendPoint: Sendable, Equatable, Identifiable {
    var id: Date { date }
    let date: Date
    let raw: Double
    let trend: Double
}

enum NutritionAnalytics {

    /// Sums samples into one `DailyTotals` per calendar day, including empty days in range.
    static func dailyTotals(_ samples: [IntakeSample], from start: Date, to end: Date,
                            calendar: Calendar = .current) -> [DailyTotals] {
        let startDay = calendar.startOfDay(for: start)
        let endDay = calendar.startOfDay(for: end)
        var buckets: [Date: DailyTotals] = [:]
        var day = startDay
        while day <= endDay {
            buckets[day] = DailyTotals(day: day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        for s in samples {
            let key = calendar.startOfDay(for: s.date)
            guard var bucket = buckets[key] else { continue }
            bucket.calories += s.calories
            bucket.proteinG += s.proteinG
            bucket.carbsG += s.carbsG
            bucket.fatG += s.fatG
            buckets[key] = bucket
        }
        return buckets.values.sorted { $0.day < $1.day }
    }

    /// Average of days that have any logged intake (unlogged days are excluded, not zeros).
    static func averageLoggedCalories(_ totals: [DailyTotals]) -> Double? {
        let logged = totals.filter { $0.calories > 0 }
        guard !logged.isEmpty else { return nil }
        return logged.reduce(0) { $0 + $1.calories } / Double(logged.count)
    }

    /// Consecutive days up to and including `today` with at least one entry.
    static func loggingStreak(_ totals: [DailyTotals], today: Date = .now, calendar: Calendar = .current) -> Int {
        let byDay = Dictionary(uniqueKeysWithValues: totals.map { ($0.day, $0.calories) })
        var streak = 0
        var day = calendar.startOfDay(for: today)
        // Today not yet logged doesn't break a streak.
        if (byDay[day] ?? 0) == 0 { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        while (byDay[day] ?? 0) > 0 {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    /// Exponentially smoothed weight trend (α = 0.1, Hacker's Diet style) that
    /// filters day-to-day water fluctuations.
    static func weightTrend(_ samples: [WeightSample], alpha: Double = 0.1) -> [TrendPoint] {
        let sorted = samples.sorted { $0.date < $1.date }
        guard let first = sorted.first else { return [] }
        var trend = first.weightKg
        return sorted.map { s in
            trend += alpha * (s.weightKg - trend)
            return TrendPoint(date: s.date, raw: s.weightKg, trend: trend)
        }
    }

    /// Weekly rate of change of the trend line (kg/week) via least squares.
    static func weeklyRate(_ trend: [TrendPoint]) -> Double? {
        guard trend.count >= 2, let t0 = trend.first?.date else { return nil }
        let xs = trend.map { $0.date.timeIntervalSince(t0) / 86_400 }
        let ys = trend.map(\.trend)
        let n = Double(xs.count)
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
        let den = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard den > 0 else { return nil }
        return num / den * 7
    }

    /// Observed TDEE from energy balance:
    ///   TDEE ≈ mean intake − (Δtrend weight × 7700 kcal) / days
    /// Requires ≥ 14 days span and ≥ 10 logged days for a meaningful estimate.
    static func adaptiveTDEE(intake: [DailyTotals], trend: [TrendPoint]) -> Double? {
        guard let first = trend.first, let last = trend.last else { return nil }
        let days = last.date.timeIntervalSince(first.date) / 86_400
        let logged = intake.filter { $0.calories > 0 && $0.day >= first.date && $0.day <= last.date }
        guard days >= 14, logged.count >= 10 else { return nil }
        let meanIntake = logged.reduce(0) { $0 + $1.calories } / Double(logged.count)
        let deltaKg = last.trend - first.trend
        return meanIntake - deltaKg * NutritionEngine.kcalPerKgBodyMass / days
    }
}
