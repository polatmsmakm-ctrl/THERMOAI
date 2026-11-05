//
//  PaywallView.swift
//  THERMOAI — Views/Paywall
//
//  Purpose: StoreKit 2 paywall for THERMO AI Pro with plan selection,
//           restore, and required subscription disclosures.
//  Dependencies: SwiftUI, StoreKit, Services/SubscriptionService.swift
//

import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss
    @State private var selectedID: String?
    @State private var isPurchasing = false

    private var subs: SubscriptionService { env.subscriptions }

    private let features: [(String, String)] = [
        ("camera.viewfinder", "300 AI photo & text analyses per day"),
        ("fork.knife", "7-day AI meal plans"),
        ("sparkles", "Unlimited coach conversations"),
        ("waveform.path.ecg", "Adaptive TDEE from your real data"),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    ThermoLogo(size: 72).padding(.top, Theme.Spacing.lg)
                    Text("THERMO AI Pro").font(Theme.Typography.title).foregroundStyle(Theme.Colors.textPrimary)
                    Text("Turn up the heat on your results.").font(Theme.Typography.callout).foregroundStyle(Theme.Colors.textSecondary)

                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                            ForEach(features, id: \.1) { icon, text in
                                Label { Text(text).foregroundStyle(Theme.Colors.textPrimary) } icon: {
                                    Image(systemName: icon).foregroundStyle(Theme.Colors.accent)
                                }
                            }
                        }
                    }

                    if subs.isLoading {
                        ProgressView()
                    } else {
                        ForEach(subs.products, id: \.id) { product in planRow(product) }
                    }

                    if let error = subs.errorMessage { ErrorBanner(message: error) }

                    LoadingButton(title: env.isPro ? "You're Pro" : "Continue", isLoading: isPurchasing) {
                        guard let product = subs.products.first(where: { $0.id == selectedID }) else { return }
                        isPurchasing = true
                        Task {
                            let success = await subs.purchase(product, appAccountToken: env.auth.currentUserID)
                            isPurchasing = false
                            if success { dismiss() }
                        }
                    }
                    .disabled(selectedID == nil || env.isPro)

                    Button("Restore purchases") { Task { await subs.restorePurchases() } }
                        .font(Theme.Typography.callout).foregroundStyle(Theme.Colors.accent)

                    Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the period. Manage or cancel in Settings › Apple ID › Subscriptions.")
                        .font(.caption2).multilineTextAlignment(.center).foregroundStyle(Theme.Colors.textTertiary)
                    HStack(spacing: Theme.Spacing.md) {
                        Link("Terms of Use", destination: URL(string: "https://example.com/thermoai/terms")!)
                        Link("Privacy Policy", destination: URL(string: "https://example.com/thermoai/privacy")!)
                    }
                    .font(.caption)
                }
                .padding(Theme.Spacing.lg)
                .frame(maxWidth: 520)
                .frame(maxWidth: .infinity)
            }
            .thermoScreen()
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                await subs.loadProducts()
                selectedID = selectedID ?? subs.products.last?.id
            }
        }
    }

    private func planRow(_ product: Product) -> some View {
        let selected = product.id == selectedID
        return Button { selectedID = product.id } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(product.displayName).font(Theme.Typography.headline).foregroundStyle(Theme.Colors.textPrimary)
                    if let period = product.subscription?.subscriptionPeriod {
                        Text("\(product.displayPrice) / \(period.unit == .year ? "year" : "month")")
                            .font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Theme.Colors.accent : Theme.Colors.textTertiary)
            }
            .padding(Theme.Spacing.md)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.sm).fill(Theme.Colors.surface))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                .strokeBorder(selected ? Theme.Colors.accent : Theme.Colors.stroke, lineWidth: selected ? 1.5 : 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}
