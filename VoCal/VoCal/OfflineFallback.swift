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
    /// Resolve a transcript using the curated offline chain rules. `followUp`
    /// is the user's answer to a prior clarifying question, if any.
    static func resolve(transcript: String, followUpAnswer: String? = nil) -> OfflineFallbackResult {
        let text = transcript.lowercased()
        let answer = (followUpAnswer ?? "").lowercased()

        // McDonald's fries
        if text.contains("mcdonald") && text.contains("fry") {
            return .meal(VoiceParseResponse(
                transcript: transcript,
                follow_up_question: nil,
                meal: .init(
                    name: "McDonald's French Fries (Medium)",
                    detail: "Chain menu match · offline",
                    kcal: 320, protein_g: 4, carbs_g: 43, fat_g: 15,
                    slot: "snack", source: "voice", confidence: 0.97
                ),
                reasoning: "Offline McDonald's match."
            ))
        }

        // Starbucks oat latte
        if text.contains("starbucks") && text.contains("latte") {
            return .meal(VoiceParseResponse(
                transcript: transcript,
                follow_up_question: nil,
                meal: .init(
                    name: "Starbucks Iced Oatmilk Latte (Grande)",
                    detail: "Oatmilk · offline",
                    kcal: 190, protein_g: 3, carbs_g: 24, fat_g: 8,
                    slot: "breakfast", source: "voice", confidence: 0.95
                ),
                reasoning: "Offline Starbucks match."
            ))
        }

        // Chipotle bowl — supports the guac-portion follow-up
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
