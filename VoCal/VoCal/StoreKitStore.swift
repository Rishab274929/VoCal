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
//  RevenueCat path (optional): when you create the VoCal project at
//  https://app.revenuecat.com and paste the iOS API key into APIConfig,
//  this store can hand off entitlement queries to RC. Until then, we
//  source of truth straight from Apple via Transaction.currentEntitlements.
//

import Foundation
import StoreKit
import Combine

@MainActor
final class StoreKitStore: ObservableObject {
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
    @Published var lastError: String?

    private var transactionListener: Task<Void, Never>?

    init() {
        // Spin up the renewal/restore listener immediately. Without this,
        // a TestFlight tester who restores a purchase from a different
        // device won't see it reflected on this device until next launch.
        transactionListener = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(verificationResult: result)
            }
        }
    }

    deinit { transactionListener?.cancel() }

    // MARK: - Loading

    func loadProducts() async {
        state = .loading
        do {
            let fetched = try await Product.products(for: Self.productIDs)
            // Stable ordering: annual first (the "save 33%" plan), monthly second.
            products = fetched.sorted { lhs, rhs in
                lhs.id == Self.annualID && rhs.id != Self.annualID
            }
            state = .loaded
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
    /// "Restore Purchases" tap.
    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = "Restore failed: \(error.localizedDescription)"
        }
        await refreshEntitlement()
    }

    // MARK: - Entitlement

    /// True if the user currently owns an active Pro subscription.
    func refreshEntitlement() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let txn) = result, Self.productIDs.contains(txn.productID) {
                // currentEntitlements only yields ACTIVE (unrevoked, unexpired) entitlements.
                hasPro = true
                return
            }
        }
        hasPro = false
    }

    @discardableResult
    private func handle(verificationResult: VerificationResult<Transaction>) async -> Bool {
        switch verificationResult {
        case .verified(let txn):
            // Finish the transaction so Apple stops re-delivering it on launch.
            await txn.finish()
            await refreshEntitlement()
            return Self.productIDs.contains(txn.productID)
        case .unverified(_, let error):
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
