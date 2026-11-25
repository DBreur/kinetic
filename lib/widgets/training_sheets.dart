// training_sheets.dart: de sheets van een lopende training: Voeding (presets
// met −/+ en loggen met tijdstip), Warming-up (duur), Sparren instellen
// (rondes met eigen duur en doel + een doel voor het geheel), Techniek
// loggen (reps of tijd + notitie) en Combinatie loggen. Plus de lijst met
// gelogde voeding die ook ná de training aanpasbaar blijft.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../models/food_preset.dart';
import '../models/live_training.dart';
import '../models/technique.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import 'food_preset_widgets.dart';
import 'kinetic_widgets.dart';
import 'sheets.dart';
import 'start_training_sheet.dart';
import 'technique_detail_widgets.dart';

/// Kleine ronde −/+ knop met waarde ertussen (handschoenvriendelijk: 48px).
class ValueStepper extends StatelessWidget {
  const ValueStepper({
    super.key,
    required this.value,
    required this.onMinus,
    required this.onPlus,
    this.semanticsLabel = '',
    this.width = 72,
  });
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;
  final String semanticsLabel;
  final double width;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget step(IconData icon, VoidCallback? onTap, String label) => Semantics(
      button: true,
      label: '$semanticsLabel $label'.trim(),
      child: SizedBox(
        width: 48,
        height: 48,
        child: Material(
          color: k.surface,
          shape: CircleBorder(side: BorderSide(color: k.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: Icon(icon, size: 20, color: onTap == null ? k.textMuted : k.text),
          ),
        ),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        step(Icons.remove, onMinus, 'min'),
        SizedBox(
          width: width,
          child: Text(
            value,
            textAlign: TextAlign.center,
            style: context.t.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
          ),
        ),
        step(Icons.add, onPlus, 'plus'),
      ],
    );
  }
}

String _clock(int seconds) => '${seconds ~/ 60}:${two(seconds % 60)}';

// ------------------------------------------------------------------ voeding

/// Voeding-menu: presets met −/+, vrije invoer, en "Loggen" (tijdstip = nu).
Future<void> showNutritionSheet(BuildContext context) =>
    showKineticSheet<void>(context, builder: (_) => const _NutritionSheet());

class _NutritionSheet extends StatefulWidget {
  const _NutritionSheet();

  @override
  State<_NutritionSheet> createState() => _NutritionSheetState();
}

class _NutritionSheetState extends State<_NutritionSheet> {
  Map<String, int> _counts = {};
  final _free = TextEditingController();
  final _freeCarbs = TextEditingController();

  @override
  void dispose() {
    _free.dispose();
    _freeCarbs.dispose();
    super.dispose();
  }

  Map<String, int> _delta(FoodPreset preset, int d) {
    final key = preset.singular;
    final next = Map<String, int>.of(_counts);
    final v = ((next[key] ?? 0) + d).clamp(0, 99);
    if (v == 0) {
      next.remove(key);
    } else {
      next[key] = v;
    }
    setState(() => _counts = next);
    return next;
  }

