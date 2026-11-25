// food_preset_widgets.dart: voedingspresets kiezen met −/+ (maaltijd-sheet
// en straks het Voeding-menu tijdens een training). Veelgebruikte presets
// staan als snelknop in beeld; de rest zit in een alfabetische, doorzoekbare
// lijst in een eigen sheet, waar je ook presets toevoegt, bewerkt en
// verwijdert. Zo blijft het overzichtelijk, ook met veel presets.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../models/food_preset.dart';
import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';

/// Wordt aangeroepen bij −/+; geeft de nieuwe tellers terug.
typedef PresetDelta = Map<String, int> Function(FoodPreset preset, int delta);

/// "16 g koolh. • 135 g" onder de naam van een preset.
String presetDetail(FoodPreset p) => ['${grams(p.carbs)} g koolh.', if (p.hasUnit) p.amountLabel(1)].join(' • ');

/// Snelknoppen voor veelgebruikte presets + knop naar de volledige lijst.
class PresetQuickPicker extends StatelessWidget {
  const PresetQuickPicker({
    super.key,
    required this.counts,
    required this.onDelta,
    this.training = false,
    this.editable = true,
  });
  final Map<String, int> counts;
  final PresetDelta onDelta;

  /// Trainingspresets i.p.v. maaltijdpresets.
  final bool training;

  /// Presets hier kunnen maken/bewerken (tijdens een training niet: dat
  /// gaat via Instellingen).
  final bool editable;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final all = store.presetsFor(training: training);
    final frequent = store.frequentPresetsFor(training: training);
    // Ook presets die al gekozen zijn maar niet "veelgebruikt" zijn tonen,
    // zodat je ze hier weer kunt verlagen.
    final chosen = all.where((p) => (counts[p.singular] ?? 0) > 0 && !frequent.contains(p));
    final quick = [...frequent, ...chosen];
    final total = counts.values.fold<int>(0, (a, b) => a + b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Eyebrow(training ? 'Trainingspresets' : 'Voedingspresets')),
            if (editable || all.isNotEmpty)
              TextButton.icon(
                onPressed: () => showPresetListSheet(
                  context,
                  counts: counts,
                  onDelta: onDelta,
                  training: training,
                  editable: editable,
                ),
                icon: Icon(Icons.list_alt, size: 18, color: k.accent),
                label: Text(all.isEmpty ? 'Preset maken' : 'Alle presets (${all.length})'),
              ),
          ],
        ),
        if (quick.isEmpty)
          Text(
            all.isEmpty
                ? (training
                      ? 'Nog geen trainingspresets. Maak ze op de Training-pagina → Trainingspresets.'
                      : 'Maak presets zoals "Appel • 16 g" en tel ze hier met −/+.')
                : 'Presets die je vaak gebruikt verschijnen hier als snelknop.',
            style: context.t.caption,
          )
        else
          for (final p in quick)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PresetStepperRow(preset: p, count: counts[p.singular] ?? 0, onDelta: (d) => onDelta(p, d)),
            ),
        if (total > 0 && quick.isNotEmpty)
          Text('$total ${total == 1 ? 'item' : 'items'} gekozen', style: context.t.caption),
      ],
    );
  }
}

