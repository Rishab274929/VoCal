//
//  GoogleSignIn.swift
//  VoCal
//
//  Google OAuth via ASWebAuthenticationSession — no Google SDK required.
//  We use the OAuth 2.0 authorization-code + PKCE flow for native apps:
//    1. Spin up an ASWebAuthenticationSession pointing at
//       https://accounts.google.com/o/oauth2/v2/auth with response_type=code
//    2. User signs in via Safari View Controller (handles 2FA, passkeys, etc.)
//    3. Google redirects to com.EricSpencer.VoCal:/oauth/callback?code=...
//    4. We POST the code + PKCE verifier to /api/auth/google; the backend
//       exchanges it with Google, verifies the ID token, then returns our VoCal
//       JWT. The rest of the app works exactly like the anonymous flow.
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
//  SECURITY: the authorization code is bound to a per-request PKCE verifier
//  before VoCal mints its own JWT. Google may omit `nonce` from the ID token
//  produced by the code exchange, so PKCE is the primary binding for this
//  flow.
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
    static let iosClientID = "877358530849-mef6vo3adi3oidccq610ifv7u7oqjp3c.apps.googleusercontent.com"

    /// The reversed form Google requires as the OAuth redirect scheme.
    /// `com.googleusercontent.apps.1234-abcdefgh`
    static var redirectScheme: String {
        // Drop the trailing ".apps.googleusercontent.com" and reverse the rest.
        let suffix = ".apps.googleusercontent.com"
        guard iosClientID.hasSuffix(suffix) else { return "com.googleusercontent.apps.invalid" }
        let base = String(iosClientID.dropLast(suffix.count))
        return "com.googleusercontent.apps.\(base)"
    }

    static var redirectURI: String {
        "\(redirectScheme):/oauth/callback"
    }

    private var session: ASWebAuthenticationSession?

    @Published private(set) var isSigningIn = false
    @Published var lastError: String?

    enum Error: Swift.Error, LocalizedError {
        case notConfigured
        case userCancelled
        case noAuthorizationCode
        case stateMismatch
        case backend(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google sign-in isn't configured yet. Paste your iOS client ID."
            case .userCancelled: "Sign-in cancelled."
            case .noAuthorizationCode: "Google didn't return an authorization code."
            case .stateMismatch: "Google sign-in returned an invalid session state. Try again."
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
        let codeVerifier = Self.randomNonce(length: 64)
        let codeChallenge = Self.sha256Base64URL(codeVerifier)
        let state = Self.randomNonce()
        let authURL = try buildAuthURL(
            hashedNonce: hashedNonce,
            codeChallenge: codeChallenge,
            state: state
        )
        let authorizationCode = try await runWebAuthSession(authURL: authURL, expectedState: state)
        return try await exchangeWithBackend(
            authorizationCode: authorizationCode,
            codeVerifier: codeVerifier,
            redirectURI: Self.redirectURI,
            nonce: hashedNonce,
            linkAnonymousUserID: linkAnonymousUserID,
            linkAnonymousToken: linkAnonymousToken
        )
    }

    // MARK: - OAuth URL

    private func buildAuthURL(hashedNonce: String, codeChallenge: String, state: String) throws -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: Self.iosClientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "nonce", value: hashedNonce),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            // Force a fresh authorization to surface the account chooser if
            // the user has multiple Google accounts. Without this, Google
            // silently re-uses whichever one is "first" in their cookies.
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        guard let url = c.url else { throw Error.notConfigured }
        return url
    }

    // MARK: - Web auth session

    private func runWebAuthSession(authURL: URL, expectedState: String) async throws -> String {
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
                guard let callbackURL else {
                    continuation.resume(throwing: Error.noAuthorizationCode)
                    return
                }
                if let returnedError = Self.callbackValue(name: "error", in: callbackURL) {
                    continuation.resume(throwing: Error.backend(returnedError))
                    return
                }
                guard let returnedState = Self.callbackValue(name: "state", in: callbackURL),
                      Self.constantTimeEquals(returnedState, expectedState) else {
                    continuation.resume(throwing: Error.stateMismatch)
                    return
                }
                guard let code = Self.callbackValue(name: "code", in: callbackURL) else {
                    continuation.resume(throwing: Error.noAuthorizationCode)
                    return
                }
                continuation.resume(returning: code)
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
            if !session.start() {
                continuation.resume(throwing: Error.notConfigured)
                return
            }
        }
    }

    // MARK: - Backend exchange

    private func exchangeWithBackend(
        authorizationCode: String,
        codeVerifier: String,
        redirectURI: String,
        nonce: String,
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
        var payload: [String: String] = [
            "authorization_code": authorizationCode,
            "code_verifier": codeVerifier,
            "redirect_uri": redirectURI,
            "nonce": nonce
        ]
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
                let formDecoded = parts[1].replacingOccurrences(of: "+", with: " ")
                return formDecoded.removingPercentEncoding ?? formDecoded
            }
        }
        return nil
    }

    private static func callbackValue(name: String, in url: URL) -> String? {
        if let query = url.query,
           let value = queryValue(name: name, in: query) {
            return value
        }
        if let fragment = url.fragment,
           let value = queryValue(name: name, in: fragment) {
            return value
        }
        return nil
    }

    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let aa = Array(a.utf8)
        let bb = Array(b.utf8)
        var diff = aa.count ^ bb.count
        let count = max(aa.count, bb.count)
        for i in 0..<count {
            diff |= Int(aa.indices.contains(i) ? aa[i] : 0) ^ Int(bb.indices.contains(i) ? bb[i] : 0)
        }
        return diff == 0
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

    private static func sha256Base64URL(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - UIKit bridge to satisfy AS APIs in a SwiftUI app

import UIKit
