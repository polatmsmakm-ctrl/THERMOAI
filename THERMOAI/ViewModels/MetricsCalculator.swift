//
//  MetricsCalculator.swift
//  THERMOAI — ViewModels
//
//  Purpose: Bridges SwiftData models to the pure engine/analytics layer.
//           Shared by Dashboard, Progress, Assistant and Meal Plan view models.
//  Dependencies: Models/PersistentModels.swift, Core/Calculation, Core/Analytics
//

import Foundation

@MainActor
enum MetricsCalculator {

    /// Most recent non-deleted weight.
    static func currentWeightKg(_ weights: [WeightEntry]) -> Double? {
        weights.filter { !$0.isSoftDeleted }.max { $0.recordedAt < $1.recordedAt }?.weightKg
    }

    /// Body fat: latest weigh-in value, else profile value.
    static func currentBodyFat(profile: UserProfile, weights: [WeightEntry]) -> Double? {
        weights.filter { !$0.isSoftDeleted && $0.bodyFatPercent != nil }
            .max { $0.recordedAt < $1.recordedAt }?.bodyFatPercent ?? profile.bodyFatPercent
    }

    static func metabolicProfile(profile: UserProfile, weights: [WeightEntry]) -> MetabolicProfile? {
        guard let weight = currentWeightKg(weights),
              let input = try? MetabolicInput(weightKg: weight, heightCm: profile.heightCm, ageYears: profile.ageYears,
                                              sex: profile.sex,
                                              bodyFatPercent: currentBodyFat(profile: profile, weights: weights),
                                              activity: profile.activity)
        else { return nil }
        return NutritionEngine.profile(for: input, formula: profile.formula, goal: profile.goal,
                                       rateKgPerWeek: profile.goalRateKgPerWeek)
    }

    static func intakeSamples(_ entries: [FoodEntry]) -> [IntakeSample] {
        entries.filter { !$0.isSoftDeleted }.map {
            IntakeSample(date: $0.consumedAt, calories: $0.calories, proteinG: $0.proteinG, carbsG: $0.carbsG, fatG: $0.fatG)
        }
    }

    static func weightSamples(_ weights: [WeightEntry]) -> [WeightSample] {
        weights.filter { !$0.isSoftDeleted }.map { WeightSample(date: $0.recordedAt, weightKg: $0.weightKg) }
    }

    static func totals(for day: Date, entries: [FoodEntry], calendar: Calendar = .current) -> DailyTotals {
        NutritionAnalytics.dailyTotals(intakeSamples(entries), from: day, to: day, calendar: calendar).first
            ?? DailyTotals(day: calendar.startOfDay(for: day))
    }

    static func nutritionContext(profile: UserProfile, weights: [WeightEntry], entries: [FoodEntry]) -> NutritionContext {
        let metabolic = metabolicProfile(profile: profile, weights: weights)
        let today = totals(for: .now, entries: entries)
        return NutritionContext(targetCalories: metabolic?.targetCalories ?? 2000,
                                consumedCalories: today.calories,
                                proteinTargetG: metabolic?.macros.proteinG ?? 0,
                                carbsTargetG: metabolic?.macros.carbsG ?? 0,
                                fatTargetG: metabolic?.macros.fatG ?? 0,
                                goal: profile.goal.rawValue)
    }
}
