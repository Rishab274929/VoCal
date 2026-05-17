// VoCal — the first calorie tracker that actually listens.
// Flutter entry point. Mirrors VoCalApp.swift: load persisted state (or
// empty), gate the main shell on onboarding completion, dark-first.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/content_view.dart';
import 'screens/onboarding_flow.dart';
import 'services/auth_session.dart';
import 'services/coach_api.dart';
import 'services/food_canon.dart';
import 'services/photo_api.dart';
import 'services/tts_api.dart';
import 'state/app_model.dart';
import 'theme/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force light status-bar / nav-bar icons against the ink canvas. Setting
  // both `statusBarBrightness` (iOS) and `statusBarIconBrightness`
  // (Android) here, plus transparent system nav-bar so we render under it
  // edge-to-edge.
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarBrightness: Brightness.dark, // iOS — content behind is dark
    statusBarIconBrightness: Brightness.light, // Android — light glyphs
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Edge-to-edge so our custom tab bar sits flush against the gesture bar.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Load the on-device food canon, the persisted app state, and the auth
  // session in parallel. Auth bootstrap mints an anon JWT on first launch
  // (or refreshes a cached one) so the very first /api/voice/parse call
  // already has a bearer to send. We deliberately await all three so the
  // first frame draws with everything settled (no flash of "signed out"
  // or empty totals).
  final auth = AuthSession();
  await Future.wait<void>([
    FoodCanon.instance.load(),
    auth.bootstrap(),
  ]);
  final appModel = await AppModel.fromPersistedOrEmpty();
  // Inject auth into the model so meal-save flows can attach the bearer
  // without every call site having to look it up via Provider.
  appModel.auth = auth;

  // Cold-launch day rollover. fromPersistedOrEmpty already rolls if the
  // snapshot was written on a prior calendar day, but invoking
  // rolloverIfNewDay here is the explicit lifecycle hook the spec asks
  // for and a defensive no-op when the snapshot is already current.
  appModel.rolloverIfNewDay();

  // Wire pluggable auth-header sources for the coach + photo API clients.
  // They live in their own services file so the API code stays decoupled
  // from AuthSession's concrete API surface — only main.dart imports both.
  CoachApiAuth.tokenLoader = () => auth.currentToken();
  PhotoApiAuth.tokenLoader = () => auth.currentToken();
  TtsApiAuth.tokenLoader = () => auth.currentToken();

  runApp(
    // Multi-provider so widgets can `context.watch<AuthSession>()` to
    // re-render on sign-in / sign-out, independently of AppModel. The
    // AppModel-side reference (above) is the path for non-widget code.
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthSession>.value(value: auth),
        ChangeNotifierProvider<AppModel>.value(value: appModel),
      ],
      child: const VoCalApp(),
    ),
  );
}

class VoCalApp extends StatefulWidget {
  const VoCalApp({super.key});

  @override
  State<VoCalApp> createState() => _VoCalAppState();
}

class _VoCalAppState extends State<VoCalApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Foreground = AppLifecycleState.resumed (covers cold-start-after-bg
    // and the OS-mediated wake-from-lock cases on both Android and iOS).
    // Re-running rolloverIfNewDay here is what catches "user left the app
    // open last night and re-opened it after midnight" — without this the
    // calorie ring would show yesterday's totals until the next save.
    if (state == AppLifecycleState.resumed) {
      // Read the model out of Provider rather than capturing it in initState
      // — that way we don't crash if a future refactor swaps the provider
      // for a riverpod/get_it indirection.
      try {
        context.read<AppModel>().rolloverIfNewDay();
      } catch (_) {
        // Provider not yet attached (very early lifecycle) — safe to skip;
        // the cold-launch path in main() already ran rolloverIfNewDay once.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VoCal',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      // Force dark — iOS uses `.preferredColorScheme(.dark)`. Android Material
      // would otherwise honor the system setting and surface light-mode
      // tweaks (e.g. textfield ripples) underneath our overrides.
      themeMode: ThemeMode.dark,
      darkTheme: buildAppTheme(),
      home: const RootView(),
    );
  }
}

/// Top-level router. Onboarding gates the main shell.
class RootView extends StatelessWidget {
  const RootView({super.key});

  @override
  Widget build(BuildContext context) {
    final completed =
        context.select<AppModel, bool>((m) => m.hasCompletedOnboarding);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 350),
      child: completed
          ? const ContentView(key: ValueKey('content'))
          : const OnboardingFlow(key: ValueKey('onboarding')),
    );
  }
}
