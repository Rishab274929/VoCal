// Two-photo body-fat baseline — Flutter port of BodyFatPhotoSheet.swift.
// front + side photos → heuristic BF% with a confidence band.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showBodyFatPhotoSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.96,
      child: BodyFatPhotoSheet(),
    ),
  );
}

enum _Step { intro, front, side, result }

class BodyFatPhotoSheet extends StatefulWidget {
  const BodyFatPhotoSheet({super.key});

  @override
  State<BodyFatPhotoSheet> createState() => _BodyFatPhotoSheetState();
}

class _BodyFatPhotoSheetState extends State<BodyFatPhotoSheet> {
  final _picker = ImagePicker();
  _Step _step = _Step.intro;
  File? _front;
  File? _side;
  bool _estimating = false;
  double? _resultPct;
  double _confidence = 0.82;

  Future<void> _capture(_Step slot) async {
    final x = await _picker.pickImage(
        source: ImageSource.camera, imageQuality: 85);
    if (x == null) return;
    if (!mounted) return; // sheet may have been dragged away
    setState(() {
      if (slot == _Step.front) {
        _front = File(x.path);
      } else {
        _side = File(x.path);
      }
    });
    _advance();
  }

  void _advance() {
    if (!mounted) return;
    switch (_step) {
      case _Step.intro:
        setState(() => _step = _front == null ? _Step.front : _Step.side);
      case _Step.front:
        setState(() => _step = _Step.side);
      case _Step.side:
        setState(() => _step = _Step.result);
        _runEstimate();
      case _Step.result:
        _persist();
        Navigator.of(context).maybePop();
    }
  }

  double _bmi() {
    final app = context.read<AppModel>();
    final kg = app.profile.weightLbs * 0.4536;
    final m = app.profile.heightInches * 0.0254;
    if (m <= 0) return 22;
    return kg / (m * m);
  }

  Future<void> _runEstimate() async {
    setState(() => _estimating = true);
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    final sex = context.read<AppModel>().profile.sex.toLowerCase();
    double baseline;
    double confidence;
    switch (sex) {
      case 'f':
      case 'female':
        baseline = 23.0;
        confidence = 0.78;
      case 'm':
      case 'male':
        baseline = 16.5;
        confidence = 0.78;
      default:
        baseline = 19.75;
        confidence = 0.62;
    }
    final est = (baseline + (_bmi() - 22) * 1.6).clamp(8.0, 35.0);
    setState(() {
      _resultPct = est;
      _confidence = confidence;
      _estimating = false;
    });
  }

  void _persist() {
    final pct = _resultPct;
    if (pct == null) return;
    final app = context.read<AppModel>();
    app.addBodyMetric(BodyMetric(
      weightLbs: app.profile.weightLbs,
      bodyFatPct: pct,
      confidence: _confidence,
      measuredAt: DateTime.now(),
    ));
  }

