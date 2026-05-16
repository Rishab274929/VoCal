// Domain models — Flutter port of Item.swift + Persistence.swift snapshot.
// Plain Dart classes with explicit JSON (ISO8601 dates) so the on-disk
// snapshot is diff-friendly and matches the Swift schema conceptually.

import 'dart:convert';

// MARK: - Meals

enum MealSource {
  voice('voice'),
  photo('photo'),
  manual('manual'),
  voicePhoto('voice+photo'),
  barcode('barcode');

  final String raw;
  const MealSource(this.raw);

  static MealSource fromRaw(String? v) =>
      MealSource.values.firstWhere((e) => e.raw == v, orElse: () => MealSource.voice);
}

enum MealSlot {
  breakfast('breakfast'),
  lunch('lunch'),
  dinner('dinner'),
  snack('snack');

  final String raw;
  const MealSlot(this.raw);

  static MealSlot fromRaw(String? v) =>
      MealSlot.values.firstWhere((e) => e.raw == v, orElse: () => MealSlot.snack);
}

class MealEntry {
  final String id;
  String name;
  String detail;
  int calories;
  int protein; // grams
  int carbs; // grams
  int fat; // grams
  DateTime loggedAt;
  MealSlot slot;
  MealSource source;

  MealEntry({
    String? id,
    required this.name,
    required this.detail,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.loggedAt,
    required this.slot,
    required this.source,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString() +
            '-${name.hashCode}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'detail': detail,
        'calories': calories,
        'protein': protein,
        'carbs': carbs,
        'fat': fat,
        'loggedAt': loggedAt.toIso8601String(),
        'slot': slot.raw,
        'source': source.raw,
      };

  factory MealEntry.fromJson(Map<String, dynamic> j) => MealEntry(
        id: j['id'] as String?,
        name: j['name'] as String,
        detail: j['detail'] as String? ?? '',
        calories: (j['calories'] as num).toInt(),
        protein: (j['protein'] as num).toInt(),
        carbs: (j['carbs'] as num).toInt(),
        fat: (j['fat'] as num).toInt(),
        loggedAt: DateTime.parse(j['loggedAt'] as String),
        slot: MealSlot.fromRaw(j['slot'] as String?),
        source: MealSource.fromRaw(j['source'] as String?),
      );
}

// MARK: - Daily totals

class DailyTotals {
  DateTime date;
  int calorieGoal;
  int caloriesEaten;
  int proteinGoal;
  int proteinEaten;
  int carbsGoal;
  int carbsEaten;
  int fatGoal;
  int fatEaten;

  DailyTotals({
    required this.date,
    required this.calorieGoal,
    required this.caloriesEaten,
    required this.proteinGoal,
    required this.proteinEaten,
    required this.carbsGoal,
    required this.carbsEaten,
    required this.fatGoal,
    required this.fatEaten,
  });

  int get calorieRemaining =>
      (calorieGoal - caloriesEaten) < 0 ? 0 : calorieGoal - caloriesEaten;
  double get calorieProgress =>
      (caloriesEaten / (calorieGoal <= 0 ? 1 : calorieGoal)).clamp(0, 1);

  Map<String, dynamic> toJson() => {
        'date': date.toIso8601String(),
        'calorieGoal': calorieGoal,
        'caloriesEaten': caloriesEaten,
        'proteinGoal': proteinGoal,
        'proteinEaten': proteinEaten,
        'carbsGoal': carbsGoal,
        'carbsEaten': carbsEaten,
        'fatGoal': fatGoal,
        'fatEaten': fatEaten,
      };

  factory DailyTotals.fromJson(Map<String, dynamic> j) => DailyTotals(
        date: DateTime.parse(j['date'] as String),
        calorieGoal: (j['calorieGoal'] as num).toInt(),
        caloriesEaten: (j['caloriesEaten'] as num).toInt(),
        proteinGoal: (j['proteinGoal'] as num).toInt(),
        proteinEaten: (j['proteinEaten'] as num).toInt(),
        carbsGoal: (j['carbsGoal'] as num).toInt(),
        carbsEaten: (j['carbsEaten'] as num).toInt(),
        fatGoal: (j['fatGoal'] as num).toInt(),
        fatEaten: (j['fatEaten'] as num).toInt(),
      );
}

// MARK: - User

enum Entitlement { free, pro }

class UserProfile {
  String displayName;
  int streakDays;
  double weightLbs;
  double heightInches;
  int dailyCalorieGoal;
  String sex; // "m", "f", or "" (unspecified)
  int birthYear;
  Entitlement entitlement;

