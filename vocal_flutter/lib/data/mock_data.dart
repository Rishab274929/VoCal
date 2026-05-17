// Demo seed + sample data — Flutter port of MockData.swift.
// `voicePrompts` and the history/weight/bodyfat series are referenced at
// runtime (voice sheet, progress screen), so this ships in the app.

import '../models/models.dart';

class MockData {
  static UserProfile get profile => UserProfile(
        displayName: 'Eric',
        streakDays: 12,
        weightLbs: 168,
        heightInches: 70,
        dailyCalorieGoal: 2200,
        sex: 'm',
        birthYear: 1995,
        entitlement: Entitlement.free,
      );

  static DailyTotals get today => DailyTotals(
        date: DateTime.now(),
        calorieGoal: 2200,
        caloriesEaten: 1180,
        proteinGoal: 160,
        proteinEaten: 84,
        carbsGoal: 240,
        carbsEaten: 138,
        fatGoal: 70,
        fatEaten: 41,
      );

  static List<MealEntry> get recentMeals {
    DateTime at(int h, int m) {
      final n = DateTime.now();
      return DateTime(n.year, n.month, n.day, h, m);
    }

    return [
      MealEntry(
        name: 'Chipotle Chicken Bowl',
        detail: 'Double chicken, brown rice, black beans, 1× guac',
        calories: 1080,
        protein: 74,
        carbs: 78,
        fat: 42,
        loggedAt: at(13, 6),
        slot: MealSlot.lunch,
        source: MealSource.voice,
      ),
      MealEntry(
        name: 'Starbucks Iced Oatmilk Latte',
        detail: 'Grande, oatmilk, no syrup',
        calories: 190,
        protein: 3,
        carbs: 24,
        fat: 8,
        loggedAt: at(10, 22),
        slot: MealSlot.breakfast,
        source: MealSource.voice,
      ),
      MealEntry(
        name: 'Greek yogurt + berries',
        detail: 'Fage 2%, blueberries, honey, walnuts',
        calories: 320,
        protein: 22,
        carbs: 34,
        fat: 11,
        loggedAt: at(8, 12),
        slot: MealSlot.breakfast,
        source: MealSource.voice,
      ),
    ];
  }

  static List<(DateTime date, int calories, int goal)> get historySummaries {
    const sample = [
      2080, 1890, 2210, 1750, 2340, 2020, 1660,
      2150, 1980, 2280, 1820, 2090, 1940, 2050
    ];
    final now = DateTime.now();
    return List.generate(sample.length, (i) {
      final day = now.subtract(Duration(days: i + 1));
      return (day, sample[i], 2200);
    });
  }

  static const List<String> voicePrompts = [
    "log a medium fry from McDonald's",
    'grande iced oat latte from Starbucks',
    'Chipotle bowl, double chicken, brown rice, black beans, guac',
    'two scrambled eggs and a piece of toast',
    'a big bowl of pasta with red sauce',
  ];

  static const List<double> weightSeries = [
    171.4, 171.0, 170.6, 170.2, 169.9, 169.6, 169.2,
    168.9, 168.7, 168.5, 168.2, 168.0
  ];

  static const List<double> bodyFatSeries = [
    18.4, 18.2, 18.1, 17.9, 17.7, 17.6, 17.4, 17.2, 17.0
  ];

  static List<BodyMetric> get bodyMetrics {
    final now = DateTime.now();
    final n = weightSeries.length;
    return List.generate(n, (idx) {
      final w = weightSeries[n - 1 - idx];
      final bfIdx = bodyFatSeries.length - 1 - (n - 1 - idx);
      final bf = (bfIdx >= 0 && bfIdx < bodyFatSeries.length)
          ? bodyFatSeries[bfIdx]
          : null;
      final date = now.subtract(Duration(days: (n - 1 - idx) * 3));
      return BodyMetric(
          weightLbs: w, bodyFatPct: bf, confidence: 0.82, measuredAt: date);
    }).reversed.toList();
  }

  static List<CoachMessage> get coachIntro => [
        CoachMessage(
          role: CoachRole.assistant,
          content:
              "Morning. You're 1,020 kcal under and 76g of protein short. Want a high-protein lunch idea from a chain you usually order from?",
        ),
      ];
}
