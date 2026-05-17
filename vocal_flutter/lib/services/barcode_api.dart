// Barcode lookup client — Flutter port of BarcodeAPI.swift.
//
// Hits the Cloudflare Worker /api/barcode/<code> route, which already
// chains USDA Branded → Open Food Facts → fallback resolvers on the
// server side. The client just normalizes the code (digits only, 8..14)
// and parses the response shape `{ meal: ParsedMeal, source: string }`.
//
// We don't talk to OFF directly — the User-Agent allow-list relationship
// the iOS BarcodeAPI has with OFF isn't reproducible from the public
// Android client, and the worker handles it for us.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'api_response_hook.dart';
import 'voice_api.dart' show ApiConfig;

class BarcodeApiResult {
  final ParsedMeal meal;
  final String source;
  BarcodeApiResult(this.meal, this.source);
}

/// Distinguished error so callers can render a clean "not in database"
/// state instead of a generic failure message.
class BarcodeApiNotFound implements Exception {
  const BarcodeApiNotFound();
  @override
  String toString() => 'Barcode not in database';
}

class BarcodeApi {
  /// 8s timeout — matches iOS BarcodeAPI URLRequest.timeoutInterval.
  static const Duration _timeout = Duration(seconds: 8);

  /// Pluggable auth so callers don't have to drill the AuthSession
  /// through every layer. Optional — anonymous lookups still work via
  /// the worker's body-fallback identity resolution.
  static Future<String?> Function()? tokenLoader;

  static Future<BarcodeApiResult> lookup(String code) async {
    // Normalize defensively — the backend gates on /^\d{8,14}$/ too,
    // but a local check is cheaper than a round-trip on garbage input.
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 14) {
      throw const BarcodeApiNotFound();
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}/barcode/$digits');
    final headers = <String, String>{};
    try {
      final token = await tokenLoader?.call();
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
    } catch (_) {
      // Auth is best-effort — never block the lookup on a token fetch
      // failure. The worker accepts anonymous requests.
    }
    final http.Response res;
    try {
      res = await http.get(uri, headers: headers).timeout(_timeout);
    } on TimeoutException {
      throw Exception('Request timed out');
    } on SocketException catch (e) {
      throw Exception('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw Exception('HTTP client error: ${e.message}');
    }
    ApiResponseHook.notify(res);
    if (res.statusCode == 404) throw const BarcodeApiNotFound();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Bad server response (${res.statusCode})');
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Malformed server response');
      }
      final mealJson = decoded['meal'];
      if (mealJson is! Map<String, dynamic>) {
        throw const BarcodeApiNotFound();
      }
      final meal = ParsedMeal.fromJson(mealJson);
      final source = (decoded['source'] as String?) ?? 'backend';
      return BarcodeApiResult(meal, source);
    } on FormatException catch (e) {
      throw Exception('Malformed server response: ${e.message}');
    }
  }
}
