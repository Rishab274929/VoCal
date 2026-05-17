// Live barcode logging — Flutter port of BarcodeScannerSheet.swift.
//
// Tier 2 logging path: point the rear camera at a UPC/EAN/GTIN code, the
// device decodes it via MLKit (Android) / AVFoundation+Vision (iOS) via the
// `mobile_scanner` plugin, we hit the same `/api/barcode/<code>` Cloudflare
// Worker the iOS app uses, then drop the resolved meal into AppModel.
//
// Behavioral parity with iOS:
//   - Live camera preview with rounded-rect viewfinder + voltage reticle
//   - Digit normalization (strip non-digits, validate 8..14 length)
//   - Medium-impact haptic on detection
//   - "Saved" handoff via appModel.addMeal — same idempotency rules apply
//   - On lookup failure: graceful error + "Try again" / dismiss
//
// Differences vs iOS:
//   - No manual code entry form (per task spec — manual path closes the sheet)
//   - Permission denial surfaces a passive label rather than re-prompting
//     (mobile_scanner handles the OS prompt internally; we just react)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/voice_api.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showBarcodeScannerSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    // Full-screen modal with drag-down dismiss — matches the meal-photo and
    // voice-capture sheets exactly so the iOS-side muscle memory ports over.
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.96,
      child: BarcodeScannerSheet(),
    ),
  );
}

enum _ScanPhase {
  /// Live preview + viewfinder + waiting on a detection.
  scanning,

  /// Detection landed; resolving the meal against the backend.
  resolving,

  /// Resolved successfully — show the meal card with Save/Re-scan CTAs.
  resolved,

  /// Lookup failed (404, network, malformed). Surfaces error + retry.
  failed,
}

class BarcodeScannerSheet extends StatefulWidget {
  const BarcodeScannerSheet({super.key});

  @override
  State<BarcodeScannerSheet> createState() => _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState extends State<BarcodeScannerSheet>
    with WidgetsBindingObserver {
  /// One controller per sheet lifetime — `mobile_scanner` manages the
  /// underlying CameraX/AVCaptureSession internally and surfaces start/stop
  /// via this handle. We restrict formats to the food-barcode subset so QR
  /// codes on shipping labels and the like never trigger a resolver call.
  late final MobileScannerController _controller = MobileScannerController(
    // mobile_scanner v5 exposes a single `itf` (Interleaved 2-of-5) entry
    // that covers ITF-14 too — there's no dedicated GTIN-14 constant. The
    // digit-length gate downstream is what actually enforces 8..14 anyway.
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.itf,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
    ],
    // Normal speed — `unrestricted` fires per-frame on Android, drains
    // battery, and we don't need <100ms latency here.
    detectionSpeed: DetectionSpeed.normal,
  );

  _ScanPhase _phase = _ScanPhase.scanning;
  String? _lastCode;
  ParsedMeal? _resolvedMeal;
  String? _resolvedSource;
  String? _errorMessage;
  bool _permissionDenied = false;
  bool _torchOn = false;

