//
//  DevBypass.swift
//  VoCal
//
//  Demo-mode bypass switches. When `enabled` is true, the app shows
//  "Skip" affordances in Onboarding and PaywallSheet that grant Pro
//  entitlement locally without going through Google/Apple sign-in or
//  StoreKit. Flip to `false` before App Store submission.
//

import Foundation

enum DevBypass {
    /// Controls visibility of demo-mode bypass buttons across the app.
    /// Read at view-render time, so flipping in code recompiles immediately.
    static let enabled: Bool = true

    /// Default profile applied when the user taps "Skip onboarding".
    /// Mid-range defaults so the app has sensible totals out of the box.
    static func defaultProfile() -> UserProfile {
        UserProfile(
            displayName: "Demo",
            streakDays: 0,
            weightLbs: 165,
            heightInches: 68,
            dailyCalorieGoal: 2200,
            sex: "",
            birthYear: 1995,
            entitlement: .pro
        )
    }

    /// Default daily calorie goal used by skip-onboarding bypass.
    static let defaultCalorieGoal: Int = 2200
}
