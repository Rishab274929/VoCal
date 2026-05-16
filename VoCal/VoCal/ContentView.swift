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
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
            AmbientBackground()

            Group {
                switch selection {
                case .today:    TodayView(showingVoice: $showingVoice, showingPhoto: $showingPhoto)
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
        .sheet(isPresented: $showingPaywall) {
            PaywallSheet()
                .presentationDetents([.large])
                .presentationBackground(Theme.Palette.ink)
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
