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
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);

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
