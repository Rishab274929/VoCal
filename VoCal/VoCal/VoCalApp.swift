//
//  VoCalApp.swift
//  VoCal
//

import SwiftUI

@main
struct VoCalApp: App {
    @StateObject private var appModel = AppModel(
        totals: MockData.today,
        meals: MockData.recentMeals,
        profile: MockData.profile,
        bodyMetrics: MockData.bodyMetrics,
        coachMessages: MockData.coachIntro,
        hasCompletedOnboarding: true
    )

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
