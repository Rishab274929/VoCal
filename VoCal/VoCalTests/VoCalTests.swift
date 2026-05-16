//
//  VoCalTests.swift
//  VoCalTests
//

import Testing
import Foundation
@testable import VoCal

struct VoCalTests {

    // MARK: FoodCanon — the on-device top-N lookup

    @Test func canonResolvesPlainApple() async throws {
        let hit = FoodCanon.shared.lookup("apple")
        try #require(hit != nil)
        #expect(hit?.name == "Apple, raw, medium")
        #expect(hit?.kcal == 95)
    }

    @Test func canonResolvesNaturalLanguageApple() async throws {
        let hit = FoodCanon.shared.lookup("I had an apple")
        try #require(hit != nil)
        #expect(hit?.name == "Apple, raw, medium")
    }

    @Test func canonResolves8ozGrilledChickenBreast() async throws {
        let hit = FoodCanon.shared.lookup("8 oz grilled chicken breast")
        try #require(hit != nil)
        #expect(hit?.name == "Chicken breast, grilled (8 oz)")
        #expect(hit?.protein_g == 62)
    }

    @Test func canonResolvesSliceOfPepperoniPizza() async throws {
        let hit = FoodCanon.shared.lookup("slice of pepperoni pizza")
        try #require(hit != nil)
        #expect(hit?.name == "Pizza, pepperoni (1 slice)")
        #expect(hit?.kcal == 313)
    }

    @Test func canonResolvesTwoScrambledEggs() async throws {
        let hit = FoodCanon.shared.lookup("two scrambled eggs")
        try #require(hit != nil)
        // Longer alias "two scrambled eggs" beats "scrambled eggs" / "egg".
        #expect(hit?.name == "Eggs, scrambled (2)")
        #expect(hit?.kcal == 182)
    }

    @Test func canonMissesUnknownChainItem() async throws {
        // Chain canon lives on the backend; on-device should miss BK Whopper
        // and let the network call (or backend chain canon) handle it.
        let hit = FoodCanon.shared.lookup("burger king whopper")
        #expect(hit == nil)
    }

    @Test func canonMissesEmptyInput() async throws {
        #expect(FoodCanon.shared.lookup("") == nil)
        #expect(FoodCanon.shared.lookup("   ") == nil)
    }

    @Test func canonNormalizeStripsFillers() async throws {
        let n1 = FoodCanon.normalize("I had a banana")
        #expect(n1 == "banana")
        let n2 = FoodCanon.normalize("Um, just some plain rice.")
        #expect(n2 == "plain rice")
    }

    // MARK: Persistence — full app state round-trip

    @Test func persistenceRoundTripsAppState() async throws {
        Persistence.clear()
        let meal = MealEntry(
            name: "Apple, raw, medium",
            detail: "1 medium (182g) · cached",
            calories: 95, protein: 0, carbs: 25, fat: 0,
            loggedAt: .now,
            slot: .snack,
            source: .voice
        )
        let snap = AppStateSnapshot(
            version: AppStateSnapshot.currentVersion,
            totals: DailyTotals(date: .now, calorieGoal: 2000, caloriesEaten: 95,
                                proteinGoal: 140, proteinEaten: 0,
                                carbsGoal: 220, carbsEaten: 25,
                                fatGoal: 65, fatEaten: 0),
            meals: [meal],
            profile: UserProfile(displayName: "TestUser", streakDays: 1,
                                 weightLbs: 170, heightInches: 70,
                                 dailyCalorieGoal: 2000, sex: "m",
                                 birthYear: 1995, entitlement: .free),
            bodyMetrics: [],
            coachMessages: [],
            hasCompletedOnboarding: true,
            savedAt: .now
        )
        Persistence.save(snap)
        let loaded = Persistence.load()
        try #require(loaded != nil)
        #expect(loaded?.profile.displayName == "TestUser")
        #expect(loaded?.meals.count == 1)
        #expect(loaded?.meals.first?.name == "Apple, raw, medium")
        #expect(loaded?.totals.caloriesEaten == 95)
        #expect(loaded?.hasCompletedOnboarding == true)
        Persistence.clear()
        #expect(Persistence.load() == nil)
    }

    @Test func fromPersistedOrEmptyReturnsEmptyStateWhenNoFile() async throws {
        Persistence.clear()
        let model = await AppModel.fromPersistedOrEmpty()
        let onboarded = await MainActor.run { model.hasCompletedOnboarding }
        let mealCount = await MainActor.run { model.meals.count }
        let name = await MainActor.run { model.profile.displayName }
        #expect(onboarded == false)
        #expect(mealCount == 0)
        #expect(name == "")
    }

    // MARK: DailyMacrosSnapshot round-trip

    @Test func dailyMacrosSnapshotRoundTrips() async throws {
        let totals = DailyTotals(
            date: .now,
            calorieGoal: 2200, caloriesEaten: 1180,
            proteinGoal: 160, proteinEaten: 84,
            carbsGoal: 240, carbsEaten: 138,
            fatGoal: 70, fatEaten: 41
        )
        DailyMacrosSnapshot.write(from: totals)
        let read = DailyMacrosSnapshot.read()
        try #require(read != nil)
        #expect(read?.calorieGoal == 2200)
        #expect(read?.proteinShort == 76)
        #expect(read?.calorieRemaining == 1020)
    }
}
