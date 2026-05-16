// Voice-first nutrition coach — Flutter port of CoachView.swift.
// Heuristic replies offline so the demo always feels alive.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

class CoachView extends StatefulWidget {
  const CoachView({super.key});

  @override
  State<CoachView> createState() => _CoachViewState();
}

class _CoachViewState extends State<CoachView> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  bool _thinking = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _send() {
    final app = context.read<AppModel>();
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    app.appendCoach(CoachMessage(role: CoachRole.user, content: trimmed));
    _controller.clear();
    setState(() => _thinking = true);
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      final reply = _reply(trimmed, app);
      app.appendCoach(
          CoachMessage(role: CoachRole.assistant, content: reply));
      setState(() => _thinking = false);
      _scrollToEnd();
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut);
      }
    });
  }

  String _reply(String prompt, AppModel app) {
    final lower = prompt.toLowerCase();
    final t = app.totals;
    final proteinShort = (t.proteinGoal - t.proteinEaten) < 0
        ? 0
        : t.proteinGoal - t.proteinEaten;
    final kcalLeft = t.calorieRemaining;

    if (lower.contains('protein')) {
      return "You're at ${t.proteinEaten}g of ${t.proteinGoal}g protein — "
          "${proteinShort}g short with $kcalLeft kcal left. A grilled chicken "
          "bowl from Cava (≈40g protein, ~520 kcal) or Chick-fil-A's grilled "
          "nuggets 12-ct (~38g protein, ~210 kcal) would clear most of it.";
    }
    if (lower.contains('pasta') || lower.contains('dinner')) {
      return "With $kcalLeft kcal to play with, a 2-cup serving of spaghetti "
          "pomodoro lands around 560 kcal. Add a 4 oz grilled chicken breast "
          "(~190 kcal, 35g protein) and you're at 750 kcal — well under "
          "budget, and you finish the day on protein.";
    }
    if (lower.contains('hungry') || lower.contains('snack')) {
      return "Could be a protein gap — you've leaned breakfast-heavy and "
          "light on protein at lunch. A Greek yogurt + handful of almonds "
          "(~250 kcal, 18g protein) usually kills the 4pm dip without "
          "ruining dinner.";
    }
    return "I'm watching your day: ${t.caloriesEaten} eaten, $kcalLeft "
        "remaining, ${t.proteinEaten}g protein in. What were you thinking "
        "of having?";
  }

  Widget _suggestion(String text) {
    return GestureDetector(
      onTap: () => _controller.text = text,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Palette.hairlineStrong),
        ),
        child: Text(text, style: AppType.body(13, color: Palette.ash)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppModel>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Eyebrow('COACH', color: Palette.pulse),
                  const Spacer(),
                  Row(children: [
                    Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                            color: Palette.voltage,
                            shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text('on duty',
                        style: AppType.body(10,
                            weight: FontWeight.w600,
                            color: Palette.smoke)),
                  ]),
                ],
              ),
              const SizedBox(height: 8),
              Text('Talk to it. It knows your day.',
                  style: AppType.serif(28, weight: FontWeight.w500)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(28, 14, 28, 18),
            children: [
              Row(
                children: [
                  const Icon(Icons.auto_awesome,
                      size: 16, color: Palette.voltage),
                  const SizedBox(width: 12),
                  const Eyebrow('TRY ASKING'),
                ],
              ),
              const SizedBox(height: 12),
              _suggestion('How do I hit 180g protein today?'),
              _suggestion('What if I want pasta for dinner?'),
              _suggestion('Why am I always hungry at 4pm?'),
              const SizedBox(height: 14),
              for (final m in app.coachMessages) ...[
                CoachBubble(role: m.role, content: m.content),
                const SizedBox(height: 14),
              ],
              if (_thinking)
                Row(children: [
                  const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Palette.voltage)),
                  const SizedBox(width: 8),
                  Text('thinking…',
                      style: AppType.body(12, color: Palette.smoke)),
                ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Palette.inkSurface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: Palette.hairlineStrong),
                  ),
                  child: TextField(
                    controller: _controller,
                    style: AppType.body(15),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 14),
                      hintText: 'Ask anything…',
                      hintStyle:
                          AppType.body(15, color: Palette.smoke),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Disable the send affordance when there's no message — empty
              // taps used to silently no-op and looked like a dead button.
              Opacity(
                opacity: _controller.text.trim().isEmpty ? 0.55 : 1.0,
                child: GestureDetector(
                  onTap: _controller.text.trim().isEmpty ? null : _send,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _controller.text.trim().isEmpty
                          ? Palette.pulse
                          : Palette.voltage,
                      boxShadow: [
                        BoxShadow(
                            color: (_controller.text.trim().isEmpty
                                    ? Palette.pulse
                                    : Palette.voltage)
                                .withOpacity(0.4),
                            blurRadius: 12),
                      ],
                    ),
                    child: Icon(
                        _controller.text.trim().isEmpty
                            ? Icons.mic
                            : Icons.arrow_upward,
                        size: 16,
                        color: Palette.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
