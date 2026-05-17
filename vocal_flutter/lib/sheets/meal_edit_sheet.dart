// Meal edit sheet — tap an entry on Today's log to open this full-screen
// modal. Editable: name, detail, kcal + macros, slot, and the optional
// micronutrient fields when the parser populated them.
//
// We work on a copy of the original entry until Save — bailing mid-edit
// (Cancel or backswipe) must NOT mutate the model. On Save we call
// AppModel.editMeal which reconciles day totals atomically.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showMealEditSheet(BuildContext context, MealEntry meal) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => FractionallySizedBox(
      heightFactor: 0.96,
      child: MealEditSheet(original: meal),
    ),
  );
}

class MealEditSheet extends StatefulWidget {
  final MealEntry original;
  const MealEditSheet({super.key, required this.original});

  @override
  State<MealEditSheet> createState() => _MealEditSheetState();
}

class _MealEditSheetState extends State<MealEditSheet> {
  late final TextEditingController _name;
  late final TextEditingController _detail;
  late final TextEditingController _kcal;
  late final TextEditingController _protein;
  late final TextEditingController _carbs;
  late final TextEditingController _fat;
  // Micros — strings so an empty box round-trips to null on save (vs.
  // "0" which would force every micro field to render as a hard zero).
  late final TextEditingController _sodium;
  late final TextEditingController _fiber;
  late final TextEditingController _sugar;
  late final TextEditingController _calcium;
  late final TextEditingController _iron;
  late final TextEditingController _vitC;
  late final TextEditingController _potassium;
  late MealSlot _slot;
  bool _microsOpen = false;

  @override
  void initState() {
    super.initState();
    final m = widget.original;
    _name = TextEditingController(text: m.name);
    _detail = TextEditingController(text: m.detail);
    _kcal = TextEditingController(text: '${m.calories}');
    _protein = TextEditingController(text: '${m.protein}');
    _carbs = TextEditingController(text: '${m.carbs}');
    _fat = TextEditingController(text: '${m.fat}');
    _sodium = TextEditingController(text: m.sodiumMg?.toString() ?? '');
    _fiber = TextEditingController(text: m.fiberG?.toString() ?? '');
    _sugar = TextEditingController(text: m.sugarG?.toString() ?? '');
    _calcium = TextEditingController(text: m.calciumMg?.toString() ?? '');
    _iron = TextEditingController(text: m.ironMg?.toString() ?? '');
    _vitC = TextEditingController(text: m.vitaminCMg?.toString() ?? '');
    _potassium = TextEditingController(text: m.potassiumMg?.toString() ?? '');
    _slot = m.slot;
    // Auto-expand the micros panel when the original has any populated —
    // hiding values behind a tap on edit would surprise a user who
    // remembers seeing the field on Today.
    _microsOpen = m.hasAnyMicros;
  }

  @override
  void dispose() {
    _name.dispose();
    _detail.dispose();
    _kcal.dispose();
    _protein.dispose();
    _carbs.dispose();
    _fat.dispose();
    _sodium.dispose();
    _fiber.dispose();
    _sugar.dispose();
    _calcium.dispose();
    _iron.dispose();
    _vitC.dispose();
    _potassium.dispose();
    super.dispose();
  }

  int _intOr(String s, int fallback) {
    final v = int.tryParse(s.trim());
    return v == null || v < 0 ? fallback : v;
  }

