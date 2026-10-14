// workout_template_edit_screen.dart — trainingsschema maken/aanpassen
//
// Een schema is een naam + een vaste lijst oefeningen met vaste sets
// (kg/reps) — bv. "Dag 1" met Squat 3x5 op 80kg. Bij het starten van een
// krachttraining kun je zo'n schema kiezen als startpunt; de sets blijven
// daarna gewoon aanpasbaar, precies als bij handmatig toegevoegde
// oefeningen.

import 'package:flutter/material.dart';

import '../core/exercise_library.dart';
import '../models/exercise.dart';
import '../models/workout_template.dart';
import '../repositories/circuit_repository.dart';
import '../repositories/exercise_repository.dart';
import '../repositories/workout_template_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/block_widgets.dart' show AddBlockButton;

/// Resultaat van het schema-aanpasscherm: het opgeslagen schema, of een
/// signaal dat het is verwijderd.
class WorkoutTemplateEditResult {
  final WorkoutTemplate? template;
  final bool deleted;
  const WorkoutTemplateEditResult.saved(this.template) : deleted = false;
  const WorkoutTemplateEditResult.deleted() : template = null, deleted = true;
}

class WorkoutTemplateEditScreen extends StatefulWidget {
  const WorkoutTemplateEditScreen({
    super.key,
    required this.controller,
    this.template,
  });

  final AppController controller;

  /// Null bij een nieuw schema.
  final WorkoutTemplate? template;

  @override
  State<WorkoutTemplateEditScreen> createState() =>
      _WorkoutTemplateEditScreenState();
}

class _TemplateEditSet {
  double kg;
  int reps;

  /// Tijd-gebaseerde set (bv. een plank van 45s) i.p.v. reps — `null`
  /// betekent gewoon een reps-gebaseerde set zoals voorheen.
  int? seconds;

  /// "Tot verzuring" plus hoeveel erna, bv. "5–10".
  bool toBurn;
  String extraTarget;
  _TemplateEditSet({
    this.kg = 0,
    this.reps = 8,
    this.seconds,
    this.toBurn = false,
    this.extraTarget = '',
  });

  _TemplateEditSet copy() => _TemplateEditSet(
    kg: kg,
    reps: reps,
    seconds: seconds,
    toBurn: toBurn,
    extraTarget: extraTarget,
  );
}

class _TemplateEditExercise {
  String name;
  List<_TemplateEditSet> sets;
  _TemplateEditExercise({required this.name, required this.sets});
}

class _WorkoutTemplateEditScreenState extends State<WorkoutTemplateEditScreen> {
  late final TextEditingController _name;
  late List<_TemplateEditExercise> _exercises;
  bool _adding = false;
  bool _busy = false;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  late final ExerciseRepository _exerciseRepo;
  late final WorkoutTemplateRepository _templateRepo;
  late final CircuitRepository _circuitRepo;
  List<Exercise> _knownExercises = [];
  late List<Circuit> _circuits;
  List<Circuit> _savedCircuits = [];

