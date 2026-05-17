//
//  PaywallSheet.swift
//  VoCal
//
//  Hard paywall after onboarding. Sandbox-mode wireframe — purchase flow
//  shells RevenueCat behavior via callbacks so the demo works on TestFlight
//  with a sandbox account.
//

import SwiftUI

struct PaywallSheet: View {
    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    // Use the app-wide singleton so the transaction listener that's been
    // running since launch is the same instance the paywall is bound to —
    // otherwise renewals/refunds that arrived before the user opened the
    // sheet would be invisible to it.
    //
    // `@ObservedObject` (not `@StateObject`) because the singleton's
    // lifetime is NOT owned by this view — it's owned by the app. Using
    // `@StateObject` here would still work but produce a spurious second
    // retain and obscure the ownership semantics.
    @ObservedObject private var store = StoreKitStore.shared

    var onSubscribe: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    @State private var plan: StoreKitStore.Plan = .annual
    @State private var restoring = false
    @State private var didCompleteSubscription = false

    var body: some View {
        ZStack {
            AmbientBackground()

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VoCalWordmark()
                    Text("PRO")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.Palette.ink)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Theme.Palette.voltage))
                    Spacer()
                    // Show the X only when this is an exploratory upgrade flow
                    // launched from Profile (a `pro` user wanting to inspect)
                    // or after the user already has pro (so they can close it).
                    // For the post-onboarding hard paywall (no callbacks set,
                    // user is still .free) the X is hidden — they must
                    // subscribe, restore, or use the explicit "Maybe later"
                    // route exposed by callers that pass `onSkip`.
                    if onSkip == nil && (appModel.profile.entitlement == .pro || store.hasPro) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.Palette.ash)
                                .frame(width: 30, height: 30)
                                .background(Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 20)

                ScrollView {
                    VStack(alignment: .leading, spacing: 28) {
                        headline
                        features
                        planPicker
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 24)
            }
        }
        // SECURITY: lock the sheet against swipe-down dismissal during the
        // post-onboarding hard-paywall flow. Without this, the iOS
        // interactive-dismiss gesture lets the user swipe past the paywall
        // even though we hid the X button. We allow dismiss only when:
        //  - there's an explicit `onSkip` callback (caller is OnboardingFlow,
        //    which has its own "Maybe later" → finish() path), OR
        //  - the user has already purchased (so the sheet is in an
        //    "informational" mode).
        .interactiveDismissDisabled(
            onSkip == nil
            && appModel.profile.entitlement != .pro
            && !store.hasPro
        )
    }

    // MARK: headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("UPGRADE")
                .eyebrow(Theme.Palette.pulse)
            (
                Text("Track every chain meal. ")
                    .foregroundStyle(Theme.Palette.bone)
                + Text("By voice.")
                    .foregroundStyle(Theme.Palette.voltage)
                    .font(Theme.Font.serif(36, weight: .medium, italic: true))
            )
            .font(Theme.Font.serif(36, weight: .medium))
            .lineSpacing(2)

            Text("Unlimited voice logging. Restaurant-aware macros. Photo fact-check. Body fat from selfies. Apple Watch + Live Activity.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.Palette.ash)
                .padding(.top, 4)
        }
    }

    // MARK: features

    private var features: some View {
        VStack(spacing: 0) {
            featureRow(icon: "waveform", title: "Unlimited voice logs", detail: "Free is 3/day. Pro: unlimited.")
            divider
            featureRow(icon: "fork.knife", title: "Restaurant intelligence", detail: "Top 25 chains, plus agentic search.")
            divider
            featureRow(icon: "camera.viewfinder", title: "Photo + voice fact-check", detail: "Snap, answer, log.")
            divider
            featureRow(icon: "figure.arms.open", title: "BF% from selfies", detail: "Front + side photo, with confidence band.")
            divider
            featureRow(icon: "applewatch.radiowaves.left.and.right", title: "Watch + Live Activity", detail: "Log from your wrist or Dynamic Island.")
            divider
            featureRow(icon: "bubble.left.and.text.bubble.right", title: "Voice nutrition coach", detail: "Talk to it. It knows your day.")
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .fill(Theme.Palette.inkSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                        .strokeBorder(Theme.Palette.hairline, lineWidth: 1)
                )
        )
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Theme.Palette.voltage.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.voltage)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.Palette.voltage)
        }
        .padding(.vertical, 10)
    }

    private var divider: some View {
        Rectangle().fill(Theme.Palette.hairline).frame(height: 1)
    }

    // MARK: plan picker

    private var planPicker: some View {
        HStack(spacing: 10) {
            planCard(.annual,  price: store.displayPrice(for: .annual),  per: store.priceUnit(for: .annual),  savings: "Save 33%")
            planCard(.monthly, price: store.displayPrice(for: .monthly), per: store.priceUnit(for: .monthly), savings: nil)
        }
    }

    private func planCard(_ p: StoreKitStore.Plan, price: String, per: String, savings: String?) -> some View {
        let active = plan == p
        return Button { plan = p } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(p == .annual ? "Annual" : "Monthly")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(active ? Theme.Palette.voltage : Theme.Palette.bone)
                    Spacer()
                    if let savings {
                        Text(savings)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.0)
                            .foregroundStyle(Theme.Palette.ink)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Theme.Palette.voltage))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(Theme.Font.serif(28, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                    Text("/ \(per)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(active ? Theme.Palette.voltage : Theme.Palette.hairlineStrong, lineWidth: active ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: footer

    private var footer: some View {
        VStack(spacing: 10) {
            VoltageButton(
                title: store.isPurchasing ? "Processing…" : subscribeLabel,
                icon: store.isPurchasing ? nil : "lock.open.fill"
            ) {
                Task { await purchase() }
            }
            .opacity(store.isPurchasing ? 0.5 : 1)
            .allowsHitTesting(!store.isPurchasing)

            if let err = store.lastError {
                Text(err)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.pulse)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 14) {
                Button {
                    Task {
                        restoring = true
                        await store.restore()
                        restoring = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if restoring {
                            ProgressView().controlSize(.mini).tint(Theme.Palette.smoke)
                        }
                        Text(restoring ? "Restoring…" : "Restore")
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.Palette.smoke)
                .disabled(restoring || store.isPurchasing)
                if let skip = onSkip {
                    Text("·").font(.system(size: 10)).foregroundStyle(Theme.Palette.smoke)
                    Button("Maybe later", action: skip)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.smoke)
                }
                if DevBypass.enabled {
                    Text("·").font(.system(size: 10)).foregroundStyle(Theme.Palette.smoke)
                    Button("Skip · demo") {
                        // Local Pro grant — no StoreKit, no backend. Mirrors the
                        // onSubscribe / restore path: bump entitlement, persist,
                        // then dismiss (or forward onSubscribe so callers like
                        // OnboardingFlow advance through finish()).
                        appModel.profile.entitlement = .pro
                        appModel.persist()
                        if let cb = onSubscribe {
                            cb()
                        } else {
                            dismiss()
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
                }
            }
        }
        .task {
            await store.loadProducts()
            // Catch any pending purchases from a prior session whose verification
            // arrived between launch and the user opening the paywall.
            let hasPro = await store.refreshEntitlement()
            if hasPro {
                completeSubscriptionIfNeeded()
            }
        }
        .onChange(of: store.hasPro) { _, hasPro in
            // Mirror the StoreKit truth into the AppModel either direction.
            // Going pro: persist + auto-dismiss. Losing pro (refund, expired,
            // family-share revoked) while paywall is open: revoke locally so
            // the gated UI re-engages on next paint.
            if hasPro {
                completeSubscriptionIfNeeded()
            } else if appModel.profile.entitlement == .pro {
                // Refund / family-share revoke / expired and not renewed.
                // Direct mutation on the @Published profile; persist() runs
                // via AppModel's existing didSet-equivalent (next mutation
                // through any AppModel method will save). To be safe, force
                // a persist by re-applying via the existing API surface:
                appModel.profile.entitlement = .free
                appModel.persist()
            }
        }
    }

    private func purchase() async {
        let succeeded = await store.purchase(plan)
        if succeeded {
            completeSubscriptionIfNeeded()
        }
    }

    private func completeSubscriptionIfNeeded() {
        guard !didCompleteSubscription else { return }
        didCompleteSubscription = true
        if appModel.profile.entitlement != .pro {
            appModel.upgradeToPro()
        }
        if let onSubscribe {
            onSubscribe()
        } else {
            dismiss()
        }
    }

    private var subscribeLabel: String {
        let price = store.displayPrice(for: plan)
        switch plan {
        case .annual:  return "Start free 7-day trial — \(price)/yr"
        case .monthly: return "Subscribe — \(price)/mo"
        }
    }
}

#Preview {
    PaywallSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile
        ))
        .preferredColorScheme(.dark)
}
