// The killer flow — Flutter port of VoiceCaptureSheet.swift.
// listen → parse → (maybe follow up) → review → save. Tier 0 on-device
// canon → backend → offline fallback.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/mock_data.dart';
import '../models/models.dart';
import '../services/food_canon.dart';
import '../services/offline_fallback.dart';
import '../services/speech_recorder.dart';
import '../services/voice_api.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showVoiceCaptureSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.96,
      child: VoiceCaptureSheet(),
    ),
  );
}

enum _Phase { listening, parsing, followUp, review }

class VoiceCaptureSheet extends StatefulWidget {
  const VoiceCaptureSheet({super.key});

  @override
  State<VoiceCaptureSheet> createState() => _VoiceCaptureSheetState();
}

class _VoiceCaptureSheetState extends State<VoiceCaptureSheet> {
  final _recorder = SpeechRecorder();
  final _transcript = TextEditingController();
  final _followUp = TextEditingController();

  _Phase _phase = _Phase.listening;
  int _promptIndex = 0;
  Timer? _rotator;
  String? _followUpQuestion;
  String _reasoning = '';
  String? _error;
  MealEntry? _parsed;
  bool _userEditing = false;

  @override
  void initState() {
    super.initState();
    _transcript.text = MockData.voicePrompts[_promptIndex];
    _recorder.addListener(_onRecorder);
    _startRotator();
    _startRecording();
  }

  @override
  void dispose() {
    _rotator?.cancel();
    _recorder.removeListener(_onRecorder);
    _recorder.stop();
    _recorder.dispose();
    _transcript.dispose();
    _followUp.dispose();
    super.dispose();
  }

  void _onRecorder() {
    if (!mounted) return;
    if (_phase == _Phase.listening &&
        !_userEditing &&
        _recorder.partialTranscript.isNotEmpty) {
      _transcript.text = _recorder.partialTranscript;
    }
    setState(() {});
  }

