// Offline fallback chain-restaurant matcher — Flutter port of
// OfflineFallback.swift. Used when on-device FoodCanon misses AND the
// backend round-trip fails. Keeps the three killer phrases working with
// zero network.

import '../models/models.dart';

sealed class OfflineFallbackResult {}

class OfflineMeal extends OfflineFallbackResult {
  final VoiceParseResponse response;
  OfflineMeal(this.response);
}

class OfflineFollowUp extends OfflineFallbackResult {
  final String question;
  final String reasoning;
  OfflineFollowUp(this.question, this.reasoning);
}

class OfflineMiss extends OfflineFallbackResult {}

class OfflineFallback {
  static OfflineFallbackResult resolve(String transcript,
      {String? followUpAnswer}) {
    final text = transcript.toLowerCase();
    final answer = (followUpAnswer ?? '').toLowerCase();

    // McDonald's fries
    if (text.contains('mcdonald') && text.contains('fry')) {
      return OfflineMeal(VoiceParseResponse(
        transcript: transcript,
        followUpQuestion: null,
        meal: ParsedMeal(
          name: "McDonald's French Fries (Medium)",
          detail: 'Chain menu match · offline',
          kcal: 320,
          proteinG: 4,
          carbsG: 43,
          fatG: 15,
          slot: 'snack',
          source: 'voice',
          confidence: 0.97,
        ),
        reasoning: "Offline McDonald's match.",
      ));
    }

    // Starbucks oat latte
    if (text.contains('starbucks') && text.contains('latte')) {
      return OfflineMeal(VoiceParseResponse(
        transcript: transcript,
        followUpQuestion: null,
        meal: ParsedMeal(
          name: 'Starbucks Iced Oatmilk Latte (Grande)',
          detail: 'Oatmilk · offline',
          kcal: 190,
          proteinG: 3,
          carbsG: 24,
          fatG: 8,
          slot: 'breakfast',
          source: 'voice',
          confidence: 0.95,
        ),
        reasoning: 'Offline Starbucks match.',
      ));
    }

    // Chipotle bowl — supports the guac-portion follow-up
    if (text.contains('chipotle') && text.contains('bowl')) {
      final guacAnswered = answer.contains('single') ||
          answer.contains('double') ||
          answer.contains('two');
      if (text.contains('guac') && !guacAnswered) {
        return OfflineFollowUp(
          'Single scoop of guac?',
          'Need guac portion to finalize macros.',
        );
      }
      final doubleChicken =
          text.contains('double') && text.contains('chicken');
      final chickenCals = doubleChicken ? 360 : 180;
      final chickenProtein = doubleChicken ? 64 : 32;
      final chickenFat = doubleChicken ? 14 : 7;
      final guacDouble = answer.contains('double') || answer.contains('two');
      final wantsGuac = text.contains('guac');
      final guacCals = wantsGuac ? (guacDouble ? 460 : 230) : 0;
      final guacFat = wantsGuac ? (guacDouble ? 44 : 22) : 0;
      final guacCarbs = wantsGuac ? (guacDouble ? 16 : 8) : 0;
      final kcal = 210 + 130 + chickenCals + guacCals;
      final detail =
          '${doubleChicken ? "double" : "single"} chicken, brown rice, black beans'
          '${wantsGuac ? ", ${guacDouble ? "2× guac" : "1× guac"}" : ""}'
          ' · offline';
      return OfflineMeal(VoiceParseResponse(
        transcript: transcript,
        followUpQuestion: null,
        meal: ParsedMeal(
          name: 'Chipotle Chicken Bowl',
          detail: detail,
          kcal: kcal,
          proteinG: chickenProtein + 9,
          carbsG: 45 + 22 + guacCarbs,
          fatG: chickenFat + 2 + guacFat,
          slot: 'lunch',
          source: 'voice',
          confidence: 0.92,
        ),
        reasoning: 'Offline Chipotle template.',
      ));
    }

    return OfflineMiss();
  }

  /// Generic last-resort estimate — flagged low confidence.
  static VoiceParseResponse genericEstimate(String transcript) {
    return VoiceParseResponse(
      transcript: transcript,
      followUpQuestion: null,
      meal: ParsedMeal(
        name: 'Meal from voice',
        detail: 'Estimated fallback · offline',
        kcal: 450,
        proteinG: 20,
        carbsG: 45,
        fatG: 20,
        slot: 'snack',
        source: 'voice',
        confidence: 0.4,
      ),
      reasoning: 'Offline fallback estimate — no matcher confident enough.',
    );
  }
}
