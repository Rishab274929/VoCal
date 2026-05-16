//
//  VoCalApp.swift
//  VoCal
//

import SwiftUI
import UIKit

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
    // Wired so `.onChange(of: scenePhase)` can fire `rolloverIfNewDay`
    // when the user foregrounds the app after midnight. Without this, a
    // phone left on overnight would still display yesterday's totals on
    // resume — the in-memory `totals.date` only gets refreshed on cold
    // launch via `fromPersistedOrEmpty`.
    @Environment(\.scenePhase) private var scenePhase

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
            // Best-effort anonymous sign-in. Triggers a /api/auth/anonymous
            // call on first launch and refreshes the JWT if our cached one
            // is close to expiry. Network failure is non-fatal — the rest
            // of the app falls back to unauthenticated requests.
            _ = try? await AuthSession.shared.currentToken()
            await VoCalHealth.shared.requestAuthorization()
            // Cold-launch drain of any meals Siri logged while the app was
            // suspended. Mirrors the foreground-resume drain below; without
            // both legs, Siri-logged meals would sit in UserDefaults until
            // a meal was eventually saved through the UI.
            drainPendingSiriMeals()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Day-rollover guard at the cheapest hook we have: every time
            // the app becomes active. `rolloverIfNewDay` is a no-op when
            // the in-memory totals are already from today, so the cost is
            // a single `Calendar.isDateInToday` check per resume.
            if newPhase == .active {
                appModel.rolloverIfNewDay()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            // Resume drain — separate from the `.task` cold-launch path so
            // a user who minimizes the app, asks Siri to log a snack, and
            // then comes back gets credit for that snack immediately
            // instead of on the next manual save.
            drainPendingSiriMeals()
        }
    }

    /// Pull any meals Siri logged while suspended and fold them into the
    /// AppModel. Each item is converted to a `MealEntry`; `addMeal` handles
    /// the totals math, persistence, snapshot write, and HealthKit mirror.
    private func drainPendingSiriMeals() {
        let pending = PendingMealQueue.drain()
        guard !pending.isEmpty else { return }
        for item in pending {
            let meal = MealEntry(
                name: item.name,
                detail: item.detail,
                calories: item.kcal,
                protein: item.protein_g,
                carbs: item.carbs_g,
                fat: item.fat_g,
                loggedAt: item.loggedAt,
                slot: MealEntry.Slot(rawValue: item.slot) ?? .snack,
                source: MealEntry.Source(rawValue: item.source) ?? .voice
            )
            appModel.addMeal(meal)
        }
    }
}