  Future<void> _startRecording() async {
    await _recorder.requestAuthorization();
    if (!_recorder.isAuthorized) return;
    try {
      await _recorder.start();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _startRotator() {
    _rotator?.cancel();
    _rotator = Timer.periodic(const Duration(milliseconds: 2600), (_) {
      if (!mounted) return;
      setState(() {
        _promptIndex = (_promptIndex + 1) % MockData.voicePrompts.length;
        if (_phase == _Phase.listening && !_userEditing) {
          _transcript.text = MockData.voicePrompts[_promptIndex];
        }
      });
    });
  }

  Future<void> _parse({String? followUp}) async {
    if (_recorder.isRecording) {
      final f = await _recorder.finish();
      if (!mounted) return;
      if (f.isNotEmpty) _transcript.text = f;
    }
    if (!mounted) return;
    setState(() {
      _error = null;
      _phase = _Phase.parsing;
    });

    final text = _transcript.text.trim();

    // Tier 0: on-device canon (skipped mid-clarification).
    if (followUp == null) {
      final hit = FoodCanon.instance.lookup(text);
      if (hit != null) {
        _reasoning = 'Matched on-device canon (${hit.name}).';
        _applyMeal(hit.asParsedMeal(), text);
        return;
      }
    }

    try {
      // Attach the bearer minted by AuthSession so the backend can route
      // the parse to user-scoped KV cache + rate-limit buckets. Falls back
      // to null when AuthSession hasn't bootstrapped yet (tests, or first
      // launch with no network) — backend's body-fallback path still
      // accepts that.
      final token = await context.read<AppModel>().auth?.currentToken();
      final res = await VoiceApiClient.parseMeal(
          transcript: text,
          followUpAnswer: followUp,
          authToken: token);
      _reasoning = res.reasoning;
      if (res.followUpQuestion != null && res.meal == null) {
        setState(() {
          _followUpQuestion = res.followUpQuestion;
          _phase = _Phase.followUp;
        });
        return;
      }
      if (res.meal == null) {
        setState(() {
          _error = 'No meal returned. Try again.';
          _phase = _Phase.listening;
        });
        return;
      }
      _applyMeal(res.meal!, res.transcript);
    } catch (_) {
      final result =
          OfflineFallback.resolve(text, followUpAnswer: followUp);
      switch (result) {
        case OfflineMeal(:final response):
          if (response.meal != null) {
            _applyMeal(response.meal!, text,
                reasoning: response.reasoning);
          } else {
            setState(() {
              _error = "Couldn't parse. Try re-recording.";
              _phase = _Phase.listening;
            });
          }
        case OfflineFollowUp(:final question, :final reasoning):
          setState(() {
            _followUpQuestion = question;
            _reasoning = reasoning;
            _phase = _Phase.followUp;
          });
        case OfflineMiss():
          final g = OfflineFallback.genericEstimate(text);
          _applyMeal(g.meal!, text, reasoning: g.reasoning);
      }
    }
  }

  void _applyMeal(ParsedMeal raw, String transcript, {String? reasoning}) {
    _parsed = MealEntry(
      name: raw.name,
      detail: raw.detail,
      calories: raw.kcal,
      protein: raw.proteinG,
      carbs: raw.carbsG,
      fat: raw.fatG,
      loggedAt: DateTime.now(),
      slot: MealSlot.fromRaw(raw.slot),
      source: MealSource.fromRaw(raw.source),
    );
    _transcript.text = transcript;
    if (reasoning != null) _reasoning = reasoning;
    setState(() => _phase = _Phase.review);
  }

  String get _eyebrow {
    switch (_phase) {
      case _Phase.listening:
        return 'Listening';
      case _Phase.parsing:
        return 'Parsing';
      case _Phase.followUp:
        return 'One more thing';
      case _Phase.review:
        return "Here's what I caught";
    }
  }

  String get _headline {
    switch (_phase) {
      case _Phase.listening:
        return 'Just say what you ate.';
      case _Phase.parsing:
        return 'Working on it…';
      case _Phase.followUp:
        return 'Quick check';
      case _Phase.review:
        return _parsed?.name ?? 'Meal';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.ink,
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Eyebrow(_eyebrow.toUpperCase(), color: Palette.pulse),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Palette.hairlineStrong)),
                      child: const Icon(Icons.close,
                          size: 14, color: Palette.ash),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(_headline,
                  style: AppType.serif(32, weight: FontWeight.w500)),
              const SizedBox(height: 12),
              Expanded(child: SingleChildScrollView(child: _body())),
              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.listening:
        return _listening();
      case _Phase.parsing:
        return _parsing();
      case _Phase.followUp:
        return _followUpView();
      case _Phase.review:
        return _review();
    }
  }

