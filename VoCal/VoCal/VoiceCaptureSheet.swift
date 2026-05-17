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
import UIKit

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
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
        }
        .onAppear {
            // Do NOT pre-fill `transcriptDraft` with a tutorial prompt — the
            // "TRY SAYING" pill rotates independently below, and pre-filling
            // here used to get parsed as the actual meal if the rotator
            // overwrote what the user said before they hit Stop.
            startPromptRotator()
            startRecordingIfPossible()
        }
        .onDisappear {
            promptRotator?.invalidate()
            recorder.stop()
        }
        // Backgrounding while listening: iOS suspends the audio engine and
        // the recognition task can throw. Tear down cleanly here so the
        // mic doesn't stay "hot" against a suspended engine and so we don't
        // hand the user a half-broken session on the next foreground.
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            if recorder.isRecording {
                recorder.cancel()
                if phase == .listening {
                    parseError = "Recording stopped — the app went to the background."
                }
            }
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
            guard recorder.isAuthorized else {
                // Permission denied: surface a clear message instead of
                // leaving the user staring at a "TRANSCRIPT" placeholder
                // with no indication anything is broken. They can still
                // type into the field and tap "Stop & parse".
                parseError = recorder.micAuth == .denied
                    ? "Microphone access denied. Enable it in Settings → VoCal → Microphone."
                    : "Speech recognition disabled. Enable it in Settings → VoCal → Speech Recognition."
                return
            }
            // Guard against double-start when this is called from both
            // onAppear and the Re-record button in quick succession — the
            // recorder itself guards too, but clearing the prior error here
            // avoids a stale "denied" message from a prior session.
            guard !recorder.isRecording else { return }
            do {
                try recorder.start()
                parseError = nil
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
                        followUpQuestion = nil
                        parseError = nil
                    }
                    // Restart the mic on Back, otherwise the user sees a
                    // listening UI with no LIVE TRANSCRIPT pulse and the
                    // partials never flow in.
                    startRecordingIfPossible()
                }
                VoltageButton(title: "Submit", icon: "arrow.right") {
                    Task { await parseCurrentTranscript(followUp: followUpAnswer) }
                }
                .opacity(followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.4 : 1)
                .allowsHitTesting(!followUpAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            case .review:
                GhostButton(title: "Re-record", icon: "arrow.counterclockwise") {
                    // Reset EVERY piece of session state so the next round
                    // doesn't inherit a stale follow-up question or answer
                    // (previously you could record A → follow-up → save →
                    // record B → see A's follow-up still primed).
                    isUserEditing = false
                    transcriptDraft = ""
                    parsedMeal = nil
                    parseReasoning = ""
                    parseError = nil
                    followUpQuestion = nil
                    followUpAnswer = ""
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
        // Flush mic if still capturing. `finish()` awaits the recognizer's
        // final `isFinal` callback (up to ~700ms) so punctuation + casing
        // matches what the user actually said.
        if recorder.isRecording {
            let final = await recorder.finish()
            if !final.isEmpty, !isUserEditing {
                transcriptDraft = final
            }
        }

        parseError = nil
        parseStartedAt = Date()

        let payloadTranscript = transcriptDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't ship an empty string to the parser. Without this guard we'd
        // flip to .parsing, hit the network with "", and silently apply the
        // generic 450 kcal fallback estimate — a confusing UX.
        if payloadTranscript.isEmpty && followUp == nil {
            parseError = recorder.isAuthorized
                ? "Didn't catch that. Try again."
                : "Microphone access denied. Enable it in Settings to use voice."
            return
        }

        withAnimation(.easeInOut) { phase = .parsing }

        // Tier 0: on-device canon. Resolves whole foods + common prepared
        // items instantly without any network call. Only used when there is
        // no follow-up answer — once we're mid-clarification the backend
        // should own the resolution.
        if followUp == nil, let hit = FoodCanon.shared.lookup(payloadTranscript) {
            let meal = hit.asParsedMeal(transcript: payloadTranscript)
            parseReasoning = "Matched on-device canon (\(hit.name))."
            applyParsedMeal(meal, transcript: payloadTranscript)
            return
        }

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
            // Network failed — go through the shared offline fallback module.
            switch OfflineFallback.resolve(transcript: payloadTranscript, followUpAnswer: followUp) {
            case .meal(let response):
                if let meal = response.meal {
                    applyParsedMeal(meal, transcript: payloadTranscript, reasoning: response.reasoning)
                } else {
                    parseError = "Couldn't parse. Try re-recording."
                    withAnimation { phase = .listening }
                }
            case .followUp(let question, let reasoning):
                followUpQuestion = question
                parseReasoning = reasoning
                withAnimation(.spring) { phase = .followUp }
            case .miss:
                let generic = OfflineFallback.genericEstimate(transcript: payloadTranscript)
                if let meal = generic.meal {
                    applyParsedMeal(meal, transcript: payloadTranscript, reasoning: generic.reasoning)
                } else {
                    parseError = "Couldn't parse. Try re-recording."
                    withAnimation { phase = .listening }
                }
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
            source: src,
            sodium_mg: raw.sodium_mg,
            fiber_g: raw.fiber_g,
            sugar_g: raw.sugar_g,
            calcium_mg: raw.calcium_mg,
            iron_mg: raw.iron_mg,
            vitamin_c_mg: raw.vitamin_c_mg,
            potassium_mg: raw.potassium_mg
        )
        transcriptDraft = transcript
        if let reasoning { parseReasoning = reasoning }
        withAnimation(.spring) { phase = .review }
    }

    private func startPromptRotator() {
        promptRotator?.invalidate()
        promptRotator = Timer.scheduledTimer(withTimeInterval: 2.6, repeats: true) { _ in
            Task { @MainActor in
                // Only rotate the `promptIndex` (drives the "TRY SAYING" pill).
                // NEVER touch `transcriptDraft` here — overwriting the live
                // transcription every 2.6s caused the bug where the user said
                // "one monster" and got parsed as "medium fry from McDonald's".
                withAnimation(.easeInOut) {
                    promptIndex = (promptIndex + 1) % MockData.voicePrompts.count
                }
            }
        }
    }
}

// MARK: - API client

private enum VoiceAPIClient {
    static func parseMeal(transcript: String, followUpAnswer: String?) async throws -> VoiceParseResponse {
        guard let endpoint = URL(string: "\(APIConfig.baseURL)/voice/parse") else {
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
        await AuthSession.shared.authorize(&request)

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