  UserProfile({
    required this.displayName,
    required this.streakDays,
    required this.weightLbs,
    required this.heightInches,
    required this.dailyCalorieGoal,
    this.sex = '',
    this.birthYear = 1995,
    this.entitlement = Entitlement.free,
  });

  UserProfile copy() => UserProfile(
        displayName: displayName,
        streakDays: streakDays,
        weightLbs: weightLbs,
        heightInches: heightInches,
        dailyCalorieGoal: dailyCalorieGoal,
        sex: sex,
        birthYear: birthYear,
        entitlement: entitlement,
      );

  Map<String, dynamic> toJson() => {
        'displayName': displayName,
        'streakDays': streakDays,
        'weightLbs': weightLbs,
        'heightInches': heightInches,
        'dailyCalorieGoal': dailyCalorieGoal,
        'sex': sex,
        'birthYear': birthYear,
        'entitlement': entitlement.name,
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        displayName: j['displayName'] as String? ?? '',
        streakDays: (j['streakDays'] as num?)?.toInt() ?? 0,
        weightLbs: (j['weightLbs'] as num?)?.toDouble() ?? 0,
        heightInches: (j['heightInches'] as num?)?.toDouble() ?? 0,
        dailyCalorieGoal: (j['dailyCalorieGoal'] as num?)?.toInt() ?? 2000,
        sex: j['sex'] as String? ?? '',
        birthYear: (j['birthYear'] as num?)?.toInt() ?? 1995,
        entitlement: (j['entitlement'] as String?) == 'pro'
            ? Entitlement.pro
            : Entitlement.free,
      );
}

// MARK: - Body metrics

class BodyMetric {
  final String id;
  double weightLbs;
  double? bodyFatPct;
  double? confidence;
  DateTime measuredAt;

  BodyMetric({
    String? id,
    required this.weightLbs,
    this.bodyFatPct,
    this.confidence,
    required this.measuredAt,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();

  Map<String, dynamic> toJson() => {
        'id': id,
        'weightLbs': weightLbs,
        'bodyFatPct': bodyFatPct,
        'confidence': confidence,
        'measuredAt': measuredAt.toIso8601String(),
      };

  factory BodyMetric.fromJson(Map<String, dynamic> j) => BodyMetric(
        id: j['id'] as String?,
        weightLbs: (j['weightLbs'] as num).toDouble(),
        bodyFatPct: (j['bodyFatPct'] as num?)?.toDouble(),
        confidence: (j['confidence'] as num?)?.toDouble(),
        measuredAt: DateTime.parse(j['measuredAt'] as String),
      );
}

// MARK: - Coach

enum CoachRole { user, assistant }

class CoachMessage {
  final String id;
  CoachRole role;
  String content;
  DateTime createdAt;

  CoachMessage({
    String? id,
    required this.role,
    required this.content,
    DateTime? createdAt,
  })  : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
        createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
      };

  factory CoachMessage.fromJson(Map<String, dynamic> j) => CoachMessage(
        id: j['id'] as String?,
        role: (j['role'] as String?) == 'user'
            ? CoachRole.user
            : CoachRole.assistant,
        content: j['content'] as String,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );
}

// MARK: - API payloads / responses

class VoiceParsePayload {
  final String transcript;
  final String? followUpAnswer;
  VoiceParsePayload({required this.transcript, this.followUpAnswer});

  Map<String, dynamic> toJson() => {
        'transcript': transcript,
        'follow_up_answer': followUpAnswer,
      };
}

class ParsedMeal {
  String name;
  String detail;
  int kcal;
  int proteinG;
  int carbsG;
  int fatG;
  String slot;
  String source;
  double confidence;

  ParsedMeal({
    required this.name,
    required this.detail,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.slot,
    required this.source,
    required this.confidence,
  });

  ParsedMeal copy() => ParsedMeal(
        name: name,
        detail: detail,
        kcal: kcal,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        slot: slot,
        source: source,
        confidence: confidence,
      );

