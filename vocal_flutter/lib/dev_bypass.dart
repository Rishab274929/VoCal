// Flip `enabled` to false before Play Store submission. When true, the
// app shows "Skip" buttons in Onboarding and PaywallSheet that grant
// Pro entitlement locally without auth or StoreKit. Mirrors the iOS
// DevBypass shim — same field names, same defaults.
//
// IMPORTANT: this is a demo / hackathon affordance, NOT a runtime feature
// flag. Toggling it requires a rebuild; there is no remote kill-switch.
// Production releases MUST ship with `enabled = false`.

import 'models/models.dart';

class DevBypass {
  /// Master switch — wraps every Skip CTA in the UI. Set false before
  /// submitting to the Play Store; the constness lets Dart's tree-shaker
  /// strip the Skip buttons from the release bundle.
  static const bool enabled = true;

  /// Default Pro profile used when the user taps Skip. Values mirror the
  /// iOS DevBypass.defaultProfile() so a demo built on either platform
  /// behaves the same — ~average male adult, 2200 kcal target.
  ///
  /// NOTE: UserProfile.heightInches is declared as double on this branch
  /// (see models.dart:212) — pass numeric literals as `.0` to avoid a
  /// silent int→double widening warning on stricter analyzer modes.
  static UserProfile defaultProfile() {
    return UserProfile(
      displayName: 'Demo',
      streakDays: 0,
      sex: '',
      heightInches: 68.0,
      weightLbs: 165.0,
      birthYear: 1995,
      dailyCalorieGoal: 2200,
      entitlement: Entitlement.pro,
    );
  }
}
