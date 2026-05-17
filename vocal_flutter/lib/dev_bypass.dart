// Flip `enabled` to true in DEBUG builds to expose "Skip" affordances in
// Onboarding and PaywallSheet that grant Pro entitlement locally without
// auth or StoreKit. Mirrors the iOS DevBypass #if DEBUG guard —
// Release/Profile builds always ship with `enabled = false` so a
// hackathon demo affordance can't leak into the Play Store APK.
//
// IMPORTANT: this is a demo / hackathon affordance, NOT a runtime feature
// flag. There is no remote kill-switch.

import 'package:flutter/foundation.dart';

import 'models/models.dart';

class DevBypass {
  /// Master switch — wraps every Skip CTA in the UI. `kReleaseMode` is
  /// const, so the Dart tree-shaker can strip Skip buttons from the
  /// release bundle entirely; in debug we keep them visible.
  static const bool enabled = !kReleaseMode;

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
