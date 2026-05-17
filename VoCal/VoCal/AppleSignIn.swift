//
//  AppleSignIn.swift
//  VoCal
//
//  Sign in with Apple via AuthenticationServices. Apple Review Guideline 4.8
//  REQUIRES Sign in with Apple to be offered alongside any third-party social
//  login (Google, etc.). Without this, App Store submission gets auto-rejected.
//
//  ──────────────────────────────────────────────────────────────────────────
//  PROVISIONING NOTE (read this before debugging SiwA in production)
//
//  If Sign in with Apple fails in production with `ASAuthorizationError`
//  (canceled / unknown / failed), the issue is almost certainly a STALE
//  PROVISIONING PROFILE, not this code. The capability has to be present
//  on developer.apple.com for the bundle ID AND in the embedded profile
//  inside the .ipa. A TestFlight build produced before the capability was
//  enabled will keep failing every SiwA request even after the capability
//  is toggled on, because the profile baked into that build predates it.
//
//  Fix path (in order of speed):
//    1. Xcode → target → Signing & Capabilities → toggle "Automatically
//       manage signing" OFF and then back ON. Xcode regenerates a fresh
//       profile that includes the SiwA entitlement.
//    2. Or: Xcode → Settings → Accounts → your team → Download Manual
//       Profiles. Pulls the freshest provisioning profiles from Apple.
//    3. Rebuild + re-upload to TestFlight. The OLD build will keep
//       failing — there is no over-the-air entitlement patch.
//
//  Sanity check: `codesign -d --entitlements - VoCal.app` should show
//  `com.apple.developer.applesignin` in the entitlement dict. If it's
//  missing, the build was signed without the capability — go back to
//  step 1.
//  ──────────────────────────────────────────────────────────────────────────
//
//  Flow:
//    1. Generate a CSPRNG nonce. Hash it to SHA-256 and stamp the hash onto
//       the ASAuthorizationAppleIDRequest. Apple binds the hash into the
//       returned identity_token's `nonce` claim — replay defense.
//    2. Run ASAuthorizationController to surface Apple's native sheet.
//       User authenticates with Face ID / Touch ID / passcode + chooses
//       whether to share their real email or a private relay email.
//    3. On success we get back: identity_token (signed JWT from Apple),
//       an optional authorization_code (short-lived, server can exchange
//       for refresh token if it ever needs to), user_id (stable across
//       reinstalls on the same Apple ID), and — first time only —
//       full_name + email.
//    4. POST all of that to /api/auth/apple. Backend verifies the JWS
//       against Apple's published JWKS, optionally exchanges the auth
//       code with Apple's token endpoint, and returns our own JWT.
//
//  Why a separate file vs. inline in AuthSession: keeps the
//  ASAuthorizationControllerDelegate dance + Combine wiring out of
//  AuthSession, which stays a thin Keychain + token wrapper. Same split
//  we already use for GoogleSignIn.swift.
//
//  SECURITY: full_name and email arrive ONLY on the first sign-in (Apple
//  policy). On any subsequent sign-in Apple returns nil for both. The
//  server must persist them on first contact; iOS forwards them verbatim
//  without trying to cache them locally (we'd just duplicate the server
//  state — and a stale local cache is more attack surface than it's worth).
//

import Foundation
import AuthenticationServices
import CryptoKit
import Combine

@MainActor
final class AppleSignIn: NSObject, ObservableObject {
    static let shared = AppleSignIn()

    enum Error: Swift.Error, LocalizedError {
        case userCancelled
        case noIdentityToken
        case backend(String)
        case underlying(Swift.Error)

        var errorDescription: String? {
            switch self {
            case .userCancelled:           "Sign-in cancelled."
            case .noIdentityToken:         "Apple didn't return an identity token."
            case .backend(let m):           m
            case .underlying(let e):        e.localizedDescription
            }
        }
    }

    struct AppleAuthResponse: Codable {
        let user_id: String
        let token: String
        let expires_at: Int64
        let is_new_user: Bool?
    }

    /// In-flight raw nonce for the active authorization request. The backend
    /// hashes this value and compares it with the signed identity_token's
    /// `nonce` claim before issuing a VoCal JWT.
    private var currentRawNonce: String?

    /// Bridges the delegate-based ASAuthorizationController API into a
    /// modern async throws. The controller's delegate calls back exactly
    /// once per request (success or failure), so a CheckedContinuation is
    /// safe.
    private var pendingContinuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Swift.Error>?

    /// Imperative path: kicks off the native Sign-in-with-Apple flow via an
    /// internal ASAuthorizationController, then exchanges the credential
    /// with our backend. Use this when there's no SwiftUI
    /// `SignInWithAppleButton` available (e.g. UIKit surfaces, programmatic
    /// triggers).
    ///
    /// SwiftUI views should prefer `SignInWithAppleButton` + the
    /// `prepareNonce` / `completeAuthorization` pair below so Apple's
    /// official button styling (required by their HIG) is preserved.
    ///
    /// - Parameter linkAnonymousUserID: if the device is currently anon, pass
    ///   that user_id so the backend can merge meals/profile into the new
    ///   Apple identity. Mirrors what GoogleSignIn.signIn does.
    /// - Parameter linkAnonymousToken: the anonymous JWT — proof we own that
    ///   anonymous user_id.
    func signIn(
        linkAnonymousUserID: String? = nil,
        linkAnonymousToken: String? = nil
    ) async throws -> AppleAuthResponse {
        let (_, hashedNonce) = prepareNonce()

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = hashedNonce

        let credential: ASAuthorizationAppleIDCredential
        do {
            credential = try await runAuthorizationController(request: request)
        } catch let e as Error {
            throw e
        } catch let e as ASAuthorizationError where e.code == .canceled {
            throw Error.userCancelled
        } catch {
            throw Error.underlying(error)
        }

        return try await completeAuthorization(
            credential: credential,
            linkAnonymousUserID: linkAnonymousUserID,
            linkAnonymousToken: linkAnonymousToken
        )
    }

