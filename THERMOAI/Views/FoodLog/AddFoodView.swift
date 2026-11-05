//
//  AddFoodView.swift
//  THERMOAI — Views/FoodLog
//
//  Purpose: Add food via natural-language AI description ("2 eggs and toast")
//           or manual macro entry.
//  Dependencies: SwiftUI, SwiftData, ViewModels/FoodLogViewModel.swift
//

import SwiftUI
import SwiftData

struct AddFoodView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var vm: FoodLogViewModel
    let exportToHealth: Bool

    enum Mode: String, CaseIterable { case describe = "Describe", manual = "Manual" }
    @State private var mode: Mode = .describe

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    Picker("Mode", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue) }
                    }
                    .pickerStyle(.segmented)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(MealType.allCases) { meal in
                                SelectableChip(title: meal.title, systemImage: meal.symbol, isSelected: vm.draftMeal == meal) {
                                    vm.draftMeal = meal
                                }
                            }
                        }
                    }

                    if mode == .describe { describeSection } else { manualSection }
                    if let error = vm.errorMessage { ErrorBanner(message: error) }
                }
                .padding(Theme.Spacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Add food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .animation(Theme.Motion.spring, value: mode)
            .animation(Theme.Motion.spring, value: vm.textResult)
        }
    }

    // MARK: Describe (AI)

    private var describeSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ThermoCard {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label("Describe your meal", systemImage: "sparkles")
                        .font(Theme.Typography.headline).foregroundStyle(Theme.Colors.accentAmber)
                    TextField("e.g. Chicken shawarma wrap with garlic sauce and a small fries",
                              text: $vm.aiDescription, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundStyle(Theme.Colors.textPrimary)
                }
            }
            LoadingButton(title: "Analyze", systemImage: "wand.and.stars", isLoading: vm.isAnalyzingText) {
                Task { await vm.analyzeDescription() }
            }
            .disabled(vm.aiDescription.trimmingCharacters(in: .whitespaces).isEmpty)

            if let result = vm.textResult {
                AnalysisResultCard(items: result.items, notes: result.notes)
                Button("Add \(Int(result.totalCalories)) kcal to \(vm.draftMeal.title)") {
                    vm.saveTextResult(in: context, exportToHealth: exportToHealth)
                    dismiss()
                }
                .buttonStyle(.thermoPrimary)
            }
        }
    }

    // MARK: Manual

    private var manualSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            ThermoCard {
                VStack(spacing: Theme.Spacing.sm) {
                    TextField("Food name", text: $vm.draftName)
                        .font(Theme.Typography.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Divider().overlay(Theme.Colors.stroke)
                    NumericField(title: "Calories", value: $vm.draftCalories, unit: "kcal", precision: 0)
                    NumericField(title: "Protein", value: $vm.draftProtein, unit: "g")
                    NumericField(title: "Carbs", value: $vm.draftCarbs, unit: "g")
                    NumericField(title: "Fat", value: $vm.draftFat, unit: "g")
                    NumericField(title: "Weight", value: $vm.draftGrams, unit: "g", precision: 0)
                }
            }
            if vm.draftDerivedCalories > 0, abs(vm.draftDerivedCalories - vm.draftCalories) > max(vm.draftCalories * 0.2, 30) {
                Button {
                    vm.draftCalories = vm.draftDerivedCalories.rounded()
                } label: {
                    Label("Macros suggest \(Int(vm.draftDerivedCalories)) kcal — use that?", systemImage: "function")
                        .font(Theme.Typography.caption)
                }
                .foregroundStyle(Theme.Colors.accentAmber)
            }
            Button("Save") {
                vm.saveDraft(in: context, exportToHealth: exportToHealth)
                if vm.errorMessage == nil { dismiss() }
            }
            .buttonStyle(.thermoPrimary)
            .disabled(!vm.draftIsValid)
        }
    }
}

/// Shared list of AI-detected items (used by text and photo analysis).
struct AnalysisResultCard: View {
    let items: [AnalyzedFoodItem]
    let notes: String

    var body: some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                ForEach(items) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(item.portionDescription) · \(Int(item.estimatedGrams)) g")
                                .font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                            ConfidenceBadge(confidence: item.confidence)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(Int(item.calories)) kcal").font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                            Text("P \(Int(item.proteinG)) · C \(Int(item.carbsG)) · F \(Int(item.fatG))")
                                .font(.caption2.monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    if item != items.last { Divider().overlay(Theme.Colors.stroke) }
                }
                if !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(Theme.Colors.textTertiary).padding(.top, 4)
                }
            }
        }
    }
}