  bool get _isNew => widget.template == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.template?.name ?? '');
    _circuits = List.of(widget.template?.circuits ?? const []);
    _exercises = (widget.template?.exercises ?? const [])
        .map(
          (e) => _TemplateEditExercise(
            name: e.name,
            sets: e.sets
                .map(
                  (s) => _TemplateEditSet(
                    kg: s.kg,
                    reps: s.reps,
                    seconds: s.seconds,
                    toBurn: s.toBurn,
                    extraTarget: s.extraTarget,
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    _exerciseRepo = ExerciseRepository(widget.controller.client!);
    _templateRepo = WorkoutTemplateRepository(widget.controller.client!);
    _circuitRepo = CircuitRepository(widget.controller.client!);
    _loadKnownExercises();
    _loadSavedCircuits();
  }

  Future<void> _loadSavedCircuits() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      final circuits = await _circuitRepo.listForUser(userId);
      if (mounted) setState(() => _savedCircuits = circuits);
    } catch (_) {
      // Picker blijft leeg; eerst een circuit aanmaken in Instellingen.
    }
  }

  Future<void> _pickCircuit() async {
    final chosen = await showModalBottomSheet<Circuit>(
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
          MediaQuery.of(ctx).padding.bottom + 20,
        ),
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
            Text(
              'Circuit toevoegen',
              style: AppText.cardTitle.copyWith(fontSize: 18),
            ),
            const SizedBox(height: 16),
            if (_savedCircuits.isEmpty)
              Text(
                'Nog geen circuits — maak er eerst een aan via Instellingen.',
                style: AppText.caption,
              )
            else
              for (final c in _savedCircuits)
                InkWell(
                  onTap: () => Navigator.pop(ctx, c),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColor.lineStrong),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.name, style: AppText.bodyStrong),
                              Text(
                                c.summary,
                                style: AppText.caption.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
    if (chosen == null || !mounted) return;
    setState(() => _circuits.add(chosen));
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

  @override
  void dispose() {
    _name.dispose();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

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

  void _reorderExercise(int oldIndex, int newIndex) {
    setState(() {
      final moved = _exercises.removeAt(oldIndex);
      _exercises.insert(newIndex, moved);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geef het schema een naam.')),
      );
      return;
    }
    if (_exercises.isEmpty && _circuits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Voeg minstens één oefening of circuit toe.'),
        ),
      );
      return;
    }
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    setState(() => _busy = true);
    final entries = _exercises
        .map(
          (e) => ExerciseEntry(
            name: e.name,
            sets: e.sets
                .map(
                  (s) => ExerciseSet(
                    kg: s.kg,
                    reps: s.reps,
                    seconds: s.toBurn ? null : s.seconds,
                    toBurn: s.toBurn,
                    extraTarget: s.toBurn ? s.extraTarget : '',
                  ),
                )
                .toList(),
          ),
        )
        .toList();
    try {
      final saved = _isNew
          ? await _templateRepo.create(
              WorkoutTemplate(
                id: '',
                name: name,
                exercises: entries,
                circuits: _circuits,
              ),
              userId,
            )
          : await _templateRepo.updateContent(
              widget.template!.copyWith(
                name: name,
                exercises: entries,
                circuits: _circuits,
              ),
            );
      if (mounted) {
        Navigator.pop(context, WorkoutTemplateEditResult.saved(saved));
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

  Future<void> _confirmDelete() async {
    final template = widget.template;
    if (template == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Schema verwijderen?', style: AppText.cardTitle),
        content: Text(
          '"${template.name}" wordt verwijderd.',
          style: AppText.body.copyWith(color: AppColor.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Annuleer'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            style: TextButton.styleFrom(foregroundColor: AppColor.redBright),
            child: const Text('Verwijder'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _templateRepo.delete(template.id);
      if (mounted) {
        Navigator.pop(context, const WorkoutTemplateEditResult.deleted());
      }
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verwijderen is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      appBar: AppBar(
        backgroundColor: AppColor.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(
          _isNew ? 'Nieuw schema' : 'Schema aanpassen',
          style: AppText.bodyStrong.copyWith(fontSize: 14),
        ),
        actions: [
          if (!_isNew)
            IconButton(
              onPressed: _busy ? null : _confirmDelete,
              icon: const Icon(Icons.delete_outline, color: AppColor.redBright),
            ),
        ],
      ),
      body: Stack(
        children: [
          ListView(
            controller: _scroll,
            padding: EdgeInsets.fromLTRB(
              20,
              18,
              20,
              100 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              Text('NAAM', style: AppText.overline),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                style: AppText.bodyStrong,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColor.surface,
                  hintText: 'Bijvoorbeeld "Dag 1"',
                  hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Text('OEFENINGEN', style: AppText.overline),
              const SizedBox(height: 10),
              if (_exercises.isNotEmpty)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorderExercise,
                  children: [
                    for (var ei = 0; ei < _exercises.length; ei++)
                      Padding(
                        key: ValueKey(_exercises[ei]),
                        padding: EdgeInsets.zero,
                        child: _TemplateExerciseCard(
                          exercise: _exercises[ei],
                          onRemove: () =>
                              setState(() => _exercises.removeAt(ei)),
                          onAddSet: () => setState(
                            () => _exercises[ei].sets.add(
                              _exercises[ei].sets.isEmpty
                                  ? _TemplateEditSet()
                                  : _exercises[ei].sets.last.copy(),
                            ),
                          ),
                          onRemoveSet: (si) =>
                              setState(() => _exercises[ei].sets.removeAt(si)),
                          onSetChanged: (si, patch) => setState(() {
                            patch(_exercises[ei].sets[si]);
                          }),
                          dragHandle: ReorderableDragStartListener(
                            index: ei,
                            child: const Padding(
                              padding: EdgeInsets.all(4),
                              child: Icon(
                                Icons.drag_handle,
                                size: 18,
                                color: AppColor.inkFaint,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              if (_adding)
                _AddTemplateExerciseInline(
                  query: _query,
                  customExercises: _knownExercises,
                  onPick: (name) => setState(() {
                    _exercises.add(
                      _TemplateEditExercise(
                        name: name,
                        sets: [_TemplateEditSet()],
                      ),
                    );
                    _adding = false;
                    _query.clear();
                  }),
                  onCancel: () => setState(() {
                    _adding = false;
                    _query.clear();
                  }),
                )
              else
                AddBlockButton(
                  label: 'Oefening toevoegen',
                  onTap: () {
                    setState(() => _adding = true);
                    _scrollToBottom();
                  },
                ),
              const SizedBox(height: 22),
              Text('CIRCUITS', style: AppText.overline),
              const SizedBox(height: 10),
              for (var ci = 0; ci < _circuits.length; ci++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: AppColor.surfaceRaised,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _circuits[ci].name,
                                style: AppText.bodyStrong.copyWith(
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                _circuits[ci].summary,
                                style: AppText.caption.copyWith(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        InkWell(
                          onTap: () =>
                              setState(() => _circuits.removeAt(ci)),
                          borderRadius: BorderRadius.circular(7),
                          child: const Padding(
                            padding: EdgeInsets.all(4),
                            child: Icon(
                              Icons.close,
                              size: 16,
                              color: AppColor.inkFaint,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              AddBlockButton(
                label: 'Circuit toevoegen',
                onTap: _pickCircuit,
              ),
            ],
          ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: FilledButton(
              onPressed: _busy ? null : _save,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: const Text('Opslaan'),
            ),
          ),
          if (_busy)
            Container(
              color: Colors.black.withValues(alpha: .55),
              alignment: Alignment.center,
              child: const CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _TemplateExerciseCard extends StatelessWidget {
  const _TemplateExerciseCard({
    required this.exercise,
    required this.onRemove,
    required this.onAddSet,
    required this.onRemoveSet,
    required this.onSetChanged,
    this.dragHandle,
  });

  final _TemplateEditExercise exercise;
  final VoidCallback onRemove;
  final VoidCallback onAddSet;
  final ValueChanged<int> onRemoveSet;
  final void Function(int setIndex, void Function(_TemplateEditSet) patch)
  onSetChanged;
  final Widget? dragHandle;

  Widget _numberField({
    required double value,
    required VoidCallback onDown,
    required VoidCallback onUp,
    required String label,
    bool asInt = false,
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
        SizedBox(
          width: 48,
          child: Text(
            '$text $label',
            textAlign: TextAlign.center,
            style: AppText.caption,
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

  /// "Verzuring + 5–10" — tik om aan te passen hoeveel herhalingen er na
  /// de verzuring nog moeten komen.
  Widget _burnTarget(BuildContext context, int si) {
    final target = exercise.sets[si].extraTarget;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final controller = TextEditingController(text: target);
        final result = await showDialog<String>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Na de verzuring', style: AppText.cardTitle),
            content: TextField(
              controller: controller,
              autofocus: true,
              style: AppText.body,
              decoration: const InputDecoration(
                hintText: 'Aantal herhalingen, bv. 5–10',
              ),
              onSubmitted: (v) => Navigator.pop(c, v),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Annuleer'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, controller.text),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        if (result != null) {
          onSetChanged(si, (s) => s.extraTarget = result.trim());
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              target.isEmpty ? 'verzuring' : '+$target',
              style: AppText.cardTitle.copyWith(color: AppColor.amber),
            ),
            Text(
              'na verzuring',
              style: AppText.caption.copyWith(
                fontSize: 9,
                color: AppColor.inkFaint,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
              ?dragHandle,
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
                        (s) => s.kg = (s.kg - 2.5).clamp(0, 500),
                      ),
                      onUp: () => onSetChanged(
                        si,
                        (s) => s.kg = (s.kg + 2.5).clamp(0, 500),
                      ),
                      label: 'kg',
                    ),
                  ),
                  Expanded(
                    child: exercise.sets[si].toBurn
                        ? _burnTarget(context, si)
                        : exercise.sets[si].seconds != null
                        ? _numberField(
                            value: exercise.sets[si].seconds!.toDouble(),
                            onDown: () => onSetChanged(
                              si,
                              (s) =>
                                  s.seconds = (s.seconds! - 5).clamp(5, 600),
                            ),
                            onUp: () => onSetChanged(
                              si,
                              (s) =>
                                  s.seconds = (s.seconds! + 5).clamp(5, 600),
                            ),
                            label: 's',
                            asInt: true,
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
                          ),
                  ),
                  InkWell(
                    // reps → tijd → tot verzuring → reps
                    onTap: () => onSetChanged(si, (s) {
                      if (s.toBurn) {
                        s.toBurn = false;
                        s.seconds = null;
                      } else if (s.seconds != null) {
                        s.toBurn = true;
                        s.seconds = null;
                        if (s.extraTarget.isEmpty) s.extraTarget = '5–10';
                      } else {
                        s.seconds = 30;
                      }
                    }),
                    borderRadius: BorderRadius.circular(99),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        exercise.sets[si].toBurn
                            ? Icons.local_fire_department_outlined
                            : exercise.sets[si].seconds != null
                            ? Icons.timer_outlined
                            : Icons.repeat,
                        size: 16,
                        color: exercise.sets[si].toBurn
                            ? AppColor.amber
                            : AppColor.inkFaint,
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
}

class _AddTemplateExerciseInline extends StatelessWidget {
  const _AddTemplateExerciseInline({
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        border: Border.all(color: AppColor.teal.withValues(alpha: .3)),
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: query,
            style: AppText.body,
            decoration: InputDecoration(
              filled: true,
              fillColor: AppColor.surfaceRaised,
              hintText: 'Zoek of typ een oefening',
              hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: query,
            builder: (context, value, _) {
              final q = value.text.trim().toLowerCase();
              final allNames = <String>{
                ...kExerciseLibrary,
                ...customExercises.map((e) => e.name),
              };
              final options = allNames
                  .where((n) => q.isEmpty || n.toLowerCase().contains(q))
                  .take(6)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final name in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: InkWell(
                        onTap: () => onPick(name),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: AppColor.surfaceRaised,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(name, style: AppText.bodyStrong),
                        ),
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: onCancel,
                          child: const Text('Annuleer'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: value.text.trim().isEmpty
                              ? null
                              : () => onPick(value.text.trim()),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColor.teal,
                            foregroundColor: AppColor.greenInk,
                          ),
                          child: const Text('Eigen oefening'),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
