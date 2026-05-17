// Backend TTS client — POST /api/coach/voice
//
// Body: { "text": String }
// Response: audio/mpeg (mp3 bytes), Bearer JWT required, rate-limited 20/min
//
// Mirrors the iOS CoachVoiceAPI in VoiceCoach.swift verbatim — same URL,
// same 20s timeout, same silent-fallback contract. Returns the raw mp3
// bytes; the caller (CoachView) is responsible for handing them to
// `just_audio` for playback.
//
// On any non-2xx / network / parse error we throw [TtsApiException]. The UI
// catches that and silently skips audio — the coach text reply has already
// landed, so a missing voice is just a (visible-only) quality regression,
// not a broken feature.
//
// Auth: pulled via [TtsApiAuth.tokenLoader] (set once in main.dart, same
// pattern as CoachApiAuth). We do NOT block the request on a missing token
// — the backend's body-fallback path can still resolve the user — but it
// will probably return 401, which we treat as any other non-200 (silent
// skip). That keeps an auth-bootstrap-race from masking a real backend
// outage as an "auth bug."

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'voice_api.dart' show ApiConfig;

/// Pluggable auth header source. Set once at app init:
///     TtsApiAuth.tokenLoader = () => auth.currentToken();
/// Keeping the indirection so this file doesn't have to import AuthSession
/// directly — same decoupling pattern as CoachApiAuth + PhotoApiAuth.
class TtsApiAuth {
  /// Returns the current bearer token or null. Should be fast (no
  /// network); AuthSession.currentToken() already caches + lazy-refreshes.
  static Future<String?> Function()? tokenLoader;
}

class TtsApiException implements Exception {
  final String message;
  TtsApiException(this.message);
  @override
  String toString() => 'TtsApiException: $message';
}

class TtsApiClient {
  /// 20s timeout matches iOS CoachVoiceAPI — the ElevenLabs proxy can be
  /// slow on cold starts, and shorter values caused the very first coach
  /// reply of a session to time out routinely during dev.
  static const Duration _timeout = Duration(seconds: 20);

  /// Fetch mp3 bytes for the given coach reply text. Returns the raw
  /// audio buffer on 2xx; throws [TtsApiException] on any failure.
  ///
  /// The caller is expected to write the bytes to a temp file or wrap
  /// them in a [StreamAudioSource] for `just_audio`. We don't decode or
  /// play here — that's a UI-layer concern.
  static Future<Uint8List> speak(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw TtsApiException('Refusing to TTS empty string');
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}/coach/voice');

    // Best-effort auth — same posture as CoachApiClient. Never block on
    // a tokenLoader exception; let the backend 401 in that case.
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'audio/mpeg',
    };
    final loader = TtsApiAuth.tokenLoader;
    if (loader != null) {
      try {
        final token = await loader();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // Swallow — see header note about auth-bootstrap races.
      }
    }

    final http.Response res;
    try {
      res = await http
          .post(uri, headers: headers, body: jsonEncode({'text': trimmed}))
          .timeout(_timeout);
    } on TimeoutException {
      throw TtsApiException('TTS request timed out');
    } on SocketException catch (e) {
      throw TtsApiException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw TtsApiException('HTTP client error: ${e.message}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw TtsApiException('Bad TTS response (${res.statusCode})');
    }
    if (res.bodyBytes.isEmpty) {
      throw TtsApiException('Empty TTS body');
    }
    return res.bodyBytes;
  }
}
