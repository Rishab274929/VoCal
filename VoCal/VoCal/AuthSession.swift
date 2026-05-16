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

    enum Provider: String, Codable { case anonymous, google }

    private struct Snapshot: Codable {
        let userID: String
        let token: String
        let expiresAt: Date
        let deviceID: String
        var provider: Provider = .anonymous
        var email: String?
        var displayName: String?
        var pictureURL: String?
    }

    @Published private(set) var userID: String?
    @Published private(set) var isAuthenticated = false
    @Published private(set) var provider: Provider = .anonymous
    @Published private(set) var email: String?
    @Published private(set) var displayName: String?
    @Published private(set) var pictureURL: String?

    private var current: Snapshot?
    private var pendingFetch: Task<Snapshot, Error>?

    private init() {
        if let loaded: Snapshot = Keychain.load(key: Self.keychainKey) {
            self.current = loaded
            self.userID = loaded.userID
            self.provider = loaded.provider
            self.email = loaded.email
            self.displayName = loaded.displayName
            self.pictureURL = loaded.pictureURL
            // Treat the session as authenticated even if the JWT is past
            // its expiry — we'll refresh lazily on the next backend call.
            self.isAuthenticated = true
        }
        // Touch StoreKitStore.shared so its transaction listener spins up
        // at the same time as auth, instead of waiting for the user to
        // open the paywall. Without this, renewals/refunds delivered
        // before the paywall is opened would be missed.
        _ = StoreKitStore.shared
    }

    /// Trade a Google ID token for our backend JWT. Once this succeeds the
    /// session is "upgraded" from anonymous to a signed-in Google user;
    /// subsequent backend calls authenticate as that user.
    ///
    /// If we were previously signed in as an anonymous user, we pass that
    /// `user_id` + token to the backend so it can merge the anonymous
    /// account's meals/profile into the new Google identity. Server is the
    /// authority on the merge — iOS just hands over enough to prove the
    /// merge is legitimate.
    func signInWithGoogle() async throws {
        // Capture the prior anon credentials BEFORE any awaits so we can
        // hand them to the backend regardless of intervening state changes.
        let priorAnonUserID: String?
        let priorAnonToken: String?
        if current?.provider == .anonymous {
            priorAnonUserID = current?.userID
            priorAnonToken = current?.token
        } else {
            priorAnonUserID = nil
            priorAnonToken = nil
        }

        let resp = try await GoogleSignIn.shared.signIn(
            linkAnonymousUserID: priorAnonUserID,
            linkAnonymousToken: priorAnonToken
        )
        let snap = Snapshot(
            userID: resp.user_id,
            token: resp.token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(resp.expires_at) / 1000),
            deviceID: current?.deviceID ?? Self.loadOrCreateDeviceID(),
            provider: .google,
            email: resp.email,
            displayName: resp.name,
            pictureURL: resp.picture
        )
        current = snap
        userID = snap.userID
        provider = .google
        email = snap.email
        displayName = snap.displayName
        pictureURL = snap.pictureURL
        isAuthenticated = true
        Keychain.save(snap, key: Self.keychainKey)
        // NOTE on local state: the on-disk meal log (vocal_state.v1.json in
        // Persistence) is intentionally NOT cleared. The user expects their
        // logged-while-anon meals to survive the upgrade. The backend merge
        // is for cross-device continuity; local-only is enough for the
        // common single-device case. If the backend merge fails, the local
        // log is still intact — worst case the user has to re-log on a
        // second device.
    }

    // MARK: - Public surface

    /// Ensures we have a valid (non-expired) token. Refreshes if needed.
    /// Returns the token string. Throws on network failure.
    ///
    /// For a Google-signed-in session whose JWT has expired, we currently
    /// return the stale token rather than silently downgrading to a fresh
    /// anonymous identity (which would orphan the user's account from the
    /// server's perspective). A backend `/api/auth/google/refresh` endpoint
    /// or a re-prompt-with-Google flow would be the right long-term fix;
    /// for now the backend's JWT TTL must be long enough that this case
    /// is rare, and the user re-opening the app + tapping Sign In with
    /// Google again is the recovery path.
    func currentToken() async throws -> String {
        if let snap = current, snap.expiresAt > Date().addingTimeInterval(60) {
            return snap.token
        }
        // Anonymous: safe to silently rotate via /api/auth/anonymous since
        // the device_id keeps the same user_id across rotations.
        if current?.provider == .anonymous || current == nil {
            return try await refresh().token
        }
        // Google: return the stale token rather than overwrite the
        // Google identity with a fresh anon one. The backend will reject
        // it with 401, and the caller can prompt the user to sign in
        // again. (Backend should ideally tolerate clock skew + grace.)
        return current?.token ?? ""
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
    ///
    /// - Parameter clearLocalData: when true, also wipes the persisted meal
    ///   log + profile from the Documents directory. Use this when a user
    ///   explicitly signs out (vs. the case where we're rotating a stale
    ///   anon token where the meals belong to the same person). The
    ///   default `false` matches the old behavior so existing call sites
    ///   keep working — but the Profile-screen "Sign out" button should
    ///   pass `true`.
    func signOut(clearLocalData: Bool = false) {
        Keychain.delete(key: Self.keychainKey)
        current = nil
        userID = nil
        provider = .anonymous
        email = nil
        displayName = nil
        pictureURL = nil
        isAuthenticated = false
        if clearLocalData {
            Persistence.clear()
            // Also drop the cached daily-macros snapshot so the App Intents
            // and widget don't keep reading the previous user's totals.
            UserDefaults.standard.removeObject(forKey: DailyMacrosSnapshot.defaultsKey)
            UserDefaults.standard.removeObject(forKey: StoreKitStore.entitlementCacheKey)
        }
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
            deviceID: deviceID,
            provider: .anonymous,
            email: nil,
            displayName: nil,
            pictureURL: nil
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
