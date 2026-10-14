// circuit_edit_screen.dart — circuit maken/aanpassen
//
// Een circuit is een naam + stappen die je in rondes doorloopt, met rust
// ertussen. Elke stap is óf een tijd ("1 min schaduwboksen", telt af) óf
// een aantal herhalingen ("10× push-up", je tikt "Klaar"). Ook een
// warming-up is gewoon een circuit. Met beschrijving en video's, zoals
// bij technieken.

import 'package:flutter/material.dart';

import '../core/exercise_library.dart';
import '../models/agenda.dart' show normalizeUrl;
import '../models/circuit.dart';
import '../models/exercise.dart';
import '../repositories/circuit_repository.dart';
import '../repositories/exercise_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/block_widgets.dart' show AddBlockButton, NumberStepper;
import '../widgets/kinetic.dart';
import '../widgets/video_link_row.dart';

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
  late final TextEditingController _description;
  final _newVideo = TextEditingController();
  late List<CircuitStep> _steps;
  late List<String> _videoUrls;
  late int _rounds;
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
    final c = widget.circuit;
    _name = TextEditingController(text: c?.name ?? '');
    _description = TextEditingController(text: c?.description ?? '');
    _steps = List.of(c?.effectiveSteps ?? const []);
    _videoUrls = List.of(c?.videoUrls ?? const []);
    _rounds = c?.rounds ?? 3;
    _restSeconds = c?.restSeconds ?? 20;
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
    _description.dispose();
    _newVideo.dispose();
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

  void _reorderStep(int oldIndex, int newIndex) {
    setState(() {
      final moved = _steps.removeAt(oldIndex);
      _steps.insert(newIndex, moved);
    });
  }

  /// Nieuwe stap: zelfde soort doel als de vorige stap (handig bij
  /// "1 min ..., 1 min ..."), anders 40 seconden.
  void _addStep(String name) {
    final last = _steps.isEmpty ? null : _steps.last;
    setState(() {
      _steps.add(
        last == null || last.isTimed
            ? CircuitStep(name: name, seconds: last?.seconds ?? 40)
            : CircuitStep(name: name, reps: last.reps),
      );
      _adding = false;
      _query.clear();
    });
  }

  Future<void> _editTarget(int i) async {
    final result = await showModalBottomSheet<CircuitStep>(
      context: context,
      builder: (_) => _StepTargetSheet(step: _steps[i]),
    );
    if (result != null) setState(() => _steps[i] = result);
  }

  void _addVideo({bool askLabel = true}) {
    final url = normalizeUrl(_newVideo.text);
    if (url.isEmpty) return;
    setState(() {
      _videoUrls.add(url);
      _newVideo.clear();
    });
    // Meteen een naam laten geven (overslaan mag).
    if (askLabel) editVideoLabel(context, url);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Geef het circuit een naam.')),
      );
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voeg minstens één oefening toe.')),
      );
      return;
    }
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    // Een link die je nog in het veld had staan telt ook mee.
    if (_newVideo.text.trim().isNotEmpty) _addVideo(askLabel: false);
    setState(() => _busy = true);
    final circuit = (widget.circuit ?? const Circuit(id: '', name: '')).copyWith(
      name: name,
      exerciseNames: [for (final s in _steps) s.name],
      steps: _steps,
      rounds: _rounds,
      restSeconds: _restSeconds,
      description: _description.text.trim(),
      videoUrls: _videoUrls,
    );
    try {
      final saved = _isNew
          ? await _circuitRepo.create(circuit, userId)
          : await _circuitRepo.updateContent(circuit);
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
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(
          _isNew ? 'Nieuw circuit' : 'Circuit aanpassen',
          style: AppText.bodyStrong,
        ),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Verwijderen',
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
              16,
              12,
              16,
              100 + MediaQuery.of(context).padding.bottom,
            ),
            children: [
              const KLabel('Naam'),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                style: AppText.bodyStrong,
                decoration: const InputDecoration(
                  hintText: 'Bijvoorbeeld "Conditie + schaduwboksen"',
                ),
              ),
              const SizedBox(height: 16),
              const KLabel('Beschrijving (optioneel)'),
              const SizedBox(height: 8),
              TextField(
                controller: _description,
                style: AppText.body,
                minLines: 2,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'Bv. tempo hoog, techniek boven snelheid',
                ),
              ),
              const SizedBox(height: 16),
              KCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
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
                      label: 'RUST TUSSEN STAPPEN',
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
              const SizedBox(height: 20),
              const KLabel('Stappen'),
              const SizedBox(height: 4),
              Text(
                'Tik op de tijd of het aantal om te kiezen tussen tijd en '
                'herhalingen.',
                style: AppText.caption,
              ),
              const SizedBox(height: 10),
              if (_steps.isNotEmpty)
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorderItem: _reorderStep,
                  children: [
                    for (var i = 0; i < _steps.length; i++)
                      Padding(
                        key: ValueKey('$i-${_steps[i].name}'),
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CircuitStepRow(
                          index: i,
                          step: _steps[i],
                          onTarget: () => _editTarget(i),
                          onRemove: () => setState(() => _steps.removeAt(i)),
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
                  onPick: _addStep,
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
              const SizedBox(height: 20),
              const KLabel("Video's (optioneel)"),
              const SizedBox(height: 8),
              for (var i = 0; i < _videoUrls.length; i++)
                VideoLinkRow(
                  url: _videoUrls[i],
                  onRemove: () => setState(() => _videoUrls.removeAt(i)),
                ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _newVideo,
                      keyboardType: TextInputType.url,
                      style: AppText.body,
                      onSubmitted: (_) => _addVideo(),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'Link naar video (YouTube, Instagram, …)',
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Video toevoegen',
                    onPressed: () => _addVideo(),
                    icon: const Icon(Icons.add_link, color: AppColor.ice),
                  ),
                ],
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
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

class _CircuitStepRow extends StatelessWidget {
  const _CircuitStepRow({
    required this.index,
    required this.step,
    required this.onTarget,
    required this.onRemove,
    this.dragHandle,
  });

  final int index;
  final CircuitStep step;
  final VoidCallback onTarget;
  final VoidCallback onRemove;
  final Widget? dragHandle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
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
          Expanded(child: Text(step.name, style: AppText.bodyStrong)),
          ActionChip(
            avatar: Icon(
              step.isTimed ? Icons.timer_outlined : Icons.repeat,
              size: 16,
              color: AppColor.ice,
            ),
            label: Text(
              step.targetLabel,
              style: AppText.bodyStrong.copyWith(color: AppColor.ice),
            ),
            onPressed: onTarget,
          ),
          IconButton(
            tooltip: 'Verwijderen',
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16, color: AppColor.inkFaint),
          ),
        ],
      ),
    );
  }
}

