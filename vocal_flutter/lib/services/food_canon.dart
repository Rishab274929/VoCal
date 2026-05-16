// On-device food canon — Flutter port of FoodCanon.swift.
// First-stop lookup before any network call. Loaded once from the bundled
// assets/food_canon.json. Two-pass match (exact alias, then all-tokens
// fuzzy). Transcripts naming a known chain punt to the backend.

import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/models.dart';

class FoodCanonEntry {
  final String name;
  final List<String> aliases;
  final String portion;
  final int kcal;
  final int proteinG;
  final int carbsG;
  final int fatG;
  final String defaultSlot;

  FoodCanonEntry({
    required this.name,
    required this.aliases,
    required this.portion,
    required this.kcal,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.defaultSlot,
  });

  factory FoodCanonEntry.fromJson(Map<String, dynamic> j) => FoodCanonEntry(
        name: j['name'] as String,
        aliases:
            (j['aliases'] as List).map((e) => e.toString()).toList(),
        portion: j['portion'] as String? ?? '',
        kcal: (j['kcal'] as num).toInt(),
        proteinG: (j['protein_g'] as num).toInt(),
        carbsG: (j['carbs_g'] as num).toInt(),
        fatG: (j['fat_g'] as num).toInt(),
        defaultSlot: j['default_slot'] as String? ?? 'snack',
      );

  ParsedMeal asParsedMeal() => ParsedMeal(
        name: name,
        detail: '$portion · cached',
        kcal: kcal,
        proteinG: proteinG,
        carbsG: carbsG,
        fatG: fatG,
        slot: defaultSlot,
        source: 'voice',
        confidence: 0.92,
      );
}

class FoodCanon {
  FoodCanon._();
  static final FoodCanon instance = FoodCanon._();

  List<FoodCanonEntry> _entries = [];
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final raw = await rootBundle.loadString('assets/food_canon.json');
      final j = jsonDecode(raw) as Map<String, dynamic>;
      _entries = (j['entries'] as List)
          .map((e) => FoodCanonEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      _entries = [];
    }
    _loaded = true;
  }

  static const Set<String> _chainHints = {
    'mcdonald', 'starbucks', 'chipotle', 'chick-fil-a', 'chickfila',
    'chick fil a', 'burger king', 'subway', 'taco bell', 'wendy', 'panera',
    'cava', 'sweetgreen', 'domino', 'pizza hut', 'five guys', 'in-n-out',
    'in n out', 'shake shack', 'kfc', 'popeyes', 'panda express',
    'olive garden', 'cheesecake factory', "chili's", 'applebees',
    "applebee's", 'buffalo wild wings', 'outback', 'tgi friday', 'denny',
    'ihop', 'dunkin', 'jamba juice', 'smoothie king', 'jersey mike',
    'jimmy john', 'potbelly', 'qdoba', "moe's", 'moes'
  };

  /// Lowercase, strip punctuation, drop filler, collapse whitespace.
  /// Mirrors vocal-api/src/lib/normalize.ts and FoodCanon.swift.
  static String normalize(String s) {
    const filler = {
      'uh', 'um', 'uhh', 'umm', 'like', 'you', 'know', 'so', 'just',
      'really', 'actually', 'basically', 'i', 'ate', 'had', 'got',
      'have', 'having', 'a', 'an', 'the', 'some', 'of'
    };
    const allowed = "abcdefghijklmnopqrstuvwxyz0123456789 '-";
    final lowered = s.toLowerCase();
    final buf = StringBuffer();
    for (final ch in lowered.split('')) {
      buf.write(allowed.contains(ch) ? ch : ' ');
    }
    return buf
        .toString()
        .split(' ')
        .where((w) => w.isNotEmpty && !filler.contains(w))
        .join(' ');
  }

  /// Best-effort match for a free-text transcript. Returns null on miss.
  FoodCanonEntry? lookup(String transcript) {
    final lowered = transcript.toLowerCase();
    if (_chainHints.any(lowered.contains)) return null;
    final norm = normalize(transcript);
    if (norm.isEmpty) return null;

    FoodCanonEntry? bestEntry;
    int bestLen = -1;

    // Pass 1 — exact alias hit; longest alias wins.
    for (final entry in _entries) {
      for (final alias in entry.aliases) {
        final a = normalize(alias);
        if (a.isEmpty) continue;
        if (norm == a ||
            norm.contains(' $a ') ||
            norm.startsWith('$a ') ||
            norm.endsWith(' $a')) {
          if (a.length > bestLen) {
            bestEntry = entry;
            bestLen = a.length;
          }
        }
      }
    }
    if (bestEntry != null) return bestEntry;

    // Pass 2 — all-tokens-present fuzzy (multi-word aliases only).
    final transcriptTokens = norm.split(' ').toSet();
    for (final entry in _entries) {
      for (final alias in entry.aliases) {
        final aliasTokens =
            normalize(alias).split(' ').where((w) => w.isNotEmpty).toList();
        if (aliasTokens.length < 2) continue;
        if (aliasTokens.every(transcriptTokens.contains)) {
          if (aliasTokens.length > bestLen) {
            bestEntry = entry;
            bestLen = aliasTokens.length;
          }
        }
      }
    }
    return bestEntry;
  }
}
