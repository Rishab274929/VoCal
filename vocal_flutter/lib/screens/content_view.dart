// Editorial app shell — Flutter port of ContentView.swift. Custom bottom
// tab bar with an inlined mic; voice / photo / paywall sheets reachable
// from anywhere.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../sheets/meal_photo_sheet.dart';
import '../sheets/voice_capture_sheet.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';
import 'coach_view.dart';
import 'paywall_sheet.dart';
import 'profile_view.dart';
import 'progress_screen.dart';
import 'today_view.dart';

class ContentView extends StatefulWidget {
  const ContentView({super.key});

  @override
  State<ContentView> createState() => _ContentViewState();
}

class _ContentViewState extends State<ContentView> {
  AppTab _tab = AppTab.today;

  /// Keys mirror iOS AppStorage keys verbatim so a future cross-platform
  /// migration of UserDefaults wouldn't surprise users.
  static const _firstPaywallKey = 'vocal.didShowFirstPaywall';

  @override
  void initState() {
    super.initState();
    // Defer one frame so the onboarding fade-out completes before the
    // paywall slides up (matches iOS's 0.8s asyncAfter cadence loosely).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOnboardingPaywall();
    });
  }

  Future<void> _maybeShowOnboardingPaywall() async {
    final app = context.read<AppModel>();
    if (app.profile.entitlement != Entitlement.free) return;
    if (!app.hasCompletedOnboarding) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_firstPaywallKey) ?? false) return;
    await prefs.setBool(_firstPaywallKey, true);

    if (!mounted) return;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;
    showPaywallSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    final screen = switch (_tab) {
      AppTab.today => TodayView(
          onShowVoice: () => showVoiceCaptureSheet(context),
          onShowPhoto: () => showMealPhotoSheet(context),
        ),
      AppTab.progress => const ProgressScreen(),
      AppTab.coach => const CoachView(),
      AppTab.profile =>
        ProfileView(onShowPaywall: () => showPaywallSheet(context)),
    };

    return Scaffold(
      backgroundColor: Palette.ink,
      // Inlined tab bar — no floating overhang, no awkward stacking. The
      // tab bar handles its own bottom safe-area inset so we set
      // bottom: false on the screen's SafeArea.
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          Positioned.fill(
            child: Column(
              children: [
                Expanded(child: SafeArea(bottom: false, child: screen)),
                EditorialTabBar(
                  selection: _tab,
                  onSelect: (t) => setState(() => _tab = t),
                  onMic: () => showVoiceCaptureSheet(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
