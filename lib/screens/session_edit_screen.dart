// session_edit_screen.dart — training achteraf aanpassen
//
// Notitie over de hele training wijzigen, technieken/warming-up/sparren
// toevoegen die je vergeten was of aanpassen (beoordeling, duur, notitie),
// bij krachttraining sets/oefeningen aanpassen, en de training verwijderen.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/session_times.dart';
import '../models/combination.dart';
import '../models/exercise.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../repositories/combination_repository.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/technique_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/number_input.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/block_widgets.dart';
import '../widgets/nutrition_log.dart';

/// Resultaat van het aanpassingsscherm: ofwel de bijgewerkte sessie, ofwel
/// een signaal dat hij is verwijderd.
class SessionEditResult {
  final TrainingSession? session;
  final bool deleted;
  const SessionEditResult.updated(this.session) : deleted = false;
  const SessionEditResult.deleted() : session = null, deleted = true;
}

class SessionEditScreen extends StatefulWidget {
  const SessionEditScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.controller,
  });

  final TrainingSession session;
  final SessionRepository repository;
  final AppController controller;

  @override
  State<SessionEditScreen> createState() => _SessionEditScreenState();
}

class _EditSet {
  double kg;
  int reps;

  /// Tijd-set (bv. plank): seconden in plaats van reps.
  int? seconds;

  /// De oorspronkelijke set, zodat verzuring en gelukt/reden bij opslaan
  /// blijven staan — hier pas je kg en reps (of de tijd) aan.
  final ExerciseSet? base;
  _EditSet({this.kg = 0, this.reps = 8, this.seconds, this.base});

  /// "Tot verzuring": geen reps om aan te passen.
  bool get toBurn => base?.toBurn ?? false;

  ExerciseSet toSet() => (base ?? const ExerciseSet(kg: 0, reps: 0)).copyWith(
    kg: kg,
    reps: reps,
    seconds: seconds,
    clearSeconds: seconds == null,
    done: true,
  );
}

class _EditExercise {
  String name;
  List<_EditSet> sets;

  /// Blok en rust blijven zoals ze in de training stonden.
  final int? block;
  final int? restSeconds;
  _EditExercise({
    required this.name,
    required this.sets,
    this.block,
    this.restSeconds,
  });
}

