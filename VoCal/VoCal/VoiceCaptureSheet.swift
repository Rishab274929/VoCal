//
//  VoiceCaptureSheet.swift
//  VoCal
//
//  The killer flow: listen → parse → (maybe follow up) → review → save.
//  Visually a single dramatic dark sheet: editorial heading, big serif
//  transcript, animated coral orb, hairline buttons. Calls the live
//  /api/voice/parse endpoint and falls back to local parsing offline.
//

import SwiftUI

struct VoiceCaptureSheet: View {
    enum Phase { case listening, parsing, followUp, review }

    @EnvironmentObject private var appModel: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .listening
    @State private var promptIndex = 0
    @State private var promptRotator: Timer?

    @State private var transcriptDraft = ""
    @State private var followUpQuestion: String?
    @State private var followUpAnswer = ""
    @State private var parseReasoning = ""
    @State private var parseError: String?
    @State private var parsedMeal: MealEntry?
    @State private var parseStartedAt: Date?
    @State private var isUserEditing = false

    @StateObject private var recorder = SpeechRecorder()

    var body: some View {
        ZStack {
            Theme.Palette.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header
                Spacer(minLength: 12)

                Group {
                    switch phase {
                    case .listening: listeningContent
                    case .parsing:   parsingContent
                    case .followUp:  followUpContent
                    case .review:    reviewContent
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer()

                footerButtons
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .onAppear {
            transcriptDraft = MockData.voicePrompts[promptIndex]
            startPromptRotator()
            startRecordingIfPossible()
        }
        .onDisappear {
            promptRotator?.invalidate()
            recorder.stop()
        }
        .onChange(of: recorder.partialTranscript) { _, newValue in
            // Live transcript replaces the rotating placeholder once user starts speaking
            if phase == .listening, !isUserEditing, !newValue.isEmpty {
                transcriptDraft = newValue
            }
        }
    }

    private func startRecordingIfPossible() {
        Task {
            await recorder.requestAuthorization()
            guard recorder.isAuthorized else { return }
            do {
                try recorder.start()
            } catch {
                parseError = error.localizedDescription
            }
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(eyebrowText.uppercased())
                    .eyebrow(Theme.Palette.pulse)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.ash)
                        .frame(width: 32, height: 32)
                        .background(Circle().strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            Text(headlineText)
                .font(Theme.Font.serif(32, weight: .medium))
                .foregroundStyle(Theme.Palette.bone)
                .multilineTextAlignment(.leading)
        }
    }

    private var eyebrowText: String {
        switch phase {
        case .listening: "Listening"
        case .parsing:   "Parsing"
        case .followUp:  "One more thing"
        case .review:    "Here's what I caught"
        }
    }

    private var headlineText: String {
        switch phase {
        case .listening: "Just say what you ate."
        case .parsing:   "Working on it…"
        case .followUp:  "Quick check"
        case .review:    parsedMeal?.name ?? "Meal"
        }
    }

    // MARK: listening

    private var listeningContent: some View {
        VStack(spacing: 32) {
            WaveformOrb(isActive: true, tint: Theme.Palette.pulse)
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 12) {
                Text("TRY SAYING")
                    .eyebrow()
                Text("\u{201C}\(MockData.voicePrompts[promptIndex])\u{201D}")
                    .font(Theme.Font.serif(20, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.ash)
                    .lineLimit(3)
                    .id("prompt-\(promptIndex)")
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Text(recorder.isRecording ? "LIVE TRANSCRIPT" : "TRANSCRIPT")
                        .eyebrow(recorder.isRecording ? Theme.Palette.pulse : Theme.Palette.smoke)
                    if recorder.isRecording {
                        Circle()
                            .fill(Theme.Palette.pulse)
                            .frame(width: 6, height: 6)
                            .scaleEffect(recorder.isRecording ? 1 : 0.5)
                            .animation(.easeInOut(duration: 0.6).repeatForever(), value: recorder.isRecording)
                    }
                }
                TextField(
                    "",
                    text: $transcriptDraft,
                    prompt: Text("Type or speak…").foregroundStyle(Theme.Palette.smoke),
                    axis: .vertical
                )
                .lineLimit(2...4)
                .foregroundStyle(Theme.Palette.bone)
                .textInputAutocapitalization(.sentences)
                .padding(.vertical, 14)
                .padding(.horizontal, 14)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                        .fill(Theme.Palette.inkSurface)
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                                .strokeBorder(Theme.Palette.hairlineStrong, lineWidth: 1)
                        )
                )
                .onTapGesture { isUserEditing = true }
            }

            if let parseError {
                Text(parseError)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.pulse)
            }
        }
    }

    // MARK: parsing (transitional state)

    private var parsingContent: some View {
        VStack(spacing: 28) {
            WaveformOrb(isActive: true, tint: Theme.Palette.voltage)
                .frame(width: 220, height: 220)
                .frame(maxWidth: .infinity)

            Text(transcriptDraft)
                .font(Theme.Font.serif(24, weight: .regular, italic: true))
                .foregroundStyle(Theme.Palette.bone)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.Palette.voltage)
                Text("Checking restaurant menus + USDA…")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.Palette.smoke)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: follow-up

    private var followUpContent: some View {
        VStack(spacing: 24) {
            FollowUpQuestionCard(
                question: followUpQuestion ?? "Could you clarify?",
                answer: $followUpAnswer
            )
            Text("WHY?")
                .eyebrow()
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(parseReasoning.isEmpty ? "Helps lock the macro estimate." : parseReasoning)
                .font(.system(size: 13))
                .foregroundStyle(Theme.Palette.ash)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: review

    private var reviewContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let meal = parsedMeal {
                VStack(alignment: .leading, spacing: 10) {
                    DisplayNumber(value: meal.calories, label: "calories")
                    Text(meal.detail)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.Palette.ash)
                }

                HStack(spacing: 10) {
                    MacroPill(letter: "P", value: meal.protein, tint: Theme.Palette.protein)
                    MacroPill(letter: "C", value: meal.carbs, tint: Theme.Palette.carbs)
                    MacroPill(letter: "F", value: meal.fat, tint: Theme.Palette.fat)
                    Spacer()
                    Text(meal.slot.rawValue.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(2.0)
                        .foregroundStyle(Theme.Palette.voltage)
                }

                if !parseReasoning.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("REASONING")
                            .eyebrow()
                        Text(parseReasoning)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.Palette.ash)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("TRANSCRIPT")
                    .eyebrow()
                Text(transcriptDraft)
                    .font(Theme.Font.serif(18, weight: .regular, italic: true))
                    .foregroundStyle(Theme.Palette.bone)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous)
                    .fill(Theme.Palette.inkSurface)
            )
        }
    }

    // MARK: footer

    private var footerButtons: some View {
        HStack(spacing: 12) {
            switch phase {
            case .listening, .parsing:
                GhostButton(title: "Cancel", icon: nil) {
                    dismiss()
                }
                VoltageButton(title: phase == .parsing ? "Working…" : "Stop & parse", icon: phase == .parsing ? nil : "stop.fill") {
                    Task { await parseCurrentTranscript() }
                }
                .opacity(phase == .parsing ? 0.5 : 1)
                .allowsHitTesting(phase != .parsing)

            case .followUp:
                GhostButton(title: "Back") {
                    withAnimation(.spring) {
                        phase = .listening
                        followUpAnswer = ""
                        parseError = nil
                    }
                }
                VoltageButton(title: "Submit", icon: "arrow.right") {
                    Task { await parseCurrentTranscript(followUp: followUpAnswer) }
                }
                .opacity(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .allowsHitTesting(!followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            case .review:
                GhostButton(title: "Re-record", icon: "arrow.counterclockwise") {
                    isUserEditing = false
                    transcriptDraft = ""
                    parsedMeal = nil
                    parseReasoning = ""
                    withAnimation(.spring) { phase = .listening }
                    startRecordingIfPossible()
                }
                VoltageButton(title: "Save", icon: "checkmark") {
                    guard let meal = parsedMeal else { return }
                    appModel.addMeal(meal)
                    dismiss()
                }
            }
        }
    }

    // MARK: parsing pipeline

    private func parseCurrentTranscript(followUp: String? = nil) async {
        // Flush mic if still capturing
        if recorder.isRecording {
            let final = recorder.finish()
            if !final.isEmpty {
                transcriptDraft = final
            }
        }

        parseError = nil
        parseStartedAt = Date()
        withAnimation(.easeInOut) { phase = .parsing }

        let payloadTranscript = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let response = try await VoiceAPIClient.parseMeal(transcript: payloadTranscript, followUpAnswer: followUp)
            parseReasoning = response.reasoning
            if let question = response.follow_up_question, response.meal == nil {
                followUpQuestion = question
                withAnimation(.spring) { phase = .followUp }
                return
            }
            guard let meal = response.meal else {
                parseError = "No meal returned. Try again."
                withAnimation { phase = .listening }
                return
            }
            applyParsedMeal(meal, transcript: response.transcript)
        } catch {
            // Local fallback so the demo still works offline
            if let local = localFallback(for: payloadTranscript, followUp: followUp) {
                applyParsedMeal(local.meal, transcript: payloadTranscript, reasoning: local.reasoning)
            } else {
                parseError = "Couldn't parse. Try re-recording."
                withAnimation { phase = .listening }
            }
        }
    }

    private func applyParsedMeal(_ raw: VoiceParseResponse.ParsedMeal, transcript: String, reasoning: String? = nil) {
        let slot = MealEntry.Slot(rawValue: raw.slot) ?? .snack
        let src = MealEntry.Source(rawValue: raw.source) ?? .voice
        parsedMeal = MealEntry(
            name: raw.name,
            detail: raw.detail,
            calories: raw.kcal,
            protein: raw.protein_g,
            carbs: raw.carbs_g,
            fat: raw.fat_g,
            loggedAt: .now,
            slot: slot,
            source: src
        )
        transcriptDraft = transcript
        if let reasoning { parseReasoning = reasoning }
        withAnimation(.spring) { phase = .review }
    }

    private struct LocalFallbackResult {
        let meal: VoiceParseResponse.ParsedMeal
        let reasoning: String
    }

    private func localFallback(for transcript: String, followUp: String?) -> LocalFallbackResult? {
        let text = transcript.lowercased()
        let answer = (followUp ?? "").lowercased()

        if text.contains("mcdonald") && text.contains("fry") {
            return LocalFallbackResult(
                meal: .init(name: "McDonald's French Fries (Medium)", detail: "Chain menu match · offline cache",
                            kcal: 320, protein_g: 4, carbs_g: 43, fat_g: 15, slot: "snack", source: "voice", confidence: 0.97),
                reasoning: "Offline match against cached McDonald's menu."
            )
        }
        if text.contains("starbucks") && text.contains("latte") {
            return LocalFallbackResult(
                meal: .init(name: "Starbucks Iced Oatmilk Latte (Grande)", detail: "Oatmilk · offline cache",
                            kcal: 190, protein_g: 3, carbs_g: 24, fat_g: 8, slot: "breakfast", source: "voice", confidence: 0.95),
                reasoning: "Offline match against cached Starbucks menu."
            )
        }
        if text.contains("chipotle") && text.contains("bowl") {
            let guacAnswered = answer.contains("single") || answer.contains("double") || answer.contains("two")
            if text.contains("guac") && !guacAnswered {
                followUpQuestion = "Single scoop of guac?"
                parseReasoning = "Need guac portion to finalize macros."
                withAnimation(.spring) { phase = .followUp }
                return nil
            }
            // Per Chipotle's published nutrition: brown rice 210, black beans 130,
            // chicken 180, guac 230 (1 scoop) / 460 (2 scoops), fajita veg ~20.
            let doubleChicken = text.contains("double") && text.contains("chicken")
            let chickenCals = doubleChicken ? 360 : 180
            let chickenProtein = doubleChicken ? 64 : 32
            let chickenFat = doubleChicken ? 14 : 7
            let guacDouble = answer.contains("double") || answer.contains("two")
            let guacCals = guacDouble ? 460 : 230
            let guacFat = guacDouble ? 44 : 22
            let kcal = 210 /* brown rice */ + 130 /* black beans */ + chickenCals + guacCals
            let detail = (doubleChicken ? "double" : "single") + " chicken, brown rice, black beans, "
                + (guacDouble ? "2× guac" : "1× guac") + " · offline"
            return LocalFallbackResult(
                meal: .init(
                    name: "Chipotle Chicken Bowl",
                    detail: detail,
                    kcal: kcal,
                    protein_g: chickenProtein + 5 /* beans */ + 4 /* rice */,
                    carbs_g: 45 /* rice */ + 22 /* beans */ + (guacDouble ? 16 : 8) /* guac */,
                    fat_g: chickenFat + 2 /* rice/beans */ + guacFat,
                    slot: "lunch", source: "voice", confidence: 0.92
                ),
                reasoning: "Offline match against cached Chipotle template."
            )
        }
        return LocalFallbackResult(
            meal: .init(name: "Meal from voice", detail: "Estimated fallback",
                        kcal: 450, protein_g: 20, carbs_g: 45, fat_g: 20,
                        slot: "snack", source: "voice", confidence: 0.5),
            reasoning: "Offline fallback estimate."
        )
    }

    private func startPromptRotator() {
        promptRotator?.invalidate()
        promptRotator = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.easeInOut) {
                    promptIndex = (promptIndex + 1) % MockData.voicePrompts.count
                    if phase == .listening {
                        transcriptDraft = MockData.voicePrompts[promptIndex]
                    }
                }
            }
        }
    }
}

// MARK: - API client

private enum VoiceAPIClient {
    static func parseMeal(transcript: String, followUpAnswer: String?) async throws -> VoiceParseResponse {
        let baseURL = ProcessInfo.processInfo.environment["VOCAL_API_BASE_URL"] ?? "https://vocal.best/api"
        guard let endpoint = URL(string: "\(baseURL)/voice/parse") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // 15s is enough headroom for the backend's LLM path (chain canon hits
        // resolve in <100ms; LLM cache-miss is ~2-8s; USDA fallback ~1-2s).
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(
            VoiceParsePayload(transcript: transcript, follow_up_answer: followUpAnswer)
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(VoiceParseResponse.self, from: data)
    }
}

#Preview {
    VoiceCaptureSheet()
        .environmentObject(AppModel(
            totals: MockData.today,
            meals: MockData.recentMeals,
            profile: MockData.profile,
            hasCompletedOnboarding: true
        ))
        .preferredColorScheme(.dark)
}
