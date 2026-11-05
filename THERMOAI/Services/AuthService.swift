//
//  AuthService.swift
//  THERMOAI — Services
//
//  Purpose: Supabase Auth (GoTrue) over REST — email/password, Sign in with Apple
//           (native id_token flow), token refresh, sign-out and account deletion.
//           Session persisted in the Keychain.
//  Dependencies: Foundation, CryptoKit, Observation, Networking/HTTPClient.swift,
//                Utilities/KeychainStore.swift, Config/AppConfig.swift
//
//  Endpoints used (Supabase Auth REST):
//    POST /auth/v1/signup
//    POST /auth/v1/token?grant_type=password
//    POST /auth/v1/token?grant_type=refresh_token
//    POST /auth/v1/token?grant_type=id_token      (provider = apple)
//    POST /auth/v1/logout
//    POST /functions/v1/delete-account             (custom Edge Function)
//

import Foundation
import CryptoKit
import Observation

struct AuthUser: Codable, Sendable, Equatable {
    let id: UUID
    let email: String?
}

struct AuthSession: Codable, Sendable, Equatable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let user: AuthUser

    var isExpiringSoon: Bool { expiresAt.timeIntervalSinceNow < 60 }
}

/// Raw GoTrue token response.
private struct TokenResponse: Decodable {
    let access_token: String?
    let refresh_token: String?
    let expires_in: Double?
    let user: UserPayload?
    // Signup with email confirmation enabled returns the user at the top level.
    let id: UUID?
    let email: String?

    struct UserPayload: Decodable { let id: UUID; let email: String? }
}

@MainActor
@Observable
final class AuthService {
    enum State: Equatable {
        case restoring
        case signedOut
        case awaitingEmailConfirmation(email: String)
        case signedIn(AuthUser)
    }

    private(set) var state: State = .restoring
    private(set) var session: AuthSession?

    private let config: AppConfig
    private let http: HTTPClient
    private let keychain: KeychainStore
    private var refreshTask: Task<AuthSession, Error>?
    private static let sessionKey = "thermoai.auth.session"

    init(config: AppConfig, http: HTTPClient = HTTPClient(), keychain: KeychainStore = KeychainStore()) {
        self.config = config
        self.http = http
        self.keychain = keychain
    }

    var currentUserID: UUID? { session?.user.id }

    // MARK: Lifecycle

    /// Restores a persisted session at launch and refreshes it when stale.
    func restore() async {
        guard let data = keychain.data(for: Self.sessionKey),
              let saved = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            state = .signedOut
            return
        }
        session = saved
        state = .signedIn(saved.user)
        if saved.isExpiringSoon {
            do { _ = try await refresh() } catch APIError.offline {
                // Keep the cached session; the app works offline and will refresh later.
            } catch {
                clearSession()
            }
        }
    }

    // MARK: Email / password

    func signUp(email: String, password: String, displayName: String) async throws {
        struct Body: Encodable {
            let email: String; let password: String; let data: [String: String]
        }
        let request = try URLRequest.json(config.authURL.appending(path: "signup"),
                                          body: Body(email: email, password: password, data: ["display_name": displayName]),
                                          headers: baseHeaders)
        let response: TokenResponse = try await http.send(request)
        if response.access_token != nil {
            try store(response)
        } else {
            state = .awaitingEmailConfirmation(email: email)
        }
    }

    func signIn(email: String, password: String) async throws {
        struct Body: Encodable { let email: String; let password: String }
        let request = try URLRequest.json(tokenURL(grant: "password"),
                                          body: Body(email: email, password: password),
                                          headers: baseHeaders)
        try store(try await http.send(request, as: TokenResponse.self))
    }

    // MARK: Sign in with Apple

    /// Creates a random nonce. Pass `sha256(nonce)` to ASAuthorizationAppleIDRequest
    /// and the raw nonce to `signInWithApple(idToken:rawNonce:)`.
    static func makeNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func signInWithApple(idToken: String, rawNonce: String) async throws {
        struct Body: Encodable { let provider: String; let id_token: String; let nonce: String }
        let request = try URLRequest.json(tokenURL(grant: "id_token"),
                                          body: Body(provider: "apple", id_token: idToken, nonce: rawNonce),
                                          headers: baseHeaders)
        try store(try await http.send(request, as: TokenResponse.self))
    }

    // MARK: Tokens

    /// Returns a valid access token, refreshing if needed. Concurrent callers share one refresh.
    func validAccessToken() async throws -> String {
        guard let session else { throw APIError.unauthorized }
        if !session.isExpiringSoon { return session.accessToken }
        return try await refresh().accessToken
    }

    @discardableResult
    func refresh() async throws -> AuthSession {
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = session?.refreshToken else { throw APIError.unauthorized }

        let task = Task<AuthSession, Error> { [config, http, baseHeaders] in
            struct Body: Encodable { let refresh_token: String }
            var components = URLComponents(url: config.authURL.appending(path: "token"), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
            let request = try URLRequest.json(components.url!, body: Body(refresh_token: refreshToken), headers: baseHeaders)
            let response = try await http.send(request, as: TokenResponse.self)
            return try Self.makeSession(from: response)
        }
        refreshTask = task
        defer { refreshTask = nil }

        do {
            let newSession = try await task.value
            persist(newSession)
            return newSession
        } catch APIError.unauthorized {
            clearSession()
            throw APIError.unauthorized
        } catch let APIError.server(status, _, _) where status == 400 {
            // Refresh token revoked or reused.
            clearSession()
            throw APIError.unauthorized
        }
    }

    // MARK: Sign out / delete

    func signOut() async {
        if let token = session?.accessToken {
            var headers = baseHeaders
            headers["Authorization"] = "Bearer \(token)"
            let request = URLRequest.json(config.authURL.appending(path: "logout"), method: "POST", headers: headers)
            _ = try? await http.sendRaw(request)   // best effort
        }
        clearSession()
    }

    /// Permanently deletes the account and all server data (App Store Guideline 5.1.1(v)).
    func deleteAccount() async throws {
        let token = try await validAccessToken()
        var headers = baseHeaders
        headers["Authorization"] = "Bearer \(token)"
        let request = URLRequest.json(config.functionsURL.appending(path: "delete-account"), method: "POST", headers: headers)
        try await http.sendRaw(request)
        clearSession()
    }

    // MARK: Private

    private var baseHeaders: [String: String] { ["apikey": config.supabaseAnonKey] }

    private func tokenURL(grant: String) -> URL {
        var components = URLComponents(url: config.authURL.appending(path: "token"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grant)]
        return components.url!
    }

    private func store(_ response: TokenResponse) throws {
        persist(try Self.makeSession(from: response))
    }

    private nonisolated static func makeSession(from r: TokenResponse) throws -> AuthSession {
        guard let access = r.access_token, let refresh = r.refresh_token, let user = r.user else {
            throw APIError.invalidResponse
        }
        return AuthSession(accessToken: access, refreshToken: refresh,
                           expiresAt: Date().addingTimeInterval(r.expires_in ?? 3600),
                           user: AuthUser(id: user.id, email: user.email))
    }

    private func persist(_ newSession: AuthSession) {
        session = newSession
        state = .signedIn(newSession.user)
        if let data = try? JSONEncoder().encode(newSession) {
            try? keychain.set(data, for: Self.sessionKey)
        }
    }

    private func clearSession() {
        session = nil
        state = .signedOut
        keychain.remove(Self.sessionKey)
    }
}
