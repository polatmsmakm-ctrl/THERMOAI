//
//  SyncDTOs.swift
//  THERMOAI — Networking
//
//  Purpose: Wire formats for PostgREST tables. Column names match the SQL
//           migration exactly. Conversion to/from SwiftData models lives here
//           so models stay persistence-only.
//  Dependencies: Models/PersistentModels.swift, Models/AIModels.swift, Networking/HTTPClient.swift
//

import Foundation

// MARK: - Profile

struct ProfileRow: Codable, Sendable {
    var id: UUID
    var displayName: String
    var sex: BiologicalSex?
    var birthDate: String?          // "yyyy-MM-dd"
    var heightCm: Double?
    var activityLevel: ActivityLevel
    var goal: WeightGoal
    var goalRateKgWeek: Double
    var bodyFatPercent: Double?
    var bmrFormula: BMRFormula
    var isPro: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case sex
        case birthDate = "birth_date"
        case heightCm = "height_cm"
        case activityLevel = "activity_level"
        case goal
        case goalRateKgWeek = "goal_rate_kg_week"
        case bodyFatPercent = "body_fat_percent"
        case bmrFormula = "bmr_formula"
        case isPro = "is_pro"
    }
}

/// Only the user-writable columns (is_pro is server-managed).
struct ProfileUpdate: Encodable, Sendable {
    let displayName: String
    let sex: BiologicalSex
    let birthDate: String
    let heightCm: Double
    let activityLevel: ActivityLevel
    let goal: WeightGoal
    let goalRateKgWeek: Double
    let bodyFatPercent: Double?
    let bmrFormula: BMRFormula

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name", sex, birthDate = "birth_date", heightCm = "height_cm"
        case activityLevel = "activity_level", goal, goalRateKgWeek = "goal_rate_kg_week"
        case bodyFatPercent = "body_fat_percent", bmrFormula = "bmr_formula"
    }

    // Encode explicit nulls so clearing body fat propagates.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(displayName, forKey: .displayName)
        try c.encode(sex, forKey: .sex)
        try c.encode(birthDate, forKey: .birthDate)
        try c.encode(heightCm, forKey: .heightCm)
        try c.encode(activityLevel, forKey: .activityLevel)
        try c.encode(goal, forKey: .goal)
        try c.encode(goalRateKgWeek, forKey: .goalRateKgWeek)
        try c.encode(bodyFatPercent, forKey: .bodyFatPercent)
        try c.encode(bmrFormula, forKey: .bmrFormula)
    }
}

extension ProfileUpdate {
    @MainActor
    init(_ p: UserProfile) {
        self.init(displayName: p.displayName, sex: p.sex, birthDate: JSONCoding.dateOnlyString(p.birthDate),
                  heightCm: p.heightCm, activityLevel: p.activity, goal: p.goal,
                  goalRateKgWeek: p.goalRateKgPerWeek, bodyFatPercent: p.bodyFatPercent, bmrFormula: p.formula)
    }
}

// MARK: - Food entries

struct FoodEntryRow: Codable, Sendable {
    var id: UUID
    var userId: UUID
    var consumedAt: Date
    var mealType: MealType
    var name: String
    var servingDesc: String
    var grams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var source: EntrySource
    var aiConfidence: Double?
    var isDeleted: Bool
    var updatedAt: Date?            // server-assigned; never sent

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", consumedAt = "consumed_at", mealType = "meal_type", name
        case servingDesc = "serving_desc", grams, calories, proteinG = "protein_g", carbsG = "carbs_g"
        case fatG = "fat_g", fiberG = "fiber_g", source, aiConfidence = "ai_confidence"
        case isDeleted = "is_deleted", updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(userId, forKey: .userId)
        try c.encode(consumedAt, forKey: .consumedAt); try c.encode(mealType, forKey: .mealType)
        try c.encode(name, forKey: .name); try c.encode(servingDesc, forKey: .servingDesc)
        try c.encode(grams, forKey: .grams); try c.encode(calories, forKey: .calories)
        try c.encode(proteinG, forKey: .proteinG); try c.encode(carbsG, forKey: .carbsG)
        try c.encode(fatG, forKey: .fatG); try c.encode(fiberG, forKey: .fiberG)
        try c.encode(source, forKey: .source); try c.encode(aiConfidence, forKey: .aiConfidence)
        try c.encode(isDeleted, forKey: .isDeleted)
    }
}

extension FoodEntryRow {
    @MainActor
    init(_ e: FoodEntry, userID: UUID) {
        self.init(id: e.id, userId: userID, consumedAt: e.consumedAt, mealType: e.mealType, name: e.name,
                  servingDesc: e.servingDescription, grams: e.grams, calories: e.calories, proteinG: e.proteinG,
                  carbsG: e.carbsG, fatG: e.fatG, fiberG: e.fiberG, source: e.source,
                  aiConfidence: e.aiConfidence, isDeleted: e.isSoftDeleted, updatedAt: nil)
    }

    @MainActor
    func apply(to e: FoodEntry) {
        e.consumedAt = consumedAt; e.mealType = mealType; e.name = name; e.servingDescription = servingDesc
        e.grams = grams; e.calories = calories; e.proteinG = proteinG; e.carbsG = carbsG; e.fatG = fatG
        e.fiberG = fiberG; e.sourceRaw = source.rawValue; e.aiConfidence = aiConfidence
        e.isSoftDeleted = isDeleted; e.updatedAt = updatedAt ?? .now; e.needsSync = false
    }
}

// MARK: - Weight entries

struct WeightEntryRow: Codable, Sendable {
    var id: UUID
    var userId: UUID
    var recordedAt: Date
    var weightKg: Double
    var bodyFatPercent: Double?
    var isDeleted: Bool
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", recordedAt = "recorded_at", weightKg = "weight_kg"
        case bodyFatPercent = "body_fat_percent", isDeleted = "is_deleted", updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(userId, forKey: .userId)
        try c.encode(recordedAt, forKey: .recordedAt); try c.encode(weightKg, forKey: .weightKg)
        try c.encode(bodyFatPercent, forKey: .bodyFatPercent); try c.encode(isDeleted, forKey: .isDeleted)
    }
}

extension WeightEntryRow {
    @MainActor
    init(_ w: WeightEntry, userID: UUID) {
        self.init(id: w.id, userId: userID, recordedAt: w.recordedAt, weightKg: w.weightKg,
                  bodyFatPercent: w.bodyFatPercent, isDeleted: w.isSoftDeleted, updatedAt: nil)
    }

    @MainActor
    func apply(to w: WeightEntry) {
        w.recordedAt = recordedAt; w.weightKg = weightKg; w.bodyFatPercent = bodyFatPercent
        w.isSoftDeleted = isDeleted; w.updatedAt = updatedAt ?? .now; w.needsSync = false
    }
}

// MARK: - Meal plans

struct MealPlanRow: Codable, Sendable {
    var id: UUID
    var userId: UUID
    var title: String
    var targetKcal: Double
    var plan: MealPlanResponse
    var isDeleted: Bool
    var createdAt: Date?
    var updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, userId = "user_id", title, targetKcal = "target_kcal", plan
        case isDeleted = "is_deleted", createdAt = "created_at", updatedAt = "updated_at"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(userId, forKey: .userId); try c.encode(title, forKey: .title)
        try c.encode(targetKcal, forKey: .targetKcal); try c.encode(plan, forKey: .plan)
        try c.encode(isDeleted, forKey: .isDeleted)
    }
}
