// App-wide state container — Flutter port of AppModel (ObservableObject).
// ChangeNotifier maps almost 1:1 to SwiftUI's ObservableObject; provider's
// ChangeNotifierProvider + context.watch replaces @EnvironmentObject.
//
// HealthKit has no Android equivalent, so the iOS `VoCalHealth` write
// fire-and-forget is intentionally dropped here. On iOS this Flutter build
// could later bridge HealthKit (and Health Connect on Android) via a plugin.

import 'package:flutter/foundation.dart';

import '../models/models.dart';
import '../services/persistence.dart';

class AppModel extends ChangeNotifier {
  DailyTotals totals;
  List<MealEntry> meals;
  UserProfile profile;
  List<BodyMetric> bodyMetrics;
  List<CoachMessage> coachMessages;
  bool hasCompletedOnboarding;
  MealEntry? lastSavedMeal;

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

  void completeOnboarding(UserProfile newProfile, int calorieGoal) {
    profile = newProfile;
    totals.calorieGoal = calorieGoal;
    profile.dailyCalorieGoal = calorieGoal;
    hasCompletedOnboarding = true;
    DailyMacrosSnapshot.writeFrom(totals);
    _persist();
    notifyListeners();
  }
}
