//
//  VoiceCoach.swift
//  VoCal
//
//  Conversational voice coach: continuous on-device speech recognition
//  (free), backend LLM (cheap, via Wafer GLM-5.1), on-device TTS
//  (AVSpeechSynthesizer, free). The coach knows the user's day because
//  every request includes today's DailyMacrosSnapshot.
//
//  Cost model: only the LLM tokens cost money. STT and TTS are local.
//  At ~300 tokens in / ~120 tokens out per turn, a typical session
//  ($0.0001 / 1k input on GLM-5.1) is well under a cent.
//
//  Architecture:
//   - VoiceCoachSession is an @MainActor ObservableObject the CoachView
//     hosts. It owns the SpeechRecorder, the AVSpeechSynthesizer, and
//     the conversation history.
//   - One method `startTurn()` flips the session into listening mode.
//     When the user pauses for ~1.5s, the recorder stops and the
//     transcript is sent to /api/coach. The reply text is appended to
//     the chat AND read aloud.
//   - `interrupt()` stops the TTS so the user can talk back.
//

import Foundation
import AVFoundation
import Combine
import Speech

@MainActor
final class VoiceCoachSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // MARK: - State

    enum Phase: Equatable {
        case idle
        case listening
        case thinking
        case speaking
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var liveTranscript: String = ""
    @Published private(set) var lastError: String?

    /// Conversation history visible to the model. We keep the last 8 turns
    /// so the coach can follow up ("what about pasta then?") without bloat.
    @Published private(set) var history: [CoachMessage] = []

    // MARK: - Internals

    private let recorder = SpeechRecorder()
    private let synth = AVSpeechSynthesizer()
    private var silenceTimer: Timer?
    private var lastTranscriptUpdate: Date = .now
    private var transcriptCancellable: AnyCancellable?
    private var todaySnapshot: DailyMacrosSnapshot?

    override init() {
        super.init()
        synth.delegate = self
    }

    deinit {
        silenceTimer?.invalidate()
    }

    // MARK: - Public

    /// Begin one conversational turn. Asks permissions if needed, then
    /// listens until the user stops speaking for ~1.5s.
    func startTurn() {
        // Interrupt any TTS in progress.
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        // Always read the freshest day-state snapshot before each turn.
        todaySnapshot = DailyMacrosSnapshot.read()

        Task { [weak self] in
            guard let self else { return }
            await recorder.requestAuthorization()
            guard recorder.isAuthorized else {
                lastError = "Microphone or speech permission denied."
                phase = .idle
                return
            }
            do {
                try recorder.start()
                phase = .listening
                liveTranscript = ""
                lastTranscriptUpdate = .now
                bindTranscript()
                armSilenceTimer()
            } catch {
                lastError = error.localizedDescription
                phase = .idle
            }
        }
    }

    /// Tap-to-stop. Used by a "Send" button while listening.
    func endTurn() {
        guard phase == .listening else { return }
        finalizeTurn()
    }

    /// Stop everything (TTS + recording). Called when the user leaves the view.
    func cancel() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        transcriptCancellable?.cancel()
        transcriptCancellable = nil
        if recorder.isRecording {
            _ = recorder.finish()
        }
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        phase = .idle
    }

    /// Manually send a typed prompt (the chat composer still works for
    /// users who don't want to speak).
    func sendTyped(_ text: String) {
        let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        todaySnapshot = DailyMacrosSnapshot.read()
        history.append(CoachMessage(role: .user, content: prompt))
        Task { await callBackend(prompt: prompt) }
    }

    // MARK: - Live transcript handling

    private func bindTranscript() {
        transcriptCancellable = recorder.$partialTranscript
            .sink { [weak self] new in
                guard let self else { return }
                self.liveTranscript = new
                self.lastTranscriptUpdate = .now
            }
    }

    /// Polls every 250ms; if no transcript update for 1.5s while the user
    /// has actually said something, treat it as end-of-turn.
    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.phase == .listening else { return }
                let idleFor = Date().timeIntervalSince(self.lastTranscriptUpdate)
                if !self.liveTranscript.isEmpty && idleFor > 1.5 {
                    self.finalizeTurn()
                }
            }
        }
    }

    private func finalizeTurn() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        let final = recorder.finish()
        let prompt = final.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            phase = .idle
            return
        }
        history.append(CoachMessage(role: .user, content: prompt))
        Task { await callBackend(prompt: prompt) }
    }

    // MARK: - Backend turn

    private func callBackend(prompt: String) async {
        phase = .thinking
        do {
            let reply = try await CoachAPI.send(
                prompt: prompt,
                history: history.suffix(8).map { ($0.role.rawValue, $0.content) },
                snapshot: todaySnapshot
            )
            history.append(CoachMessage(role: .assistant, content: reply))
            speak(reply)
        } catch {
            let fallback = "Sorry — I couldn't reach the coach. \(error.localizedDescription)"
            history.append(CoachMessage(role: .assistant, content: fallback))
            phase = .idle
            lastError = error.localizedDescription
        }
    }

    // MARK: - TTS

    private func speak(_ text: String) {
        phase = .speaking
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            // Best-effort — if audio session fails the synth will still try.
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = preferredVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0
        synth.speak(utterance)
    }

    private func preferredVoice() -> AVSpeechSynthesisVoice? {
        // Apple's "Enhanced" or "Premium" voices have a much warmer timbre
        // than the default. Fall back to any en-US voice.
        let preferredIDs = [
            "com.apple.voice.premium.en-US.Zoe",
            "com.apple.voice.enhanced.en-US.Evan",
            "com.apple.voice.enhanced.en-US.Samantha",
            "com.apple.voice.enhanced.en-US.Aaron"
        ]
        for id in preferredIDs {
            if let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        }
        return AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.phase = .idle }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.phase = .idle }
    }
}

