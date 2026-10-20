// circuit_edit_screen.dart — circuit maken/aanpassen
//
// Een circuit is een naam + stappen die je in rondes doorloopt, met rust
// ertussen. Elke stap is óf een tijd ("1 min schaduwboksen", telt af) óf
// een aantal herhalingen ("10× push-up", je tikt "Klaar"). Ook een
// warming-up is gewoon een circuit. Met beschrijving en video's, zoals
// bij technieken.

import 'package:flutter/material.dart';

import '../models/agenda.dart' show normalizeUrl;
import '../models/circuit.dart';
import '../models/exercise.dart';
import '../repositories/circuit_repository.dart';
import '../repositories/exercise_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../core/rest_blocks.dart';
import '../widgets/block_widgets.dart' show AddBlockButton, NumberStepper;
import '../widgets/exercise_blocks.dart';
import '../widgets/exercise_picker.dart';
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
  late bool _roundsPerBlock;
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
    _roundsPerBlock = c?.roundsPerBlock ?? true;
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
      _normalizeBlocks();
    });
  }

  // ── Blokken binnen het circuit ─────────────────────────────────────────

  List<int?> get _blocks => [for (final s in _steps) s.block];

  /// Zet de bloknummers terug op de stappen, met dezelfde rondes per blok.
  void _applyBlocks(List<int?> blocks, {Map<int, int>? rounds}) {
    final normalized = normalizeBlocks(blocks);
    for (var i = 0; i < _steps.length; i++) {
      final id = normalized[i];
      _steps[i] = id == null
          ? _steps[i].copyWith(clearBlock: true)
          : _steps[i].copyWith(
              block: id,
              blockRounds: rounds?[id] ?? _steps[i].blockRounds ?? _rounds,
            );
    }
  }

  void _normalizeBlocks() => _applyBlocks(_blocks);

  /// Rondes van het blok waar stap [i] in zit.
  int _blockRoundsOf(int i) {
    final r = blockRange(_blocks, i);
    return _steps[r.start].blockRounds ?? _rounds;
  }

  void _linkStep(int i) {
    if (i <= 0) return;
    final blocks = _blocks;
    final id = blocks[i - 1] ?? freshBlockId(blocks);
    final rounds = _steps[i - 1].block == null
        ? _rounds
        : _blockRoundsOf(i - 1);
    blocks[i - 1] = id;
    blocks[i] = id;
    setState(() => _applyBlocks(blocks, rounds: {id: rounds}));
  }

  void _unlinkStep(int i) {
    final blocks = _blocks;
    final r = blockRange(blocks, i);
    blocks[i] = null;
    if (i > r.start && i + 1 < r.end) {
      final id = freshBlockId(blocks);
      for (var k = i + 1; k < r.end; k++) {
        blocks[k] = id;
      }
    }
    setState(() => _applyBlocks(blocks));
  }

  Future<void> _editBlockRounds(int i) async {
    var value = _blockRoundsOf(i);
    final result = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Rondes van dit blok', style: AppText.title),
                const SizedBox(height: 12),
                NumberStepper(
                  label: 'RONDES',
                  value: value,
                  onDown: () =>
                      setSheet(() => value = (value - 1).clamp(1, 20)),
                  onUp: () => setSheet(() => value = (value + 1).clamp(1, 20)),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(c, value),
                  child: const Text('Klaar'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result == null || !mounted) return;
    final r = blockRange(_blocks, i);
    setState(() {
      for (var k = r.start; k < r.end; k++) {
        _steps[k] = _steps[k].copyWith(blockRounds: result);
      }
    });
  }

  /// Nieuwe stap: zelfde soort doel als de vorige stap (handig bij
  /// "1 min ..., 1 min ..."), anders 40 seconden. De rust erna begint op
  /// de standaard.
  void _addStep(String name) {
    final last = _steps.isEmpty ? null : _steps.last;
    setState(() {
      _steps.add(
        last == null
            ? CircuitStep(name: name, seconds: 40)
            : CircuitStep(
                name: name,
                seconds: last.seconds,
                reps: last.reps,
                toBurn: last.toBurn,
                extraTarget: last.extraTarget,
              ),
      );
      _adding = false;
      _query.clear();
    });
  }

  Future<void> _editTarget(int i) async {
    final result = await showModalBottomSheet<CircuitStep>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _StepTargetSheet(step: _steps[i], defaultRest: _restSeconds),
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
    final circuit = (widget.circuit ?? const Circuit(id: '', name: ''))
        .copyWith(
          name: name,
          exerciseNames: [for (final s in _steps) s.name],
          steps: _steps,
          rounds: _rounds,
          restSeconds: _restSeconds,
          description: _description.text.trim(),
          videoUrls: _videoUrls,
          roundsPerBlock: _roundsPerBlock,
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

  /// Start het circuit als losse training, zoals het nu in de editor staat
  /// (ook als je de wijzigingen nog niet hebt opgeslagen).
  void _startNow() {
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voeg minstens één oefening toe.')),
      );
      return;
    }
    final name = _name.text.trim();
    widget.controller.startCircuitTraining(
      (widget.circuit ?? const Circuit(id: '', name: '')).copyWith(
        name: name.isEmpty ? 'Circuit' : name,
        exerciseNames: [for (final s in _steps) s.name],
        steps: _steps,
        rounds: _rounds,
        restSeconds: _restSeconds,
        description: _description.text.trim(),
        videoUrls: _videoUrls,
        roundsPerBlock: _roundsPerBlock,
      ),
    );
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
    final blocks = blockInfos(_blocks);
    return Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: () => Navigator.pop(context)),
        title: Text(
          _isNew ? 'Nieuw circuit' : 'Circuit aanpassen',
          style: AppText.bodyStrong,
        ),
        actions: [
          IconButton(
            tooltip: 'Start als training',
            onPressed: _busy ? null : _startNow,
            icon: const Icon(Icons.play_arrow),
          ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 4,
                ),
                child: Column(
                  children: [
                    if (_blocks.any((b) => b != null)) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text('RONDES LOPEN', style: AppText.overline),
                      ),
                      const SizedBox(height: 6),
                      KSegmented<bool>(
                        options: const [
                          (true, 'Per blok', Icons.view_agenda_outlined),
                          (false, 'Hele circuit', Icons.loop),
                        ],
                        selected: _roundsPerBlock,
                        onChanged: (v) => setState(() => _roundsPerBlock = v),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _roundsPerBlock
                            ? 'Eerst alle rondes van blok A, dan van blok B.'
                            : 'Alle oefeningen één keer achter elkaar, en dat '
                                  '$_rounds keer.',
                        style: AppText.caption,
                      ),
                      const Divider(height: 24, color: AppColor.line),
                    ],
                    NumberStepper(
                      label: _blocks.any((b) => b != null) && _roundsPerBlock
                          ? 'RONDES (OEFENINGEN BUITEN EEN BLOK)'
                          : 'RONDES',
                      value: _rounds,
                      onDown: () =>
                          setState(() => _rounds = (_rounds - 1).clamp(1, 20)),
                      onUp: () =>
                          setState(() => _rounds = (_rounds + 1).clamp(1, 20)),
                    ),
                    const Divider(height: 24, color: AppColor.line),
                    NumberStepper(
                      label: 'STANDAARD RUST NA ELKE OEFENING',
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
                'Tik op een oefening om te kiezen tussen tijd, herhalingen of '
                'tot verzuring, en hoeveel rust erna (of geen). Via ⋮ koppel '
                'je oefeningen tot een blok met eigen rondes.',
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
                      Column(
                        key: ValueKey('$i-${_steps[i].name}'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (blocks[i].inBlock && blocks[i].isFirst)
                            BlockHeader(
                              info: blocks[i],
                              rounds: _blockRoundsOf(i),
                              restSeconds: 0,
                              onEditRest: () {
                                if (_roundsPerBlock) _editBlockRounds(i);
                              },
                              label: _roundsPerBlock
                                  ? 'Blok ${blocks[i].letter} · '
                                        '${_blockRoundsOf(i)} '
                                        '${_blockRoundsOf(i) == 1 ? 'ronde' : 'rondes'}'
                                  : 'Blok ${blocks[i].letter}',
                            ),
                          BlockFrame(
                            info: blocks[i],
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _CircuitStepRow(
                                index: i,
                                step: _steps[i],
                                defaultRest: _restSeconds,
                                onTarget: () => _editTarget(i),
                                menu: PopupMenuButton<String>(
                                  tooltip: 'Blok',
                                  padding: EdgeInsets.zero,
                                  iconSize: 18,
                                  icon: const Icon(
                                    Icons.more_vert,
                                    color: AppColor.inkFaint,
                                  ),
                                  onSelected: (a) => switch (a) {
                                    'link' => _linkStep(i),
                                    'unlink' => _unlinkStep(i),
                                    _ => _editBlockRounds(i),
                                  },
                                  itemBuilder: (_) => [
                                    if (i > 0)
                                      const PopupMenuItem(
                                        value: 'link',
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.link),
                                          title: Text(
                                            'Koppel aan oefening erboven',
                                          ),
                                          subtitle: Text(
                                            'Samen een blok met eigen rondes',
                                          ),
                                        ),
                                      ),
                                    if (blocks[i].inBlock) ...[
                                      if (_roundsPerBlock)
                                        const PopupMenuItem(
                                          value: 'rounds',
                                          child: ListTile(
                                            dense: true,
                                            contentPadding: EdgeInsets.zero,
                                            leading: Icon(Icons.repeat),
                                            title: Text('Rondes van het blok'),
                                          ),
                                        ),
                                      const PopupMenuItem(
                                        value: 'unlink',
                                        child: ListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          leading: Icon(Icons.link_off),
                                          title: Text('Losmaken uit blok'),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                onRemove: () => setState(() {
                                  _steps.removeAt(i);
                                  _normalizeBlocks();
                                }),
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
                          ),
                        ],
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
    required this.defaultRest,
    required this.onTarget,
    required this.onRemove,
    this.dragHandle,
    this.menu,
  });

  final int index;
  final CircuitStep step;
  final int defaultRest;
  final VoidCallback onTarget;
  final VoidCallback onRemove;
  final Widget? dragHandle;
  final Widget? menu;

  String get _restLabel {
    final rest = step.restSeconds ?? defaultRest;
    final text = rest > 0 ? '${rest}s rust erna' : 'geen rust erna';
    return step.restSeconds == null ? '$text (standaard)' : text;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTarget,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.name, style: AppText.bodyStrong),
                  Text(
                    _restLabel,
                    style: AppText.caption.copyWith(
                      fontSize: 11,
                      color: step.restSeconds == null
                          ? AppColor.inkFaint
                          : AppColor.inkMuted,
                    ),
                  ),
                ],
              ),
            ),
            ActionChip(
              avatar: Icon(
                switch (step.kind) {
                  StepKind.time => Icons.timer_outlined,
                  StepKind.reps => Icons.repeat,
                  StepKind.burn => Icons.local_fire_department_outlined,
                },
                size: 16,
                color: step.toBurn ? AppColor.amber : AppColor.ice,
              ),
              label: Text(
                step.targetLabel,
                style: AppText.bodyStrong.copyWith(
                  color: step.toBurn ? AppColor.amber : AppColor.ice,
                ),
              ),
              onPressed: onTarget,
            ),
            ?menu,
            IconButton(
              tooltip: 'Verwijderen',
              onPressed: onRemove,
              icon: const Icon(Icons.close, size: 16, color: AppColor.inkFaint),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kiest het doel van een stap — een tijd (in stappen van 5 s), een aantal
/// herhalingen of tot verzuring (met eventueel nog herhalingen erna) — en
/// hoeveel rust er na deze stap komt.
class _StepTargetSheet extends StatefulWidget {
  const _StepTargetSheet({required this.step, required this.defaultRest});

  final CircuitStep step;
  final int defaultRest;

  @override
  State<_StepTargetSheet> createState() => _StepTargetSheetState();
}

class _StepTargetSheetState extends State<_StepTargetSheet> {
  late StepKind _kind = widget.step.kind;
  late int _seconds = widget.step.seconds ?? 60;
  late int _reps = widget.step.reps ?? 10;
  late final _extra = TextEditingController(
    text: widget.step.toBurn ? widget.step.extraTarget : '',
  );
  late bool _defaultRest = widget.step.restSeconds == null;
  late int _rest = widget.step.restSeconds ?? widget.defaultRest;
  late List<String> _videos = List.of(widget.step.videoUrls);

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  CircuitStep _result() {
    final name = widget.step.name;
    final rest = _defaultRest ? null : _rest;
    final step = switch (_kind) {
      StepKind.time => CircuitStep(
        name: name,
        seconds: _seconds,
        restSeconds: rest,
      ),
      StepKind.reps => CircuitStep(name: name, reps: _reps, restSeconds: rest),
      StepKind.burn => CircuitStep(
        name: name,
        toBurn: true,
        extraTarget: _extra.text.trim(),
        restSeconds: rest,
      ),
    };
    return step.copyWith(
      videoUrls: _videos,
      block: widget.step.block,
      blockRounds: widget.step.blockRounds,
    );
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context);
    return SingleChildScrollView(
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
          Text(widget.step.name, style: AppText.title),
          const SizedBox(height: 14),
          KSegmented<StepKind>(
            options: const [
              (StepKind.time, 'Tijd', Icons.timer_outlined),
              (StepKind.reps, 'Reps', Icons.repeat),
              (
                StepKind.burn,
                'Verzuring',
                Icons.local_fire_department_outlined,
              ),
            ],
            selected: _kind,
            onChanged: (v) => setState(() => _kind = v),
          ),
          const SizedBox(height: 16),
          switch (_kind) {
            StepKind.time => NumberStepper(
              label: 'TIJD',
              value: _seconds,
              suffix: 's',
              onDown: () =>
                  setState(() => _seconds = (_seconds - 5).clamp(5, 900)),
              onUp: () =>
                  setState(() => _seconds = (_seconds + 5).clamp(5, 900)),
            ),
            StepKind.reps => NumberStepper(
              label: 'HERHALINGEN',
              value: _reps,
              suffix: '×',
              onDown: () => setState(() => _reps = (_reps - 1).clamp(1, 200)),
              onUp: () => setState(() => _reps = (_reps + 1).clamp(1, 200)),
            ),
            StepKind.burn => TextField(
              controller: _extra,
              style: AppText.body,
              decoration: const InputDecoration(
                labelText: 'Herhalingen na de verzuring (optioneel)',
                hintText: 'Bv. 5–10',
              ),
            ),
          },
          const SizedBox(height: 16),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _defaultRest,
            onChanged: (v) => setState(() => _defaultRest = v),
            title: Text('Standaard rust erna', style: AppText.bodyStrong),
            subtitle: Text(
              widget.defaultRest > 0
                  ? '${widget.defaultRest}s, zoals ingesteld bij het circuit'
                  : 'Geen rust, zoals ingesteld bij het circuit',
              style: AppText.caption,
            ),
          ),
          if (!_defaultRest)
            NumberStepper(
              label: 'RUST NA DEZE OEFENING',
              value: _rest,
              suffix: 's',
              onDown: () => setState(() => _rest = (_rest - 5).clamp(0, 300)),
              onUp: () => setState(() => _rest = (_rest + 5).clamp(0, 300)),
            ),
          const SizedBox(height: 16),
          const KLabel("Video's bij deze oefening"),
          const SizedBox(height: 8),
          VideoLinksEditor(
            urls: _videos,
            onChanged: (v) => setState(() => _videos = v),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context, _result()),
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
  Widget build(BuildContext context) => ExercisePicker(
    query: query,
    customExercises: customExercises,
    onPick: onPick,
    onCancel: onCancel,
  );
}
