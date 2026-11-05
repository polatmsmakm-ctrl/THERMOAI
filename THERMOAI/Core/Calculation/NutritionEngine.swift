//
//  NutritionEngine.swift
//  THERMOAI — Core/Calculation
//
//  Purpose: Pure, UI-independent metabolic calculations.
//  Dependencies: Foundation, Models/Enums.swift
//
//  UNITS (all inputs are metric, SI-adjacent):
//    weight  → kilograms (kg)
//    height  → centimetres (cm)
//    age     → whole years
//    energy  → kilocalories (kcal), per day unless stated
//    body fat→ percent (0–100), never a fraction
//
//  LIMITATIONS (surfaced in the UI on the Metabolic Calculator screen):
//    • Predictive equations estimate population averages; individual error is
//      commonly ±10% and larger at the extremes of body size.
//    • None are validated for under-18s, pregnancy/lactation, or clinical states
//      (thyroid disease, amputation, critical illness). The app is not a medical device.
//    • Activity multipliers already contain an average TEF (~10%). TEF is reported
//      separately for insight, but is NOT added to TDEE a second time.
//

import Foundation

// MARK: - Errors

public enum CalculationError: Error, Equatable, Sendable, LocalizedError {
    case invalidWeight(Double)
    case invalidHeight(Double)
    case invalidAge(Int)
    case invalidBodyFat(Double)
    case bodyFatRequired

    public var errorDescription: String? {
        switch self {
        case .invalidWeight(let w):  "Weight \(w) kg is outside the supported range (20–400 kg)."
        case .invalidHeight(let h):  "Height \(h) cm is outside the supported range (50–272 cm)."
        case .invalidAge(let a):     "Age \(a) is outside the supported range (18–100 years)."
        case .invalidBodyFat(let b): "Body fat \(b)% is outside the supported range (2–70%)."
        case .bodyFatRequired:       "Katch-McArdle requires a body fat percentage."
        }
    }
}

// MARK: - Inputs & outputs

/// Validated anthropometric input for every calculation.
public struct MetabolicInput: Sendable, Equatable {
    public let weightKg: Double
    public let heightCm: Double
    public let ageYears: Int
    public let sex: BiologicalSex
    public let bodyFatPercent: Double?
    public let activity: ActivityLevel

    public init(weightKg: Double, heightCm: Double, ageYears: Int, sex: BiologicalSex,
                bodyFatPercent: Double? = nil, activity: ActivityLevel) throws {
        guard (20...400).contains(weightKg) else { throw CalculationError.invalidWeight(weightKg) }
        guard (50...272).contains(heightCm) else { throw CalculationError.invalidHeight(heightCm) }
        guard (18...100).contains(ageYears) else { throw CalculationError.invalidAge(ageYears) }
        if let bf = bodyFatPercent, !(2...70).contains(bf) { throw CalculationError.invalidBodyFat(bf) }
        self.weightKg = weightKg
        self.heightCm = heightCm
        self.ageYears = ageYears
        self.sex = sex
        self.bodyFatPercent = bodyFatPercent
        self.activity = activity
    }
}

public struct MacroTargets: Sendable, Equatable, Codable {
    public var calories: Double
    public var proteinG: Double
    public var carbsG: Double
    public var fatG: Double

    public init(calories: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.calories = calories; self.proteinG = proteinG; self.carbsG = carbsG; self.fatG = fatG
    }

    public static let zero = MacroTargets(calories: 0, proteinG: 0, carbsG: 0, fatG: 0)
}

public struct TEFBreakdown: Sendable, Equatable {
    public let protein: Double
    public let carbohydrate: Double
    public let fat: Double
    public let alcohol: Double
    public var total: Double { protein + carbohydrate + fat + alcohol }
}

public enum BMICategory: String, Sendable, CaseIterable {
    case underweight = "Underweight"
    case normal = "Healthy range"
    case overweight = "Overweight"
    case obese = "Obesity"
}

