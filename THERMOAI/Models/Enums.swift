//
//  Enums.swift
//  THERMOAI — Models
//
//  Purpose: Domain enums shared by the calculation engine, SwiftData models,
//           networking DTOs and UI. Raw values match the Postgres enums in
//           backend/supabase/migrations/20261105000001_initial_schema.sql.
//  Dependencies: Foundation
//

import Foundation

public enum BiologicalSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case male, female
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

public enum ActivityLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case sedentary, light, moderate, active, veryActive

    public var id: String { rawValue }

    /// Physical activity level multipliers (McArdle et al.).
    public var multiplier: Double {
        switch self {
        case .sedentary:  1.2
        case .light:      1.375
        case .moderate:   1.55
        case .active:     1.725
        case .veryActive: 1.9
        }
    }

    public var title: String {
        switch self {
        case .sedentary:  "Sedentary"
        case .light:      "Lightly active"
        case .moderate:   "Moderately active"
        case .active:     "Very active"
        case .veryActive: "Athlete"
        }
    }

    public var detail: String {
        switch self {
        case .sedentary:  "Desk job, little exercise"
        case .light:      "Exercise 1–3 days/week"
        case .moderate:   "Exercise 3–5 days/week"
        case .active:     "Hard exercise 6–7 days/week"
        case .veryActive: "Physical job or twice-daily training"
        }
    }
}

public enum WeightGoal: String, Codable, CaseIterable, Identifiable, Sendable {
    case lose, maintain, gain
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .lose: "Lose weight"
        case .maintain: "Maintain"
        case .gain: "Build muscle"
        }
    }
    public var symbol: String {
        switch self {
        case .lose: "arrow.down.right"
        case .maintain: "equal"
        case .gain: "arrow.up.right"
        }
    }
}

public enum BMRFormula: String, Codable, CaseIterable, Identifiable, Sendable {
    case mifflinStJeor, harrisBenedictRevised, katchMcArdle
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .mifflinStJeor: "Mifflin-St Jeor"
        case .harrisBenedictRevised: "Harris-Benedict (Revised)"
        case .katchMcArdle: "Katch-McArdle"
        }
    }
    public var summary: String {
        switch self {
        case .mifflinStJeor: "Most accurate for the general population."
        case .harrisBenedictRevised: "Classic equation, revised 1984."
        case .katchMcArdle: "Uses lean body mass; best when body fat is known."
        }
    }
}

public enum MealType: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var symbol: String {
        switch self {
        case .breakfast: "sunrise.fill"
        case .lunch: "sun.max.fill"
        case .dinner: "moon.stars.fill"
        case .snack: "leaf.fill"
        }
    }

    /// Sensible default based on time of day.
    public static func suggested(for date: Date = .now, calendar: Calendar = .current) -> MealType {
        switch calendar.component(.hour, from: date) {
        case 4..<11: .breakfast
        case 11..<16: .lunch
        case 16..<22: .dinner
        default: .snack
        }
    }
}

public enum EntrySource: String, Codable, CaseIterable, Sendable {
    case manual, aiPhoto, aiText, mealPlan, healthKit
}
