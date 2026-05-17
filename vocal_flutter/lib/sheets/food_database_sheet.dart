// Lightweight food-database search — Flutter port of FoodDatabaseSheet.swift.
//
// Lets the user paste a UPC/EAN and pull it through the existing barcode
// resolver (USDA Branded → Open Food Facts on the worker side). This is a
// SCAFFOLD: there's no free-text food-name search endpoint yet, so name
// queries surface a "coming soon" hint and suggest the camera/voice path
// instead. The barcode-lookup path is fully wired.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/barcode_api.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showFoodDatabaseSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.85,
      child: FoodDatabaseSheet(),
    ),
  );
}

class FoodDatabaseSheet extends StatefulWidget {
  const FoodDatabaseSheet({super.key});

  @override
  State<FoodDatabaseSheet> createState() => _FoodDatabaseSheetState();
}

class _FoodDatabaseSheetState extends State<FoodDatabaseSheet> {
  final TextEditingController _query = TextEditingController();
  bool _lookingUp = false;
  MealEntry? _lastResult;
  String? _lastError;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  String get _trimmed => _query.text.trim();

  /// True when the query is a plausible barcode (8–14 digits after
  /// stripping whitespace). Routes the same input box to the barcode
  /// API without forcing the user to pick a mode.
  bool get _queryIsCode {
    final t = _trimmed;
    if (t.isEmpty) return false;
    final digitsOnly = t.split('').every(
        (c) => c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39);
    if (!digitsOnly) return false;
    return t.length >= 8 && t.length <= 14;
  }

  Future<void> _runLookup() async {
    final q = _trimmed;
    if (q.isEmpty) return;
    if (_queryIsCode) {
      await _lookupCode(q);
    } else {
      setState(() {
        _lastError = 'Free-text name search is coming soon. For now, '
            'scan the barcode with the camera or describe it via voice.';
        _lastResult = null;
      });
    }
  }

  Future<void> _lookupCode(String code) async {
    setState(() {
      _lookingUp = true;
      _lastError = null;
    });
    try {
      final result = await BarcodeApi.lookup(code);
      if (!mounted) return;
      final meal = MealEntry(
        name: result.meal.name,
        detail: result.meal.detail,
        calories: result.meal.kcal,
        protein: result.meal.proteinG,
        carbs: result.meal.carbsG,
        fat: result.meal.fatG,
        loggedAt: DateTime.now(),
        slot: MealSlot.fromRaw(result.meal.slot),
        source: MealSource.barcode,
      );
      setState(() {
        _lastResult = meal;
        _lastError = null;
        _lookingUp = false;
      });
    } on BarcodeApiNotFound {
      if (!mounted) return;
      setState(() {
        _lastResult = null;
        _lastError = "Couldn't find that code in the food database.";
        _lookingUp = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastResult = null;
        _lastError = 'Lookup failed. $e';
        _lookingUp = false;
      });
    }
  }

  void _logResult() {
    final meal = _lastResult;
    if (meal == null) return;
    context.read<AppModel>().addMeal(meal);
    HapticFeedback.mediumImpact();
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
          padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _header(),
              const SizedBox(height: 16),
              _searchField(),
              const SizedBox(height: 16),
              if (_lookingUp)
                _loadingRow()
              else if (_lastResult != null)
                _resultCard(_lastResult!)
              else if (_lastError != null)
                _errorRow(_lastError!)
              else
                _placeholderHint(),
              const Spacer(),
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
              const Eyebrow('FOOD DATABASE', color: Palette.pulse),
              const SizedBox(height: 6),
              Text(
                'Search by name or barcode.',
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

  Widget _searchField() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.inkSurface,
        borderRadius: BorderRadius.circular(Radii.sm),
        border: Border.all(color: Palette.hairlineStrong),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 14, color: Palette.smoke),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _query,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _runLookup(),
              style: AppType.body(14, color: Palette.bone),
              keyboardType: TextInputType.text,
              autocorrect: false,
              decoration: InputDecoration(
                isCollapsed: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: '"Greek yogurt" or 0049000028058',
                hintStyle: AppType.body(14, color: Palette.smoke),
              ),
            ),
          ),
          GestureDetector(
            onTap: _trimmed.isEmpty ? null : _runLookup,
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 6),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _trimmed.isEmpty
                    ? Palette.hairlineStrong
                    : Palette.paper,
              ),
              child: Icon(
                Icons.arrow_forward,
                size: 16,
                color:
                    _trimmed.isEmpty ? Palette.smoke : Palette.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _loadingRow() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Row(
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: Palette.bone),
          ),
          const SizedBox(width: 10),
          Text(
            'Looking up...',
            style: AppType.body(13, color: Palette.smoke),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(MealEntry meal) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('RESULT'),
          const SizedBox(height: 12),
          Text(
            meal.name,
            style: AppType.serif(22, weight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                '${meal.calories} kcal',
                style: AppType.mono(13, weight: FontWeight.w600),
              ),
              const SizedBox(width: 10),
              MacroPill(letter: 'P', value: meal.protein, tint: Palette.protein),
              const SizedBox(width: 6),
              MacroPill(letter: 'C', value: meal.carbs, tint: Palette.carbs),
              const SizedBox(width: 6),
              MacroPill(letter: 'F', value: meal.fat, tint: Palette.fat),
            ],
          ),
          if (meal.detail.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              meal.detail,
              style: AppType.body(12, color: Palette.smoke),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              GhostButton(
                title: 'Clear',
                fullWidth: false,
                onTap: () {
                  setState(() {
                    _lastResult = null;
                    _lastError = null;
                    _query.clear();
                  });
                },
              ),
              const SizedBox(width: 12),
              VoltageButton(
                title: 'Log it',
                icon: Icons.check,
                fullWidth: false,
                onTap: _logResult,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _errorRow(String err) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Text(
        err,
        style: AppType.body(13, color: Palette.pulse),
      ),
    );
  }

  Widget _placeholderHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Type to search',
            style: AppType.serif(20, weight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            'Paste a UPC/EAN to look it up in the food database. '
            "Free-text name search is rolling out — for now, the camera "
            'shutter or voice still works for foods without a barcode.',
            style: AppType.body(13, color: Palette.smoke),
          ),
        ],
      ),
    );
  }
}
