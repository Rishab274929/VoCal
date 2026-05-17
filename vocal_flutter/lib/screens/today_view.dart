// Editorial daily dashboard — Flutter port of TodayView.swift.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../sheets/meal_edit_sheet.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

class TodayView extends StatelessWidget {
  final VoidCallback onShowVoice;
  /// Single unified camera entry point — covers both still-frame meal
  /// photos AND live barcode scanning in one sheet. iOS commit
  /// collapsed the separate photo + barcode buttons into one for the
  /// same reason (the user-intent is "log what's in front of me").
  final VoidCallback onShowUnifiedCamera;
  const TodayView(
      {super.key,
      required this.onShowVoice,
      required this.onShowUnifiedCamera});

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
                onTap: onShowUnifiedCamera,
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

          // ring block — entire card is a tap target that opens the
          // unified camera. Subtle camera glyph at the ring's edge
          // signals tap-to-log. iOS parity: ring-as-tap-target landed
          // alongside the unified camera so the rich primary surface
          // becomes the dominant logging entry point.
          GestureDetector(
            onTap: onShowUnifiedCamera,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: cardDecoration(radius: Radii.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      CalorieRing(
                          eaten: t.caloriesEaten,
                          goal: t.calorieGoal,
                          size: 168),
                      Container(
                        margin: const EdgeInsets.all(4),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Palette.inkSurface,
                          border: Border.all(color: Palette.hairlineStrong),
                        ),
                        child: const Icon(Icons.camera_alt,
                            size: 12, color: Palette.bone),
                      ),
                    ],
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _statColumn('EATEN', t.caloriesEaten, Palette.bone),
                        _hr(),
                        _statColumn('GOAL', t.calorieGoal, Palette.ash),
                        _hr(),
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

          // Micros — only shown when at least one meal today populated any
          // micronutrient field. Backend may omit micros for low-confidence
          // parses, so we hide the section entirely rather than render a
          // panel full of em-dashes.
          _MicrosPanel(meals: app.meals),
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
                  _SwipeableMealCard(meal: m),
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

// MARK: - Swipeable meal row
//
// Wraps MealCard in a Dismissible for swipe-to-delete + a tap target that
// opens MealEditSheet. We use `confirmDismiss` to show an AlertDialog before
// the entry is removed — a destructive action with no undo path needs at
// least one confirm beat, otherwise a rogue swipe on a phone in a pocket
// silently drops the user's most recent meal.
class _SwipeableMealCard extends StatelessWidget {
  final MealEntry meal;
  const _SwipeableMealCard({required this.meal});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('meal-${meal.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: Palette.pulse.withOpacity(0.18),
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: Palette.pulse.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.delete_outline, color: Palette.pulse, size: 18),
            const SizedBox(width: 8),
            Text('DELETE',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    color: Palette.pulse)),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        final ok = await showDialog<bool>(
          context: context,
          builder: (dialogCtx) => AlertDialog(
            backgroundColor: Palette.inkSurface,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Radii.md)),
            title: Text('Delete this meal?',
                style: AppType.serif(20, weight: FontWeight.w500)),
            content: Text(
                '${meal.name} · ${meal.calories} kcal will be removed from today.',
                style: AppType.body(13, color: Palette.ash)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(false),
                child: Text('Keep',
                    style: AppType.body(13,
                        weight: FontWeight.w600, color: Palette.ash)),
              ),
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(true),
                child: Text('Delete',
                    style: AppType.body(13,
                        weight: FontWeight.w700, color: Palette.pulse)),
              ),
            ],
          ),
        );
        return ok == true;
      },
      onDismissed: (_) {
        context.read<AppModel>().removeMeal(meal);
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showMealEditSheet(context, meal),
        child: MealCard(meal: meal),
      ),
    );
  }
}

// MARK: - Micros panel (day totals)
//
// Aggregates the optional micronutrient fields across today's meals. Each
// micro field renders as a single row only when at least one meal supplied
// a value — there's no "0 mg" rendered for fields the parser couldn't
// extract, because zero would imply "we measured this and it's zero," not
// "we never measured." Collapsible to keep Today's hero block uncluttered
// for the common case where micros aren't populated.
class _MicrosPanel extends StatefulWidget {
  final List<MealEntry> meals;
  const _MicrosPanel({required this.meals});

  @override
  State<_MicrosPanel> createState() => _MicrosPanelState();
}

class _MicrosPanelState extends State<_MicrosPanel> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final hasAny = widget.meals.any((m) => m.hasAnyMicros);
    if (!hasAny) return const SizedBox.shrink();

    // Sum each field; null contributions skipped.
    int? sumOf(int? Function(MealEntry) pick) {
      int total = 0;
      bool any = false;
      for (final m in widget.meals) {
        final v = pick(m);
        if (v != null) {
          total += v;
          any = true;
        }
      }
      return any ? total : null;
    }

    final rows = <(String, int, String)>[
      if (sumOf((m) => m.sodiumMg) != null)
        ('Sodium', sumOf((m) => m.sodiumMg)!, 'mg'),
      if (sumOf((m) => m.fiberG) != null)
        ('Fiber', sumOf((m) => m.fiberG)!, 'g'),
      if (sumOf((m) => m.sugarG) != null)
        ('Sugar', sumOf((m) => m.sugarG)!, 'g'),
      if (sumOf((m) => m.calciumMg) != null)
        ('Calcium', sumOf((m) => m.calciumMg)!, 'mg'),
      if (sumOf((m) => m.ironMg) != null)
        ('Iron', sumOf((m) => m.ironMg)!, 'mg'),
      if (sumOf((m) => m.vitaminCMg) != null)
        ('Vitamin C', sumOf((m) => m.vitaminCMg)!, 'mg'),
      if (sumOf((m) => m.potassiumMg) != null)
        ('Potassium', sumOf((m) => m.potassiumMg)!, 'mg'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Spacing.lg),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('Micros',
                  style: AppType.serif(22, weight: FontWeight.w600)),
              const SizedBox(width: 8),
              Icon(
                  _open
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: Palette.smoke),
              const Spacer(),
              Text('${rows.length} tracked',
                  style: AppType.body(12, color: Palette.smoke)),
            ],
          ),
        ),
        if (_open) ...[
          const SizedBox(height: Spacing.md),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: cardDecoration(),
            child: Column(
              children: [
                for (var i = 0; i < rows.length; i++) ...[
                  Row(
                    children: [
                      Text(rows[i].$1.toUpperCase(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.6,
                              color: Palette.smoke)),
                      const Spacer(),
                      Text('${rows[i].$2}',
                          style: AppType.mono(14, weight: FontWeight.w600)),
                      const SizedBox(width: 4),
                      Text(rows[i].$3,
                          style: AppType.body(11, color: Palette.smoke)),
                    ],
                  ),
                  if (i < rows.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child:
                          Container(height: 1, color: Palette.hairline),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
