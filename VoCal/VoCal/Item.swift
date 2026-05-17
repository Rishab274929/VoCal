//
//  Item.swift
//  VoCal
//
//  Domain models. Plain Swift structs / ObservableObject. SwiftData
//  persistence is post-hackathon — for now everything lives in AppModel.
//

import Foundation
import SwiftUI
import Combine

// MARK: - Meals

struct MealEntry: Identifiable, Hashable, Codable {
    enum Source: String, Hashable, Codable { case voice, photo, manual, voicePhoto = "voice+photo", barcode }
    enum Slot: String, Hashable, CaseIterable, Codable { case breakfast, lunch, dinner, snack }

    let id: UUID
    var name: String
    var detail: String
    var calories: Int
    var protein: Int   // grams
    var carbs: Int     // grams
    var fat: Int       // grams
    var loggedAt: Date
    var slot: Slot
    var source: Source

    // MARK: Micronutrients (all optional — backend may omit; older
    // persisted meals must decode cleanly without them).
    var sodium_mg: Int? = nil
    var fiber_g: Int? = nil
    var sugar_g: Int? = nil
    var calcium_mg: Int? = nil
    var iron_mg: Double? = nil
    var vitamin_c_mg: Double? = nil
    var potassium_mg: Int? = nil

    init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        calories: Int,
        protein: Int,
        carbs: Int,
        fat: Int,
        loggedAt: Date,
        slot: Slot,
        source: Source,
        sodium_mg: Int? = nil,
        fiber_g: Int? = nil,
        sugar_g: Int? = nil,
        calcium_mg: Int? = nil,
        iron_mg: Double? = nil,
        vitamin_c_mg: Double? = nil,
        potassium_mg: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.loggedAt = loggedAt
        self.slot = slot
        self.source = source
        self.sodium_mg = sodium_mg
        self.fiber_g = fiber_g
        self.sugar_g = sugar_g
        self.calcium_mg = calcium_mg
        self.iron_mg = iron_mg
        self.vitamin_c_mg = vitamin_c_mg
        self.potassium_mg = potassium_mg
    }
}

// MARK: - Daily totals

struct DailyTotals: Hashable, Codable {
    var date: Date
    var calorieGoal: Int
    var caloriesEaten: Int
    var proteinGoal: Int
    var proteinEaten: Int
    var carbsGoal: Int
    var carbsEaten: Int
    var fatGoal: Int
    var fatEaten: Int

    var calorieRemaining: Int { max(0, calorieGoal - caloriesEaten) }
    var calorieProgress: Double { min(1, Double(caloriesEaten) / Double(max(1, calorieGoal))) }
}

// MARK: - User

struct UserProfile: Hashable, Codable {
    var displayName: String
    var streakDays: Int
    var weightLbs: Double
    var heightInches: Double
    var dailyCalorieGoal: Int
    var sex: String = ""  // "m", "f", or "" (unspecified)
    var birthYear: Int = 1995
    var entitlement: Entitlement = .free

    enum Entitlement: String, Hashable, Codable {
        case free, pro
    }
}

// MARK: - Body metrics

struct BodyMetric: Identifiable, Hashable, Codable {
    let id: UUID
    var weightLbs: Double
    var bodyFatPct: Double?
    var confidence: Double?
    var measuredAt: Date

    init(
        id: UUID = UUID(),
        weightLbs: Double,
        bodyFatPct: Double? = nil,
        confidence: Double? = nil,
        measuredAt: Date
    ) {
        self.id = id
        self.weightLbs = weightLbs
        self.bodyFatPct = bodyFatPct
        self.confidence = confidence
        self.measuredAt = measuredAt
    }
}

// MARK: - Coach

struct CoachMessage: Identifiable, Hashable, Codable {
    enum Role: String, Hashable, Codable { case user, assistant }
    let id: UUID
    var role: Role
    var content: String
    var createdAt: Date