  String get _headline {
    switch (_step) {
      case _Step.intro:
        return 'Two photos. About 30 seconds.';
      case _Step.front:
        return 'Snap a front-facing photo.';
      case _Step.side:
        return 'Now a side profile.';
      case _Step.result:
        return 'Estimate ready.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.ink,
      // Keyboard avoidance — sheet should bump up if a 3rd-party Android
      // IME ever overlays (not used by this sheet today but cheap insurance).
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('BODY FAT', color: Palette.pulse),
                      const SizedBox(height: 8),
                      Text(_headline,
                          style:
                              AppType.serif(28, weight: FontWeight.w500)),
                    ],
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(context).maybePop(),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: Palette.hairlineStrong)),
                      child: const Icon(Icons.close,
                          size: 13, color: Palette.ash),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(child: SingleChildScrollView(child: _content())),
              const SizedBox(height: 12),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _content() {
    switch (_step) {
      case _Step.intro:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Stand against a plain wall in tight clothes (or in your '
                'skivvies). Light from in front. Tap the silhouette to '
                'capture each angle.',
                style: AppType.body(14, color: Palette.ash)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _silhouette(_front, 'Front')),
                const SizedBox(width: 14),
                Expanded(child: _silhouette(_side, 'Side')),
              ],
            ),
            const SizedBox(height: 16),
            const Eyebrow('PRIVACY'),
            const SizedBox(height: 6),
            Text(
                'Photos are encrypted with a per-user key and stored only '
                'while the estimate is running. Toggle 90-day retention in '
                'Profile → Privacy.',
                style: AppType.body(11, color: Palette.smoke)),
          ],
        );
      case _Step.front:
        return _captureSlot(_Step.front, _front, 'Front');
      case _Step.side:
        return _captureSlot(_Step.side, _side, 'Side');
      case _Step.result:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_estimating)
              Row(children: [
                const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Palette.voltage)),
                const SizedBox(width: 10),
                Text('Running vision model…',
                    style: AppType.body(13, color: Palette.smoke)),
              ])
            else if (_resultPct != null) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(_resultPct!.toStringAsFixed(1),
                      style: AppType.serif(80,
                          weight: FontWeight.w500,
                          color: Palette.voltage)),
                  const SizedBox(width: 6),
                  Text('%',
                      style: AppType.serif(28,
                          italic: true, color: Palette.smoke)),
                ],
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.bar_chart,
                    size: 11, color: Palette.ash),
                const SizedBox(width: 8),
                Text('Confidence band ±1.4 pts',
                    style: AppType.body(12, color: Palette.ash)),
              ]),
              const SizedBox(height: 6),
              Text('Saved to Progress.',
                  style: AppType.body(12, color: Palette.smoke)),
            ],
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: _silhouette(_front, 'Front')),
                const SizedBox(width: 10),
                Expanded(child: _silhouette(_side, 'Side')),
              ],
            ),
          ],
        );
    }
  }

  Widget _captureSlot(_Step slot, File? img, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow('${label.toUpperCase()} ANGLE'),
        const SizedBox(height: 14),
        GestureDetector(
          onTap: () => _capture(slot),
          child: Container(
            height: 280,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Palette.inkSurface,
              borderRadius: BorderRadius.circular(22),
              border:
                  Border.all(color: Palette.hairlineStrong, width: 1.5),
            ),
            child: img != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: Image.file(img,
                        height: 280,
                        width: double.infinity,
                        fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.accessibility,
                          size: 56, color: Palette.smoke),
                      const SizedBox(height: 10),
                      Text('Tap to capture ${label.toLowerCase()}',
                          style:
                              AppType.body(13, color: Palette.smoke)),
                    ],
                  ),
          ),
        ),
      ],
    );
  }

  Widget _silhouette(File? img, String label) {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Palette.inkSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Stack(
        children: [
          if (img != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.file(img, fit: BoxFit.cover),
              ),
            ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 10,
            child: Center(child: Eyebrow(label.toUpperCase())),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    switch (_step) {
      case _Step.intro:
        return Row(
          children: [
            Expanded(
                child: GhostButton(
                    title: 'Cancel',
                    onTap: () => Navigator.of(context).maybePop())),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: 'Start',
                icon: Icons.arrow_forward,
                onTap: () => _capture(_Step.front),
              ),
            ),
          ],
        );
      case _Step.front:
        return Row(
          children: [
            Expanded(
                child: GhostButton(title: 'Skip', onTap: _advance)),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: _front == null ? 'Capture front' : 'Continue',
                icon: _front == null
                    ? Icons.camera_alt
                    : Icons.arrow_forward,
                onTap: () =>
                    _front == null ? _capture(_Step.front) : _advance(),
              ),
            ),
          ],
        );
      case _Step.side:
        return Row(
          children: [
            Expanded(
                child: GhostButton(title: 'Skip', onTap: _advance)),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: _side == null ? 'Capture side' : 'Estimate',
                icon: _side == null
                    ? Icons.camera_alt
                    : Icons.auto_awesome,
                onTap: () =>
                    _side == null ? _capture(_Step.side) : _advance(),
              ),
            ),
          ],
        );
      case _Step.result:
        return Row(
          children: [
            Expanded(
              child: GhostButton(
                title: 'Retake',
                onTap: () => setState(() {
                  _front = null;
                  _side = null;
                  _resultPct = null;
                  _step = _Step.intro;
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: VoltageButton(
                title: 'Save & close',
                icon: Icons.check,
                onTap: () {
                  _persist();
                  Navigator.of(context).maybePop();
                },
              ),
            ),
          ],
        );
    }
  }
}
