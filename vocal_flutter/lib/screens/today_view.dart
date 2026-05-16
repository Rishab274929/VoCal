// Editorial daily dashboard — Flutter port of TodayView.swift.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

class TodayView extends StatelessWidget {
  final VoidCallback onShowVoice;
  final VoidCallback onShowPhoto;
  final VoidCallback onShowBarcode;
  const TodayView(
      {super.key,
      required this.onShowVoice,
      required this.onShowPhoto,
      required this.onShowBarcode});

  String _greeting(String name) {
    final h = DateTime.now().hour;
    String prefix;
    if (h >= 5 && h < 12) {
      prefix = 'Morning';
    } else if (h >= 12 && h < 17) {
      prefix = 'Afternoon';
    } else if (h >= 17 && h < 22) {
      prefix = 'Evening';
    } else {
      prefix = 'Late night';
    }
    return '$prefix · $name';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppModel>();
    final t = app.totals;
    // Match iOS: format with thousands separators so 1880 reads as 1,880
    // and the headline fits on two lines instead of three on a Pixel 9.
    final kcalFmt = NumberFormat.decimalPattern();

    return SingleChildScrollView(
      // iOS bumped horizontal padding 24→28 (commit 79bf629) to keep
      // tracked eyebrows + italic wordmark from clipping the left edge.
      // Bottom 18 — the tab bar is now in-flow, no need for the old 80
      // overhang gutter.
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // top bar
          Row(
            children: [
              const VoCalWordmark(),
              const Spacer(),
              GestureDetector(
                onTap: onShowBarcode,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.hairlineStrong),
                  ),
                  child: const Icon(Icons.qr_code_scanner,
                      size: 14, color: Palette.bone),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onShowPhoto,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Palette.hairlineStrong),
                  ),
                  child: const Icon(Icons.camera_alt,
                      size: 13, color: Palette.bone),
                ),
              ),
              const SizedBox(width: 10),
              StreakBadge(days: app.profile.streakDays),
            ],
          ),
          const SizedBox(height: Spacing.lg),

          // hero
          // Eyebrow widget already uppercases — don't double-call .toUpperCase
          Eyebrow(_greeting(app.profile.displayName.isEmpty
              ? 'there'
              : app.profile.displayName)),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                  text: 'You have ',
                  style: AppType.serif(36,
                      weight: FontWeight.w500, color: Palette.smoke)),
              TextSpan(
                  text: '${kcalFmt.format(t.calorieRemaining)} kcal',
                  style: AppType.serif(36,
                      weight: FontWeight.w500,
                      italic: true,
                      color: Palette.voltage)),
              // Match iOS exactly: " left today." (not "left in the day.")
              TextSpan(
                  text: ' left today.',
                  style: AppType.serif(36,
                      weight: FontWeight.w500, color: Palette.ash)),
            ]),
          ),
          const SizedBox(height: Spacing.lg),

          // ring block
          Container(
            padding: const EdgeInsets.all(20),
            decoration: cardDecoration(radius: Radii.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CalorieRing(
                    eaten: t.caloriesEaten, goal: t.calorieGoal, size: 168),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _statColumn('EATEN', t.caloriesEaten, Palette.bone),
                      _hr(),
                      _statColumn('GOAL', t.calorieGoal, Palette.ash),
                      _hr(),
                      // Match iOS: column label is REMAINING, not DEFICIT
                      _statColumn(
                          'REMAINING',
                          (t.calorieGoal - t.caloriesEaten) < 0
                              ? 0
                              : t.calorieGoal - t.caloriesEaten,
                          Palette.voltage),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // macros
          const SectionHeader(title: 'Macros', eyebrow: 'Today'),
          const SizedBox(height: Spacing.md),
          MacroBar(
              label: 'Protein',
              eaten: t.proteinEaten,
              goal: t.proteinGoal,
              tint: Palette.protein),
          const SizedBox(height: 18),
          MacroBar(
              label: 'Carbs',
              eaten: t.carbsEaten,
              goal: t.carbsGoal,
              tint: Palette.carbs),
          const SizedBox(height: 18),
          MacroBar(
              label: 'Fat',
              eaten: t.fatEaten,
              goal: t.fatGoal,
              tint: Palette.fat),
          const SizedBox(height: Spacing.lg),

          // meals
          SectionHeader(
              title: "Today's log",
              eyebrow: '${app.meals.length} entries'),
          const SizedBox(height: Spacing.md),
          if (app.meals.isEmpty)
            _emptyMeals(context)
          else
            Column(
              children: [
                for (final m in app.meals) ...[
                  MealCard(meal: m),
                  const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }

  Widget _hr() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Container(height: 1, color: Palette.hairline),
      );

  Widget _statColumn(String label, int value, Color tint) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 2,
                color: Palette.smoke)),
        const SizedBox(height: 2),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('$value',
                style: AppType.serif(24,
                    weight: FontWeight.w500, color: tint)),
            const SizedBox(width: 4),
            Text('kcal', style: AppType.body(10, color: Palette.smoke)),
          ],
        ),
      ],
    );
  }

  Widget _emptyMeals(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(30),
      decoration: cardDecoration(),
      child: Column(
        children: [
          const Icon(Icons.graphic_eq, size: 28, color: Palette.voltage),
          const SizedBox(height: 12),
          Text('Nothing logged yet',
              style: AppType.serif(20,
                  weight: FontWeight.w500, italic: true)),
          const SizedBox(height: 8),
          Text('Tap the mic and just say what you ate.',
              textAlign: TextAlign.center,
              style: AppType.body(13, color: Palette.smoke)),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: onShowVoice,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                  color: Palette.voltage,
                  borderRadius: BorderRadius.circular(20)),
              child: Text('Say something',
                  style: AppType.body(13,
                      weight: FontWeight.w600, color: Palette.ink)),
            ),
          ),
        ],
      ),
    );
  }
}
