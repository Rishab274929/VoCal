// App-wide state container — Flutter port of AppModel (ObservableObject).
// ChangeNotifier maps almost 1:1 to SwiftUI's ObservableObject; provider's
// ChangeNotifierProvider + context.watch replaces @EnvironmentObject.
//
// HealthKit has no Android equivalent, so the iOS `VoCalHealth` write
// fire-and-forget is intentionally dropped here. On iOS this Flutter build
// could later bridge HealthKit (and Health Connect on Android) via a plugin.

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/auth_session.dart';
import '../services/persistence.dart';

class AppModel extends ChangeNotifier {
  DailyTotals totals;
  List<MealEntry> meals;
  UserProfile profile;
  List<BodyMetric> bodyMetrics;
  List<CoachMessage> coachMessages;
  bool hasCompletedOnboarding;
  MealEntry? lastSavedMeal;

  /// Lazily-injected by main() after bootstrap. Stored here (rather than
  /// pulled from Provider at each call site) so meal-save flows can attach
  /// the bearer to outgoing API calls without every caller having to drill
  /// through `context`. Null in tests and before main() wires it in —
  /// always null-check before touching.
  AuthSession? auth;

  // ---------------------------------------------------------------------------
  // Free-tier voice cap (parity with iOS — 3 voice logs / day on Free).
  //
  // Stored in SharedPreferences (not the on-disk snapshot) so the cap is
  // resilient to a snapshot rewrite/restore — restoring a backup from a
  // different day shouldn't grant a phantom 3 fresh logs. Keys are mirrored
  // exactly from the iOS UserDefaults keys so a future Flutter→native bridge
  // sees the same data.
  static const String _voiceCountKey = 'vocal.dailyVoiceCount.v1';
  static const String _voiceDateKey = 'vocal.dailyVoiceDate.v1';
  static const int freeVoiceCapPerDay = 3;

  int _dailyVoiceCount = 0;
  /// ISO-8601 yyyy-MM-dd (day only) of the day _dailyVoiceCount belongs to.
  /// Empty string means "never logged"; treated as a different day from any
  /// real date so the next check resets the counter (this is desired).
  String _dailyVoiceDate = '';

  /// Idempotency window — the cooldown between accepting two saves of the
  /// same logical meal. Matches iOS AppModel.dedupeWindow.
  static const Duration _dedupeWindow = Duration(seconds: 2);

  /// Wall-clock instant of the last accepted addMeal. Used to detect a
  /// double-tap on Save independent of the meal's loggedAt (which may be
  /// backdated for historical entries). Mirrors iOS lastAddMealAt.
  DateTime? _lastAddMealAt;

  AppModel({
    required this.totals,
    required List<MealEntry> meals,
    required this.profile,
    List<BodyMetric> bodyMetrics = const [],
    List<CoachMessage> coachMessages = const [],
    this.hasCompletedOnboarding = true,
  })  : meals = List.of(meals),
        // Defensive copy so `const []` defaults can't poison the mutable
        // accessor paths (addBodyMetric/appendCoach would throw
        // UnsupportedError on a const list).
        bodyMetrics = List.of(bodyMetrics),
        coachMessages = List.of(coachMessages) {
    DailyMacrosSnapshot.writeFrom(totals);
  }

  factory AppModel.fromSnapshot(AppStateSnapshot s) => AppModel(
        totals: s.totals,
        meals: s.meals,
        profile: s.profile,
        bodyMetrics: s.bodyMetrics,
        coachMessages: s.coachMessages,
        hasCompletedOnboarding: s.hasCompletedOnboarding,
      );

  /// Entry point used by main() at launch.
  ///
  /// Day-rollover guard: if the persisted snapshot was last written on a
  /// prior calendar day, zero the *eaten* macros while preserving the *goals*
  /// + meals history. Without this, opening the app at 12:01 AM would show
  /// yesterday's calorie ring as still "1,180 / 2,200" instead of resetting
  /// to today's "0 / 2,200". Mirrors iOS AppModel.fromPersistedOrEmpty().
  static Future<AppModel> fromPersistedOrEmpty() async {
    final snap = await Persistence.load() ?? AppStateSnapshot.empty();
    final now = DateTime.now();
    final saved = snap.totals.date;
    final isToday = saved.year == now.year &&
        saved.month == now.month &&
        saved.day == now.day;
    if (!isToday) {
      snap.totals.date = now;
      snap.totals.caloriesEaten = 0;
      snap.totals.proteinEaten = 0;
      snap.totals.carbsEaten = 0;
      snap.totals.fatEaten = 0;
    }
    final model = AppModel.fromSnapshot(snap);
    if (!isToday) {
      // Persist the rolled-over totals so the App Intents / shared_preferences
      // mirror see today's zeros rather than yesterday's leftovers.
      model._persist();
    }
    return model;
  }

