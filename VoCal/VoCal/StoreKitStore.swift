//
//  StoreKitStore.swift
//  VoCal
//
//  StoreKit 2 wrapper. Fetches the two Pro products, handles purchase,
//  listens to `Transaction.updates` for restores + renewals, and flips
//  `AppModel.profile.entitlement` to `.pro` on success.
//
//  TestFlight sandbox path: Apple's StoreKit honors sandbox sign-ins
//  automatically when the build comes from TestFlight or Xcode. No
//  config flag needed on our side — sandbox transactions arrive through
//  the same Transaction.updates stream.
//
//  Server entitlement path: local StoreKit remains the device source of truth
//  for purchase UX, then the app posts the App Store receipt to
//  /api/entitlements/refresh so Cloudflare can populate user_entitlements.
//  Pro-gated backend endpoints require that server row.
//
//  Lifecycle: `StoreKitStore.shared` is a process-wide singleton. The
//  transaction listener spins up on first access (from `VoCalApp` at
//  launch) and lives for the lifetime of the app process — not just
//  while the paywall sheet is open. Without this, refunds, renewals,
//  ask-to-buy approvals, and cross-device restores that arrive while
//  the paywall is closed would be silently dropped and the user would
//  either keep premium they no longer paid for OR lose premium they
//  did pay for, depending on direction. App-wide ownership also lets
//  the `Transaction.unfinished` drain on cold launch catch any prior
//  pending purchase that completed between sessions.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class StoreKitStore: ObservableObject {
    /// App-wide singleton. Initialized once on first access — currently
    /// triggered by `AuthSession.init()` so the transaction listener is up
    /// before any UI is shown. PaywallSheet binds to the same instance via
    /// `@ObservedObject private var store = StoreKitStore.shared`.
    static let shared = StoreKitStore()

    // Product identifiers configured in App Store Connect.
    // These must match the In-App Purchase product IDs exactly.
    static let monthlyID = "com.EricSpencer.VoCal.pro.monthly"
    static let annualID  = "com.EricSpencer.VoCal.pro.annual"
    static let productIDs: Set<String> = [monthlyID, annualID]

    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    enum Plan: Hashable, CaseIterable { case monthly, annual }

    @Published private(set) var products: [Product] = []
    @Published private(set) var state: LoadState = .idle
    @Published private(set) var isPurchasing = false
    @Published private(set) var hasPro = false
    @Published private(set) var lastServerSyncAt: Date?
    @Published var lastError: String?

    /// Mirror of `hasPro` written to UserDefaults so a cold launch can paint
    /// the gated UI before StoreKit's async `currentEntitlements` resolves.
    /// Source of truth is still Apple — this is just a cache.
    static let entitlementCacheKey = "vocal.entitlement.pro.v1"

    private var transactionListener: Task<Void, Never>?
    private var lastServerSyncAttemptAt: Date?

    private struct EntitlementRefreshResponse: Decodable {
        let is_pro: Bool
        let product_id: String?
        let expires_at: Int64?
    }

    private struct APIError: Decodable {
        let error: String?
    }

    private init() {
        // Seed `hasPro` from the cached value so the UI doesn't flicker
        // free→pro on launch for an already-subscribed user.
        self.hasPro = UserDefaults.standard.bool(forKey: Self.entitlementCacheKey)

        // Spin up the renewal/restore listener immediately. Without this,
        // a TestFlight tester who restores a purchase from a different
        // device won't see it reflected on this device until next launch.
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(verificationResult: result)
            }
        }

        // Self-bootstrap: drain any unfinished transactions from the prior
        // session and re-sync the entitlement cache against Apple's truth.
        // Fire-and-forget; the UI uses the cached `hasPro` until this
        // resolves. Without this, a purchase that completed while the app
        // was killed (e.g. ask-to-buy approved overnight) wouldn't be
        // recognized until the user manually tapped Restore.
        Task { [weak self] in
            await self?.bootstrap()
        }
    }

    // deinit intentionally omitted: this is a singleton, never deallocates.
    // The Transaction.updates listener lives for the lifetime of the process
    // by design — cancelling it would defeat the whole point of having a
    // listener that survives sheet open/close cycles.

    // MARK: - Cold-launch drain

    /// Call once from `VoCalApp` at launch. Drains any unfinished
    /// transactions from the previous session and refreshes the entitlement
    /// cache against Apple's current state. Safe to call multiple times.
    func bootstrap() async {
        // Apple's recommendation: drain Transaction.unfinished on launch so
        // any purchase that completed while the app was killed gets finished
        // and credited.
        for await result in Transaction.unfinished {
            await handle(verificationResult: result)
        }
        await refreshEntitlement(forceServerSync: true, surfaceSyncErrors: false)
    }

    // MARK: - Loading

    func loadProducts() async {
        // Don't re-fetch if we already have both products loaded.
        if state == .loaded, products.count == Self.productIDs.count { return }
        state = .loading
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            // Stable ordering: annual first (the "save 33%" plan), monthly second.
            products = fetched.sorted { lhs, rhs in
                lhs.id == Self.annualID && rhs.id != Self.annualID
            }
            // `Product.products(for:)` does NOT throw when the store returns
            // an empty set — it just yields []. The most common cause in the
            // simulator is that the Xcode scheme has no StoreKit Configuration
            // file selected, so the local store has zero products to vend.
            // Surface that explicitly instead of leaving the paywall stuck
            // on "$4.99 / month" placeholder prices with no way to buy.
            if products.isEmpty {
                let msg = "No products returned. In Simulator: enable the StoreKit Configuration file in Edit Scheme → Run → Options. In TestFlight/App Store: products may still be propagating in App Store Connect."
                state = .failed(msg)
                lastError = msg
            } else {
                state = .loaded
            }
            await refreshEntitlement()
        } catch {
            state = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func product(for plan: Plan) -> Product? {
        switch plan {
        case .monthly: return products.first { $0.id == Self.monthlyID }
        case .annual:  return products.first { $0.id == Self.annualID }
        }
    }

    // MARK: - Purchase

    @discardableResult
    func purchase(_ plan: Plan) async -> Bool {
        guard let product = product(for: plan) else {
            lastError = "Plan not available. Check your App Store Connect IAPs."
            return false
        }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let success = await handle(verificationResult: verification)
                return success
            case .userCancelled:
                return false
            case .pending:
                // Ask-to-buy / SCA flow. We'll get the transaction via
                // Transaction.updates when it eventually completes.
                lastError = "Purchase pending parental approval."
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    /// Re-check entitlements from Apple. Called on App resume + after a
    /// "Restore Purchases" tap. Surfaces a friendly message if there was
    /// nothing to restore so the spinner doesn't appear stuck.
    func restore() async {
        // Optimistically clear any prior error so the user sees fresh state.
        let priorEntitlement = hasPro
        lastError = nil
        do {
            try await AppStore.sync()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
            return
        }
        await refreshEntitlement(forceServerSync: true, surfaceSyncErrors: true)
        if !priorEntitlement && !hasPro {
            // Sync succeeded but no eligible purchase exists for this Apple ID.
            lastError = "No prior purchase found for this Apple ID."
        }
    }

    // MARK: - Entitlement

    /// True if the user currently owns an active Pro subscription.
    /// Drives the @Published `hasPro` flag plus the UserDefaults cache.
    @discardableResult
    func refreshEntitlement(
        forceServerSync: Bool = false,
        surfaceSyncErrors: Bool = false
    ) async -> Bool {
        var found = false
        for await result in Transaction.currentEntitlements {
            // Only trust VERIFIED entitlements. An unverified result here
            // means the JWS signature didn't check out — could be jailbreak
            // tampering. Treat as not-entitled.
            if case .verified(let txn) = result, Self.productIDs.contains(txn.productID) {
                // currentEntitlements only yields ACTIVE (unrevoked, unexpired) entitlements,
                // so reaching this point means the user is paid up RIGHT NOW.
                // Defense in depth: also check `revocationDate` and `isUpgraded` in case
                // a future SDK version yields revoked ones.
                if txn.revocationDate == nil && !txn.isUpgraded {
                    found = true
                    break
                }
            }
        }
        hasPro = found
        UserDefaults.standard.set(found, forKey: Self.entitlementCacheKey)
        if found {
            await syncServerEntitlement(force: forceServerSync, surfaceErrors: surfaceSyncErrors)
        }
        return found
    }

    @discardableResult
    func syncServerEntitlement(force: Bool = false, surfaceErrors: Bool = true) async -> Bool {
        guard hasPro else { return false }
        let now = Date()
        if !force, let last = lastServerSyncAttemptAt, now.timeIntervalSince(last) < 30 {
            return true
        }
        lastServerSyncAttemptAt = now

        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            if surfaceErrors {
                lastError = "App Store receipt unavailable. Restore purchases and try again."
            }
            return false
        }

        let receiptData: Data
        do {
            receiptData = try Data(contentsOf: receiptURL)
        } catch {
            if surfaceErrors {
                lastError = "App Store receipt unavailable. Restore purchases and try again."
            }
            return false
        }

        guard !receiptData.isEmpty else {
            if surfaceErrors {
                lastError = "App Store receipt is empty. Restore purchases and try again."
            }
            return false
        }

        guard let url = URL(string: "\(APIConfig.baseURL)/entitlements/refresh") else {
            if surfaceErrors { lastError = "Bad entitlement sync URL." }
            return false
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 20
        await AuthSession.shared.authorize(&req)
        req.httpBody = try? JSONEncoder().encode([
            "receipt_data": receiptData.base64EncodedString()
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                if surfaceErrors { lastError = "Bad entitlement sync response." }
                return false
            }
            if (200..<300).contains(http.statusCode) {
                let decoded = try JSONDecoder().decode(EntitlementRefreshResponse.self, from: data)
                if decoded.is_pro {
                    lastServerSyncAt = Date()
                    return true
                }
                if surfaceErrors {
                    lastError = "Apple receipt did not include an active VoCal Pro subscription."
                }
                return false
            }

            let msg = (try? JSONDecoder().decode(APIError.self, from: data).error) ?? "HTTP \(http.statusCode)"
            if surfaceErrors {
                switch http.statusCode {
                case 401:
                    lastError = "Sign in again to sync Pro with VoCal."
                case 503:
                    lastError = "VoCal Pro is active on this device, but server receipt validation is not configured yet."
                default:
                    lastError = "Couldn't sync Pro with VoCal: \(msg)"
                }
            }
            return false
        } catch {
            if surfaceErrors {
                lastError = "Couldn't sync Pro with VoCal: \(error.localizedDescription)"
            }
            return false
        }
    }

    @discardableResult
    private func handle(verificationResult: VerificationResult<Transaction>) async -> Bool {
        switch verificationResult {
        case .verified(let txn):
            // Finish the transaction so Apple stops re-delivering it on launch.
            await txn.finish()
            await refreshEntitlement(forceServerSync: true, surfaceSyncErrors: true)
            return Self.productIDs.contains(txn.productID)
        case .unverified(_, let error):
            // SECURITY: never grant entitlement on an unverified transaction.
            // The JWS signature check is our only defense against a tampered
            // client claiming pro. Surface the error for diagnostics.
            lastError = "Unverified purchase: \(error.localizedDescription)"
            return false
        }
    }
}

// MARK: - Pricing helpers

extension StoreKitStore {
    /// Localized price string for a plan. Falls back to a placeholder if
    /// products haven't loaded yet (during the first paint of the paywall).
    func displayPrice(for plan: Plan) -> String {
        switch (plan, product(for: plan)) {
        case (.monthly, let p?): return p.displayPrice
        case (.annual,  let p?): return p.displayPrice
        case (.monthly, nil):    return "$4.99"
        case (.annual,  nil):    return "$39.99"
        }
    }

    /// `"month"` / `"year"` style unit string for the price row.
    func priceUnit(for plan: Plan) -> String {
        switch plan {
        case .monthly: return "month"
        case .annual:  return "year"
        }
    }
}
