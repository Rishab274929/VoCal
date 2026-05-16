// Editorial onboarding — Flutter port of OnboardingFlow.swift.
// Five steps: pitch → name → body basics → goal → ready → paywall.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';
import 'paywall_sheet.dart';

enum _Step { pitch, name, body, goal, ready }

class OnboardingFlow extends StatefulWidget {
  const OnboardingFlow({super.key});

  @override
  State<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends State<OnboardingFlow> {
  _Step _step = _Step.pitch;
  final _name = TextEditingController();
  String _sex = 'm';
  int _heightFeet = 5;
  int _heightInches = 10;
  int _weight = 168;
  double _goalKcal = 2200;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canAdvance =>
      _step != _Step.name || _name.text.trim().isNotEmpty;

  String get _cta {
    switch (_step) {
      case _Step.pitch:
        return 'Get started';
      case _Step.name:
        return 'Continue';
      case _Step.body:
        return 'Continue';
      case _Step.goal:
        return 'Looks good';
      case _Step.ready:
        return 'Start tracking';
    }
  }

  void _advance() {
    if (_step == _Step.ready) {
      showPaywallSheet(
        context,
        onSubscribe: () {
          context.read<AppModel>().upgradeToPro();
          _finish();
        },
        onSkip: _finish,
      );
      return;
    }
    setState(() => _step = _Step.values[_step.index + 1]);
  }

  void _back() {
    setState(() => _step = _Step.values[
        (_step.index - 1).clamp(0, _Step.values.length - 1)]);
  }

  void _finish() {
    final app = context.read<AppModel>();
    final profile = app.profile.copy();
    profile.displayName =
        _name.text.trim().isEmpty ? profile.displayName : _name.text.trim();
    profile.sex = _sex;
    profile.heightInches = (_heightFeet * 12 + _heightInches).toDouble();
    profile.weightLbs = _weight.toDouble();
    app.completeOnboarding(profile, _goalKcal.toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ink,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Row(
                    children: [
                      for (final s in _Step.values) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 400),
                          curve: Curves.easeOut,
                          width: s == _step ? 28 : 14,
                          height: 3,
                          decoration: BoxDecoration(
                            color: s.index <= _step.index
                                ? Palette.voltage
                                : Palette.hairlineStrong,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      const Spacer(),
                      const VoCalWordmark(),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                    child: _content(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                  child: Row(
                    children: [
                      if (_step != _Step.pitch) ...[
                        Expanded(
                            child: GhostButton(
                                title: 'Back', onTap: _back)),
                        const SizedBox(width: 12),
                      ],
                      Expanded(
                        child: VoltageButton(
                          title: _cta,
                          icon: _step == _Step.ready
                              ? Icons.check
                              : Icons.arrow_forward,
                          enabled: _canAdvance,
                          onTap: _advance,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _content() {
    switch (_step) {
      case _Step.pitch:
        return _pitch();
      case _Step.name:
        return _nameView();
      case _Step.body:
        return _bodyView();
      case _Step.goal:
        return _goalView();
      case _Step.ready:
        return _readyView();
    }
  }

  Widget _pitch() {
    Widget pill(String t) => Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.hairlineStrong),
          ),
          child: Row(
            children: [
              const Icon(Icons.graphic_eq,
                  size: 13, color: Palette.voltage),
              const SizedBox(width: 12),
              Expanded(
                child: Text('“$t”',
                    style: AppType.serif(15, italic: true)),
              ),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('INTRODUCING', color: Palette.pulse),
        const SizedBox(height: 18),
        Text.rich(TextSpan(children: [
          TextSpan(
              text: 'The first calorie tracker that ',
              style: AppType.serif(48, weight: FontWeight.w500)),
          TextSpan(
              text: 'actually listens.',
              style: AppType.serif(48,
                  weight: FontWeight.w500,
                  italic: true,
                  color: Palette.voltage)),
        ])),
        const SizedBox(height: 18),
        Text(
            'Cal AI needs a photo. MyFitnessPal needs you to type. VoCal '
            'just needs you to talk.',
            style: AppType.body(15, color: Palette.ash)),
        const SizedBox(height: 22),
        pill("medium fry from McDonald's"),
        pill('grande iced oat latte from Starbucks'),
        pill('Chipotle bowl, double chicken, guac'),
      ],
    );
  }

  Widget _nameView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('01 · WHO YOU ARE'),
        const SizedBox(height: 18),
        Text('What should I call you?',
            style: AppType.serif(38, weight: FontWeight.w500)),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          style: AppType.serif(24),
          cursorColor: Palette.voltage,
          decoration: InputDecoration(
            hintText: 'Your first name',
            hintStyle: AppType.serif(24, color: Palette.smoke),
            enabledBorder: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Palette.voltage, width: 1.5)),
            focusedBorder: const UnderlineInputBorder(
                borderSide:
                    BorderSide(color: Palette.voltage, width: 1.5)),
          ),
        ),
      ],
    );
  }

  Widget _bodyView() {
    Widget wheel(List<String> items, int value, ValueChanged<int> onChange) {
      return Container(
        height: 96,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.hairlineStrong),
        ),
        child: ListWheelScrollView.useDelegate(
          itemExtent: 32,
          diameterRatio: 1.6,
          physics: const FixedExtentScrollPhysics(),
          controller:
              FixedExtentScrollController(initialItem: value),
          onSelectedItemChanged: onChange,
          childDelegate: ListWheelChildBuilderDelegate(
            childCount: items.length,
            builder: (_, i) => Center(
              child: Text(items[i],
                  style: AppType.body(17, weight: FontWeight.w500)),
            ),
          ),
        ),
      );
    }

    Widget group(String label, Widget child) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Eyebrow(label.toUpperCase()),
            const SizedBox(height: 6),
            child,
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('02 · BODY BASELINE'),
        const SizedBox(height: 18),
        Text("A few numbers, then we're done.",
            style: AppType.serif(32, weight: FontWeight.w500)),
        const SizedBox(height: 22),
        group(
          'Sex',
          Row(
            children: [
              for (final o in const [
                ('m', 'Male'),
                ('f', 'Female'),
                ('x', 'Prefer not')
              ]) ...[
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _sex = o.$1),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _sex == o.$1
                            ? Palette.voltage
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: _sex == o.$1
                                ? Palette.voltage
                                : Palette.hairlineStrong),
                      ),
                      child: Text(o.$2,
                          style: AppType.body(13,
                              weight: FontWeight.w600,
                              color: _sex == o.$1
                                  ? Palette.ink
                                  : Palette.bone)),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        group(
          'Height',
          Row(
            children: [
              Expanded(
                child: wheel(
                    List.generate(4, (i) => "${i + 4}′"),
                    _heightFeet - 4,
                    (i) => setState(() => _heightFeet = i + 4)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: wheel(
                    List.generate(12, (i) => '$i″'),
                    _heightInches,
                    (i) => setState(() => _heightInches = i)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        group(
          'Weight',
          wheel(
              List.generate(231, (i) => '${i + 90} lb'),
              _weight - 90,
              (i) => setState(() => _weight = i + 90)),
        ),
      ],
    );
  }

  Widget _goalView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('03 · YOUR TARGET'),
        const SizedBox(height: 18),
        Text("What's your daily target?",
            style: AppType.serif(32, weight: FontWeight.w500)),
        const SizedBox(height: 22),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text('${_goalKcal.toInt()}',
                style: AppType.serif(88,
                    weight: FontWeight.w500, color: Palette.voltage)),
            const SizedBox(width: 8),
            Text('kcal',
                style: AppType.serif(24,
                    italic: true, color: Palette.smoke)),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: Palette.voltage,
            inactiveTrackColor: Palette.hairlineStrong,
            thumbColor: Palette.voltage,
            overlayColor: Palette.voltage.withOpacity(0.2),
          ),
          child: Slider(
            value: _goalKcal,
            min: 1200,
            max: 4000,
            divisions: 56,
            onChanged: (v) =>
                setState(() => _goalKcal = (v / 50).round() * 50),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('1,200',
                style: AppType.body(11,
                    weight: FontWeight.w600, color: Palette.smoke)),
            Text('4,000',
                style: AppType.body(11,
                    weight: FontWeight.w600, color: Palette.smoke)),
          ],
        ),
        const SizedBox(height: 10),
        Text(
            "You can change this any time. We'll nudge it up on "
            'high-strain days when you connect your Watch or WHOOP.',
            style: AppType.body(13, color: Palette.ash)),
      ],
    );
  }

  Widget _readyView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('04 · READY', color: Palette.voltage),
        const SizedBox(height: 18),
        Text('Try it out.',
            style: AppType.serif(48, weight: FontWeight.w500)),
        const SizedBox(height: 18),
        Text(
            "Tap the mic and say what you ate. We'll log it for you — "
            'restaurant macros included.',
            style: AppType.body(15, color: Palette.ash)),
        const SizedBox(height: 24),
        const Center(
            child: WaveformOrb(isActive: true, tint: Palette.voltage)),
      ],
    );
  }
}
