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

    init(locale: Locale = .current) {
        self.recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
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

        // Audio session setup
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
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

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                }
                if error != nil {
                    self.lastError = error?.localizedDescription
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
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Stop and return the final transcript.
    func finish() -> String {
        let final = partialTranscript
        stop()
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
