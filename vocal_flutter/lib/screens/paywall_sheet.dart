// Hard paywall — Flutter port of PaywallSheet.swift. Purchase flow is a
// sandbox wireframe (callbacks shell RevenueCat behavior).

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showPaywallSheet(
  BuildContext context, {
  VoidCallback? onSubscribe,
  VoidCallback? onSkip,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: onSkip == null,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.95,
      child: PaywallSheet(onSubscribe: onSubscribe, onSkip: onSkip),
    ),
  );
}

class PaywallSheet extends StatefulWidget {
  final VoidCallback? onSubscribe;
  final VoidCallback? onSkip;
  const PaywallSheet({super.key, this.onSubscribe, this.onSkip});

  @override
  State<PaywallSheet> createState() => _PaywallSheetState();
}

class _PaywallSheetState extends State<PaywallSheet> {
  bool _annual = true;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: AmbientBackground()),
        SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Row(
                  children: [
                    const VoCalWordmark(),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Palette.voltage,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('PRO',
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 2,
                              color: Palette.ink)),
                    ),
                    const Spacer(),
                    if (widget.onSkip == null)
                      GestureDetector(
                        onTap: () => Navigator.of(context).maybePop(),
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Palette.hairlineStrong)),
                          child: const Icon(Icons.close,
                              size: 13, color: Palette.ash),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('UPGRADE', color: Palette.pulse),
                      const SizedBox(height: 12),
                      Text.rich(TextSpan(children: [
                        TextSpan(
                            text: 'Track every chain meal. ',
                            style: AppType.serif(36,
                                weight: FontWeight.w500)),
                        TextSpan(
                            text: 'By voice.',
                            style: AppType.serif(36,
                                weight: FontWeight.w500,
                                italic: true,
                                color: Palette.voltage)),
                      ])),
                      const SizedBox(height: 12),
                      Text(
                          'Unlimited voice logging. Restaurant-aware macros. '
                          'Photo fact-check. Body fat from selfies. Apple '
                          'Watch + Live Activity.',
                          style: AppType.body(14, color: Palette.ash)),
                      const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: cardDecoration(),
                        child: Column(
                          children: [
                            _feature(Icons.graphic_eq,
                                'Unlimited voice logs',
                                'Free is 3/day. Pro: unlimited.'),
                            _div(),
                            _feature(Icons.restaurant,
                                'Restaurant intelligence',
                                'Top 25 chains, plus agentic search.'),
                            _div(),
                            _feature(Icons.center_focus_strong,
                                'Photo + voice fact-check',
                                'Snap, answer, log.'),
                            _div(),
                            _feature(Icons.accessibility_new,
                                'BF% from selfies',
                                'Front + side photo, with confidence band.'),
                            _div(),
                            _feature(Icons.watch,
                                'Watch + Live Activity',
                                'Log from your wrist or Dynamic Island.'),
                            _div(),
                            _feature(Icons.forum,
                                'Voice nutrition coach',
                                'Talk to it. It knows your day.'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                              child: _plan(true, '\$39.99', 'year',
                                  'Save 33%')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _plan(
                                  false, '\$4.99', 'month', null)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  children: [
                    VoltageButton(
                      title: _annual
                          ? 'Start free 7-day trial — \$39.99/yr'
                          : 'Subscribe — \$4.99/mo',
                      icon: Icons.lock_open,
                      onTap: () {
                        context.read<AppModel>().upgradeToPro();
                        if (widget.onSubscribe != null) {
                          widget.onSubscribe!();
                        }
                        Navigator.of(context).maybePop();
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('Restore',
                            style:
                                AppType.body(12, color: Palette.smoke)),
                        if (widget.onSkip != null) ...[
                          Text('  ·  ',
                              style: AppType.body(10,
                                  color: Palette.smoke)),
                          GestureDetector(
                            onTap: () {
                              widget.onSkip!();
                              Navigator.of(context).maybePop();
                            },
                            child: Text('Maybe later',
                                style: AppType.body(12,
                                    color: Palette.smoke)),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _div() => Container(height: 1, color: Palette.hairline);

  Widget _feature(IconData icon, String title, String detail) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: Palette.voltage.withOpacity(0.12),
                shape: BoxShape.circle),
            child: Icon(icon, size: 14, color: Palette.voltage),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppType.body(14, weight: FontWeight.w600)),
                Text(detail,
                    style: AppType.body(11, color: Palette.smoke)),
              ],
            ),
          ),
          const Icon(Icons.check, size: 14, color: Palette.voltage),
        ],
      ),
    );
  }

  Widget _plan(bool annual, String price, String per, String? savings) {
    final active = _annual == annual;
    return GestureDetector(
      onTap: () => setState(() => _annual = annual),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Palette.inkSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: active ? Palette.voltage : Palette.hairlineStrong,
              width: active ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(annual ? 'Annual' : 'Monthly',
                    style: AppType.body(12,
                        weight: FontWeight.w600,
                        color: active ? Palette.voltage : Palette.bone)),
                const Spacer(),
                if (savings != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                        color: Palette.voltage,
                        borderRadius: BorderRadius.circular(20)),
                    child: Text(savings,
                        style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1,
                            color: Palette.ink)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(price,
                    style: AppType.serif(28, weight: FontWeight.w500)),
                const SizedBox(width: 2),
                Text('/ $per',
                    style: AppType.body(11, color: Palette.smoke)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
