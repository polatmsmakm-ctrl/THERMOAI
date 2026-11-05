//
//  GeminiService.swift
//  THERMOAI — Services
//
//  Purpose: Client for all AI features. Talks ONLY to the `gemini-proxy` Edge
//           Function — the Gemini API key never exists on device. Applies a
//           second, client-side validation pass to every structured response.
//  Dependencies: Networking/SupabaseClient.swift, Models/AIModels.swift,
//                Services/AIResponseValidator.swift
//

import Foundation

/// Abstraction so view models can be tested with a mock.
protocol AIServicing: Sendable {
    func analyzeFood(imageJPEG: Data, note: String?) async throws -> FoodAnalysisResult
    func analyzeFood(description: String) async throws -> FoodAnalysisResult
    func chat(history: [ChatTurn], context: NutritionContext) async throws -> ChatReply
    func mealPlan(targets: MacroTargets, preferences: MealPreferences, days: Int) async throws -> MealPlanResponse
}

enum AIServiceError: Error, LocalizedError, Equatable {
    case notFood
    case emptyInput
    case imageTooLarge

    var errorDescription: String? {
        switch self {
        case .notFood: "We couldn't find any food in that photo. Try a closer, well-lit shot."
        case .emptyInput: "Describe what you ate first."
        case .imageTooLarge: "That image is too large to analyse."
        }
    }
}

struct GeminiService: AIServicing {
    private let client: SupabaseClient
    private static let functionName = "gemini-proxy"
    private static let maxImageBytes = 4 * 1024 * 1024

    init(client: SupabaseClient) {
        self.client = client
    }

    func analyzeFood(imageJPEG: Data, note: String?) async throws -> FoodAnalysisResult {
        guard imageJPEG.count <= Self.maxImageBytes else { throw AIServiceError.imageTooLarge }
        let request = AIRequest(task: .analyzeFoodImage,
                                imageBase64: imageJPEG.base64EncodedString(),
                                mimeType: "image/jpeg",
                                note: note?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty)
        let result: FoodAnalysisResult = try await client.invoke(Self.functionName, body: request, timeout: 90)
        return try AIResponseValidator.validate(result)
    }

    func analyzeFood(description: String) async throws -> FoodAnalysisResult {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AIServiceError.emptyInput }
        let request = AIRequest(task: .analyzeFoodText, description: trimmed)
        let result: FoodAnalysisResult = try await client.invoke(Self.functionName, body: request)
        return try AIResponseValidator.validate(result)
    }

    func chat(history: [ChatTurn], context: NutritionContext) async throws -> ChatReply {
        let request = AIRequest(task: .chat, messages: Array(history.suffix(40)), context: context)
        let reply: ChatReply = try await client.invoke(Self.functionName, body: request)
        return try AIResponseValidator.validate(reply)
    }

    func mealPlan(targets: MacroTargets, preferences: MealPreferences, days: Int) async throws -> MealPlanResponse {
        let request = AIRequest(task: .mealPlan, targets: targets, preferences: preferences, days: min(max(days, 1), 7))
        let plan: MealPlanResponse = try await client.invoke(Self.functionName, body: request, timeout: 120)
        return try AIResponseValidator.validate(plan)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
