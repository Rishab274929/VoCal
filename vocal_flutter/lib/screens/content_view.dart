// Editorial app shell — Flutter port of ContentView.swift. Custom bottom
// tab bar with a floating mic; voice / photo / paywall sheets reachable
// from anywhere.

import 'package:flutter/material.dart';

import '../sheets/meal_photo_sheet.dart';
import '../sheets/voice_capture_sheet.dart';
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
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          Positioned.fill(child: SafeArea(bottom: false, child: screen)),
          Align(
            alignment: Alignment.bottomCenter,
            child: EditorialTabBar(
              selection: _tab,
              onSelect: (t) => setState(() => _tab = t),
              onMic: () => showVoiceCaptureSheet(context),
            ),
          ),
        ],
      ),
    );
  }
}
