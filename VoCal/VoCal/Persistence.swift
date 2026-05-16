//
//  Persistence.swift
//  VoCal
//
//  JSON snapshot of the full app state to the Documents directory. Saved on
//  every mutation; loaded once at launch. Force-quit / cold-launch resumes
//  exactly where the user left off — no more "your day is gone" footgun.
//
//  We deliberately use plain Codable + a single file rather than SwiftData
//  because:
//   (1) zero Xcode-side ceremony (no @Model, no ModelContainer setup),
//   (2) easy to inspect via the file system during demos and bug reports,
//   (3) lets `AppModel` stay the single source of truth without async hops.
//
//  Schema is versioned. When we change shape we bump `version` and either
//  migrate or discard old payloads.
//

import Foundation

struct AppStateSnapshot: Codable {
    var version: Int
    var totals: DailyTotals
    var meals: [MealEntry]
    var profile: UserProfile
    var bodyMetrics: [BodyMetric]
    var coachMessages: [CoachMessage]
    var hasCompletedOnboarding: Bool
    var savedAt: Date

    static let currentVersion = 1
}

enum Persistence {
    private static let fileName = "vocal_state.v1.json"

    /// Returns the URL inside the app's Documents directory. Documents persists
    /// across launches and is included in iCloud Drive backups by default.
    private static func fileURL() -> URL? {
        guard let dir = try? FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return dir.appendingPathComponent(fileName)
    }

    /// Writes a snapshot. Best-effort — failures are logged via `print` and
    /// otherwise swallowed; we never want a save error to break a save flow.
    static func save(_ snapshot: AppStateSnapshot) {
        guard let url = fileURL() else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            // Atomic write so a crash mid-save doesn't leave a half-written file.
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            print("[VoCal.Persistence] save failed: \(error)")
        }
    }

    /// Loads the most recent snapshot or nil if no save exists / decode fails.
    /// On schema-version mismatch we return nil and let the caller fall back
    /// to a fresh empty state (rather than risk a corrupt-but-loadable mix).
    static func load() -> AppStateSnapshot? {
        guard let url = fileURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let snap = try? decoder.decode(AppStateSnapshot.self, from: data) else { return nil }
        if snap.version != AppStateSnapshot.currentVersion { return nil }
        return snap
    }

    /// Removes the persisted state. Useful for "Sign out" / reset flows.
    /// No-op if no file exists.
    static func clear() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension AppStateSnapshot {
    /// Empty state for a brand-new user. Sensible defaults that survive
    /// onboarding immediately if the user skips fields.
    static func empty() -> AppStateSnapshot {
        AppStateSnapshot(
            version: AppStateSnapshot.currentVersion,
            totals: DailyTotals(
                date: .now,
                calorieGoal: 2000,
                caloriesEaten: 0,
                proteinGoal: 140,
                proteinEaten: 0,
                carbsGoal: 220,
                carbsEaten: 0,
                fatGoal: 65,
                fatEaten: 0
            ),
            meals: [],
            profile: UserProfile(
                displayName: "",
                streakDays: 0,
                weightLbs: 0,
                heightInches: 0,
                dailyCalorieGoal: 2000,
                sex: "",
                birthYear: 1995,
                entitlement: .free
            ),
            bodyMetrics: [],
            coachMessages: [],
            hasCompletedOnboarding: false,
            savedAt: .now
        )
    }
}
