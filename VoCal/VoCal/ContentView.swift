//
//  ContentView.swift
//  VoCal
//
//  Editorial app shell. The bottom tab bar is a `safeAreaInset` overlay
//  so the floating mic button overhangs cleanly. Voice + paywall sheets
//  are reachable from anywhere via shared state.
//
//  Paywall enforcement: this view gates EVERY render on
//  `appModel.profile.entitlement`. Free users see the hard paywall via
//  `.fullScreenCover` — they cannot reach the tabs at all until they
//  subscribe (or restore). The cold-launch trigger via
//  `vocal.didShowFirstPaywall` is still here, but it's now only used to
//  avoid double-presenting (the entitlement gate would otherwise pop the
//  paywall ~800ms after onboarding's own paywall).
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appModel: AppModel
    @State private var selection: EditorialTabBar.Tab = .today
    @State private var showingVoice = false
    @State private var showingPhoto = false
    @State private var showingBarcode = false
    @State private var showingPaywall = false
    @AppStorage("vocal.dailyVoiceCount") private var dailyVoiceCount: Int = 0
    @AppStorage("vocal.dailyVoiceDate") private var dailyVoiceDate: String = ""

    /// Free tier cap. Set generously so the user can taste the product
    /// before the paywall — but low enough that heavy users feel it.
    private static let freeDailyVoiceCap = 3

    /// Day-only ISO8601 string (e.g. "2026-05-16") used to key the daily
    /// voice cap. We compare against this on every mic tap; a mismatch means
    /// the day has rolled over and the count resets to 0.
    private static let dayOnlyFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()

    /// True if the user has reached the cap for today (and is on free tier).
    /// Pro users always return false. Also returns false if the cached date
    /// doesn't match today — we treat that as "fresh slate, count = 0".
    private var hasHitVoiceCap: Bool {
        guard appModel.profile.entitlement == .free else { return false }
        let today = Self.dayOnlyFormatter.string(from: .now)
        if dailyVoiceDate != today { return false }
        return dailyVoiceCount >= Self.freeDailyVoiceCap
    }

    /// True if the user has no Pro entitlement. Drives the full-screen
    /// hard-paywall cover so a free user literally cannot reach the home
    /// tabs without subscribing or restoring.
    private var showHardPaywall: Bool {
        appModel.profile.entitlement == .free
    }

    /// Show the paywall on cold launch for free users. Today this is
    /// largely redundant with the entitlement gate (`showHardPaywall`
    /// above), but the flag is kept so the cold-launch sheet doesn't
    /// double-present with onboarding's `.ready` → paywall transition. The
    /// onboarding flow sets this flag to `true` BEFORE finishing so the
    /// gate's `.fullScreenCover` is the only paywall the user sees right
    /// after onboarding.
    private func maybeShowOnboardingPaywall() {
        guard appModel.profile.entitlement == .free else { return }
        guard appModel.hasCompletedOnboarding else { return }
        // The entitlement gate (`.fullScreenCover` below) is now the
        // authoritative trigger — this helper only flips the legacy
        // `didShowFirstPaywall` flag so any downstream consumers that
        // still read it see a consistent value.
        let key = "vocal.didShowFirstPaywall"
        if !UserDefaults.standard.bool(forKey: key) {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    /// Tap target for the mic button + Today's "Say something" CTA. Free
    /// users at-cap see the hard paywall instead of the voice sheet — that's
    /// the upgrade trigger.
    private func requestVoiceCapture() {
        if hasHitVoiceCap {
            showingPaywall = true
            return
        }
        showingVoice = true
    }

    var body: some View {
        ZStack {
            AmbientBackground()

            Group {
                switch selection {
                case .today:    TodayView(showingVoice: $showingVoice, showingPhoto: $showingPhoto, showingBarcode: $showingBarcode)
                case .progress: ProgressScreen()
                case .coach:    CoachView()
                case .profile:  ProfileView(showingPaywall: $showingPaywall)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            EditorialTabBar(selection: $selection) {
                requestVoiceCapture()
            }
        }
        .background(Theme.Palette.ink.ignoresSafeArea())
        .sheet(isPresented: $showingVoice) {
            VoiceCaptureSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingPhoto) {
            MealPhotoSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showingBarcode) {
            BarcodeScannerSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
                .presentationDragIndicator(.visible)
        }
        // SOFT paywall — explicit upgrade tap from Profile, where the user
        // already has access to the app and is browsing the upgrade options.
        // This one has no `onSkip` either (PaywallSheet auto-detects pro
        // users and shows an X for closing), so it can be dismissed when
        // appropriate.
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
        }
        // HARD paywall — full-screen entitlement gate. A free user CANNOT
        // reach the home tabs at all; the only paths out are subscribe or
        // restore. Hidden the moment `entitlement == .pro`, which flips via
        // PaywallSheet's StoreKit listener.
        //
        // Using `.fullScreenCover` (not `.sheet`) so there's no peek of the
        // home UI behind it and the user can't swipe past — this is the
        // single authoritative gate after onboarding.
        .fullScreenCover(isPresented: Binding(
            get: { showHardPaywall && appModel.hasCompletedOnboarding },
            set: { _ in /* read-only; entitlement drives it */ }
        )) {
            PaywallSheet()
                .presentationBackground(Theme.Palette.ink)
        }
        .onAppear { maybeShowOnboardingPaywall() }
        .onChange(of: appModel.hasCompletedOnboarding) { _, done in
            if done { maybeShowOnboardingPaywall() }
        }
        // Daily voice cap accounting: every time a meal is saved (via the
        // voice sheet OR via Siri), if the source is voice/voice+photo we
        // bump the day counter. We watch `lastSavedMeal` rather than counting
        // taps on the mic button because:
        //  - a tapped-and-cancelled voice session shouldn't count
        //  - the manual edit/correction path also goes through addMeal
        //  - Siri-logged meals (via App Intents) should count too
        //
        // The cap itself is gated to free users only, so a Pro user's
        // counter still tracks (cheap), but the `requestVoiceCapture()`
        // guard never fires for them.
        .onChange(of: appModel.lastSavedMeal?.id) { _, _ in
            guard let meal = appModel.lastSavedMeal else { return }
            // Only voice-shaped sources count toward the voice cap.
            // Barcode + manual + photo-only entries don't burn voice quota.
            switch meal.source {
            case .voice, .voicePhoto:
                bumpVoiceCount()
            case .photo, .manual, .barcode:
                return
            }
        }
    }

    /// Reset count if the day has flipped, then increment. Called from
    /// `lastSavedMeal` observation above. Safe to call from any thread —
    /// `@AppStorage` is just a wrapper over UserDefaults.
    private func bumpVoiceCount() {
        let today = Self.dayOnlyFormatter.string(from: .now)
        if dailyVoiceDate != today {
            dailyVoiceDate = today
            dailyVoiceCount = 0
        }
        dailyVoiceCount += 1
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            bodyMetrics: MockData.bodyMetrics,
            coachMessages: MockData.coachIntro,
            hasCompletedOnboarding: true
        ))
        .preferredColorScheme(.dark)
}
