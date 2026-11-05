//
//  AuthView.swift
//  THERMOAI — Views/Auth
//
//  Purpose: Sign in / create account with email or Sign in with Apple.
//  Dependencies: SwiftUI, AuthenticationServices, ViewModels/AuthViewModel.swift
//

import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var vm: AuthViewModel?
    @FocusState private var focused: Field?

    enum Field { case name, email, password }

    var body: some View {
        Group {
            if let vm { content(vm) } else { Color.clear }
        }
        .onAppear { if vm == nil { vm = AuthViewModel(auth: env.auth) } }
    }

    @ViewBuilder
    private func content(_ vm: AuthViewModel) -> some View {
        @Bindable var vm = vm
        ScrollView {
            VStack(spacing: Theme.Spacing.lg) {
                VStack(spacing: Theme.Spacing.sm) {
                    ThermoLogo(size: 76)
                    Text("THERMO AI")
                        .font(Theme.Typography.title).tracking(5)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text("Metabolic intelligence for every meal.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .padding(.top, 48)

                if case .awaitingEmailConfirmation(let email) = env.auth.state {
                    GlassCard {
                        Label("Check \(email) to confirm your account, then sign in.", systemImage: "envelope.badge")
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }
                }

                Picker("Mode", selection: $vm.mode.animation(Theme.Motion.spring)) {
                    ForEach(AuthViewModel.Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                VStack(spacing: Theme.Spacing.sm) {
                    if vm.mode == .signUp {
                        ThermoTextField(title: "Name", text: $vm.displayName, systemImage: "person")
                            .textContentType(.name)
                            .focused($focused, equals: .name)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    ThermoTextField(title: "Email", text: $vm.email, systemImage: "envelope")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focused, equals: .email)
                    ThermoTextField(title: "Password (8+ characters)", text: $vm.password, systemImage: "lock", isSecure: true)
                        .textContentType(vm.mode == .signUp ? .newPassword : .password)
                        .focused($focused, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { Task { await vm.submit() } }
                }

                if let error = vm.errorMessage { ErrorBanner(message: error) }

                LoadingButton(title: vm.mode.rawValue, isLoading: vm.isLoading) {
                    focused = nil
                    Task { await vm.submit() }
                }

                HStack {
                    Rectangle().fill(Theme.Colors.stroke).frame(height: 1)
                    Text("or").font(Theme.Typography.caption).foregroundStyle(Theme.Colors.textTertiary)
                    Rectangle().fill(Theme.Colors.stroke).frame(height: 1)
                }

                SignInWithAppleButton(.continue) { request in
                    vm.prepare(request)
                } onCompletion: { result in
                    Task { await vm.handle(result) }
                }
                .signInWithAppleButtonStyle(.white)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

                Text("THERMO AI provides estimates for general wellness and is not medical advice.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .padding(.top, Theme.Spacing.sm)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(maxWidth: 480)
            .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .thermoScreen()
        .animation(Theme.Motion.spring, value: vm.errorMessage)
    }
}