    /// SwiftUI path step 1: generate a CSPRNG nonce, stash the raw form for
    /// later, and return the hashed form to stamp onto the
    /// ASAuthorizationAppleIDRequest. Called from
    /// `SignInWithAppleButton.onRequest`.
    @discardableResult
    func prepareNonce() -> (rawNonce: String, hashedNonce: String) {
        let raw = Self.randomNonce()
        let hashed = Self.sha256Hex(raw)
        currentRawNonce = raw
        return (raw, hashed)
    }

    /// SwiftUI path step 2: given the credential returned by
    /// `SignInWithAppleButton.onCompletion`, exchange it with our backend
    /// and return the JWT response.
    ///
    /// Reuses the raw nonce stashed by `prepareNonce()` so we don't lose
    /// replay defense between the request and the callback.
    func completeAuthorization(
        credential: ASAuthorizationAppleIDCredential,
        linkAnonymousUserID: String? = nil,
        linkAnonymousToken: String? = nil
    ) async throws -> AppleAuthResponse {
        guard let identityTokenData = credential.identityToken,
              let identityToken = String(data: identityTokenData, encoding: .utf8) else {
            throw Error.noIdentityToken
        }
        let authorizationCode = credential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }
            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        guard let rawNonce = currentRawNonce else {
            throw Error.backend("Apple sign-in nonce was not prepared. Try again.")
        }
        defer { currentRawNonce = nil }

        // full_name + email are nil on every sign-in AFTER the first.
        // Server is responsible for persisting them on first contact.
        let fullName: [String: String]?
        if let pn = credential.fullName {
            var name: [String: String] = [:]
            if let given = pn.givenName?.trimmingCharacters(in: .whitespaces), !given.isEmpty {
                name["given"] = given
            }
            if let family = pn.familyName?.trimmingCharacters(in: .whitespaces), !family.isEmpty {
                name["family"] = family
            }
            fullName = name.isEmpty ? nil : name
        } else {
            fullName = nil
        }

        return try await exchangeWithBackend(
            identityToken: identityToken,
            authorizationCode: authorizationCode,
            nonce: rawNonce,
            userID: credential.user,
            fullName: fullName,
            email: credential.email,
            linkAnonymousUserID: linkAnonymousUserID,
            linkAnonymousToken: linkAnonymousToken
        )
    }

    // MARK: - Controller plumbing

    private func runAuthorizationController(request: ASAuthorizationAppleIDRequest) async throws -> ASAuthorizationAppleIDCredential {
        try await withCheckedThrowingContinuation { continuation in
            self.pendingContinuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Backend exchange

    private func exchangeWithBackend(
        identityToken: String,
        authorizationCode: String?,
        nonce: String,
        userID: String,
        fullName: [String: String]?,
        email: String?,
        linkAnonymousUserID: String?,
        linkAnonymousToken: String?
    ) async throws -> AppleAuthResponse {
        guard let url = URL(string: "\(APIConfig.baseURL)/auth/apple") else {
            throw Error.backend("Bad URL")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15

        // Build payload as [String: AnyHashable]-style dictionary serialized
        // by JSONSerialization so we can omit nil keys cleanly rather than
        // sending `"email": null` (some servers treat that differently from
        // an absent key).
        var payload: [String: Any] = [
            "identity_token": identityToken,
            "nonce": nonce,
            "user_id": userID
        ]
        if let authorizationCode = authorizationCode { payload["authorization_code"] = authorizationCode }
        if let fullName  = fullName  { payload["full_name"] = fullName }
        if let email     = email     { payload["email"] = email }
        if let uid       = linkAnonymousUserID { payload["link_anonymous_user_id"] = uid }
        if let tok       = linkAnonymousToken  { payload["link_anonymous_token"] = tok }
        req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.backend("Bad response") }
        if !(200..<300).contains(http.statusCode) {
            struct Err: Codable { let error: String? }
            let msg = (try? JSONDecoder().decode(Err.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Error.backend(msg)
        }
        return try JSONDecoder().decode(AppleAuthResponse.self, from: data)
    }

    // MARK: - Nonce helpers

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        if status == errSecSuccess {
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        // Fallback if SecRandomCopyBytes fails (should never happen).
        let chars: [Character] = Array("0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func sha256Hex(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate / PresentationContextProviding

extension AppleSignIn: ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        Task { @MainActor in
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential else {
                self.pendingContinuation?.resume(throwing: Error.noIdentityToken)
                self.pendingContinuation = nil
                return
            }
            self.pendingContinuation?.resume(returning: cred)
            self.pendingContinuation = nil
        }
    }

    nonisolated func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Swift.Error) {
        Task { @MainActor in
            self.pendingContinuation?.resume(throwing: error)
            self.pendingContinuation = nil
        }
    }

    nonisolated func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Find the active key window. Falls back to a fresh window if none exists.
        // The closure is nonisolated, so we have to do the UIKit dance from
        // off-MainActor; UIApplication.shared is thread-safe for these reads.
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
           let window = scene.windows.first(where: { $0.isKeyWindow }) {
            return window
        }
        return UIWindow()
    }
}

// MARK: - UIKit bridge

import UIKit
