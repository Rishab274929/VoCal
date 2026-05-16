// Backend client — Flutter port of APIConfig.swift + VoiceAPIClient.
// Single source of truth for the base URL. The custom domain vocal.best is
// live and Cloudflare-fronted. Override for local dev with:
//   flutter run --dart-define=VOCAL_API_BASE_URL=http://10.0.2.2:8788/api
// (10.0.2.2 is the Android emulator's alias for the host machine.)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';

class ApiConfig {
  static const String baseUrl = String.fromEnvironment(
    'VOCAL_API_BASE_URL',
    defaultValue: 'https://vocal.best/api',
  );
}

class VoiceApiException implements Exception {
  final String message;
  VoiceApiException(this.message);
  @override
  String toString() => 'VoiceApiException: $message';
}

class VoiceApiClient {
  /// 15s headroom for the backend LLM path (chain canon hits resolve in
  /// <100ms; LLM cache-miss is ~2-8s; USDA fallback ~1-2s). Mirrors iOS
  /// VoiceCaptureSheet.swift timeoutInterval = 15.
  static Future<VoiceParseResponse> parseMeal({
    required String transcript,
    String? followUpAnswer,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/voice/parse');
    // Match the iOS payload shape exactly: when followUpAnswer is null,
    // OMIT the key rather than sending `"follow_up_answer": null`. The
    // backend handles both, but the omit form is what Swift's JSONEncoder
    // produces and what cache keys upstream are built around.
    final Map<String, dynamic> body = <String, dynamic>{
      'transcript': transcript,
    };
    if (followUpAnswer != null) {
      body['follow_up_answer'] = followUpAnswer;
    }

    final http.Response res;
    try {
      res = await http
          .post(
            uri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw VoiceApiException('Request timed out');
    } on SocketException catch (e) {
      throw VoiceApiException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw VoiceApiException('HTTP client error: ${e.message}');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw VoiceApiException('Bad server response (${res.statusCode})');
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw VoiceApiException('Malformed server response');
      }
      return VoiceParseResponse.fromJson(decoded);
    } on FormatException catch (e) {
      throw VoiceApiException('Malformed server response: ${e.message}');
    }
  }
}