/// Eén preset met naam, details en −/aantal/+.
class PresetStepperRow extends StatelessWidget {
  const PresetStepperRow({super.key, required this.preset, required this.count, required this.onDelta, this.onEdit});
  final FoodPreset preset;
  final int count;
  final ValueChanged<int> onDelta;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final active = count > 0;
    return Material(
      color: active ? k.primaryTint : k.well,
      borderRadius: BorderRadius.circular(KRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(KRadius.md),
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      active ? preset.label(count) : preset.singular,
                      style: context.t.bodyStrong,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      active && preset.hasUnit
                          ? '${grams(preset.carbs * count)} g koolh. • ${preset.amountLabel(count)}'
                          : (active ? '${grams(preset.carbs * count)} g koolh.' : presetDetail(preset)),
                      style: context.t.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (onEdit != null)
                IconButton(
                  tooltip: '${preset.singular} bewerken',
                  onPressed: onEdit,
                  icon: Icon(Icons.edit_outlined, size: 18, color: k.textMuted),
                ),
              _RoundStep(
                icon: Icons.remove,
                enabled: active,
                label: '${preset.singular} min',
                onTap: () => onDelta(-1),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: context.t.subtitle.copyWith(
                    color: active ? k.accent : k.textMuted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _RoundStep(icon: Icons.add, enabled: true, label: '${preset.singular} plus', onTap: () => onDelta(1)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundStep extends StatelessWidget {
  const _RoundStep({required this.icon, required this.enabled, required this.label, required this.onTap});
  final IconData icon;
  final bool enabled;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 44,
        height: 44,
        child: Material(
          color: enabled ? k.surface : Colors.transparent,
          shape: CircleBorder(side: BorderSide(color: enabled ? k.border : k.border.withValues(alpha: 0.4))),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    onTap();
                  }
                : null,
            child: Icon(icon, size: 20, color: enabled ? k.text : k.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Volledige presetlijst: alfabetisch, doorzoekbaar, met −/+ en beheer.
Future<void> showPresetListSheet(
  BuildContext context, {
  required Map<String, int> counts,
  required PresetDelta onDelta,
  bool training = false,
  bool editable = true,
}) => showKineticSheet<void>(
  context,
  scrollable: false,
  builder: (_) => _PresetListSheet(counts: counts, onDelta: onDelta, training: training, editable: editable),
);

class _PresetListSheet extends StatefulWidget {
  const _PresetListSheet({required this.counts, required this.onDelta, required this.training, required this.editable});
  final Map<String, int> counts;
  final PresetDelta onDelta;
  final bool training;
  final bool editable;

  @override
  State<_PresetListSheet> createState() => _PresetListSheetState();
}

class _PresetListSheetState extends State<_PresetListSheet> {
  late Map<String, int> _counts = Map.of(widget.counts);
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final q = _query.trim().toLowerCase();
    final all = store.presetsFor(training: widget.training);
    final presets = all
        .where((p) => q.isEmpty || p.singular.toLowerCase().contains(q) || p.plural.toLowerCase().contains(q))
        .toList();
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SizedBox(
      height: height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(widget.training ? 'Trainingspresets' : 'Voedingspresets', style: context.t.headline),
              ),
              if (widget.editable)
                FilledButton.icon(
                  onPressed: () => showPresetEditor(context, training: widget.training),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Nieuw'),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.editable
                ? 'Alfabetisch • lang indrukken of potlood om te bewerken'
                : 'Alfabetisch • presets beheer je op de Training-pagina',
            style: context.t.caption,
          ),
          const SizedBox(height: 12),
          if (all.length > 6) ...[
            TextField(
              onChanged: (v) => setState(() => _query = v),
              style: context.t.body,
              decoration: InputDecoration(
                hintText: 'Zoek preset...',
                prefixIcon: Icon(Icons.search, color: k.textMuted),
              ),
            ),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: presets.isEmpty
                ? Center(
                    child: Text(
                      all.isEmpty ? 'Nog geen presets. Tik op "Nieuw".' : 'Geen preset gevonden.',
                      style: context.t.caption,
                    ),
                  )
                : ListView.separated(
                    itemCount: presets.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final p = presets[i];
                      return PresetStepperRow(
                        preset: p,
                        count: _counts[p.singular] ?? 0,
                        onEdit: widget.editable
                            ? () => showPresetEditor(context, existing: p, training: widget.training)
                            : null,
                        onDelta: (d) => setState(() => _counts = widget.onDelta(p, d)),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 12),
          BigButton(label: 'Klaar', icon: Icons.check, height: 52, onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    );
  }
}

/// Preset maken of bewerken (met verwijderen).
Future<void> showPresetEditor(BuildContext context, {FoodPreset? existing, bool training = false}) =>
    showKineticSheet<void>(
      context,
      builder: (_) => _PresetEditor(existing: existing, training: training),
    );

class _PresetEditor extends StatefulWidget {
  const _PresetEditor({this.existing, required this.training});
  final FoodPreset? existing;
  final bool training;

  @override
  State<_PresetEditor> createState() => _PresetEditorState();
}

class _PresetEditorState extends State<_PresetEditor> {
  late final _singular = TextEditingController(text: widget.existing?.singular ?? '');
  late final _plural = TextEditingController(text: widget.existing?.plural ?? '');
  late final _carbs = TextEditingController(text: widget.existing == null ? '' : grams(widget.existing!.carbs));
  late final _amount = TextEditingController(
    text: (widget.existing?.unitAmount ?? 0) > 0 ? grams(widget.existing!.unitAmount) : '',
  );
  late String _unit = widget.existing?.unitLabel.isNotEmpty == true ? widget.existing!.unitLabel : 'g';
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_singular, _plural, _carbs, _amount]) {
      c.dispose();
    }
    super.dispose();
  }

  double? _num(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _save() async {
    final singular = _singular.text.trim();
    final plural = _plural.text.trim().isEmpty ? singular : _plural.text.trim();
    final carbs = _num(_carbs);
    final amount = _num(_amount) ?? 0;
    if (singular.isEmpty) return setState(() => _error = 'Geef de preset een naam.');
    if (carbs == null || carbs < 0 || carbs > 500) {
      return setState(() => _error = 'Vul de koolhydraten per stuk in (0-500 g).');
    }
    if (amount < 0 || amount > 5000) return setState(() => _error = 'Controleer de hoeveelheid.');
    final store = KineticScope.read(context);
    final clash = store
        .presetsFor(training: widget.training)
        .any((p) => p.singular.toLowerCase() == singular.toLowerCase() && p.singular != widget.existing?.singular);
    if (clash) return setState(() => _error = 'Er bestaat al een preset "$singular".');
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await store.upsertPreset(
      FoodPreset(
        singular: singular,
        plural: plural,
        carbs: carbs,
        unitAmount: amount,
        unitLabel: amount > 0 ? _unit : '',
      ),
      replacing: widget.existing?.singular,
      training: widget.training,
    );
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _saving = false;
        _error = 'Opslaan mislukt. Controleer je verbinding.';
      });
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final p = widget.existing!;
    final store = KineticScope.read(context);
    final ok = await store.deletePreset(p, training: widget.training);
    if (!mounted) return;
    if (ok) Navigator.of(context).pop();
    showToast(context, ok ? '${p.singular} verwijderd' : 'Verwijderen mislukt', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final editing = widget.existing != null;
    InputDecoration deco(String label, [String? hint]) => InputDecoration(labelText: label, hintText: hint);
    final numFormat = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          editing ? 'Preset bewerken' : (widget.training ? 'Nieuwe trainingspreset' : 'Nieuwe preset'),
          style: context.t.headline,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _singular,
                textCapitalization: TextCapitalization.sentences,
                style: context.t.body,
                decoration: deco('Enkelvoud', 'Appel'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _plural,
                textCapitalization: TextCapitalization.sentences,
                style: context.t.body,
                decoration: deco('Meervoud', 'Appels'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _carbs,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: numFormat,
          style: context.t.body,
          decoration: deco('Koolhydraten per stuk (g)', '16'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: numFormat,
                style: context.t.body,
                decoration: deco('Hoeveelheid per stuk (optioneel)', '135'),
              ),
            ),
            const SizedBox(width: 8),
            for (final u in {'g', 'ml', if (widget.existing?.unitLabel.isNotEmpty == true) widget.existing!.unitLabel})
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: KChip(label: u, selected: _unit == u, onTap: () => setState(() => _unit = u)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text('Bijvoorbeeld 1 appel = 135 g, 1 glas melk = 80 ml.', style: context.t.caption),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: context.t.caption.copyWith(color: k.danger)),
        ],
        const SizedBox(height: 20),
        BigButton(
          label: _saving ? 'Opslaan…' : 'Preset opslaan',
          icon: Icons.check,
          height: 52,
          onPressed: _saving ? null : _save,
        ),
        if (editing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _saving ? null : _delete,
            icon: Icon(Icons.delete_outline, color: k.danger),
            label: Text('Preset verwijderen', style: TextStyle(color: k.danger)),
          ),
        ],
      ],
    );
  }
}

/// Presets beheren (Eten: maaltijdpresets, Training: trainingspresets).
/// Ingeklapt een compacte regel; uitgeklapt de lijst met bewerken en nieuw.
class PresetManagerCard extends StatefulWidget {
  const PresetManagerCard({super.key, required this.training});
  final bool training;

  @override
  State<PresetManagerCard> createState() => _PresetManagerCardState();
}

class _PresetManagerCardState extends State<PresetManagerCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final training = widget.training;
    final presets = store.presetsFor(training: training);
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(KRadius.md),
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                IconTile(
                  icon: training ? Icons.sports_mma : Icons.restaurant,
                  size: 40,
                  color: training ? k.danger : k.warning,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(training ? 'Trainingspresets' : 'Maaltijdpresets', style: context.t.bodyStrong),
                      const SizedBox(height: 2),
                      Text(
                        '${presets.length} ${presets.length == 1 ? 'preset' : 'presets'} • '
                        '${training ? 'voor het Voeding-menu tijdens trainingen' : 'voor het loggen van maaltijden'}',
                        style: context.t.caption,
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: _open ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.expand_more, color: k.textSecondary),
                ),
              ],
            ),
          ),
          if (_open) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => showPresetEditor(context, training: training),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Nieuwe preset'),
              ),
            ),
            const SizedBox(height: 12),
            if (presets.isEmpty) Text('Nog geen presets.', style: context.t.caption),
            for (final p in presets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: KWell(
                  onTap: () => showPresetEditor(context, existing: p, training: training),
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.singular, style: context.t.bodyStrong),
                            Text(presetDetail(p), style: context.t.caption),
                          ],
                        ),
                      ),
                      Icon(Icons.edit_outlined, size: 18, color: k.textMuted),
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