  factory ParsedMeal.fromJson(Map<String, dynamic> j) => ParsedMeal(
        name: j['name'] as String? ?? 'Meal',
        detail: j['detail'] as String? ?? '',
        kcal: (j['kcal'] as num?)?.toInt() ?? 0,
        proteinG: (j['protein_g'] as num?)?.toInt() ?? 0,
        carbsG: (j['carbs_g'] as num?)?.toInt() ?? 0,
        fatG: (j['fat_g'] as num?)?.toInt() ?? 0,
        slot: j['slot'] as String? ?? 'snack',
        source: j['source'] as String? ?? 'voice',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0.5,
      );
}

class VoiceParseResponse {
  String transcript;
  String? followUpQuestion;
  ParsedMeal? meal;
  String reasoning;

  VoiceParseResponse({
    required this.transcript,
    this.followUpQuestion,
    this.meal,
    required this.reasoning,
  });

  factory VoiceParseResponse.fromJson(Map<String, dynamic> j) =>
      VoiceParseResponse(
        transcript: j['transcript'] as String? ?? '',
        followUpQuestion: j['follow_up_question'] as String?,
        meal: j['meal'] == null
            ? null
            : ParsedMeal.fromJson(j['meal'] as Map<String, dynamic>),
        reasoning: j['reasoning'] as String? ?? '',
      );
}

// MARK: - App state snapshot (persisted to Documents)

class AppStateSnapshot {
  int version;
  DailyTotals totals;
  List<MealEntry> meals;
  UserProfile profile;
  List<BodyMetric> bodyMetrics;
  List<CoachMessage> coachMessages;
  bool hasCompletedOnboarding;
  DateTime savedAt;

  static const int currentVersion = 1;

  AppStateSnapshot({
    required this.version,
    required this.totals,
    required this.meals,
    required this.profile,
    required this.bodyMetrics,
    required this.coachMessages,
    required this.hasCompletedOnboarding,
    required this.savedAt,
  });

  String encode() => jsonEncode({
        'version': version,
        'totals': totals.toJson(),
        'meals': meals.map((m) => m.toJson()).toList(),
        'profile': profile.toJson(),
        'bodyMetrics': bodyMetrics.map((b) => b.toJson()).toList(),
        'coachMessages': coachMessages.map((c) => c.toJson()).toList(),
        'hasCompletedOnboarding': hasCompletedOnboarding,
        'savedAt': savedAt.toIso8601String(),
      });

  static AppStateSnapshot? decode(String raw) {
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final snap = AppStateSnapshot(
        version: (j['version'] as num).toInt(),
        totals: DailyTotals.fromJson(j['totals'] as Map<String, dynamic>),
        meals: (j['meals'] as List)
            .map((e) => MealEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        profile: UserProfile.fromJson(j['profile'] as Map<String, dynamic>),
        bodyMetrics: (j['bodyMetrics'] as List)
            .map((e) => BodyMetric.fromJson(e as Map<String, dynamic>))
            .toList(),
        coachMessages: (j['coachMessages'] as List)
            .map((e) => CoachMessage.fromJson(e as Map<String, dynamic>))
            .toList(),
        hasCompletedOnboarding: j['hasCompletedOnboarding'] as bool? ?? false,
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
      if (snap.version != currentVersion) return null;
      return snap;
    } catch (_) {
      return null;
    }
  }

  /// Empty state for a brand-new user.
  factory AppStateSnapshot.empty() => AppStateSnapshot(
        version: currentVersion,
        totals: DailyTotals(
          date: DateTime.now(),
          calorieGoal: 2000,
          caloriesEaten: 0,
          proteinGoal: 140,
          proteinEaten: 0,
          carbsGoal: 220,
          carbsEaten: 0,
          fatGoal: 65,
          fatEaten: 0,
        ),
        meals: [],
        profile: UserProfile(
          displayName: '',
          streakDays: 0,
          weightLbs: 0,
          heightInches: 0,
          dailyCalorieGoal: 2000,
          sex: '',
          birthYear: 1995,
          entitlement: Entitlement.free,
        ),
        bodyMetrics: [],
        coachMessages: [],
        hasCompletedOnboarding: false,
        savedAt: DateTime.now(),
      );
}
