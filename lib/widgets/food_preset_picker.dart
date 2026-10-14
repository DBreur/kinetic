// food_preset_picker.dart — presets kiezen tijdens het loggen, ook als je er
// honderd hebt: gekozen presets bovenaan met +/−, je meest gebruikte als
// chips (één tik = +1), zoeken met de beste treffers eerst, en "Alle
// presets" voor de volledige lijst per letter.

import 'package:flutter/material.dart';

import '../core/food_preset_usage.dart';
import '../core/formatters.dart';
import '../models/food_preset.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic.dart';

class FoodPresetPicker extends StatefulWidget {
  const FoodPresetPicker({
    super.key,
    required this.presets,
    required this.counts,
    required this.onChange,
    this.usage = const {},
  });

  final List<FoodPreset> presets;

  /// Aantal per preset (op [FoodPreset.singular]).
  final Map<String, int> counts;
  final Map<String, int> usage;

  /// +1 of −1 voor één preset.
  final void Function(FoodPreset preset, int delta) onChange;

  @override
  State<FoodPresetPicker> createState() => _FoodPresetPickerState();
}

class _FoodPresetPickerState extends State<FoodPresetPicker> {
  final _search = TextEditingController();

  static const _maxResults = 8;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  FoodPreset? _byName(String singular) {
    for (final p in widget.presets) {
      if (p.singular == singular) return p;
    }
    return null;
  }

  Future<void> _openAll() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AllPresetsSheet(
        presets: widget.presets,
        counts: widget.counts,
        usage: widget.usage,
        onChange: widget.onChange,
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final chosen = [
      for (final e in widget.counts.entries)
        if (e.value > 0 && _byName(e.key) != null) (_byName(e.key)!, e.value),
    ]..sort((a, b) => a.$1.singular.compareTo(b.$1.singular));
    final query = _search.text.trim();
    final frequent = frequentPresets(widget.presets, widget.usage)
        .where((p) => (widget.counts[p.singular] ?? 0) == 0)
        .toList();
    final results = query.isEmpty
        ? const <FoodPreset>[]
        : searchPresets(widget.presets, query, usage: widget.usage)
              .where((p) => (widget.counts[p.singular] ?? 0) == 0)
              .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('PRESETS', style: AppText.overline)),
            TextButton.icon(
              onPressed: _openAll,
              icon: const Icon(Icons.format_list_bulleted, size: 16),
              label: Text('Alle ${widget.presets.length}'),
            ),
          ],
        ),
        if (chosen.isNotEmpty) ...[
          for (final (p, count) in chosen)
            PresetStepperRow(
              preset: p,
              count: count,
              onChange: (d) => widget.onChange(p, d),
              highlighted: true,
            ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _search,
          style: AppText.body,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search, size: 18),
            hintText: 'Zoek een preset…',
            suffixIcon: query.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Wissen',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(_search.clear),
                  ),
          ),
        ),
        const SizedBox(height: 8),
        if (query.isNotEmpty) ...[
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Geen presets gevonden.', style: AppText.caption),
            ),
          for (final p in results.take(_maxResults))
            PresetStepperRow(
              preset: p,
              count: widget.counts[p.singular] ?? 0,
              onChange: (d) => widget.onChange(p, d),
            ),
          if (results.length > _maxResults)
            TextButton(
              onPressed: _openAll,
              child: Text('Nog ${results.length - _maxResults} treffers…'),
            ),
        ] else if (frequent.isNotEmpty) ...[
          const KLabel('Vaak gebruikt'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final p in frequent)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text(
                    '${p.singular} · ${carbsText(p.carbs)}g',
                    style: AppText.caption.copyWith(color: AppColor.ink),
                  ),
                  onPressed: () => widget.onChange(p, 1),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Eén preset met −/aantal/+, compact.
class PresetStepperRow extends StatelessWidget {
  const PresetStepperRow({
    super.key,
    required this.preset,
    required this.count,
    required this.onChange,
    this.highlighted = false,
  });

  final FoodPreset preset;
  final int count;
  final ValueChanged<int> onChange;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final p = preset;
    final sub = [
      '${carbsText(p.carbs)} g KH per stuk',
      if (p.hasUnit) '${p.amountLabel(1)} per stuk',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
      decoration: BoxDecoration(
        color: highlighted ? AppColor.tealWash : AppColor.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    text: count > 0 ? p.label(count) : p.singular,
                    style: AppText.bodyStrong.copyWith(
                      color: highlighted ? AppColor.tealBright : AppColor.ink,
                    ),
                    children: [
                      if (p.hasUnit && count > 0)
                        TextSpan(
                          text: ' (${p.amountLabel(count)})',
                          style: AppText.caption,
                        ),
                    ],
                  ),
                ),
                Text(sub, style: AppText.caption.copyWith(fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Eén minder',
            onPressed: count > 0 ? () => onChange(-1) : null,
            icon: const Icon(Icons.remove, size: 18),
          ),
          SizedBox(
            width: 22,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: AppText.bodyStrong.copyWith(
                color: count > 0 ? AppColor.tealBright : AppColor.inkFaint,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Eén meer',
            onPressed: () => onChange(1),
            icon: const Icon(Icons.add, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Volledige lijst per letter, met zoeken — voor als je bladeren handiger
/// vindt dan zoeken.
class _AllPresetsSheet extends StatefulWidget {
  const _AllPresetsSheet({
    required this.presets,
    required this.counts,
    required this.usage,
    required this.onChange,
  });

  final List<FoodPreset> presets;
  final Map<String, int> counts;
  final Map<String, int> usage;
  final void Function(FoodPreset preset, int delta) onChange;

  @override
  State<_AllPresetsSheet> createState() => _AllPresetsSheetState();
}

class _AllPresetsSheetState extends State<_AllPresetsSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final filtered = query.isEmpty
        ? widget.presets
        : searchPresets(widget.presets, query, usage: widget.usage);
    final groups = groupByLetter(filtered);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: .85,
      maxChildSize: .95,
      builder: (context, scroll) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColor.lineStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text('Alle presets', style: AppText.title),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Klaar'),
                      ),
                    ],
                  ),
                  TextField(
                    controller: _search,
                    style: AppText.body,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: 'Zoek…',
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (groups.isEmpty)
                    Text('Geen presets gevonden.', style: AppText.caption),
                  for (final (letter, items) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(2, 10, 0, 6),
                      child: KLabel(letter, color: AppColor.ice),
                    ),
                    for (final p in items)
                      PresetStepperRow(
                        preset: p,
                        count: widget.counts[p.singular] ?? 0,
                        highlighted: (widget.counts[p.singular] ?? 0) > 0,
                        onChange: (d) {
                          widget.onChange(p, d);
                          setState(() {});
                        },
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
