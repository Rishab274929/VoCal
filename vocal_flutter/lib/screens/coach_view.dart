// Voice-first nutrition coach — Flutter port of CoachView.swift.
//
// Replies come from POST /api/coach (CoachApiClient). On network failure we
// show a single canned line — we intentionally do NOT run a local heuristic
// here. The previous local heuristic disagreed with the iOS coach's answers
// for the same prompt + day-state, which led to "the coach lied to me on my
// phone but not my friend's phone" support reports.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/coach_api.dart';
import '../services/tts_api.dart';
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

  // ---------------------------------------------------------------------
  // TTS playback state
  // ---------------------------------------------------------------------

  /// SharedPreferences key — same name as the iOS @AppStorage key so the
  /// settings feels conceptually consistent across platforms (though
  /// preferences are NOT synced between iOS and Android installs).
  static const String _voiceEnabledPrefKey = 'vocal.coachVoiceEnabled';

  /// Local mute toggle. Defaults to true (audio on) to match iOS. Loaded
  /// from SharedPreferences in initState() — the build runs once with
  /// the default before the load completes, which is fine because no
  /// audio plays until the user actually sends a coach turn.
  bool _voiceEnabled = true;

  /// Single AudioPlayer reused across coach turns. just_audio handles
  /// internal source swapping cleanly; creating a fresh player per reply
  /// leaks native resources on Android (we saw the audio session drop
  /// out after ~5 turns during smoke tests).
  late final AudioPlayer _audio = AudioPlayer();

  /// Monotonically-incrementing turn id. Each call to _maybeSpeak() grabs
  /// the next value; if a newer call has moved the counter forward while
  /// the older job is mid-fetch, the older one bails out instead of
  /// playing stale audio over fresh audio. Cleaner than juggling
  /// Future cancellation across the fetch/write/play stages.
  int _ttsRequestSeq = 0;

  /// True while audio is actively playing. Drives the small "speaking…"
  /// row + the pulsing speaker icon. Mirrors VoiceCoachSession.isSpeaking
  /// on iOS so the UX feels uniform.
  bool _isSpeaking = false;

  /// Temp file path most recently used for an mp3. Held so we can unlink
  /// it on dispose / next-reply — Android's temp dir doesn't auto-prune
  /// and 50-200KB of mp3 per turn would build up over a long session.
  String? _lastTempFilePath;

  @override
  void initState() {
    super.initState();
    _loadVoicePref();
    // Drive _isSpeaking from the player's actual state so we catch the
    // moment audio truly stops (not just when the future resolves).
    // ProcessingState.completed is the canonical "finished" signal for
    // just_audio — `playing` alone flips false during buffering too.
    _audio.playerStateStream.listen((state) {
      final speaking = state.playing &&
          state.processingState != ProcessingState.completed &&
          state.processingState != ProcessingState.idle;
      if (mounted && speaking != _isSpeaking) {
        setState(() => _isSpeaking = speaking);
      }
    });
  }

  Future<void> _loadVoicePref() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getBool(_voiceEnabledPrefKey);
      if (stored != null && mounted) {
        setState(() => _voiceEnabled = stored);
      }
    } catch (_) {
      // SharedPreferences shouldn't realistically fail to read, but if it
      // does we just keep the default (audio on).
    }
  }

  Future<void> _toggleVoice() async {
    final next = !_voiceEnabled;
    setState(() => _voiceEnabled = next);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_voiceEnabledPrefKey, next);
    } catch (_) {
      // Best-effort persistence — if this fails the toggle still works
      // for the current session, which is what the user cares about.
    }
    if (!next) {
      // Muting: kill any reply currently in flight or playing so the
      // user isn't stuck listening to the rest of the current sentence.
      _ttsRequestSeq++;
      try {
        await _audio.stop();
      } catch (_) {}
      if (mounted) setState(() => _isSpeaking = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    // Stop + release the audio engine so AudioFocus is released and the
    // native player thread tears down. Without dispose() the process
    // sticks around in the background even after the view is gone.
    _audio.dispose();
    if (_lastTempFilePath != null) {
      try {
        File(_lastTempFilePath!).deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  /// Canned fallback shown on any network/parse failure. Intentionally
  /// generic so the user knows it's a comms problem (not the coach's
  /// opinion). Mirrors iOS's user-visible error string when the API throws.
  static const String _fallbackReply =
      "I'm having trouble connecting. Try again in a moment.";

  /// Fire-and-forget: fetch mp3 bytes for [reply] and play them via
  /// just_audio. Any failure (network, decode, 401, rate-limit) is
  /// silently swallowed — coach must stay usable in text-only mode per
  /// the spec.
  ///
  /// Sequence-tagged so a newer turn fired before we resolve causes the
  /// older job to bail out without touching the player. Without the
  /// sequence guard, "I asked twice in a row" ends with the older reply
  /// playing on top of the newer one (mp3 fetch latency is variable).
  Future<void> _maybeSpeak(String reply) async {
    if (!_voiceEnabled) return;
    final mySeq = ++_ttsRequestSeq;
    Uint8List bytes;
    try {
      bytes = await TtsApiClient.speak(reply);
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[coach.tts] fetch failed: $e');
      }
      return;
    }
    if (mySeq != _ttsRequestSeq) return; // superseded by a newer turn

    // Write to a temp .mp3 file and hand the path to just_audio.
    // setFilePath is simpler + more reliable than wrapping bytes in a
    // custom StreamAudioSource — the latter trips an Android EOF bug on
    // small payloads (<8KB) where the player blocks forever waiting for
    // more data.
    String path;
    try {
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/coach_tts_${DateTime.now().millisecondsSinceEpoch}.mp3');
      await file.writeAsBytes(bytes, flush: true);
      path = file.path;
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[coach.tts] temp write failed: $e');
      }
      return;
    }
    if (mySeq != _ttsRequestSeq) {
      // User fired another turn while we were writing. Clean up the
      // orphaned temp file rather than leaving it for next launch.
      try {
        await File(path).delete();
      } catch (_) {}
      return;
    }

    // Clean up the previous reply's mp3 now that we have a new one to
    // play. Doing it here rather than after play() means the file
    // sticks around long enough for the player to read it.
    final previous = _lastTempFilePath;
    _lastTempFilePath = path;
    if (previous != null) {
      try {
        await File(previous).delete();
      } catch (_) {}
    }

    try {
      await _audio.stop();
      await _audio.setFilePath(path);
      if (mySeq != _ttsRequestSeq) return;
      await _audio.play();
    } catch (e) {
      if (kDebugMode) {
        // ignore: avoid_print
        print('[coach.tts] playback failed: $e');
      }
    }
  }

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

    // Fire TTS after the text bubble is in the thread so the audio and
    // the on-screen reply land together. We don't await — let _maybeSpeak
    // run its fetch+play in the background. The user is free to type the
    // next prompt while audio plays; the sequence guard inside _maybeSpeak
    // makes sure a follow-up turn cancels stale audio cleanly.
    //
    // Don't speak the fallback string — when we couldn't reach the LLM,
    // we almost certainly can't reach the TTS proxy either, and the
    // canned line ("I'm having trouble connecting...") feels uncanny
    // when read aloud as if it were a real coach answer.
    if (reply != _fallbackReply) {
      // ignore: discarded_futures
      _maybeSpeak(reply);
    }
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
                  // Speaker icon — taps toggle coach voice on/off. Pulses
                  // (via AnimatedScale) while audio is actually playing
                  // so the user gets visual confirmation that the toggle
                  // is doing something.
                  GestureDetector(
                    onTap: _toggleVoice,
                    child: AnimatedScale(
                      scale: _isSpeaking ? 1.12 : 1.0,
                      duration: const Duration(milliseconds: 240),
                      curve: Curves.easeInOut,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Palette.hairlineStrong),
                        ),
                        child: Icon(
                          _voiceEnabled
                              ? Icons.volume_up_rounded
                              : Icons.volume_off_rounded,
                          size: 14,
                          color: _voiceEnabled
                              ? Palette.voltage
                              : Palette.smoke,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
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
              if (_isSpeaking && !_thinking)
                Row(children: [
                  const Icon(Icons.graphic_eq,
                      size: 14, color: Palette.voltage),
                  const SizedBox(width: 8),
                  Text('speaking…',
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
