//
//  OnboardingViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Multi-step onboarding (body → activity → goal → review). Produces the
//           UserProfile and first WeightEntry; optionally imports from HealthKit.
//  Dependencies: SwiftData, Models, Core/Calculation, Services/HealthKitService.swift
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class OnboardingViewModel {
    enum Step: Int, CaseIterable { case welcome, body, activity, goal, review }

    var step: Step = .welcome
    var displayName = ""
    var sex: BiologicalSex = .female
    var birthDate = Calendar.current.date(byAdding: .year, value: -30, to: .now)!
    var heightCm: Double = 168
    var weightKg: Double = 70
    var bodyFatPercent: Double? = nil
    var activity: ActivityLevel = .light
    var goal: WeightGoal = .maintain
    var rateKgPerWeek: Double = 0.5
    var targetWeightKg: Double = 65
    var isImporting = false
    var errorMessage: String?

    private let health: any HealthServicing

    init(health: any HealthServicing, displayName: String = "") {
        self.health = health
        self.displayName = displayName
    }

    var ageYears: Int { Calendar.current.dateComponents([.year], from: birthDate, to: .now).year ?? 0 }

    var validationMessage: String? {
        if step == .body {
            if ageYears < 18 { return "THERMO AI is designed for adults 18 and over." }
            if !(50...272).contains(heightCm) { return "Enter a height between 50 and 272 cm." }
            if !(20...400).contains(weightKg) { return "Enter a weight between 20 and 400 kg." }
            if let bf = bodyFatPercent, !(2...70).contains(bf) { return "Body fat must be between 2% and 70%." }
        }
        return nil
    }

    var canAdvance: Bool { validationMessage == nil }

    /// Live preview shown on the review step.
    var preview: MetabolicProfile? {
        guard let input = try? MetabolicInput(weightKg: weightKg, heightCm: heightCm, ageYears: ageYears, sex: sex,
                                              bodyFatPercent: bodyFatPercent, activity: activity) else { return nil }
        return NutritionEngine.profile(for: input, formula: bodyFatPercent == nil ? .mifflinStJeor : .katchMcArdle,
                                       goal: goal, rateKgPerWeek: rateKgPerWeek)
    }

    func next() {
        guard canAdvance, let nextStep = Step(rawValue: step.rawValue + 1) else { return }
        step = nextStep
    }

    func back() {
        guard let prev = Step(rawValue: step.rawValue - 1) else { return }
        step = prev
    }

    /// Pre-fills body metrics from Apple Health when the user opts in.
    func importFromHealth() async {
        guard health.isAvailable else { errorMessage = "Apple Health isn't available on this device."; return }
        isImporting = true
        defer { isImporting = false }
        do {
            try await health.requestAuthorization()
            if let w = try await health.latestBodyMassKg() { weightKg = (w * 10).rounded() / 10 }
            if let h = try await health.latestHeightCm() { heightCm = h.rounded() }
            if let bf = try await health.latestBodyFatPercent() { bodyFatPercent = (bf * 10).rounded() / 10 }
        } catch {
            errorMessage = "Couldn't read Apple Health: \(error.localizedDescription)"
        }
    }

    /// Persists the profile. `userID` makes the local profile id match the Supabase row.
    func complete(in context: ModelContext, userID: UUID, healthEnabled: Bool) throws {
        let profile = UserProfile(id: userID, displayName: displayName, sex: sex, birthDate: birthDate,
                                  heightCm: heightCm, activity: activity, goal: goal,
                                  goalRateKgPerWeek: goal == .maintain ? 0 : rateKgPerWeek,
                                  targetWeightKg: goal == .maintain ? nil : targetWeightKg,
                                  bodyFatPercent: bodyFatPercent,
                                  formula: bodyFatPercent == nil ? .mifflinStJeor : .katchMcArdle)
        profile.healthKitEnabled = healthEnabled
        profile.onboardingCompleted = true
        context.insert(profile)
        context.insert(WeightEntry(weightKg: weightKg, bodyFatPercent: bodyFatPercent))
        try context.save()
    }
}
