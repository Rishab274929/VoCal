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
final class VoiceCoachSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {

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

    /// True while the TTS-fetched mp3 (or local fallback synth) is actively
    /// playing audio. CoachView observes this to drive the SPEAKING indicator
    /// — same UI lights for both the ElevenLabs and AVSpeechSynthesizer
    /// paths so the user can't tell which is in use.
    @Published private(set) var isSpeaking: Bool = false

    /// User-controlled mute toggle bound to CoachView's speaker icon.
    /// When false, every TTS fetch is skipped — text still appears in the
    /// thread but no audio plays (no AVSpeechSynthesizer fallback either,
    /// since the explicit intent is "silent mode").
    @Published var voiceEnabled: Bool = true

    // MARK: - Internals

    private let recorder = SpeechRecorder()
    private let synth = AVSpeechSynthesizer()
    private var silenceTimer: Timer?
    private var lastTranscriptUpdate: Date = .now
    private var transcriptCancellable: AnyCancellable?
    private var todaySnapshot: DailyMacrosSnapshot?

    // MARK: - TTS playback (ElevenLabs via /api/coach/voice)
    /// AVAudioPlayer holds onto the decoded mp3; we have to retain it for
    /// the lifetime of playback or it tears down mid-utterance with no
    /// callback. Kept as a property rather than a local in speakRemote()
    /// for the same reason.
    private var audioPlayer: AVAudioPlayer?
    /// The audio-session category that was active before we forced
    /// `.playback` for TTS. Restored in audioPlayerDidFinishPlaying so
    /// other apps (music, podcasts) un-duck correctly.
    private var priorAudioCategory: AVAudioSession.Category?
    private var priorAudioMode: AVAudioSession.Mode?
    /// Token for the in-flight TTS URLSession task. Stored so cancel()
    /// can drop a pending fetch when the user navigates away or starts
    /// a new turn before the audio has begun streaming.
    private var ttsTask: Task<Void, Never>?

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
        // Guard against double-tap on the mic button kicking off two
        // recorder.start() calls in parallel. Only spin up if we're idle.
        guard phase == .idle else { return }
        // Interrupt any TTS in progress.
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        // Always read the freshest day-state snapshot before each turn.
        todaySnapshot = DailyMacrosSnapshot.read()
        // Optimistically claim the phase so a second startTurn() bounces
        // off the `guard` above before the auth Task even begins.
        phase = .listening

        Task { [weak self] in
            guard let self else { return }
            await recorder.requestAuthorization()
            guard recorder.isAuthorized else {
                lastError = "Microphone or speech permission denied. Enable both in Settings → VoCal."
                phase = .idle
                return
            }
            do {
                try recorder.start()
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
        // Hard-cancel rather than `finish()` — we're aborting, not flushing.
        // `cancel()` is sync so we don't strand the user mid-navigation.
        recorder.cancel()
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        // Drop the in-flight TTS fetch + any actively playing mp3 so the
        // coach goes truly silent when the user navigates away. Without
        // these, a slow TTS request would finish 5-15s later and start
        // playback while the user is on a different screen.
        ttsTask?.cancel()
        ttsTask = nil
        if let player = audioPlayer, player.isPlaying {
            player.stop()
        }
        audioPlayer = nil
        isSpeaking = false
        // Hand the audio session back to other apps so music/podcasts can
        // resume. Without this, ducked apps stay ducked indefinitely after
        // the user leaves Coach.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        // Cancel any prior subscription first, otherwise repeated startTurn
        // calls accumulate sinks that all write to liveTranscript.
        transcriptCancellable?.cancel()
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
        transcriptCancellable?.cancel()
        transcriptCancellable = nil
        // Move to thinking immediately so the UI doesn't sit on "LISTENING"
        // while we wait ~700ms for the recognizer's final transcript.
        phase = .thinking
        Task { [weak self] in
            guard let self else { return }
            let final = await recorder.finish()
            let prompt = final.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !prompt.isEmpty else {
                phase = .idle
                return
            }
            history.append(CoachMessage(role: .user, content: prompt))
            await callBackend(prompt: prompt)
        }
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
        // Refuse to enqueue empty utterances — synth.speak on empty string
        // is a no-op that doesn't trigger didFinish, leaving us stuck in
        // .speaking forever.
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            phase = .idle
            isSpeaking = false
            return
        }
        // Voice muted by the user — text reply already landed in history,
        // so we just stay silent and return the phase to idle.
        guard voiceEnabled else {
            phase = .idle
            isSpeaking = false
            return
        }
        phase = .speaking
        isSpeaking = true

        // Cancel any prior TTS fetch so an old reply's audio can't play
        // on top of a new one (rare, but happens if the user fires two
        // turns in quick succession).
        ttsTask?.cancel()
        ttsTask = Task { [weak self] in
            guard let self else { return }
            do {
                let mp3 = try await CoachVoiceAPI.fetch(text: trimmed)
                if Task.isCancelled { return }
                await self.playRemote(mp3: mp3, fallbackText: trimmed)
            } catch {
                // Any non-200 / network / decode failure: silent skip per
                // spec. Coach has already shown the text reply, so the
                // user just gets no audio. Don't fall back to AVSpeech
                // here — the spec says coach must keep working in
                // text-only mode, NOT "use the OS voice as backup".
                await MainActor.run {
                    self.isSpeaking = false
                    if self.phase == .speaking { self.phase = .idle }
                }
            }
        }
    }

