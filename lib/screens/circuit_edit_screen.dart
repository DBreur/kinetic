// circuit_edit_screen.dart — circuit maken/aanpassen
//
// Een circuit is een naam + een lijst oefeningnamen die je in rondes
// doorloopt, elk voor dezelfde werktijd met dezelfde rust ertussen (bv.
// "3 rondes van 40s werk / 20s rust"). Ook een warming-up is gewoon een
// circuit — geen apart concept. Vereenvoudigde versie van
// workout_template_edit_screen.dart: geen sets/kg/reps, alleen namen.

import 'package:flutter/material.dart';

import '../core/exercise_library.dart';
import '../models/circuit.dart';
import '../models/exercise.dart';
import '../repositories/circuit_repository.dart';
import '../repositories/exercise_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/block_widgets.dart' show AddBlockButton, NumberStepper;

/// Resultaat van het circuit-aanpasscherm: het opgeslagen circuit, of een
/// signaal dat het is verwijderd.
class CircuitEditResult {
  final Circuit? circuit;
  final bool deleted;
  const CircuitEditResult.saved(this.circuit) : deleted = false;
  const CircuitEditResult.deleted() : circuit = null, deleted = true;
}

class CircuitEditScreen extends StatefulWidget {
  const CircuitEditScreen({super.key, required this.controller, this.circuit});

  final AppController controller;

  /// Null bij een nieuw circuit.
  final Circuit? circuit;

  @override
  State<CircuitEditScreen> createState() => _CircuitEditScreenState();
}

class _CircuitEditScreenState extends State<CircuitEditScreen> {
  late final TextEditingController _name;
  late List<String> _exerciseNames;
  late int _rounds;
  late int _workSeconds;
  late int _restSeconds;
  bool _adding = false;
  bool _busy = false;
  final _query = TextEditingController();
  final _scroll = ScrollController();
  late final ExerciseRepository _exerciseRepo;
  late final CircuitRepository _circuitRepo;
  List<Exercise> _knownExercises = [];

  bool get _isNew => widget.circuit == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.circuit?.name ?? '');
    _exerciseNames = List.of(widget.circuit?.exerciseNames ?? const []);
    _rounds = widget.circuit?.rounds ?? 3;
    _workSeconds = widget.circuit?.workSeconds ?? 40;
    _restSeconds = widget.circuit?.restSeconds ?? 20;
    _exerciseRepo = ExerciseRepository(widget.controller.client!);
    _circuitRepo = CircuitRepository(widget.controller.client!);
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
      final moved = _exerciseNames.removeAt(oldIndex);
      _exerciseNames.insert(newIndex, moved);
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geef het circuit een naam.')),
      );
      return;
    }
    if (_exerciseNames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voeg minstens één oefening toe.')),
      );
      return;
    }
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    setState(() => _busy = true);
    try {
      final saved = _isNew
          ? await _circuitRepo.create(
              Circuit(
                id: '',
                name: name,
                exerciseNames: _exerciseNames,
                rounds: _rounds,
                workSeconds: _workSeconds,
                restSeconds: _restSeconds,
              ),
              userId,
            )
          : await _circuitRepo.updateContent(
              widget.circuit!.copyWith(
                name: name,
                exerciseNames: _exerciseNames,
                rounds: _rounds,
                workSeconds: _workSeconds,
                restSeconds: _restSeconds,
              ),
            );
      if (mounted) {
        Navigator.pop(context, CircuitEditResult.saved(saved));
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
    final circuit = widget.circuit;
    if (circuit == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Circuit verwijderen?', style: AppText.cardTitle),
        content: Text(
          '"${circuit.name}" wordt verwijderd.',
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
      await _circuitRepo.delete(circuit.id);
      if (mounted) {
        Navigator.pop(context, const CircuitEditResult.deleted());
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
          _isNew ? 'Nieuw circuit' : 'Circuit aanpassen',
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
                  hintText: 'Bijvoorbeeld "Warming-up mobiliteit"',
                  hintStyle: AppText.body.copyWith(color: AppColor.inkGhost),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide.none,
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
                    NumberStepper(
                      label: 'RONDES',
                      value: _rounds,
                      onDown: () => setState(
                        () => _rounds = (_rounds - 1).clamp(1, 20),
                      ),
                      onUp: () =>
                          setState(() => _rounds = (_rounds + 1).clamp(1, 20)),
                    ),
                    const Divider(height: 24, color: AppColor.line),
                    NumberStepper(
                      label: 'WERKTIJD',
                      value: _workSeconds,
                      suffix: 's',
                      onDown: () => setState(
                        () => _workSeconds = (_workSeconds - 5).clamp(5, 600),
                      ),
                      onUp: () => setState(
                        () => _workSeconds = (_workSeconds + 5).clamp(5, 600),
                      ),
                    ),
                    const Divider(height: 24, color: AppColor.line),
                    NumberStepper(
                      label: 'RUSTTIJD',
                      value: _restSeconds,
                      suffix: 's',
                      onDown: () => setState(
                        () => _restSeconds = (_restSeconds - 5).clamp(0, 300),
                      ),
                      onUp: () => setState(
                        () => _restSeconds = (_restSeconds + 5).clamp(0, 300),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              Text('OEFENINGEN', style: AppText.overline),
              const SizedBox(height: 10),
              if (_exerciseNames.isNotEmpty)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorderExercise,
                  children: [
                    for (var i = 0; i < _exerciseNames.length; i++)
                      Padding(
                        key: ValueKey('$i-${_exerciseNames[i]}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CircuitExerciseRow(
                          index: i,
                          name: _exerciseNames[i],
                          onRemove: () =>
                              setState(() => _exerciseNames.removeAt(i)),
                          dragHandle: ReorderableDragStartListener(
                            index: i,
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
                _AddCircuitExerciseInline(
                  query: _query,
                  customExercises: _knownExercises,
                  onPick: (name) => setState(() {
                    _exerciseNames.add(name);
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
        ],
      ),
    );
  }
}

class _CircuitExerciseRow extends StatelessWidget {
  const _CircuitExerciseRow({
    required this.index,
    required this.name,
    required this.onRemove,
    this.dragHandle,
  });

  final int index;
  final String name;
  final VoidCallback onRemove;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColor.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          ?dragHandle,
          SizedBox(
            width: 20,
            child: Text(
              '${index + 1}',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(name, style: AppText.bodyStrong)),
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(7),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: AppColor.inkFaint),
            ),
          ),
        ],
      ),
    );
  }
}

class _AddCircuitExerciseInline extends StatelessWidget {
  const _AddCircuitExerciseInline({
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