  void _log() {
    final store = KineticScope.read(context);
    final carbs = parseNum(_freeCarbs.text) ?? 0;
    final items = _counts.values.fold<int>(0, (a, b) => a + b);
    if (items == 0 && _free.text.trim().isEmpty && carbs <= 0) return;
    store.logNutrition(_counts, freeLabel: _free.text, freeCarbs: carbs);
    HapticFeedback.mediumImpact();
    showToast(context, 'Voeding gelogd om ${hhmm(store.now())}');
    setState(() {
      _counts = {};
      _free.clear();
      _freeCarbs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final logged = store.training?.nutrition ?? const <NutritionLog>[];
    final byName = {for (final p in store.trainingPresets) p.singular: p};
    final pending = _counts.entries.fold<double>(0, (a, e) => a + (byName[e.key]?.carbs ?? 0) * e.value) +
        (parseNum(_freeCarbs.text) ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Voeding', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Tel met −/+ en tik op Loggen. Tijdstip wordt meteen vastgelegd.', style: context.t.caption),
        const SizedBox(height: 16),
        PresetQuickPicker(counts: _counts, onDelta: _delta, training: true, editable: false),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 3,
              child: TextField(
                controller: _free,
                textCapitalization: TextCapitalization.sentences,
                style: context.t.body,
                decoration: const InputDecoration(labelText: 'Iets anders (optioneel)', hintText: 'Sportdrank'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _freeCarbs,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                onChanged: (_) => setState(() {}),
                style: context.t.body,
                decoration: const InputDecoration(labelText: 'Koolh. (g)'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        BigButton(
          label: pending > 0 ? 'Loggen • ${grams(pending)} g koolh.' : 'Loggen',
          icon: Icons.check,
          height: 56,
          onPressed: _log,
        ),
        if (logged.isNotEmpty) ...[
          const SizedBox(height: 24),
          FormLabel('Gelogd deze training', trailing: '${grams(store.training!.nutritionCarbs)} g koolh.', trailingColor: k.accent),
          NutritionLogList(
            items: logged,
            onCount: (n, c) => store.updateNutrition(n.id, count: c),
            onTime: (n, at) => store.updateNutrition(n.id, at: at),
            onDelete: (n) => store.deleteNutrition(n.id),
          ),
        ],
      ],
    );
  }
}

/// Gelogde voeding met aantal −/+, tijd aanpassen en verwijderen. Wordt
/// zowel tijdens als na de training (sessiedetails) gebruikt.
class NutritionLogList extends StatelessWidget {
  const NutritionLogList({super.key, required this.items, required this.onCount, required this.onTime, required this.onDelete});
  final List<NutritionLog> items;
  final void Function(NutritionLog n, int count) onCount;
  final void Function(NutritionLog n, DateTime at) onTime;
  final void Function(NutritionLog n) onDelete;

  Future<void> _pickTime(BuildContext context, NutritionLog n) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(n.at),
      builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (picked == null) return;
    onTime(n, DateTime(n.at.year, n.at.month, n.at.day, picked.hour, picked.minute));
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final sorted = [...items]..sort((a, b) => a.at.compareTo(b.at));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: KWell(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(KRadius.sm),
                    onTap: () => _pickTime(context, n),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                      child: Text(hhmm(n.at), style: context.t.bodyStrong.copyWith(color: k.accent)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(n.label, style: context.t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                        Text(
                          [
                            '${grams(n.carbs)} g koolh.',
                            if (n.mmol != null) '${n.mmol!.toStringAsFixed(1)} mmol/L',
                          ].join(' • '),
                          style: context.t.caption,
                        ),
                      ],
                    ),
                  ),
                  ValueStepper(
                    value: '${n.count}',
                    width: 30,
                    semanticsLabel: n.label,
                    onMinus: n.count > 1 ? () => onCount(n, n.count - 1) : null,
                    onPlus: () => onCount(n, n.count + 1),
                  ),
                  IconButton(
                    tooltip: '${n.label} verwijderen',
                    onPressed: () => onDelete(n),
                    icon: Icon(Icons.delete_outline, color: k.dangerInk),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------- warming-up

/// Warming-up toevoegen (of [existing] aanpassen). Standaard 15 minuten.
Future<void> showWarmupSheet(BuildContext context, {WarmupLog? existing}) =>
    showKineticSheet<void>(context, builder: (_) => _WarmupSheet(existing: existing));

class _WarmupSheet extends StatefulWidget {
  const _WarmupSheet({this.existing});
  final WarmupLog? existing;

  @override
  State<_WarmupSheet> createState() => _WarmupSheetState();
}

class _WarmupSheetState extends State<_WarmupSheet> {
  late int _minutes = widget.existing?.minutes ?? 15;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.read(context);
    final k = context.k;
    final editing = widget.existing != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(editing ? 'Warming-up aanpassen' : 'Warming-up toevoegen', style: context.t.headline),
        const SizedBox(height: 4),
        Text('Hoe lang duurde de warming-up?', style: context.t.caption),
        const SizedBox(height: 24),
        Center(
          child: ValueStepper(
            value: '$_minutes min',
            width: 110,
            semanticsLabel: 'Warming-up',
            onMinus: _minutes > 1 ? () => setState(() => _minutes = _minutes - (_minutes > 5 ? 5 : 1)) : null,
            onPlus: _minutes < 120 ? () => setState(() => _minutes = _minutes + (_minutes >= 5 ? 5 : 1)) : null,
          ),
        ),
        const SizedBox(height: 24),
        BigButton(
          label: editing ? 'Opslaan' : 'Warming-up toevoegen',
          icon: Icons.check,
          height: 56,
          onPressed: () {
            if (editing) {
              store.updateWarmup(widget.existing!.id, _minutes);
            } else {
              store.addWarmup(minutes: _minutes);
            }
            Navigator.of(context).pop();
          },
        ),
        if (editing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () {
              store.removeWarmup(widget.existing!.id);
              Navigator.of(context).pop();
            },
            icon: Icon(Icons.delete_outline, color: k.dangerInk),
            label: Text('Verwijderen', style: TextStyle(color: k.dangerInk)),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- sparren

/// Sparblok instellen (nieuw), of [existing] aanpassen: ook tijdens het
/// sparren (rondes, duur, doelen) en achteraf (gedane rondes, verwijderen).
Future<void> showSparringSetupSheet(BuildContext context, {SparringBlock? existing}) =>
    showKineticSheet<void>(context, builder: (_) => _SparringSetupSheet(existing: existing));

class _SparringSetupSheet extends StatefulWidget {
  const _SparringSetupSheet({this.existing});
  final SparringBlock? existing;

  @override
  State<_SparringSetupSheet> createState() => _SparringSetupSheetState();
}

class _SparringSetupSheetState extends State<_SparringSetupSheet> {
  late final _goal = TextEditingController(text: widget.existing?.goal ?? '');
  late List<SparRound> _rounds;
  late List<TextEditingController> _roundGoals;
  late int _roundsDone = widget.existing?.roundsDone ?? 0;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _rounds = [...e.rounds];
    } else {
      final cfg = KineticScope.read(context).sparringConfig;
      _rounds = List.generate(cfg.rounds.clamp(1, 12), (_) => SparRound(workSeconds: cfg.workSeconds, restSeconds: cfg.restSeconds));
    }
    _roundGoals = [for (final r in _rounds) TextEditingController(text: r.goal)];
  }

  @override
  void dispose() {
    _goal.dispose();
    for (final c in _roundGoals) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _editing => widget.existing != null;

  /// Lopend blok: de huidige ronde (1-based), anders 0.
  int _currentRound(KineticStore store) =>
      widget.existing != null && store.training?.activeSparring?.id == widget.existing!.id ? (store.sparring?.round ?? 0) : 0;

  void _addRound() => setState(() {
    final last = _rounds.last;
    _rounds = [..._rounds, SparRound(workSeconds: last.workSeconds, restSeconds: last.restSeconds)];
    _roundGoals = [..._roundGoals, TextEditingController()];
  });

  void _removeRound(int i) => setState(() {
    _roundGoals[i].dispose();
    _rounds = [..._rounds]..removeAt(i);
    _roundGoals = [..._roundGoals]..removeAt(i);
    _roundsDone = _roundsDone.clamp(0, _rounds.length);
  });

  void _setRound(int i, SparRound r) => setState(() => _rounds = [..._rounds]..[i] = r);

  List<SparRound> get _withGoals => [
    for (var i = 0; i < _rounds.length; i++) _rounds[i].copyWith(goal: _roundGoals[i].text.trim()),
  ];

  void _save() {
    final store = KineticScope.read(context);
    final rounds = _withGoals;
    final e = widget.existing;
    if (e != null) {
      store.updateSparringBlock(e.id, rounds: rounds, goal: _goal.text, roundsDone: e.isFinished ? _roundsDone : null);
      Navigator.of(context).pop();
      return;
    }
    // Onthoud het format van ronde 1 als standaard voor de volgende keer.
    store.setSparringConfig(store.sparringConfig.copyWithRounds(rounds.length, rounds.first.workSeconds, rounds.first.restSeconds));
    store.startSparringBlock(rounds: rounds, goal: _goal.text);
    Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final store = KineticScope.read(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sparblok verwijderen?'),
        content: const Text('Rondes, doelen en tellers van dit sparblok worden uit de training gehaald.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.k.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    store.removeSparringBlock(widget.existing!.id);
    nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final total = _rounds.fold<int>(0, (a, r) => a + r.workSeconds) ~/ 60;
    final current = _currentRound(store);
    final finished = widget.existing?.isFinished ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(_editing ? 'Sparren aanpassen' : 'Sparren', style: context.t.headline),
        const SizedBox(height: 4),
        Text(
          current > 0
              ? 'Loopt nu (ronde $current). Wijzigingen gelden meteen; gedane rondes blijven staan.'
              : store.restTimerEnabled
              ? 'Elke ronde eigen duur en doel. Rust loopt als timer (instelbaar in Instellingen).'
              : 'Elke ronde eigen duur en doel. Rust duurt tot jij de volgende ronde start.',
          style: context.t.caption,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _goal,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(
            labelText: 'Doel voor het sparren (optioneel)',
            hintText: 'Zet minimaal 5 worpen in',
            prefixIcon: Icon(Icons.flag_outlined),
          ),
        ),
        if (finished) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Gedane rondes', style: context.t.bodyStrong)),
              ValueStepper(
                value: '$_roundsDone / ${_rounds.length}',
                width: 70,
                semanticsLabel: 'Gedane rondes',
                onMinus: _roundsDone > 0 ? () => setState(() => _roundsDone--) : null,
                onPlus: _roundsDone < _rounds.length ? () => setState(() => _roundsDone++) : null,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        FormLabel('Rondes', trailing: '${_rounds.length} × • $total min werk'),
        for (var i = 0; i < _rounds.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: KWell(
              color: current == i + 1 ? k.primaryTint : null,
              borderColor: current == i + 1 ? k.primary : null,
              padding: const EdgeInsets.fromLTRB(12, 10, 4, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          current == i + 1 ? 'Ronde ${i + 1} • nu' : (current > i + 1 ? 'Ronde ${i + 1} • gedaan' : 'Ronde ${i + 1}'),
                          style: context.t.subtitle,
                        ),
                      ),
                      // Gedane en lopende rondes kun je niet weghalen.
                      if (_rounds.length > 1 && i + 1 > current)
                        IconButton(
                          tooltip: 'Ronde ${i + 1} verwijderen',
                          onPressed: () => _removeRound(i),
                          icon: Icon(Icons.close, color: k.textMuted),
                        ),
                    ],
                  ),
                  Row(
                    children: [
                      Expanded(child: Text('Werk', style: context.t.caption)),
                      ValueStepper(
                        value: _clock(_rounds[i].workSeconds),
                        semanticsLabel: 'Ronde ${i + 1} werk',
                        onMinus: _rounds[i].workSeconds > 30
                            ? () => _setRound(i, _rounds[i].copyWith(workSeconds: _rounds[i].workSeconds - 30))
                            : null,
                        onPlus: () => _setRound(i, _rounds[i].copyWith(workSeconds: _rounds[i].workSeconds + 30)),
                      ),
                    ],
                  ),
                  if (i < _rounds.length - 1) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: Text('Rust erna', style: context.t.caption)),
                        ValueStepper(
                          value: _clock(_rounds[i].restSeconds),
                          semanticsLabel: 'Ronde ${i + 1} rust',
                          onMinus: _rounds[i].restSeconds > 0
                              ? () => _setRound(i, _rounds[i].copyWith(restSeconds: _rounds[i].restSeconds - 15))
                              : null,
                          onPlus: () => _setRound(i, _rounds[i].copyWith(restSeconds: _rounds[i].restSeconds + 15)),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextField(
                      controller: _roundGoals[i],
                      textCapitalization: TextCapitalization.sentences,
                      style: context.t.body,
                      decoration: InputDecoration(
                        labelText: 'Doel ronde ${i + 1} (optioneel)',
                        hintText: i == 0 ? 'Zet Harai Goshi in' : null,
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _rounds.length < 15 ? _addRound : null,
          icon: const Icon(Icons.add),
          label: const Text('Ronde toevoegen'),
        ),
        const SizedBox(height: 16),
        BigButton(
          label: _editing ? 'Opslaan' : 'Start sparren',
          icon: _editing ? Icons.check : Icons.sports_mma,
          height: 56,
          onPressed: _save,
        ),
        if (finished) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: store.isSparringActive
                ? null
                : () {
                    final s = KineticScope.read(context);
                    final id = widget.existing!.id;
                    Navigator.of(context).pop();
                    s.repeatSparringBlock(id);
                  },
            icon: const Icon(Icons.replay),
            label: Text(store.isSparringActive ? 'Er loopt al een sparblok' : 'Opnieuw sparren (zelfde rondes)'),
          ),
        ],
        if (_editing) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: _delete,
            icon: Icon(Icons.delete_outline, color: k.dangerInk),
            label: Text('Sparblok verwijderen', style: TextStyle(color: k.dangerInk)),
          ),
        ],
      ],
    );
  }
}

// --------------------------------------------------------------- techniek

/// Techniek loggen buiten het sparren: reps of tijd, plus een notitie.
Future<void> showTechniqueLogSheet(BuildContext context, Technique technique) =>
    showKineticSheet<void>(context, builder: (_) => _TechniqueLogSheet(technique: technique));

class _TechniqueLogSheet extends StatefulWidget {
  const _TechniqueLogSheet({required this.technique});
  final Technique technique;

  @override
  State<_TechniqueLogSheet> createState() => _TechniqueLogSheetState();
}

class _TechniqueLogSheetState extends State<_TechniqueLogSheet> {
  late TechniqueLog _log = KineticScope.read(context).techniqueLog(widget.technique.id);
  late final _note = TextEditingController(text: _log.note);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    KineticScope.read(context).setTechniqueLog(widget.technique.id, _log.copyWith(note: _note.text.trim()));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tech = widget.technique;
    final reps = _log.measure == TechniqueMeasure.reps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(tech.name, style: context.t.headline),
        if (tech.learningGoal.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Doel: ${tech.learningGoal.trim()}', style: context.t.caption),
        ],
        const SizedBox(height: 16),
        KSegmented<TechniqueMeasure>(
          options: const [(TechniqueMeasure.reps, 'Reps'), (TechniqueMeasure.time, 'Tijd')],
          value: _log.measure,
          onChanged: (m) => setState(() => _log = _log.copyWith(measure: m)),
        ),
        const SizedBox(height: 20),
        Center(
          child: reps
              ? ValueStepper(
                  value: '${_log.reps}',
                  width: 90,
                  semanticsLabel: '${tech.name} reps',
                  onMinus: _log.reps > 0 ? () => setState(() => _log = _log.copyWith(reps: (_log.reps - 5).clamp(0, 9999))) : null,
                  onPlus: () => setState(() => _log = _log.copyWith(reps: _log.reps + 5)),
                )
              : ValueStepper(
                  value: _clock(_log.seconds),
                  width: 90,
                  semanticsLabel: '${tech.name} tijd',
                  onMinus: _log.seconds > 0 ? () => setState(() => _log = _log.copyWith(seconds: (_log.seconds - 60).clamp(0, 36000))) : null,
                  onPlus: () => setState(() => _log = _log.copyWith(seconds: _log.seconds + 60)),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          reps ? 'Stappen van 5 reps' : 'Stappen van 1 minuut',
          textAlign: TextAlign.center,
          style: context.t.caption,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _note,
          minLines: 2,
          maxLines: 5,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: const InputDecoration(labelText: 'Notitie', hintText: 'Wat viel op? Grip, timing, setup...'),
        ),
        const SizedBox(height: 16),
        BigButton(label: 'Opslaan', icon: Icons.check, height: 56, onPressed: _save),
        const SizedBox(height: 20),
        // Video's (uitleg) en beoordelen, ook tijdens de training.
        TechniqueDetails(techniqueId: tech.id, compact: true),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () {
            final store = KineticScope.read(context);
            final backup = store.removeSessionTechnique(tech.id);
            Navigator.of(context).pop();
            showToast(
              context,
              '${tech.name} uit de training gehaald',
              actionLabel: 'Ongedaan',
              onAction: () => store.restoreSessionTechnique(tech.id, backup),
            );
          },
          icon: Icon(Icons.remove_circle_outline, color: context.k.dangerInk),
          label: Text('Uit deze training halen', style: TextStyle(color: context.k.dangerInk)),
        ),
      ],
    );
  }
}

