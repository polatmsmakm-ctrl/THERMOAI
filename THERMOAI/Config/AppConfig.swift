//
//  AppConfig.swift
//  THERMOAI — Config
//
//  Purpose: Typed access to build-time configuration injected through
//           Config/Secrets.xcconfig → Info.plist. Only PUBLIC values live here:
//           the Supabase anon key is designed to be shipped in clients and is
//           protected by Row Level Security. The Gemini key NEVER appears in the app.
//  Dependencies: Foundation
//

import Foundation

struct AppConfig: Sendable {
    let supabaseURL: URL
    let supabaseAnonKey: String
    let proMonthlyProductID: String
    let proYearlyProductID: String

    enum ConfigError: Error, LocalizedError {
        case missing(String)
        case invalidURL(String)
        var errorDescription: String? {
            switch self {
            case .missing(let key): "Missing Info.plist key \(key). Check Config/Secrets.xcconfig."
            case .invalidURL(let value): "Invalid SUPABASE_URL: \(value)"
            }
        }
    }

    /// Loads configuration from the main bundle's Info.plist.
    static func load(from bundle: Bundle = .main) throws -> AppConfig {
        func value(_ key: String) throws -> String {
            guard let v = bundle.object(forInfoDictionaryKey: key) as? String,
                  !v.isEmpty, !v.hasPrefix("$(") else { throw ConfigError.missing(key) }
            return v
        }
        let urlString = try value("SUPABASE_URL")
        guard let url = URL(string: urlString), url.scheme == "https" || url.host == "127.0.0.1" || url.host == "localhost" else {
            throw ConfigError.invalidURL(urlString)
        }
        return AppConfig(
            supabaseURL: url,
            supabaseAnonKey: try value("SUPABASE_ANON_KEY"),
            proMonthlyProductID: (bundle.object(forInfoDictionaryKey: "PRO_MONTHLY_PRODUCT_ID") as? String) ?? "com.example.thermoai.pro.monthly",
            proYearlyProductID: (bundle.object(forInfoDictionaryKey: "PRO_YEARLY_PRODUCT_ID") as? String) ?? "com.example.thermoai.pro.yearly"
        )
    }

    /// Configuration used by SwiftUI previews and unit tests (no network).
    static let preview = AppConfig(
        supabaseURL: URL(string: "https://preview.supabase.co")!,
        supabaseAnonKey: "preview-anon-key",
        proMonthlyProductID: "com.example.thermoai.pro.monthly",
        proYearlyProductID: "com.example.thermoai.pro.yearly"
    )

    var authURL: URL { supabaseURL.appending(path: "auth/v1") }
    var restURL: URL { supabaseURL.appending(path: "rest/v1") }
    var functionsURL: URL { supabaseURL.appending(path: "functions/v1") }
}
