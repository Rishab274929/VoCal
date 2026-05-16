// Backend photo client — Flutter port of /api/photo/parse caller.
//
// POST /api/photo/parse
// Body: { image_base64: String, voice_context?: String, follow_up_answer?: String }
// Returns the same VoiceParseResponse shape as /api/voice/parse so the UI
// (follow-up loop, ParsedMeal review) handles both paths identically.
//
// Image policy
// ----------------------------------------------------------------------------
// We resize to max-edge 1024px @ JPEG q=70 BEFORE base64 encoding. The
// backend hard-rejects payloads over ~1.5 MB. iOS's CameraCaptureView does
// the same downscale; matching here means the LLM sees comparable inputs
// across platforms (and our token spend per parse stays predictable).
//
// We do the resize off the platform channel (pure Dart, package:image) so
// the CPU work happens on the Dart isolate's microtask queue — `compute()`
// would marshal a multi-MB byte array across isolates and end up slower
// for typical phone photos (~2-5 MB).
//
// Auth header is pluggable through PhotoApiAuth.tokenLoader — same pattern
// as coach_api.dart so the AuthSession agent only has to wire one place.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

import '../models/models.dart';
import 'voice_api.dart' show ApiConfig;

/// Pluggable auth header source — see CoachApiAuth in coach_api.dart for the
/// rationale. Set once at app init from main.dart.
class PhotoApiAuth {
  static Future<String?> Function()? tokenLoader;
}

class PhotoApiException implements Exception {
  final String message;
  PhotoApiException(this.message);
  @override
  String toString() => 'PhotoApiException: $message';
}

class PhotoApiClient {
  /// Max edge in pixels post-resize. 1024 is the lowest that still gives the
  /// vision model enough detail to read text on a chain-restaurant cup
  /// (Cava bowl labels, etc.). Going to 768 dropped chain-recognition
  /// accuracy on internal tests; staying at 2048 doubled token cost.
  static const int _maxEdgePx = 1024;

  /// JPEG quality 0-100. 70 keeps file size ~150-300KB for a typical phone
  /// photo while still being legible to GPT-4o-mini. Higher quality buys
  /// almost nothing past q=70 for meal photos (low-detail subjects).
  static const int _jpegQuality = 70;

  /// 15s timeout — matches the voice_api timeout (the underlying LLM call
  /// has the same p99 distribution). The image upload itself is a few
  /// hundred KB so network time is negligible on cellular.
  static const Duration _timeout = Duration(seconds: 15);

  /// Resize the given JPEG/HEIC/PNG file to a max edge of 1024px,
  /// re-encode as JPEG q=70, return the base64 string (no data URL prefix).
  /// Falls back to the raw file bytes if decode fails — better to send a
  /// too-big image and let the server reject it than to silently fail here.
  static Future<String> _encodeImage(File file) async {
    final bytes = await file.readAsBytes();
    img.Image? decoded;
    try {
      decoded = img.decodeImage(bytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      // Couldn't decode — best effort: base64 the raw bytes. The server may
      // still accept it (it handles JPEG/PNG); if not, the error surfaces
      // through the normal failure path.
      return base64Encode(bytes);
    }
    final longSide = decoded.width >= decoded.height
        ? decoded.width
        : decoded.height;
    img.Image processed = decoded;
    if (longSide > _maxEdgePx) {
      // Resize down (never up — upscaling adds no signal and inflates bytes).
      if (decoded.width >= decoded.height) {
        processed = img.copyResize(decoded,
            width: _maxEdgePx, interpolation: img.Interpolation.linear);
      } else {
        processed = img.copyResize(decoded,
            height: _maxEdgePx, interpolation: img.Interpolation.linear);
      }
    }
    final jpeg = img.encodeJpg(processed, quality: _jpegQuality);
    return base64Encode(jpeg);
  }

  /// Parse a meal photo. Pass `followUpAnswer` only on a follow-up turn —
  /// the first call should leave it null. `voiceContext` is whatever the
  /// user typed/spoke alongside the photo (may be empty).
  static Future<VoiceParseResponse> parseMeal({
    required File image,
    String? voiceContext,
    String? followUpAnswer,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/photo/parse');

    String b64;
    try {
      b64 = await _encodeImage(image);
    } catch (e) {
      throw PhotoApiException('Could not encode image: $e');
    }

    // Mirror iOS payload keys exactly. The backend accepts both `image_b64`
    // and `image_base64` (case-tolerant per parse.ts:106) — we send the
    // canonical `image_base64` form that iOS uses, so server-side telemetry
    // keys align across clients.
    final body = <String, dynamic>{
      'image_base64': b64,
    };
    final vc = voiceContext?.trim();
    if (vc != null && vc.isNotEmpty) {
      body['voice_context'] = vc;
    }
    if (followUpAnswer != null && followUpAnswer.trim().isNotEmpty) {
      body['follow_up_answer'] = followUpAnswer.trim();
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    final loader = PhotoApiAuth.tokenLoader;
    if (loader != null) {
      try {
        final token = await loader();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // Soft-auth: backend accepts unauthenticated photo parses.
      }
    }

    final http.Response res;
    try {
      res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw PhotoApiException('Request timed out');
    } on SocketException catch (e) {
      throw PhotoApiException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw PhotoApiException('HTTP client error: ${e.message}');
    }

    if (res.statusCode == 413) {
      // Backend rejected the image as too large. Our resize should keep us
      // well under the cap; if we hit this it's almost certainly an
      // un-decodable source that fell through to the raw-bytes path above.
      throw PhotoApiException('Photo too large — try a different shot.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw PhotoApiException('Bad server response (${res.statusCode})');
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw PhotoApiException('Malformed photo response');
      }
      return VoiceParseResponse.fromJson(decoded);
    } on FormatException catch (e) {
      throw PhotoApiException('Malformed photo response: ${e.message}');
    }
  }
}