    /// Decode + play the mp3 buffer that came back from /api/coach/voice.
    /// Stays @MainActor because AVAudioPlayer init + audio-session calls
    /// must run on the main thread per Apple's docs.
    private func playRemote(mp3: Data, fallbackText: String) async {
        do {
            // Snapshot the current audio category/mode so we can restore
            // them after playback. Without this, the next time the user
            // hits the mic the session is still in .playback mode and
            // recording can fail with a "deactivated input" error.
            let session = AVAudioSession.sharedInstance()
            priorAudioCategory = session.category
            priorAudioMode = session.mode

            // `.playback` is required to actually emit audio when the
            // mute switch is on (the coach replying mid-meeting is the
            // whole point of the voice mode). `.spokenAudio` mode +
            // `.duckOthers` mirrors the AVSpeechSynth path so a podcast
            // dips politely instead of mixing or cutting out.
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let player = try AVAudioPlayer(data: mp3)
            player.delegate = self
            audioPlayer = player
            if !player.prepareToPlay() {
                throw NSError(domain: "VoiceCoach.TTS", code: -2, userInfo: [NSLocalizedDescriptionKey: "prepareToPlay returned false"])
            }
            if !player.play() {
                throw NSError(domain: "VoiceCoach.TTS", code: -3, userInfo: [NSLocalizedDescriptionKey: "play returned false"])
            }
        } catch {
            // Decode / playback failure — clean up the audio session and
            // stay silent. We deliberately do NOT fall back to local
            // AVSpeechSynth here; the user got the text reply already
            // and a sudden Siri-voice would be jarring.
            audioPlayer = nil
            isSpeaking = false
            releaseAudioSessionAfterPlayback()
            if phase == .speaking { phase = .idle }
        }
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
        Task { @MainActor [weak self] in
            self?.releaseAudioSessionAfterPlayback()
            self?.isSpeaking = false
            self?.phase = .idle
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.releaseAudioSessionAfterPlayback()
            self?.isSpeaking = false
            self?.phase = .idle
        }
    }

    // MARK: - AVAudioPlayerDelegate (remote TTS mp3 playback)

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioPlayer = nil
            self.isSpeaking = false
            self.releaseAudioSessionAfterPlayback()
            if self.phase == .speaking { self.phase = .idle }
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        // Treat decode errors the same as a successful-but-empty finish:
        // clean up and silently bail. Coach text reply already showed.
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.audioPlayer = nil
            self.isSpeaking = false
            self.releaseAudioSessionAfterPlayback()
            if self.phase == .speaking { self.phase = .idle }
        }
    }

    /// Restore the audio-session category that was active before the TTS
    /// reply, then deactivate so music/podcasts can un-duck. Without the
    /// category restore the session stays in `.playback` mode, which can
    /// break the speech recognizer the next time the user taps the mic.
    private func releaseAudioSessionAfterPlayback() {
        let session = AVAudioSession.sharedInstance()
        if let prior = priorAudioCategory {
            try? session.setCategory(prior, mode: priorAudioMode ?? .default)
        }
        priorAudioCategory = nil
        priorAudioMode = nil
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Coach voice TTS client

/// Wraps POST /api/coach/voice. Returns the raw mp3 bytes on 2xx. Throws
/// on any non-200 so the caller can decide whether to fall back silently
/// (VoiceCoachSession.speak does — spec says coach must keep working in
/// text-only mode if TTS fails).
enum CoachVoiceAPI {
    private struct Payload: Codable { let text: String }

    enum Error: Swift.Error, LocalizedError {
        case badResponse
        case server(Int)
        case empty
        var errorDescription: String? {
            switch self {
            case .badResponse: "Bad TTS response."
            case .server(let s): "TTS HTTP \(s)."
            case .empty: "Empty TTS body."
            }
        }
    }

    /// Fetch the audio/mpeg body for `text`. 20s timeout because the
    /// upstream ElevenLabs proxy can be slow on cold starts — anything
    /// shorter and the very first reply of a session often times out.
    static func fetch(text: String) async throws -> Data {
        guard let url = URL(string: "\(APIConfig.baseURL)/coach/voice") else {
            throw Error.badResponse
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 20
        req.httpBody = try JSONEncoder().encode(Payload(text: text))
        await AuthSession.shared.authorize(&req)
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw Error.badResponse }
        await MainActor.run { AuthSession.shared.captureMintedSessionIfNeeded(from: http) }
        guard (200..<300).contains(http.statusCode) else {
            throw Error.server(http.statusCode)
        }
        guard !data.isEmpty else { throw Error.empty }
        return data
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
