// Saved-foods quick-re-log — Flutter port of SavedFoodsSheet.swift.
//
// Pulls the most-recently-logged unique meals out of AppModel.meals
// (dedup by lowercased name, capped at 40) so re-logging a regular
// breakfast or yesterday's leftover pasta is a single tap.
//
// Clones the meal with a fresh id + current loggedAt and forces
// `source: manual` so the daily voice-cap doesn't count a "I tapped a
// saved food" as voice usage.
//
// When a real saved-foods schema lands, this sheet swaps its data
// source without changing the call site.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showSavedFoodsSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.92,
      child: SavedFoodsSheet(),
    ),
  );
}

class SavedFoodsSheet extends StatefulWidget {
  const SavedFoodsSheet({super.key});

  @override
  State<SavedFoodsSheet> createState() => _SavedFoodsSheetState();
}

class _SavedFoodsSheetState extends State<SavedFoodsSheet> {
  final TextEditingController _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// Dedup by lowercased + trimmed name, preserve recency (insertion
  /// order from AppModel.meals is already most-recent-first), cap at 40
  /// — same window as iOS so the surface stays "recent regulars," not a
  /// scroll-forever history.
  List<MealEntry> _uniqueRecent(List<MealEntry> meals) {
    final seen = <String>{};
    final out = <MealEntry>[];
    for (final m in meals) {
      final key = m.name.toLowerCase().trim();
      if (key.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      out.add(m);
      if (out.length >= 40) break;
    }
    return out;
  }

  List<MealEntry> _filtered(List<MealEntry> recent) {
    final q = _query.text.trim().toLowerCase();
    if (q.isEmpty) return recent;
    return recent
        .where((m) =>
            m.name.toLowerCase().contains(q) ||
            m.detail.toLowerCase().contains(q))
        .toList();
  }

  void _reLog(MealEntry meal) {
    final fresh = MealEntry(
      name: meal.name,
      detail: meal.detail,
      calories: meal.calories,
      protein: meal.protein,
      carbs: meal.carbs,
      fat: meal.fat,
      loggedAt: DateTime.now(),
      slot: meal.slot,
      source: MealSource.manual,
      sodiumMg: meal.sodiumMg,
      fiberG: meal.fiberG,
      sugarG: meal.sugarG,
      calciumMg: meal.calciumMg,
      ironMg: meal.ironMg,
      vitaminCMg: meal.vitaminCMg,
      potassiumMg: meal.potassiumMg,
    );
    context.read<AppModel>().addMeal(fresh);
    HapticFeedback.mediumImpact();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppModel>();
    final recent = _uniqueRecent(app.meals);
    final list = _filtered(recent);
    return Container(
      color: Palette.ink,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 16),
              _searchField(),
              const SizedBox(height: 16),
              Expanded(
                child: list.isEmpty ? _emptyState() : _list(list),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('SAVED FOODS', color: Palette.pulse),
              const SizedBox(height: 6),
              Text(
                'Your recent regulars.',
                style: AppType.serif(28, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Palette.hairlineStrong),
            ),
            child: const Icon(Icons.close, size: 13, color: Palette.ash),
          ),
        ),
      ],
    );
  }

  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.inkSurface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 14, color: Palette.smoke),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              style: AppType.body(14, color: Palette.bone),
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: 'Search saved meals',
                hintStyle: AppType.body(14, color: Palette.smoke),
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_query.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                _query.clear();
                setState(() {});
              },
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.cancel, size: 16, color: Palette.smoke),
              ),
            ),
        ],
      ),
    );
  }

  Widget _list(List<MealEntry> meals) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      physics: const ClampingScrollPhysics(),
      itemCount: meals.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _savedRow(meals[i]),
    );
  }

  Widget _savedRow(MealEntry meal) {
    return GestureDetector(
      onTap: () => _reLog(meal),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: cardDecoration(radius: Radii.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meal.name,
                    style: AppType.serif(17, weight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${meal.calories} kcal',
                        style: AppType.mono(11, color: Palette.smoke),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'P${meal.protein} · C${meal.carbs} · F${meal.fat}',
                        style: AppType.mono(11, color: Palette.smoke),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.add_circle, size: 20, color: Palette.paper),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nothing here yet.',
            style: AppType.serif(20, weight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            "Log a meal by voice, photo, or barcode and it'll show up "
            'here as a one-tap re-log.',
            style: AppType.body(13, color: Palette.smoke),
          ),
        ],
      ),
    );
  }
}
