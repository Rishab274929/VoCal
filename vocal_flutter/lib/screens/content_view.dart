// Editorial app shell — Flutter port of ContentView.swift. Custom bottom
// tab bar with an inlined mic; voice / unified-camera / saved-foods /
// food-database / paywall sheets reachable from anywhere.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../sheets/food_database_sheet.dart';
import '../sheets/saved_foods_sheet.dart';
import '../sheets/unified_camera_sheet.dart';
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

  /// Open the voice capture sheet, but gate on the free-tier cap first.
  /// Free users get [AppModel.freeVoiceCapPerDay] voice logs per local day;
  /// once they're past the cap we redirect to the paywall.
  Future<void> _launchVoiceCapture() async {
    final app = context.read<AppModel>();
    final allowed = await app.canLogVoice();
    if (!mounted) return;
    if (!allowed) {
      showPaywallSheet(context);
      return;
    }

    final beforeId = app.lastSavedMeal?.id;
    await showVoiceCaptureSheet(context);
    if (!mounted) return;
    final after = app.lastSavedMeal;
    if (after != null && after.id != beforeId) {
      // Photo and barcode flows don't bump the counter (per iOS: Free
      // tier is unlimited for photo + barcode; only voice is capped).
      await app.recordVoiceLog();
    }
  }

  /// Long-press chooser surfaced from the mic. Three logging surfaces
  /// + cancel. Order matches iOS ContentView.confirmationDialog —
  /// "Take a photo or scan" first because it's the most general path,
  /// "Saved foods" second (most-used after voice), "Food database" last.
  Future<void> _showAddPicker() async {
    final selection = await showModalBottomSheet<_AddChoice>(
      context: context,
      backgroundColor: Palette.ink,
      barrierColor: Colors.black.withOpacity(0.6),
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: Palette.hairlineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Eyebrow('LOG A MEAL'),
                ),
                _AddPickerTile(
                  icon: Icons.camera_alt,
                  title: 'Take a photo or scan',
                  subtitle: 'Camera shutter + live barcode scan in one view.',
                  onTap: () => Navigator.pop(sheetContext, _AddChoice.camera),
                ),
                const SizedBox(height: 8),
                _AddPickerTile(
                  icon: Icons.bookmark_border,
                  title: 'Saved foods',
                  subtitle: 'Re-log something from your recent regulars.',
                  onTap: () => Navigator.pop(sheetContext, _AddChoice.saved),
                ),
                const SizedBox(height: 8),
                _AddPickerTile(
                  icon: Icons.search,
                  title: 'Food database',
                  subtitle: 'Look up by barcode or name.',
                  onTap: () =>
                      Navigator.pop(sheetContext, _AddChoice.database),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext),
                  child: Text('Cancel',
                      style: AppType.body(14, color: Palette.smoke)),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || selection == null) return;
    switch (selection) {
      case _AddChoice.camera:
        await showUnifiedCameraSheet(context);
        break;
      case _AddChoice.saved:
        await showSavedFoodsSheet(context);
        break;
      case _AddChoice.database:
        await showFoodDatabaseSheet(context);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final unifiedCamera = () => showUnifiedCameraSheet(context);
    final screen = switch (_tab) {
      AppTab.today => TodayView(
          onShowVoice: _launchVoiceCapture,
          onShowUnifiedCamera: unifiedCamera,
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
          Positioned.fill(
            child: Column(
              children: [
                Expanded(child: SafeArea(bottom: false, child: screen)),
                EditorialTabBar(
                  selection: _tab,
                  onSelect: (t) => setState(() => _tab = t),
                  onMic: _launchVoiceCapture,
                  onAdd: _showAddPicker,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _AddChoice { camera, saved, database }

class _AddPickerTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _AddPickerTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: cardDecoration(radius: Radii.sm),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Palette.hairlineStrong),
              ),
              child: Icon(icon, size: 18, color: Palette.bone),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: AppType.serif(17, weight: FontWeight.w500)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: AppType.body(12, color: Palette.smoke)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Palette.smoke),
          ],
        ),
      ),
    );
  }
}
