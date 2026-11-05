//
//  RootView.swift
//  THERMOAI — App
//
//  Purpose: Top-level routing: config error → splash → auth → onboarding → main tabs.
//  Dependencies: SwiftUI, SwiftData, Views/*
//

import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var profiles: [UserProfile]

    var body: some View {
        ZStack {
            Theme.Colors.background.ignoresSafeArea()
            content
        }
        .animation(.smooth(duration: 0.45), value: routeKey)
        .onChange(of: env.auth.state) { _, _ in env.handleAuthChange() }
    }

    @ViewBuilder
    private var content: some View {
        if let error = env.configurationError {
            ConfigurationErrorView(message: error)
        } else {
            switch env.auth.state {
            case .restoring:
                SplashView().transition(.opacity)
            case .signedOut, .awaitingEmailConfirmation:
                AuthView().transition(.opacity)
            case .signedIn:
                if let profile = profiles.first, profile.onboardingCompleted {
                    MainTabView().transition(.opacity)
                } else {
                    OnboardingView().transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
    }

    private var routeKey: String {
        switch env.auth.state {
        case .restoring: "restoring"
        case .signedOut, .awaitingEmailConfirmation: "auth"
        case .signedIn: (profiles.first?.onboardingCompleted ?? false) ? "main" : "onboarding"
        }
    }
}

struct SplashView: View {
    @State private var pulse = false
    var body: some View {
        VStack(spacing: 20) {
            ThermoLogo(size: 88)
                .scaleEffect(pulse ? 1.04 : 0.96)
                .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: pulse)
            Text("THERMO AI")
                .font(Theme.Typography.title)
                .tracking(6)
                .foregroundStyle(Theme.Colors.textPrimary)
        }
        .onAppear { pulse = true }
    }
}

struct ConfigurationErrorView: View {
    let message: String
    var body: some View {
        ContentUnavailableView {
            Label("Configuration needed", systemImage: "wrench.and.screwdriver")
        } description: {
            Text(message)
        }
        .foregroundStyle(Theme.Colors.textPrimary)
    }
}
