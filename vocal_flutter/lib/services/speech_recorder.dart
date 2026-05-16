// Streaming speech-to-text — Flutter port of SpeechRecorder.swift.
// Wraps the speech_to_text plugin (Android SpeechRecognizer + iOS Speech /
// SFSpeechRecognizer). Publishes partial text while you talk and a final
// transcript on stop. Falls back to typed input if permission is denied or
// the recognizer is unavailable.

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';

class SpeechRecorder extends ChangeNotifier {
  final SpeechToText _stt = SpeechToText();

  String partialTranscript = '';
  bool isRecording = false;
  String? lastError;
  bool _available = false;
  bool _authorized = false;

  bool get isAuthorized => _authorized;
  bool get isAvailable => _available;

  /// Asks for mic permission and initializes the recognizer. Safe to call
  /// repeatedly — the OS only shows the prompt the first time.
  Future<void> requestAuthorization() async {
    try {
      final mic = await Permission.microphone.request();
      _authorized = mic.isGranted;
      if (!_authorized) {
        lastError = 'Microphone permission denied.';
        notifyListeners();
        return;
      }
      _available = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            if (isRecording) {
              isRecording = false;
              notifyListeners();
            }
          }
        },
        onError: (err) {
          lastError = err.errorMsg;
          isRecording = false;
          notifyListeners();
        },
      );
    } catch (e) {
      _available = false;
      lastError = e.toString();
    }
    notifyListeners();
  }

  /// Begin streaming transcription. Throws if setup fails so the caller can
  /// show the typing fallback.
  Future<void> start() async {
    if (isRecording) return;
    if (!_available || !_authorized) {
      throw StateError(
          'Speech recognition unavailable or microphone permission denied.');
    }
    partialTranscript = '';
    lastError = null;
    isRecording = true;
    notifyListeners();

    await _stt.listen(
      onResult: (result) {
        partialTranscript = result.recognizedWords;
        notifyListeners();
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 4),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
    );
  }

  /// End the recording session. Idempotent.
  Future<void> stop() async {
    if (!isRecording) return;
    isRecording = false;
    try {
      await _stt.stop();
    } catch (_) {}
    notifyListeners();
  }

  /// Stop and return the final transcript.
  Future<String> finish() async {
    final t = partialTranscript;
    await stop();
    return t;
  }
}
