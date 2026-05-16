//
//  OfflineFallback.swift
//  VoCal
//
//  Single source of truth for the offline fallback chain-restaurant matcher.
//  Used when the on-device `FoodCanon` misses AND the backend round-trip
//  fails (airplane mode, captive wifi, Cloudflare 5xx, etc.). The point is
//  to keep the demo flowing for the three killer phrases even when there's
//  zero network — every other code path has already had a fair shot.
//
//  Returns:
//   - `.meal(VoiceParseResponse)` for a confident offline match
//   - `.followUp(question, reasoning)` when we need a clarification round
//   - `.miss` when nothing matches — caller decides whether to show an
//     "estimated fallback" generic meal or an error.
//

import Foundation

enum OfflineFallbackResult {
    case meal(VoiceParseResponse)
    case followUp(question: String, reasoning: String)
    case miss
}

enum OfflineFallback {
    /// One chain-menu offline item. `brandTokens` are ANY-of (any of these
    /// substrings in the transcript signals the brand); `itemTokens` are
    /// ALL-of (every group's tokens must appear). Macros mirror
    /// `vocal-api/src/ai/canon.ts` exactly — drift here would surface as
    /// "Whopper is 670 when online, 540 when offline" which corrodes user
    /// trust faster than a slow network ever could.
    private struct OfflineItem {
        let brandTokens: [String]
        let itemMatch: [[String]]      // OR of (AND of tokens)
        let name: String
        let detail: String
        let kcal: Int
        let protein: Int
        let carbs: Int
        let fat: Int
        let slot: String
        let confidence: Double
    }

