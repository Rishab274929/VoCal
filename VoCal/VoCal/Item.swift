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

struct MealEntry: Identifiable, Hashable {
    enum Source: String, Hashable { case voice, photo, manual, voicePhoto = "voice+photo", barcode }
    enum Slot: String, Hashable, CaseIterable { case breakfast, lunch, dinner, snack }

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

struct DailyTotals: Hashable {
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

struct UserProfile: Hashable {
    var displayName: String
    var streakDays: Int
    var weightLbs: Double
    var heightInches: Double
    var dailyCalorieGoal: Int
    var sex: String = "x"
    var birthYear: Int = 1995
    var entitlement: Entitlement = .free

    enum Entitlement: String, Hashable {
        case free, pro
    }
}

// MARK: - Body metrics

struct BodyMetric: Identifiable, Hashable {
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

struct CoachMessage: Identifiable, Hashable {
    enum Role: String, Hashable { case user, assistant }
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
    }

    func addMeal(_ meal: MealEntry) {
        meals.insert(meal, at: 0)
        totals.caloriesEaten += meal.calories
        totals.proteinEaten += meal.protein
        totals.carbsEaten += meal.carbs
        totals.fatEaten += meal.fat
        lastSavedMeal = meal

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
    }

    func addBodyMetric(_ metric: BodyMetric) {
        bodyMetrics.insert(metric, at: 0)
    }

    func appendCoach(_ message: CoachMessage) {
        coachMessages.append(message)
    }

    func updateGoal(daily kcal: Int) {
        totals.calorieGoal = kcal
        profile.dailyCalorieGoal = kcal
    }

    func upgradeToPro() {
        profile.entitlement = .pro
    }
}

// MARK: - API payloads / responses

struct VoiceParsePayload: Codable {
    var transcript: String
    var follow_up_answer: String?
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
