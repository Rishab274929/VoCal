// Editorial component library — Flutter port of Components.swift.
// Big serif numerals, thin hairlines, tactile accent fills. Everything
// reuses theme tokens — never raw colors.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme/theme.dart';

// MARK: - Display number — the editorial hero stat

class DisplayNumber extends StatelessWidget {
  final int value;
  final String label;
  final String unit;
  final Color tint;
  final double size;

  const DisplayNumber({
    super.key,
    required this.value,
    required this.label,
    this.unit = 'kcal',
    this.tint = Palette.bone,
    this.size = 92,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('$value',
                style: AppType.serif(size,
                    weight: FontWeight.w500, color: tint)),
            const SizedBox(width: 8),
            Padding(
              padding: EdgeInsets.only(bottom: size * 0.10),
              child: Text(unit,
                  style: AppType.serif(size * 0.28,
                      italic: true, color: Palette.smoke)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Eyebrow(label),
      ],
    );
  }
}

// MARK: - Calorie ring

class CalorieRing extends StatelessWidget {
  final int eaten;
  final int goal;
  final double size;

  const CalorieRing({
    super.key,
    required this.eaten,
    required this.goal,
    this.size = 248,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (eaten / (goal <= 0 ? 1 : goal)).clamp(0.0, 1.0);
    final over = goal > 0 && eaten > goal;
    final delta = eaten - goal;
    final remaining = over ? delta : (goal - eaten);
    final tint = over ? Palette.pulse : Palette.voltage;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOut,
            builder: (_, p, __) => CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(progress: p, tint: tint),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$remaining',
                  style: AppType.serif(size * 0.32,
                      weight: FontWeight.w500, color: Palette.bone)),
              const SizedBox(height: 6),
              Text(over ? 'KCAL OVER' : 'KCAL LEFT',
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 2.4,
                      color: over ? Palette.pulse : Palette.smoke)),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('$eaten',
                      style: AppType.mono(11,
                          weight: FontWeight.w500, color: Palette.ash)),
                  const SizedBox(width: 6),
                  Text('of', style: AppType.body(12, color: Palette.smoke)),
                  const SizedBox(width: 6),
                  Text('$goal',
                      style: AppType.mono(11,
                          weight: FontWeight.w500, color: Palette.ash)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color tint;
  _RingPainter({required this.progress, required this.tint});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;

    // Outer ghost ring
    canvas.drawCircle(
      center,
      size.width / 2 - 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Palette.hairline,
    );

    // Track
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..color = Palette.hairlineStrong,
    );

    if (progress <= 0) return;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final sweep = progress * 2 * math.pi;
    const start = -math.pi / 2;

    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: const GradientRotation(-math.pi / 2),
      colors: [
        tint.withOpacity(0.6),
        tint,
        tint,
      ],
    ).createShader(rect);

    // Glow pass
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = tint.withOpacity(0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );
    // Main stroke
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.tint != tint;
}

// MARK: - Macro bar

class MacroBar extends StatelessWidget {
  final String label;
  final int eaten;
  final int goal;
  final Color tint;

  const MacroBar({
    super.key,
    required this.label,
    required this.eaten,
    required this.goal,
    required this.tint,
  });

