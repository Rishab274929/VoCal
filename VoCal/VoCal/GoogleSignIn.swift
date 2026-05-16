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

import Foundation
import AuthenticationServices
import Combine

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
        case backend(String)
        var errorDescription: String? {
            switch self {
            case .notConfigured: "Google sign-in isn't configured yet. Paste your iOS client ID."
            case .userCancelled: "Sign-in cancelled."
            case .noIDToken:     "Google didn't return an id_token."
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
    func signIn() async throws -> GoogleAuthResponse {
        guard Self.iosClientID.hasPrefix("PASTE") == false else {
            throw Error.notConfigured
        }
        isSigningIn = true
        defer { isSigningIn = false }

        let nonce = Self.randomNonce()
        let authURL = try buildAuthURL(nonce: nonce)
        let idToken = try await runWebAuthSession(authURL: authURL)
        return try await exchangeWithBackend(idToken: idToken)
    }

    // MARK: - OAuth URL

    private func buildAuthURL(nonce: String) throws -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id", value: Self.iosClientID),
            URLQueryItem(name: "redirect_uri", value: "\(Self.redirectScheme):/oauth/callback"),
            URLQueryItem(name: "response_type", value: "id_token"),
            URLQueryItem(name: "scope", value: "openid email profile"),
            URLQueryItem(name: "nonce", value: nonce)
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
            session.prefersEphemeralWebBrowserSession = false  // share cookies with Safari so the user stays signed in
            self.session = session
            session.start()
        }
    }

    // MARK: - Backend exchange

    private func exchangeWithBackend(idToken: String) async throws -> GoogleAuthResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/google") else {
            throw Error.backend("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONEncoder().encode(["id_token": idToken])
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
        let chars: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<length).map { _ in chars.randomElement()! })
    }
}

// MARK: - UIKit bridge to satisfy AS APIs in a SwiftUI app

import UIKit