  /// Guards against MLKit re-firing on the same frame while we're still
  /// resolving — mobile_scanner's `normal` detection speed will still emit
  /// 1-3 callbacks before we've called `stop()`.
  bool _isHandlingDetection = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Async tear-down: dispose() returns a Future on mobile_scanner v5 but we
    // can't await it from a sync override. Fire-and-forget — the plugin
    // serializes its own platform-channel teardown so the camera is released
    // before the sheet's animations finish.
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Mirror iOS's viewWillAppear/viewWillDisappear pattern: pause the camera
    // when the app backgrounds so the green "camera in use" indicator drops
    // and resume on foreground. Only does anything in the live scan phase.
    if (_phase != _ScanPhase.scanning) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.start());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      unawaited(_controller.stop());
    }
  }

  // MARK: - Detection pipeline

  void _onDetect(BarcodeCapture capture) {
    if (_isHandlingDetection || _phase != _ScanPhase.scanning) return;
    final raw = capture.barcodes.isNotEmpty
        ? capture.barcodes.first.rawValue
        : null;
    if (raw == null || raw.isEmpty) return;
    // Strip everything that isn't a digit (QR codes can come back as URLs;
    // some Code128 payloads embed prefix chars). Then validate the 8..14
    // window — same gate the backend uses (`/^\d{8,14}$/`).
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 14) return;
    _isHandlingDetection = true;
    HapticFeedback.mediumImpact();
    // Stop the scanner so the preview freezes during the lookup and we don't
    // spend CPU on a stream we'll immediately discard.
    unawaited(_controller.stop());
    _resolve(digits);
  }

  Future<void> _resolve(String code) async {
    setState(() {
      _phase = _ScanPhase.resolving;
      _lastCode = code;
      _errorMessage = null;
    });
    try {
      final result = await _BarcodeApi.lookup(code);
      if (!mounted) return;
      setState(() {
        _resolvedMeal = result.meal;
        _resolvedSource = result.source;
        _phase = _ScanPhase.resolved;
      });
    } on _BarcodeNotFound {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            "Couldn't find that barcode. Try voice or photo logging.";
        _phase = _ScanPhase.failed;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Lookup failed. $e';
        _phase = _ScanPhase.failed;
      });
    }
  }

  void _rescan() {
    setState(() {
      _phase = _ScanPhase.scanning;
      _lastCode = null;
      _resolvedMeal = null;
      _resolvedSource = null;
      _errorMessage = null;
      _isHandlingDetection = false;
    });
    unawaited(_controller.start());
  }

  void _save() {
    final m = _resolvedMeal;
    if (m == null) return;
    final entry = MealEntry(
      name: m.name,
      detail: m.detail,
      calories: m.kcal,
      protein: m.proteinG,
      carbs: m.carbsG,
      fat: m.fatG,
      loggedAt: DateTime.now(),
      slot: MealSlot.fromRaw(m.slot),
      source: MealSource.barcode,
    );
    context.read<AppModel>().addMeal(entry);
    Navigator.of(context).maybePop();
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
      if (!mounted) return;
      setState(() => _torchOn = !_torchOn);
    } catch (_) {
      // Many devices (front cam, simulator) reject torch toggles silently —
      // there's no signal worth surfacing to the user here.
    }
  }

  // MARK: - Build

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
              const SizedBox(height: 20),
              Expanded(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: _body(),
                ),
              ),
              if (_phase == _ScanPhase.resolved ||
                  _phase == _ScanPhase.failed) ...[
                const SizedBox(height: 12),
                _footer(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _header() {
    final title = switch (_phase) {
      _ScanPhase.resolved => _resolvedMeal?.name ?? 'Scanned',
      _ScanPhase.resolving => 'Looking it up…',
      _ScanPhase.failed => 'No match',
      _ScanPhase.scanning => 'Point at the package.',
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('BARCODE', color: Palette.pulse),
              const SizedBox(height: 8),
              Text(
                title,
                style: AppType.serif(28, weight: FontWeight.w500),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Torch toggle — only meaningful in the live scan phase. We render
        // the slot regardless to keep the close button anchored on the right.
        if (_phase == _ScanPhase.scanning && !_permissionDenied)
          GestureDetector(
            onTap: _toggleTorch,
            child: Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _torchOn
                        ? Palette.voltage
                        : Palette.hairlineStrong),
              ),
              child: Icon(
                _torchOn ? Icons.flash_on : Icons.flash_off,
                size: 13,
                color: _torchOn ? Palette.voltage : Palette.ash,
              ),
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

  Widget _body() {
    switch (_phase) {
      case _ScanPhase.scanning:
        return _scannerSection();
      case _ScanPhase.resolving:
        return _resolvingSection();
      case _ScanPhase.resolved:
        return _resultSection(_resolvedMeal!);
      case _ScanPhase.failed:
        return _failedSection();
    }
  }

  Widget _scannerSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('LIVE CAMERA'),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: SizedBox(
            height: 360,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: Palette.inkSurface),
                MobileScanner(
                  controller: _controller,
                  onDetect: _onDetect,
                  // v5 signature: (BuildContext, MobileScannerException,
                  // Widget? child). We don't use the child; the plugin's
                  // default error pane is a black box w/ a white icon, which
                  // wouldn't read on Palette.ink anyway.
                  errorBuilder: (context, error, child) {
                    // The plugin surfaces permission denial here on iOS;
                    // Android typically returns a `notInitialized` if the
                    // user denied at the system dialog.
                    if (!_permissionDenied) {
                      // Defer the state mutation off the build-frame.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) {
                          setState(() => _permissionDenied = true);
                        }
                      });
                    }
                    return Container(
                      alignment: Alignment.center,
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Camera unavailable.\nGrant access in Settings to scan barcodes.',
                        textAlign: TextAlign.center,
                        style: AppType.body(13, color: Palette.smoke),
                      ),
                    );
                  },
                  fit: BoxFit.cover,
                ),
                if (!_permissionDenied) _viewfinderOverlay(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'UPC-A · UPC-E · EAN-8/13 · GTIN-14',
          style: AppType.body(12, color: Palette.smoke),
        ),
      ],
    );
  }

  /// Decorative reticle overlaid on the camera preview. Hairline rounded
  /// rectangle frames the full preview; the voltage-colored inner rect
  /// (~220x96, same as iOS) marks the barcode sweet spot.
  Widget _viewfinderOverlay() {
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dashed outer frame — matches iOS hairlineStrong dashed border.
          CustomPaint(
            painter: _DashedBorderPainter(
              color: Palette.hairlineStrong,
              radius: 22,
              strokeWidth: 1.5,
              dashLength: 6,
              gapLength: 6,
            ),
          ),
          // Voltage reticle.
          Center(
            child: Container(
              width: 220,
              height: 96,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Palette.voltage, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Palette.voltage.withOpacity(0.4),
                    blurRadius: 14,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resolvingSection() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Palette.voltage),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _lastCode == null
                  ? 'Looking it up…'
                  : 'Looking up $_lastCode…',
              style: AppType.body(13, color: Palette.smoke),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultSection(ParsedMeal m) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Serif numerals for kcal — DisplayNumber pulls from AppType.serif,
        // matching the iOS result card.
        DisplayNumber(value: m.kcal, label: 'calories'),
        const SizedBox(height: 18),
        Row(
          children: [
            MacroPill(letter: 'P', value: m.proteinG, tint: Palette.protein),
            const SizedBox(width: 8),
            MacroPill(letter: 'C', value: m.carbsG, tint: Palette.carbs),
            const SizedBox(width: 8),
            MacroPill(letter: 'F', value: m.fatG, tint: Palette.fat),
          ],
        ),
        const SizedBox(height: 14),
        if (m.detail.isNotEmpty)
          Text(m.detail, style: AppType.body(13, color: Palette.ash)),
        if (_resolvedSource != null || _lastCode != null) ...[
          const SizedBox(height: 18),
          const Eyebrow('SOURCE'),
          const SizedBox(height: 6),
          Text(
            _resolvedSource == null
                ? 'Code ${_lastCode ?? ''}'
                : 'Resolved via $_resolvedSource · Code ${_lastCode ?? ''}',
            style: AppType.body(12, color: Palette.smoke),
          ),
        ],
      ],
    );
  }

  Widget _failedSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(
        border: Palette.pulse.withOpacity(0.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('NO MATCH', color: Palette.pulse),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Lookup failed.',
            style: AppType.body(14, color: Palette.bone),
          ),
          if (_lastCode != null) ...[
            const SizedBox(height: 8),
            Text(
              'Code: $_lastCode',
              style: AppType.mono(12, color: Palette.smoke),
            ),
          ],
        ],
      ),
    );
  }

  Widget _footer() {
    if (_phase == _ScanPhase.resolved) {
      return Row(
        children: [
          Expanded(
            child: GhostButton(
              title: 'Scan another',
              icon: Icons.refresh,
              onTap: _rescan,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: VoltageButton(
              title: 'Save meal',
              icon: Icons.check,
              onTap: _save,
            ),
          ),
        ],
      );
    }
    // Failed
    return Row(
      children: [
        Expanded(
          child: GhostButton(
            title: 'Enter manually',
            icon: Icons.edit,
            onTap: () => Navigator.of(context).maybePop(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: VoltageButton(
            title: 'Try again',
            icon: Icons.refresh,
            onTap: _rescan,
          ),
        ),
      ],
    );
  }
}

// MARK: - Backend client
//
// Mirrors iOS BarcodeAPI.swift but trims the OFF direct-from-client fallback
// because the Cloudflare Worker already proxies USDA Branded + OFF on the
// server side. If the worker 404s, the client treats it as definitive — we
// don't have the User-Agent allow-list relationship with OFF that the iOS
// path leans on.

class _BarcodeResult {
  final ParsedMeal meal;
  final String source;
  _BarcodeResult(this.meal, this.source);
}

class _BarcodeNotFound implements Exception {}

class _BarcodeApi {
  /// 8s timeout — matches iOS BarcodeAPI URLRequest.timeoutInterval = 8.
  static const Duration _timeout = Duration(seconds: 8);

  static Future<_BarcodeResult> lookup(String code) async {
    // Normalize defensively in case a caller skipped the digit gate (the
    // backend will 400 on garbage anyway, but a local check is cheaper).
    final digits = code.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 8 || digits.length > 14) {
      throw _BarcodeNotFound();
    }
    final uri = Uri.parse('${ApiConfig.baseUrl}/barcode/$digits');
    final http.Response res;
    try {
      res = await http.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw Exception('Request timed out');
    } on SocketException catch (e) {
      throw Exception('Network unavailable: ${e.message}');
    } on http.ClientException catch (e) {
      throw Exception('HTTP client error: ${e.message}');
    }
    if (res.statusCode == 404) throw _BarcodeNotFound();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('Bad server response (${res.statusCode})');
    }
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Malformed server response');
      }
      // Backend shape: { meal: ParsedMeal, source: string }
      final mealJson = decoded['meal'];
      if (mealJson is! Map<String, dynamic>) {
        throw _BarcodeNotFound();
      }
      final meal = ParsedMeal.fromJson(mealJson);
      final source = (decoded['source'] as String?) ?? 'backend';
      return _BarcodeResult(meal, source);
    } on FormatException catch (e) {
      throw Exception('Malformed server response: ${e.message}');
    }
  }
}

// MARK: - Painters

/// Dashed rounded rectangle border — used for the camera viewfinder frame.
/// Pure CustomPainter so we don't pull in another package for a single line.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final double radius;
  final double strokeWidth;
  final double dashLength;
  final double gapLength;

  _DashedBorderPainter({
    required this.color,
    required this.radius,
    required this.strokeWidth,
    required this.dashLength,
    required this.gapLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dashLength).clamp(0.0, metric.length);
        canvas.drawPath(
          metric.extractPath(distance, next),
          paint,
        );
        distance = next + gapLength;
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.dashLength != dashLength ||
      old.gapLength != gapLength;
}
