// Editorial profile — Flutter port of ProfileView.swift.

import 'package:flutter/material.dart';
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
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
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
                  child: _statTile('Daily kcal', '${p.dailyCalorieGoal}')),
              const SizedBox(width: 10),
              Expanded(
                  child:
                      _statTile('Weight', '${p.weightLbs.toInt()} lb')),
              const SizedBox(width: 10),
              Expanded(
                  child: _statTile('Height', _height(p.heightInches))),
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

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(radius: Radii.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow(label.toUpperCase()),
          const SizedBox(height: 6),
          Text(value, style: AppType.serif(20, weight: FontWeight.w500)),
        ],
      ),
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
