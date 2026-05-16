//
//  AuthSession.swift
//  VoCal
//
//  Anonymous device-bound auth. On first launch we generate a stable
//  device UUID, POST it to /api/auth/anonymous, and persist the returned
//  JWT in the Keychain. Subsequent backend calls attach the token via
//  AuthSession.shared.authorizedRequest(...) which auto-refreshes when
//  the token expires.
//
//  Why Keychain vs UserDefaults: tokens survive backup/restore and
//  app uninstall→reinstall (on the same device), so a user gets the
//  same anon ID back. UserDefaults would lose it on reinstall.
//

import Foundation
import Security
import Combine

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    private struct Snapshot: Codable {
        let userID: String
        let token: String
        let expiresAt: Date
        let deviceID: String
    }

    @Published private(set) var userID: String?
    @Published private(set) var isAuthenticated = false

    private var current: Snapshot?
    private var pendingFetch: Task<Snapshot, Error>?

    private init() {
        if let loaded: Snapshot = Keychain.load(key: Self.keychainKey) {
            self.current = loaded
            self.userID = loaded.userID
            // Treat the session as authenticated even if the JWT is past
            // its expiry — we'll refresh lazily on the next backend call.
            self.isAuthenticated = true
        }
    }

    // MARK: - Public surface

    /// Ensures we have a valid (non-expired) token. Refreshes if needed.
    /// Returns the token string. Throws on network failure.
    func currentToken() async throws -> String {
        if let snap = current, snap.expiresAt > Date().addingTimeInterval(60) {
            return snap.token
        }
        return try await refresh().token
    }

    /// Stamp an outgoing URLRequest with `Authorization: Bearer <token>`.
    /// Returns the same request, unchanged, if the auth call fails — we
    /// never want a token-fetch error to break an actual user action.
    func authorize(_ request: inout URLRequest) async {
        if let token = try? await currentToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    /// Erase the local session. Next request will create a fresh anon user.
    /// Used by sign-out flows once SiwA lands.
    func signOut() {
        Keychain.delete(key: Self.keychainKey)
        current = nil
        userID = nil
        isAuthenticated = false
    }

    // MARK: - Refresh

    /// Force-refresh the anonymous session. Coalesces concurrent calls so
    /// the app never fires more than one /api/auth/anonymous request at a time.
    @discardableResult
    private func refresh() async throws -> Snapshot {
        if let pending = pendingFetch {
            return try await pending.value
        }
        let task = Task { try await self.doRefresh() }
        pendingFetch = task
        defer { pendingFetch = nil }
        do {
            let snap = try await task.value
            self.current = snap
            self.userID = snap.userID
            self.isAuthenticated = true
            Keychain.save(snap, key: Self.keychainKey)
            return snap
        } catch {
            // Re-throw but keep `current` so a transient failure doesn't
            // log the user out entirely.
            throw error
        }
    }

    private func doRefresh() async throws -> Snapshot {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/anonymous") else {
            throw URLError(.badURL)
        }
        // Reuse the existing device ID if we have one — gives the user
        // the same anon account back if their token expired.
        let deviceID = current?.deviceID ?? Self.loadOrCreateDeviceID()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 10
        let body = ["device_id": deviceID]
        req.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let parsed = try JSONDecoder().decode(Response.self, from: data)
        return Snapshot(
            userID: parsed.user_id,
            token: parsed.token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(parsed.expires_at) / 1000),
            deviceID: deviceID
        )
    }

    private struct Response: Codable {
        let user_id: String
        let token: String
        let expires_at: Int64  // server returns millis
    }

    // MARK: - Device ID

    private static func loadOrCreateDeviceID() -> String {
        // Use identifierForVendor as the seed — it's stable per
        // app-installation per device. Wrap it in a Keychain entry so
        // it survives a re-install if the Keychain is restored from
        // backup.
        if let existing: String = Keychain.load(key: deviceKeychainKey) {
            return existing
        }
        let fresh = UUID().uuidString
        Keychain.save(fresh, key: deviceKeychainKey)
        return fresh
    }

    private static let keychainKey = "vocal.auth.anonymous.v1"
    private static let deviceKeychainKey = "vocal.device.id.v1"
}

// MARK: - Minimal Keychain helper

enum Keychain {
    static func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
        let attrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(attrs as CFDictionary, nil)
    }

    static func load<T: Codable>(key: String) -> T? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