  /// Reset eaten macros if the day has flipped since the last update.
  /// Call this from a lifecycle hook (e.g. AppLifecycleState.resumed) so a
  /// phone left on overnight rolls over the next time the user opens the app.
  /// Returns true if a rollover happened.
  bool rolloverIfNewDay() {
    final now = DateTime.now();
    final d = totals.date;
    final isToday =
        d.year == now.year && d.month == now.month && d.day == now.day;
    if (isToday) return false;
    totals.date = now;
    totals.caloriesEaten = 0;
    totals.proteinEaten = 0;
    totals.carbsEaten = 0;
    totals.fatEaten = 0;
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
    return true;
  }

  void _persist() {
    final snapshot = AppStateSnapshot(
      version: AppStateSnapshot.currentVersion,
      totals: totals,
      meals: meals,
      profile: profile,
      bodyMetrics: bodyMetrics,
      coachMessages: coachMessages,
      hasCompletedOnboarding: hasCompletedOnboarding,
      savedAt: DateTime.now(),
    );
    // Fire-and-forget; never blocks a user-facing flow.
    Persistence.save(snapshot);
  }

  void addMeal(MealEntry meal) {
    // Idempotency: ignore a save with the same name+kcal that arrived within
    // _dedupeWindow of the previous accepted save. We compare wall-clock-now
    // to _lastAddMealAt (not to meal.loggedAt) because loggedAt may be
    // backdated for historical entries — a user-initiated "I forgot to log
    // this morning's banana" should NOT be silently swallowed even if its
    // name+kcal happen to match the last save.
    //
    // Also scan the top 3 of meals (insertion order, not loggedAt) so a
    // recently-backdated entry at index 0 doesn't let a double-tap slip
    // through on indexes 1/2. Mirrors iOS AppModel.addMeal logic exactly.
    final now = DateTime.now();
    final last = _lastAddMealAt;
    if (last != null && now.difference(last) < _dedupeWindow) {
      final recentSlice = meals.take(3);
      for (final m in recentSlice) {
        if (m.name == meal.name && m.calories == meal.calories) {
          return;
        }
      }
    }
    meals.insert(0, meal);
    totals.caloriesEaten += meal.calories;
    totals.proteinEaten += meal.protein;
    totals.carbsEaten += meal.carbs;
    totals.fatEaten += meal.fat;
    lastSavedMeal = meal;
    _lastAddMealAt = now;
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }

  void removeMeal(MealEntry meal) {
    final idx = meals.indexWhere((m) => m.id == meal.id);
    if (idx < 0) return;
    meals.removeAt(idx);
    int floor0(int v) => v < 0 ? 0 : v;
    totals.caloriesEaten = floor0(totals.caloriesEaten - meal.calories);
    totals.proteinEaten = floor0(totals.proteinEaten - meal.protein);
    totals.carbsEaten = floor0(totals.carbsEaten - meal.carbs);
    totals.fatEaten = floor0(totals.fatEaten - meal.fat);
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }

  /// Replace [original] with [updated] in the meal list and reconcile day
  /// totals by the macro delta. We match by id (not by reference) so a
  /// caller can pass a freshly-constructed updated entry without having to
  /// preserve the original instance handle. If no match is found we no-op
  /// rather than appending — silently turning an "edit" into an "add"
  /// would double-count macros.
  ///
  /// totals.caloriesEaten is floor-clamped at 0 — an edit that *reduces*
  /// macros below zero (e.g. the user fixed a wildly-overestimated parse)
  /// shouldn't leave a negative remainder lingering in the ring.
  void editMeal(MealEntry original, MealEntry updated) {
    final idx = meals.indexWhere((m) => m.id == original.id);
    if (idx < 0) return;
    int floor0(int v) => v < 0 ? 0 : v;
    // Compute deltas off the *previous* in-list values (not the caller-
    // passed `original`) — that's what the totals reflect and using
    // anything else opens a window where two concurrent edits desync.
    final prev = meals[idx];
    totals.caloriesEaten =
        floor0(totals.caloriesEaten - prev.calories + updated.calories);
    totals.proteinEaten =
        floor0(totals.proteinEaten - prev.protein + updated.protein);
    totals.carbsEaten =
        floor0(totals.carbsEaten - prev.carbs + updated.carbs);
    totals.fatEaten = floor0(totals.fatEaten - prev.fat + updated.fat);
    meals[idx] = updated;
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }

  void addBodyMetric(BodyMetric metric) {
    bodyMetrics.insert(0, metric);
    _persist();
    notifyListeners();
  }

  void appendCoach(CoachMessage message) {
    coachMessages.add(message);
    _persist();
    notifyListeners();
  }

