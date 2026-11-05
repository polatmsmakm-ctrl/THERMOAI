//
//  AppEnvironment.swift
//  THERMOAI — App
//
//  Purpose: Composition root / dependency container. Builds every service once
//           and is injected into SwiftUI with `.environment(_:)`.
//  Dependencies: Config/AppConfig.swift, all Services, Networking/SupabaseClient.swift
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class AppEnvironment {
    let config: AppConfig
    let auth: AuthService
    let subscriptions: SubscriptionService
    let health: any HealthServicing
    let ai: any AIServicing
    let supabase: SupabaseClient
    let container: ModelContainer

    /// Created after sign-in (needs the user ID).
    private(set) var sync: SyncService?

    /// Non-nil when configuration failed (shown on a blocking error screen).
    let configurationError: String?

    init(container: ModelContainer) {
        let loaded: AppConfig
        var configError: String?
        do {
            loaded = try AppConfig.load()
        } catch {
            loaded = .preview
            configError = error.localizedDescription
        }
        self.config = loaded
        self.configurationError = configError
        self.container = container

        let http = HTTPClient()
        let auth = AuthService(config: loaded, http: http)
        self.auth = auth
        let client = SupabaseClient(config: loaded, http: http) { try await auth.validAccessToken() }
        self.supabase = client
        self.ai = GeminiService(client: client)
        self.health = HealthKitService()
        self.subscriptions = SubscriptionService(config: loaded)
    }

    /// Test / preview initialiser with injectable services.
    init(config: AppConfig, auth: AuthService, ai: any AIServicing, health: any HealthServicing, container: ModelContainer) {
        self.config = config
        self.auth = auth
        self.ai = ai
        self.health = health
        self.container = container
        self.supabase = SupabaseClient(config: config) { try await auth.validAccessToken() }
        self.subscriptions = SubscriptionService(config: config)
        self.configurationError = nil
    }

    /// Effective Pro status: StoreKit entitlement OR server flag.
    var isPro: Bool { subscriptions.isPro || (sync?.isPro ?? false) }

    func bootstrap() async {
        subscriptions.start()
        await auth.restore()
        handleAuthChange()
    }

    /// Recreates the sync service for the signed-in user (or tears it down).
    func handleAuthChange() {
        if let userID = auth.currentUserID {
            if sync == nil {
                sync = SyncService(context: container.mainContext, client: supabase, userID: userID)
            }
            subscriptions.serverClient = supabase
            Task {
                await sync?.syncNow()
                await subscriptions.refreshEntitlements()   // reports active subscriptions to the server
            }
        } else {
            // Local mode (no account): keep local data, just stop syncing.
            sync = nil
            subscriptions.serverClient = nil
        }
    }

    /// Removes all local data (unused in local mode) so the next account starts clean.
    func wipeLocalData() {
        let context = container.mainContext
        try? context.delete(model: FoodEntry.self)
        try? context.delete(model: WeightEntry.self)
        try? context.delete(model: SavedMealPlan.self)
        try? context.delete(model: UserProfile.self)
        try? context.save()
    }
}
