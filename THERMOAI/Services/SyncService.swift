//
//  SyncService.swift
//  THERMOAI — Services
//
//  Purpose: Offline-first synchronisation between SwiftData and Supabase.
//    1. PUSH: upsert every local row with `needsSync == true` (soft deletes included).
//    2. PULL: fetch rows whose server `updated_at` > last successful sync.
//    3. MERGE: last-write-wins — a server row overwrites a local row unless the
//       local row is still dirty and newer.
//  Dependencies: SwiftData, Networking/SupabaseClient.swift, Networking/SyncDTOs.swift,
//                Models/PersistentModels.swift
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class SyncService {
    enum Status: Equatable { case idle, syncing, failed(String), offline }

    private(set) var status: Status = .idle
    private(set) var lastSyncedAt: Date?
    private(set) var isPro = false

    private let context: ModelContext
    private let client: SupabaseClient
    private let userID: UUID
    private let defaults: UserDefaults

    /// Pull window overlap that tolerates small clock skew.
    private static let skew: TimeInterval = 120

    init(context: ModelContext, client: SupabaseClient, userID: UUID, defaults: UserDefaults = .standard) {
        self.context = context
        self.client = client
        self.userID = userID
        self.defaults = defaults
        self.lastSyncedAt = defaults.object(forKey: lastSyncKey) as? Date
    }

    private var lastSyncKey: String { "thermoai.sync.last.\(userID.uuidString)" }

    // MARK: Public

    func syncNow() async {
        guard status != .syncing else { return }
        status = .syncing
        let started = Date()
        do {
            try await pushProfile()
            try await pushFood()
            try await pushWeights()
            try await pushPlans()

            let since = (lastSyncedAt ?? .distantPast).addingTimeInterval(-Self.skew)
            try await pullProfile()
            try await pullFood(since: since)
            try await pullWeights(since: since)
            try await pullPlans(since: since)

            try context.save()
            lastSyncedAt = started
            defaults.set(started, forKey: lastSyncKey)
            status = .idle
        } catch APIError.offline {
            status = .offline
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    // MARK: Push

    private func pushProfile() async throws {
        guard let profile = try context.fetch(FetchDescriptor<UserProfile>()).first,
              profile.needsSync, profile.onboardingCompleted else { return }
        try await client.update("profiles", id: userID, fields: ProfileUpdate(profile))
        profile.needsSync = false
    }

    private func pushFood() async throws {
        let dirty = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.needsSync }))
        for batch in dirty.chunked(into: 200) {
            try await client.upsert("food_entries", rows: batch.map { FoodEntryRow($0, userID: userID) })
            batch.forEach { $0.needsSync = false }
        }
    }

    private func pushWeights() async throws {
        let dirty = try context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.needsSync }))
        for batch in dirty.chunked(into: 200) {
            try await client.upsert("weight_entries", rows: batch.map { WeightEntryRow($0, userID: userID) })
            batch.forEach { $0.needsSync = false }
        }
    }

    private func pushPlans() async throws {
        let dirty = try context.fetch(FetchDescriptor<SavedMealPlan>(predicate: #Predicate { $0.needsSync }))
        let rows: [MealPlanRow] = dirty.compactMap { p in
            guard let plan = p.plan else { return nil }
            return MealPlanRow(id: p.id, userId: userID, title: p.title, targetKcal: p.targetCalories,
                               plan: plan, isDeleted: p.isSoftDeleted, createdAt: nil, updatedAt: nil)
        }
        try await client.upsert("meal_plans", rows: rows)
        dirty.forEach { $0.needsSync = false }
    }

    // MARK: Pull

    private func pullProfile() async throws {
        let rows: [ProfileRow] = try await client.select("profiles", query: [
            URLQueryItem(name: "id", value: "eq.\(userID.uuidString.lowercased())"),
            URLQueryItem(name: "select", value: "*"),
        ])
        guard let row = rows.first else { return }
        isPro = row.isPro ?? false

        let local = try context.fetch(FetchDescriptor<UserProfile>()).first
        // Never overwrite unsynced local edits; seed a new device from the server.
        if let local, local.needsSync { return }
        guard let sex = row.sex, let height = row.heightCm,
              let birth = row.birthDate.flatMap(JSONCoding.parseDate) else { return }

        let profile = local ?? {
            let p = UserProfile(id: userID)
            context.insert(p)
            return p
        }()
        profile.displayName = row.displayName
        profile.sex = sex
        profile.birthDate = birth
        profile.heightCm = height
        profile.activity = row.activityLevel
        profile.goal = row.goal
        profile.goalRateKgPerWeek = row.goalRateKgWeek
        profile.bodyFatPercent = row.bodyFatPercent
        profile.formula = row.bmrFormula
        profile.onboardingCompleted = true
        profile.needsSync = false
    }

    private func changedQuery(since: Date) -> [URLQueryItem] {
        let iso = ISO8601DateFormatter().string(from: since)
        return [URLQueryItem(name: "updated_at", value: "gt.\(iso)"),
                URLQueryItem(name: "select", value: "*"),
                URLQueryItem(name: "order", value: "updated_at.asc"),
                URLQueryItem(name: "limit", value: "1000")]
    }

    private func pullFood(since: Date) async throws {
        let rows: [FoodEntryRow] = try await client.select("food_entries", query: changedQuery(since: since))
        for row in rows {
            let id = row.id
            let existing = try context.fetch(FetchDescriptor<FoodEntry>(predicate: #Predicate { $0.id == id })).first
            if let existing {
                if existing.needsSync, existing.updatedAt > (row.updatedAt ?? .distantPast) { continue }
                row.apply(to: existing)
            } else if !row.isDeleted {
                let entry = FoodEntry(id: row.id, mealType: row.mealType, name: row.name, calories: row.calories,
                                      proteinG: row.proteinG, carbsG: row.carbsG, fatG: row.fatG)
                row.apply(to: entry)
                context.insert(entry)
            }
        }
    }

    private func pullWeights(since: Date) async throws {
        let rows: [WeightEntryRow] = try await client.select("weight_entries", query: changedQuery(since: since))
        for row in rows {
            let id = row.id
            let existing = try context.fetch(FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.id == id })).first
            if let existing {
                if existing.needsSync, existing.updatedAt > (row.updatedAt ?? .distantPast) { continue }
                row.apply(to: existing)
            } else if !row.isDeleted {
                let entry = WeightEntry(id: row.id, weightKg: row.weightKg)
                row.apply(to: entry)
                context.insert(entry)
            }
        }
    }

    private func pullPlans(since: Date) async throws {
        let rows: [MealPlanRow] = try await client.select("meal_plans", query: changedQuery(since: since))
        for row in rows {
            let id = row.id
            let existing = try context.fetch(FetchDescriptor<SavedMealPlan>(predicate: #Predicate { $0.id == id })).first
            if let existing {
                if existing.needsSync { continue }
                existing.isSoftDeleted = row.isDeleted
                existing.title = row.title
                existing.planData = (try? JSONEncoder().encode(row.plan)) ?? existing.planData
                existing.needsSync = false
            } else if !row.isDeleted, let saved = try? SavedMealPlan(id: row.id, title: row.title,
                                                                      targetCalories: row.targetKcal, plan: row.plan) {
                saved.createdAt = row.createdAt ?? .now
                saved.needsSync = false
                context.insert(saved)
            }
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
