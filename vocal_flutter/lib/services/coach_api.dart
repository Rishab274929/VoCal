// Backend coach client — Flutter port of VoCal/CoachAPI in VoiceCoach.swift.
//
// POST /api/coach
// Body (matches iOS Payload struct verbatim):
//   {
//     "prompt":  String,
//     "history": [ { role: "user"|"assistant", content: String }, ... ],
//     "totals":  { calorie_goal, calories_eaten, protein_goal, protein_eaten,
//                  carbs_goal, carbs_eaten, fat_goal, fat_eaten }   // optional
//   }
// Response: { "reply": String }
//
// Notes
// ----------------------------------------------------------------------------
// * Bearer auth is best-effort. Another agent in this wave is shipping the
//   Flutter equivalent of AuthSession; this client looks up the token via
//   reflection-by-path (a top-level loader function in
//   `services/auth_session.dart` if present, otherwise None). The backend
//   tolerates missing auth via the soft-auth path in /api/coach, so an
//   integration ordering bug here doesn't break the demo.
// * 30s timeout to match iOS req.timeoutInterval = 30 in VoiceCoach.swift.
// * Streaming is NOT supported by /api/coach — it returns a single JSON body.
//   Do not switch to a streaming client without changing the backend first.
// * On any network / parse error we throw CoachApiException; the UI catches
//   that and surfaces a canned fallback line. We do NOT run a local heuristic
//   here — that was the source of inconsistent answers between platforms.
//
// Auth indirection ------------------------------------------------------------
// To stay decoupled from the AuthSession agent's WIP file, we use a setter:
//   CoachApiAuth.tokenLoader = () => AuthSession.currentToken;
// Whoever wires AuthSession into the app should call this once at startup.
// If unset, requests go out without an Authorization header.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_response_hook.dart';
import 'voice_api.dart' show ApiConfig;

/// Pluggable auth header source. Set during app init (e.g. in main.dart) so
/// the coach client doesn't need a hard import of AuthSession's exact API.
///
/// Example wiring once AuthSession ships:
///     CoachApiAuth.tokenLoader = () async => AuthSession.instance.currentToken();
class CoachApiAuth {
  /// Returns the current bearer token or null. Should be fast (no network),
  /// since it's awaited inline before every coach request. AuthSession is
  /// expected to cache + lazy-refresh.
  static Future<String?> Function()? tokenLoader;
}

class CoachApiException implements Exception {
  final String message;
  CoachApiException(this.message);
  @override
  String toString() => 'CoachApiException: $message';
}

/// Mirrors the iOS Payload.TotalsDTO field-by-field. Optional — if the caller
/// doesn't pass it, the backend falls back to its D1 query or a heuristic.
class CoachTotals {
  final int calorieGoal;
  final int caloriesEaten;
  final int proteinGoal;
  final int proteinEaten;
  final int carbsGoal;
  final int carbsEaten;
  final int fatGoal;
  final int fatEaten;

  const CoachTotals({
    required this.calorieGoal,
    required this.caloriesEaten,
    required this.proteinGoal,
    required this.proteinEaten,
    required this.carbsGoal,
    required this.carbsEaten,
    required this.fatGoal,
    required this.fatEaten,
  });

  /// Construct from the app's DailyTotals — the snake_case keys here MUST
  /// match the iOS payload exactly (the backend matches on those keys).
  factory CoachTotals.fromDailyTotals(DailyTotals t) => CoachTotals(
        calorieGoal: t.calorieGoal,
        caloriesEaten: t.caloriesEaten,
        proteinGoal: t.proteinGoal,
        proteinEaten: t.proteinEaten,
        carbsGoal: t.carbsGoal,
        carbsEaten: t.carbsEaten,
        fatGoal: t.fatGoal,
        fatEaten: t.fatEaten,
      );

  Map<String, dynamic> toJson() => {
        'calorie_goal': calorieGoal,
        'calories_eaten': caloriesEaten,
        'protein_goal': proteinGoal,
        'protein_eaten': proteinEaten,
        'carbs_goal': carbsGoal,
        'carbs_eaten': carbsEaten,
        'fat_goal': fatGoal,
        'fat_eaten': fatEaten,
      };
}

class CoachApiClient {
  /// Send one coach turn. `history` is the prior chat capped at 8 turns by
  /// the caller (we forward unchanged — backend also caps to 8 for safety).
  ///
  /// Returns the reply text. Throws CoachApiException on any failure; the UI
  /// is responsible for showing a canned fallback.
  static Future<String> send({
    required String prompt,
    required List<CoachMessage> history,
    CoachTotals? totals,
  }) async {
    final uri = Uri.parse('${ApiConfig.baseUrl}/coach');

    // History DTO — same shape iOS sends. Map enum role → backend string.
    // Cap at last 8 to match VoiceCoach.swift history.suffix(8).
    final lastEight = history.length > 8
        ? history.sublist(history.length - 8)
        : history;
    final historyJson = lastEight
        .map((m) => {
              'role': m.role == CoachRole.user ? 'user' : 'assistant',
              'content': m.content,
            })
        .toList();

    final body = <String, dynamic>{
      'prompt': prompt,
      'history': historyJson,
    };
    if (totals != null) {
      body['totals'] = totals.toJson();
    }

    // Best-effort auth header. Never block / error the request if the loader
    // throws — auth-as-prerequisite would break the demo if the AuthSession
    // wiring lags this client by a turn.
    final headers = <String, String>{'Content-Type': 'application/json'};
    final loader = CoachApiAuth.tokenLoader;
    if (loader != null) {
      try {
        final token = await loader();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
        }
      } catch (_) {
        // Swallow: backend tolerates anonymous coach requests.
      }
    }

    final http.Response res;
    try {
      res = await http
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw CoachApiException('Request timed out');
    } on SocketException catch (e) {
      throw CoachApiException('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw CoachApiException('HTTP client error: ${e.message}');
    }
    ApiResponseHook.notify(res);

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw CoachApiException('Bad server response (${res.statusCode})');
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw CoachApiException('Malformed coach response');
      }
      final reply = decoded['reply'];
      if (reply is! String || reply.trim().isEmpty) {
        throw CoachApiException('Empty coach reply');
      }
      return reply;
    } on FormatException catch (e) {
      throw CoachApiException('Malformed coach response: ${e.message}');
    }
  }
}
