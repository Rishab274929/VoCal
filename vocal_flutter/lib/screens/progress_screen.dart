// Progress: kcal trend, weight, body-fat, recent days — Flutter port of
// HistoryView.swift (ProgressScreen).

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../data/mock_data.dart';
import '../sheets/bodyfat_photo_sheet.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  static const List<double> _barHeights = [70, 86, 64, 96, 110, 78, 96];
  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppModel>();

    final weights =
        app.bodyMetrics.map((b) => b.weightLbs).toList().reversed.toList();
    final curW = weights.isNotEmpty ? weights.last : app.profile.weightLbs;
    final firstW = weights.isNotEmpty ? weights.first : curW;
    final dW = curW - firstW;

    final bfs = app.bodyMetrics
        .where((b) => b.bodyFatPct != null)
        .map((b) => b.bodyFatPct!)
        .toList()
        .reversed
        .toList();
    final curBf = bfs.isNotEmpty ? bfs.last : 17.0;
    final firstBf = bfs.isNotEmpty ? bfs.first : curBf;
    final dBf = curBf - firstBf;

    return SingleChildScrollView(
      // iOS spacing parity: 28 horizontal, 24 bottom (no tab-bar overhang).
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('PROGRESS', color: Palette.pulse),
          const SizedBox(height: 6),
          Text('Two weeks at a glance.',
              style: AppType.serif(28, weight: FontWeight.w500)),
          const SizedBox(height: Spacing.lg),

          // weekly kcal chart
          Container(
            padding: const EdgeInsets.all(20),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('CALORIES · 7 DAYS'),
                        const SizedBox(height: 2),
                        Text('avg 1,940 kcal',
                            style: AppType.body(14,
                                weight: FontWeight.w600)),
                      ],
                    ),
                    const Spacer(),
                    Row(children: [
                      Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                              color: Palette.voltage,
                              shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text('today',
                          style: AppType.body(10, color: Palette.smoke)),
                    ]),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Column(
                          children: [
                            SizedBox(
                              height: 120,
                              child: Stack(
                                alignment: Alignment.bottomCenter,
                                children: [
                                  Container(
                                    width: 16,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      color: Palette.hairlineStrong,
                                      borderRadius:
                                          BorderRadius.circular(4),
                                    ),
                                  ),
                                  Container(
                                    width: 16,
                                    height: _barHeights[i],
                                    decoration: BoxDecoration(
                                      color: i == 6
                                          ? Palette.voltage
                                          : Palette.bone.withOpacity(0.5),
                                      borderRadius:
                                          BorderRadius.circular(4),
                                      boxShadow: i == 6
                                          ? [
                                              BoxShadow(
                                                  color: Palette.voltage
                                                      .withOpacity(0.5),
                                                  blurRadius: 8)
                                            ]
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(_weekdays[i],
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                    color: i == 6
                                        ? Palette.voltage
                                        : Palette.smoke)),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // weight card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: cardDecoration(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Eyebrow('WEIGHT'),
                        const SizedBox(height: 2),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(curW.toStringAsFixed(1),
                                style: AppType.serif(32,
                                    weight: FontWeight.w500)),
                            const SizedBox(width: 6),
                            Text('lb',
                                style: AppType.body(13,
                                    color: Palette.smoke)),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(_delta(dW, 'lb'),
                            style: AppType.body(12,
                                weight: FontWeight.w600,
                                color: dW < 0
                                    ? Palette.voltage
                                    : Palette.pulse)),
                        const SizedBox(height: 4),
                        Text('vs 4 weeks ago',
                            style: AppType.body(10, color: Palette.smoke)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  height: 88,
                  child: WeightSparkline(
                      values: weights.isEmpty ? [curW, curW] : weights,
                      tint: Palette.voltage),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // body fat card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: cardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('BODY FAT'),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(curBf.toStringAsFixed(1),
                              style: AppType.serif(48,
                                  weight: FontWeight.w500)),
                          const SizedBox(width: 4),
                          Text('%',
                              style: AppType.serif(18,
                                  italic: true, color: Palette.smoke)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.south_east,
                              size: 10, color: Palette.voltage),
                          const SizedBox(width: 6),
                          Text(
                              '${dBf.abs().toStringAsFixed(1)} pts in 30d',
                              style: AppType.body(11, color: Palette.ash)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: () => showBodyFatPhotoSheet(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Palette.voltage),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.camera_alt,
                                  size: 11, color: Palette.voltage),
                              const SizedBox(width: 6),
                              Text('Take baseline',
                                  style: AppType.body(11,
                                      weight: FontWeight.w600,
                                      color: Palette.voltage)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(88, 88),
                        painter: _BfRingPainter(
                            (curBf / 40.0).clamp(0.0, 0.5)),
                      ),
                      const Icon(Icons.accessibility_new,
                          size: 22, color: Palette.bone),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: Spacing.lg),

          // recent days
          const SectionHeader(
              title: 'Recent days', eyebrow: 'Past two weeks'),
          const SizedBox(height: 14),
          for (final d in MockData.historySummaries) ...[
            _HistoryRow(date: d.$1, calories: d.$2, goal: d.$3),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  String _delta(double v, String unit) {
    final sign = v < 0 ? '−' : '+';
    return '$sign${v.abs().toStringAsFixed(1)} $unit';
  }
}

class _BfRingPainter extends CustomPainter {
  final double progress;
  _BfRingPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 4;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..color = Palette.hairlineStrong);
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      -3.14159 / 2,
      progress * 2 * 3.14159,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(colors: [
          Palette.pulse,
          Palette.voltage,
          Palette.voltage
        ]).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_BfRingPainter old) => old.progress != progress;
}

class _HistoryRow extends StatelessWidget {
  final DateTime date;
  final int calories;
  final int goal;
  const _HistoryRow(
      {required this.date, required this.calories, required this.goal});

  @override
  Widget build(BuildContext context) {
    final progress = (calories / (goal <= 0 ? 1 : goal)).clamp(0.0, 1.2);
    final over = calories > goal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: cardDecoration(radius: Radii.sm),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('EEE').format(date).toUpperCase(),
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                        color: Palette.bone)),
                Text(DateFormat('MMM d').format(date),
                    style: AppType.body(10, color: Palette.smoke)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              return SizedBox(
                height: 4,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: Palette.hairlineStrong,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: (c.maxWidth * progress.clamp(0.0, 1.0))
                          .clamp(2.0, c.maxWidth),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: over ? Palette.pulse : Palette.voltage,
                            borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 90,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$calories',
                    style: AppType.mono(13, weight: FontWeight.w600)),
                Text(' / $goal',
                    style: AppType.mono(10, color: Palette.smoke)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