  Widget _listening() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
            child: WaveformOrb(isActive: true, tint: Palette.pulse)),
        const SizedBox(height: 32),
        const Eyebrow('TRY SAYING'),
        const SizedBox(height: 12),
        Text('“${MockData.voicePrompts[_promptIndex]}”',
            style: AppType.serif(20, italic: true, color: Palette.ash)),
        const SizedBox(height: 24),
        Row(
          children: [
            Eyebrow(
                _recorder.isRecording ? 'LIVE TRANSCRIPT' : 'TRANSCRIPT',
                color: _recorder.isRecording
                    ? Palette.pulse
                    : Palette.smoke),
            if (_recorder.isRecording) ...[
              const SizedBox(width: 6),
              Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                      color: Palette.pulse, shape: BoxShape.circle)),
            ],
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _transcript,
          maxLines: 4,
          minLines: 2,
          style: AppType.body(15),
          onTap: () => _userEditing = true,
          decoration: InputDecoration(
            hintText: 'Type or speak…',
            hintStyle: AppType.body(15, color: Palette.smoke),
            filled: true,
            fillColor: Palette.inkSurface,
            contentPadding: const EdgeInsets.all(14),
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
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: AppType.body(12, color: Palette.pulse)),
        ],
      ],
    );
  }

  Widget _parsing() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Center(
            child: WaveformOrb(isActive: true, tint: Palette.voltage)),
        const SizedBox(height: 28),
        Text(_transcript.text,
            style: AppType.serif(24, italic: true)),
        const SizedBox(height: 20),
        Row(
          children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Palette.voltage)),
            const SizedBox(width: 8),
            Text('Checking restaurant menus + USDA…',
                style: AppType.body(12, color: Palette.smoke)),
          ],
        ),
      ],
    );
  }

  Widget _followUpView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FollowUpQuestionCard(
            question: _followUpQuestion ?? 'Could you clarify?',
            controller: _followUp),
        const SizedBox(height: 24),
        const Eyebrow('WHY?'),
        const SizedBox(height: 8),
        Text(_reasoning.isEmpty
            ? 'Helps lock the macro estimate.'
            : _reasoning,
            style: AppType.body(13, color: Palette.ash)),
      ],
    );
  }

  Widget _review() {
    final m = _parsed;
    if (m == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DisplayNumber(value: m.calories, label: 'calories'),
        const SizedBox(height: 10),
        Text(m.detail, style: AppType.body(14, color: Palette.ash)),
        const SizedBox(height: 16),
        Row(
          children: [
            MacroPill(letter: 'P', value: m.protein, tint: Palette.protein),
            const SizedBox(width: 10),
            MacroPill(letter: 'C', value: m.carbs, tint: Palette.carbs),
            const SizedBox(width: 10),
            MacroPill(letter: 'F', value: m.fat, tint: Palette.fat),
            const Spacer(),
            Text(m.slot.raw.toUpperCase(),
                style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 2,
                    color: Palette.voltage)),
          ],
        ),
        if (_reasoning.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Eyebrow('REASONING'),
          const SizedBox(height: 6),
          Text(_reasoning, style: AppType.body(12, color: Palette.ash)),
        ],
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: cardDecoration(radius: Radii.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('TRANSCRIPT'),
              const SizedBox(height: 6),
              Text(_transcript.text,
                  style: AppType.serif(18, italic: true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    switch (_phase) {
      case _Phase.listening:
      case _Phase.parsing:
        return Row(
          children: [
            Expanded(
                child: GhostButton(
                    title: 'Cancel',
                    onTap: () => Navigator.of(context).maybePop())),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: _phase == _Phase.parsing
                    ? 'Working…'
                    : 'Stop & parse',
                icon: _phase == _Phase.parsing ? null : Icons.stop,
                enabled: _phase != _Phase.parsing,
                onTap: () => _parse(),
              ),
            ),
          ],
        );
      case _Phase.followUp:
        final answered = _followUp.text.trim().isNotEmpty;
        return Row(
          children: [
            Expanded(
              child: GhostButton(
                title: 'Back',
                onTap: () => setState(() {
                  _phase = _Phase.listening;
                  _followUp.clear();
                  _error = null;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: 'Submit',
                icon: Icons.arrow_forward,
                enabled: answered,
                onTap: () => _parse(followUp: _followUp.text),
              ),
            ),
          ],
        );
      case _Phase.review:
        return Row(
          children: [
            Expanded(
              child: GhostButton(
                title: 'Re-record',
                icon: Icons.refresh,
                onTap: () {
                  _userEditing = false;
                  _transcript.clear();
                  _parsed = null;
                  _reasoning = '';
                  setState(() => _phase = _Phase.listening);
                  _startRecording();
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: 'Save',
                icon: Icons.check,
                onTap: () {
                  final m = _parsed;
                  if (m == null) return;
                  context.read<AppModel>().addMeal(m);
                  Navigator.of(context).maybePop();
                },
              ),
            ),
          ],
        );
    }
  }
}
