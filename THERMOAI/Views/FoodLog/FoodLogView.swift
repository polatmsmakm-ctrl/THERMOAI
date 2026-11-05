//
//  FoodLogView.swift
//  THERMOAI — Views/FoodLog
//
//  Purpose: Daily food diary grouped by meal, with day navigation, swipe-to-
//           delete, duplicate-to-today and an "Add food" sheet.
//  Dependencies: SwiftUI, SwiftData, ViewModels/FoodLogViewModel.swift
//

import SwiftUI
import SwiftData

struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<FoodEntry> { !$0.isSoftDeleted }, sort: \FoodEntry.consumedAt) private var entries: [FoodEntry]
    @Query(filter: #Predicate<WeightEntry> { !$0.isSoftDeleted }) private var weights: [WeightEntry]

    @State private var vm: FoodLogViewModel
    @State private var showAdd = false

    init(env: AppEnvironment) {
        _vm = State(initialValue: FoodLogViewModel(ai: env.ai, health: env.health))
    }

    private var dayTotals: DailyTotals { MetricsCalculator.totals(for: vm.selectedDay, entries: entries) }
    private var target: Double {
        profiles.first.flatMap { MetricsCalculator.metabolicProfile(profile: $0, weights: weights)?.targetCalories } ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section { daySummary.listRowBackground(Color.clear).listRowInsets(EdgeInsets()) }

                ForEach(MealType.allCases) { meal in
                    let items = vm.entries(entries, for: meal)
                    Section {
                        if items.isEmpty {
                            Button { vm.draftMeal = meal; showAdd = true } label: {
                                Label("Add \(meal.title.lowercased())", systemImage: "plus.circle")
                                    .foregroundStyle(Theme.Colors.textTertiary)
                            }
                        }
                        ForEach(items) { entry in
                            FoodEntryRowView(entry: entry)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { withAnimation { vm.delete(entry, in: context) } } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    if !vm.isToday {
                                        Button { vm.duplicateToToday(entry, in: context) } label: {
                                            Label("Log today", systemImage: "plus.square.on.square")
                                        }
                                        .tint(Theme.Colors.accent)
                                    }
                                }
                        }
                    } header: {
                        HStack {
                            Label(meal.title, systemImage: meal.symbol)
                            Spacer()
                            Text("\(Int(items.reduce(0) { $0 + $1.calories })) kcal").monospacedDigit()
                        }
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .listRowBackground(Theme.Colors.surface)
                }
            }
            .listStyle(.insetGrouped)
            .thermoScreen()
            .navigationTitle("Diary")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("Add food")
                }
            }
            .sheet(isPresented: $showAdd) {
                AddFoodView(vm: vm, exportToHealth: profiles.first?.healthKitEnabled ?? false)
                    .presentationDetents([.large])
                    .presentationBackground(Theme.Colors.backgroundElevated)
            }
        }
    }

    private var daySummary: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Button { withAnimation { vm.shiftDay(by: -1) } } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous day")
                Spacer()
                Text(vm.isToday ? "Today" : vm.selectedDay.formatted(.dateTime.weekday(.wide).day().month()))
                    .font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                    .contentTransition(.opacity)
                Spacer()
                Button { withAnimation { vm.shiftDay(by: 1) } } label: { Image(systemName: "chevron.right") }
                    .disabled(vm.isToday)
                    .accessibilityLabel("Next day")
            }
            .font(.headline)
            .foregroundStyle(Theme.Colors.accent)

            ThermoCard {
                HStack(spacing: Theme.Spacing.lg) {
                    MacroDonutChart(proteinG: dayTotals.proteinG, carbsG: dayTotals.carbsG, fatG: dayTotals.fatG)
                        .frame(width: 92, height: 92)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text("\(Int(dayTotals.calories))").font(Theme.Typography.metric).foregroundStyle(Theme.Colors.textPrimary)
                            Text("/ \(Int(target)) kcal").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Text("P \(Int(dayTotals.proteinG))g · C \(Int(dayTotals.carbsG))g · F \(Int(dayTotals.fatG))g")
                            .font(Theme.Typography.caption.monospacedDigit()).foregroundStyle(Theme.Colors.textSecondary)
                        Text("TEF ≈ \(Int(dayTotals.tef.total)) kcal")
                            .font(.caption2).foregroundStyle(Theme.Colors.accentAmber)
                    }
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
    }
}

struct FoodEntryRowView: View {
    let entry: FoodEntry

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.name).font(Theme.Typography.body).foregroundStyle(Theme.Colors.textPrimary).lineLimit(1)
                    if entry.source == .aiPhoto || entry.source == .aiText {
                        Image(systemName: "sparkles").font(.caption2).foregroundStyle(Theme.Colors.accentAmber)
                            .accessibilityLabel("AI estimate")
                    }
                }
                Text([entry.servingDescription, "P \(Int(entry.proteinG)) · C \(Int(entry.carbsG)) · F \(Int(entry.fatG))"]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.Colors.textSecondary).lineLimit(1)
            }
            Spacer()
            Text("\(Int(entry.calories))").font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
