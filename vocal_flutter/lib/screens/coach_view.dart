// Voice-first nutrition coach — Flutter port of CoachView.swift.
//
// Replies come from POST /api/coach (CoachApiClient). On network failure we
// show a single canned line — we intentionally do NOT run a local heuristic
// here. The previous local heuristic disagreed with the iOS coach's answers
// for the same prompt + day-state, which led to "the coach lied to me on my
// phone but not my friend's phone" support reports.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/coach_api.dart';
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

  /// Canned fallback shown on any network/parse failure. Intentionally
  /// generic so the user knows it's a comms problem (not the coach's
  /// opinion). Mirrors iOS's user-visible error string when the API throws.
  static const String _fallbackReply =
      "I'm having trouble connecting. Try again in a moment.";

  Future<void> _send() async {
    final app = context.read<AppModel>();
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;

    // Snapshot the prior history BEFORE appending the new user turn —
    // otherwise the LLM sees the just-sent message twice (once in `history`,
    // once as the `prompt`) and tends to echo it back.
    final priorHistory = List<CoachMessage>.from(app.coachMessages);

    app.appendCoach(CoachMessage(role: CoachRole.user, content: trimmed));
    _controller.clear();
    setState(() => _thinking = true);
    _scrollToEnd();

    String reply;
    try {
      reply = await CoachApiClient.send(
        prompt: trimmed,
        history: priorHistory,
        totals: CoachTotals.fromDailyTotals(app.totals),
      );
    } on CoachApiException {
      reply = _fallbackReply;
    } catch (_) {
      // Defensive: any unexpected error still surfaces the canned line
      // rather than the local heuristic — see the file-header note.
      reply = _fallbackReply;
    }

    if (!mounted) return;
    app.appendCoach(
        CoachMessage(role: CoachRole.assistant, content: reply));
    setState(() => _thinking = false);
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