  @override
  Widget build(BuildContext context) {
    final progress = (eaten / (goal <= 0 ? 1 : goal)).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.8,
                    color: Palette.smoke)),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text('$eaten',
                    style: AppType.mono(15, weight: FontWeight.w600)),
                Text(' / ',
                    style: AppType.mono(12,
                        weight: FontWeight.w400, color: Palette.smoke)),
                Text('${goal}g',
                    style: AppType.mono(12,
                        weight: FontWeight.w400, color: Palette.smoke)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (_, c) {
          return Stack(
            children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                    color: Palette.hairlineStrong,
                    borderRadius: BorderRadius.circular(2)),
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress.toDouble()),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOut,
                builder: (_, p, __) => Container(
                  height: 4,
                  width: math.max(2.0, c.maxWidth * p),
                  decoration: BoxDecoration(
                    color: tint,
                    borderRadius: BorderRadius.circular(2),
                    boxShadow: [
                      BoxShadow(
                          color: tint.withOpacity(0.4), blurRadius: 6),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}

// MARK: - Macro pill

class MacroPill extends StatelessWidget {
  final String letter;
  final int value;
  final Color tint;
  const MacroPill(
      {super.key,
      required this.letter,
      required this.value,
      required this.tint});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tint, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text.rich(TextSpan(children: [
            TextSpan(
                text: letter,
                style: AppType.mono(12,
                    weight: FontWeight.w500, color: Palette.smoke)),
            TextSpan(
                text: ' $value',
                style: AppType.mono(12,
                    weight: FontWeight.w500, color: Palette.bone)),
            TextSpan(
                text: 'g',
                style: AppType.mono(12,
                    weight: FontWeight.w500, color: Palette.smoke)),
          ])),
        ],
      ),
    );
  }
}

// MARK: - Meal card

class MealCard extends StatelessWidget {
  final MealEntry meal;
  const MealCard({super.key, required this.meal});

  Color get _slotColor {
    switch (meal.slot) {
      case MealSlot.breakfast:
        return Palette.carbs;
      case MealSlot.lunch:
        return Palette.voltage;
      case MealSlot.dinner:
        return Palette.fat;
      case MealSlot.snack:
        return Palette.protein;
    }
  }