// MARK: - Backend client

enum CoachAPI {
    private struct Payload: Codable {
        var prompt: String
        var history: [HistoryTurn]
        var totals: TotalsDTO?
        struct HistoryTurn: Codable { let role: String; let content: String }
        struct TotalsDTO: Codable {
            var calorie_goal: Int
            var calories_eaten: Int
            var protein_goal: Int
            var protein_eaten: Int
            var carbs_goal: Int
            var carbs_eaten: Int
            var fat_goal: Int
            var fat_eaten: Int
        }
    }
    private struct Response: Codable { let reply: String }
    private struct ErrorBody: Codable { let error: String? }

    enum Error: Swift.Error, LocalizedError {
        case badResponse
        case server(Int, String)
        var errorDescription: String? {
            switch self {
            case .badResponse:        "Bad coach response."
            case .server(let s, let m): "Coach \(s): \(m)"
            }
        }
    }

    static func send(
        prompt: String,
        history: [(role: String, content: String)],
        snapshot: DailyMacrosSnapshot?
    ) async throws -> String {
        guard let url = URL(string: "\(APIConfig.baseURL)/coach") else {
            throw Error.badResponse
        }
        let totals = snapshot.map {
            Payload.TotalsDTO(
                calorie_goal: $0.calorieGoal,
                calories_eaten: $0.caloriesEaten,
                protein_goal: $0.proteinGoal,
                protein_eaten: $0.proteinEaten,
                carbs_goal: $0.carbsGoal,
                carbs_eaten: $0.carbsEaten,
                fat_goal: $0.fatGoal,
                fat_eaten: $0.fatEaten
            )
        }
        let payload = Payload(
            prompt: prompt,
            history: history.map { Payload.HistoryTurn(role: $0.role, content: $0.content) },
            totals: totals
        )
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 30
        req.httpBody = try JSONEncoder().encode(payload)
        await AuthSession.shared.authorize(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }
        if !(200..<300).contains(http.statusCode) {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error ?? "HTTP \(http.statusCode)"
            throw Error.server(http.statusCode, msg)
        }
        return try JSONDecoder().decode(Response.self, from: data).reply
    }
}
