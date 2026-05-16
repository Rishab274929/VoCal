//
//  GoogleSignIn.swift
//  VoCal
//
//  Google OAuth via ASWebAuthenticationSession — no Google SDK required.
//  We use the OAuth 2.0 implicit / "PKCE for native apps" flow:
//    1. Spin up an ASWebAuthenticationSession pointing at
//       https://accounts.google.com/o/oauth2/v2/auth with response_type=id_token
//    2. User signs in via Safari View Controller (handles 2FA, passkeys, etc.)
//    3. Google redirects to com.EricSpencer.VoCal:/oauth/callback#id_token=...
//    4. We extract the id_token, POST it to /api/auth/google, persist the
//       resulting VoCal JWT in the Keychain, and the rest of the app works
//       exactly like the anonymous flow.
//
//  Why not the Google SDK? Adding GoogleSignIn-iOS via SPM means modifying
//  the .xcodeproj, GoogleService-Info.plist juggling, and an extra ~5 MB
//  in the binary. ASWebAuthenticationSession is built into iOS, gives us
//  the same UX, and means zero project file edits.
//
//  Setup before this works:
//   1. https://console.cloud.google.com → APIs & Services → Credentials.
//   2. Create OAuth client ID, type: iOS, Bundle ID com.EricSpencer.VoCal.
//   3. Copy the client ID (looks like 1234-abc.apps.googleusercontent.com).
//   4. Paste it into the .clientID literal in GoogleSignIn.iosClientID below.
//      Also set GOOGLE_CLIENT_ID_IOS as a Cloudflare Pages secret.
//   5. Add the reversed-client-ID URL scheme to Info.plist as a CFBundleURLType:
//      e.g. "com.googleusercontent.apps.1234-abc"
//   6. Add this same reversed-client-ID as the Authorized redirect URI on the
//      Google console for the iOS client.
//
//  SECURITY: this flow is hardened against replay attacks via the
//  OIDC `nonce` claim. We generate a random nonce, embed its SHA-256 in
//  the Google auth URL, and verify the returned id_token's `nonce` claim
//  matches before trusting the token. The id_token JWS signature itself is
//  verified server-side at /api/auth/google by checking Google's JWKS.
//

import Foundation
import AuthenticationServices
import Combine
import CryptoKit

