//
//  MealPlanView.swift
//  THERMOAI — Views/MealPlan
//
//  Purpose: AI meal planning — preferences form, generated plan by day with
//           per-meal macros, one-tap logging, saving and saved-plan history.
//           Navigation-agnostic (hosted in a NavigationStack by its parent).
//  Dependencies: SwiftUI, SwiftData, ViewModels/MealPlanViewModel.swift
//

import SwiftUI
import SwiftData

struct MealPlanView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<WeightEntry> { !$0.isSoftDeleted }) private var weights: [WeightEntry]
    @Query(filter: #Predicate<SavedMealPlan> { !$0.isSoftDeleted }, sort: \SavedMealPlan.createdAt, order: .reverse)
    private var savedPlans: [SavedMealPlan]

    @State private var vm: MealPlanViewModel
    @State private var log: FoodLogViewModel
    @State private var showPaywall = false
    @State private var loggedMealIDs: Set<String> = []

    init(env: AppEnvironment) {
        _vm = State(initialValue: MealPlanViewModel(ai: env.ai))
        _log = State(initialValue: FoodLogViewModel(ai: env.ai, health: env.health))
    }

    private var targets: MacroTargets? {
        profiles.first.flatMap { MetricsCalculator.metabolicProfile(profile: $0, weights: weights)?.macros }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                if let targets { targetsCard(targets) }
                preferencesCard
                if let error = vm.errorMessage {
                    ErrorBanner(message: error)
                    if error.contains("Pro") || error == APIError.quotaExceeded.errorDescription {
                        Button("See Pro") { showPaywall = true }.buttonStyle(.thermoSecondary)
                    }
                }
                LoadingButton(title: vm.plan == nil ? "Generate plan" : "Regenerate", systemImage: "wand.and.stars",
                              isLoading: vm.isGenerating) {
                    guard let targets else { return }
                    Task { await vm.generate(targets: targets, isPro: env.isPro) }
                }
                .disabled(targets == nil)

                if let plan = vm.plan { planSection(plan) }
                if !savedPlans.isEmpty { savedSection }
            }
            .padding(Theme.Spacing.md)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .thermoScreen()
        .navigationTitle("Meal Plans")
        .animation(Theme.Motion.spring, value: vm.plan)
        .sheet(isPresented: $showPaywall) { PaywallView() }
    }

    // MARK: Sections

    private func targetsCard(_ t: MacroTargets) -> some View {
        GlassCard(padding: Theme.Spacing.md) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Daily target").font(Theme.Typography.overline).textCase(.uppercase).foregroundStyle(Theme.Colors.accentAmber)
                    Text("\(Int(t.calories)) kcal").font(Theme.Typography.title2).foregroundStyle(Theme.Colors.textPrimary)
                }
                Spacer()
                Text("P \(Int(t.proteinG)) · C \(Int(t.carbsG)) · F \(Int(t.fatG))")
                    .font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private var preferencesCard: some View {
        @Bindable var vm = vm
        return ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("Diet").font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(MealPlanViewModel.diets, id: \.self) { diet in
                            SelectableChip(title: diet.capitalized, isSelected: vm.preferences.diet == diet) {
                                vm.preferences.diet = diet
                            }
                        }
                    }
                }
                TextField("Allergies (comma separated)", text: $vm.allergiesText)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Divider().overlay(Theme.Colors.stroke)
                TextField("Foods you dislike", text: $vm.dislikesText)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Divider().overlay(Theme.Colors.stroke)
                Stepper("Days: \(vm.days)\(vm.days > 1 && !env.isPro ? "  (Pro)" : "")", value: $vm.days, in: 1...7)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
    }

    private func planSection(_ plan: MealPlanResponse) -> some View {
        @Bindable var vm = vm
        return VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: plan.title, subtitle: plan.notes.isEmpty ? nil : plan.notes, actionTitle: "Save") {
                vm.save(in: context, targetCalories: targets?.calories ?? 0)
            }
            if plan.days.count > 1 {
                Picker("Day", selection: $vm.selectedDay) {
                    ForEach(plan.days) { Text("Day \($0.dayIndex)").tag($0.dayIndex) }
                }
                .pickerStyle(.segmented)
            }
            if let day = vm.currentDay {
                HStack {
                    Text("\(Int(day.totalCalories)) kcal").font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                    Text(String(format: "%+.1f%% vs target", day.calorieDeviation * 100))
                        .font(.caption).foregroundStyle(abs(day.calorieDeviation) <= 0.05 ? Theme.Colors.success : Theme.Colors.warning)
                }
                ForEach(day.meals) { meal in mealCard(meal) }
            }
        }
    }

    private func mealCard(_ meal: PlannedMeal) -> some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack {
                    Label(meal.mealType.title, systemImage: meal.mealType.symbol)
                        .font(Theme.Typography.overline).textCase(.uppercase).foregroundStyle(Theme.Colors.accentAmber)
                    Spacer()
                    Text("\(Int(meal.calories)) kcal").font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                }
                Text(meal.name).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                Text(meal.description).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                DisclosureGroup("Ingredients") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(meal.ingredients, id: \.self) { Text("• \($0)").font(.caption) }
                    }
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(Theme.Typography.caption)
                .tint(Theme.Colors.accent)
                HStack {
                    Text("P \(Int(meal.proteinG)) · C \(Int(meal.carbsG)) · F \(Int(meal.fatG))")
                        .font(.caption.monospacedDigit()).foregroundStyle(Theme.Colors.textTertiary)
                    Spacer()
                    let logged = loggedMealIDs.contains(meal.id)
                    Button(logged ? "Logged" : "Log meal", systemImage: logged ? "checkmark" : "plus") {
                        vm.log(meal, using: log, in: context, exportToHealth: profiles.first?.healthKitEnabled ?? false)
                        loggedMealIDs.insert(meal.id)
                    }
                    .font(Theme.Typography.caption.weight(.semibold))
                    .foregroundStyle(logged ? Theme.Colors.success : Theme.Colors.accent)
                    .disabled(logged)
                    .sensoryFeedback(.success, trigger: logged)
                }
            }
        }
    }

    private var savedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: "Saved plans")
            ForEach(savedPlans) { saved in
                Button { vm.load(saved) } label: {
                    ThermoCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(saved.title).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                                Text("\(Int(saved.targetCalories)) kcal · \(saved.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption).foregroundStyle(Theme.Colors.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.Colors.textTertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        saved.softDelete()
                        try? context.save()
                    }
                }
            }
        }
    }
}