  String _time(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.md),
      child: Container(
        decoration: cardDecoration(),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: _slotColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(meal.slot.raw.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                  color: _slotColor)),
                          const SizedBox(width: 6),
                          Text('·',
                              style: TextStyle(
                                  fontSize: 9, color: Palette.smoke)),
                          const SizedBox(width: 6),
                          Text(_time(meal.loggedAt),
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Palette.smoke)),
                          const SizedBox(width: 6),
                          if (meal.source == MealSource.voice)
                            Icon(Icons.graphic_eq,
                                size: 11, color: Palette.smoke)
                          else if (meal.source == MealSource.photo)
                            Icon(Icons.camera_alt,
                                size: 11, color: Palette.smoke),
                          const Spacer(),
                          Text('${meal.calories}',
                              style: AppType.serif(28,
                                  weight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(meal.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body(16, weight: FontWeight.w600)),
                      if (meal.detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(meal.detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                AppType.body(13, color: Palette.ash)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          MacroPill(
                              letter: 'P',
                              value: meal.protein,
                              tint: Palette.protein),
                          const SizedBox(width: 6),
                          MacroPill(
                              letter: 'C',
                              value: meal.carbs,
                              tint: Palette.carbs),
                          const SizedBox(width: 6),
                          MacroPill(
                              letter: 'F',
                              value: meal.fat,
                              tint: Palette.fat),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// MARK: - Mic button
//
// iOS commit 7e2e04a inlined this button into the tab bar (size 52 from a
// floating 78). The old floating FAB extended the perceived bar height by
// ~30pt and overhung into content above. Sized + shadow tuned to live inside
// an HStack slot, not float.

class MicButton extends StatefulWidget {
  final VoidCallback onTap;
  final double size;
  const MicButton({super.key, required this.onTap, this.size = 52});

  @override
  State<MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<MicButton>
    with TickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat();
  late final AnimationController _rot =
      AnimationController(vsync: this, duration: const Duration(seconds: 18))
        ..repeat();

  @override
  void dispose() {
    _pulse.dispose();
    _rot.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return Semantics(
      label: 'Log a meal with your voice',
      button: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: SizedBox(
          width: s,
          height: s,
          child: AnimatedBuilder(
            animation: Listenable.merge([_pulse, _rot]),
            builder: (_, __) {
              final p = _pulse.value;
              return Stack(
                alignment: Alignment.center,
                children: [
                  Transform.scale(
                    scale: 1 + 0.7 * p,
                    child: Opacity(
                      opacity: (1 - p).clamp(0.0, 1.0),
                      child: Container(
                        width: s,
                        height: s,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Palette.pulse.withOpacity(0.55),
                              width: 1.5),
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: s,
                    height: s,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Palette.ink,
                      border: Border.all(color: Palette.pulse, width: 2),
                      boxShadow: [
                        BoxShadow(
                            color: Palette.pulse.withOpacity(0.4),
                            blurRadius: 14),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: _rot.value * 2 * math.pi,
                    child: CustomPaint(
                      size: Size(s, s),
                      painter: _TickPainter(s),
                    ),
                  ),
                  Icon(Icons.mic, size: s * 0.32, color: Palette.bone),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  final double size;
  _TickPainter(this.size);

  @override
  void paint(Canvas canvas, Size canvasSize) {
    final c = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final r = size * 0.42;
    for (var i = 0; i < 24; i++) {
      final major = i % 3 == 0;
      final paint = Paint()
        ..color = Palette.pulse.withOpacity(major ? 0.9 : 0.25)
        ..strokeWidth = 1;
      final angle = i / 24 * 2 * math.pi;
      final len = major ? size * 0.10 : size * 0.05;
      final dir = Offset(math.sin(angle), -math.cos(angle));
      canvas.drawLine(c + dir * (r - len), c + dir * r, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.size != size;
}

// MARK: - Waveform orb

class WaveformOrb extends StatefulWidget {
  final bool isActive;
  final Color tint;
  const WaveformOrb({super.key, this.isActive = true, this.tint = Palette.pulse});

  @override
  State<WaveformOrb> createState() => _WaveformOrbState();
}

class _WaveformOrbState extends State<WaveformOrb>
    with TickerProviderStateMixin {
  late final AnimationController _bloom =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2200))
        ..repeat();
  late final AnimationController _bars =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _bloom.dispose();
    _bars.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = widget.tint;
    return SizedBox(
      width: 240,
      height: 240,
      child: AnimatedBuilder(
        animation: Listenable.merge([_bloom, _bars]),
        builder: (_, __) {
          return Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                () {
                  final t = ((_bloom.value + i * 0.19) % 1.0);
                  return Transform.scale(
                    scale: 0.6 + 0.7 * t,
                    child: Opacity(
                      opacity: ((1 - t) * 0.6).clamp(0.0, 1.0),
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: tint.withOpacity(0.35 - i * 0.07 < 0
                                  ? 0.02
                                  : 0.35 - i * 0.07)),
                        ),
                      ),
                    ),
                  );
                }(),
              Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [tint, tint.withOpacity(0)],
                  ),
                ),
              ),
              Container(
                width: 158,
                height: 158,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Palette.ink,
                  border: Border.all(color: tint, width: 2),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (var i = 0; i < 5; i++) ...[
                    Container(
                      width: 5,
                      height: 18 +
                          (widget.isActive
                              ? (10 + (i * 13) % 38) * _bars.value
                              : 0),
                      decoration: BoxDecoration(
                          color: tint,
                          borderRadius: BorderRadius.circular(3)),
                    ),
                    if (i < 4) const SizedBox(width: 7),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// MARK: - Section header

class SectionHeader extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final String? trailing;
  const SectionHeader(
      {super.key, required this.title, this.eyebrow, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null)
          Text(eyebrow!.toUpperCase(),
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2,
                  color: Palette.smoke)),
        if (eyebrow != null) const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(title,
                style: AppType.serif(22, weight: FontWeight.w600)),
            const Spacer(),
            if (trailing != null)
              Text(trailing!,
                  style: AppType.body(12, color: Palette.smoke)),
          ],
        ),
      ],
    );
  }
}

// MARK: - Buttons

class VoltageButton extends StatelessWidget {
  final String title;
  final IconData? icon;
  final bool fullWidth;
  final bool enabled;
  final VoidCallback onTap;
  const VoltageButton({
    super.key,
    required this.title,
    this.icon,
    this.fullWidth = true,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        color: Palette.voltage,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
              color: Palette.voltage.withOpacity(0.35),
              blurRadius: 22,
              offset: const Offset(0, 6)),
        ],
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: Palette.ink),
            const SizedBox(width: 8),
          ],
          Text(title,
              style: AppType.body(15,
                  weight: FontWeight.w600, color: Palette.ink)),
        ],
      ),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: fullWidth ? SizedBox(width: double.infinity, child: child) : child,
      ),
    );
  }
}

class GhostButton extends StatelessWidget {
  final String title;
  final IconData? icon;
  final Color tint;
  final bool fullWidth;
  final VoidCallback onTap;
  const GhostButton({
    super.key,
    required this.title,
    this.icon,
    this.tint = Palette.bone,
    this.fullWidth = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Row(
        mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: tint),
            const SizedBox(width: 8),
          ],
          Text(title,
              style: AppType.body(14, weight: FontWeight.w600, color: tint)),
        ],
      ),
    );
    return GestureDetector(
      onTap: onTap,
      child: fullWidth ? SizedBox(width: double.infinity, child: child) : child,
    );
  }
}

