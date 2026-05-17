// Unified camera surface — Flutter port of UnifiedCameraSheet.swift.
//
// One sheet that does two things at once:
//   1. Continuously scans for product barcodes (UPC-A/E, EAN-8/13, Code
//      128/39, QR). When a fresh code resolves, a product card fades in
//      over the live preview. "Log it" drops the meal into AppModel.
//   2. A shutter button captures a still frame and routes it to
//      MealPhotoSheet (prefilledImage:) for AI parsing — reusing the
//      same review + follow-up + save flow as the standalone photo path.
//
// Implementation note: iOS uses a single AVCaptureSession for both
// barcode-metadata and photo-output. Android with mobile_scanner doesn't
// expose a still-capture API, so we hand off briefly to image_picker's
// system camera for the shutter. The user-facing flow is the same —
// aim → snap → review in MealPhotoSheet — just with a momentary native
// camera handoff. Live barcode scanning during preview is identical.
//
// Debounce policy on barcode lookups (so the metadata pipeline can't
// hammer the resolver at video frame rate):
//   - Skip frames while a previous lookup is in flight.
//   - Hold every successfully-resolved code in a 30-second cache.
//   - Cap to ~1 attempted lookup per second across ALL codes.
//   - Medium haptic on each unique detection.
//
// Body-fat photo capture stays in BodyFatPhotoSheet — the two-photo
// + heuristic + vision fallback is body-composition specific and
// isn't a "snap and parse" intent.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/barcode_api.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';
import 'meal_photo_sheet.dart';

Future<void> showUnifiedCameraSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.black,
    barrierColor: Colors.black.withOpacity(0.85),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.96,
      child: UnifiedCameraSheet(),
    ),
  );
}

class UnifiedCameraSheet extends StatefulWidget {
  const UnifiedCameraSheet({super.key});

  @override
  State<UnifiedCameraSheet> createState() => _UnifiedCameraSheetState();
}

