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

        // For plural/typo tolerance, also build a "lemmatized" copy where
        // common English plurals collapse to their singular ("apples" →
        // "apple", "berries" → "berry"). This is checked alongside the
        // literal form so we never *lose* a literal match — we only ADD
        // matches that would have been missed.
        let lemmaTokens = norm.split(separator: " ").map { Self.singularize(String($0)) }
        let lemmaNorm = lemmaTokens.joined(separator: " ")
        let transcriptTokens: Set<String> = Set(
            norm.split(separator: " ").map(String.init) + lemmaTokens
        )

        // Pass 1 — exact alias hit. Pick the longest alias to disambiguate
        // ("two eggs" beats "egg"). Use strict `>` so that on a tie the
        // *first-declared* entry wins, which lets the JSON's authoring
        // order serve as a tie-break ranking signal.
        var best: (entry: FoodCanonEntry, aliasLen: Int)? = nil
        for entry in entries {
            for alias in entry.aliases {
                let a = Self.normalize(alias)
                guard !a.isEmpty else { continue }
                if Self.containsWhole(a, in: norm) || Self.containsWhole(a, in: lemmaNorm) {
                    if best == nil || a.count > best!.aliasLen {
                        best = (entry, a.count)
                    }
                }
            }
        }
        if let best { return best.entry }

        // Pass 2 — all-tokens-present fuzzy. Every word of the alias must
        // appear (as a whole word) somewhere in the transcript. Keeps the
        // longest match. Lemmatize both sides so "apples" still matches a
        // multi-word alias containing "apple".
        for entry in entries {
            for alias in entry.aliases {
                let aliasTokens = Self.normalize(alias)
                    .split(separator: " ")
                    .map { Self.singularize(String($0)) }
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

    /// Whole-word containment: does `needle` appear inside `haystack` as a
    /// standalone token (not as a substring of a longer word)? Handles the
    /// edge cases of needle at the start, end, or exact match of haystack.
    private static func containsWhole(_ needle: String, in haystack: String) -> Bool {
        if haystack == needle { return true }
        if haystack.hasPrefix("\(needle) ") { return true }
        if haystack.hasSuffix(" \(needle)") { return true }
        return haystack.contains(" \(needle) ")
    }

    /// Naive English singularizer — strips a trailing 's' / 'es' / 'ies'
    /// suffix when the rest of the token is at least 2 chars. Not linguistic,
    /// just enough to fix the "apples" / "berries" / "tomatoes" miss cases.
    /// Leaves single-character words and known non-pluralizable tokens
    /// (e.g. "rice", "pasta", "tuna") alone.
    private static func singularize(_ token: String) -> String {
        // Tokens ending in 'ss' (e.g. "swiss") aren't plurals.
        if token.hasSuffix("ss") { return token }
        if token.hasSuffix("ies") && token.count >= 5 {
            // "berries" → "berry"; "fries" stays "fries" because aliases
            // include the literal plural form, but normalize will still
            // match via lemmaTokens if needed.
            return String(token.dropLast(3)) + "y"
        }
        if token.hasSuffix("es") && token.count >= 4 {
            // "tomatoes" → "tomato"; "boxes" → "box"
            return String(token.dropLast(2))
        }
        if token.hasSuffix("s") && token.count >= 3 {
            return String(token.dropLast(1))
        }
        return token
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
