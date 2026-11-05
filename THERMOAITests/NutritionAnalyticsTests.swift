//
//  NutritionAnalyticsTests.swift
//  THERMOAITests
//
//  Purpose: Tests daily bucketing, streaks, weight smoothing and adaptive TDEE.
//  Dependencies: Swift Testing, @testable THERMOAI
//

import Foundation
import Testing
@testable import THERMOAI

@Suite("NutritionAnalytics")
struct NutritionAnalyticsTests {
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func day(_ offset: Int, hour: Int = 12) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: hour))!
        return calendar.date(byAdding: .day, value: offset, to: base)!
    }

    @Test func bucketsByDayIncludingEmptyDays() {
        let samples = [
            IntakeSample(date: day(0, hour: 8), calories: 500, proteinG: 30, carbsG: 50, fatG: 20),
            IntakeSample(date: day(0, hour: 19), calories: 700, proteinG: 40, carbsG: 60, fatG: 30),
            IntakeSample(date: day(2), calories: 1000, proteinG: 50, carbsG: 100, fatG: 40),
        ]
        let totals = NutritionAnalytics.dailyTotals(samples, from: day(0), to: day(2), calendar: calendar)
        #expect(totals.count == 3)
        #expect(totals[0].calories == 1200)
        #expect(totals[0].proteinG == 70)
        #expect(totals[1].calories == 0)
        #expect(totals[2].calories == 1000)
    }

    @Test func averageIgnoresUnloggedDays() {
        let totals = [DailyTotals(day: day(0), calories: 2000), DailyTotals(day: day(1)), DailyTotals(day: day(2), calories: 1000)]
        #expect(NutritionAnalytics.averageLoggedCalories(totals) == 1500)
        #expect(NutritionAnalytics.averageLoggedCalories([]) == nil)
    }

    @Test func streakCountsConsecutiveDays() {
        let totals = (0..<5).map { i in
            DailyTotals(day: calendar.startOfDay(for: day(i)), calories: i == 1 ? 0 : 1500)
        }
        // Days 2,3,4 logged; day 1 empty → streak 3 as of day 4.
        #expect(NutritionAnalytics.loggingStreak(totals, today: day(4), calendar: calendar) == 3)
    }

    @Test func streakNotBrokenByUnloggedToday() {
        let totals = [DailyTotals(day: calendar.startOfDay(for: day(0)), calories: 1800),
                      DailyTotals(day: calendar.startOfDay(for: day(1)), calories: 0)]
        #expect(NutritionAnalytics.loggingStreak(totals, today: day(1), calendar: calendar) == 1)
    }

    @Test func weightTrendSmoothsNoise() {
        let samples = [80.0, 81.0, 79.0, 80.5, 79.5].enumerated().map { WeightSample(date: day($0.offset), weightKg: $0.element) }
        let trend = NutritionAnalytics.weightTrend(samples)
        #expect(trend.count == 5)
        #expect(trend.first?.trend == 80)
        let spread = (trend.map(\.trend).max() ?? 0) - (trend.map(\.trend).min() ?? 0)
        #expect(spread < 0.5)
    }

    @Test func weeklyRateOfLinearLoss() {
        // 0.1 kg/day down = −0.7 kg/week.
        let points = (0..<21).map { TrendPoint(date: day($0), raw: 80 - Double($0) * 0.1, trend: 80 - Double($0) * 0.1) }
        let rate = NutritionAnalytics.weeklyRate(points)
        #expect(rate != nil)
        #expect(abs((rate ?? 0) + 0.7) < 0.0001)
    }

    @Test func adaptiveTDEEStableWeightEqualsIntake() {
        let intake = (0..<20).map { DailyTotals(day: calendar.startOfDay(for: day($0)), calories: 2500) }
        let trend = (0..<20).map { TrendPoint(date: calendar.startOfDay(for: day($0)), raw: 80, trend: 80) }
        let tdee = NutritionAnalytics.adaptiveTDEE(intake: intake, trend: trend)
        #expect(tdee != nil)
        #expect(abs((tdee ?? 0) - 2500) < 0.001)
    }

    @Test func adaptiveTDEERequiresEnoughData() {
        let intake = (0..<5).map { DailyTotals(day: day($0), calories: 2000) }
        let trend = (0..<5).map { TrendPoint(date: day($0), raw: 80, trend: 80) }
        #expect(NutritionAnalytics.adaptiveTDEE(intake: intake, trend: trend) == nil)
    }
}
