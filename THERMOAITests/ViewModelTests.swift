//
//  ViewModelTests.swift
//  THERMOAITests
//
//  Purpose: View model behaviour with mocked AI and Health services and an
//           in-memory SwiftData container.
//  Dependencies: Swift Testing, SwiftData, @testable THERMOAI
//

import Foundation
import SwiftData
import Testing
@testable import THERMOAI

// MARK: - Mocks

final class MockAIService: AIServicing, @unchecked Sendable {
    var foodResult: Result<FoodAnalysisResult, Error> = .success(
        FoodAnalysisResult(isFood: true, items: [AnalyzedFoodItem(name: "Egg", portionDescription: "2 large", estimatedGrams: 100,
                                                                  calories: 143, proteinG: 12.6, carbsG: 0.7, fatG: 9.5,
                                                                  fiberG: 0, confidence: 0.9)], notes: ""))
    var chatResult: Result<ChatReply, Error> = .success(ChatReply(reply: "Eat more protein.", suggestions: ["Why?"]))
    var planResult: Result<MealPlanResponse, Error> = .success(MealPlanResponse(title: "Plan", days: [
        MealPlanDay(dayIndex: 1, meals: [PlannedMeal(mealType: .lunch, name: "Bowl", description: "", ingredients: [],
                                                    calories: 600, proteinG: 40, carbsG: 60, fatG: 20)],
                    totalCalories: 600, calorieDeviation: 0)], notes: ""))
    private(set) var lastChatHistory: [ChatTurn] = []
    private(set) var mealPlanCalls = 0

    func analyzeFood(imageJPEG: Data, note: String?) async throws -> FoodAnalysisResult { try foodResult.get() }
    func analyzeFood(description: String) async throws -> FoodAnalysisResult { try foodResult.get() }
    func chat(history: [ChatTurn], context: NutritionContext) async throws -> ChatReply {
        lastChatHistory = history
        return try chatResult.get()
    }
    func mealPlan(targets: MacroTargets, preferences: MealPreferences, days: Int) async throws -> MealPlanResponse {
        mealPlanCalls += 1
        return try planResult.get()
    }
}

struct MockHealthService: HealthServicing {
    var isAvailable: Bool { false }
    func requestAuthorization() async throws {}
    func latestBodyMassKg() async throws -> Double? { nil }
    func latestHeightCm() async throws -> Double? { nil }
    func latestBodyFatPercent() async throws -> Double? { nil }
    func activeEnergyKcal(on day: Date) async throws -> Double { 0 }
    func saveFood(name: String, date: Date, calories: Double, proteinG: Double, carbsG: Double, fatG: Double, entryID: UUID) async throws {}
    func saveBodyMass(kg: Double, date: Date) async throws {}
}

private let testContext = NutritionContext(targetCalories: 2000, consumedCalories: 500, proteinTargetG: 150,
                                           carbsTargetG: 200, fatTargetG: 60, goal: "lose")

// MARK: - Tests

@MainActor
@Suite("View models")
struct ViewModelTests {

    @Test func assistantSendsHistoryAndAppendsReply() async {
        let ai = MockAIService()
        let vm = AssistantViewModel(ai: ai)
        vm.input = "How much protein?"
        await vm.send(context: testContext)
        #expect(vm.messages.count == 2)
        #expect(vm.messages.last?.role == .assistant)
        #expect(ai.lastChatHistory.first?.text == "How much protein?")
        #expect(vm.suggestions == ["Why?"])
        #expect(vm.input.isEmpty)
    }

    @Test func assistantSurfacesErrors() async {
        let ai = MockAIService()
        ai.chatResult = .failure(APIError.quotaExceeded)
        let vm = AssistantViewModel(ai: ai)
        await vm.send("Hi", context: testContext)
        #expect(vm.errorMessage == APIError.quotaExceeded.errorDescription)
        #expect(vm.messages.count == 1)
    }

    @Test func mealPlanMultiDayRequiresPro() async {
        let ai = MockAIService()
        let vm = MealPlanViewModel(ai: ai)
        vm.days = 3
        await vm.generate(targets: MacroTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 60), isPro: false)
        #expect(ai.mealPlanCalls == 0)
        #expect(vm.errorMessage != nil)