  void updateGoal(int kcal) {
    totals.calorieGoal = kcal;
    profile.dailyCalorieGoal = kcal;
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }

  void upgradeToPro() {
    profile.entitlement = Entitlement.pro;
    _persist();
    notifyListeners();
  }

  /// Mutate the profile via a callback. The callback receives the live
  /// profile object and returns nothing — mutations are picked up via
  /// notifyListeners after the callback returns. Persists synchronously
  /// like every other mutator. Keeps the public API tiny (callers don't
  /// need to know which fields to copy vs which to mutate).
  ///
  /// If the daily kcal goal changes, mirror it into `totals.calorieGoal`
  /// so the Today ring reflects the new target immediately rather than
  /// waiting for a next-day rollover.
  void updateProfile(void Function(UserProfile p) mutate) {
    final prevGoal = profile.dailyCalorieGoal;
    mutate(profile);
    if (profile.dailyCalorieGoal != prevGoal) {
      totals.calorieGoal = profile.dailyCalorieGoal;
    }
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }

  void completeOnboarding(UserProfile newProfile, int calorieGoal) {
    profile = newProfile;
    totals.calorieGoal = calorieGoal;
    profile.dailyCalorieGoal = calorieGoal;
    hasCompletedOnboarding = true;
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Free-tier voice cap
  //
  // The counter and date live in SharedPreferences (not the JSON snapshot)
  // so a snapshot restore can't reset a user's daily cap mid-day. We hydrate
  // lazily on first read — that's cheap and avoids forcing every caller of
  // AppModel.fromPersistedOrEmpty() to await an extra round-trip on launch.

  static String _todayKey() {
    // yyyy-MM-dd in local time. We deliberately use local time (not UTC) so
    // "a day" matches the user's calendar; a New York user shouldn't get
    // their cap reset at 8 PM because UTC midnight ticked over.
    final n = DateTime.now();
    final m = n.month.toString().padLeft(2, '0');
    final d = n.day.toString().padLeft(2, '0');
    return '${n.year}-$m-$d';
  }

  bool _capHydrated = false;
  Future<void> _hydrateVoiceCapIfNeeded() async {
    if (_capHydrated) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _dailyVoiceCount = prefs.getInt(_voiceCountKey) ?? 0;
      _dailyVoiceDate = prefs.getString(_voiceDateKey) ?? '';
    } catch (_) {
      // Best-effort — if SharedPreferences is unavailable (very rare),
      // treat as fresh day with zero usage. Worst case: user gets a few
      // extra logs for this session.
      _dailyVoiceCount = 0;
      _dailyVoiceDate = '';
    }
    _capHydrated = true;
  }

  /// Synchronous in-memory rollover — call after `_hydrateVoiceCapIfNeeded()`
  /// has run at least once (canLogVoice / recordVoiceLog both await it).
  void _rolloverVoiceCounterIfNeeded() {
    final today = _todayKey();
    if (_dailyVoiceDate != today) {
      _dailyVoiceCount = 0;
      _dailyVoiceDate = today;
    }
  }

  /// True when the user is allowed to start a voice-log flow. Pro users
  /// are always allowed. Free users get `freeVoiceCapPerDay` logs per
  /// local calendar day; this method handles the day rollover internally
  /// so callers don't need to invoke `rolloverIfNewDay()` first.
  ///
  /// Awaiting this at the point-of-action keeps the cap honest even if
  /// the app sat in the background overnight and never got a foreground
  /// lifecycle callback.
  Future<bool> canLogVoice() async {
    if (profile.entitlement == Entitlement.pro) return true;
    await _hydrateVoiceCapIfNeeded();
    _rolloverVoiceCounterIfNeeded();
    return _dailyVoiceCount < freeVoiceCapPerDay;
  }

  /// Cached in-memory count — only meaningful after canLogVoice has been
  /// awaited at least once this session. Useful for surfacing "2 of 3 used
  /// today" badges without re-awaiting.
  int get dailyVoiceCountCached => _dailyVoiceCount;

  /// Bump the counter after a successful voice meal save. Persists to
  /// SharedPreferences so the cap survives an app kill. Does NOT call
  /// `notifyListeners()` because the meal save that triggered this already
  /// did, and an extra notify would re-render the whole tree for nothing.
  Future<void> recordVoiceLog() async {
    if (profile.entitlement == Entitlement.pro) return;
    await _hydrateVoiceCapIfNeeded();
    _rolloverVoiceCounterIfNeeded();
    _dailyVoiceCount += 1;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_voiceCountKey, _dailyVoiceCount);
      await prefs.setString(_voiceDateKey, _dailyVoiceDate);
    } catch (_) {
      // In-memory state is still bumped, so the user is gated for the rest
      // of this session even if the persistence write failed.
    }
  }
}
