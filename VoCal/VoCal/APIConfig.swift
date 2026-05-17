//
//  APIConfig.swift
//  VoCal
//
//  Single source of truth for the backend base URL. The custom domain
//  vocal.best is live and Cloudflare-fronted; the pages.dev URL stays as
//  a reference for direct cluster access during incidents.
//

import Foundation

enum APIConfig {
    /// Order: env override → canonical custom domain.
    /// Override via `VOCAL_API_BASE_URL` in the scheme env for local dev
    /// (e.g. `http://localhost:8788/api` when running `wrangler pages dev`).
    static var baseURL: String {
        if let override = ProcessInfo.processInfo.environment["VOCAL_API_BASE_URL"], !override.isEmpty {
            return override
        }
        return "https://vocal.best/api"
    }
}

enum BackendAPIError: Swift.Error, LocalizedError {
    case signInRequired(String)
    case proRequired(String)
    case server(Int, String)
    case malformed

    var errorDescription: String? {
        switch self {
        case .signInRequired(let message):
            return message.isEmpty ? "Sign in again to continue." : message
        case .proRequired(let message):
            return message.isEmpty ? "VoCal Pro is required." : message
        case .server(let status, let message):
            return message.isEmpty ? "Server \(status)" : "Server \(status): \(message)"
        case .malformed:
            return "Unexpected response from the server."
        }
    }

    var needsUserAction: Bool {
        switch self {
        case .signInRequired, .proRequired: return true
        case .server, .malformed: return false
        }
    }

    static func from(status: Int, data: Data) -> BackendAPIError {
        let message = (try? JSONDecoder().decode([String: String].self, from: data))?["error"] ?? ""
        switch status {
        case 401:
            return .signInRequired(message.isEmpty ? "Sign in again to continue." : message)
        case 402:
            return .proRequired(message.isEmpty ? "VoCal Pro is required." : message)
        default:
            return .server(status, message)
        }
    }
}