    init(id: UUID = UUID(), role: Role, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

// MARK: - App state container

@MainActor
final class AppModel: ObservableObject {
    @Published var totals: DailyTotals
    @Published var meals: [MealEntry]
    @Published var profile: UserProfile
    @Published var bodyMetrics: [BodyMetric]
    @Published var coachMessages: [CoachMessage]
    @Published var hasCompletedOnboarding: Bool
    @Published var lastSavedMeal: MealEntry?

    init(
        totals: DailyTotals,
        meals: [MealEntry],
        profile: UserProfile,
        bodyMetrics: [BodyMetric] = [],
        coachMessages: [CoachMessage] = [],
        hasCompletedOnboarding: Bool = true
    ) {
        self.totals = totals
        self.meals = meals
        self.profile = profile
        self.bodyMetrics = bodyMetrics
        self.coachMessages = coachMessages
        self.hasCompletedOnboarding = hasCompletedOnboarding
        // Make sure App Intents have a snapshot to read on first invocation.
        DailyMacrosSnapshot.write(from: totals)
    }

    /// Rehydrate from a persisted snapshot. Use at app launch via
    /// `AppModel.fromPersistedOrEmpty()` rather than calling directly.
    convenience init(snapshot: AppStateSnapshot) {
        self.init(
            totals: snapshot.totals,
            meals: snapshot.meals,
            profile: snapshot.profile,
            bodyMetrics: snapshot.bodyMetrics,
            coachMessages: snapshot.coachMessages,
            hasCompletedOnboarding: snapshot.hasCompletedOnboarding
        )
    }

    /// Build an AppModel from disk if we have a saved state, otherwise from
    /// a clean empty state. The entry point used by `VoCalApp` at launch.
    ///
    /// Day-rollover guard: if the persisted snapshot was last written on a
    /// prior calendar day, we zero the *eaten* macros while preserving the
    /// *goals* + meals history. Without this, opening the app at 12:01 AM
    /// would show yesterday's calorie ring as still "1,180 / 2,200" instead
    /// of resetting to today's "0 / 2,200".
    static func fromPersistedOrEmpty() -> AppModel {
        var snap = Persistence.load() ?? AppStateSnapshot.empty()
        var rolledOver = false
        if !Calendar.current.isDateInToday(snap.totals.date) {
            snap.totals.date = .now
            snap.totals.caloriesEaten = 0
            snap.totals.proteinEaten = 0
            snap.totals.carbsEaten = 0
            snap.totals.fatEaten = 0
            rolledOver = true
        }
        let model = AppModel(snapshot: snap)
        // Only flush back to disk when we actually changed something. Avoids
        // a needless write on every cold launch when the user just opens the
        // app multiple times in the same day.
        if rolledOver { model.persist() }
        return model
    }

    /// Reset eaten macros if the day has flipped since the last update.
    /// Call this from `.task` or `.onChange(of: scenePhase)` so a phone
    /// left on overnight rolls over the next time the user opens the app.
    /// Returns `true` if a rollover happened.
    @discardableResult
    func rolloverIfNewDay() -> Bool {
        guard !Calendar.current.isDateInToday(totals.date) else { return false }
        totals.date = .now
        totals.caloriesEaten = 0
        totals.proteinEaten = 0
        totals.carbsEaten = 0
        totals.fatEaten = 0
        DailyMacrosSnapshot.write(from: totals)
        persist()
        return true
    }

    /// Serialize the current state and write it to disk. Called automatically
    /// from every mutating method below; safe to call manually.
    func persist() {
        let snapshot = AppStateSnapshot(
            version: AppStateSnapshot.currentVersion,
            totals: totals,
            meals: meals,
            profile: profile,
            bodyMetrics: bodyMetrics,
            coachMessages: coachMessages,
            hasCompletedOnboarding: hasCompletedOnboarding,
            savedAt: .now
        )
        Persistence.save(snapshot)
    }

    /// Idempotency window — the cooldown between accepting two saves of the
    /// same logical meal. Anything inside this window is treated as a
    /// double-tap on the save button. Keep this >= one human reaction (~0.5s)
    /// but well under "I had two of those" cadence (~5s).
    private static let dedupeWindow: TimeInterval = 2

    /// Wall-clock instant of the last accepted `addMeal`. Used to detect a
    /// double-tap on Save independent of the meal's `loggedAt` (which the
    /// caller may backdate for a historical entry).
    private var lastAddMealAt: Date?

    func addMeal(_ meal: MealEntry) {
        // Idempotency: ignore a save with the same name+kcal that arrived
        // within `dedupeWindow` seconds of the previous accepted save. We
        // compare wall-clock-now to `lastAddMealAt` (not to `meal.loggedAt`)
        // because `loggedAt` can be backdated for historical entries — a
        // user-initiated "I forgot to log this morning's banana" should NOT
        // be silently swallowed even if its name+kcal happen to match the
        // last save.
        //
        // Also scan the top 3 of `meals` rather than just `meals.first`
        // because `meals` is sorted by *insertion order*, not `loggedAt`. A
        // recently-backdated entry can sit at index 0 with an old
        // `loggedAt`, so checking only `meals.first` would let a double-tap
        // slip through.
        let now = Date.now
        if let last = lastAddMealAt, now.timeIntervalSince(last) < Self.dedupeWindow {
            let recentSlice = meals.prefix(3)
            if recentSlice.contains(where: { $0.name == meal.name && $0.calories == meal.calories }) {
                return
            }
        }
        meals.insert(meal, at: 0)
        totals.caloriesEaten += meal.calories
        totals.proteinEaten += meal.protein
        totals.carbsEaten += meal.carbs
        totals.fatEaten += meal.fat
        lastSavedMeal = meal
        lastAddMealAt = now
        DailyMacrosSnapshot.write(from: totals)
        persist()

        // Mirror to Apple Health (no-op if unauthorized)
        Task { await VoCalHealth.shared.write(meal: meal) }
    }

    /// Replace `original` with `updated` in place. Recomputes totals by
    /// subtracting the original macros and adding the updated. The id is
    /// preserved by the caller (MealEditSheet) so HealthKit's metadata
    /// `HKMetadataKeyExternalUUID` keeps matching — delete + write keeps
    /// Apple Health in sync without orphan samples.
    ///
    /// No-op if the original is no longer in the list (eg. user deleted
    /// from another surface between edit-open and edit-save).
    func editMeal(_ original: MealEntry, to updated: MealEntry) {
        guard let idx = meals.firstIndex(of: original) else { return }
        meals[idx] = updated
        totals.caloriesEaten = max(0, totals.caloriesEaten - original.calories + updated.calories)
        totals.proteinEaten  = max(0, totals.proteinEaten  - original.protein  + updated.protein)
        totals.carbsEaten    = max(0, totals.carbsEaten    - original.carbs    + updated.carbs)
        totals.fatEaten      = max(0, totals.fatEaten      - original.fat      + updated.fat)
        DailyMacrosSnapshot.write(from: totals)
        persist()

        // Mirror to HealthKit: delete old samples (matched by external UUID)
        // and write fresh ones. Both fire-and-forget so the UI never blocks
        // on HK. If the user hasn't granted HK auth both calls are no-ops.
        Task { await VoCalHealth.shared.delete(meal: original) }
        Task { await VoCalHealth.shared.write(meal: updated) }
    }

    func removeMeal(_ meal: MealEntry) {
        guard let idx = meals.firstIndex(of: meal) else { return }
        meals.remove(at: idx)
        totals.caloriesEaten = max(0, totals.caloriesEaten - meal.calories)
        totals.proteinEaten = max(0, totals.proteinEaten - meal.protein)
        totals.carbsEaten = max(0, totals.carbsEaten - meal.carbs)
        totals.fatEaten = max(0, totals.fatEaten - meal.fat)
        DailyMacrosSnapshot.write(from: totals)
        persist()

        // Mirror the deletion to Apple Health so a meal removed in-app
        // doesn't leave an orphan HKCorrelation behind. Mirrors the
        // fire-and-forget pattern in `addMeal`; no-op if unauthorized.
        Task { await VoCalHealth.shared.delete(meal: meal) }
    }

    func addBodyMetric(_ metric: BodyMetric) {
        bodyMetrics.insert(metric, at: 0)
        persist()
    }

    func appendCoach(_ message: CoachMessage) {
        coachMessages.append(message)
        persist()
    }

    func updateGoal(daily kcal: Int) {
        totals.calorieGoal = kcal
        profile.dailyCalorieGoal = kcal
        DailyMacrosSnapshot.write(from: totals)
        persist()
    }

    /// Mutate the profile via a closure, then persist + sync the snapshot
    /// + keep `totals.calorieGoal` aligned with `profile.dailyCalorieGoal`
    /// (so widgets / intents pick up a new daily-kcal target without a
    /// separate `updateGoal` call). All edits go through this so we have
    /// one persistence point.
    func updateProfile(_ mutate: (inout UserProfile) -> Void) {
        var copy = profile
        mutate(&copy)
        profile = copy
        // Keep daily-kcal mirror coherent — `DailyMacrosSnapshot` reads from
        // `totals.calorieGoal`, so if the user just bumped their kcal target
        // we have to mirror it before we write the snapshot.
        totals.calorieGoal = profile.dailyCalorieGoal
        DailyMacrosSnapshot.write(from: totals)
        persist()
    }

    func upgradeToPro() {
        profile.entitlement = .pro
        persist()
    }

    func completeOnboarding(profile newProfile: UserProfile, calorieGoal: Int) {
        self.profile = newProfile
        self.totals.calorieGoal = calorieGoal
        self.profile.dailyCalorieGoal = calorieGoal
        self.hasCompletedOnboarding = true
        DailyMacrosSnapshot.write(from: totals)
        persist()
    }
}

// MARK: - API payloads / responses

struct VoiceParsePayload: Codable {
    var transcript: String
    var follow_up_answer: String?
}

// MARK: - Daily macros snapshot (shared with App Intents)

/// Compact today snapshot that the App Intents read so Siri can answer
/// "what are my macros" without spinning up the full UI. Written to
/// `UserDefaults.standard` on every meal save / goal update; since the
/// App Intents live in the main app bundle they share the same defaults
/// store.
struct DailyMacrosSnapshot: Codable, Sendable {
    var date: Date
    var calorieGoal: Int
    var caloriesEaten: Int
    var proteinGoal: Int
    var proteinEaten: Int
    var carbsGoal: Int
    var carbsEaten: Int
    var fatGoal: Int
    var fatEaten: Int

    var calorieRemaining: Int { max(0, calorieGoal - caloriesEaten) }
    var proteinShort: Int { max(0, proteinGoal - proteinEaten) }
    var carbsShort: Int { max(0, carbsGoal - carbsEaten) }
    var fatShort: Int { max(0, fatGoal - fatEaten) }

    static let defaultsKey = "vocal.dailyMacrosSnapshot.v1"

    /// Shared encoder/decoder pair. Both pin to ISO 8601 dates so the on-disk
    /// format matches `Persistence` and is greppable from `xcrun simctl
    /// spawn ... defaults read` during demos. Using `JSONEncoder()` with no
    /// strategy on one side and `.iso8601` on the other (the bug this
    /// replaces) would still round-trip — both sides are paired — but it
    /// quietly broke any external tooling that tried to inspect the value.
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    nonisolated static func write(from totals: DailyTotals) {
        let snap = DailyMacrosSnapshot(
            date: totals.date,
            calorieGoal: totals.calorieGoal,
            caloriesEaten: totals.caloriesEaten,
            proteinGoal: totals.proteinGoal,
            proteinEaten: totals.proteinEaten,
            carbsGoal: totals.carbsGoal,
            carbsEaten: totals.carbsEaten,
            fatGoal: totals.fatGoal,
            fatEaten: totals.fatEaten
        )
        if let data = try? encoder.encode(snap) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    nonisolated static func read() -> DailyMacrosSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snap = try? decoder.decode(DailyMacrosSnapshot.self, from: data) else {
            return nil
        }
        // Stale-day guard: if the snapshot isn't from today, the intent should
        // assume a fresh day (eaten = 0 against the persisted goals).
        if !Calendar.current.isDateInToday(snap.date) {
            return DailyMacrosSnapshot(
                date: .now,
                calorieGoal: snap.calorieGoal,
                caloriesEaten: 0,
                proteinGoal: snap.proteinGoal,
                proteinEaten: 0,
                carbsGoal: snap.carbsGoal,
                carbsEaten: 0,
                fatGoal: snap.fatGoal,
                fatEaten: 0
            )
        }
        return snap
    }
}

struct VoiceParseResponse: Codable {
    struct ParsedMeal: Codable {
        var name: String
        var detail: String
        var kcal: Int
        var protein_g: Int
        var carbs_g: Int
        var fat_g: Int
        var slot: String
        var source: String
        var confidence: Double

        // MARK: Optional micronutrients — present once the backend's
        // micronutrient parser ships. Until then these decode as nil and
        // the meal still saves cleanly with macros only.
        var sodium_mg: Int? = nil
        var fiber_g: Int? = nil
        var sugar_g: Int? = nil
        var calcium_mg: Int? = nil
        var iron_mg: Double? = nil
        var vitamin_c_mg: Double? = nil
        var potassium_mg: Int? = nil
    }

    var transcript: String
    var follow_up_question: String?
    var meal: ParsedMeal?
    var reasoning: String
}
