//
//  ContentView.swift
//  VoCal
//
//  Editorial app shell. The bottom tab bar is a `safeAreaInset` overlay
//  so the floating mic button overhangs cleanly. Voice + paywall sheets
//  are reachable from anywhere via shared state.
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

    /// Show the paywall on cold launch for free users who've been around
    /// for at least 1 day (gives them a chance to log something first).
    private func maybeShowOnboardingPaywall() {
        guard appModel.profile.entitlement == .free else { return }
        guard appModel.hasCompletedOnboarding else { return }
        // The first launch after onboarding goes straight to a paywall;
        // we use AppStorage to remember we showed it so we don't spam.
        let key = "vocal.didShowFirstPaywall"
        let didShow = UserDefaults.standard.bool(forKey: key)
        if !didShow {
            UserDefaults.standard.set(true, forKey: key)
            // Defer a beat so onboarding's fade-out animation completes.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                showingPaywall = true
            }
        }
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
                showingVoice = true
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
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
        }
        .onAppear { maybeShowOnboardingPaywall() }
        .onChange(of: appModel.hasCompletedOnboarding) { _, done in
            if done { maybeShowOnboardingPaywall() }
        }
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
