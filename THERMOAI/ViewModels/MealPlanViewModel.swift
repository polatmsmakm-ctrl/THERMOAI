//
//  MealPlanViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Generates AI meal plans from the user's macro targets and
//           preferences, saves them, and logs planned meals to the food log.
//  Dependencies: SwiftData, Services/GeminiService.swift, Models
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class MealPlanViewModel {
    var preferences = MealPreferences()
    var allergiesText = ""
    var dislikesText = ""
    var days = 1
    private(set) var isGenerating = false
    private(set) var plan: MealPlanResponse?
    var selectedDay = 1
    var errorMessage: String?

    static let diets = ["omnivore", "vegetarian", "vegan", "pescatarian", "keto", "mediterranean", "halal"]

    private let ai: any AIServicing

    init(ai: any AIServicing) { self.ai = ai }

    func generate(targets: MacroTargets, isPro: Bool) async {
        if days > 1 && !isPro {
            errorMessage = "Multi-day plans are part of THERMO AI Pro."
            return
        }
        preferences.allergies = Self.parseList(allergiesText)
        preferences.dislikes = Self.parseList(dislikesText)
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }
        do {
            plan = try await ai.mealPlan(targets: targets, preferences: preferences, days: days)
            selectedDay = 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var currentDay: MealPlanDay? { plan?.days.first { $0.dayIndex == selectedDay } }

    func save(in context: ModelContext, targetCalories: Double) {
        guard let plan else { return }
        do {
            context.insert(try SavedMealPlan(title: plan.title, targetCalories: targetCalories, plan: plan))
            try context.save()
        } catch {
            errorMessage = "Couldn't save plan: \(error.localizedDescription)"
        }
    }

    func load(_ saved: SavedMealPlan) {
        plan = saved.plan
        selectedDay = 1
    }

    func log(_ meal: PlannedMeal, using log: FoodLogViewModel, in context: ModelContext, exportToHealth: Bool) {
        let entry = FoodEntry(mealType: meal.mealType, name: meal.name, servingDescription: "1 serving",
                              calories: meal.calories, proteinG: meal.proteinG, carbsG: meal.carbsG,
                              fatG: meal.fatG, source: .mealPlan)
        log.insert([entry], in: context, exportToHealth: exportToHealth)
    }

    static func parseList(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(20)
            .map { String($0.prefix(40)) }
    }
}
