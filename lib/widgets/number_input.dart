// number_input.dart — een getal zelf typen (bv. 22,5 kg of 12 reps) in
// plaats van met −/+ te tikken. Gedeeld door de live training, de
// schema-editor en het bewerken van een training.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/kinetic_theme.dart';

/// Vraagt een getal. [decimal] = komma toegestaan (gewicht). Geeft null bij
/// annuleren of een ongeldige invoer; komma en punt werken allebei.
Future<double?> showNumberInput(
  BuildContext context, {
  required String title,
  required double initial,
  bool decimal = false,
  String? suffix,
  double min = 0,
  double max = 1000,
}) async {
  String fmt(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString().replaceAll('.', ',');
  final controller = TextEditingController(text: fmt(initial))
    ..selection = TextSelection(
      baseOffset: 0,
      extentOffset: fmt(initial).length,
    );
  double? parse(String text) {
    final v = double.tryParse(text.trim().replaceAll(',', '.'));
    if (v == null || v < min || v > max) return null;
    return decimal ? v : v.roundToDouble();
  }

  final result = await showDialog<double>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title, style: AppText.cardTitle),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
          ),
        ],
        style: AppText.title,
        decoration: InputDecoration(suffixText: suffix),
        onSubmitted: (v) => Navigator.pop(c, parse(v)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Annuleer'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c, parse(controller.text)),
          child: const Text('Opslaan'),
        ),
      ],
    ),
  );
  // Bewust geen controller.dispose(): het venster schuift nog even uit beeld
  // en gebruikt hem dan nog; de garbage collector ruimt hem op.
  return result;
}
