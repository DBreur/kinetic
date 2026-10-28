// focus_picker.dart — kiezen hoe lang je op een techniek wilt focussen: de
// eerstvolgende training, een aantal trainingen, een periode of tot een
// datum. Gedeeld door het techniekdetail en de live sambo-sessie.

import 'package:flutter/material.dart';

import '../models/technique.dart';
import '../theme/kinetic_theme.dart';
import 'block_widgets.dart' show NumberStepper;

/// De gekozen focus.
class FocusChoice {
  final FocusMode mode;
  final int? trainings;
  final DateTime? until;
  const FocusChoice(this.mode, {this.trainings, this.until});
}

/// Null = geannuleerd. [FocusMode.none] = focus stoppen.
Future<FocusChoice?> showFocusPicker(
  BuildContext context, {
  required Technique technique,
}) async {
  final now = DateTime.now();
  final active = technique.isFocusActive(now);
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Text('Focus op ${technique.name}', style: AppText.title),
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Nu: ${technique.focusLabel}',
                style: AppText.caption.copyWith(color: AppColor.coralSoft),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.skip_next_outlined),
            title: const Text('Eerstvolgende training'),
            onTap: () => Navigator.pop(c, 'next'),
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Een aantal trainingen'),
            subtitle: const Text(
              'Telt af bij elke training waarin je hem oefent',
            ),
            onTap: () => Navigator.pop(c, 'count'),
          ),
          for (final (key, label) in const [
            ('w1', '1 week'),
            ('w2', '2 weken'),
            ('m1', '1 maand'),
          ])
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: Text('Voor $label'),
              onTap: () => Navigator.pop(c, key),
            ),
          ListTile(
            leading: const Icon(Icons.event_outlined),
            title: const Text('Tot een datum'),
            onTap: () => Navigator.pop(c, 'date'),
          ),
          if (active)
            ListTile(
              leading: const Icon(Icons.close, color: AppColor.redBright),
              title: const Text(
                'Focus stoppen',
                style: TextStyle(color: AppColor.redBright),
              ),
              onTap: () => Navigator.pop(c, 'stop'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return null;
  final today = DateTime(now.year, now.month, now.day);
  switch (choice) {
    case 'next':
      return const FocusChoice(FocusMode.next);
    case 'stop':
      return const FocusChoice(FocusMode.none);
    case 'w1':
      return FocusChoice(
        FocusMode.until,
        until: today.add(const Duration(days: 6)),
      );
    case 'w2':
      return FocusChoice(
        FocusMode.until,
        until: today.add(const Duration(days: 13)),
      );
    case 'm1':
      return FocusChoice(
        FocusMode.until,
        until: DateTime(today.year, today.month + 1, today.day - 1),
      );
    case 'date':
      final picked = await showDatePicker(
        context: context,
        initialDate: today.add(const Duration(days: 7)),
        firstDate: today,
        lastDate: today.add(const Duration(days: 366)),
        helpText: 'Focus tot en met',
      );
      return picked == null
          ? null
          : FocusChoice(FocusMode.until, until: picked);
    case 'count':
      var count = technique.focusMode == FocusMode.count
          ? (technique.focusTrainingsLeft ?? 3)
          : 3;
      final result = await showDialog<int>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (c, setState) => AlertDialog(
            title: Text('Aantal trainingen', style: AppText.cardTitle),
            content: NumberStepper(
              label: 'TRAININGEN',
              value: count,
              onDown: () => setState(() => count = (count - 1).clamp(1, 50)),
              onUp: () => setState(() => count = (count + 1).clamp(1, 50)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annuleer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, count),
                child: const Text('OK'),
              ),
            ],
          ),
        ),
      );
      return result == null
          ? null
          : FocusChoice(FocusMode.count, trainings: result);
  }
  return null;
}
