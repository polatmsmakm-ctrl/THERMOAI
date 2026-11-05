//
//  FoodLogViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Day navigation, grouping by meal, manual/AI-text entry creation,
//           deletion (soft) and optional HealthKit export.
//  Dependencies: SwiftData, Models, Services/GeminiService.swift, Services/HealthKitService.swift
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class FoodLogViewModel {
    var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    var errorMessage: String?

    // Manual entry draft
    var draftName = ""
    var draftMeal: MealType = .suggested()
    var draftCalories: Double = 0
    var draftProtein: Double = 0
    var draftCarbs: Double = 0
    var draftFat: Double = 0
    var draftGrams: Double = 0

    // AI text entry
    var aiDescription = ""
    var isAnalyzingText = false
    var textResult: FoodAnalysisResult?

    private let ai: any AIServicing
    private let health: any HealthServicing

    init(ai: any AIServicing, health: any HealthServicing) {
        self.ai = ai
        self.health = health
    }

    // MARK: Day navigation

    var isToday: Bool { Calendar.current.isDateInToday(selectedDay) }

    func shiftDay(by days: Int) {
        guard let d = Calendar.current.date(byAdding: .day, value: days, to: selectedDay) else { return }
        if d <= Calendar.current.startOfDay(for: .now) { selectedDay = d }
    }

    func entries(_ all: [FoodEntry], for meal: MealType) -> [FoodEntry] {
        all.filter { !$0.isSoftDeleted && $0.mealType == meal && Calendar.current.isDate($0.consumedAt, inSameDayAs: selectedDay) }
            .sorted { $0.consumedAt < $1.consumedAt }
    }

    // MARK: Manual entry

    var draftIsValid: Bool {
        !draftName.trimmingCharacters(in: .whitespaces).isEmpty && draftCalories > 0 && draftCalories <= 10_000
            && [draftProtein, draftCarbs, draftFat, draftGrams].allSatisfy { $0 >= 0 }
    }

    /// Calories implied by entered macros (helps users catch typos).
    var draftDerivedCalories: Double {
        NutritionEngine.energy(proteinG: draftProtein, carbsG: draftCarbs, fatG: draftFat)
    }

    func saveDraft(in context: ModelContext, exportToHealth: Bool) {
        guard draftIsValid else { errorMessage = "Enter a name and calories."; return }
        let entry = FoodEntry(consumedAt: timestampForSelectedDay(), mealType: draftMeal, name: draftName.trimmingCharacters(in: .whitespaces),
                              servingDescription: draftGrams > 0 ? "\(Int(draftGrams)) g" : "", grams: draftGrams,
                              calories: draftCalories, proteinG: draftProtein, carbsG: draftCarbs, fatG: draftFat)
        insert([entry], in: context, exportToHealth: exportToHealth)
        resetDraft()
    }

    func resetDraft() {
        draftName = ""; draftCalories = 0; draftProtein = 0; draftCarbs = 0; draftFat = 0; draftGrams = 0
        draftMeal = .suggested()
    }

    // MARK: AI text entry

    func analyzeDescription() async {
        isAnalyzingText = true
        errorMessage = nil
        defer { isAnalyzingText = false }
        do {
            textResult = try await ai.analyzeFood(description: aiDescription)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveTextResult(in context: ModelContext, exportToHealth: Bool) {
        guard let result = textResult else { return }
        let entries = Self.entries(from: result.items, meal: draftMeal, at: timestampForSelectedDay(), source: .aiText)
        insert(entries, in: context, exportToHealth: exportToHealth)
        textResult = nil
        aiDescription = ""
    }

    // MARK: Delete / duplicate

    func delete(_ entry: FoodEntry, in context: ModelContext) {
        entry.softDelete()
        try? context.save()
    }

    func duplicateToToday(_ entry: FoodEntry, in context: ModelContext) {
        let copy = FoodEntry(mealType: entry.mealType, name: entry.name, servingDescription: entry.servingDescription,
                             grams: entry.grams, calories: entry.calories, proteinG: entry.proteinG,
                             carbsG: entry.carbsG, fatG: entry.fatG, fiberG: entry.fiberG, source: .manual)
        context.insert(copy)
        try? context.save()
    }

    // MARK: Shared helpers

    static func entries(from items: [AnalyzedFoodItem], meal: MealType, at date: Date, source: EntrySource) -> [FoodEntry] {
        items.map {
            FoodEntry(consumedAt: date, mealType: meal, name: $0.name, servingDescription: $0.portionDescription,
                      grams: $0.estimatedGrams, calories: $0.calories.rounded(), proteinG: $0.proteinG,
                      carbsG: $0.carbsG, fatG: $0.fatG, fiberG: $0.fiberG, source: source, aiConfidence: $0.confidence)
        }
    }

    func insert(_ entries: [FoodEntry], in context: ModelContext, exportToHealth: Bool) {
        for entry in entries { context.insert(entry) }
        do { try context.save() } catch { errorMessage = "Couldn't save: \(error.localizedDescription)" }
        guard exportToHealth else { return }
        let payload = entries.map { ($0.name, $0.consumedAt, $0.calories, $0.proteinG, $0.carbsG, $0.fatG, $0.id) }
        let health = self.health
        Task {
            for p in payload {
                try? await health.saveFood(name: p.0, date: p.1, calories: p.2, proteinG: p.3, carbsG: p.4, fatG: p.5, entryID: p.6)
            }
        }
    }

    /// Entries logged for a past day are placed at noon of that day.
    private func timestampForSelectedDay() -> Date {
        if isToday { return .now }
        return Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: selectedDay) ?? selectedDay
    }
}