/// Full metabolic profile produced by `NutritionEngine.profile(for:...)`.
public struct MetabolicProfile: Sendable, Equatable {
    public let formula: BMRFormula
    public let bmr: Double
    public let tdee: Double
    public let targetCalories: Double
    public let dailyEnergyDelta: Double          // negative = deficit
    public let macros: MacroTargets
    public let bmi: Double
    public let bmiCategory: BMICategory
    public let leanBodyMassKg: Double
    public let leanMassIsEstimated: Bool
    public let wasClampedToSafetyFloor: Bool
}

// MARK: - Engine

public enum NutritionEngine {

    // MARK: Constants

    /// Approximate energy content of 1 kg of body-mass change (mostly adipose tissue).
    /// Widely used (Wishnofsky, 1958); real-world change is non-linear due to adaptation.
    public static let kcalPerKgBodyMass: Double = 7700

    /// Atwater general factors (kcal per gram).
    public enum Atwater {
        public static let protein: Double = 4
        public static let carbohydrate: Double = 4
        public static let fat: Double = 9
        public static let alcohol: Double = 7
    }

    /// Thermic effect fractions (midpoints of published ranges):
    /// protein 20–30%, carbohydrate 5–10%, fat 0–3%, alcohol 10–30%.
    public enum TEFFraction {
        public static let protein: Double = 0.25
        public static let carbohydrate: Double = 0.075
        public static let fat: Double = 0.02
        public static let alcohol: Double = 0.15
    }

    /// Commonly cited minimum intakes without medical supervision.
    public static func safetyFloor(for sex: BiologicalSex) -> Double {
        sex == .male ? 1500 : 1200
    }

    // MARK: BMR equations

    /// Mifflin-St Jeor (1990).
    ///  Men:   BMR = 10·W + 6.25·H − 5·A + 5
    ///  Women: BMR = 10·W + 6.25·H − 5·A − 161
    /// Considered the most accurate general-population equation (ADA 2005 review).
    public static func mifflinStJeor(_ i: MetabolicInput) -> Double {
        let base = 10 * i.weightKg + 6.25 * i.heightCm - 5 * Double(i.ageYears)
        return base + (i.sex == .male ? 5 : -161)
    }

    /// Revised Harris-Benedict (Roza & Shizgal, 1984).
    ///  Men:   BMR = 88.362 + 13.397·W + 4.799·H − 5.677·A
    ///  Women: BMR = 447.593 + 9.247·W + 3.098·H − 4.330·A
    public static func harrisBenedictRevised(_ i: MetabolicInput) -> Double {
        let a = Double(i.ageYears)
        switch i.sex {
        case .male:   return 88.362 + 13.397 * i.weightKg + 4.799 * i.heightCm - 5.677 * a
        case .female: return 447.593 + 9.247 * i.weightKg + 3.098 * i.heightCm - 4.330 * a
        }
    }

    /// Katch-McArdle: BMR = 370 + 21.6·LBM(kg). Sex-independent; requires body fat %.
    public static func katchMcArdle(_ i: MetabolicInput) throws -> Double {
        guard let bf = i.bodyFatPercent else { throw CalculationError.bodyFatRequired }
        return 370 + 21.6 * leanBodyMass(weightKg: i.weightKg, bodyFatPercent: bf)
    }

    /// Dispatches to the selected equation. Falls back to Mifflin-St Jeor when
    /// Katch-McArdle is requested without body-fat data.
    public static func bmr(_ i: MetabolicInput, formula: BMRFormula) -> (value: Double, usedFormula: BMRFormula) {
        switch formula {
        case .mifflinStJeor:         return (mifflinStJeor(i), .mifflinStJeor)
        case .harrisBenedictRevised: return (harrisBenedictRevised(i), .harrisBenedictRevised)
        case .katchMcArdle:
            if let v = try? katchMcArdle(i) { return (v, .katchMcArdle) }
            return (mifflinStJeor(i), .mifflinStJeor)
        }
    }

