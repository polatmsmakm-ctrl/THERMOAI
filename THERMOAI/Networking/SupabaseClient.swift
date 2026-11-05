//
//  SupabaseClient.swift
//  THERMOAI — Networking
//
//  Purpose: Thin PostgREST + Edge Functions client. Every call carries the anon
//           key (`apikey`) and the user's JWT, so Row Level Security applies.
//  Dependencies: Foundation, Networking/HTTPClient.swift, Config/AppConfig.swift
//

import Foundation

struct SupabaseClient: Sendable {
    typealias TokenProvider = @Sendable () async throws -> String

    let config: AppConfig
    let http: HTTPClient
    let accessToken: TokenProvider

    init(config: AppConfig, http: HTTPClient = HTTPClient(), accessToken: @escaping TokenProvider) {
        self.config = config
        self.http = http
        self.accessToken = accessToken
    }

    // MARK: PostgREST

    /// GET /rest/v1/{table}?{query}
    func select<T: Decodable & Sendable>(_ table: String, query: [URLQueryItem]) async throws -> [T] {
        var components = URLComponents(url: config.restURL.appending(path: table), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        let request = URLRequest.json(components.url!, method: "GET", headers: try await headers())
        return try await http.send(request)
    }

    /// Bulk upsert keyed on primary key `id` (last-write-wins).
    func upsert<T: Encodable & Sendable>(_ table: String, rows: [T]) async throws {
        guard !rows.isEmpty else { return }
        var components = URLComponents(url: config.restURL.appending(path: table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "on_conflict", value: "id")]
        var h = try await headers()
        h["Prefer"] = "resolution=merge-duplicates,return=minimal"
        let request = try URLRequest.json(components.url!, method: "POST", body: rows, headers: h)
        try await http.sendRaw(request)
    }

    /// PATCH /rest/v1/{table}?id=eq.{id}
    func update<T: Encodable & Sendable>(_ table: String, id: UUID, fields: T) async throws {
        var components = URLComponents(url: config.restURL.appending(path: table), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")]
        var h = try await headers()
        h["Prefer"] = "return=minimal"
        let request = try URLRequest.json(components.url!, method: "PATCH", body: fields, headers: h)
        try await http.sendRaw(request)
    }

    // MARK: Edge Functions

    /// POST /functions/v1/{name}
    func invoke<Body: Encodable & Sendable, Response: Decodable & Sendable>(
        _ name: String, body: Body, timeout: TimeInterval = 60
    ) async throws -> Response {
        let request = try URLRequest.json(config.functionsURL.appending(path: name), method: "POST",
                                          body: body, headers: try await headers(), timeout: timeout)
        return try await http.send(request)
    }

    // MARK: Private

    private func headers() async throws -> [String: String] {
        let token = try await accessToken()
        return ["apikey": config.supabaseAnonKey, "Authorization": "Bearer \(token)"]
    }
}
