//
//  AIModels.swift
//  THERMOAI — Models
//
//  Purpose: Codable DTOs exchanged with the gemini-proxy Edge Function.
//           Field names mirror backend/supabase/functions/gemini-proxy/schemas.ts.
//  Dependencies: Foundation, Models/Enums.swift
//

import Foundation

// MARK: - Requests

struct AIRequest: Encodable, Sendable {
    enum Task: String, Encodable, Sendable { case analyzeFoodImage, analyzeFoodText, chat, mealPlan }

    let task: Task
    var imageBase64: String? = nil
    var mimeType: String? = nil
    var description: String? = nil
    var note: String? = nil
    var messages: [ChatTurn]? = nil
    var context: NutritionContext? = nil
    var targets: MacroTargets? = nil
    var preferences: MealPreferences? = nil
    var days: Int? = nil
}

struct ChatTurn: Codable, Sendable, Equatable {
    enum Role: String, Codable, Sendable { case user, assistant }
    let role: Role
    let text: String
}

struct NutritionContext: Codable, Sendable, Equatable {
    var targetCalories: Double
    var consumedCalories: Double
    var proteinTargetG: Double
    var carbsTargetG: Double
    var fatTargetG: Double
    var goal: String
}

struct MealPreferences: Codable, Sendable, Equatable {
    var diet: String = "omnivore"
    var allergies: [String] = []
    var dislikes: [String] = []
    var cuisines: [String] = []
}

// MARK: - Food analysis

struct FoodAnalysisResult: Codable, Sendable, Equatable {
    var isFood: Bool
    var items: [AnalyzedFoodItem]
    var notes: String

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { items.reduce(0) { $0 + $1.fatG } }
    var averageConfidence: Double {
        items.isEmpty ? 0 : items.reduce(0) { $0 + $1.confidence } / Double(items.count)
    }
}

struct AnalyzedFoodItem: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name)-\(estimatedGrams)" }
    var name: String
    var portionDescription: String
    var estimatedGrams: Double
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double
    var confidence: Double

    /// Returns a copy with all nutrients scaled to a new gram weight
    /// (used when the user corrects the AI's portion estimate).
    func scaled(toGrams newGrams: Double) -> AnalyzedFoodItem {
        guard estimatedGrams > 0 else { return self }
        let f = max(newGrams, 0) / estimatedGrams
        var copy = self
        copy.estimatedGrams = max(newGrams, 0)
        copy.calories = calories * f
        copy.proteinG = proteinG * f
        copy.carbsG = carbsG * f
        copy.fatG = fatG * f
        copy.fiberG = fiberG * f
        return copy
    }
}

// MARK: - Chat

struct ChatReply: Codable, Sendable, Equatable {
    var reply: String
    var suggestions: [String]
}

// MARK: - Meal plan

struct MealPlanResponse: Codable, Sendable, Equatable {
    var title: String
    var days: [MealPlanDay]
    var notes: String
}

struct MealPlanDay: Codable, Sendable, Equatable, Identifiable {
    var id: Int { dayIndex }
    var dayIndex: Int
    var meals: [PlannedMeal]
    var totalCalories: Double
    var calorieDeviation: Double
}

struct PlannedMeal: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(mealType.rawValue)-\(name)" }
    var mealType: MealType
    var name: String
    var description: String
    var ingredients: [String]
    var calories: Double
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
}

// MARK: - Backend error envelope

struct BackendErrorEnvelope: Decodable, Sendable {
    struct Body: Decodable, Sendable { let code: String; let message: String }
    let error: Body
}
