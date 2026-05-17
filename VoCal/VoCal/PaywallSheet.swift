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
                .padding(.top, 16)

                VStack(alignment: .leading, spacing: 16) {
                    headline
                    features
                    planPicker
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                Spacer(minLength: 8)

                footer
                    .padding(.horizontal, 28)
                    .padding(.bottom, 20)
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
        VStack(alignment: .leading, spacing: 6) {
            (
                Text("Track every meal. ")
                    .foregroundStyle(Theme.Palette.bone)
                + Text("By voice.")
                    .foregroundStyle(Theme.Palette.voltage)
                    .font(Theme.Font.serif(26, weight: .medium, italic: true))
            )
            .font(Theme.Font.serif(26, weight: .medium))

            Text("Unlimited logging, restaurant macros, photo fact-check, body fat, coach.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.ash)
        }
    }

    // MARK: features

    private var features: some View {
        VStack(spacing: 0) {
            featureRow(icon: "waveform", title: "Unlimited voice logs", detail: "Free caps at 3/day")
            divider
            featureRow(icon: "fork.knife", title: "Restaurant macros", detail: "Top 25 chains + agentic search")
            divider
            featureRow(icon: "camera.viewfinder", title: "Photo fact-check", detail: "Snap a meal, verify macros")
            divider
            featureRow(icon: "bubble.left.and.text.bubble.right", title: "Voice coach + BF%", detail: "Talk to it. Body-fat from selfies.")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
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
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.Palette.voltage)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.bone)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            Spacer()
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Theme.Palette.voltage)
        }
        .padding(.vertical, 8)
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(p == .annual ? "Annual" : "Monthly")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(active ? Theme.Palette.voltage : Theme.Palette.bone)
                    Spacer()
                    if let savings {
                        Text(savings)
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(Theme.Palette.ink)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Theme.Palette.voltage))
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(price)
                        .font(Theme.Font.serif(22, weight: .medium))
                        .foregroundStyle(Theme.Palette.bone)
                    Text("/ \(per)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
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