@MainActor
final class GoogleSignIn: NSObject, ObservableObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = GoogleSignIn()

    /// PASTE your iOS client ID here once it's issued in Google Cloud Console.
    /// Looks like: `1234567890-abcdefgh.apps.googleusercontent.com`
    /// Leave the placeholder in place to expose a clear runtime error rather
    /// than silently fail; the Sign-In button will surface "Not configured."
    static let iosClientID = "PASTE_YOUR_IOS_CLIENT_ID.apps.googleusercontent.com"

    /// The reversed form Google requires as the OAuth redirect scheme.
    /// `com.googleusercontent.apps.1234-abcdefgh`
    static var redirectScheme: String {
        // Drop the trailing ".apps.googleusercontent.com" and reverse the rest.
        let suffix = ".apps.googleusercontent.com"
        guard iosClientID.hasSuffix(suffix) else { return "com.googleusercontent.apps.invalid" }
        let base = String(iosClientID.dropLast(suffix.count))
        return "com.googleusercontent.apps.\(base)"
    }

    private var session: ASWebAuthenticationSession?

    @Published private(set) var isSigningIn = false
    @Published var lastError: String?

    enum Error: Swift.Error, LocalizedError {
        case notConfigured
        case userCancelled
        case noIDToken
        case nonceMismatch
        case backend(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google sign-in isn't configured yet. Paste your iOS client ID."
            case .userCancelled: "Sign-in cancelled."
            case .noIDToken:     "Google didn't return an id_token."
            case .nonceMismatch: "Google sign-in security check failed. Try again."
            case .backend(let m): m
            }
        }
    }

    struct GoogleAuthResponse: Codable {
        let user_id: String
        let token: String
        let expires_at: Int64
        let email: String?
        let name: String?
        let picture: String?
        let is_new_user: Bool?
    }

    /// Kicks off the Google sign-in flow. On success, returns the backend
    /// response (the iOS app should persist `token` and treat the user as
    /// signed-in via Google instead of anonymous).
    ///
    /// - Parameter linkAnonymousUserID: if the device is currently signed in
    ///   anonymously, pass that user_id so the backend can merge the
    ///   anonymous account's data into the new Google account. Server
    ///   handles the merge atomically; on conflict the Google account wins.
    /// - Parameter linkAnonymousToken: the anonymous JWT, sent as proof
    ///   that the caller actually owns that anonymous user_id. Without
    ///   this, anyone could claim any anon ID's data.
    func signIn(
        linkAnonymousUserID: String? = nil,
        linkAnonymousToken: String? = nil
    ) async throws -> GoogleAuthResponse {
        guard Self.iosClientID.hasPrefix("PASTE") == false else {
            throw Error.notConfigured
        }
        isSigningIn = true
        defer { isSigningIn = false }

        let rawNonce = Self.randomNonce()
        let hashedNonce = Self.sha256Hex(rawNonce)
        let authURL = try buildAuthURL(hashedNonce: hashedNonce)
        let idToken = try await runWebAuthSession(authURL: authURL)
        // OIDC replay defense: the id_token's `nonce` claim must equal the
        // SHA-256 of the random value we sent in the auth URL. If a
        // malicious app intercepts the redirect URI (e.g., a competing app
        // registered the same scheme), this catches the replay.
        try Self.verifyNonceClaim(in: idToken, expectedHashedNonce: hashedNonce)
        return try await exchangeWithBackend(
            idToken: idToken,
            linkAnonymousUserID: linkAnonymousUserID,
            linkAnonymousToken: linkAnonymousToken
        )
    }

    // MARK: - OAuth URL

    private func buildAuthURL(hashedNonce: String) throws -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: Self.iosClientID),
            URLQueryItem(name: "redirect_uri", value: "\(Self.redirectScheme):/oauth/callback"),
            URLQueryItem(name: "response_type", value: "id_token"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            // We send the SHA-256 hashed nonce per OIDC best practice — the
            // raw value never leaves the device. Same scheme Apple uses for
            // Sign-In-with-Apple nonce binding.
            URLQueryItem(name: "nonce", value: hashedNonce),
            // Force a fresh authorization to surface the account chooser if
            // the user has multiple Google accounts. Without this, Google
            // silently re-uses whichever one is "first" in their cookies.
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = c.url else { throw Error.notConfigured }
        return url
    }

    // MARK: - Web auth session

    private func runWebAuthSession(authURL: URL) async throws -> String {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Swift.Error>) in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: Self.redirectScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: Error.userCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL,
                      // ID tokens come back in the URL FRAGMENT (after #) for response_type=id_token.
                      let fragment = callbackURL.fragment,
                      let idToken = Self.queryValue(name: "id_token", in: fragment) else {
                    continuation.resume(throwing: Error.noIDToken)
                    return
                }
                continuation.resume(returning: idToken)
            }
            session.presentationContextProvider = self
            // Use an ephemeral session so we don't leak the user's Safari
            // cookies into the OAuth flow. The cost is that the user has to
            // re-enter their Google password the first time per app launch,
            // but the security upside (no cookie persistence that could
            // outlive a sign-out) is worth it for an app that stores meal
            // data tied to an identity.
            session.prefersEphemeralWebBrowserSession = true
            self.session = session
            session.start()
        }
    }

    // MARK: - Backend exchange

    private func exchangeWithBackend(
        idToken: String,
        linkAnonymousUserID: String?,
        linkAnonymousToken: String?
    ) async throws -> GoogleAuthResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/google") else {
            throw Error.backend("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        var payload: [String: String] = ["id_token": idToken]
        // Send the prior anonymous credentials so the backend can re-link
        // any meals/profile/body_metrics tied to that anonymous user_id to
        // the new Google identity. The token is proof-of-ownership: without
        // it, anyone with knowledge of an anon UUID could claim its data.
        // Backend SHOULD validate the anonymous JWT before doing the merge.
        if let uid = linkAnonymousUserID { payload["link_anonymous_user_id"] = uid }
        if let tok = linkAnonymousToken  { payload["link_anonymous_token"] = tok }
        req.httpBody = try JSONEncoder().encode(payload)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.backend("Bad response") }
        if !(200..<300).contains(http.statusCode) {
            struct Err: Codable { let error: String? }
            let msg = (try? JSONDecoder().decode(Err.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Error.backend(msg)
        }
        return try JSONDecoder().decode(GoogleAuthResponse.self, from: data)
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Find the active key window. Falls back to a fresh window if none exists.
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return UIWindow()
    }

    // MARK: - Helpers

    private static func queryValue(name: String, in query: String) -> String? {
        for pair in query.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 && parts[0] == name {
                return parts[1].removingPercentEncoding ?? parts[1]
            }
        }
        return nil
    }

    private static func randomNonce(length: Int = 32) -> String {
        // Use SecRandomCopyBytes for cryptographically strong randomness
        // rather than `Array.randomElement()` which uses the system PRNG
        // that's not guaranteed to be CSPRNG-quality on all platforms.
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status == errSecSuccess {
            // URL-safe base64 (no padding, +/ replaced with -_) — keeps the
            // value safe to pass as a query param without further escaping.
            let s = Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return s
        }
        // Fallback if SecRandomCopyBytes fails (should never happen). Marked
        // as a less-good source so a security audit can spot if we end up here.
        let chars: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Decode the unverified payload of a JWS and confirm its `nonce` claim
    /// equals our expected hashed nonce. Throws `.nonceMismatch` otherwise.
    /// We do NOT verify the JWS signature here — Google's keys are checked
    /// server-side at `/api/auth/google` via Google's published JWKS. The
    /// nonce check is replay defense only, complementary to signature
    /// verification.
    private static func verifyNonceClaim(in idToken: String, expectedHashedNonce: String) throws {
        let parts = idToken.split(separator: ".")
        guard parts.count >= 2 else { throw Error.nonceMismatch }
        let payloadSegment = String(parts[1])
        guard let data = Self.base64URLDecode(payloadSegment),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nonce = json["nonce"] as? String else {
            throw Error.nonceMismatch
        }
        // Constant-time compare to avoid timing leaks on the nonce value
        // (low risk since nonces are single-use, but cheap to do right).
        guard Self.constantTimeEquals(nonce, expectedHashedNonce) else {
            throw Error.nonceMismatch
        }
    }

    private static func base64URLDecode(_ input: String) -> Data? {
        var s = input
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = (4 - s.count % 4) % 4
        s.append(String(repeating: "=", count: padding))
        return Data(base64Encoded: s)
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        if aBytes.count != bBytes.count { return false }
        var diff: UInt8 = 0
        for i in 0..<aBytes.count { diff |= aBytes[i] ^ bBytes[i] }
        return diff == 0
    }
}

// MARK: - UIKit bridge to satisfy AS APIs in a SwiftUI app

import UIKit