        await vm.generate(targets: MacroTargets(calories: 2000, proteinG: 150, carbsG: 200, fatG: 60), isPro: true)
        #expect(ai.mealPlanCalls == 1)
        #expect(vm.plan?.title == "Plan")
    }

    @Test func parsesPreferenceLists() {
        #expect(MealPlanViewModel.parseList("peanuts, shellfish,\n gluten ,,") == ["peanuts", "shellfish", "gluten"])
    }

    @Test func foodLogDraftValidationAndSave() throws {
        let container = try ThermoSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let vm = FoodLogViewModel(ai: MockAIService(), health: MockHealthService())
        #expect(!vm.draftIsValid)
        vm.draftName = "Apple"
        vm.draftCalories = 95
        vm.draftCarbs = 25
        #expect(vm.draftIsValid)
        vm.saveDraft(in: context, exportToHealth: false)
        let saved = try context.fetch(FetchDescriptor<FoodEntry>())
        #expect(saved.count == 1)
        #expect(saved.first?.needsSync == true)
        #expect(vm.draftName.isEmpty)
    }

    @Test func softDeleteMarksForSync() throws {
        let container = try ThermoSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let entry = FoodEntry(mealType: .snack, name: "Bar", calories: 200, proteinG: 10, carbsG: 20, fatG: 8)
        entry.needsSync = false
        context.insert(entry)
        FoodLogViewModel(ai: MockAIService(), health: MockHealthService()).delete(entry, in: context)
        #expect(entry.isSoftDeleted)
        #expect(entry.needsSync)
    }

    @Test func onboardingValidatesAdultsOnly() {
        let vm = OnboardingViewModel(health: MockHealthService())
        vm.step = .body
        vm.birthDate = Calendar.current.date(byAdding: .year, value: -16, to: .now)!
        #expect(!vm.canAdvance)
        vm.birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
        #expect(vm.canAdvance)
        #expect(vm.preview != nil)
    }

    @Test func onboardingCompletePersistsProfileAndWeight() throws {
        let container = try ThermoSchema.makeContainer(inMemory: true)
        let vm = OnboardingViewModel(health: MockHealthService())
        let userID = UUID()
        try vm.complete(in: container.mainContext, userID: userID, healthEnabled: false)
        let profiles = try container.mainContext.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.first?.id == userID)
        #expect(profiles.first?.onboardingCompleted == true)
        #expect(try container.mainContext.fetch(FetchDescriptor<WeightEntry>()).count == 1)
    }

    @Test func dashboardComputesSnapshot() throws {
        let container = try ThermoSchema.makeContainer(inMemory: true)
        let profile = UserProfile(sex: .male, birthDate: Calendar.current.date(byAdding: .year, value: -30, to: .now)!,
                                  heightCm: 180, activity: .moderate, goal: .maintain)
        let weight = WeightEntry(weightKg: 80)
        let food = FoodEntry(mealType: .lunch, name: "Meal", calories: 600, proteinG: 40, carbsG: 60, fatG: 20)
        container.mainContext.insert(profile)
        container.mainContext.insert(weight)
        container.mainContext.insert(food)

        let vm = DashboardViewModel(health: MockHealthService())
        vm.refresh(profile: profile, entries: [food], weights: [weight])
        let snap = try #require(vm.snapshot)
        #expect(snap.today.calories == 600)
        #expect(snap.metabolic?.bmr == 1780)
        #expect(snap.weekly.count == 7)
        #expect(vm.insight != nil)
    }

    @Test func scannerPortionEditRescalesNutrients() {
        let vm = ScannerViewModel(ai: MockAIService())
        let item = AnalyzedFoodItem(name: "Rice", portionDescription: "1 cup", estimatedGrams: 100, calories: 130,
                                    proteinG: 2.7, carbsG: 28, fatG: 0.3, fiberG: 0.4, confidence: 0.8)
        vm.items = [item]
        vm.updateGrams(for: item, to: 200)
        #expect(vm.totalCalories == 260)
        vm.remove(vm.items[0])
        #expect(vm.items.isEmpty)
    }
}
