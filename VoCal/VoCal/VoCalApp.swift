//
//  VoCalApp.swift
//  VoCal
//

import SwiftUI

@main
struct VoCalApp: App {
    // Loads the persisted snapshot from Documents if present; otherwise
    // starts a brand-new user at an empty state with onboarding pending.
    // Replaces the old MockData seed, which made every fresh install look
    // like a 12-day-streak demo account.
    @StateObject private var appModel = AppModel.fromPersistedOrEmpty()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appModel)
                .preferredColorScheme(.dark)
                .tint(Theme.Palette.voltage)
        }
    }
}

/// Top-level router. Onboarding gates the main shell.
struct RootView: View {
    @EnvironmentObject private var appModel: AppModel

    var body: some View {
        ZStack {
            if appModel.hasCompletedOnboarding {
                ContentView()
                    .transition(.opacity)
            } else {
                OnboardingFlow()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: appModel.hasCompletedOnboarding)
        .task {
            await VoCalHealth.shared.requestAuthorization()
        }
    }
}
