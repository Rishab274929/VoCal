//
//  AppIntents.swift
//  VoCal
//
//  App Intents — exposed to Siri, Shortcuts, Spotlight, Action Button,
//  and the Camera Control button. The flagship intent is
//  `LogMealByVoiceIntent`: takes a spoken sentence, sends it through the
//  same parse pipeline the app uses, returns confirmation.
//

import AppIntents
import Foundation

// MARK: - Log meal by voice

@available(iOS 16.0, *)
struct LogMealByVoiceIntent: AppIntent {
    static var title: LocalizedStringResource = "Log meal by voice"
    static var description = IntentDescription(
        "Speak what you ate and VoCal logs it with calories and macros."
    )
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "What did you eat?",
        description: "Say what you ate. \"Medium fry from McDonald's\" works.",
        requestValueDialog: IntentDialog("What did you eat?")
    )
    var spokenText: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Trim + validate. Siri occasionally hands us empty strings if the
        // user cancels the parameter prompt — bail with a friendly retry
        // instead of POSTing "" to the parser.
        let trimmed = spokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            let dialog: IntentDialog = "I didn't catch that. Try saying what you ate."
            return .result(dialog: dialog)
        }

        let response: VoiceParseResponse
        do {
            response = try await VoiceParseAPI.parse(transcript: trimmed)
        } catch {
            // Hard network failure → fall back through the offline matcher.
            // The matcher already short-circuits chain queries to deterministic
            // macros, so the killer demos still work in airplane mode.
            switch OfflineFallback.resolve(transcript: trimmed, followUpAnswer: nil) {
            case .meal(let r):     response = r
            case .followUp, .miss:
                let dialog: IntentDialog = "I couldn't reach VoCal's network. Open the app and try again."
                return .result(dialog: dialog)
            }
        }

        guard let meal = response.meal else {
            // The backend asked a follow-up question. Siri can't easily do a
            // multi-turn clarification inside one intent perform, so we
            // surface the question verbatim and let the user log it in-app.
            if let q = response.follow_up_question {
                let dialog = IntentDialog(stringLiteral: "Before I log that — \(q) Open VoCal to finish.")
                return .result(dialog: dialog)
            }
            let dialog: IntentDialog = "I couldn't parse that. Try saying it like 'medium fry from McDonald's'."
            return .result(dialog: dialog)
        }

        // Persist the meal in two places so the running app picks it up:
        //   1. Bump the DailyMacrosSnapshot so "what are my macros" reflects
        //      the change before the app is even opened.
        //   2. Append to a pending-meals queue keyed in UserDefaults; the
        //      next AppModel mutation can drain it. The app reads this queue
        //      on launch / foreground via PendingMealQueue.
        DailyMacrosSnapshot.addMealToSnapshot(meal)
        PendingMealQueue.enqueue(meal: meal, transcript: trimmed)

        let dialog = IntentDialog(stringLiteral: "Logged \(meal.name) at \(meal.kcal) calories.")
        return .result(dialog: dialog)
    }
}

// MARK: - Pending meal queue (cross-process bridge for Siri logs)

/// Lightweight UserDefaults-backed FIFO of meals Siri logged while the app
/// was suspended. The app drains this queue on launch / foreground so the
/// macros land in the persisted store and HealthKit gets the writes.
///
/// Lives in AppIntents.swift to stay inside the voice-subsystem scope; the
/// app-side reader can be added in a follow-up PR without breaking us here.
enum PendingMealQueue {
    private static let defaultsKey = "vocal.pendingSiriMeals.v1"

    struct Item: Codable {
        let name: String
        let detail: String
        let kcal: Int
        let protein_g: Int
        let carbs_g: Int
        let fat_g: Int
        let slot: String
        let source: String
        let transcript: String
        let loggedAt: Date
    }

    static func enqueue(meal: VoiceParseResponse.ParsedMeal, transcript: String) {
        var existing = readAll()
        existing.append(Item(
            name: meal.name,
            detail: meal.detail,
            kcal: meal.kcal,
            protein_g: meal.protein_g,
            carbs_g: meal.carbs_g,
            fat_g: meal.fat_g,
            slot: meal.slot,
            source: meal.source,
            transcript: transcript,
            loggedAt: .now
        ))
        // Hard cap so a misbehaving Siri loop can't blow up UserDefaults.
        if existing.count > 32 { existing = Array(existing.suffix(32)) }
        if let data = try? JSONEncoder().encode(existing) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }

    static func readAll() -> [Item] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let items = try? JSONDecoder().decode([Item].self, from: data) else {
            return []
        }
        return items
    }

    static func drain() -> [Item] {
        let items = readAll()
        UserDefaults.standard.removeObject(forKey: defaultsKey)
        return items
    }
}

