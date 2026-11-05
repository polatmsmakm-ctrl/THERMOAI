//
//  AuthViewModel.swift
//  THERMOAI — ViewModels
//
//  Purpose: Form state and validation for email/password and Sign in with Apple.
//  Dependencies: Services/AuthService.swift, AuthenticationServices
//

import Foundation
import AuthenticationServices
import Observation

@MainActor
@Observable
final class AuthViewModel {
    enum Mode: String, CaseIterable { case signIn = "Sign In", signUp = "Create Account" }

    var mode: Mode = .signIn
    var email = ""
    var password = ""
    var displayName = ""
    var isLoading = false
    var errorMessage: String?

    private let auth: AuthService
    private var currentNonce: String?

    init(auth: AuthService) { self.auth = auth }

    var isFormValid: Bool {
        let emailOK = email.contains("@") && email.contains(".") && email.count >= 5
        let passwordOK = password.count >= 8
        let nameOK = mode == .signIn || !displayName.trimmingCharacters(in: .whitespaces).isEmpty
        return emailOK && passwordOK && nameOK
    }

    func submit() async {
        guard isFormValid else {
            errorMessage = mode == .signUp
                ? "Enter your name, a valid email and a password of at least 8 characters."
                : "Enter a valid email and password."
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let trimmedEmail = email.trimmingCharacters(in: .whitespaces).lowercased()
            switch mode {
            case .signIn: try await auth.signIn(email: trimmedEmail, password: password)
            case .signUp: try await auth.signUp(email: trimmedEmail, password: password,
                                                displayName: displayName.trimmingCharacters(in: .whitespaces))
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Sign in with Apple

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AuthService.makeNonce()
        currentNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = AuthService.sha256(nonce)
    }

    func handle(_ result: Result<ASAuthorization, Error>) async {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Apple sign-in returned no identity token."
                return
            }
            isLoading = true
            defer { isLoading = false }
            do {
                try await auth.signInWithApple(idToken: idToken, rawNonce: nonce)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