/// Kiest het doel van een stap: een tijd (in stappen van 5 s) of een aantal
/// herhalingen.
class _StepTargetSheet extends StatefulWidget {
  const _StepTargetSheet({required this.step});

  final CircuitStep step;

  @override
  State<_StepTargetSheet> createState() => _StepTargetSheetState();
}

class _StepTargetSheetState extends State<_StepTargetSheet> {
  late bool _timed = widget.step.isTimed;
  late int _seconds = widget.step.seconds ?? 60;
  late int _reps = widget.step.reps ?? 10;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        20 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.step.name, style: AppText.title),
          const SizedBox(height: 14),
          KSegmented<bool>(
            options: const [
              (true, 'Tijd', Icons.timer_outlined),
              (false, 'Herhalingen', Icons.repeat),
            ],
            selected: _timed,
            onChanged: (v) => setState(() => _timed = v),
          ),
          const SizedBox(height: 16),
          if (_timed)
            NumberStepper(
              label: 'TIJD',
              value: _seconds,
              suffix: 's',
              onDown: () =>
                  setState(() => _seconds = (_seconds - 5).clamp(5, 900)),
              onUp: () =>
                  setState(() => _seconds = (_seconds + 5).clamp(5, 900)),
            )
          else
            NumberStepper(
              label: 'HERHALINGEN',
              value: _reps,
              suffix: '×',
              onDown: () => setState(() => _reps = (_reps - 1).clamp(1, 200)),
              onUp: () => setState(() => _reps = (_reps + 1).clamp(1, 200)),
            ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _timed
                  ? CircuitStep(name: widget.step.name, seconds: _seconds)
                  : CircuitStep(name: widget.step.name, reps: _reps),
            ),
            child: const Text('Klaar'),
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