    // MARK: TDEE & energy expenditure

    /// Total Daily Energy Expenditure = BMR × physical activity level (PAL) multiplier.
    public static func tdee(bmr: Double, activity: ActivityLevel) -> Double {
        bmr * activity.multiplier
    }

    /// TDEE that substitutes measured active energy (e.g. from HealthKit) for the
    /// activity multiplier: BMR + active kcal + TEF(≈10% of intake).
    public static func measuredEnergyExpenditure(bmr: Double, activeEnergyKcal: Double, intakeKcal: Double) -> Double {
        bmr + max(activeEnergyKcal, 0) + 0.10 * max(intakeKcal, 0)
    }

    // MARK: TEF

    /// Thermic effect of food per macronutrient (kcal).
    public static func thermicEffect(proteinG: Double, carbsG: Double, fatG: Double, alcoholG: Double = 0) -> TEFBreakdown {
        TEFBreakdown(
            protein: proteinG * Atwater.protein * TEFFraction.protein,
            carbohydrate: carbsG * Atwater.carbohydrate * TEFFraction.carbohydrate,
            fat: fatG * Atwater.fat * TEFFraction.fat,
            alcohol: alcoholG * Atwater.alcohol * TEFFraction.alcohol
        )
    }

    /// Atwater energy of a set of macronutrients (kcal).
    public static func energy(proteinG: Double, carbsG: Double, fatG: Double, alcoholG: Double = 0) -> Double {
        proteinG * Atwater.protein + carbsG * Atwater.carbohydrate + fatG * Atwater.fat + alcoholG * Atwater.alcohol
    }

    // MARK: Goals: deficits & surpluses

    /// Daily energy delta (kcal/day) required for a weekly rate of change.
    /// Negative for weight loss, positive for gain, 0 for maintenance.
    public static func dailyEnergyDelta(goal: WeightGoal, rateKgPerWeek: Double) -> Double {
        let rate = min(max(rateKgPerWeek, 0), 1.5)
        let magnitude = rate * kcalPerKgBodyMass / 7
        switch goal {
        case .lose:     return -magnitude
        case .maintain: return 0
        case .gain:     return magnitude
        }
    }

    /// Goal calories with safety floor applied.
    public static func targetCalories(tdee: Double, goal: WeightGoal, rateKgPerWeek: Double, sex: BiologicalSex)
        -> (calories: Double, clamped: Bool) {
        let raw = tdee + dailyEnergyDelta(goal: goal, rateKgPerWeek: rateKgPerWeek)
        let floor = safetyFloor(for: sex)
        return raw < floor ? (floor, true) : (raw, false)
    }

    /// Projected weeks to reach a target weight at a constant daily delta.
    public static func weeksToGoal(currentKg: Double, targetKg: Double, dailyDelta: Double) -> Double? {
        let diff = targetKg - currentKg
        guard dailyDelta != 0, diff.sign == dailyDelta.sign else { return nil }
        return (diff * kcalPerKgBodyMass) / (dailyDelta * 7)
    }

    // MARK: Macronutrients

    /// Evidence-based macro split:
    ///  • Protein: 2.0 g/kg (lose, preserves lean mass), 1.6 g/kg (maintain), 1.8 g/kg (gain).
    ///    Uses lean-adjusted weight when BMI ≥ 30 to avoid overestimation.
    ///  • Fat: 25% of calories, minimum 0.6 g/kg for hormonal health.
    ///  • Carbohydrate: remaining energy (never negative).
    public static func macros(calories: Double, weightKg: Double, heightCm: Double, goal: WeightGoal) -> MacroTargets {
        let proteinPerKg: Double = switch goal {
        case .lose: 2.0
        case .maintain: 1.6
        case .gain: 1.8
        }
        let bmiValue = bmi(weightKg: weightKg, heightCm: heightCm)
        let referenceWeight = bmiValue >= 30 ? 25 * pow(heightCm / 100, 2) * 1.1 : weightKg

        var protein = proteinPerKg * referenceWeight
        var fat = max(0.25 * calories / Atwater.fat, 0.6 * weightKg)

        // Ensure protein + fat never exceed the calorie budget.
        let pfEnergy = protein * Atwater.protein + fat * Atwater.fat
        if pfEnergy > calories {
            let scale = calories / pfEnergy
            protein *= scale
            fat *= scale
        }
        let carbs = max(0, (calories - protein * Atwater.protein - fat * Atwater.fat) / Atwater.carbohydrate)
        return MacroTargets(calories: calories, proteinG: protein.rounded(), carbsG: carbs.rounded(), fatG: fat.rounded())
    }

