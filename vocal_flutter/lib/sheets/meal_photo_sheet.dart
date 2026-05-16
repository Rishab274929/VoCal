// Photo-first logging — Flutter port of CameraCaptureView.swift's
// MealPhotoSheet. Snap/pick → simulated first pass → "Anything underneath
// I can't see?" follow-up → save.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_model.dart';
import '../theme/theme.dart';
import '../widgets/components.dart';

Future<void> showMealPhotoSheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ink,
    barrierColor: Colors.black.withOpacity(0.6),
    builder: (_) => const FractionallySizedBox(
      heightFactor: 0.96,
      child: MealPhotoSheet(),
    ),
  );
}

class MealPhotoSheet extends StatefulWidget {
  const MealPhotoSheet({super.key});

  @override
  State<MealPhotoSheet> createState() => _MealPhotoSheetState();
}

class _MealPhotoSheetState extends State<MealPhotoSheet> {
  final _picker = ImagePicker();
  final _followUp = TextEditingController();

  File? _image;
  bool _parsing = false;
  ParsedMeal? _firstPass;
  String? _followUpQuestion;
  MealEntry? _saved;

  @override
  void dispose() {
    _followUp.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final x = await _picker.pickImage(source: source, imageQuality: 85);
    if (x == null) return;
    if (!mounted) return;
    setState(() => _image = File(x.path));
    await _runFirstPass();
  }

  Future<void> _runFirstPass() async {
    if (!mounted) return;
    setState(() => _parsing = true);
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() {
      _firstPass = ParsedMeal(
        name: 'Layered salad bowl',
        detail: 'Greens, chicken, quinoa, dressing',
        kcal: 520,
        proteinG: 38,
        carbsG: 42,
        fatG: 20,
        slot: 'lunch',
        source: 'photo',
        confidence: 0.7,
      );
      _followUpQuestion = "Anything underneath I can't see?";
      _parsing = false;
    });
  }

  void _answerFollowUp() {
    final base = _firstPass;
    if (base == null) return;
    final a = _followUp.text.toLowerCase();
    final adj = base.copy();
    if (a.contains('quinoa') || a.contains('rice')) {
      adj.kcal += 110;
      adj.carbsG += 22;
      adj.proteinG += 4;
      adj.detail = 'Greens, chicken, quinoa (extra), dressing';
    } else if (a.contains('oil') || a.contains('dressing')) {
      adj.kcal += 90;
      adj.fatG += 10;
    }
    setState(() {
      _firstPass = adj;
      _followUpQuestion = null;
    });
    _commit(adj, MealSource.voicePhoto);
  }

  void _commit(ParsedMeal m, MealSource source) {
    final entry = MealEntry(
      name: m.name,
      detail: m.detail,
      calories: m.kcal,
      protein: m.proteinG,
      carbs: m.carbsG,
      fat: m.fatG,
      loggedAt: DateTime.now(),
      slot: MealSlot.fromRaw(m.slot),
      source: source,
    );
    context.read<AppModel>().addMeal(entry);
    setState(() => _saved = entry);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) Navigator.of(context).maybePop();
    });
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Eyebrow('MEAL PHOTO', color: Palette.pulse),
                      const SizedBox(height: 8),
                      Text(
                          _image == null
                              ? "Snap what's on the plate."
                              : "Here's what I see.",
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
              Expanded(
                child: SingleChildScrollView(
                  child: _image == null ? _chooser() : _preview(),
                ),
              ),
              if (_image != null && _saved == null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: GhostButton(
                        title: 'Retake',
                        icon: Icons.refresh,
                        onTap: () => setState(() {
                          _image = null;
                          _firstPass = null;
                          _followUpQuestion = null;
                          _followUp.clear();
                        }),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: VoltageButton(
                        title:
                            _followUpQuestion == null ? 'Save' : 'Submit',
                        icon: _followUpQuestion == null
                            ? Icons.check
                            : Icons.arrow_forward,
                        enabled: _followUpQuestion == null ||
                            _followUp.text.trim().isNotEmpty,
                        onTap: () {
                          if (_followUpQuestion == null) {
                            if (_firstPass != null) {
                              _commit(_firstPass!, MealSource.photo);
                            }
                          } else {
                            _answerFollowUp();
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chooser() {
    return Column(
      children: [
        Container(
          height: 240,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: Palette.hairlineStrong, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.center_focus_weak,
                  size: 44, color: Palette.voltage),
              const SizedBox(height: 12),
              Text('Photo-first logging',
                  style: AppType.serif(18, weight: FontWeight.w500)),
              const SizedBox(height: 4),
              Text("I'll start with a guess and ask one quick follow-up.",
                  textAlign: TextAlign.center,
                  style: AppType.body(12, color: Palette.smoke)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: GhostButton(
                title: 'Library',
                icon: Icons.photo_library,
                onTap: () => _pick(ImageSource.gallery),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: VoltageButton(
                title: 'Open camera',
                icon: Icons.camera_alt,
                onTap: () => _pick(ImageSource.camera),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _preview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.file(_image!,
              height: 260, width: double.infinity, fit: BoxFit.cover),
        ),
        const SizedBox(height: 16),
        if (_parsing)
          Row(children: [
            const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Palette.voltage)),
            const SizedBox(width: 8),
            Text('Analyzing photo…',
                style: AppType.body(12, color: Palette.smoke)),
          ])
        else if (_saved != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: cardDecoration(
                fill: Palette.voltage.withOpacity(0.08),
                border: Palette.voltage.withOpacity(0.5)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('LOGGED', color: Palette.voltage),
                const SizedBox(height: 6),
                Text(_saved!.name,
                    style: AppType.serif(22, weight: FontWeight.w500)),
                const SizedBox(height: 4),
                Text(
                    '${_saved!.calories} kcal · ${_saved!.protein}P · '
                    '${_saved!.carbs}C · ${_saved!.fat}F',
                    style: AppType.body(13, color: Palette.ash)),
              ],
            ),
          )
        else if (_followUpQuestion != null)
          FollowUpQuestionCard(
              question: _followUpQuestion!, controller: _followUp)
        else if (_firstPass != null)
          _preCard(_firstPass!),
      ],
    );
  }

  Widget _preCard(ParsedMeal m) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('FIRST PASS'),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${m.kcal}',
                  style: AppType.serif(40, weight: FontWeight.w500)),
              const SizedBox(width: 8),
              Text('kcal',
                  style: AppType.serif(16,
                      italic: true, color: Palette.smoke)),
            ],
          ),
          const SizedBox(height: 8),
          Text(m.name, style: AppType.body(15, weight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              MacroPill(letter: 'P', value: m.proteinG, tint: Palette.protein),
              const SizedBox(width: 8),
              MacroPill(letter: 'C', value: m.carbsG, tint: Palette.carbs),
              const SizedBox(width: 8),
              MacroPill(letter: 'F', value: m.fatG, tint: Palette.fat),
            ],
          ),
        ],
      ),
    );
  }
}