/// Technieken aan de training toevoegen uit de vault.
Future<void> addTechniquesToTraining(BuildContext context) async {
  final store = KineticScope.read(context);
  final pick = await showTechniquePicker(
    context,
    title: 'Techniek toevoegen',
    initiallySelected: (e) => e.own != null && store.sessionTechniqueIds.contains(e.own!.id),
  );
  if (pick == null) return;
  for (final e in pick.entries) {
    final t = await store.ensureOwnTechnique(e);
    if (t != null && !store.sessionTechniqueIds.contains(t.id)) store.toggleSessionTechnique(t.id);
  }
}

// ------------------------------------------------------------- combinatie

/// Combinatie loggen: technieken in volgorde aantikken (bv. Harai Goshi →
/// O-soto-gari). Dezelfde combinatie nog eens loggen telt op.
Future<void> showComboSheet(BuildContext context) =>
    showKineticSheet<void>(context, builder: (_) => const _ComboSheet());

class _ComboSheet extends StatefulWidget {
  const _ComboSheet();

  @override
  State<_ComboSheet> createState() => _ComboSheetState();
}

class _ComboSheetState extends State<_ComboSheet> {
  final List<String> _steps = [];

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final session = store.sessionTechniques;
    final others = store.techniques.where((t) => !store.sessionTechniqueIds.contains(t.id)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final logged = store.training?.combos ?? const <ComboLog>[];
    Widget chip(Technique t) => KChip(
      label: t.name,
      selected: false,
      icon: Icons.add,
      onTap: () => setState(() => _steps.add(t.name)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Combinatie loggen', style: context.t.headline),
        const SizedBox(height: 4),
        Text(
          store.combinations.isEmpty
              ? "Tik de technieken in volgorde aan. Vaste combinaties maak je onder Technieken → Combo's."
              : 'Tik een opgeslagen combinatie, of stel er hieronder zelf een samen.',
          style: context.t.caption,
        ),
        const SizedBox(height: 16),
        if (store.combinations.isNotEmpty) ...[
          const FormLabel('Opgeslagen combinaties'),
          for (final c in store.combinations)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  store.logCombo(c.techniques.isEmpty ? [c.name] : c.techniques, combinationId: c.id);
                  showToast(context, '${c.sequence} gelogd');
                },
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.alt_route, color: k.purple),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.name, style: context.t.bodyStrong),
                          if (c.techniques.isNotEmpty) Text(c.sequence, style: context.t.caption),
                        ],
                      ),
                    ),
                    Icon(Icons.add_circle_outline, color: k.accent),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          const FormLabel('Zelf samenstellen'),
        ],
        KWell(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 32),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _steps.isEmpty ? 'Nog niets gekozen' : _steps.join(' → '),
                    style: context.t.subtitle.copyWith(color: _steps.isEmpty ? k.textMuted : k.text),
                  ),
                ),
                if (_steps.isNotEmpty)
                  IconButton(
                    tooltip: 'Laatste stap weghalen',
                    onPressed: () => setState(_steps.removeLast),
                    icon: Icon(Icons.backspace_outlined, color: k.textSecondary),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (session.isNotEmpty) ...[
          const FormLabel('Technieken van deze training'),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final t in session) chip(t)]),
          const SizedBox(height: 16),
        ],
        if (others.isNotEmpty) ...[
          const FormLabel('Overige technieken'),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final t in others.take(30)) chip(t)]),
          const SizedBox(height: 16),
        ],
        BigButton(
          label: 'Combinatie loggen',
          icon: Icons.check,
          height: 56,
          onPressed: _steps.length < 2
              ? null
              : () {
                  store.logCombo(List.of(_steps));
                  showToast(context, '${_steps.join(' → ')} gelogd');
                  setState(_steps.clear);
                },
        ),
        if (logged.isNotEmpty) ...[
          const SizedBox(height: 24),
          const FormLabel('Gelogd deze training'),
          for (final c in logged)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: KWell(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(
                  children: [
                    Expanded(child: Text(c.label, style: context.t.bodyStrong)),
                    ValueStepper(
                      value: '${c.count}×',
                      width: 40,
                      semanticsLabel: c.label,
                      onMinus: () => store.changeComboCount(c.id, -1),
                      onPlus: () => store.changeComboCount(c.id, 1),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

/// Details van een techniek tijdens de training: wat je hebt gelogd, je
/// notitie, video's (afspelen in de app) en beoordeling. "Aanpassen" opent
/// pas het loggen van reps/tijd en notitie.
Future<void> showTrainingTechniqueDetails(BuildContext context, Technique technique) =>
    showKineticSheet<void>(context, builder: (_) => _TrainingTechniqueDetails(technique: technique));

class _TrainingTechniqueDetails extends StatelessWidget {
  const _TrainingTechniqueDetails({required this.technique});
  final Technique technique;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final t = technique;
    final log = store.techniqueLog(t.id);
    final reps = log.measure == TechniqueMeasure.reps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 6,
          children: [
            KPill(t.group.label, dense: true),
            if (t.isInFocus) const KPill('Focus', tone: KTone.warning, icon: Icons.priority_high, dense: true),
          ],
        ),
        const SizedBox(height: 10),
        Text(t.name, style: context.t.headline),
        if (t.learningGoal.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text('Doel: ${t.learningGoal.trim()}', style: context.t.caption),
        ],
        const SizedBox(height: 16),
        KWell(
          child: Row(
            children: [
              Icon(reps ? Icons.repeat : Icons.timer_outlined, color: k.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  reps ? '${log.reps} reps deze training' : '${durationLabel(log.seconds ~/ 60)} deze training',
                  style: context.t.bodyStrong,
                ),
              ),
            ],
          ),
        ),
        if (log.note.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          KWell(child: Text(log.note.trim(), style: context.t.body)),
        ],
        const SizedBox(height: 12),
        BigButton(
          label: 'Reps/tijd en notitie aanpassen',
          icon: Icons.edit_outlined,
          style: KButtonStyle.secondary,
          height: 52,
          fitLabel: true,
          onPressed: () {
            Navigator.of(context).pop();
            showTechniqueLogSheet(context, t);
          },
        ),
        const SizedBox(height: 20),
        TechniqueDetails(techniqueId: t.id),
      ],
    );
  }
}
