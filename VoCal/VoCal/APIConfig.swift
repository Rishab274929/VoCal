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