class _UnifiedCameraSheetState extends State<UnifiedCameraSheet>
    with WidgetsBindingObserver {
  late final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.qrCode,
    ],
    detectionSpeed: DetectionSpeed.normal,
  );
  final ImagePicker _picker = ImagePicker();

  ParsedMeal? _resolvedMeal;
  String? _lastLookupError;
  bool _cameraUnavailable = false;
  bool _isCapturingPhoto = false;

  /// Debounce gates — same shape as iOS UnifiedCameraController.
  final Map<String, DateTime> _recentlyLookedUp = {};
  DateTime _lastDetectionDispatchAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _lookupInFlight = false;
  static const Duration _dedupeWindow = Duration(seconds: 30);
  static const Duration _minDetectionInterval = Duration(seconds: 1);

  /// Manual fallback shown when the camera errors out (simulator,
  /// denied permission, no hardware). Same role as iOS's
  /// `showingManualEntry`.
  bool _showingManualEntry = false;
  final TextEditingController _manualCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _manualCode.dispose();
    // Async tear-down: dispose() returns a Future on mobile_scanner v5 but
    // we can't await it from a sync override. Plugin serializes its own
    // platform-channel teardown.
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Release the camera while we're backgrounded (drops the green
    // "camera in use" indicator); resume on return.
    if (state == AppLifecycleState.resumed && !_isCapturingPhoto) {
      unawaited(_controller.start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_controller.stop());
    }
  }

  // MARK: - Detection pipeline

  void _onDetect(BarcodeCapture capture) {
    if (_lookupInFlight) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (raw == null || raw.isEmpty) return;
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 14) return;
    final now = DateTime.now();
    // Per-code dedupe: same code within 30s → ignore.
    final last = _recentlyLookedUp[digits];
    if (last != null && now.difference(last) < _dedupeWindow) return;
    // Rate gate: at most one dispatch / sec across all codes.
    if (now.difference(_lastDetectionDispatchAt) < _minDetectionInterval) {
      return;
    }
    _lastDetectionDispatchAt = now;
    HapticFeedback.lightImpact();
    unawaited(_resolveCode(digits));
  }

  Future<void> _resolveCode(String code) async {
    _lookupInFlight = true;
    _recentlyLookedUp[code] = DateTime.now();
    try {
      final result = await BarcodeApi.lookup(code);
      if (!mounted) return;
      setState(() {
        _resolvedMeal = result.meal;
        _lastLookupError = null;
        _manualCode.clear();
      });
    } on BarcodeApiNotFound {
      if (!mounted) return;
      setState(() {
        _lastLookupError =
            'Not in database. Try the shutter to parse the plate.';
      });
      // Don't poison the cache on a hard not-found — let the user re-aim.
      _recentlyLookedUp.remove(code);
    } catch (_) {
      if (!mounted) return;
      setState(() => _lastLookupError = 'Lookup failed.');
      _recentlyLookedUp.remove(code);
    } finally {
      _lookupInFlight = false;
      // Refresh the cache timestamp on completion so we measure from "we
      // finished the round-trip", not "we kicked off" — prevents a slow
      // lookup from being re-fired before it completes.
      _recentlyLookedUp[code] = DateTime.now();
    }
  }

  void _logMeal() {
    final m = _resolvedMeal;
    if (m == null) return;
    context.read<AppModel>().addMeal(MealEntry(
          name: m.name,
          detail: m.detail,
          calories: m.kcal,
          protein: m.proteinG,
          carbs: m.carbsG,
          fat: m.fatG,
          loggedAt: DateTime.now(),
          slot: MealSlot.fromRaw(m.slot),
          source: MealSource.barcode,
        ));
    HapticFeedback.mediumImpact();
    setState(() => _resolvedMeal = null);
    Navigator.of(context).maybePop();
  }

  void _dismissProductCard() {
    setState(() {
      _resolvedMeal = null;
      _lastLookupError = null;
    });
  }

  // MARK: - Photo capture

  Future<void> _capturePhoto() async {
    if (_isCapturingPhoto) return;
    setState(() => _isCapturingPhoto = true);
    HapticFeedback.heavyImpact();
    // Release the live scanner before invoking the system camera so we
    // don't double-claim the device. mobile_scanner restarts cleanly on
    // resume; we also re-arm below as a belt-and-suspenders.
    await _controller.stop();
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (x == null) {
        // User cancelled the system camera — re-arm the scanner and stay.
        setState(() => _isCapturingPhoto = false);
        unawaited(_controller.start());
        return;
      }
      final file = File(x.path);
      final nav = Navigator.of(context);
      // Pop the unified sheet first so the meal-photo sheet's modal
      // doesn't stack on top — cleaner back-stack, single back-press
      // to leave logging entirely.
      nav.maybePop();
      // Defer the new sheet by one microtask so the previous one has
      // finished popping its modal route. Without this we sometimes
      // land on a torn-down BuildContext.
      Future.microtask(() {
        // ignore: use_build_context_synchronously
        showMealPhotoSheet(context, prefilledImage: file);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isCapturingPhoto = false);
      unawaited(_controller.start());
    }
  }

  Future<void> _submitManualCode() async {
    final code = _manualCode.text.trim();
    if (code.isEmpty) return;
    await _resolveCode(code);
  }

  // MARK: - Build

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Stack(
        children: [
          // Live preview / fallback.
          Positioned.fill(child: _previewLayer()),
          // Foreground UI.
          SafeArea(
            child: Column(
              children: [
                _topBar(),
                const Spacer(),
                _reticle(),
                const Spacer(),
                if (_resolvedMeal != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: _productCard(_resolvedMeal!),
                  ),
                ] else if (_showingManualEntry) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                    child: _manualEntryCard(),
                  ),
                ],
                Padding(
                  padding: const EdgeInsets.only(bottom: 28),
                  child: _shutterRow(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewLayer() {
    return MobileScanner(
      controller: _controller,
      onDetect: _onDetect,
      fit: BoxFit.cover,
      errorBuilder: (context, error, _) {
        // The plugin surfaces permission denial / hardware absence here.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_cameraUnavailable) {
            setState(() {
              _cameraUnavailable = true;
              _showingManualEntry = true;
            });
          }
        });
        return Container(
          color: Colors.black,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(24),
          child: Text(
            'Camera unavailable.\nType a barcode below or close to try voice.',
            textAlign: TextAlign.center,
            style: AppType.body(13, color: Palette.smoke),
          ),
        );
      },
    );
  }

  Widget _topBar() {
    final eyebrowText = _cameraUnavailable
        ? 'MANUAL ENTRY'
        : (_resolvedMeal == null ? 'AIM · TAP TO SNAP' : 'PRODUCT FOUND');
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55),
                borderRadius: BorderRadius.circular(40),
                border: Border.all(color: Colors.white.withOpacity(0.18)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.close, size: 13, color: Colors.white),
                  const SizedBox(width: 6),
                  Text('Close',
                      style: AppType.body(13,
                          weight: FontWeight.w600, color: Colors.white)),
                ],
              ),
            ),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(40),
              border: Border.all(color: Colors.white.withOpacity(0.18)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _cameraUnavailable
                        ? Colors.white.withOpacity(0.3)
                        : Colors.greenAccent,
                  ),
                ),
                const SizedBox(width: 8),
                Text(eyebrowText,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.6,
                      color: Colors.white.withOpacity(0.85),
                    )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _reticle() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 260,
          height: 220,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.55),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 18,
              ),
            ],
          ),
        ),
        if (_lastLookupError != null) ...[
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.55),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Text(
              _lastLookupError!,
              style: TextStyle(
                fontSize: 11,
                color: Colors.white.withOpacity(0.85),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _productCard(ParsedMeal meal) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.inkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'BARCODE',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.6,
                  color: Palette.smoke,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: _dismissProductCard,
                child: Container(
                  width: 22,
                  height: 22,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.close,
                    size: 12,
                    color: Colors.white.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            meal.name,
            style: AppType.serif(20,
                weight: FontWeight.w500, color: Colors.white),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${meal.kcal} kcal',
                style: AppType.mono(13,
                    weight: FontWeight.w600, color: Colors.white),
              ),
              const SizedBox(width: 10),
              MacroPill(
                  letter: 'P', value: meal.proteinG, tint: Palette.protein),
              const SizedBox(width: 6),
              MacroPill(
                  letter: 'C', value: meal.carbsG, tint: Palette.carbs),
              const SizedBox(width: 6),
              MacroPill(letter: 'F', value: meal.fatG, tint: Palette.fat),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              GhostButton(
                title: 'Dismiss',
                fullWidth: false,
                onTap: _dismissProductCard,
              ),
              const SizedBox(width: 10),
              VoltageButton(
                title: 'Log it',
                icon: Icons.check,
                fullWidth: false,
                onTap: _logMeal,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _manualEntryCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Palette.inkSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TYPE A BARCODE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              color: Palette.smoke,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualCode,
                  keyboardType: TextInputType.number,
                  style: AppType.body(14, color: Colors.white),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.18)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.18)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.4)),
                    ),
                    filled: true,
                    fillColor: Colors.black.withOpacity(0.5),
                    hintText: '0049000028058',
                    hintStyle: AppType.body(14, color: Palette.smoke),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _submitManualCode,
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Palette.paper,
                  ),
                  child: const Icon(
                    Icons.arrow_forward,
                    size: 18,
                    color: Palette.ink,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _shutterRow() {
    final enabled = !_cameraUnavailable && !_isCapturingPhoto;
    return Center(
      child: Opacity(
        opacity: enabled ? 1 : 0.3,
        child: GestureDetector(
          onTap: enabled ? _capturePhoto : null,
          child: SizedBox(
            width: 78,
            height: 78,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 78,
                  height: 78,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.5),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
