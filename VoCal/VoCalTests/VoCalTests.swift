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
