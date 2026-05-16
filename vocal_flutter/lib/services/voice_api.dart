// Backend client — Flutter port of APIConfig.swift + VoiceAPIClient.
// Single source of truth for the base URL. The custom domain vocal.best is
// live and Cloudflare-fronted. Override for local dev with:
//   flutter run --dart-define=VOCAL_API_BASE_URL=http://10.0.2.2:8788/api
// (10.0.2.2 is the Android emulator's alias for the host machine.)

import 'dart:convert';

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
  /// <100ms; LLM cache-miss is ~2-8s; USDA fallback ~1-2s).
  static Future<VoiceParseResponse> parseMeal({
    required String transcript,
    String? followUpAnswer,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/voice/parse');
    final res = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(VoiceParsePayload(
            transcript: transcript,
            followUpAnswer: followUpAnswer,
          ).toJson()),
        )
        .timeout(const Duration(seconds: 15));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw VoiceApiException('Bad server response (${res.statusCode})');
    }
    return VoiceParseResponse.fromJson(
        jsonDecode(res.body) as Map<String, dynamic>);
  }
}