    /// Order matters: more specific (longer) matches go first so e.g. "large
    /// fry" wins over plain "fry" within the McDonald's brand.
    private static let table: [OfflineItem] = [
        // -------- McDonald's --------
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["big", "mac"]],
            name: "McDonald's Big Mac",
            detail: "Chain menu match · offline",
            kcal: 590, protein: 25, carbs: 45, fat: 34,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["quarter", "pounder"]],
            name: "McDonald's Quarter Pounder with Cheese",
            detail: "Chain menu match · offline",
            kcal: 520, protein: 30, carbs: 42, fat: 26,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["mcchicken"], ["mc", "chicken"]],
            name: "McDonald's McChicken",
            detail: "Chain menu match · offline",
            kcal: 400, protein: 14, carbs: 39, fat: 21,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["mcnugget"], ["chicken", "nugget", "10"]],
            name: "McDonald's Chicken McNuggets (10 pc)",
            detail: "Chain menu match · offline",
            kcal: 410, protein: 23, carbs: 25, fat: 24,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["egg", "mcmuffin"], ["sausage", "mcmuffin"]],
            name: "McDonald's Egg McMuffin",
            detail: "Chain menu match · offline",
            kcal: 310, protein: 17, carbs: 30, fat: 13,
            slot: "breakfast", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["large", "fries"], ["large", "fry"]],
            name: "McDonald's French Fries (Large)",
            detail: "Chain menu match · offline",
            kcal: 480, protein: 7, carbs: 66, fat: 23,
            slot: "snack", confidence: 0.97
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["small", "fries"], ["small", "fry"]],
            name: "McDonald's French Fries (Small)",
            detail: "Chain menu match · offline",
            kcal: 230, protein: 3, carbs: 31, fat: 11,
            slot: "snack", confidence: 0.97
        ),
        OfflineItem(
            brandTokens: ["mcdonald", "mcd"],
            itemMatch: [["fry"], ["fries"]],
            name: "McDonald's French Fries (Medium)",
            detail: "Chain menu match · offline",
            kcal: 320, protein: 4, carbs: 43, fat: 15,
            slot: "snack", confidence: 0.97
        ),

        // -------- Starbucks --------
        OfflineItem(
            brandTokens: ["starbucks", "sbux"],
            itemMatch: [["iced", "oat", "latte"], ["iced", "oatmilk", "latte"]],
            name: "Starbucks Iced Oatmilk Latte (Grande)",
            detail: "Oatmilk · offline",
            kcal: 190, protein: 3, carbs: 24, fat: 8,
            slot: "breakfast", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["starbucks", "sbux"],
            itemMatch: [["pumpkin", "spice", "latte"], ["psl"]],
            name: "Starbucks Pumpkin Spice Latte (Grande)",
            detail: "2% milk, whipped cream · offline",
            kcal: 390, protein: 14, carbs: 52, fat: 14,
            slot: "breakfast", confidence: 0.93
        ),
        OfflineItem(
            brandTokens: ["starbucks", "sbux"],
            itemMatch: [["cold", "brew"]],
            name: "Starbucks Cold Brew (Grande)",
            detail: "Black · offline",
            kcal: 5, protein: 1, carbs: 0, fat: 0,
            slot: "breakfast", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["starbucks", "sbux"],
            itemMatch: [["frappuccino"], ["frap"]],
            name: "Starbucks Caramel Frappuccino (Grande)",
            detail: "Whipped cream · offline",
            kcal: 380, protein: 5, carbs: 56, fat: 15,
            slot: "snack", confidence: 0.92
        ),
        OfflineItem(
            brandTokens: ["starbucks", "sbux"],
            itemMatch: [["latte", "oat"], ["latte", "oatmilk"]],
            name: "Starbucks Oatmilk Latte (Grande)",
            detail: "Oatmilk · offline",
            kcal: 270, protein: 4, carbs: 35, fat: 12,
            slot: "breakfast", confidence: 0.93
        ),
        OfflineItem(
            brandTokens: ["starbucks", "sbux"],
            itemMatch: [["latte"]],
            name: "Starbucks Caffe Latte (Grande)",
            detail: "2% milk · offline",
            kcal: 190, protein: 13, carbs: 18, fat: 7,
            slot: "breakfast", confidence: 0.9
        ),

        // -------- Chick-fil-A --------
        OfflineItem(
            brandTokens: ["chick-fil-a", "chickfila", "chick fil a"],
            itemMatch: [["spicy", "chicken", "sandwich"]],
            name: "Chick-fil-A Spicy Chicken Sandwich",
            detail: "No sides · offline",
            kcal: 450, protein: 28, carbs: 41, fat: 20,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["chick-fil-a", "chickfila", "chick fil a"],
            itemMatch: [["chicken", "sandwich"]],
            name: "Chick-fil-A Chicken Sandwich",
            detail: "Original, no sides · offline",
            kcal: 420, protein: 28, carbs: 41, fat: 17,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["chick-fil-a", "chickfila", "chick fil a"],
            itemMatch: [["grilled", "nugget"]],
            name: "Chick-fil-A Grilled Nuggets (12 pc)",
            detail: "Lean · offline",
            kcal: 210, protein: 38, carbs: 2, fat: 5,
            slot: "lunch", confidence: 0.93
        ),
        OfflineItem(
            brandTokens: ["chick-fil-a", "chickfila", "chick fil a"],
            itemMatch: [["nugget"]],
            name: "Chick-fil-A Chicken Nuggets (8 pc)",
            detail: "Breaded · offline",
            kcal: 250, protein: 27, carbs: 11, fat: 11,
            slot: "lunch", confidence: 0.92
        ),
        OfflineItem(
            brandTokens: ["chick-fil-a", "chickfila", "chick fil a"],
            itemMatch: [["waffle", "fry"], ["waffle", "fries"]],
            name: "Chick-fil-A Waffle Fries (Medium)",
            detail: "Side · offline",
            kcal: 420, protein: 5, carbs: 50, fat: 24,
            slot: "snack", confidence: 0.95
        ),

        // -------- Burger King --------
        OfflineItem(
            brandTokens: ["burger king", "bk"],
            itemMatch: [["whopper", "jr"]],
            name: "Burger King Whopper Jr.",
            detail: "Chain menu match · offline",
            kcal: 340, protein: 15, carbs: 29, fat: 19,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["burger king", "bk"],
            itemMatch: [["whopper"]],
            name: "Burger King Whopper",
            detail: "Chain menu match · offline",
            kcal: 670, protein: 28, carbs: 49, fat: 40,
            slot: "lunch", confidence: 0.95
        ),

        // -------- Subway --------
        OfflineItem(
            brandTokens: ["subway"],
            itemMatch: [["turkey", "footlong"], ["footlong", "turkey"]],
            name: "Subway Turkey Footlong",
            detail: "9-grain wheat, standard veg · offline",
            kcal: 560, protein: 36, carbs: 90, fat: 8,
            slot: "lunch", confidence: 0.93
        ),
        OfflineItem(
            brandTokens: ["subway"],
            itemMatch: [["italian", "bmt"]],
            name: "Subway Italian B.M.T. (6 inch)",
            detail: "9-grain wheat · offline",
            kcal: 420, protein: 19, carbs: 45, fat: 17,
            slot: "lunch", confidence: 0.93
        ),

        // -------- Taco Bell --------
        OfflineItem(
            brandTokens: ["taco bell"],
            itemMatch: [["crunchwrap", "supreme"]],
            name: "Taco Bell Crunchwrap Supreme",
            detail: "Beef · offline",
            kcal: 530, protein: 16, carbs: 71, fat: 21,
            slot: "lunch", confidence: 0.95
        ),
        OfflineItem(
            brandTokens: ["taco bell"],
            itemMatch: [["crunchy", "taco"]],
            name: "Taco Bell Crunchy Taco",
            detail: "Beef · offline",
            kcal: 170, protein: 8, carbs: 13, fat: 9,
            slot: "snack", confidence: 0.93
        )
    ]

    /// Resolve a transcript using the curated offline chain rules. `followUp`
    /// is the user's answer to a prior clarifying question, if any.
    static func resolve(transcript: String, followUpAnswer: String? = nil) -> OfflineFallbackResult {
        let text = transcript.lowercased()
        let answer = (followUpAnswer ?? "").lowercased()

        // Chipotle bowl — supports the guac-portion follow-up. Lives outside
        // the table because of the structured ingredient + follow-up flow.
        if text.contains("chipotle") && text.contains("bowl") {
            let guacAnswered = answer.contains("single") || answer.contains("double") || answer.contains("two")
            if text.contains("guac") && !guacAnswered {
                return .followUp(
                    question: "Single scoop of guac?",
                    reasoning: "Need guac portion to finalize macros."
                )
            }
            let doubleChicken = text.contains("double") && text.contains("chicken")
            let chickenCals = doubleChicken ? 360 : 180
            let chickenProtein = doubleChicken ? 64 : 32
            let chickenFat = doubleChicken ? 14 : 7
            let guacDouble = answer.contains("double") || answer.contains("two")
            let wantsGuac = text.contains("guac")
            let guacCals = wantsGuac ? (guacDouble ? 460 : 230) : 0
            let guacFat = wantsGuac ? (guacDouble ? 44 : 22) : 0
            let guacCarbs = wantsGuac ? (guacDouble ? 16 : 8) : 0
            let kcal = 210 + 130 + chickenCals + guacCals
            let detail = "\(doubleChicken ? "double" : "single") chicken, brown rice, black beans"
                + (wantsGuac ? ", \(guacDouble ? "2× guac" : "1× guac")" : "")
                + " · offline"
            return .meal(VoiceParseResponse(
                transcript: transcript,
                follow_up_question: nil,
                meal: .init(
                    name: "Chipotle Chicken Bowl",
                    detail: detail,
                    kcal: kcal,
                    protein_g: chickenProtein + 9,
                    carbs_g: 45 + 22 + guacCarbs,
                    fat_g: chickenFat + 2 + guacFat,
                    slot: "lunch", source: "voice", confidence: 0.92
                ),
                reasoning: "Offline Chipotle template."
            ))
        }

        // Table-driven brand+item match. First match in `table` wins, so
        // order entries from most-specific to least-specific within a brand.
        for item in table {
            guard item.brandTokens.contains(where: { text.contains($0) }) else { continue }
            let hit = item.itemMatch.contains { group in
                group.allSatisfy { text.contains($0) }
            }
            if hit {
                return .meal(VoiceParseResponse(
                    transcript: transcript,
                    follow_up_question: nil,
                    meal: .init(
                        name: item.name,
                        detail: item.detail,
                        kcal: item.kcal, protein_g: item.protein,
                        carbs_g: item.carbs, fat_g: item.fat,
                        slot: item.slot, source: "voice",
                        confidence: item.confidence
                    ),
                    reasoning: "Offline chain match: \(item.name)."
                ))
            }
        }

        return .miss
    }

    /// Generic last-resort estimate — clearly flagged as low confidence so
    /// the UI / Siri can frame it as a guess rather than a fact.
    static func genericEstimate(transcript: String) -> VoiceParseResponse {
        VoiceParseResponse(
            transcript: transcript,
            follow_up_question: nil,
            meal: .init(
                name: "Meal from voice",
                detail: "Estimated fallback · offline",
                kcal: 450, protein_g: 20, carbs_g: 45, fat_g: 20,
                slot: "snack", source: "voice", confidence: 0.4
            ),
            reasoning: "Offline fallback estimate — no matcher confident enough."
        )
    }
}