class _SessionEditScreenState extends State<SessionEditScreen> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late int _durationMinutes;
  late DateTime _startedAt;
  late List<TechniqueEntry> _blocks;
  late List<_EditExercise> _exercises;
  late List<NutritionEntry> _nutrition;
  bool _adding = false;
  bool _addingExercise = false;
  bool _busy = false;
  final _exerciseQuery = TextEditingController();
  final _scroll = ScrollController();
  late final TechniqueRepository _techniqueRepo;
  late final CombinationRepository _comboRepo;
  late final ExerciseRepository _exerciseRepo;
  List<Technique> _knownTechniques = [];
  List<Combination> _knownCombinations = [];
  List<Exercise> _knownExercises = [];

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.session.title);
    _note = TextEditingController(text: widget.session.note);
    _durationMinutes = widget.session.durationMinutes;
    _startedAt = widget.session.startedAt;
    _blocks = widget.session.blocks.map(TechniqueEntry.fromBlock).toList();
    _exercises = widget.session.exercises
        .map(
          (e) => _EditExercise(
            name: e.name,
            block: e.block,
            restSeconds: e.restSeconds,
            sets: e.sets
                .map(
                  (s) => _EditSet(
                    kg: s.kg,
                    reps: s.reps,
                    seconds: s.seconds,
                    base: s,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    _nutrition = List.of(widget.session.nutrition);
    _techniqueRepo = TechniqueRepository(widget.controller.client!);
    _comboRepo = CombinationRepository(widget.controller.client!);
    _exerciseRepo = ExerciseRepository(widget.controller.client!);
    _loadKnownTechniques();
    _loadKnownCombinations();
    _loadKnownExercises();
  }

  Future<void> _loadKnownExercises() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final exercises = await _exerciseRepo.listForUser(userId);
      if (mounted) setState(() => _knownExercises = exercises);
    } catch (_) {
      // Autocomplete blijft leeg; typen van een nieuwe naam werkt gewoon.
    }
  }

  Future<void> _loadKnownTechniques() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final techniques = await _techniqueRepo.listForUser(userId);
      if (mounted) setState(() => _knownTechniques = techniques);
    } catch (_) {
      // Autocomplete blijft leeg; typen van een nieuwe naam werkt gewoon.
    }
  }

  Future<void> _loadKnownCombinations() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final combos = await _comboRepo.listForUser(userId);
      if (mounted) setState(() => _knownCombinations = combos);
    } catch (_) {
      // Combinaties blijven leeg; losse technieken toevoegen werkt gewoon.
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _exerciseQuery.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Zonder dit blijft het formulier onder de vouw staan wanneer de lijst al
  /// (bijna) de hele hoogte van het scherm vult.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _editBlock(int i) async {
    final removed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              20,
        ),
        child: _BlockEditSheet(
          entry: _blocks[i],
          onRemove: () => Navigator.pop(ctx, true),
        ),
      ),
    );
    if (removed == true) {
      setState(() => _blocks.removeAt(i));
    } else {
      setState(() {});
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final trimmedTitle = _title.text.trim();
      final updated = widget.session.copyWith(
        title: trimmedTitle.isEmpty ? widget.session.title : trimmedTitle,
        note: _note.text.trim(),
        startedAt: _startedAt,
        durationMinutes: _durationMinutes,
        blocks: _blocks.map((t) => t.toBlock()).toList(),
        nutrition: _nutrition,
        exercises: _exercises
            .map(
              (e) => ExerciseEntry(
                name: e.name,
                sets: e.sets.map((s) => s.toSet()).toList(),
                block: e.block,
                restSeconds: e.restSeconds,
              ),
            )
            .toList(),
      );
      final saved = await widget.repository.updateContent(updated);
      final userId = widget.controller.user?.id;
      if (userId != null) {
        final knownNames = _knownTechniques.map((t) => t.name).toSet();
        final newOnes = _blocks.where(
          (t) =>
              t.kind == BlockKind.technique &&
              !t.catalogLinked &&
              !knownNames.contains(t.name),
        );
        for (final t in newOnes) {
          await _techniqueRepo.create(
            Technique(
              id: '',
              name: t.name,
              category: t.meta.split(' · ').first.isNotEmpty
                  ? t.meta.split(' · ').first
                  : 'Overig',
            ),
            userId,
          );
        }
        final knownExerciseNames = _knownExercises
            .map((e) => e.name.trim().toLowerCase())
            .toSet();
        final newExerciseNames = {
          for (final e in _exercises)
            if (!knownExerciseNames.contains(e.name.trim().toLowerCase()))
              e.name.trim(),
        };
        for (final name in newExerciseNames) {
          try {
            await _exerciseRepo.create(Exercise(id: '', name: name), userId);
          } catch (_) {
            // Bestaat al (de database staat geen dubbele namen toe) — de
            // training zelf is gewoon opgeslagen.
          }
        }
      }
      if (mounted) {
        Navigator.pop(context, SessionEditResult.updated(saved));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Opslaan is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Training verwijderen?', style: AppText.cardTitle),
        content: Text(
          'De training en alle notities verdwijnen. Je glucosedata blijft staan.',
          style: AppText.body.copyWith(color: AppColor.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            style: FilledButton.styleFrom(backgroundColor: AppColor.red),
            child: const Text('Verwijderen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() => _busy = true);
    try {
      await widget.repository.delete(widget.session.id);
      if (mounted) {
        Navigator.pop(context, const SessionEditResult.deleted());
      }
    } catch (_) {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSambo = widget.session.kind == SessionKind.sambo;
    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Training aanpassen',
          style: AppText.bodyStrong.copyWith(fontSize: 14),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _busy,
        child: Opacity(
          opacity: _busy ? .6 : 1,
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 100),
            children: [
              Text('NAAM', style: AppText.overline),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColor.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: TextField(
                  controller: _title,
                  style: AppText.bodyStrong,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Naam van de training',
                    hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('NOTITIE OVER DE TRAINING', style: AppText.overline),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColor.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: TextField(
                  controller: _note,
                  maxLines: 4,
                  minLines: 2,
                  style: AppText.body,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    hintText: 'Hoe voelde de training?',
                    hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: AppColor.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                ),
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    // Van/tot: van verschuift de training (duur blijft), tot
                    // past de duur aan; de duur hieronder schuift tot mee.
                    Row(
                      children: [
                        Expanded(
                          child: _TimeButton(
                            label: 'Van',
                            time: _startedAt,
                            onPicked: (t) => setState(
                              () => _startedAt = withTime(
                                _startedAt,
                                t.hour,
                                t.minute,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _TimeButton(
                            label: 'Tot',
                            time: endFor(_startedAt, _durationMinutes),
                            onPicked: (t) => setState(
                              () => _durationMinutes = durationUntil(
                                _startedAt,
                                t.hour,
                                t.minute,
                              ).clamp(0, 600),
                            ),
                          ),
                        ),
                      ],
                    ),
                    NumberStepper(
                      label: 'DUUR VAN DE TRAINING',
                      value: _durationMinutes,
                      suffix: ' min',
                      onDown: () => setState(
                        () => _durationMinutes = (_durationMinutes - 5).clamp(
                          0,
                          600,
                        ),
                      ),
                      onUp: () => setState(
                        () => _durationMinutes = (_durationMinutes + 5).clamp(
                          0,
                          600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSambo) ...[
                const SizedBox(height: 22),
                Text(
                  'TECHNIEKEN, WARMING-UP EN SPARREN',
                  style: AppText.overline,
                ),
                const SizedBox(height: 10),
                for (var i = 0; i < _blocks.length; i++)
                  _BlockRow(
                    key: ValueKey(_blocks[i].id),
                    entry: _blocks[i],
                    onTap: () => _editBlock(i),
                  ),
                if (_adding)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 10),
                    child: BlockAddForm(
                      showOpenButton: false,
                      existingTechniques: _knownTechniques,
                      existingCombinations: _knownCombinations,
                      onSubmit: (entry, {required openAfter}) => setState(() {
                        _blocks.add(entry);
                        _adding = false;
                      }),
                      onCancel: () => setState(() => _adding = false),
                    ),
                  )
                else
                  AddBlockButton(
                    onTap: () {
                      setState(() => _adding = true);
                      _scrollToBottom();
                    },
                  ),
              ] else ...[
                const SizedBox(height: 22),
                Text('OEFENINGEN', style: AppText.overline),
                const SizedBox(height: 10),
                for (var ei = 0; ei < _exercises.length; ei++)
                  _EditExerciseCard(
                    exercise: _exercises[ei],
                    onRemove: () => setState(() => _exercises.removeAt(ei)),
                    onAddSet: () => setState(
                      () => _exercises[ei].sets.add(
                        _EditSet(
                          kg: _exercises[ei].sets.isEmpty
                              ? 0
                              : _exercises[ei].sets.last.kg,
                          reps: _exercises[ei].sets.isEmpty
                              ? 8
                              : _exercises[ei].sets.last.reps,
                          // Zelfde soort set als de vorige (tijd/verzuring).
                          seconds: _exercises[ei].sets.isEmpty
                              ? null
                              : _exercises[ei].sets.last.seconds,
                          base: _exercises[ei].sets.isEmpty
                              ? null
                              : _exercises[ei].sets.last.base?.copyWith(
                                  completed: null,
                                  clearCompleted: true,
                                  note: '',
                                ),
                        ),
                      ),
                    ),
                    onRemoveSet: (si) =>
                        setState(() => _exercises[ei].sets.removeAt(si)),
                    onSetChanged: (si, patch) => setState(() {
                      patch(_exercises[ei].sets[si]);
                    }),
                  ),
                if (_addingExercise)
                  _AddExerciseInline(
                    query: _exerciseQuery,
                    customExercises: _knownExercises,
                    onPick: (name) => setState(() {
                      _exercises.add(
                        _EditExercise(name: name, sets: [_EditSet()]),
                      );
                      _addingExercise = false;
                      _exerciseQuery.clear();
                    }),
                    onCancel: () => setState(() {
                      _addingExercise = false;
                      _exerciseQuery.clear();
                    }),
                  )
                else
                  AddBlockButton(
                    label: 'Oefening toevoegen',
                    onTap: () {
                      setState(() => _addingExercise = true);
                      _scrollToBottom();
                    },
                  ),
              ],
              if (_nutrition.isNotEmpty) ...[
                const SizedBox(height: 22),
                Text('VOEDING TIJDENS TRAINING', style: AppText.overline),
                const SizedBox(height: 10),
                NutritionLogList(
                  entries: _nutrition,
                  onRemove: (i) => setState(() => _nutrition.removeAt(i)),
                ),
              ],
              const SizedBox(height: 30),
              Text(
                'VERWIJDEREN',
                style: AppText.overline.copyWith(color: AppColor.redBright),
              ),
              const SizedBox(height: 10),
              Text(
                'De training en alle notities verdwijnen. Je glucosedata blijft staan.',
                style: AppText.caption,
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _delete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColor.redBright,
                  side: const BorderSide(color: AppColor.red),
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('Training verwijderen'),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
          child: FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Opslaan...' : 'Wijzigingen bewaren'),
          ),
        ),
      ),
    );
  }
}

class _BlockRow extends StatelessWidget {
  const _BlockRow({super.key, required this.entry, required this.onTap});
  final TechniqueEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(entry.name, style: AppText.bodyStrong),
                  const SizedBox(height: 3),
                  Text(
                    blockMetaLine(entry),
                    style: AppText.caption.copyWith(fontSize: 10),
                  ),
                ],
              ),
            ),
            if (entry.kind == BlockKind.technique && entry.rating > 0)
              Text(
                '★' * entry.rating,
                style: AppText.caption.copyWith(color: AppColor.amberBright),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColor.inkFaint),
          ],
        ),
      ),
    );
  }
}

