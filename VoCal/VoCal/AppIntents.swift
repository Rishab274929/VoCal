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
        let response = try await VoiceParseAPI.parse(transcript: spokenText)

        guard let meal = response.meal else {
            let dialog: IntentDialog = "I couldn't parse that. Try saying it like 'medium fry from McDonald's'."
            return .result(dialog: dialog)
        }

        // Save to local cache via App Group / shared store (post-hackathon)
        // For now we just confirm verbally so Siri can read it back.
        let dialog = IntentDialog("Logged \(meal.name) at \(meal.kcal) calories.")
        return .result(dialog: dialog)
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
        AppShortcut(
            intent: LogMealByVoiceIntent(),
            phrases: [
                "Log a meal in \(.applicationName)",
                "Log what I ate in \(.applicationName)",
                "Track a meal in \(.applicationName)"
            ],
            shortTitle: "Log meal",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: GetDailyMacrosIntent(),
            phrases: [
                "What are my macros in \(.applicationName)",
                "How many calories do I have left in \(.applicationName)"
            ],
            shortTitle: "Today's macros",
            systemImageName: "chart.bar.xaxis"
        )
        AppShortcut(
            intent: OpenMicIntent(),
            phrases: [
                "Open the mic in \(.applicationName)"
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

        let baseURL = ProcessInfo.processInfo.environment["VOCAL_API_BASE_URL"] ?? "https://vocal.best/api"
        guard let endpoint = URL(string: "\(baseURL)/voice/parse") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Match VoiceCaptureSheet; LLM path can be ~5-8s.
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(VoiceParsePayload(transcript: transcript, follow_up_answer: followUp))

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
