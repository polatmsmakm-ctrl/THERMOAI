//
//  AssistantViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Conversational AI nutrition assistant with personalised context.
//  Dependencies: Services/GeminiService.swift, Models/AIModels.swift
//

import Foundation
import Observation

@MainActor
@Observable
final class AssistantViewModel {
    struct Message: Identifiable, Equatable {
        let id = UUID()
        let role: ChatTurn.Role
        let text: String
        let date = Date()
    }

    private(set) var messages: [Message] = []
    private(set) var suggestions: [String] = [
        "How much protein should I eat?",
        "What is the thermic effect of food?",
        "Why has my weight plateaued?",
    ]
    private(set) var isThinking = false
    var input = ""
    var errorMessage: String?

    private let ai: any AIServicing
    static let maxMessageLength = 2000

    init(ai: any AIServicing) { self.ai = ai }

    var canSend: Bool {
        let t = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !t.isEmpty && t.count <= Self.maxMessageLength && !isThinking
    }

    func send(_ text: String? = nil, context: NutritionContext) async {
        let content = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isThinking else { return }
        input = ""
        errorMessage = nil
        messages.append(Message(role: .user, text: String(content.prefix(Self.maxMessageLength))))
        isThinking = true
        defer { isThinking = false }

        do {
            let history = messages.map { ChatTurn(role: $0.role, text: $0.text) }
            let reply = try await ai.chat(history: history, context: context)
            messages.append(Message(role: .assistant, text: reply.reply))
            suggestions = reply.suggestions
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clear() {
        messages = []
        errorMessage = nil
    }
}
