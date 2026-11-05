//
//  SubscriptionService.swift
//  THERMOAI — Services
//
//  Purpose: StoreKit 2 subscriptions for THERMO AI Pro (monthly / yearly).
//           Entitlement is derived from verified transactions on device.
//           Server-side AI quota uses `profiles.is_pro`, which only the
//           `verify-subscription` Edge Function can set after confirming the
//           transaction with Apple — the client can never grant itself Pro.
//  Dependencies: StoreKit, Observation, Config/AppConfig.swift, Networking/SupabaseClient.swift
//

import Foundation
import StoreKit
import Observation

@MainActor
@Observable
final class SubscriptionService {
    private(set) var products: [Product] = []
    private(set) var isPro = false
    private(set) var isLoading = false
    var errorMessage: String?

    private let productIDs: [String]
    private var updatesTask: Task<Void, Never>?

    init(config: AppConfig) {
        productIDs = [config.proMonthlyProductID, config.proYearlyProductID]
    }

    /// Call once at launch: listens for renewals, refunds and purchases made elsewhere.
    func start() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                }
                await self?.refreshEntitlements()
            }
        }
        Task { await refreshEntitlements() }
    }

    func loadProducts() async {
        guard products.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            products = try await Product.products(for: productIDs).sorted { $0.price < $1.price }
        } catch {
            errorMessage = "Couldn't load subscriptions. Check your connection."
        }
    }

    /// Purchases a product. Returns true when Pro is active afterwards.
    @discardableResult
    func purchase(_ product: Product, appAccountToken: UUID?) async -> Bool {
        do {
            var options: Set<Product.PurchaseOption> = []
            // Links the transaction to the Supabase user for the server webhook.
            if let appAccountToken { options.insert(.appAccountToken(appAccountToken)) }
            let result = try await product.purchase(options: options)
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "The purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        return isPro
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            errorMessage = "Restore failed: \(error.localizedDescription)"
        }
    }

    func refreshEntitlements() async {
        var active = false
        var originalID: UInt64?
        for await result in Transaction.currentEntitlements {
            if case .verified(let t) = result, productIDs.contains(t.productID), t.revocationDate == nil {
                active = true
                originalID = t.originalID
            }
        }
        isPro = active
        if let originalID { await reportToServer(originalTransactionID: originalID) }
    }

    // MARK: Server entitlement

    /// Set by AppEnvironment once a user is signed in.
    var serverClient: SupabaseClient?

    /// Asks the `verify-subscription` Edge Function to confirm the subscription with
    /// Apple and update `profiles.is_pro` (which raises the server-side AI quota).
    private func reportToServer(originalTransactionID: UInt64) async {
        guard let serverClient else { return }
        struct Body: Encodable, Sendable { let originalTransactionId: String }
        struct Response: Decodable, Sendable { let isPro: Bool }
        _ = try? await serverClient.invoke("verify-subscription",
                                           body: Body(originalTransactionId: String(originalTransactionID))) as Response
    }
}
