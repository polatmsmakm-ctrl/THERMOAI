//
//  ScannerViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: State machine for AI photo recognition:
//    idle → precheck (on-device Vision) → analyzing (Gemini via backend)
//         → review (user can adjust portions) → saved
//  Dependencies: UIKit, SwiftData, Services/ImageProcessor.swift, Services/GeminiService.swift,
//                ViewModels/FoodLogViewModel.swift (entry mapping)
//

import UIKit
import SwiftData
import Observation

@MainActor
@Observable
final class ScannerViewModel {
    enum Phase: Equatable {
        case idle
        case checking
        case analyzing
        case review
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var capturedImage: UIImage?
    var items: [AnalyzedFoodItem] = []
    var notes = ""
    var userNote = ""
    var mealType: MealType = .suggested()
    var skipFoodCheck = false

    /// Below this on-device score the user is asked to confirm before using AI quota.
    static let foodLikelihoodThreshold = 0.15

    private let ai: any AIServicing
    private var analysisTask: Task<Void, Never>?

    init(ai: any AIServicing) { self.ai = ai }

    var totalCalories: Double { items.reduce(0) { $0 + $1.calories } }
    var totalProtein: Double { items.reduce(0) { $0 + $1.proteinG } }
    var totalCarbs: Double { items.reduce(0) { $0 + $1.carbsG } }
    var totalFat: Double { items.reduce(0) { $0 + $1.fatG } }

    func analyze(_ image: UIImage) {
        analysisTask?.cancel()
        capturedImage = image
        analysisTask = Task { await runAnalysis(image) }
    }

    func retry() {
        guard let capturedImage else { phase = .idle; return }
        skipFoodCheck = true
        analyze(capturedImage)
    }

    func cancel() {
        analysisTask?.cancel()
        reset()
    }

    func reset() {
        phase = .idle
        capturedImage = nil
        items = []
        notes = ""
        userNote = ""
        skipFoodCheck = false
    }

    /// User corrected a portion — rescale nutrients proportionally.
    func updateGrams(for item: AnalyzedFoodItem, to grams: Double) {
        guard let idx = items.firstIndex(of: item) else { return }
        items[idx] = item.scaled(toGrams: grams)
    }

    func remove(_ item: AnalyzedFoodItem) {
        items.removeAll { $0 == item }
    }

    func save(using log: FoodLogViewModel, in context: ModelContext, exportToHealth: Bool) {
        let entries = FoodLogViewModel.entries(from: items, meal: mealType, at: .now, source: .aiPhoto)
        log.insert(entries, in: context, exportToHealth: exportToHealth)
        reset()
    }

    // MARK: Private

    private func runAnalysis(_ image: UIImage) async {
        do {
            if !skipFoodCheck {
                phase = .checking
                let likelihood = await ImageProcessor.foodLikelihood(of: image)
                guard !Task.isCancelled else { return }
                if likelihood < Self.foodLikelihoodThreshold {
                    phase = .failed("This doesn't look like food. Tap Retry to analyse anyway.")
                    return
                }
            }
            phase = .analyzing
            let jpeg = try ImageProcessor.preparedJPEG(from: image)
            let result = try await ai.analyzeFood(imageJPEG: jpeg, note: userNote)
            guard !Task.isCancelled else { return }
            items = result.items
            notes = result.notes
            phase = .review
        } catch is CancellationError {
            return
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
