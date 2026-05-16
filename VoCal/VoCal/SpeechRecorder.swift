//
//  SpeechRecorder.swift
//  VoCal
//
//  Thin async wrapper over `SFSpeechRecognizer` + `AVAudioEngine` for
//  on-device, streaming meal-log transcription. Publishes partial text
//  while you talk and a final transcript on stop. Falls back to typed
//  input if either permission is denied or the recognizer fails.
//

import Foundation
import AVFoundation
import Speech
import Combine

@MainActor
final class SpeechRecorder: ObservableObject {
    enum AuthState { case unknown, authorized, denied, restricted }

    @Published private(set) var partialTranscript: String = ""
    @Published private(set) var isRecording: Bool = false
    @Published private(set) var lastError: String?
    @Published private(set) var micAuth: AuthState = .unknown
    @Published private(set) var speechAuth: AuthState = .unknown

    private let audioEngine = AVAudioEngine()
    private let recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Flips true when the recognition task delivers `result.isFinal`. Used
    /// by `finish()` to wait briefly for the cleaner final transcript instead
    /// of returning a stale partial.
    private var sawFinalResult: Bool = false

    init(locale: Locale = Locale(identifier: "en-US")) {
        // Pin to en-US by default: the food parser (chain canon, on-device
        // FoodCanon, backend LLM prompts) is English-only. Letting the
        // recognizer follow `Locale.current` meant a French/Spanish/etc.
        // user got transcripts the parser couldn't match and silently
        // collapsed to the generic 450 kcal stub.
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        registerInterruptionObserver()
    }

    /// Stop cleanly when the audio session is interrupted (phone call,
    /// Siri, alarm). Without this the engine would keep a stale tap and the
    /// next `start()` call would fail with `kAudioUnitErr_TooManyFramesToProcess`.
    ///
    /// We use the `[weak self]` closure form rather than a `addObserver(forName:...)`
    /// + manual deregistration in deinit because `SpeechRecorder` instances
    /// live for the lifetime of their owning SwiftUI view (`@StateObject`)
    /// or session object, so the observer never outlives the consumer. The
    /// `weak` capture lets ARC drop the instance freely either way.
    private func registerInterruptionObserver() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if type == .began, self.isRecording {
                    self.lastError = "Recording interrupted."
                    self.cancel()
                }
            }
        }
    }

    /// Asks for both Speech + Microphone authorization in parallel. Safe to
    /// call repeatedly — iOS will only show each system prompt the first time.
    func requestAuthorization() async {
        async let speechStatus: SFSpeechRecognizerAuthorizationStatus = withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status) }
        }
        async let micGranted: Bool = withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in cont.resume(returning: granted) }
        }
        let (speech, mic) = await (speechStatus, micGranted)
        speechAuth = Self.map(speech)
        micAuth = mic ? .authorized : .denied
    }

    var isAuthorized: Bool { micAuth == .authorized && speechAuth == .authorized }

    /// Begin streaming transcription. Throws if any setup step fails so the
    /// caller can show a fallback typing UI without surprising silence.
    func start() throws {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            throw NSError(domain: "VoCal.SpeechRecorder", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Speech recognition is unavailable on this device."])
        }
        guard isAuthorized else {
            throw NSError(domain: "VoCal.SpeechRecorder", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Microphone or speech permission denied."])
        }

        // Audio session setup.
        //
        // Use `.playAndRecord` (not `.record`) so the `.duckOthers` option is
        // actually honored — `.duckOthers` is silently ignored on a
        // record-only category. `.measurement` mode also disables system
        // echo cancellation, which is the wrong tradeoff for short, casual
        // voice memos in a noisy room. Switching to `.spokenAudio` /
        // `.default` gives us Apple's tuned processing for speech.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord,
                                mode: .spokenAudio,
                                options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Recognition request
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if #available(iOS 16.0, *) {
            req.addsPunctuation = true
        }
        request = req

        // Audio engine tap
        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak req] buffer, _ in
            req?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        partialTranscript = ""
        lastError = nil
        isRecording = true
        sawFinalResult = false

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            // SFSpeechRecognitionResult.isFinal is set on the LAST result
            // delivered after `endAudio()` — its transcript is the recognizer's
            // best polished output (full punctuation, casing, alternates
            // weighted in). The series of `partial` updates that precede it
            // can have stale text. We always overwrite `partialTranscript`
            // with the freshest result, and flip `sawFinalResult` once the
            // final lands so callers can wait for it deterministically.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.sawFinalResult = true
                    }
                }
                if let err = error as NSError? {
                    // kAFAssistantErrorDomain 203/216 are emitted on a clean
                    // `endAudio()` shutdown; treat them as success.
                    let isShutdownNoise = err.domain == "kAFAssistantErrorDomain" && (err.code == 203 || err.code == 216 || err.code == 1110)
                    if !isShutdownNoise {
                        self.lastError = err.localizedDescription
                    }
                    self.stop()
                }
            }
        }
    }

    /// End the recording session and tear down audio resources. Safe to call
    /// twice; idempotent.
    func stop() {
        guard isRecording else { return }
        isRecording = false
        // Remove the tap BEFORE stopping the engine; otherwise the tap can
        // keep firing on the audio thread while the engine is mid-teardown
        // and append into a request we've already ended.
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        // `endAudio()` tells the recognizer no more samples are coming so it
        // can deliver the polished `isFinal` result. We don't call
        // `task?.cancel()` here because that throws away the final result;
        // `finish()` lets the request drain.
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        // Best-effort: deactivating the session can fail if the engine is
        // still releasing IO. Swallowing is intentional — we've already
        // torn down the recording surface from the user's POV.
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Hard-cancel the recording. Used when the caller wants to abandon a
    /// turn entirely (e.g. permission revoked mid-flight) without waiting
    /// on a final result.
    func cancel() {
        guard isRecording else { return }
        isRecording = false
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        task?.cancel()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stop and return the final transcript. Briefly polls for the
    /// recognizer's `isFinal` callback (up to ~700ms) so callers get the
    /// polished transcript with punctuation rather than the last partial.
    /// The wait is short enough to feel instantaneous to the user but long
    /// enough that the recognizer has time to finalize on-device.
    func finish() async -> String {
        guard isRecording else { return partialTranscript }
        // Signal end-of-speech FIRST so the recognizer starts producing the
        // final. Then tear down the audio engine (no more frames feed in).
        request?.endAudio()
        if audioEngine.isRunning {
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.stop()
        }
        // Wait up to ~700ms for the final result, in 50ms slices.
        for _ in 0..<14 where !sawFinalResult {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        let final = partialTranscript
        // Now safely tear the rest down (idempotent with `stop()` since
        // engine is already stopped).
        isRecording = false
        task?.finish()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return final
    }

    private static func map(_ s: SFSpeechRecognizerAuthorizationStatus) -> AuthState {
        switch s {
        case .authorized: .authorized
        case .denied:     .denied
        case .restricted: .restricted
        case .notDetermined: .unknown
        @unknown default: .unknown
        }
    }
}
