//
//  DashboardViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Derives everything the dashboard shows from profile + entries:
//           targets, today's intake, TEF, remaining budget, streak, insights.
//  Dependencies: ViewModels/MetricsCalculator.swift, Services/HealthKitService.swift
//

import Foundation
import Observation

@MainActor
@Observable
final class DashboardViewModel {
    struct Snapshot: Equatable {
        var metabolic: MetabolicProfile?
        var today: DailyTotals
        var tef: TEFBreakdown
        var streak: Int
        var weekly: [DailyTotals]
        var currentWeightKg: Double?
    }

    private(set) var snapshot: Snapshot?
    private(set) var activeEnergyToday: Double = 0
    private let health: any HealthServicing

    init(health: any HealthServicing) { self.health = health }

    func refresh(profile: UserProfile, entries: [FoodEntry], weights: [WeightEntry], now: Date = .now) {
        let calendar = Calendar.current
        let start = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        let daily = NutritionAnalytics.dailyTotals(MetricsCalculator.intakeSamples(entries), from: start, to: now)
        let today = daily.last ?? DailyTotals(day: calendar.startOfDay(for: now))
        snapshot = Snapshot(
            metabolic: MetricsCalculator.metabolicProfile(profile: profile, weights: weights),
            today: today,
            tef: today.tef,
            streak: NutritionAnalytics.loggingStreak(daily, today: now),
            weekly: Array(daily.suffix(7)),
            currentWeightKg: MetricsCalculator.currentWeightKg(weights)
        )
    }

    func loadActiveEnergy(enabled: Bool) async {
        guard enabled, health.isAvailable else { activeEnergyToday = 0; return }
        activeEnergyToday = (try? await health.activeEnergyKcal(on: .now)) ?? 0
    }

    /// Short, rule-based insight (no AI call needed).
    var insight: String? {
        guard let s = snapshot, let m = s.metabolic else { return nil }
        let proteinRatio = m.macros.proteinG > 0 ? s.today.proteinG / m.macros.proteinG : 0
        let hour = Calendar.current.component(.hour, from: .now)
        if s.today.calories == 0 { return "Log your first meal to start today's metabolic picture." }
        if s.today.calories > m.targetCalories * 1.1 { return "You're above today's target. A walk adds active energy and lifts TDEE." }
        if hour >= 15 && proteinRatio < 0.5 {
            return "Protein is at \(Int(proteinRatio * 100))% of target. Protein has the highest thermic effect (~25%)."
        }
        if s.streak >= 3 { return "\(s.streak)-day logging streak. Consistency is the strongest predictor of results." }
        return "TEF so far: \(Int(s.tef.total)) kcal burned digesting today's food."
    }
}
