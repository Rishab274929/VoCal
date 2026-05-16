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

    var onSubscribe: (() -> Void)? = nil
    var onSkip: (() -> Void)? = nil

    enum Plan: String, CaseIterable { case monthly, annual }
    @State private var plan: Plan = .annual

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
                    if onSkip == nil {
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
            planCard(.annual, price: "$39.99", per: "year", savings: "Save 33%")
            planCard(.monthly, price: "$4.99", per: "month", savings: nil)
        }
    }

    private func planCard(_ p: Plan, price: String, per: String, savings: String?) -> some View {
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
            VoltageButton(title: subscribeLabel, icon: "lock.open.fill") {
                appModel.upgradeToPro()
                onSubscribe?()
                if onSubscribe == nil { dismiss() }
            }
            HStack(spacing: 14) {
                Button("Restore") { /* RevenueCat restore */ }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
                if let skip = onSkip {
                    Text("·").font(.system(size: 10)).foregroundStyle(Theme.Palette.smoke)
                    Button("Maybe later", action: skip)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.Palette.smoke)
                }
            }
        }
    }

    private var subscribeLabel: String {
        plan == .annual ? "Start free 7-day trial — $39.99/yr" : "Subscribe — $4.99/mo"
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
