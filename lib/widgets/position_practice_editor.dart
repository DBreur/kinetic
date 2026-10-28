// position_practice_editor.dart — bij een techniek aanvinken vanuit welke
// positie(s) je hem hebt geoefend (bv. armklem vanuit mount en turtle), en
// per positie hoe het ging: sterren, aantal, wat goed ging en wat beter kan.
// Gedeeld door de live sambo-sessie en het achteraf bewerken.

import 'package:flutter/material.dart';

import '../core/positions.dart';
import '../models/training_session.dart';
import '../theme/kinetic_theme.dart';
import 'block_widgets.dart';
import 'kinetic.dart';

class PositionPracticeEditor extends StatelessWidget {
  const PositionPracticeEditor({
    super.key,
    required this.value,
    required this.onChanged,
    this.suggested = const [],
  });

  /// De aangevinkte posities met hun beoordeling.
  final List<PositionPractice> value;
  final ValueChanged<List<PositionPractice>> onChanged;

  /// De vaste posities van deze techniek (uit de catalogus); leeg = alle
  /// grondposities als keuze.
  final List<String> suggested;

  List<String> get _choices {
    final base = suggested.isNotEmpty ? suggested : kGroundPositions;
    return [
      ...base,
      // Al aangevinkte posities die niet in de standaardlijst staan.
      for (final p in value)
        if (!base.contains(p.position)) p.position,
    ];
  }

  PositionPractice? _find(String position) {
    for (final p in value) {
      if (p.position == position) return p;
    }
    return null;
  }

  void _toggle(String position) {
    final existing = _find(position);
    onChanged(
      existing == null
          ? [...value, PositionPractice(position: position)]
          : [
              for (final p in value)
                if (p.position != position) p,
            ],
    );
  }

  void _update(PositionPractice next) => onChanged([
    for (final p in value) p.position == next.position ? next : p,
  ]);

  Future<void> _addOther(BuildContext context) async {
    final all = [
      ...kGroundPositions,
      ...kPositions,
    ].where((p) => !_choices.contains(p)).toList();
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
              child: Text('Andere positie', style: AppText.cardTitle),
            ),
            for (final p in all)
              ListTile(title: Text(p), onTap: () => Navigator.pop(c, p)),
          ],
        ),
      ),
    );
    if (picked != null) {
      onChanged([...value, PositionPractice(position: picked)]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const KLabel('Vanuit welke positie(s)?'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final p in _choices)
              FilterChip(
                label: Text(p),
                selected: _find(p) != null,
                onSelected: (_) => _toggle(p),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: const Text('Andere'),
              onPressed: () => _addOther(context),
            ),
          ],
        ),
        for (final p in value) ...[
          const SizedBox(height: 12),
          _PositionCard(
            key: ValueKey(p.position),
            practice: p,
            onChanged: _update,
          ),
        ],
      ],
    );
  }
}

/// Eén aangevinkte positie: sterren, aantal, wat goed ging, wat beter kan.
class _PositionCard extends StatelessWidget {
  const _PositionCard({
    super.key,
    required this.practice,
    required this.onChanged,
  });

  final PositionPractice practice;
  final ValueChanged<PositionPractice> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .04),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColor.lineStrong),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(practice.position, style: AppText.bodyStrong),
          const SizedBox(height: 8),
          StarRow(
            rating: practice.rating,
            onRate: (r) => onChanged(
              practice.copyWith(rating: practice.rating == r ? 0 : r),
            ),
          ),
          const SizedBox(height: 8),
          NumberStepper(
            label: 'AANTAL',
            value: practice.reps,
            suffix: '×',
            onDown: () => onChanged(
              practice.copyWith(reps: (practice.reps - 1).clamp(0, 999)),
            ),
            onUp: () => onChanged(
              practice.copyWith(reps: (practice.reps + 1).clamp(0, 999)),
            ),
          ),
          const SizedBox(height: 8),
          NoteField(
            value: practice.wentWell,
            hint: 'Wat ging goed?',
            onChanged: (v) => onChanged(practice.copyWith(wentWell: v)),
          ),
          const SizedBox(height: 6),
          NoteField(
            value: practice.toImprove,
            hint: 'Wat kan beter?',
            onChanged: (v) => onChanged(practice.copyWith(toImprove: v)),
          ),
        ],
      ),
    );
  }
}