    // MARK: Body composition

    /// Body Mass Index = kg / m².
    public static func bmi(weightKg: Double, heightCm: Double) -> Double {
        let m = heightCm / 100
        return weightKg / (m * m)
    }

    /// WHO adult categories.
    public static func bmiCategory(_ bmi: Double) -> BMICategory {
        switch bmi {
        case ..<18.5: .underweight
        case ..<25:   .normal
        case ..<30:   .overweight
        default:      .obese
        }
    }

    /// Lean body mass from measured body fat: LBM = W × (1 − BF/100).
    public static func leanBodyMass(weightKg: Double, bodyFatPercent: Double) -> Double {
        weightKg * (1 - bodyFatPercent / 100)
    }

    /// Boer (1984) estimate when body fat is unknown.
    ///  Men:   LBM = 0.407·W + 0.267·H − 19.2
    ///  Women: LBM = 0.252·W + 0.473·H − 48.3
    public static func estimatedLeanBodyMass(weightKg: Double, heightCm: Double, sex: BiologicalSex) -> Double {
        switch sex {
        case .male:   0.407 * weightKg + 0.267 * heightCm - 19.2
        case .female: 0.252 * weightKg + 0.473 * heightCm - 48.3
        }
    }

    /// Estimated body fat % from Boer LBM (used only for display when unmeasured).
    public static func estimatedBodyFatPercent(weightKg: Double, heightCm: Double, sex: BiologicalSex) -> Double {
        let lbm = estimatedLeanBodyMass(weightKg: weightKg, heightCm: heightCm, sex: sex)
        return min(max((1 - lbm / weightKg) * 100, 2), 70)
    }

    // MARK: Aggregate

    /// Computes everything the dashboard needs in one call.
    public static func profile(for input: MetabolicInput, formula: BMRFormula,
                               goal: WeightGoal, rateKgPerWeek: Double) -> MetabolicProfile {
        let (bmrValue, used) = bmr(input, formula: formula)
        let tdeeValue = tdee(bmr: bmrValue, activity: input.activity)
        let target = targetCalories(tdee: tdeeValue, goal: goal, rateKgPerWeek: rateKgPerWeek, sex: input.sex)
        let bmiValue = bmi(weightKg: input.weightKg, heightCm: input.heightCm)

        let lbm: Double
        let estimated: Bool
        if let bf = input.bodyFatPercent {
            lbm = leanBodyMass(weightKg: input.weightKg, bodyFatPercent: bf); estimated = false
        } else {
            lbm = estimatedLeanBodyMass(weightKg: input.weightKg, heightCm: input.heightCm, sex: input.sex); estimated = true
        }

        return MetabolicProfile(
            formula: used,
            bmr: bmrValue,
            tdee: tdeeValue,
            targetCalories: target.calories,
            dailyEnergyDelta: target.calories - tdeeValue,
            macros: macros(calories: target.calories, weightKg: input.weightKg, heightCm: input.heightCm, goal: goal),
            bmi: bmiValue,
            bmiCategory: bmiCategory(bmiValue),
            leanBodyMassKg: lbm,
            leanMassIsEstimated: estimated,
            wasClampedToSafetyFloor: target.clamped
        )
    }
}
