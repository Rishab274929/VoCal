// Editorial profile — Flutter port of ProfileView.swift.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

class ProfileView extends StatelessWidget {
  final VoidCallback onShowPaywall;
  const ProfileView({super.key, required this.onShowPaywall});

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
  }

  String _height(double inches) {
    final total = inches.toInt();
    return "${total ~/ 12}′${total % 12}″";
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppModel>();
    final p = app.profile;
    final isPro = p.entitlement == Entitlement.pro;

    return SingleChildScrollView(
      // iOS uses 28 horizontal everywhere — match it. Bottom is 24 (tab bar
      // is in-flow so we don't need extra clearance for an overhang).
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Eyebrow('YOU', color: Palette.pulse),
              const Spacer(),
              StreakBadge(days: p.streakDays),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Palette.voltage, width: 2),
                ),
                child: Text(
                    _initials(p.displayName.isEmpty ? 'You' : p.displayName),
                    style: AppType.serif(22,
                        weight: FontWeight.w600, italic: true)),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.displayName.isEmpty ? 'You' : p.displayName,
                      style: AppType.serif(28, weight: FontWeight.w500)),
                  const SizedBox(height: 4),
                  Text('Member · ${p.entitlement.name.toUpperCase()}',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.8,
                          color: Palette.smoke)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (isPro)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: cardDecoration(),
              child: Row(
                children: [
                  const Icon(Icons.verified,
                      size: 22, color: Palette.voltage),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('VoCal Pro · active',
                          style: AppType.body(14,
                              weight: FontWeight.w600)),
                      Text('Renews on Dec 12, 2026',
                          style:
                              AppType.body(11, color: Palette.smoke)),
                    ],
                  ),
                  const Spacer(),
                  Text('Manage',
                      style: AppType.body(12,
                          weight: FontWeight.w600,
                          color: Palette.voltage)),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: onShowPaywall,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: cardDecoration(
                    border: Palette.voltage.withOpacity(0.5)),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                          color: Palette.voltage,
                          shape: BoxShape.circle),
                      child: const Icon(Icons.bolt,
                          size: 18, color: Palette.ink),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Upgrade to Pro',
                            style: AppType.body(15,
                                weight: FontWeight.w600)),
                        Text('Unlimited voice logs · 7-day trial',
                            style: AppType.body(11,
                                color: Palette.smoke)),
                      ],
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        size: 16, color: Palette.voltage),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                  child: _statTile(
                      context, 'Daily kcal', '${p.dailyCalorieGoal}',
                      onTap: () => _editKcal(context, p))),
              const SizedBox(width: 10),
              Expanded(
                  child: _statTile(
                      context, 'Weight', '${p.weightLbs.toInt()} lb',
                      onTap: () => _editWeight(context, p))),
              const SizedBox(width: 10),
              Expanded(
                  child: _statTile(
                      context, 'Height', _height(p.heightInches),
                      onTap: () => _editHeight(context, p))),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                  child: _statTile(context, 'Sex', _sexLabel(p.sex),
                      onTap: () => _editSex(context, p))),
              const SizedBox(width: 10),
              Expanded(
                  child: _statTile(
                      context, 'Birth year', '${p.birthYear}',
                      onTap: () => _editBirthYear(context, p))),
            ],
          ),
          const SizedBox(height: 24),

          Container(
            decoration: cardDecoration(),
            child: Column(
              children: [
                _settingRow(Icons.favorite, 'Apple Health', 'Connect',
                    Palette.pulse),
                _divider(),
                _settingRow(Icons.watch, 'Apple Watch', 'Connect',
                    Palette.fat),
                _divider(),
                _settingRow(Icons.notifications, 'Reminders', '3× daily',
                    Palette.carbs),
                _divider(),
                _settingRow(Icons.graphic_eq, 'Voice & language',
                    'English (US)', Palette.voltage),
                _divider(),
                _settingRow(Icons.lock, 'Privacy',
                    'On-device by default', Palette.bone),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Center(
            child: Column(
              children: [
                const VoCalWordmark(),
                const SizedBox(height: 4),
                Text('v1.0 (1) · the first calorie tracker that listens.',
                    style: AppType.body(10, color: Palette.smoke)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _sexLabel(String sex) {
    switch (sex) {
      case 'm':
        return 'Male';
      case 'f':
        return 'Female';
      default:
        return '—';
    }
  }

  Widget _statTile(BuildContext context, String label, String value,
      {VoidCallback? onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: cardDecoration(radius: Radii.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Eyebrow(label.toUpperCase()),
                if (onTap != null) ...[
                  const Spacer(),
                  const Icon(Icons.edit,
                      size: 11, color: Palette.smoke),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(value, style: AppType.serif(20, weight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Edit handlers
  //
  // Each presents a modal bottom sheet with a single numeric/picker field.
  // We call appModel.updateProfile((p) => p.field = value) so persistence
  // + notifyListeners happen exactly once per save.
  // ---------------------------------------------------------------------

  Future<void> _editKcal(BuildContext context, UserProfile p) async {
    final app = context.read<AppModel>();
    final v = await _showNumberEditor(context,
        title: 'Daily kcal goal',
        initial: p.dailyCalorieGoal,
        suffix: 'kcal',
        // 800 lower bound matches iOS — anything lower is medically
        // questionable and probably a typo. 6000 upper is a practical
        // ceiling that still lets bulking lifters log realistic targets.
        min: 800,
        max: 6000);
    if (v == null) return;
    app.updateProfile((p) => p.dailyCalorieGoal = v);
  }

  Future<void> _editWeight(BuildContext context, UserProfile p) async {
    final app = context.read<AppModel>();
    final v = await _showNumberEditor(context,
        title: 'Weight',
        initial: p.weightLbs.toInt(),
        suffix: 'lb',
        min: 60,
        max: 600);
    if (v == null) return;
    app.updateProfile((p) => p.weightLbs = v.toDouble());
  }

  Future<void> _editHeight(BuildContext context, UserProfile p) async {
    final app = context.read<AppModel>();
    final v = await _showNumberEditor(context,
        title: 'Height',
        initial: p.heightInches.toInt(),
        suffix: 'inches',
        min: 36,
        max: 90);
    if (v == null) return;
    app.updateProfile((p) => p.heightInches = v.toDouble());
  }

  Future<void> _editSex(BuildContext context, UserProfile p) async {
    final app = context.read<AppModel>();
    final v = await _showOptionPicker(context,
        title: 'Sex',
        initial: p.sex,
        options: const [
          ('m', 'Male'),
          ('f', 'Female'),
          ('', 'Prefer not to say'),
        ]);
    if (v == null) return;
    app.updateProfile((p) => p.sex = v);
  }

  Future<void> _editBirthYear(BuildContext context, UserProfile p) async {
    final app = context.read<AppModel>();
    final thisYear = DateTime.now().year;
    final v = await _showNumberEditor(context,
        title: 'Birth year',
        initial: p.birthYear,
        suffix: '',
        // 13 = COPPA / app-store minimum; thisYear-110 covers the oldest
        // verified humans alive. Tighter than the iOS slider range but
        // exactly matches what onboarding accepts on Android.
        min: 1900,
        max: thisYear - 13);
    if (v == null) return;
    app.updateProfile((p) => p.birthYear = v);
  }

  Future<int?> _showNumberEditor(BuildContext context,
      {required String title,
      required int initial,
      required String suffix,
      required int min,
      required int max}) {
    final ctrl = TextEditingController(text: '$initial');
    return showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.ink,
      builder: (sheetCtx) {
        return Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(title.toUpperCase(), color: Palette.pulse),
                  const SizedBox(height: 8),
                  Text('Edit $title.',
                      style: AppType.serif(28, weight: FontWeight.w500)),
                  const SizedBox(height: 18),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: false),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: AppType.serif(32, weight: FontWeight.w500),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: Palette.inkSurface,
                      suffixText: suffix.isEmpty ? null : suffix,
                      suffixStyle: AppType.body(13, color: Palette.smoke),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide:
                            BorderSide(color: Palette.hairlineStrong),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        borderSide:
                            BorderSide(color: Palette.hairlineStrong),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('Allowed: $min – $max',
                      style: AppType.body(11, color: Palette.smoke)),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                          child: GhostButton(
                              title: 'Cancel',
                              onTap: () =>
                                  Navigator.of(sheetCtx).pop(null))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: VoltageButton(
                        title: 'Save',
                        icon: Icons.check,
                        onTap: () {
                          final v = int.tryParse(ctrl.text.trim());
                          if (v == null || v < min || v > max) {
                            // Bad input → keep the sheet open so the user
                            // can fix it. Cheaper than popping with the
                            // initial value and silently discarding intent.
                            return;
                          }
                          Navigator.of(sheetCtx).pop(v);
                        },
                      )),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<String?> _showOptionPicker(BuildContext context,
      {required String title,
      required String initial,
      required List<(String, String)> options}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.ink,
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(title.toUpperCase(), color: Palette.pulse),
                const SizedBox(height: 8),
                Text('Choose one.',
                    style: AppType.serif(26, weight: FontWeight.w500)),
                const SizedBox(height: 18),
                for (final opt in options)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(sheetCtx).pop(opt.$1),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        color: opt.$1 == initial
                            ? Palette.voltage.withOpacity(0.12)
                            : Palette.inkSurface,
                        border: Border.all(
                            color: opt.$1 == initial
                                ? Palette.voltage
                                : Palette.hairlineStrong),
                      ),
                      child: Row(
                        children: [
                          Text(opt.$2,
                              style: AppType.body(15,
                                  weight: FontWeight.w600)),
                          const Spacer(),
                          if (opt.$1 == initial)
                            const Icon(Icons.check,
                                size: 16, color: Palette.voltage),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                GhostButton(
                    title: 'Cancel',
                    onTap: () => Navigator.of(sheetCtx).pop(null)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _divider() => Padding(
        padding: const EdgeInsets.only(left: 56),
        child: Container(height: 1, color: Palette.hairline),
      );

  Widget _settingRow(
      IconData icon, String title, String detail, Color tint) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                color: tint.withOpacity(0.14), shape: BoxShape.circle),
            child: Icon(icon, size: 13, color: tint),
          ),
          const SizedBox(width: 14),
          Text(title,
              style: AppType.body(14, weight: FontWeight.w500)),
          const Spacer(),
          Text(detail, style: AppType.body(12, color: Palette.smoke)),
          const SizedBox(width: 6),
          const Icon(Icons.chevron_right,
              size: 14, color: Palette.smoke),
        ],
      ),
    );
  }
}
