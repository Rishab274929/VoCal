// Dart-side bridge that mirrors today's calorie + protein totals into a
// known SharedPreferences key, then nudges the native Android home-screen
// widget to redraw via a HomeWidget update.
//
// iOS parity: matches WidgetBridge.swift's flat snapshot
// `{caloriesEaten, calorieGoal, proteinEaten, proteinGoal}` so the
// widget's decoder logic is one schema across platforms (the native
// AppWidgetProvider reads the same shape — see VocalWidgetProvider.kt).
//
// Why this matters: the Android widget runs in the Launcher process and
// CANNOT call into Flutter. It can only read SharedPreferences. Every
// meal mutation has to write the compact snapshot AND broadcast an
// AppWidgetManager update intent so the launcher repaints.
//
// We deliberately keep the schema flat so the native side doesn't have
// to parse the full app-state JSON (which carries dates, micros, etc.).
//
// Best-effort throughout: a write or broadcast failure is harmless —
// the OS will redraw on its next regular interval anyway.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class WidgetBridge {
  /// Key the native Android widget reads. Flutter's SharedPreferences
  /// plugin namespaces keys with a `flutter.` prefix on Android, so the
  /// AppWidgetProvider reads `flutter.vocal.widget.snapshot.v1`.
  static const String snapshotKey = 'vocal.widget.snapshot.v1';

  /// Channel name MUST match VocalWidgetProvider on the native side. The
  /// Kotlin handler turns method calls into AppWidgetManager broadcasts.
  static const MethodChannel _channel =
      MethodChannel('best.vocal.vocal/widget');

  /// Push today's totals to the widget. Writes the compact snapshot to
  /// SharedPreferences, then asks the platform side to redraw all
  /// VocalWidget instances. Both steps are fire-and-forget.
  static Future<void> publish(DailyTotals totals) async {
    final payload = jsonEncode({
      'caloriesEaten': totals.caloriesEaten,
      'calorieGoal': totals.calorieGoal,
      'proteinEaten': totals.proteinEaten,
      'proteinGoal': totals.proteinGoal,
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(snapshotKey, payload);
    } catch (_) {
      // SharedPreferences should never fail in practice; swallowing here
      // matches the rest of the persistence layer's "never break a save
      // flow on a sidecar write" stance.
    }
    // Notify the widget host. Native side schedules an AppWidgetManager
    // update; if the host process isn't reachable (e.g. iOS), the call
    // silently throws MissingPluginException and we move on.
    try {
      await _channel.invokeMethod<void>('reloadWidget');
    } on PlatformException catch (_) {
      // No widget instances on the home screen — harmless.
    } on MissingPluginException catch (_) {
      // Not running on Android, or native handler not registered yet.
    }
  }

  /// Start the live-activity foreground notification on Android (iOS
  /// Live Activity / Dynamic Island equivalent). Pins an ongoing
  /// notification with today's macros until [stopSession] is called.
  /// Requires POST_NOTIFICATIONS permission on API 33+; the call
  /// silently no-ops if the user has denied notifications.
  static Future<void> startSession() async {
    try {
      await _channel.invokeMethod<void>('startVocalSessionService');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  /// Dismiss the live-activity notification. Safe to call when it
  /// isn't running.
  static Future<void> stopSession() async {
    try {
      await _channel.invokeMethod<void>('stopVocalSessionService');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
  }

  /// Clear the snapshot on sign-out so the widget doesn't show the
  /// previous user's totals until the next mutation. Matches the iOS
  /// AuthSession.signOut() clean-up. Also stops the live-activity
  /// notification so the prior user's totals don't linger in the shade.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(snapshotKey);
    } catch (_) {}
    try {
      await _channel.invokeMethod<void>('reloadWidget');
    } on PlatformException catch (_) {
    } on MissingPluginException catch (_) {}
    await stopSession();
  }
}
