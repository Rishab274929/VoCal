// Plain weight entry — Flutter port of WeightEntrySheet.swift.
//
// Surfaces from the Progress tab so a user who just stepped on a scale
// can record the number without invoking the body-fat photo flow (which
// captures BF% and is overkill for a daily weigh-in).
//
// Persists a BodyMetric with `bodyFatPct = null` so the weight chart and
// the BF% chart stay distinct. Profile.weightLbs is updated alongside so
// the calorie-goal recomputation picks up today's number.
//
// Server-sync TODO mirrors iOS: once /api/body/weight ships, POST the
// metric here. Local-only is authoritative for the chart in the meantime.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showWeightEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.55,
      child: WeightEntrySheet(),
    ),
  );
}

class WeightEntrySheet extends StatefulWidget {
  const WeightEntrySheet({super.key});

  @override
  State<WeightEntrySheet> createState() => _WeightEntrySheetState();
}

enum _Units { lb, kg }

extension on _Units {
  String get label => this == _Units.lb ? 'lb' : 'kg';
}

class _WeightEntrySheetState extends State<WeightEntrySheet> {
  /// Raw user input — kept as a string so we can preserve mid-edit state
  /// across unit toggles instead of round-tripping through a double.
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  _Units _units = _Units.lb;
  String? _validationError;
  bool _didPrefill = false;

  @override
  void initState() {
    super.initState();
    // Defer prefill until the first build so we can read AppModel via
    // context.read (init runs before the tree is fully wired).
    WidgetsBinding.instance.addPostFrameCallback((_) => _prefillIfNeeded());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _prefillIfNeeded() {
    if (_didPrefill || !mounted) return;
    _didPrefill = true;
    final app = context.read<AppModel>();
    final lb = app.bodyMetrics.isNotEmpty
        ? app.bodyMetrics.first.weightLbs
        : app.profile.weightLbs;
    if (lb > 0) {
      _controller.text = lb.toStringAsFixed(1);
    }
    _focus.requestFocus();
  }

  void _onUnitsChanged(_Units? next) {
    if (next == null || next == _units) return;
    final value = double.tryParse(_controller.text.replaceAll(',', '.'));
    final prev = _units;
    setState(() => _units = next);
    if (value == null) return;
    // Convert the buffer so the displayed magnitude stays accurate. If
    // parsing failed we leave the raw text alone — user's mid-edit.
    if (prev == _Units.lb && next == _Units.kg) {
      _controller.text = (value * 0.45359237).toStringAsFixed(1);
    } else if (prev == _Units.kg && next == _Units.lb) {
      _controller.text = (value / 0.45359237).toStringAsFixed(1);
    }
  }

  void _save() {
    final trimmed =
        _controller.text.trim().replaceAll(',', '.');
    final value = double.tryParse(trimmed);
    if (value == null) {
      setState(() => _validationError = 'Enter a number.');
      return;
    }
    // Convert to lb (on-device storage unit) before persistence. Clamp
    // to plausible adult range so a typo doesn't anchor the chart.
    final lb = _units == _Units.lb ? value : value / 0.45359237;
    if (lb <= 40 || lb >= 800) {
      setState(() =>
          _validationError = 'Out of range. Double-check the number.');
      return;
    }
    final metric = BodyMetric(
      weightLbs: lb,
      bodyFatPct: null,
      confidence: null,
      measuredAt: DateTime.now(),
    );
    final app = context.read<AppModel>();
    app.addBodyMetric(metric);
    // Keep profile aligned with most-recent measurement so calorie-goal
    // recomputation reflects today's number — otherwise the goal stays
    // anchored to a stale weight.
    app.updateProfile((p) => p.weightLbs = lb);
    HapticFeedback.mediumImpact();
    // TODO(server-sync): once /api/body/weight ships, POST `metric` here
    // so multi-device users see the entry on every install.
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.ink,
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 18),
              _inputBlock(),
              const Spacer(),
              _saveRow(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('LOG WEIGHT', color: Palette.pulse),
              const SizedBox(height: 6),
              Text(
                'What does the scale say?',
                style: AppType.serif(28, weight: FontWeight.w500),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.of(context).maybePop(),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Palette.hairlineStrong),
            ),
            child: const Icon(Icons.close, size: 13, color: Palette.ash),
          ),
        ),
      ],
    );
  }

  Widget _inputBlock() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  focusNode: _focus,
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  style: AppType.serif(56, weight: FontWeight.w500),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    hintText: '0.0',
                    hintStyle: AppType.serif(56,
                        weight: FontWeight.w500, color: Palette.smoke),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                _units.label,
                style: AppType.serif(24,
                    weight: FontWeight.w400,
                    italic: true,
                    color: Palette.smoke),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Two-state segmented toggle. Material's SegmentedButton ships
          // with M3, picks up our colorScheme.primary (paper) cleanly.
          SegmentedButton<_Units>(
            segments: const [
              ButtonSegment(value: _Units.lb, label: Text('LB')),
              ButtonSegment(value: _Units.kg, label: Text('KG')),
            ],
            selected: {_units},
            onSelectionChanged: (s) => _onUnitsChanged(s.first),
            showSelectedIcon: false,
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(
                AppType.body(12, weight: FontWeight.w600),
              ),
            ),
          ),
          if (_validationError != null) ...[
            const SizedBox(height: 10),
            Text(
              _validationError!,
              style: AppType.body(12, color: Palette.pulse),
            ),
          ],
        ],
      ),
    );
  }

  Widget _saveRow() {
    return Row(
      children: [
        Expanded(
          child: GhostButton(
            title: 'Cancel',
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: VoltageButton(
            title: 'Save',
            icon: Icons.check,
            onTap: _save,
          ),
        ),
      ],
    );
  }
}
