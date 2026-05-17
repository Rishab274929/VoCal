// Editorial onboarding — Flutter port of OnboardingFlow.swift.
// Five steps: pitch → name → body basics → goal → ready → paywall.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../dev_bypass.dart';
import '../services/auth_session.dart';
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
  // Sex tokens mirror iOS: "m", "f", "" (unspecified). Sending "x" would
  // not round-trip with UserProfile.sex semantics consumed elsewhere.
  String _sex = 'm';
  int _heightFeet = 5;
  int _heightInches = 10;
  int _weight = 168;
  double _goalKcal = 2200;

  // Google sign-in row state — only meaningful on the pitch step. Kept
  // here instead of a nested StatefulWidget because the row is the only
  // async-driven part of the pitch and pulling it out would balloon the
  // file with a separate widget for two booleans.
  bool _signingIn = false;
  String? _signInError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Tap handler for the "Continue with Google" button on the pitch step.
  /// On success the prior anon JWT (if any) is sent to the backend so the
  /// user's pre-sign-in meals can be merged into the Google identity.
  /// Pre-fills the name field with Google's display name if we get one.
  Future<void> _signInWithGoogle() async {
    setState(() {
      _signingIn = true;
      _signInError = null;
    });
    try {
      final auth = context.read<AuthSession>();
      await auth.signInWithGoogle();
      if (!mounted) return;
      // Pre-fill the name field if Google gave us one — saves a step.
      // Use the first space-delimited token so "Jane Smith" → "Jane",
      // matching the iOS behavior in OnboardingFlow.swift.
      final dn = auth.displayName;
      if (dn != null && dn.isNotEmpty && _name.text.trim().isEmpty) {
        final first = dn.split(' ').first;
        _name.text = first.isEmpty ? dn : first;
      }
    } on AuthCancelledException {
      // User backed out of the account picker — no error UI.
    } on AuthException catch (e) {
      if (mounted) setState(() => _signInError = e.message);
    } catch (e) {
      if (mounted) setState(() => _signInError = e.toString());
    } finally {
      if (mounted) setState(() => _signingIn = false);
    }
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

  /// Demo-mode bypass — short-circuits the entire onboarding flow and grants
  /// Pro entitlement locally. Gated behind `DevBypass.enabled`; tree-shaken
  /// when that constant is false. Pulls all defaults from
  /// `DevBypass.defaultProfile()` so this and the iOS counterpart stay in
  /// sync without manual coordination.
  ///
  /// We funnel through `completeOnboarding` (rather than `updateProfile`
  /// directly) so the `hasCompletedOnboarding` flag flips and the
  /// `RootView` AnimatedSwitcher cuts straight to `ContentView`. No
  /// imperative Navigator push needed — same path as the regular finish.
  void _skipDemo() {
    final app = context.read<AppModel>();
    final demo = DevBypass.defaultProfile();
    // Preserve any displayName the user already typed on the name step —
    // tapping Skip from later steps shouldn't wipe deliberate input. The
    // pitch step's `_name` is empty so this falls through to "Demo".
    final typed = _name.text.trim();
    if (typed.isNotEmpty) {
      demo.displayName = typed;
    }
    app.completeOnboarding(demo, demo.dailyCalorieGoal);
    // Mirror onto the live profile too — completeOnboarding replaces the
    // profile wholesale, so entitlement = Pro is already set via `demo`.
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Palette.ink,
      // Let the body resize when the keyboard appears so name/goal inputs
      // stay visible.
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 24, 28, 0),
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
                    padding: EdgeInsets.fromLTRB(
                        28,
                        24,
                        28,
                        24 + MediaQuery.of(context).viewInsets.bottom),
                    child: _content(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
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
        const SizedBox(height: 18),
        _googleSignInRow(),
      ],
    );
  }

  /// Sign-in-with-Google row + "Continue as guest" affordance. Matches the
  /// iOS pitch step (see VoCal/OnboardingFlow.swift googleSignInRow).
  ///
  /// Anonymous is the default behavior of bootstrap() — the guest button
  /// here is therefore literally a no-op that advances onboarding. We
  /// surface it explicitly so the user has a clear "I'm staying anon"
  /// signal rather than feeling forced into Google sign-in.
  Widget _googleSignInRow() {
    final auth = context.watch<AuthSession>();
    // Once the user is signed in via Google, replace the row with a
    // confirmation chip so a second tap doesn't trigger another picker.
    if (auth.provider == 'google') {
      return Row(
        children: [
          const Icon(Icons.check_circle,
              size: 14, color: Palette.voltage),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              auth.email != null
                  ? 'Signed in as ${auth.email}'
                  : 'Signed in with Google',
              style: AppType.body(12,
                  weight: FontWeight.w600, color: Palette.ash),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // The button is built inline (rather than reused via VoltageButton)
        // because it needs the inverted bone-on-ink color treatment that
        // matches iOS's Google sign-in chip — VoltageButton would emit the
        // brand voltage chip instead.
        GestureDetector(
          onTap: _signingIn ? null : _signInWithGoogle,
          child: Opacity(
            opacity: _signingIn ? 0.6 : 1.0,
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 18, vertical: 12),
              decoration: BoxDecoration(
                color: Palette.bone,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_signingIn)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Palette.ink),
                    )
                  else
                    const Icon(Icons.g_mobiledata,
                        size: 22, color: Palette.ink),
                  const SizedBox(width: 8),
                  Text(
                      _signingIn
                          ? 'Opening Google…'
                          : 'Continue with Google',
                      style: AppType.body(13,
                          weight: FontWeight.w600,
                          color: Palette.ink)),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        // "Continue as guest" — anon is already the default after
        // bootstrap(), so we just advance to the next step. Naming the
        // button is the point: it makes the choice explicit instead of
        // a silent "I closed the Google chip" path.
        GestureDetector(
          onTap: _signingIn ? null : _advance,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              'Continue as guest',
              textAlign: TextAlign.center,
              style: AppType.body(12,
                  weight: FontWeight.w600, color: Palette.ash),
            ),
          ),
        ),
        if (_signInError != null) ...[
          const SizedBox(height: 6),
          Text(_signInError!,
              style: AppType.body(11,
                  weight: FontWeight.w500, color: Palette.pulse)),
        ],
        const SizedBox(height: 4),
        Text(
            "Optional. Skip and we'll keep your data device-only.",
            style: AppType.body(11, color: Palette.smoke)),
        // Dev-mode demo bypass. Wrapped in `if (DevBypass.enabled)` so the
        // Dart tree-shaker drops this entire branch from a release build
        // where the constant is flipped to false. Visually quiet on
        // purpose — a small smoke-colored text link, NOT a primary CTA —
        // so it can't be mistaken for the real path during a hands-on demo.
        if (DevBypass.enabled) ...[
          const SizedBox(height: 16),
          Center(
            child: GestureDetector(
              onTap: _signingIn ? null : _skipDemo,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                // 24 of bottom-padding ensures the tap target clears the
                // global onboarding footer's CTA — at smaller phone heights
                // the pitch content scrolls and this would otherwise sit
                // directly behind the "Get started" button.
                padding: const EdgeInsets.only(top: 4, bottom: 24),
                child: Text(
                  '› Skip onboarding · demo mode',
                  style: AppType.body(11,
                      weight: FontWeight.w500, color: Palette.smoke),
                ),
              ),
            ),
          ),
        ],
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
          autofocus: true,
          onChanged: (_) => setState(() {}),
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          inputFormatters: [
            // Names are short — guard against runaway paste / cursor stuck
            // bugs from voice input.
            LengthLimitingTextInputFormatter(40),
          ],
          onSubmitted: (_) {
            if (_canAdvance) _advance();
          },
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
              // Tokens MUST mirror iOS: empty string = "Prefer not".
              // BodyFat heuristic + UserProfile JSON checks for "" not "x".
              for (final o in const [
                ('m', 'Male'),
                ('f', 'Female'),
                ('', 'Prefer not')
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
    String fmt(int v) {
      final s = v.toString();
      // Tiny thousands-grouping without pulling intl into onboarding.
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
        buf.write(s[i]);
      }
      return buf.toString();
    }

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
            Text(fmt(_goalKcal.toInt()),
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