// MARK: - Streak badge

class StreakBadge extends StatelessWidget {
  final int days;
  const StreakBadge({super.key, required this.days});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department,
              size: 12, color: Palette.pulse),
          const SizedBox(width: 6),
          Text('$days', style: AppType.mono(13, weight: FontWeight.w600)),
          const SizedBox(width: 4),
          Text('DAY',
              style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                  color: Palette.smoke)),
        ],
      ),
    );
  }
}

// MARK: - Wordmark

class VoCalWordmark extends StatelessWidget {
  const VoCalWordmark({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Vo',
            style: AppType.serif(20,
                weight: FontWeight.w600, italic: true)),
        Text('Cal',
            style: AppType.serif(20,
                weight: FontWeight.w600,
                italic: true,
                color: Palette.voltage)),
      ],
    );
  }
}

// MARK: - Follow-up question card

class FollowUpQuestionCard extends StatelessWidget {
  final String question;
  final TextEditingController controller;
  const FollowUpQuestionCard(
      {super.key, required this.question, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Palette.inkRaised,
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: Palette.pulse.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('ONE QUICK CHECK', color: Palette.pulse),
          const SizedBox(height: 14),
          Text(question,
              style: AppType.serif(24, weight: FontWeight.w500)),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            style: AppType.body(15),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Your answer',
              hintStyle: AppType.body(15, color: Palette.smoke),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                borderSide: BorderSide(color: Palette.hairlineStrong),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(Radii.sm),
                borderSide: BorderSide(color: Palette.hairlineStrong),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// MARK: - Weight sparkline

class WeightSparkline extends StatelessWidget {
  final List<double> values;
  final Color tint;
  const WeightSparkline(
      {super.key, required this.values, this.tint = Palette.voltage});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _SparklinePainter(values, tint),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color tint;
  _SparklinePainter(this.values, this.tint);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final mn = values.reduce(math.min);
    final mx = values.reduce(math.max);
    final pad = (mx - mn) * 0.15;
    final lo = mn - pad;
    final hi = mx + pad;
    final span = math.max(0.0001, hi - lo);

    // Grid
    final grid = Paint()
      ..color = Palette.hairline
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * (i + 1) / 4;
      _dashedLine(canvas, Offset(0, y), Offset(size.width, y), grid);
    }

    final pts = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - (values[i] - lo) / span);
      pts.add(Offset(x, y));
    }

