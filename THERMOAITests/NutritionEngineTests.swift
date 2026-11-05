//
//  NutritionEngineTests.swift
//  THERMOAITests
//
//  Purpose: Verifies every equation against hand-calculated reference values.
//  Dependencies: Swift Testing, @testable THERMOAI
//

import Testing
@testable import THERMOAI

@Suite("NutritionEngine")
struct NutritionEngineTests {

    private func male() throws -> MetabolicInput {
        try MetabolicInput(weightKg: 80, heightCm: 180, ageYears: 30, sex: .male, bodyFatPercent: 20, activity: .moderate)
    }

    private func female() throws -> MetabolicInput {
        try MetabolicInput(weightKg: 60, heightCm: 165, ageYears: 25, sex: .female, activity: .light)
    }

    // MARK: BMR

    @Test func mifflinStJeorMale() throws {
        // 10*80 + 6.25*180 - 5*30 + 5 = 1780
        #expect(NutritionEngine.mifflinStJeor(try male()) == 1780)
    }

    @Test func mifflinStJeorFemale() throws {
        // 600 + 1031.25 - 125 - 161 = 1345.25
        #expect(NutritionEngine.mifflinStJeor(try female()) == 1345.25)
    }

    @Test func harrisBenedictRevised() throws {
        #expect(abs(NutritionEngine.harrisBenedictRevised(try male()) - 1853.632) < 0.001)
        #expect(abs(NutritionEngine.harrisBenedictRevised(try female()) - 1405.333) < 0.001)
    }

    @Test func katchMcArdle() throws {
        // LBM = 80 * 0.8 = 64 → 370 + 21.6*64 = 1752.4
        #expect(abs(try NutritionEngine.katchMcArdle(try male()) - 1752.4) < 0.001)
    }

    @Test func katchMcArdleRequiresBodyFat() throws {
        #expect(throws: CalculationError.bodyFatRequired) { try NutritionEngine.katchMcArdle(try female()) }
    }

    @Test func katchFallsBackToMifflinWithoutBodyFat() throws {
        let result = NutritionEngine.bmr(try female(), formula: .katchMcArdle)
        #expect(result.usedFormula == .mifflinStJeor)
        #expect(result.value == 1345.25)
    }

    // MARK: Validation

    @Test(arguments: [(10.0, 170.0, 30), (80.0, 20.0, 30), (80.0, 170.0, 12)])
    func rejectsOutOfRangeInput(weight: Double, height: Double, age: Int) {
        #expect(throws: CalculationError.self) {
            try MetabolicInput(weightKg: weight, heightCm: height, ageYears: age, sex: .male, activity: .sedentary)
        }
    }

    @Test func rejectsInvalidBodyFat() {
        #expect(throws: CalculationError.invalidBodyFat(90)) {
            try MetabolicInput(weightKg: 70, heightCm: 170, ageYears: 30, sex: .male, bodyFatPercent: 90, activity: .light)
        }
    }

    // MARK: TDEE & goals

    @Test func tdeeUsesActivityMultiplier() {
        #expect(NutritionEngine.tdee(bmr: 1780, activity: .moderate) == 2759)
        #expect(NutritionEngine.tdee(bmr: 1000, activity: .sedentary) == 1200)
    }

    @Test func dailyEnergyDelta() {
        #expect(NutritionEngine.dailyEnergyDelta(goal: .lose, rateKgPerWeek: 0.5) == -550)
        #expect(NutritionEngine.dailyEnergyDelta(goal: .gain, rateKgPerWeek: 0.25) == 275)
        #expect(NutritionEngine.dailyEnergyDelta(goal: .maintain, rateKgPerWeek: 1) == 0)
        // Rate is clamped to 1.5 kg/week.
        #expect(NutritionEngine.dailyEnergyDelta(goal: .lose, rateKgPerWeek: 5) == -1650)
    }

    @Test func safetyFloorClampsAggressiveDeficits() {
        let result = NutritionEngine.targetCalories(tdee: 1500, goal: .lose, rateKgPerWeek: 1.0, sex: .female)
        #expect(result.calories == 1200)
        #expect(result.clamped)
        let male = NutritionEngine.targetCalories(tdee: 1800, goal: .lose, rateKgPerWeek: 1.0, sex: .male)
        #expect(male.calories == 1500)
    }

    @Test func weeksToGoal() {
        #expect(NutritionEngine.weeksToGoal(currentKg: 80, targetKg: 75, dailyDelta: -550) == 10)
        // Wrong direction → nil
        #expect(NutritionEngine.weeksToGoal(currentKg: 80, targetKg: 85, dailyDelta: -550) == nil)
    }

    // MARK: TEF & energy

    @Test func thermicEffect() {
        let tef = NutritionEngine.thermicEffect(proteinG: 100, carbsG: 200, fatG: 50)
        #expect(tef.protein == 100)
        #expect(abs(tef.carbohydrate - 60) < 0.0001)
        #expect(abs(tef.fat - 9) < 0.0001)
        #expect(abs(tef.total - 169) < 0.0001)
    }

    @Test func atwaterEnergy() {
        #expect(NutritionEngine.energy(proteinG: 10, carbsG: 10, fatG: 10) == 170)
        #expect(NutritionEngine.energy(proteinG: 0, carbsG: 0, fatG: 0, alcoholG: 10) == 70)
    }

    // MARK: Macros

    @Test func macrosForWeightLoss() {
        let m = NutritionEngine.macros(calories: 2000, weightKg: 80, heightCm: 180, goal: .lose)
        #expect(m.proteinG == 160)   // 2.0 g/kg
        #expect(m.fatG == 56)        // 25% of 2000 / 9
        #expect(m.carbsG == 215)     // remainder
    }

    @Test func macrosNeverExceedCalories() {
        let m = NutritionEngine.macros(calories: 1200, weightKg: 150, heightCm: 200, goal: .lose)
        let energy = NutritionEngine.energy(proteinG: m.proteinG, carbsG: m.carbsG, fatG: m.fatG)
        #expect(energy <= 1200 + 10) // rounding tolerance
        #expect(m.carbsG >= 0)
    }

    // MARK: Body composition

    @Test func bmiAndCategory() {
        let bmi = NutritionEngine.bmi(weightKg: 80, heightCm: 180)
        #expect(abs(bmi - 24.691) < 0.001)
        #expect(NutritionEngine.bmiCategory(bmi) == .normal)
        #expect(NutritionEngine.bmiCategory(17) == .underweight)
        #expect(NutritionEngine.bmiCategory(27) == .overweight)
        #expect(NutritionEngine.bmiCategory(31) == .obese)
    }

    @Test func leanBodyMass() {
        #expect(NutritionEngine.leanBodyMass(weightKg: 80, bodyFatPercent: 25) == 60)
        #expect(abs(NutritionEngine.estimatedLeanBodyMass(weightKg: 80, heightCm: 180, sex: .male) - 61.42) < 0.001)
    }

    // MARK: Aggregate

    @Test func fullProfile() throws {
        let p = NutritionEngine.profile(for: try male(), formula: .mifflinStJeor, goal: .lose, rateKgPerWeek: 0.5)
        #expect(p.bmr == 1780)
        #expect(p.tdee == 2759)
        #expect(p.targetCalories == 2209)
        #expect(p.dailyEnergyDelta == -550)
        #expect(!p.wasClampedToSafetyFloor)
        #expect(!p.leanMassIsEstimated)
    }
}
