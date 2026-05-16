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
        source: Source
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
    static func fromPersistedOrEmpty() -> AppModel {
        let snap = Persistence.load() ?? AppStateSnapshot.empty()
        return AppModel(snapshot: snap)
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

    func addMeal(_ meal: MealEntry) {
        // Idempotency: ignore a save with the same name+kcal that arrived within
        // 2s of the last save. Prevents double-taps on Save from logging twice
        // and writing duplicate HealthKit samples.
        if let recent = meals.first,
           recent.name == meal.name,
           recent.calories == meal.calories,
           abs(recent.loggedAt.timeIntervalSince(meal.loggedAt)) < 2 {
            return
        }
        meals.insert(meal, at: 0)
        totals.caloriesEaten += meal.calories
        totals.proteinEaten += meal.protein
        totals.carbsEaten += meal.carbs
        totals.fatEaten += meal.fat
        lastSavedMeal = meal
        DailyMacrosSnapshot.write(from: totals)
        persist()

        // Mirror to Apple Health (no-op if unauthorized)
        Task { await VoCalHealth.shared.write(meal: meal) }
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
        if let data = try? JSONEncoder().encode(snap) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    nonisolated static func read() -> DailyMacrosSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let snap = try? JSONDecoder().decode(DailyMacrosSnapshot.self, from: data) else {
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
    }

    var transcript: String
    var follow_up_question: String?
    var meal: ParsedMeal?
    var reasoning: String
}