    // Fill
    final fill = Path()..moveTo(pts.first.dx, size.height);
    fill.lineTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      fill.lineTo(p.dx, p.dy);
    }
    fill.lineTo(pts.last.dx, size.height);
    fill.close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [tint.withOpacity(0.35), tint.withOpacity(0)],
        ).createShader(Offset.zero & size),
    );

    // Line
    final line = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final p in pts.skip(1)) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = tint,
    );

    // Last dot
    final last = pts.last;
    canvas.drawCircle(last, 4, Paint()..color = tint);
    canvas.drawCircle(
        last,
        4,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Palette.ink);
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint p) {
    const dash = 3.0, gap = 4.0;
    final total = (b - a).distance;
    final dir = (b - a) / total;
    var d = 0.0;
    while (d < total) {
      final s = a + dir * d;
      final e = a + dir * math.min(d + dash, total);
      canvas.drawLine(s, e, p);
      d += dash + gap;
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) => old.values != values;
}

// MARK: - Coach bubble

class CoachBubble extends StatelessWidget {
  final CoachRole role;
  final String content;
  const CoachBubble({super.key, required this.role, required this.content});

  @override
  Widget build(BuildContext context) {
    final isUser = role == CoachRole.user;
    final bubble = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width - 80),
      decoration: BoxDecoration(
        color: isUser ? Palette.voltage : Palette.inkSurface,
        borderRadius: BorderRadius.circular(22),
        border: isUser ? null : Border.all(color: Palette.hairline),
      ),
      child: Text(content,
          style: AppType.body(15,
              color: isUser ? Palette.ink : Palette.bone)),
    );
    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [Flexible(child: bubble)],
    );
  }
}

// MARK: - Ambient background

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: Palette.ink)),
        Positioned(
          left: -300,
          top: -560,
          child: Container(
            width: 460,
            height: 460,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Palette.voltage.withOpacity(0.10),
                Palette.voltage.withOpacity(0),
              ]),
            ),
          ),
        ),
        Positioned(
          right: -200,
          top: -360,
          child: Container(
            width: 380,
            height: 380,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                Palette.pulse.withOpacity(0.06),
                Palette.pulse.withOpacity(0),
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

// MARK: - Editorial tab bar

enum AppTab { today, progress, coach, profile }

extension AppTabInfo on AppTab {
  IconData get icon {
    switch (this) {
      case AppTab.today:
        return Icons.radio_button_unchecked;
      case AppTab.progress:
        return Icons.bar_chart;
      case AppTab.coach:
        return Icons.forum_outlined;
      case AppTab.profile:
        return Icons.person_outline;
    }
  }

  String get label {
    switch (this) {
      case AppTab.today:
        return 'Today';
      case AppTab.progress:
        return 'Progress';
      case AppTab.coach:
        return 'Coach';
      case AppTab.profile:
        return 'You';
    }
  }
}

class EditorialTabBar extends StatelessWidget {
  final AppTab selection;
  final ValueChanged<AppTab> onSelect;
  final VoidCallback onMic;
  const EditorialTabBar({
    super.key,
    required this.selection,
    required this.onSelect,
    required this.onMic,
  });

  @override
  Widget build(BuildContext context) {
    // iOS commit 7e2e04a inlined the mic into the center slot — no floating
    // overhang, no extra perceived height. Mirror that here.
    final bottomPad = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Palette.ink,
        border:
            Border(top: BorderSide(color: Palette.hairline, width: 1)),
      ),
      padding: EdgeInsets.only(top: 8, bottom: bottomPad),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _tab(AppTab.today),
          _tab(AppTab.progress),
          // Mic sits INLINE in the center slot. Width matches iOS (86) and
          // a small negative top padding keeps the larger circle visually
          // centered with the smaller tab icons.
          SizedBox(
            width: 86,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: MicButton(onTap: onMic, size: 52),
            ),
          ),
          _tab(AppTab.coach),
          _tab(AppTab.profile),
        ],
      ),
    );
  }

  Widget _tab(AppTab tab) {
    final active = selection == tab;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(tab),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(tab.icon,
                  size: 17,
                  color: active ? Palette.voltage : Palette.smoke),
              const SizedBox(height: 3),
              Text(tab.label.toUpperCase(),
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                      color: active ? Palette.voltage : Palette.smoke)),
            ],
          ),
        ),
      ),
    );
  }
}
