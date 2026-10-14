// set_outcome_sheet.dart — bij een set aangeven of hij gelukt is, en waarom
// (niet). Bv. "niet gelukt: schouder deed pijn" of "gelukt, maar laatste 2
// met hulp".

import 'package:flutter/material.dart';

import '../theme/kinetic_theme.dart';
import 'kinetic.dart';

class SetOutcome {
  /// true = gelukt, false = niet gelukt, null = niet aangegeven.
  final bool? completed;
  final String note;
  const SetOutcome(this.completed, this.note);
}

Future<SetOutcome?> showSetOutcomeSheet(
  BuildContext context, {
  required String title,
  bool? completed,
  String note = '',
}) {
  return showModalBottomSheet<SetOutcome>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        _SetOutcomeSheet(title: title, completed: completed, note: note),
  );
}

class _SetOutcomeSheet extends StatefulWidget {
  const _SetOutcomeSheet({
    required this.title,
    required this.completed,
    required this.note,
  });

  final String title;
  final bool? completed;
  final String note;

  @override
  State<_SetOutcomeSheet> createState() => _SetOutcomeSheetState();
}

/// KSegmented kan geen null als waarde tonen, dus een eigen enum.
enum _Choice { done, failed, none }

class _SetOutcomeSheetState extends State<_SetOutcomeSheet> {
  late _Choice _choice = switch (widget.completed) {
    true => _Choice.done,
    false => _Choice.failed,
    null => _Choice.none,
  };
  late final _note = TextEditingController(text: widget.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + insets.viewInsets.bottom + insets.padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: AppText.title),
          const SizedBox(height: 14),
          KSegmented<_Choice>(
            options: const [
              (_Choice.done, 'Gelukt', Icons.check),
              (_Choice.failed, 'Niet gelukt', Icons.close),
              (_Choice.none, 'Geen', null),
            ],
            selected: _choice,
            onChanged: (v) => setState(() => _choice = v),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _note,
            minLines: 2,
            maxLines: 4,
            style: AppText.body,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: switch (_choice) {
                _Choice.failed => 'Waarom niet? Bv. schouder deed pijn',
                _Choice.done => 'Hoe ging het? Bv. laatste 2 met hulp',
                _Choice.none => 'Notitie bij deze set',
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              SetOutcome(switch (_choice) {
                _Choice.done => true,
                _Choice.failed => false,
                _Choice.none => null,
              }, _note.text.trim()),
            ),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
  }
}
