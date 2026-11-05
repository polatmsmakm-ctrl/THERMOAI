//
//  ProgressViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Health analytics — calorie history vs target, weight trend,
//           weekly rate, adaptive TDEE, body composition, weigh-in logging.
//  Dependencies: SwiftData, Core/Analytics, ViewModels/MetricsCalculator.swift
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ProgressViewModel {
    enum Range: String, CaseIterable, Identifiable {
        case week = "1W", month = "1M", quarter = "3M", year = "1Y"
        var id: String { rawValue }
        var days: Int {
            switch self { case .week: 7; case .month: 30; case .quarter: 90; case .year: 365 }
        }
    }

    struct Analytics: Equatable {
        var intake: [DailyTotals]
        var trend: [TrendPoint]
        var averageCalories: Double?
        var weeklyRateKg: Double?
        var adaptiveTDEE: Double?
        var estimatedTDEE: Double?
    }

    var range: Range = .month
    private(set) var analytics: Analytics?
    var newWeight: Double = 0
    var newBodyFat: Double? = nil
    var errorMessage: String?

    private let health: any HealthServicing

    init(health: any HealthServicing) { self.health = health }

    func refresh(profile: UserProfile, entries: [FoodEntry], weights: [WeightEntry], now: Date = .now) {
        let start = Calendar.current.date(byAdding: .day, value: -(range.days - 1), to: Calendar.current.startOfDay(for: now))!
        let intake = NutritionAnalytics.dailyTotals(MetricsCalculator.intakeSamples(entries), from: start, to: now)
        let samples = MetricsCalculator.weightSamples(weights).filter { $0.date >= start }
        let trend = NutritionAnalytics.weightTrend(samples)
        analytics = Analytics(
            intake: intake,
            trend: trend,
            averageCalories: NutritionAnalytics.averageLoggedCalories(intake),
            weeklyRateKg: NutritionAnalytics.weeklyRate(trend),
            adaptiveTDEE: NutritionAnalytics.adaptiveTDEE(intake: intake, trend: trend),
            estimatedTDEE: MetricsCalculator.metabolicProfile(profile: profile, weights: weights)?.tdee
        )
        if newWeight == 0 { newWeight = MetricsCalculator.currentWeightKg(weights) ?? 70 }
    }

    func logWeight(in context: ModelContext, exportToHealth: Bool) {
        guard (20...400).contains(newWeight) else { errorMessage = "Enter a weight between 20 and 400 kg."; return }
        if let bf = newBodyFat, !(2...70).contains(bf) { errorMessage = "Body fat must be 2–70%."; return }
        let entry = WeightEntry(weightKg: newWeight, bodyFatPercent: newBodyFat)
        context.insert(entry)
        do { try context.save() } catch { errorMessage = error.localizedDescription; return }
        if exportToHealth {
            let kg = newWeight
            let health = self.health
            Task { try? await health.saveBodyMass(kg: kg, date: .now) }
        }
        newBodyFat = nil
    }

    func delete(_ entry: WeightEntry, in context: ModelContext) {
        entry.softDelete()
        try? context.save()
    }
}
