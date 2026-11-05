//
//  SettingsView.swift
//  THERMOAI — Views/Settings
//
//  Purpose: Profile & goal editing, BMR formula choice, Apple Health toggle,
//           subscription, sync status, sign-out and account deletion.
//           Navigation-agnostic (hosted in a NavigationStack by its parent).
//  Dependencies: SwiftUI, SwiftData, AppEnvironment, Services
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @State private var showPaywall = false
    @State private var confirmDelete = false
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            if let profile = profiles.first {
                ProfileSection(profile: profile)
                Section("Integrations") {
                    Toggle(isOn: Binding(
                        get: { profile.healthKitEnabled },
                        set: { newValue in
                            if newValue {
                                Task {
                                    do {
                                        try await env.health.requestAuthorization()
                                        profile.healthKitEnabled = true
                                    } catch {
                                        errorMessage = "Apple Health: \(error.localizedDescription)"
                                    }
                                }
                            } else {
                                profile.healthKitEnabled = false
                            }
                        })) {
                        Label("Apple Health", systemImage: "heart.fill")
                    }
                    .disabled(!env.health.isAvailable)
                }
                .listRowBackground(Theme.Colors.surface)
            }

            Section("THERMO AI Pro") {
                if env.isPro {
                    Label("Pro is active", systemImage: "checkmark.seal.fill").foregroundStyle(Theme.Colors.success)
                } else {
                    Button { showPaywall = true } label: { Label("Upgrade to Pro", systemImage: "flame.fill") }
                }
                Button("Restore purchases") { Task { await env.subscriptions.restorePurchases() } }
            }
            .listRowBackground(Theme.Colors.surface)

            Section("Account") {
                if let email = env.auth.session?.user.email {
                    LabeledContent("Email", value: email)
                }
                LabeledContent("Sync") { Text(syncDescription).foregroundStyle(Theme.Colors.textSecondary) }
                Button("Sync now") { Task { await env.sync?.syncNow() } }
                Button("Sign out") { Task { await env.auth.signOut() } }
                Button("Delete account", role: .destructive) { confirmDelete = true }
            }
            .listRowBackground(Theme.Colors.surface)

            Section {
                Text("THERMO AI provides estimates for general wellness. It is not a medical device and does not provide medical advice. Consult a healthcare professional before making significant dietary changes.")
                    .font(.caption).foregroundStyle(Theme.Colors.textTertiary)
            }
            .listRowBackground(Color.clear)

            if let errorMessage {
                Section { ErrorBanner(message: errorMessage) }.listRowBackground(Color.clear)
            }
        }
        .thermoScreen()
        .navigationTitle("Settings")
        .disabled(isWorking)
        .sheet(isPresented: $showPaywall) { PaywallView() }
        .confirmationDialog("Delete your account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account and all data", role: .destructive) {
                Task {
                    isWorking = true
                    defer { isWorking = false }
                    do { try await env.auth.deleteAccount() } catch { errorMessage = error.localizedDescription }
                }
            }
        } message: {
            Text("This permanently deletes your profile, food log, weigh-ins and meal plans. Active subscriptions must be cancelled in the App Store.")
        }
        .onDisappear { try? context.save() }
    }

    private var syncDescription: String {
        switch env.sync?.status {
        case .syncing: return "Syncing…"
        case .offline: return "Offline"
        case .failed: return "Failed"
        default:
            if let date = env.sync?.lastSyncedAt { return "Updated \(date.formatted(.relative(presentation: .named)))" }
            return "Not synced yet"
        }
    }
}

/// Editable profile fields. Every change marks the profile for sync.
private struct ProfileSection: View {
    @Bindable var profile: UserProfile

    var body: some View {
        Section("Profile") {
            TextField("Name", text: $profile.displayName).onChange(of: profile.displayName) { profile.touch() }
            Picker("Sex", selection: Binding(get: { profile.sex }, set: { profile.sex = $0; profile.touch() })) {
                ForEach(BiologicalSex.allCases) { Text($0.title).tag($0) }
            }
            DatePicker("Birth date", selection: Binding(get: { profile.birthDate }, set: { profile.birthDate = $0; profile.touch() }),
                       in: ...Calendar.current.date(byAdding: .year, value: -18, to: .now)!, displayedComponents: .date)
            NumericField(title: "Height", value: Binding(get: { profile.heightCm }, set: {
                profile.heightCm = min(max($0, 50), 272); profile.touch()
            }), unit: "cm", precision: 0)
            Toggle("Body fat known", isOn: Binding(get: { profile.bodyFatPercent != nil }, set: {
                profile.bodyFatPercent = $0 ? 20 : nil; profile.touch()
            }))
            if profile.bodyFatPercent != nil {
                NumericField(title: "Body fat", value: Binding(get: { profile.bodyFatPercent ?? 20 }, set: {
                    profile.bodyFatPercent = min(max($0, 2), 70); profile.touch()
                }), unit: "%")
            }
        }
        .listRowBackground(Theme.Colors.surface)

        Section("Goal & metabolism") {
            Picker("Activity", selection: Binding(get: { profile.activity }, set: { profile.activity = $0; profile.touch() })) {
                ForEach(ActivityLevel.allCases) { Text($0.title).tag($0) }
            }
            Picker("Goal", selection: Binding(get: { profile.goal }, set: { profile.goal = $0; profile.touch() })) {
                ForEach(WeightGoal.allCases) { Text($0.title).tag($0) }
            }
            if profile.goal != .maintain {
                VStack(alignment: .leading) {
                    Text("Rate: \(profile.goalRateKgPerWeek, specifier: "%.2f") kg/week")
                    Slider(value: Binding(get: { profile.goalRateKgPerWeek }, set: { profile.goalRateKgPerWeek = $0; profile.touch() }),
                           in: 0.1...(profile.goal == .lose ? 1.0 : 0.5), step: 0.05)
                }
                NumericField(title: "Target weight", value: Binding(get: { profile.targetWeightKg ?? 0 }, set: {
                    profile.targetWeightKg = $0 > 0 ? $0 : nil; profile.touch()
                }), unit: "kg")
            }
            Picker("BMR formula", selection: Binding(get: { profile.formula }, set: { profile.formula = $0; profile.touch() })) {
                ForEach(BMRFormula.allCases) { f in
                    VStack(alignment: .leading) { Text(f.title); Text(f.summary).font(.caption) }.tag(f)
                }
            }
            .pickerStyle(.navigationLink)
            if profile.formula == .katchMcArdle && profile.bodyFatPercent == nil {
                Text("Katch-McArdle needs body fat — using Mifflin-St Jeor until it's set.")
                    .font(.caption).foregroundStyle(Theme.Colors.warning)
            }
        }
        .listRowBackground(Theme.Colors.surface)
    }
}
