//
//  AIAndNetworkingTests.swift
//  THERMOAITests
//
//  Purpose: Client-side AI response validation, DTO decoding (matches the
//           Edge Function contract), date parsing and request encoding.
//  Dependencies: Swift Testing, @testable THERMOAI
//

import Foundation
import Testing
@testable import THERMOAI

@Suite("AI response validation")
struct AIResponseValidatorTests {
    private func item(calories: Double, p: Double, c: Double, f: Double, confidence: Double = 0.9) -> AnalyzedFoodItem {
        AnalyzedFoodItem(name: "Test", portionDescription: "1", estimatedGrams: 100, calories: calories,
                         proteinG: p, carbsG: c, fatG: f, fiberG: 0, confidence: confidence)
    }

    @Test func acceptsConsistentItem() throws {
        let validated = try AIResponseValidator.validate(item(calories: 170, p: 10, c: 10, f: 10))
        #expect(validated.calories == 170)
        #expect(validated.confidence == 0.9)
    }

    @Test func correctsInconsistentCalories() throws {
        let validated = try AIResponseValidator.validate(item(calories: 50, p: 10, c: 10, f: 10))
        #expect(validated.calories == 170)
        #expect(validated.confidence == 0.5)
    }

    @Test func rejectsNegativeValues() {
        #expect(throws: AIValidationError.invalidNumber("protein")) {
            try AIResponseValidator.validate(item(calories: 100, p: -1, c: 10, f: 1))
        }
    }

    @Test func rejectsNonFood() {
        let result = FoodAnalysisResult(isFood: false, items: [], notes: "A dog")
        #expect(throws: AIServiceError.notFood) { try AIResponseValidator.validate(result) }
    }

    @Test func clampsConfidence() throws {
        #expect(try AIResponseValidator.validate(item(calories: 170, p: 10, c: 10, f: 10, confidence: 4)).confidence == 1)
    }

    @Test func chatReplyTrimmedAndSuggestionsCapped() throws {
        let reply = try AIResponseValidator.validate(ChatReply(reply: "  Hello  ", suggestions: ["a", "b", "c", "d"]))
        #expect(reply.reply == "Hello")
        #expect(reply.suggestions.count == 3)
        #expect(throws: AIValidationError.emptyReply) { try AIResponseValidator.validate(ChatReply(reply: " ", suggestions: [])) }
    }

    @Test func portionScaling() {
        let scaled = item(calories: 200, p: 10, c: 20, f: 8).scaled(toGrams: 150)
        #expect(scaled.estimatedGrams == 150)
        #expect(scaled.calories == 300)
        #expect(scaled.proteinG == 15)
    }
}

@Suite("Networking & DTOs")
struct NetworkingTests {
    @Test func decodesEdgeFunctionFoodResponse() throws {
        let json = """
        {"isFood":true,"items":[{"name":"Rice","portionDescription":"1 cup","estimatedGrams":158,
         "calories":205,"proteinG":4.3,"carbsG":44.5,"fatG":0.4,"fiberG":0.6,"confidence":0.9}],"notes":""}
        """
        let result = try JSONCoding.decoder().decode(FoodAnalysisResult.self, from: Data(json.utf8))
        #expect(result.items.first?.name == "Rice")
        #expect(result.totalCalories == 205)
    }

    @Test func decodesMealPlanResponse() throws {
        let json = """
        {"title":"Plan","notes":"","days":[{"dayIndex":1,"totalCalories":500,"calorieDeviation":0.01,
         "meals":[{"mealType":"breakfast","name":"Oats","description":"","ingredients":["oats"],
         "calories":500,"proteinG":20,"carbsG":80,"fatG":10}]}]}
        """
        let plan = try JSONCoding.decoder().decode(MealPlanResponse.self, from: Data(json.utf8))
        #expect(plan.days.first?.meals.first?.mealType == .breakfast)
    }

    @Test(arguments: ["2026-11-05T05:22:00.123456+00:00", "2026-11-05T05:22:00Z", "2026-11-05T05:22:00.123Z"])
    func parsesPostgresTimestamps(_ value: String) {
        #expect(JSONCoding.parseDate(value) != nil)
    }

    @Test func parsesDateOnly() {
        let date = JSONCoding.parseDate("1990-04-15")
        #expect(date != nil)
        #expect(JSONCoding.dateOnlyString(date!) == "1990-04-15")
    }

    @Test func encodesAIRequestWithoutNulls() throws {
        let data = try JSONCoding.encoder().encode(AIRequest(task: .analyzeFoodText, description: "2 eggs"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["task"] as? String == "analyzeFoodText")
        #expect(object["description"] as? String == "2 eggs")
        #expect(object["imageBase64"] == nil)
    }

    @Test func foodRowEncodesSnakeCaseAndOmitsUpdatedAt() throws {
        let row = FoodEntryRow(id: UUID(), userId: UUID(), consumedAt: .now, mealType: .lunch, name: "X", servingDesc: "",
                               grams: 1, calories: 1, proteinG: 1, carbsG: 1, fatG: 1, fiberG: 0, source: .manual,
                               aiConfidence: nil, isDeleted: false, updatedAt: .now)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONCoding.encoder().encode(row)) as? [String: Any])
        #expect(object["protein_g"] != nil)
        #expect(object["meal_type"] as? String == "lunch")
        #expect(object["updated_at"] == nil)
        #expect(object.keys.contains("ai_confidence"))   // explicit null
    }

    @Test func apiErrorRetryability() {
        #expect(APIError.timeout.isRetryable)
        #expect(APIError.server(status: 503, code: nil, message: "").isRetryable)
        #expect(!APIError.unauthorized.isRetryable)
        #expect(!APIError.quotaExceeded.isRetryable)
    }

    @Test func chunking() {
        #expect(Array(0..<450).chunked(into: 200).map(\.count) == [200, 200, 50])
    }
}
