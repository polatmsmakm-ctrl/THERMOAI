//
//  AIResponseValidator.swift
//  THERMOAI — Services
//
//  Purpose: Defence-in-depth validation of AI output on device (the server
//           validates too). Pure functions — fully unit tested.
//  Dependencies: Models/AIModels.swift, Core/Calculation/NutritionEngine.swift
//

import Foundation

enum AIValidationError: Error, LocalizedError, Equatable {
    case invalidNumber(String)
    case emptyReply
    case emptyPlan

    var errorDescription: String? {
        switch self {
        case .invalidNumber(let field): "The AI returned an invalid value for \(field)."
        case .emptyReply: "The assistant didn't return an answer. Please try again."
        case .emptyPlan: "The meal plan came back empty. Please try again."
        }
    }
}

enum AIResponseValidator {
    /// Allowed relative disagreement between stated calories and Atwater energy.
    static let calorieTolerance = 0.25

    static func validate(_ result: FoodAnalysisResult) throws -> FoodAnalysisResult {
        guard result.isFood, !result.items.isEmpty else { throw AIServiceError.notFood }
        var copy = result
        copy.items = try result.items.map(validate)
        return copy
    }

    static func validate(_ item: AnalyzedFoodItem) throws -> AnalyzedFoodItem {
        for (field, value) in [("calories", item.calories), ("protein", item.proteinG), ("carbs", item.carbsG),
                               ("fat", item.fatG), ("fiber", item.fiberG), ("grams", item.estimatedGrams)] {
            guard value.isFinite, value >= 0 else { throw AIValidationError.invalidNumber(field) }
        }
        var copy = item
        copy.confidence = min(max(item.confidence, 0), 1)
        let derived = NutritionEngine.energy(proteinG: item.proteinG, carbsG: item.carbsG, fatG: item.fatG)
        if derived > 0, abs(item.calories - derived) / derived > calorieTolerance {
            copy.calories = derived.rounded()
            copy.confidence = min(copy.confidence, 0.5)
        }
        if copy.name.trimmingCharacters(in: .whitespaces).isEmpty { copy.name = "Unknown food" }
        return copy
    }

    static func validate(_ reply: ChatReply) throws -> ChatReply {
        let text = reply.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw AIValidationError.emptyReply }
        return ChatReply(reply: text, suggestions: Array(reply.suggestions.prefix(3)))
    }

    static func validate(_ plan: MealPlanResponse) throws -> MealPlanResponse {
        guard !plan.days.isEmpty, plan.days.allSatisfy({ !$0.meals.isEmpty }) else { throw AIValidationError.emptyPlan }
        for day in plan.days {
            for meal in day.meals {
                for value in [meal.calories, meal.proteinG, meal.carbsG, meal.fatG] where !(value.isFinite && value >= 0) {
                    throw AIValidationError.invalidNumber(meal.name)
                }
            }
        }
        return plan
    }
}
