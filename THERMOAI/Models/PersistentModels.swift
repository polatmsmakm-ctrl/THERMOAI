//
//  PersistentModels.swift
//  THERMOAI — Models
//
//  Purpose: SwiftData models (local source of truth, offline-first).
//           Each syncable model carries `id` (shared with Postgres), `updatedAt`,
//           `needsSync` and `isSoftDeleted` (soft delete) for SyncService.
//           NOTE: `isDeleted` is avoided because PersistentModel already defines it.
//  Dependencies: SwiftData, Models/Enums.swift, Core/Calculation/NutritionEngine.swift
//

import Foundation
import SwiftData

// MARK: - UserProfile

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var sexRaw: String
    var birthDate: Date
    var heightCm: Double
    var activityRaw: String
    var goalRaw: String
    var goalRateKgPerWeek: Double
    var targetWeightKg: Double?
    var bodyFatPercent: Double?
    var formulaRaw: String
    var useMetricUnits: Bool
    var healthKitEnabled: Bool
    var onboardingCompleted: Bool
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(),
         displayName: String = "",
         sex: BiologicalSex = .female,
         birthDate: Date = Calendar.current.date(byAdding: .year, value: -30, to: .now) ?? .now,
         heightCm: Double = 170,
         activity: ActivityLevel = .light,
         goal: WeightGoal = .maintain,
         goalRateKgPerWeek: Double = 0.5,
         targetWeightKg: Double? = nil,
         bodyFatPercent: Double? = nil,
         formula: BMRFormula = .mifflinStJeor,
         useMetricUnits: Bool = true) {
        self.id = id
        self.displayName = displayName
        self.sexRaw = sex.rawValue
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.activityRaw = activity.rawValue
        self.goalRaw = goal.rawValue
        self.goalRateKgPerWeek = goalRateKgPerWeek
        self.targetWeightKg = targetWeightKg
        self.bodyFatPercent = bodyFatPercent
        self.formulaRaw = formula.rawValue
        self.useMetricUnits = useMetricUnits
        self.healthKitEnabled = false
        self.onboardingCompleted = false
        self.updatedAt = .now
        self.needsSync = true
    }

    // Typed accessors (SwiftData stores raw strings for schema stability).
    var sex: BiologicalSex {
        get { BiologicalSex(rawValue: sexRaw) ?? .female }
        set { sexRaw = newValue.rawValue }
    }
    var activity: ActivityLevel {
        get { ActivityLevel(rawValue: activityRaw) ?? .sedentary }
        set { activityRaw = newValue.rawValue }
    }
    var goal: WeightGoal {
        get { WeightGoal(rawValue: goalRaw) ?? .maintain }
        set { goalRaw = newValue.rawValue }
    }
    var formula: BMRFormula {
        get { BMRFormula(rawValue: formulaRaw) ?? .mifflinStJeor }
        set { formulaRaw = newValue.rawValue }
    }

    var ageYears: Int {
        Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 30
    }

    /// Marks the profile dirty for sync after any edit.
    func touch() {
        updatedAt = .now
        needsSync = true
    }

    /// Builds a validated engine input; nil if any value is out of range.
    func metabolicInput(currentWeightKg: Double) -> MetabolicInput? {
        try? MetabolicInput(weightKg: currentWeightKg, heightCm: heightCm, ageYears: ageYears,
                            sex: sex, bodyFatPercent: bodyFatPercent, activity: activity)
    }
}

// MARK: - FoodEntry

@Model
final class FoodEntry {
    @Attribute(.unique) var id: UUID
    var consumedAt: Date
    var mealTypeRaw: String
    var name: String
    var servingDescription: String
    var grams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var sourceRaw: String
    var aiConfidence: Double?
    /// Soft-delete flag. Named `isSoftDeleted` because `PersistentModel` already
    /// declares `isDeleted` (context deletion state).
    var isSoftDeleted: Bool
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), consumedAt: Date = .now, mealType: MealType, name: String,
         servingDescription: String = "", grams: Double = 0, calories: Double,
         proteinG: Double, carbsG: Double, fatG: Double, fiberG: Double = 0,
         source: EntrySource = .manual, aiConfidence: Double? = nil) {
        self.id = id
        self.consumedAt = consumedAt
        self.mealTypeRaw = mealType.rawValue
        self.name = name
        self.servingDescription = servingDescription
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.sourceRaw = source.rawValue
        self.aiConfidence = aiConfidence
        self.isSoftDeleted = false
        self.updatedAt = .now
        self.needsSync = true
    }

    var mealType: MealType {
        get { MealType(rawValue: mealTypeRaw) ?? .snack }
        set { mealTypeRaw = newValue.rawValue }
    }
    var source: EntrySource { EntrySource(rawValue: sourceRaw) ?? .manual }

    func touch() { updatedAt = .now; needsSync = true }

    func softDelete() { isSoftDeleted = true; touch() }
}

// MARK: - WeightEntry

@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var weightKg: Double
    var bodyFatPercent: Double?
    var isSoftDeleted: Bool
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), recordedAt: Date = .now, weightKg: Double, bodyFatPercent: Double? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.weightKg = weightKg
        self.bodyFatPercent = bodyFatPercent
        self.isSoftDeleted = false
        self.updatedAt = .now
        self.needsSync = true
    }

    func touch() { updatedAt = .now; needsSync = true }
    func softDelete() { isSoftDeleted = true; touch() }
}

// MARK: - SavedMealPlan

@Model
final class SavedMealPlan {
    @Attribute(.unique) var id: UUID
    var title: String
    var targetCalories: Double
    var planData: Data            // JSON-encoded MealPlanResponse
    var createdAt: Date
    var isSoftDeleted: Bool
    var updatedAt: Date
    var needsSync: Bool

    init(id: UUID = UUID(), title: String, targetCalories: Double, plan: MealPlanResponse) throws {
        self.id = id
        self.title = title
        self.targetCalories = targetCalories
        self.planData = try JSONEncoder().encode(plan)
        self.createdAt = .now
        self.isSoftDeleted = false
        self.updatedAt = .now
        self.needsSync = true
    }

    var plan: MealPlanResponse? { try? JSONDecoder().decode(MealPlanResponse.self, from: planData) }

    func touch() { updatedAt = .now; needsSync = true }
    func softDelete() { isSoftDeleted = true; touch() }
}

// MARK: - Schema

enum ThermoSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, FoodEntry.self, WeightEntry.self, SavedMealPlan.self
    ]

    @MainActor
    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
