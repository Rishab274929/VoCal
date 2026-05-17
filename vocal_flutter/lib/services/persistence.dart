// JSON snapshot of the full app state to the app documents directory.
// Saved on every mutation; loaded once at launch. Mirrors Persistence.swift.

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';

class Persistence {
  static const _fileName = 'vocal_state.v1.json';

  static Future<File?> _file() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}/$_fileName');
    } catch (_) {
      return null;
    }
  }

  static Future<void> save(AppStateSnapshot snapshot) async {
    try {
      final f = await _file();
      if (f == null) return;
      // Write to a temp file then rename — atomic via the POSIX rename, so a
      // crash between write and rename leaves the previous good file intact.
      // Mirrors iOS Persistence.save's `.atomic` option.
      final tmp = File('${f.path}.tmp');
      await tmp.writeAsString(snapshot.encode(), flush: true);
      await tmp.rename(f.path);
    } catch (e) {
      // Best-effort: never let a save error break a save flow.
      // ignore: avoid_print
      print('[VoCal.Persistence] save failed: $e');
    }
  }

  static Future<AppStateSnapshot?> load() async {
    try {
      final f = await _file();
      if (f == null) return null;
      if (await f.exists()) {
        final raw = await f.readAsString();
        return AppStateSnapshot.decode(raw);
      }
      // Crash-recovery: a previous save may have been killed between
      // writeAsString and rename, leaving a .tmp orphan. If the main file is
      // missing but a complete tmp exists, prefer that over treating the user
      // as a fresh install (which would zero their day).
      final tmp = File('${f.path}.tmp');
      if (await tmp.exists()) {
        final raw = await tmp.readAsString();
        final decoded = AppStateSnapshot.decode(raw);
        if (decoded != null) {
          // Promote tmp → main so the next save uses the normal path.
          try { await tmp.rename(f.path); } catch (_) {}
          return decoded;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    try {
      final f = await _file();
      if (f != null && await f.exists()) await f.delete();
    } catch (_) {}
  }
}

/// Compact today snapshot mirrored to shared_preferences (UserDefaults
/// equivalent). Read by anything that wants today's macros without spinning
/// up the full UI. Includes the stale-day guard from DailyMacrosSnapshot.
class DailyMacrosSnapshot {
  static const _key = 'vocal.dailyMacrosSnapshot.v1';

  static Future<void> writeFrom(DailyTotals t) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode({
          'date': t.date.toIso8601String(),
          'calorieGoal': t.calorieGoal,
          'caloriesEaten': t.caloriesEaten,
          'proteinGoal': t.proteinGoal,
          'proteinEaten': t.proteinEaten,
          'carbsGoal': t.carbsGoal,
          'carbsEaten': t.carbsEaten,
          'fatGoal': t.fatGoal,
          'fatEaten': t.fatEaten,
        }),
      );
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> read() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return null;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final date = DateTime.tryParse(j['date'] as String? ?? '');
      final now = DateTime.now();
      final isToday = date != null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
      if (!isToday) {
        return {
          'date': now.toIso8601String(),
          'calorieGoal': j['calorieGoal'],
          'caloriesEaten': 0,
          'proteinGoal': j['proteinGoal'],
          'proteinEaten': 0,
          'carbsGoal': j['carbsGoal'],
          'carbsEaten': 0,
          'fatGoal': j['fatGoal'],
          'fatEaten': 0,
        };
      }
      return j;
    } catch (_) {
      return null;
    }
  }
}
