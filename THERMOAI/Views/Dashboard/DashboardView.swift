//
//  DashboardView.swift
//  THERMOAI — Views/Dashboard
//
//  Purpose: Premium "Today" dashboard — hero calorie ring (glass), macro rings,
//           energy breakdown (BMR / activity / TEF), 7-day chart, insight and
//           quick actions. Adaptive grid: 1 column iPhone, 2 columns iPad.
//  Dependencies: SwiftUI, SwiftData, ViewModels/DashboardViewModel.swift, DesignSystem
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Binding var selection: AppTab

    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<FoodEntry> { !$0.isSoftDeleted }, sort: \FoodEntry.consumedAt) private var entries: [FoodEntry]
    @Query(filter: #Predicate<WeightEntry> { !$0.isSoftDeleted }, sort: \WeightEntry.recordedAt) private var weights: [WeightEntry]

    @State private var vm: DashboardViewModel
    @State private var showPlans = false
    @State private var showCalculator = false
    @State private var showSettings = false

    init(env: AppEnvironment, selection: Binding<AppTab>) {
        _vm = State(initialValue: DashboardViewModel(health: env.health))
        _selection = selection
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.flexible(), spacing: Theme.Spacing.md), GridItem(.flexible(), spacing: Theme.Spacing.md)]
                              : [GridItem(.flexible())]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let profile = profiles.first, let snap = vm.snapshot {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        greeting(profile)
                        if let error = syncError { ErrorBanner(message: error) { Task { await env.sync?.syncNow() } } }
                        hero(snap)
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.md) {
                            energyCard(snap)
                            macroCard(snap)
                            weekCard(snap)
                            quickActions
                        }
                        if let insight = vm.insight { insightCard(insight) }
                    }
                    .padding(Theme.Spacing.md)
                    .frame(maxWidth: 1000)
                    .frame(maxWidth: .infinity)
                } else {
                    ProgressView().padding(.top, 120)
                }
            }
            .refreshable { await env.sync?.syncNow() }
            .thermoScreen()
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Meal Plans", systemImage: "fork.knife") { showPlans = true }
                        Button("Metabolic Calculator", systemImage: "function") { showCalculator = true }
                        Button("Settings", systemImage: "gearshape") { showSettings = true }
                    } label: {
                        Image(systemName: "ellipsis.circle").foregroundStyle(Theme.Colors.textPrimary)
                    }
                }
            }
            .navigationDestination(isPresented: $showPlans) { MealPlanView(env: env) }
            .navigationDestination(isPresented: $showCalculator) { MetabolicCalculatorView() }
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
        }
        .task(id: entries.count + weights.count) { recompute() }
        .task { await vm.loadActiveEnergy(enabled: profiles.first?.healthKitEnabled ?? false) }
        .onChange(of: profiles.first?.updatedAt) { _, _ in recompute() }
    }

    private var syncError: String? {
        if case .failed(let msg) = env.sync?.status { return msg }
        return nil
    }

    private func recompute() {
        guard let profile = profiles.first else { return }
        withAnimation(Theme.Motion.spring) { vm.refresh(profile: profile, entries: entries, weights: weights) }
    }

    // MARK: Sections

    private func greeting(_ profile: UserProfile) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(Theme.Typography.overline).tracking(1.2).foregroundStyle(Theme.Colors.accentAmber)
            Text(profile.displayName.isEmpty ? "Welcome back" : "Hi, \(profile.displayName)")
                .font(Theme.Typography.title).foregroundStyle(Theme.Colors.textPrimary)
        }
    }

    private func hero(_ snap: DashboardViewModel.Snapshot) -> some View {
        let target = snap.metabolic?.targetCalories ?? 0
        return GlassCard {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Spacing.xl) {
                    CalorieRing(consumed: snap.today.calories, target: target).frame(width: 220, height: 220)
                    heroStats(snap, target: target)
                }
                VStack(spacing: Theme.Spacing.lg) {
                    CalorieRing(consumed: snap.today.calories, target: target).frame(width: 220, height: 220)
                    heroStats(snap, target: target)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func heroStats(_ snap: DashboardViewModel.Snapshot, target: Double) -> some View {
        HStack(spacing: Theme.Spacing.lg) {
            heroStat("Eaten", Int(snap.today.calories), "fork.knife")
            heroStat("Target", Int(target), "scope")
            heroStat("Burned", Int(vm.activeEnergyToday), "figure.run")
        }
    }

    private func heroStat(_ title: String, _ value: Int, _ icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(Theme.Colors.accent)
            Text("\(value)").font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
                .contentTransition(.numericText(value: Double(value)))
            Text(title).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(minWidth: 64)
    }

    private func energyCard(_ snap: DashboardViewModel.Snapshot) -> some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Energy", subtitle: snap.metabolic.map { "BMR via \($0.formula.title)" })
                if let m = snap.metabolic {
                    let activity = m.tdee - m.bmr
                    EnergyStackBar(segments: [
                        .init(label: "BMR", value: m.bmr, color: Theme.Colors.accentDeep),
                        .init(label: "Activity", value: activity, color: Theme.Colors.accent),
                        .init(label: "TEF today", value: snap.tef.total, color: Theme.Colors.accentAmber),
                    ])
                    HStack {
                        metric("TDEE", "\(Int(m.tdee))")
                        Spacer()
                        metric(m.dailyEnergyDelta < 0 ? "Deficit" : m.dailyEnergyDelta > 0 ? "Surplus" : "Balance",
                               "\(Int(abs(m.dailyEnergyDelta)))")
                        Spacer()
                        metric("TEF", "\(Int(snap.tef.total))")
                    }
                } else {
                    Text("Add a weigh-in to calculate your energy needs.")
                        .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)
                }
            }
        }
    }

    private func macroCard(_ snap: DashboardViewModel.Snapshot) -> some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Macros")
                let m = snap.metabolic?.macros ?? .zero
                HStack {
                    MacroRing(title: "Protein", value: snap.today.proteinG, target: m.proteinG, color: Theme.Colors.protein)
                    Spacer()
                    MacroRing(title: "Carbs", value: snap.today.carbsG, target: m.carbsG, color: Theme.Colors.carbs)
                    Spacer()
                    MacroRing(title: "Fat", value: snap.today.fatG, target: m.fatG, color: Theme.Colors.fat)
                }
            }
        }
    }

    private func weekCard(_ snap: DashboardViewModel.Snapshot) -> some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "This week", subtitle: snap.streak > 0 ? "🔥 \(snap.streak)-day streak" : nil,
                              actionTitle: "Details") { selection = .progress }
                CalorieHistoryChart(days: snap.weekly, target: snap.metabolic?.targetCalories ?? 0, height: 160)
            }
        }
    }

    private var quickActions: some View {
        ThermoCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                SectionHeader(title: "Quick add")
                HStack(spacing: Theme.Spacing.sm) {
                    quickAction("Scan meal", "camera.fill") { selection = .scan }
                    quickAction("Log food", "plus") { selection = .diary }
                    quickAction("Ask coach", "sparkles") { selection = .coach }
                }
            }
        }
    }

    private func quickAction(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.Gradients.heat))
                Text(title).font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func insightCard(_ text: String) -> some View {
        ThermoCard {
            HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                Image(systemName: "lightbulb.max.fill").foregroundStyle(Theme.Colors.accentAmber)
                Text(text).font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textPrimary)
            }
        }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(Theme.Typography.metricSmall).foregroundStyle(Theme.Colors.textPrimary)
            Text(title).font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
        }
    }
}

/// Horizontal stacked bar showing how daily energy expenditure is composed.
struct EnergyStackBar: View {
    struct Segment: Identifiable { let id = UUID(); let label: String; let value: Double; let color: Color }
    let segments: [Segment]

    var body: some View {
        let total = max(segments.reduce(0) { $0 + max($1.value, 0) }, 1)
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(segments) { s in
                        RoundedRectangle(cornerRadius: 4).fill(s.color.gradient)
                            .frame(width: max(geo.size.width * max(s.value, 0) / total - 2, 0))
                    }
                }
            }
            .frame(height: 14)
            HStack(spacing: Theme.Spacing.md) {
                ForEach(segments) { s in
                    HStack(spacing: 4) {
                        Circle().fill(s.color).frame(width: 7, height: 7)
                        Text("\(s.label) \(Int(s.value))").font(.caption2).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}
