// VoCal — the first calorie tracker that actually listens.
// Flutter entry point. Mirrors VoCalApp.swift: load persisted state (or
// empty), gate the main shell on onboarding completion, dark-first.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'screens/content_view.dart';
import 'screens/onboarding_flow.dart';
import 'services/food_canon.dart';
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

  // Load the on-device food canon and the persisted app state in parallel.
  await FoodCanon.instance.load();
  final appModel = await AppModel.fromPersistedOrEmpty();

  runApp(
    ChangeNotifierProvider.value(
      value: appModel,
      child: const VoCalApp(),
    ),
  );
}

class VoCalApp extends StatelessWidget {
  const VoCalApp({super.key});

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
