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

  AppModel({
    required this.totals,
    required this.meals,
    required this.profile,
    this.bodyMetrics = const [],
    this.coachMessages = const [],
    this.hasCompletedOnboarding = true,
  }) {
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
  static Future<AppModel> fromPersistedOrEmpty() async {
    final snap = await Persistence.load() ?? AppStateSnapshot.empty();
    return AppModel.fromSnapshot(snap);
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
    // Idempotency: ignore a save with the same name+kcal within 2s of the
    // last save. Prevents double-taps on Save from logging twice.
    if (meals.isNotEmpty) {
      final recent = meals.first;
      if (recent.name == meal.name &&
          recent.calories == meal.calories &&
          recent.loggedAt.difference(meal.loggedAt).inMilliseconds.abs() <
              2000) {
        return;
      }
    }
    meals.insert(0, meal);
    totals.caloriesEaten += meal.calories;
    totals.proteinEaten += meal.protein;
    totals.carbsEaten += meal.carbs;
    totals.fatEaten += meal.fat;
    lastSavedMeal = meal;
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