  int? _intOrNull(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null || v < 0) return null;
    return v;
  }

  void _save() {
    final m = widget.original;
    final updated = MealEntry(
      id: m.id, // preserve identity — totals reconciliation in editMeal
      // keys off this.
      name: _name.text.trim().isEmpty ? m.name : _name.text.trim(),
      detail: _detail.text.trim(),
      calories: _intOr(_kcal.text, m.calories),
      protein: _intOr(_protein.text, m.protein),
      carbs: _intOr(_carbs.text, m.carbs),
      fat: _intOr(_fat.text, m.fat),
      loggedAt: m.loggedAt,
      slot: _slot,
      source: m.source,
      sodiumMg: _intOrNull(_sodium.text),
      fiberG: _intOrNull(_fiber.text),
      sugarG: _intOrNull(_sugar.text),
      calciumMg: _intOrNull(_calcium.text),
      ironMg: _intOrNull(_iron.text),
      vitaminCMg: _intOrNull(_vitC.text),
      potassiumMg: _intOrNull(_potassium.text),
    );
    context.read<AppModel>().editMeal(m, updated);
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
          padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('EDIT MEAL', color: Palette.pulse),
                      const SizedBox(height: 8),
                      Text('Tune the macros.',
                          style: AppType.serif(28, weight: FontWeight.w500)),
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
                      child:
                          const Icon(Icons.close, size: 13, color: Palette.ash),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _labeledField('NAME', _name),
                      const SizedBox(height: 14),
                      _labeledField('DETAIL', _detail, minLines: 1, maxLines: 3),
                      const SizedBox(height: 22),
                      const Eyebrow('SLOT'),
                      const SizedBox(height: 8),
                      _slotPicker(),
                      const SizedBox(height: 22),
                      const Eyebrow('MACROS'),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                              child: _numField(
                                  'KCAL', _kcal, suffix: 'kcal')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _numField('P', _protein, suffix: 'g')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _numField('C', _carbs, suffix: 'g')),
                          const SizedBox(width: 10),
                          Expanded(
                              child: _numField('F', _fat, suffix: 'g')),
                        ],
                      ),
                      const SizedBox(height: 22),
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => _microsOpen = !_microsOpen),
                        child: Row(
                          children: [
                            const Eyebrow('MICROS', color: Palette.pulse),
                            const SizedBox(width: 8),
                            Icon(
                                _microsOpen
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 16,
                                color: Palette.smoke),
                          ],
                        ),
                      ),
                      if (_microsOpen) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child: _numField(
                                    'SODIUM', _sodium, suffix: 'mg')),
                            const SizedBox(width: 10),
                            Expanded(
                                child:
                                    _numField('FIBER', _fiber, suffix: 'g')),
                            const SizedBox(width: 10),
                            Expanded(
                                child:
                                    _numField('SUGAR', _sugar, suffix: 'g')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child: _numField(
                                    'CALCIUM', _calcium, suffix: 'mg')),
                            const SizedBox(width: 10),
                            Expanded(
                                child:
                                    _numField('IRON', _iron, suffix: 'mg')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                                child:
                                    _numField('VIT C', _vitC, suffix: 'mg')),
                            const SizedBox(width: 10),
                            Expanded(
                                child: _numField(
                                    'POTASSIUM', _potassium, suffix: 'mg')),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                      child: GhostButton(
                          title: 'Cancel',
                          onTap: () => Navigator.of(context).maybePop())),
                  const SizedBox(width: 12),
                  Expanded(
                      child: VoltageButton(
                          title: 'Save',
                          icon: Icons.check,
                          onTap: _save)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _labeledField(String label, TextEditingController c,
      {int minLines = 1, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          minLines: minLines,
          maxLines: maxLines,
          style: AppType.body(15),
          decoration: InputDecoration(
            filled: true,
            fillColor: Palette.inkSurface,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: Palette.hairlineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: Palette.hairlineStrong),
            ),
          ),
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController c,
      {String suffix = ''}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Eyebrow(label),
        const SizedBox(height: 6),
        TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: false),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: AppType.mono(14, weight: FontWeight.w600),
          decoration: InputDecoration(
            filled: true,
            fillColor: Palette.inkSurface,
            isDense: true,
            suffixText: suffix.isEmpty ? null : suffix,
            suffixStyle: AppType.body(11, color: Palette.smoke),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: Palette.hairlineStrong),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(Radii.sm),
              borderSide: BorderSide(color: Palette.hairlineStrong),
            ),
          ),
        ),
      ],
    );
  }

  Widget _slotPicker() {
    const slots = MealSlot.values;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in slots)
          GestureDetector(
            onTap: () => setState(() => _slot = s),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                color: _slot == s ? Palette.voltage : Colors.transparent,
                border: Border.all(
                    color: _slot == s
                        ? Palette.voltage
                        : Palette.hairlineStrong),
              ),
              child: Text(s.raw.toUpperCase(),
                  style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                      color: _slot == s ? Palette.ink : Palette.bone)),
            ),
          ),
      ],
    );
  }
}