// MARK: - Snapshot mutation helper used by LogMealByVoiceIntent
//
// Defined here (not in Item.swift) to stay in scope. Reads the current
// snapshot, increments the eaten counters by the parsed meal's macros, and
// writes it back. If the snapshot is stale (different day) we start from a
// fresh zero-eaten baseline first.
@available(iOS 16.0, *)
extension DailyMacrosSnapshot {
    static func addMealToSnapshot(_ meal: VoiceParseResponse.ParsedMeal) {
        let current = DailyMacrosSnapshot.read() ?? DailyMacrosSnapshot(
            date: .now,
            calorieGoal: 2000, caloriesEaten: 0,
            proteinGoal: 140,  proteinEaten: 0,
            carbsGoal: 220,    carbsEaten: 0,
            fatGoal: 65,       fatEaten: 0
        )
        let updated = DailyMacrosSnapshot(
            date: .now,
            calorieGoal: current.calorieGoal,
            caloriesEaten: current.caloriesEaten + meal.kcal,
            proteinGoal: current.proteinGoal,
            proteinEaten: current.proteinEaten + meal.protein_g,
            carbsGoal: current.carbsGoal,
            carbsEaten: current.carbsEaten + meal.carbs_g,
            fatGoal: current.fatGoal,
            fatEaten: current.fatEaten + meal.fat_g
        )
        if let data = try? JSONEncoder().encode(updated) {
            UserDefaults.standard.set(data, forKey: DailyMacrosSnapshot.defaultsKey)
        }
    }
}

// MARK: - Get daily macros

@available(iOS 16.0, *)
struct GetDailyMacrosIntent: AppIntent {
    static var title: LocalizedStringResource = "Get daily macros"
    static var description = IntentDescription("Hear your remaining calories and macros for today.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snap = DailyMacrosSnapshot.read() else {
            let dialog: IntentDialog = "I don't have your day's log yet. Open VoCal and log a meal first."
            return .result(dialog: dialog)
        }
        // Guard against an empty/zeroed snapshot — the calorie goal should
        // never be 0 in a real account. If it is, we haven't been fully set
        // up yet and the "you hit your goal" line would be a lie.
        guard snap.calorieGoal > 0 else {
            let dialog: IntentDialog = "I don't have your goal set yet. Open VoCal to finish setup."
            return .result(dialog: dialog)
        }
        let kcalLeft = snap.calorieRemaining
        let proteinShort = snap.proteinShort
        let line: String
        switch (kcalLeft, proteinShort) {
        case (0, 0):
            line = "You've hit your calorie and protein goals for today. Nice work."
        case (let k, 0) where k > 0:
            line = "You have \(k) calories left today, and you've hit your protein goal."
        case (0, let p) where p > 0:
            line = "You're at your calorie goal, but \(p) grams short on protein."
        case (let k, let p):
            line = "You have \(k) calories left today, and you're \(p) grams short on protein."
        }
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

// MARK: - Open mic

@available(iOS 16.0, *)
struct OpenMicIntent: AppIntent {
    static var title: LocalizedStringResource = "Open VoCal mic"
    static var description = IntentDescription("Open VoCal and start listening immediately.")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Open-app intents launch the app via the URL routed below
        .result()
    }
}

// MARK: - Shortcuts surface

@available(iOS 16.0, *)
struct VoCalShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        // AppShortcuts phrases can only slot in AppEntity / AppEnum
        // parameters, not raw String. Siri prompts for the meal text after
        // the intent is matched — one extra round-trip but acceptable.
        AppShortcut(
            intent: LogMealByVoiceIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Track a meal in \(.applicationName)",
                "Log what I ate in \(.applicationName)"
            ],
            shortTitle: "Log meal",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: GetDailyMacrosIntent(),
            phrases: [
                "What are my macros in \(.applicationName)",
                "How many calories do I have left in \(.applicationName)",
                "What's left for today in \(.applicationName)"
            ],
            shortTitle: "Today's macros",
            systemImageName: "chart.bar.xaxis"
        )
        AppShortcut(
            intent: OpenMicIntent(),
            phrases: [
                "Open the mic in \(.applicationName)",
                "Start listening in \(.applicationName)"
            ],
            shortTitle: "Open mic",
            systemImageName: "mic.fill"
        )
    }
}

// MARK: - API client shared with intents

enum VoiceParseAPI {
    static func parse(transcript: String, followUp: String? = nil) async throws -> VoiceParseResponse {
        // Tier 0: on-device canon. Resolves common foods instantly so Siri
        // can answer without a network round-trip when possible.
        if followUp == nil, let hit = FoodCanon.shared.lookup(transcript) {
            return VoiceParseResponse(
                transcript: transcript,
                follow_up_question: nil,
                meal: hit.asParsedMeal(transcript: transcript),
                reasoning: "Matched on-device canon (\(hit.name))."
            )
        }

        guard let endpoint = URL(string: "\(APIConfig.baseURL)/voice/parse") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Match VoiceCaptureSheet; LLM path can be ~5-8s.
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(VoiceParsePayload(transcript: transcript, follow_up_answer: followUp))
        await AuthSession.shared.authorize(&request)

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
            return try JSONDecoder().decode(VoiceParseResponse.self, from: data)
        }
        // Network failed — fall through to shared offline fallback. Siri can't
        // easily do a follow-up mid-intent, so we collapse `.followUp` to a
        // generic estimate with a polite reasoning string.
        switch OfflineFallback.resolve(transcript: transcript, followUpAnswer: followUp) {
        case .meal(let response):
            return response
        case .followUp:
            return OfflineFallback.genericEstimate(transcript: transcript)
        case .miss:
            return OfflineFallback.genericEstimate(transcript: transcript)
        }
    }
}