class _BlockEditSheet extends StatefulWidget {
  const _BlockEditSheet({required this.entry, required this.onRemove});
  final TechniqueEntry entry;
  final VoidCallback onRemove;

  @override
  State<_BlockEditSheet> createState() => _BlockEditSheetState();
}

class _BlockEditSheetState extends State<_BlockEditSheet> {
  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: widget.entry.name);
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Naam aanpassen', style: AppText.cardTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: AppText.body,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: .05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Annuleer'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text.trim()),
            child: const Text('Opslaan'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    setState(() => widget.entry.name = result);
  }

  Future<void> _pickLoggedAt(BuildContext context) async {
    final base = widget.entry.loggedAt ?? DateTime.now();
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(base),
    );
    if (time == null) return;
    setState(
      () => widget.entry.loggedAt = DateTime(
        base.year,
        base.month,
        base.day,
        time.hour,
        time.minute,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final isTech = e.kind == BlockKind.technique;
    final accent = kBlockKindAccent[e.kind]!;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: AppColor.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  e.name,
                  style: AppText.cardTitle.copyWith(fontSize: 18),
                ),
              ),
              InkWell(
                onTap: () => _rename(context),
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.edit_outlined,
                    size: 18,
                    color: AppColor.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          InkWell(
            onTap: () => _pickLoggedAt(context),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  e.loggedAt != null
                      ? '${kBlockKindLabel[e.kind]} · gelogd om ${DateFormat('HH:mm', 'nl_NL').format(e.loggedAt!)}'
                      : kBlockKindLabel[e.kind]!,
                  style: AppText.caption,
                ),
                const SizedBox(width: 6),
                const Icon(Icons.schedule, size: 13, color: AppColor.inkFaint),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (isTech) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(13),
              ),
              child: NumberStepper(
                label: 'GEOEFEND',
                value: e.minutes,
                suffix: ' min',
                accent: accent,
                onDown: () =>
                    setState(() => e.minutes = (e.minutes - 1).clamp(0, 180)),
                onUp: () =>
                    setState(() => e.minutes = (e.minutes + 1).clamp(0, 180)),
              ),
            ),
            const SizedBox(height: 16),
            Text('HOE GING HET?', style: AppText.overline),
            const SizedBox(height: 10),
            StarRow(
              rating: e.rating,
              onRate: (r) => setState(() => e.rating = r),
            ),
            const SizedBox(height: 16),
          ] else if (e.kind == BlockKind.warmup) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .05),
                borderRadius: BorderRadius.circular(13),
              ),
              child: NumberStepper(
                label: 'DUUR',
                value: e.minutes,
                suffix: ' min',
                accent: accent,
                onDown: () =>
                    setState(() => e.minutes = (e.minutes - 2).clamp(0, 180)),
                onUp: () =>
                    setState(() => e.minutes = (e.minutes + 2).clamp(0, 180)),
              ),
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text('RONDES', style: AppText.overline),
            const SizedBox(height: 10),
            RoundsEditor(
              roundMinutes: e.roundMinutes,
              roundGoals: e.roundGoals,
              restSeconds: e.restSeconds,
              roundRestrictions: e.roundRestrictions,
              onRestrictionsChanged: (r) =>
                  setState(() => e.roundRestrictions = r),
              accent: accent,
              onChanged: (m, g) => setState(() {
                e.roundMinutes = m;
                e.roundGoals = g;
              }),
              onRestChanged: (r) => setState(() => e.restSeconds = r),
            ),
            const SizedBox(height: 18),
            Text('ALGEMENE DOELEN', style: AppText.overline),
            const SizedBox(height: 10),
            GoalsEditor(
              goals: e.goals,
              onChanged: (g) => setState(() => e.goals = g),
            ),
            const SizedBox(height: 16),
          ],
          NoteField(
            value: e.note,
            onChanged: (n) => e.note = n,
            hint: 'Notitie bij ${kBlockKindNoun[e.kind]}',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onRemove,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColor.redBright,
                    side: const BorderSide(color: AppColor.red),
                  ),
                  child: const Text('Verwijder dit blok'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Gereed'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditExerciseCard extends StatelessWidget {
  const _EditExerciseCard({
    required this.exercise,
    required this.onRemove,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetChanged,
  });

  final _EditExercise exercise;
  final VoidCallback onRemove;
  final VoidCallback onAddSet;
  final ValueChanged<int> onRemoveSet;
  final void Function(int setIndex, void Function(_EditSet) patch) onSetChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(exercise.name, style: AppText.cardTitle)),
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .06),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.close,
                    size: 14,
                    color: AppColor.inkFaint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var si = 0; si < exercise.sets.length; si++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${si + 1}',
                      textAlign: TextAlign.center,
                      style: AppText.caption,
                    ),
                  ),
                  Expanded(
                    child: _numberField(
                      value: exercise.sets[si].kg,
                      onDown: () => onSetChanged(
                        si,
                        (s) => s.kg = (s.kg - 0.5).clamp(0, 500),
                      ),
                      onUp: () => onSetChanged(
                        si,
                        (s) => s.kg = (s.kg + 0.5).clamp(0, 500),
                      ),
                      label: 'kg',
                      onTyped: (v) => onSetChanged(si, (s) => s.kg = v),
                    ),
                  ),
                  Expanded(
                    child: exercise.sets[si].toBurn
                        ? Center(
                            child: Text(
                              exercise.sets[si].base?.summary
                                      .split(' · ')
                                      .last ??
                                  'verzuring',
                              style: AppText.caption.copyWith(
                                color: AppColor.amber,
                              ),
                            ),
                          )
                        : exercise.sets[si].seconds != null
                        ? _numberField(
                            value: exercise.sets[si].seconds!.toDouble(),
                            onDown: () => onSetChanged(
                              si,
                              (s) => s.seconds = (s.seconds! - 5).clamp(5, 600),
                            ),
                            onUp: () => onSetChanged(
                              si,
                              (s) => s.seconds = (s.seconds! + 5).clamp(5, 600),
                            ),
                            label: 's',
                            asInt: true,
                            onTyped: (v) => onSetChanged(
                              si,
                              (s) => s.seconds = v.round().clamp(5, 600),
                            ),
                          )
                        : _numberField(
                            value: exercise.sets[si].reps.toDouble(),
                            onDown: () => onSetChanged(
                              si,
                              (s) => s.reps = (s.reps - 1).clamp(1, 100),
                            ),
                            onUp: () => onSetChanged(
                              si,
                              (s) => s.reps = (s.reps + 1).clamp(1, 100),
                            ),
                            label: 'reps',
                            asInt: true,
                            onTyped: (v) => onSetChanged(
                              si,
                              (s) => s.reps = v.round().clamp(1, 100),
                            ),
                          ),
                  ),
                  InkWell(
                    onTap: () => onRemoveSet(si),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: AppColor.inkFaint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          InkWell(
            onTap: onAddSet,
            borderRadius: BorderRadius.circular(11),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 9),
              decoration: BoxDecoration(
                border: Border.all(color: AppColor.lineStrong),
                borderRadius: BorderRadius.circular(11),
              ),
              alignment: Alignment.center,
              child: Text(
                '+ set',
                style: AppText.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AppColor.inkMuted,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField({
    required double value,
    required VoidCallback onDown,
    required VoidCallback onUp,
    required String label,
    bool asInt = false,
    ValueChanged<double>? onTyped,
  }) {
    final text = asInt
        ? value.toInt().toString()
        : (value % 1 == 0 ? value.toInt().toString() : value.toString());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onDown,
          child: Container(
            width: 26,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('−'),
          ),
        ),
        // Tik op het getal om het zelf te typen.
        Builder(
          builder: (context) => InkWell(
            onTap: onTyped == null
                ? null
                : () async {
                    final v = await showNumberInput(
                      context,
                      title: switch (label) {
                        'kg' => 'Gewicht',
                        's' => 'Seconden',
                        _ => 'Herhalingen',
                      },
                      initial: value,
                      decimal: !asInt,
                      suffix: label,
                      max: label == 's' ? 600 : (asInt ? 100 : 500),
                    );
                    if (v != null) onTyped(v);
                  },
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 44,
              child: Text(
                '$text $label',
                textAlign: TextAlign.center,
                style: AppText.caption,
              ),
            ),
          ),
        ),
        InkWell(
          onTap: onUp,
          child: Container(
            width: 26,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .06),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('+'),
          ),
        ),
      ],
    );
  }
}

class _AddExerciseInline extends StatelessWidget {
  const _AddExerciseInline({
    required this.query,
    required this.customExercises,
    required this.onPick,
    required this.onCancel,
  });

  final TextEditingController query;
  final List<Exercise> customExercises;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => ExercisePicker(
    query: query,
    customExercises: customExercises,
    onPick: onPick,
    onCancel: onCancel,
  );
}

/// "Van 19:00" / "Tot 20:30" — tik om een tijd te kiezen.
class _TimeButton extends StatelessWidget {
  const _TimeButton({
    required this.label,
    required this.time,
    required this.onPicked,
  });

  final String label;
  final DateTime time;
  final ValueChanged<TimeOfDay> onPicked;

  @override
  Widget build(BuildContext context) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return OutlinedButton.icon(
      onPressed: () async {
        final t = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(time),
          helpText: label,
        );
        if (t != null) onPicked(t);
      },
      icon: Icon(
        label == 'Van' ? Icons.play_arrow_outlined : Icons.flag_outlined,
        size: 18,
      ),
      label: Text('$label $hh:$mm'),
    );
  }
}
