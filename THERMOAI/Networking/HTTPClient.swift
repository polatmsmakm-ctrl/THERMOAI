//
//  HTTPClient.swift
//  THERMOAI — Networking
//
//  Purpose: Minimal, dependency-free async HTTP layer with typed errors,
//           retry for transient failures, and Supabase-compatible JSON coding.
//  Dependencies: Foundation, Models/AIModels.swift (BackendErrorEnvelope)
//

import Foundation

// MARK: - Errors

enum APIError: Error, LocalizedError, Equatable {
    case offline
    case timeout
    case unauthorized
    case quotaExceeded
    case server(status: Int, code: String?, message: String)
    case decoding(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Changes are saved and will sync later."
        case .timeout: "The request took too long. Please try again."
        case .unauthorized: "Your session has expired. Please sign in again."
        case .quotaExceeded: "You've reached today's AI limit. Upgrade to Pro for more."
        case .server(_, _, let message): message
        case .decoding: "We received an unexpected response. Please try again."
        case .invalidResponse: "Invalid server response."
        }
    }

    /// Transient errors that are safe to retry.
    var isRetryable: Bool {
        switch self {
        case .timeout: true
        case .server(let status, _, _): status == 502 || status == 503 || status == 504
        default: false
        }
    }
}

// MARK: - JSON coding

enum JSONCoding {
    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = parseDate(string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
            }
            return date
        }
        return d
    }

    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    /// Parses Postgres timestamptz ("2026-11-05T05:22:00.123456+00:00"),
    /// ISO-8601 with/without fractional seconds, and plain dates ("2026-11-05").
    static func parseDate(_ string: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        // Postgres emits microseconds; trim to milliseconds for the formatter.
        let trimmed = string.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        if let d = f.date(from: trimmed) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withFullDate]
        return f.date(from: string)
    }

    /// "yyyy-MM-dd" in UTC for Postgres `date` columns.
    static func dateOnlyString(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f.string(from: date)
    }
}

// MARK: - Client

struct HTTPClient: Sendable {
    let session: URLSession
    let maxRetries: Int

    init(session: URLSession = .shared, maxRetries: Int = 2) {
        self.session = session
        self.maxRetries = maxRetries
    }

    /// Sends a request and decodes a JSON body.
    func send<T: Decodable>(_ request: URLRequest, as type: T.Type = T.self) async throws -> T {
        let data = try await sendRaw(request)
        do {
            return try JSONCoding.decoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a request and returns the raw body, mapping HTTP and transport errors.
    @discardableResult
    func sendRaw(_ request: URLRequest) async throws -> Data {
        var attempt = 0
        while true {
            do {
                return try await perform(request)
            } catch let error as APIError where error.isRetryable && attempt < maxRetries {
                attempt += 1
                // Exponential backoff with jitter: ~0.5s, ~1s.
                let delay = UInt64((0.5 * pow(2, Double(attempt - 1)) + Double.random(in: 0...0.25)) * 1_000_000_000)
                try await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw APIError.offline
            case .timedOut: throw APIError.timeout
            default: throw APIError.server(status: -1, code: nil, message: error.localizedDescription)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        case 429:
            throw APIError.quotaExceeded
        default:
            let envelope = try? JSONCoding.decoder().decode(BackendErrorEnvelope.self, from: data)
            let supabaseMessage = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])
                .flatMap { $0["msg"] as? String ?? $0["message"] as? String ?? $0["error_description"] as? String }
            throw APIError.server(status: http.statusCode,
                                  code: envelope?.error.code,
                                  message: envelope?.error.message ?? supabaseMessage ?? "Server error (\(http.statusCode))")
        }
    }
}

// MARK: - Request building

extension URLRequest {
    /// JSON request without a body (GET / DELETE / bodiless POST).
    static func json(_ url: URL, method: String = "GET",
                     headers: [String: String] = [:], timeout: TimeInterval = 30) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        return request
    }

    /// JSON request with an encoded body.
    static func json<Body: Encodable>(_ url: URL, method: String = "POST", body: Body,
                                      headers: [String: String] = [:], timeout: TimeInterval = 30) throws -> URLRequest {
        var request = json(url, method: method, headers: headers, timeout: timeout)
        request.httpBody = try JSONCoding.encoder().encode(body)
        return request
    }
}

struct EmptyBody: Codable, Sendable {}
