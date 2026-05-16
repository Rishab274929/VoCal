# VoCal payments setup — TestFlight + production

The iOS app uses StoreKit 2 directly. Adding RevenueCat on top is optional
(useful for analytics, cross-platform entitlement sync, and webhook
delivery to the backend), but the purchase flow works on TestFlight with
**only** the App Store Connect side configured.

## Product identifiers

These IDs live in [StoreKitStore.swift](../VoCal/VoCal/StoreKitStore.swift)
and must match App Store Connect exactly:

| Product | ID | Period | Price |
|---|---|---|---|
| VoCal Pro Monthly | `com.EricSpencer.VoCal.pro.monthly` | 1 month | $4.99 |
| VoCal Pro Annual  | `com.EricSpencer.VoCal.pro.annual`  | 1 year, 7-day free trial | $39.99 |

## App Store Connect — one-time setup (REQUIRED for TestFlight)

1. Sign in to https://appstoreconnect.apple.com → My Apps → VoCal.
2. **Agreements, Tax, and Banking** must be active. If it says
   "Action Required" you can't sell anything until it's done — this is
   the most common reason in-app purchases don't show up in sandbox.
3. Click **VoCal → In-App Purchases → +**.
4. Choose **Auto-Renewable Subscription** for both products.
5. Create a subscription group called **VoCal Pro** (the two products will
   live in the same group so users can upgrade/downgrade between them).
6. Add each product:
   - Reference name: `VoCal Pro Monthly` / `VoCal Pro Annual`
   - Product ID: exact match from the table above
   - Subscription duration: 1 month / 1 year
   - Annual plan: add an **Introductory Offer** → Free Trial → 1 week
7. Localizations: at minimum English (US) — name + description (copy from
   [VoCal.storekit](../VoCal/VoCal.storekit)).
8. Set price ($4.99 / $39.99) for the US tier.
9. Add a screenshot for App Review (the paywall screenshot).
10. Submit each product for review. Review takes ~1 day. **Products must
    be in state `Ready to Submit` or `Approved` before they appear in
    StoreKit sandbox**, even for TestFlight.

## TestFlight sandbox testing

1. Create a Sandbox Tester account: App Store Connect → Users and Access
   → Sandbox Testers → +. Use an email you don't already have an Apple
   account for.
2. On the iPhone running the TestFlight build:
   - Settings → App Store → Sandbox Account → sign in with the tester
     account you just created.
3. Open VoCal, hit the paywall, tap Subscribe. You'll see the system
   purchase sheet with a `[Environment: Sandbox]` banner. Confirm.
4. Apple speeds sandbox subscriptions: monthly renews every 5 minutes,
   annual every 1 hour. So you can see renewal behavior in minutes.

## Local simulator testing (no App Store Connect needed)

For Xcode debug runs we ship [`VoCal/VoCal.storekit`](../VoCal/VoCal.storekit)
which defines the same two products locally. To use it:

1. Open the scheme editor (`Cmd-Shift-,`).
2. Run → Options → **StoreKit Configuration** → select `VoCal.storekit`.
3. Hit Run. The paywall now shows real-looking prices and the purchase
   flow runs entirely on-device — no Apple account, no card.

The transaction observer in `StoreKitStore.swift` works identically
against this local config and against real sandbox / production.

## RevenueCat (optional — recommended for prod)

We haven't wired RevenueCat yet because:
- The auto-mode classifier blocked the agent from creating a project in
  the user's RC dashboard.
- RC isn't required for TestFlight to work — StoreKit 2 alone is enough.

To add RC later:

1. Sign in to https://app.revenuecat.com and create a project called **VoCal**.
2. Apps → New → iOS:
   - Bundle ID: `com.EricSpencer.VoCal`
   - App Store Connect Shared Secret: from App Store Connect → Users
     → Shared Secret (App-Specific Shared Secret is fine).
3. Products → import both `com.EricSpencer.VoCal.pro.*` from App Store
   Connect (RC reads them automatically).
4. Offerings → create a default offering with both packages: `$rc_monthly`
   and `$rc_annual`.
5. Entitlements → create `pro` → attach both products.
6. Copy the **Public API Key (iOS)** from Project settings → API keys.
7. Add the Swift Package: in Xcode → File → Add Package Dependencies →
   `https://github.com/RevenueCat/purchases-ios` → Up to Next Major.
8. In [VoCalApp.swift](../VoCal/VoCal/VoCalApp.swift), early in
   `init()` of the app, add:
   ```swift
   import RevenueCat
   ...
   Purchases.configure(withAPIKey: "appl_XXX_paste_from_rc")
   ```
9. Replace the direct StoreKit calls in `StoreKitStore.swift` with
   `Purchases.shared.getOfferings()` / `Purchases.shared.purchase(package:)`,
   or — easier — keep the StoreKit flow and use RC's
   `StoreKit2TransactionListener` to mirror transactions to RC for
   analytics + webhook delivery to our `/api/auth` endpoint.

The webhook → backend hook is the most valuable bit: RC will POST to
`https://vocal.best/api/webhooks/revenuecat` on every purchase/renewal/
cancellation, giving the server authoritative entitlement state for
the user (vs. trusting the client).
