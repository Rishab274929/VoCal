//
//  FoodCanon.swift
//  VoCal
//
//  On-device food canon. The first-stop lookup before any network call:
//  ~100 of the most common foods, sourced from USDA FoodData Central plus
//  published brand nutrition for prepared items. Each entry has aliases so
//  natural phrases ("an apple", "two scrambled eggs", "slice of pepperoni
//  pizza") match without an LLM round-trip.
//
//  Lookup is two-pass:
//    1. Exact alias match against the normalized transcript tokens.
//    2. All-tokens-present fuzzy match — every word in the alias must appear
//       in the transcript (order-free). First/highest-priority entry wins.
//
//  Misses fall through to `VoiceAPIClient.parseMeal`, which hits the backend
//  for chain canon + LLM + USDA.
//

import Foundation

struct FoodCanonEntry: Decodable {
    let name: String
    let aliases: [String]
    let portion: String
    let kcal: Int
    let protein_g: Int
    let carbs_g: Int
    let fat_g: Int
    let default_slot: String
}

private struct CanonFile: Decodable {
    let version: Int
    let entries: [FoodCanonEntry]
}

/// Singleton holding the loaded canon. Loads on first access from the bundled
/// `food_canon.json` resource. If the resource is missing (shouldn't happen
/// in production) the lookup just returns `nil` and the caller falls back to
/// the network — no crash.
final class FoodCanon {
    static let shared = FoodCanon()

    let entries: [FoodCanonEntry]

    private init() {
        guard let url = Bundle.main.url(forResource: "food_canon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let parsed = try? JSONDecoder().decode(CanonFile.self, from: data) else {
            self.entries = []
            return
        }
        self.entries = parsed.entries
    }

    /// Best-effort match for a free-text transcript. Returns nil on miss.
    ///
    /// The on-device canon intentionally skips any transcript that names a
    /// known restaurant chain — those queries deserve the backend's chain
    /// canon ("Burger King Whopper" should not collapse to a generic
    /// cheeseburger; "medium fry from McDonald's" should not collapse to
    /// generic fries).
    func lookup(_ transcript: String) -> FoodCanonEntry? {
        let lowered = transcript.lowercased()
        if Self.chainHints.contains(where: { lowered.contains($0) }) {
            return nil
        }
        let norm = Self.normalize(transcript)
        guard !norm.isEmpty else { return nil }

        // Pass 1 — exact alias hit. Pick the longest alias to disambiguate
        // ("two eggs" beats "egg").
        var best: (entry: FoodCanonEntry, aliasLen: Int)? = nil
        for entry in entries {
            for alias in entry.aliases {
                let a = Self.normalize(alias)
                if norm == a || norm.contains(" \(a) ") || norm.hasPrefix("\(a) ") || norm.hasSuffix(" \(a)") {
                    if best == nil || a.count > best!.aliasLen {
                        best = (entry, a.count)
                    }
                }
            }
        }
        if let best { return best.entry }

        // Pass 2 — all-tokens-present fuzzy. Every word of the alias must
        // appear (as a whole word) somewhere in the transcript. Keeps the
        // longest match.
        let transcriptTokens = Set(norm.split(separator: " ").map(String.init))
        for entry in entries {
            for alias in entry.aliases {
                let aliasTokens = Self.normalize(alias).split(separator: " ").map(String.init)
                guard aliasTokens.count >= 2 else { continue }
                if aliasTokens.allSatisfy({ transcriptTokens.contains($0) }) {
                    if best == nil || aliasTokens.count > best!.aliasLen {
                        best = (entry, aliasTokens.count)
                    }
                }
            }
        }
        return best?.entry
    }

    /// Restaurant chain hints. Any of these in the transcript means we punt
    /// to the backend rather than guess from a generic on-device entry.
    private static let chainHints: Set<String> = [
        "mcdonald", "starbucks", "chipotle", "chick-fil-a", "chickfila", "chick fil a",
        "burger king", "subway", "taco bell", "wendy", "panera", "cava",
        "sweetgreen", "domino", "pizza hut", "five guys", "in-n-out", "in n out",
        "shake shack", "kfc", "popeyes", "panda express", "olive garden",
        "cheesecake factory", "chili's", "applebees", "applebee's",
        "buffalo wild wings", "outback", "tgi friday", "denny",
        "ihop", "dunkin", "jamba juice", "smoothie king", "jersey mike",
        "jimmy john", "potbelly", "qdoba", "moe's", "moes"
    ]

    /// Lowercase, strip punctuation, drop filler words, collapse whitespace.
    /// Mirrors `vocal-api/src/lib/normalize.ts` so client + backend cache
    /// keys line up.
    static func normalize(_ s: String) -> String {
        let filler: Set<String> = [
            "uh", "um", "uhh", "umm", "like", "you", "know", "so", "just",
            "really", "actually", "basically", "i", "ate", "had", "got",
            "have", "having", "a", "an", "the", "some", "of"
        ]
        let lowered = s.lowercased()
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789 '-")
        var cleaned = ""
        cleaned.reserveCapacity(lowered.count)
        for ch in lowered {
            if allowed.contains(ch) {
                cleaned.append(ch)
            } else {
                cleaned.append(" ")
            }
        }
        return cleaned
            .split(separator: " ")
            .filter { !$0.isEmpty && !filler.contains(String($0)) }
            .joined(separator: " ")
    }
}

extension FoodCanonEntry {
    /// Convert a canon hit into the `ParsedMeal` payload shape the
    /// rest of the app already speaks.
    func asParsedMeal(transcript: String) -> VoiceParseResponse.ParsedMeal {
        VoiceParseResponse.ParsedMeal(
            name: name,
            detail: portion + " · cached",
            kcal: kcal,
            protein_g: protein_g,
            carbs_g: carbs_g,
            fat_g: fat_g,
            slot: default_slot,
            source: "voice",
            confidence: 0.92
        )
    }
}
