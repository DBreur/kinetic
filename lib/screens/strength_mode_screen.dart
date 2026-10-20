// strength_mode_screen.dart — live krachttraining
//
// Zelfde opzet als mat_mode_screen.dart: dit scherm is een "view" over
// StrengthSessionController: alle data (oefeningen, glucose, timers) leeft in
// de controller, niet hier. Zo blijft de sessie gewoon doorlopen (klok,
// Nightscout-polling, alarm) als je dit scherm verlaat om naar een ander
// tabblad te gaan — zie ShellScreen voor de permanente balk die de actieve
// sessie laat zien en heropent.

import 'package:flutter/material.dart';

import '../core/rest_blocks.dart';
import '../models/exercise.dart';
import '../models/training_session.dart';
import '../repositories/circuit_repository.dart';
import '../state/strength_session_controller.dart';
import '../services/system_bars.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/number_input.dart';
import '../widgets/glucose_alarm.dart' show SnoozeBanner;
import '../widgets/info_sheet.dart';
import '../widgets/exercise_blocks.dart';
import '../widgets/exercise_picker.dart';
import '../widgets/kinetic.dart';
import '../widgets/block_widgets.dart' show AddBlockButton;
import '../widgets/manual_glucose.dart' show FingerHistoryStrip;
import '../widgets/nutrition_log.dart';
import '../widgets/set_outcome_sheet.dart';
import '../widgets/spotify_panel.dart';
import 'exercise_history_screen.dart';
import 'mat_mode_screen.dart' show GlucoseBand;

class StrengthModeScreen extends StatefulWidget {
  final StrengthSessionController controller;

  const StrengthModeScreen({super.key, required this.controller});

  @override
  State<StrengthModeScreen> createState() => _StrengthModeScreenState();
}

class _StrengthModeScreenState extends State<StrengthModeScreen> {
  final _query = TextEditingController();
  final _scroll = ScrollController();

  StrengthSessionController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    SystemBars.enterSession();
  }

  @override
  void dispose() {
    SystemBars.exitSession();
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _openNutritionSheet() {
    showNutritionSheet(
      context,
      presets: _c.appController.profile?.carbPresets ?? const [],
      entries: _c.nutrition,
      onPick: _c.logNutrition,
      onRemove: _c.removeNutrition,
    );
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

  /// Handmatig in- of uitgeklapt; anders klapt een oefening vanzelf in
  /// zodra al zijn sets af zijn.
  final Map<LiveExercise, bool> _collapsedOverride = {};

  static bool _allDone(LiveExercise e) =>
      e.sets.isNotEmpty && e.sets.every((s) => s.done);

  /// Een losse oefening klapt in zodra hij af is; een oefening in een blok
  /// pas als het hele blok af is (je wisselt er per ronde tussen).
  bool _isCollapsed(LiveExercise e) {
    final manual = _collapsedOverride[e];
    if (manual != null) return manual;
    final ei = _c.exercises.indexOf(e);
    if (ei < 0) return _allDone(e);
    final r = _c.blockOf(ei);
    return _c.exercises.sublist(r.start, r.end).every(_allDone);
  }

  void _toggleCollapsed(LiveExercise e) =>
      setState(() => _collapsedOverride[e] = !_isCollapsed(e));

  /// Klapt het hele blok van [ei] in (of uit als alles al ingeklapt is).
  void _toggleBlock(int ei) {
    final r = _c.blockOf(ei);
    final members = _c.exercises.sublist(r.start, r.end);
    final collapse = !members.every(_isCollapsed);
    setState(() {
      for (final e in members) {
        _collapsedOverride[e] = collapse;
      }
    });
  }

  bool _blockCollapsed(int ei) {
    final r = _c.blockOf(ei);
    return _c.exercises.sublist(r.start, r.end).every(_isCollapsed);
  }

  /// Aantal rondes van het blok van [ei] = het grootste aantal sets.
  int _roundsInBlock(int ei) {
    final r = _c.blockOf(ei);
    var rounds = 0;
    for (var i = r.start; i < r.end; i++) {
      final n = _c.exercises[i].sets.length;
      if (n > rounds) rounds = n;
    }
    return rounds;
  }

  Future<void> _editRest(int ei) async {
    final inBlock = _c.blockOf(ei).end - _c.blockOf(ei).start > 1;
    final choice = await showRestPicker(
      context,
      current: _c.exercises[ei].restSeconds,
      defaultRest: _c.defaultRest,
      title: inBlock
          ? 'Rust na elke ronde van het blok'
          : 'Rust na elke set · ${_c.exercises[ei].name}',
    );
    if (choice == null) return;
    _c.setRest(ei, choice.seconds);
  }

  void _onBlockAction(int ei, ExerciseBlockAction action) {
    switch (action) {
      case ExerciseBlockAction.link:
        _c.linkWithPrevious(ei);
      case ExerciseBlockAction.unlink:
        _c.unlink(ei);
      case ExerciseBlockAction.rest:
        _editRest(ei);
    }
  }

  void _openHistory(String name) {
    Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ExerciseHistoryScreen(
          exerciseName: name,
          controller: _c.appController,
        ),
      ),
    );
  }

  Future<void> _pickExercise(String name) async {
    setState(() {
      _query.clear();
    });
    await _c.pickExercise(name);
  }

  Future<void> _pickCircuit() async {
    final client = _c.appController.client;
    final userId = _c.appController.user?.id;
    if (client == null || userId == null) return;
    List<Circuit> saved = const [];
    try {
      saved = await CircuitRepository(client).listForUser(userId);
    } catch (_) {
      // Picker toont dan "nog geen circuits" i.p.v. te crashen.
    }
    if (!mounted) return;
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
            if (saved.isEmpty)
              Text(
                'Nog geen circuits — maak er eerst een aan via Instellingen.',
                style: AppText.caption,
              )
            else
              for (final c in saved)
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
                ),
          ],
        ),
      ),
    );
    if (chosen != null) _c.addCircuit(chosen);
  }

  Future<void> _confirmFinish() async {
    if (_c.saving) return;
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text('Krachttraining afronden?', style: AppText.cardTitle),
        content: Text(
          'Je sets worden opgeslagen.',
          style: AppText.body.copyWith(color: AppColor.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, 'continue'),
            child: const Text('Doorgaan'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, 'discard'),
            style: TextButton.styleFrom(foregroundColor: AppColor.redBright),
            child: const Text('Niet opslaan'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, 'save'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
            child: const Text('Afronden'),
          ),
        ],
      ),
    );
    if (!mounted || result == null || result == 'continue') return;

    if (result == 'discard') {
      Navigator.pop(context, false);
      return;
    }

    final ok = await _c.saveSession();
    if (mounted) Navigator.pop(context, ok);
  }

  int get _totalSets => _c.exercises.fold(0, (n, e) => n + e.sets.length);
  int get _doneSets =>
      _c.exercises.fold(0, (n, e) => n + e.sets.where((s) => s.done).length);
  int get _volume => _c.exercises
      .fold<double>(
        0,
        (n, e) =>
            n +
            e.sets.where((s) => s.done).fold(0, (m, s) => m + s.kg * s.reps),
      )
      .round();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final blocks = blockInfos([for (final e in _c.exercises) e.block]);
        return Scaffold(
          backgroundColor: AppColor.bg,
          // Spotify rechtsonder — niet in de glucosebalk, daar schoof hij de
          // sessietijd onder de camera.
          floatingActionButton:
              (_c.appController.profile?.spotifyButton.onStrength ?? true)
              ? const SpotifyFab()
              : null,
          // Bovenkant niet inspringen: de glucosebalk loopt zelf door tot de
          // rand (ook achter de camera-uitsparing) en zet zijn inhoud eronder.
          body: SafeArea(
            top: false,
            child: Stack(
              children: [
                Column(
                  children: [
                    GlucoseBand(
                      reading: _c.reading,
                      elapsed: _c.elapsed,
                      isPaused: _c.isPaused,
                      showPauseButton: _c.showPauseButton,
                      onStop: _confirmFinish,
                      onMinimize: () => Navigator.pop(context),
                      onTogglePause: _c.isPaused ? _c.resume : _c.pause,
                      onEnterReading: _c.isFinger
                          ? () => _c.recordManualReading(context)
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: KCard(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                const KDot(color: AppColor.ice, size: 8),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _c.title,
                                    style: AppText.cardTitle,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                KPill(
                                  text: '$_doneSets / $_totalSets sets',
                                  color: AppColor.ice,
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(
                                AppRadius.chip,
                              ),
                              child: LinearProgressIndicator(
                                value: _totalSets == 0
                                    ? 0
                                    : _doneSets / _totalSets,
                                minHeight: 4,
                                backgroundColor: AppColor.surfaceHighest,
                                valueColor: const AlwaysStoppedAnimation(
                                  AppColor.ice,
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                const KLabel('Volume'),
                                const SizedBox(width: 8),
                                Text(
                                  '$_volume kg',
                                  style: AppText.bodyStrong.copyWith(
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SnoozeBanner(
                      guard: _c.appController.alarmGuard,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    ),
                    if (_c.activeTimedSet case final active?)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _TimedSetBanner(
                          active: active,
                          paused: _c.isPaused,
                          onSkipPrep: _c.skipSetPrep,
                          onStop: _c.stopSetTimer,
                        ),
                      ),
                    if (_c.restLeft > 0)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _RestBanner(
                          secondsLeft: _c.restLeft,
                          total: _c.restTotal,
                          next: _c.restNext,
                          onSkip: _c.skipRest,
                        ),
                      ),
                    Expanded(
                      child: ListView(
                        controller: _scroll,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          16,
                          16,
                          // Ruimte voor de zwevende Spotify-knop.
                          72 + MediaQuery.of(context).padding.bottom,
                        ),
                        children: [
                          if (_c.isFinger) ...[
                            FingerHistoryStrip(
                              entries: _c.fingerEntries,
                              onTapEntry: (e) => _c.editFingerEntry(context, e),
                            ),
                            const SizedBox(height: 14),
                          ],
                          NutritionQuickButton(
                            count: _c.nutrition.length,
                            onTap: _openNutritionSheet,
                          ),
                          const SizedBox(height: 14),
                          if (_c.exercises.isNotEmpty)
                            ReorderableListView(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              onReorderItem: _c.reorderExercise,
                              children: [
                                for (var ei = 0; ei < _c.exercises.length; ei++)
                                  Column(
                                    key: ValueKey(_c.exercises[ei]),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (blocks[ei].inBlock &&
                                          blocks[ei].isFirst)
                                        BlockHeader(
                                          info: blocks[ei],
                                          rounds: _roundsInBlock(ei),
                                          restSeconds: _c.restAfter(ei),
                                          onEditRest: () => _editRest(ei),
                                          collapsed: _blockCollapsed(ei),
                                          onToggle: () => _toggleBlock(ei),
                                        ),
                                      BlockFrame(
                                        info: blocks[ei],
                                        child: _ExerciseCard(
                                          exercise: _c.exercises[ei],
                                          onOpenHistory: () => _openHistory(
                                            _c.exercises[ei].name,
                                          ),
                                          onRemove: () => _c.removeExercise(ei),
                                          onRemoveSet: (si) =>
                                              _c.removeSet(ei, si),
                                          collapsed: _isCollapsed(
                                            _c.exercises[ei],
                                          ),
                                          onToggleCollapsed: () =>
                                              _toggleCollapsed(
                                                _c.exercises[ei],
                                              ),
                                          onAddVideo: (url) =>
                                              _c.addExerciseVideo(
                                                _c.exercises[ei].name,
                                                url,
                                              ),
                                          menu: ExerciseBlockMenu(
                                            canLink: ei > 0,
                                            inBlock: blocks[ei].inBlock,
                                            onSelected: (a) =>
                                                _onBlockAction(ei, a),
                                          ),
                                          restHint: blocks[ei].inBlock
                                              ? null
                                              : _c.exercises[ei].restSeconds ==
                                                    null
                                              ? null
                                              : '${formatRest(_c.restAfter(ei))} '
                                                    'rust na elke set',
                                          onAddSet: () => _c.addSet(ei),
                                          onSetChanged: (si, patch) =>
                                              _c.updateSet(ei, si, patch),
                                          onStartSetTimer: (si) =>
                                              _c.startSetTimer(ei, si),
                                          onToggleSetMode: (si, mode) =>
                                              _c.setSetMode(ei, si, mode),
                                          info: _c.matchingCustomExercise(
                                            _c.exercises[ei].name,
                                          ),
                                          dragHandle:
                                              ReorderableDragStartListener(
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
                              ],
                            ),
                          if (_c.circuitOnly)
                            const SizedBox.shrink()
                          else if (_c.adding)
                            _AddExerciseCard(
                              query: _query,
                              customExercises: _c.customExercises,
                              onPick: _pickExercise,
                              onCancel: () {
                                _c.setAdding(false);
                                _query.clear();
                              },
                            )
                          else
                            AddBlockButton(
                              label: 'Oefening toevoegen',
                              onTap: () {
                                _c.setAdding(true);
                                _scrollToBottom();
                              },
                            ),
                          const SizedBox(height: 14),
                          for (var ci = 0; ci < _c.circuits.length; ci++)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _CircuitCard(
                                liveCircuit: _c.circuits[ci],
                                videosForStep: _c.videosForStep,
                                onStart: () => _c.startCircuit(ci),
                                onSkip: () => _c.skipCircuitPhase(ci),
                                onStop: () => _c.stopCircuit(ci),
                                onTogglePause: () => _c.togglePauseCircuit(ci),
                                onRemove: _c.circuitOnly
                                    ? null
                                    : () => _c.removeCircuit(ci),
                              ),
                            ),
                          // Een losse circuittraining is precies dat ene
                          // circuit — geen extra circuits of oefeningen.
                          if (!_c.circuitOnly)
                            AddBlockButton(
                              label: 'Circuit toevoegen',
                              onTap: _pickCircuit,
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_c.saving)
                  Container(
                    color: Colors.black.withValues(alpha: .55),
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final LiveExercise exercise;
  final VoidCallback onRemove;
  final ValueChanged<int> onRemoveSet;
  final Widget? menu;

  /// Bewaart een nieuwe video bij deze oefening in je oefeningen.
  final Future<void> Function(String url) onAddVideo;

  /// Eigen rust van een losse oefening, als die afwijkt van de standaard.
  final String? restHint;

  /// Ingeklapt: alleen de kopregel (naam, voortgang). Tik op de naam of het
  /// pijltje om uit/in te klappen.
  final bool collapsed;
  final VoidCallback onToggleCollapsed;
  final VoidCallback onAddSet;
  final VoidCallback onOpenHistory;
  final void Function(int setIndex, LiveSet Function(LiveSet)) onSetChanged;
  final void Function(int setIndex) onStartSetTimer;
  final void Function(int setIndex, SetMode mode) onToggleSetMode;
  final Widget? dragHandle;

  /// De eigen oefening (met beschrijving en video's), als die er is.
  final Exercise? info;
  const _ExerciseCard({
    required this.exercise,
    this.info,
    required this.onRemove,
    required this.onRemoveSet,
    required this.onAddVideo,
    required this.collapsed,
    required this.onToggleCollapsed,
    this.menu,
    this.restHint,
    required this.onAddSet,
    required this.onOpenHistory,
    required this.onSetChanged,
    required this.onStartSetTimer,
    required this.onToggleSetMode,
    this.dragHandle,
  });

  String get _description => (info?.description ?? '').isNotEmpty
      ? info!.description
      : exercise.description;
  List<String> get _videoUrls => info?.videoUrls ?? const [];

  void _showDescription(BuildContext context) => showInfoSheet(
    context,
    title: exercise.name,
    description: _description,
    videoUrls: _videoUrls,
    onAddVideo: onAddVideo,
  );

  String _fmtKg(double kg) =>
      kg % 1 == 0 ? kg.toInt().toString() : kg.toString();

  String _formatLastPerformance(List<ExerciseSet> sets) =>
      sets.map((s) => s.summary).join(', ');

  @override
  Widget build(BuildContext context) {
    final done = exercise.sets.where((s) => s.done).length;
    final allDone = exercise.sets.isNotEmpty && done == exercise.sets.length;
    return Container(
      margin: EdgeInsets.only(bottom: collapsed ? 6 : 12),
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: collapsed ? 6 : 14,
      ),
      decoration: BoxDecoration(
        color: allDone && collapsed ? AppColor.greenWash : AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ?dragHandle,
              Expanded(
                child: InkWell(
                  onTap: onToggleCollapsed,
                  child: Row(
                    children: [
                      if (collapsed && allDone) ...[
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: AppColor.greenBright,
                        ),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          exercise.name,
                          style: collapsed
                              ? AppText.bodyStrong
                              : AppText.cardTitle,
                          maxLines: collapsed ? 1 : null,
                          overflow: collapsed ? TextOverflow.ellipsis : null,
                        ),
                      ),
                      Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                        size: 18,
                        color: AppColor.inkFaint,
                      ),
                    ],
                  ),
                ),
              ),
              InkWell(
                onTap: onOpenHistory,
                borderRadius: BorderRadius.circular(99),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    Icons.show_chart,
                    size: 16,
                    color: AppColor.inkFaint,
                  ),
                ),
              ),
              InkWell(
                onTap: () => _showDescription(context),
                borderRadius: BorderRadius.circular(99),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    _videoUrls.isNotEmpty
                        ? Icons.play_circle_outline
                        : Icons.info_outline,
                    size: 16,
                    color: _videoUrls.isNotEmpty
                        ? AppColor.ice
                        : AppColor.inkFaint,
                  ),
                ),
              ),
              Text(
                '$done/${exercise.sets.length}',
                style: AppText.caption.copyWith(
                  color: done == exercise.sets.length
                      ? AppColor.greenBright
                      : AppColor.inkFaint,
                ),
              ),
              ?menu,
              InkWell(
                onTap: onRemove,
                borderRadius: BorderRadius.circular(7),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColor.surfaceHigh,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
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
          if (!collapsed) ...[
            if (restHint != null) ...[
              const SizedBox(height: 3),
              Text(
                restHint!,
                style: AppText.caption.copyWith(
                  fontSize: 11,
                  color: AppColor.tealBright,
                ),
              ),
            ],
            if (exercise.lastPerformance != null &&
                exercise.lastPerformance!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                'Vorige keer: ${_formatLastPerformance(exercise.lastPerformance!)}',
                style: AppText.caption.copyWith(fontSize: 11),
              ),
            ],
            if (exercise.personalRecord != null &&
                exercise.personalRecord! > 0) ...[
              const SizedBox(height: 3),
              Row(
                children: [
                  const Icon(
                    Icons.emoji_events_outlined,
                    size: 12,
                    color: AppColor.amber,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Record: ${_fmtKg(exercise.personalRecord!)}kg',
                    style: AppText.caption.copyWith(
                      fontSize: 11,
                      color: AppColor.amber,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            for (var si = 0; si < exercise.sets.length; si++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: _SetRow(
                  num: si + 1,
                  liveSet: exercise.sets[si],
                  onRemove: () => onRemoveSet(si),
                  onChanged: (patch) => onSetChanged(si, patch),
                  onStartTimer: () => onStartSetTimer(si),
                  onToggleMode: (mode) => onToggleSetMode(si, mode),
                ),
              ),
            const SizedBox(height: 8),
            InkWell(
              onTap: onAddSet,
              borderRadius: BorderRadius.circular(AppRadius.sm + 3),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColor.lineStrong),
                  borderRadius: BorderRadius.circular(AppRadius.sm + 3),
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
        ],
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final int num;
  final LiveSet liveSet;
  final VoidCallback onRemove;
  final void Function(LiveSet Function(LiveSet)) onChanged;
  final VoidCallback onStartTimer;
  final ValueChanged<SetMode> onToggleMode;
  const _SetRow({
    required this.num,
    required this.liveSet,
    required this.onRemove,
    required this.onChanged,
    required this.onStartTimer,
    required this.onToggleMode,
  });

  String _fmtMmSs(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Widget _stepper({
    required String value,
    required String unit,
    required VoidCallback onDown,
    required VoidCallback onUp,
    VoidCallback? onTapValue,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(label: '−', onTap: onDown),
            // Tik op het getal om het zelf te typen.
            InkWell(
              onTap: onTapValue,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 40,
                child: Text(
                  value,
                  textAlign: TextAlign.center,
                  style: AppText.cardTitle,
                ),
              ),
            ),
            _StepButton(label: '+', onTap: onUp),
          ],
        ),
        Text(
          unit,
          style: AppText.caption.copyWith(
            fontSize: 9,
            color: AppColor.inkFaint,
          ),
        ),
      ],
    );
  }

  Widget _timeControl() {
    final seconds = liveSet.seconds ?? 30;
    if (liveSet.timerRunning) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_fmtMmSs(liveSet.timeLeft), style: AppText.cardTitle),
          Text(
            'loopt...',
            style: AppText.caption.copyWith(
              fontSize: 9,
              color: AppColor.inkFaint,
            ),
          ),
        ],
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(
              label: '−',
              onTap: () =>
                  onChanged((s) => s..seconds = (seconds - 5).clamp(5, 600)),
            ),
            InkWell(
              onTap: onStartTimer,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 48,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.play_arrow,
                      size: 14,
                      color: AppColor.inkMuted,
                    ),
                    Text('${seconds}s', style: AppText.cardTitle),
                  ],
                ),
              ),
            ),
            _StepButton(
              label: '+',
              onTap: () =>
                  onChanged((s) => s..seconds = (seconds + 5).clamp(5, 600)),
            ),
          ],
        ),
        Text(
          'tijd',
          style: AppText.caption.copyWith(
            fontSize: 9,
            color: AppColor.inkFaint,
          ),
        ),
      ],
    );
  }

  Widget _burnControl() {
    final extra = liveSet.extraReps ?? 0;
    final target = liveSet.extraTarget;
    return _stepper(
      value: '+$extra',
      unit: target.isEmpty ? 'na verzuring' : 'na verzuring ($target)',
      onDown: () => onChanged(
        (s) => s..extraReps = ((s.extraReps ?? 0) - 1).clamp(0, 100),
      ),
      onUp: () => onChanged(
        (s) => s..extraReps = ((s.extraReps ?? 0) + 1).clamp(0, 100),
      ),
    );
  }

  /// reps → tijd → tot verzuring → reps.
  SetMode get _nextMode => switch (liveSet.mode) {
    SetMode.reps => SetMode.time,
    SetMode.time => SetMode.burn,
    SetMode.burn => SetMode.reps,
  };

  Future<void> _confirmRemove(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final choice = await showMenu<bool>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        origin.dx + 1,
        origin.dy + 1,
      ),
      items: [
        PopupMenuItem(
          value: true,
          child: Row(
            children: [
              const Icon(
                Icons.delete_outline,
                size: 18,
                color: AppColor.redBright,
              ),
              const SizedBox(width: 10),
              Text('Set $num verwijderen'),
            ],
          ),
        ),
      ],
    );
    if (choice == true) onRemove();
  }

  Future<void> _editOutcome(BuildContext context) async {
    final result = await showSetOutcomeSheet(
      context,
      title: 'Set $num',
      completed: liveSet.completed,
      note: liveSet.note,
    );
    if (result == null) return;
    onChanged(
      (s) => s
        ..completed = result.completed
        ..note = result.note,
    );
  }

  @override
  Widget build(BuildContext context) {
    final failed = liveSet.completed == false;
    final outcomeColor = switch (liveSet.completed) {
      true => AppColor.greenBright,
      false => AppColor.redBright,
      null => liveSet.note.isNotEmpty ? AppColor.ice : AppColor.inkFaint,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: failed
            ? AppColor.coralWash
            : liveSet.done
            ? AppColor.greenWash
            : AppColor.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          // Tik op het setnummer om de set te verwijderen — een aparte
          // knop past niet meer naast de steppers op een smal scherm.
          Tooltip(
            message: 'Set $num verwijderen',
            child: InkWell(
              onTap: () => _confirmRemove(context),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                width: 20,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColor.lineStrong),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text('$num', style: AppText.caption),
              ),
            ),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: _stepper(
              value: liveSet.kg % 1 == 0
                  ? liveSet.kg.toInt().toString()
                  : liveSet.kg.toString(),
              unit: 'kg',
              onDown: () =>
                  onChanged((s) => s..kg = (s.kg - 0.5).clamp(0, 500)),
              onUp: () => onChanged((s) => s..kg = (s.kg + 0.5).clamp(0, 500)),
              onTapValue: () async {
                final v = await showNumberInput(
                  context,
                  title: 'Gewicht · set $num',
                  initial: liveSet.kg,
                  decimal: true,
                  suffix: 'kg',
                  max: 500,
                );
                if (v != null) onChanged((s) => s..kg = v);
              },
            ),
          ),
          Expanded(
            child: switch (liveSet.mode) {
              SetMode.time => _timeControl(),
              SetMode.burn => _burnControl(),
              SetMode.reps => _stepper(
                value: '${liveSet.reps}',
                unit: 'reps',
                onDown: () =>
                    onChanged((s) => s..reps = (s.reps - 1).clamp(1, 100)),
                onUp: () =>
                    onChanged((s) => s..reps = (s.reps + 1).clamp(1, 100)),
                onTapValue: () async {
                  final v = await showNumberInput(
                    context,
                    title: 'Herhalingen · set $num',
                    initial: liveSet.reps.toDouble(),
                    min: 1,
                    max: 100,
                  );
                  if (v != null) onChanged((s) => s..reps = v.round());
                },
              ),
            },
          ),
          Tooltip(
            message: switch (_nextMode) {
              SetMode.reps => 'Naar herhalingen',
              SetMode.time => 'Naar tijd',
              SetMode.burn => 'Naar tot verzuring',
            },
            child: InkWell(
              onTap: () => onToggleMode(_nextMode),
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: Icon(
                  switch (liveSet.mode) {
                    SetMode.reps => Icons.repeat,
                    SetMode.time => Icons.timer_outlined,
                    SetMode.burn => Icons.local_fire_department_outlined,
                  },
                  size: 17,
                  color: liveSet.toBurn ? AppColor.amber : AppColor.inkFaint,
                ),
              ),
            ),
          ),
          Tooltip(
            message: 'Gelukt / niet gelukt',
            child: InkWell(
              onTap: () => _editOutcome(context),
              borderRadius: BorderRadius.circular(99),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 6),
                child: Icon(
                  liveSet.note.isNotEmpty
                      ? Icons.comment
                      : Icons.mode_comment_outlined,
                  size: 17,
                  color: outcomeColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () => onChanged((s) => s..done = !s.done),
            borderRadius: BorderRadius.circular(9),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: liveSet.done ? AppColor.green : Colors.transparent,
                border: Border.all(
                  color: liveSet.done ? AppColor.green : AppColor.inkFaint,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: liveSet.done
                  ? const Icon(Icons.check, size: 15, color: AppColor.greenInk)
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _StepButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 26,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: AppText.body.copyWith(
            fontWeight: FontWeight.w600,
            color: AppColor.inkMuted,
          ),
        ),
      ),
    );
  }
}

class _AddExerciseCard extends StatelessWidget {
  final TextEditingController query;
  final List<Exercise> customExercises;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;
  const _AddExerciseCard({
    required this.query,
    required this.customExercises,
    required this.onPick,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) => ExercisePicker(
    query: query,
    customExercises: customExercises,
    onPick: onPick,
    onCancel: onCancel,
  );
}

/// Grote aftelling van een tijd-set (bv. plank): eerst "Maak je klaar",
/// daarna de tijd van de oefening zelf.
class _TimedSetBanner extends StatelessWidget {
  const _TimedSetBanner({
    required this.active,
    required this.paused,
    required this.onSkipPrep,
    required this.onStop,
  });

  final ActiveTimedSet active;
  final bool paused;
  final VoidCallback onSkipPrep;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    final left = active.left.inSeconds;
    final total = active.total.inSeconds;
    final mm = (left ~/ 60).toString();
    final ss = (left % 60).toString().padLeft(2, '0');
    final accent = active.preparing ? AppColor.ice : AppColor.greenBright;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: active.preparing ? AppColor.surfaceRaised : AppColor.greenWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: .4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  active.preparing
                      ? 'Maak je klaar: ${active.name}'
                      : '${active.name} · set ${active.setIndex + 1}',
                  style: AppText.bodyStrong.copyWith(color: accent),
                ),
              ),
              if (paused)
                Text(
                  'GEPAUZEERD',
                  style: AppText.overline.copyWith(color: AppColor.amber),
                ),
            ],
          ),
          Row(
            children: [
              Text(
                '$mm:$ss',
                style: AppText.metric.copyWith(fontSize: 34, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: total > 0 ? 1 - (left / total) : 0,
                    minHeight: 4,
                    backgroundColor: AppColor.surfaceHighest,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
              ),
              if (active.preparing)
                TextButton(onPressed: onSkipPrep, child: const Text('Start'))
              else
                TextButton(onPressed: onStop, child: const Text('Stop')),
            ],
          ),
        ],
      ),
    );
  }
}

/// Rustteller die verschijnt zodra je een set afvinkt — net als in Lyfta.
class _RestBanner extends StatelessWidget {
  final int secondsLeft;
  final int total;

  /// Wat er na de rust komt, bv. "Ronde 2 · Goblet squat".
  final String? next;
  final VoidCallback onSkip;
  const _RestBanner({
    required this.secondsLeft,
    required this.total,
    required this.onSkip,
    this.next,
  });

  @override
  Widget build(BuildContext context) {
    final mm = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (secondsLeft % 60).toString().padLeft(2, '0');
    final row = Row(
      children: [
        const Icon(Icons.timer_outlined, size: 16, color: AppColor.tealBright),
        const SizedBox(width: 10),
        Text(
          'Rust · $mm:$ss',
          style: AppText.bodyStrong.copyWith(color: AppColor.tealBright),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: total <= 0 ? 1 : 1 - (secondsLeft / total),
              minHeight: 3,
              backgroundColor: AppColor.surfaceHighest,
              valueColor: const AlwaysStoppedAnimation(AppColor.teal),
            ),
          ),
        ),
        const SizedBox(width: 10),
        InkWell(
          onTap: onSkip,
          child: Text(
            'Sla over',
            style: AppText.caption.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColor.inkMuted,
            ),
          ),
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColor.tealWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColor.teal.withValues(alpha: .35)),
      ),
      child: next == null
          ? row
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                row,
                const SizedBox(height: 4),
                Text(
                  next!,
                  style: AppText.caption.copyWith(color: AppColor.inkMuted),
                ),
              ],
            ),
    );
  }
}

/// Toont een circuit: niet gestart (Start-knop), lopend (huidige
/// oefening/voorbereiden/rust + aftelklok, schakelt zelf automatisch door,
/// te pauzeren) of voltooid — met de oefeningenlijst (in te klappen), per
/// blok gegroepeerd, waarin je ziet waar je bent.
class _CircuitCard extends StatefulWidget {
  final LiveCircuit liveCircuit;

  /// Video's bij een stap (eigen video's, anders die van de oefening).
  final List<String> Function(CircuitStep step) videosForStep;
  final VoidCallback onStart;
  final VoidCallback onSkip;
  final VoidCallback onStop;
  final VoidCallback onTogglePause;
  final VoidCallback? onRemove;
  const _CircuitCard({
    required this.liveCircuit,
    required this.videosForStep,
    required this.onStart,
    required this.onSkip,
    required this.onStop,
    required this.onTogglePause,
    required this.onRemove,
  });

  @override
  State<_CircuitCard> createState() => _CircuitCardState();
}

class _CircuitCardState extends State<_CircuitCard> {
  bool? _listOpen;

  LiveCircuit get lc => widget.liveCircuit;

  String _segmentLabel(CircuitSegment seg, int index) {
    final rounds = '${seg.rounds} ronde${seg.rounds == 1 ? '' : 's'}';
    if (seg.block == null) {
      return lc.segments.length == 1 ? rounds : 'Losse oefeningen · $rounds';
    }
    final letter = blockLetter(
      lc.segments.take(index).where((g) => g.block != null).length,
    );
    return 'Blok $letter · $rounds';
  }

  String get _positionLabel {
    final seg = lc.segment;
    final roundLabel = 'Ronde ${lc.round + 1} van ${seg.rounds}';
    if (lc.segments.length == 1) return roundLabel;
    return '${_segmentLabel(seg, lc.segmentIndex).split(' · ').first} · '
        '$roundLabel';
  }

  @override
  Widget build(BuildContext context) {
    final c = lc.circuit;
    // Lijst standaard open zolang het circuit nog niet loopt, en
    // ingeklapt tijdens het lopen (dan staat de huidige oefening groot).
    final listOpen = _listOpen ?? !lc.isRunning;
    final step = lc.currentStep;
    final stepVideos = step == null
        ? const <String>[]
        : widget.videosForStep(step);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: lc.isDone ? AppColor.greenWash : AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.name, style: AppText.cardTitle)),
              if (c.description.isNotEmpty || c.videoUrls.isNotEmpty)
                InkWell(
                  onTap: () => showInfoSheet(
                    context,
                    title: c.name,
                    description: c.description,
                    videoUrls: c.videoUrls,
                  ),
                  borderRadius: BorderRadius.circular(99),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColor.inkFaint,
                    ),
                  ),
                ),
              if (!lc.isRunning && widget.onRemove != null)
                InkWell(
                  onTap: widget.onRemove,
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
          const SizedBox(height: 4),
          Text(c.summary, style: AppText.caption.copyWith(fontSize: 11)),
          const SizedBox(height: 10),
          if (lc.isDone)
            Row(
              children: [
                const Icon(
                  Icons.check_circle,
                  size: 16,
                  color: AppColor.greenBright,
                ),
                const SizedBox(width: 8),
                Text(
                  'Circuit voltooid',
                  style: AppText.bodyStrong.copyWith(
                    color: AppColor.greenBright,
                  ),
                ),
              ],
            )
          else if (lc.isRunning) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    _positionLabel,
                    style: AppText.caption.copyWith(color: AppColor.inkMuted),
                  ),
                ),
                if (lc.isPaused)
                  Text(
                    'GEPAUZEERD',
                    style: AppText.overline.copyWith(color: AppColor.amber),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    switch (lc.phase) {
                      CircuitPhase.prep =>
                        'Maak je klaar: ${lc.currentExerciseName}',
                      CircuitPhase.rest =>
                        'Rust${lc.nextStep == null ? '' : ' · hierna ${lc.nextStep!.name}'}',
                      CircuitPhase.work => lc.currentExerciseName,
                    },
                    style: AppText.bodyStrong.copyWith(
                      color: switch (lc.phase) {
                        CircuitPhase.prep => AppColor.ice,
                        CircuitPhase.rest => AppColor.tealBright,
                        CircuitPhase.work => AppColor.ink,
                      },
                    ),
                  ),
                ),
                if (lc.phase != CircuitPhase.rest && stepVideos.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => showInfoSheet(
                      context,
                      title: lc.currentExerciseName,
                      videoUrls: stepVideos,
                    ),
                    icon: const Icon(Icons.play_circle_outline, size: 16),
                    label: const Text('Video'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColor.ice,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (lc.waitingForTap)
              _RepStepBox(
                target: step!.targetLabel,
                burn: step.toBurn,
                onDone: widget.onSkip,
              )
            else
              _PhaseTimer(circuit: lc, onSkip: widget.onSkip),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: widget.onTogglePause,
                    icon: Icon(
                      lc.isPaused ? Icons.play_arrow : Icons.pause,
                      size: 18,
                    ),
                    label: Text(lc.isPaused ? 'Verder' : 'Pauze'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: widget.onStop,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(40),
                    ),
                    child: const Text('Stop'),
                  ),
                ),
              ],
            ),
          ] else
            FilledButton(
              onPressed: widget.onStart,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.green,
                foregroundColor: AppColor.greenInk,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Start circuit'),
            ),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _listOpen = !listOpen),
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Text(
                    'Oefeningen (${lc.steps.length})',
                    style: AppText.caption.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColor.inkMuted,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    listOpen ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: AppColor.inkFaint,
                  ),
                ],
              ),
            ),
          ),
          if (listOpen)
            for (var g = 0; g < lc.segments.length; g++) ...[
              if (lc.segments.length > 1 || lc.segments[g].block != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Text(
                    _segmentLabel(lc.segments[g], g),
                    style: AppText.overline.copyWith(
                      color: lc.segments[g].block == null
                          ? AppColor.inkFaint
                          : kBlockColors[lc.segments
                                    .take(g)
                                    .where((x) => x.block != null)
                                    .length %
                                kBlockColors.length],
                    ),
                  ),
                ),
              for (var i = lc.segments[g].start; i < lc.segments[g].end; i++)
                _CircuitStepLine(
                  step: lc.steps[i],
                  current: lc.isRunning && i == lc.exerciseIndex,
                  done:
                      lc.isDone ||
                      (lc.isRunning &&
                          (g < lc.segmentIndex ||
                              (g == lc.segmentIndex &&
                                  lc.round == lc.segment.rounds - 1 &&
                                  i < lc.exerciseIndex))),
                ),
            ],
        ],
      ),
    );
  }
}

/// Eén oefening in de lijst van een circuit.
class _CircuitStepLine extends StatelessWidget {
  const _CircuitStepLine({
    required this.step,
    required this.current,
    required this.done,
  });

  final CircuitStep step;
  final bool current;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final color = current
        ? AppColor.ink
        : done
        ? AppColor.inkGhost
        : AppColor.inkMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: current ? AppColor.surfaceHigh : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        children: [
          Icon(
            current
                ? Icons.play_arrow
                : done
                ? Icons.check
                : Icons.circle_outlined,
            size: 14,
            color: current ? AppColor.greenBright : color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step.name,
              style: AppText.body.copyWith(fontSize: 13, color: color),
            ),
          ),
          Text(step.targetLabel, style: AppText.caption.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Aftelklok van de huidige fase (voorbereiden, werk of rust), met
/// voortgangsbalk en "Overslaan".
class _PhaseTimer extends StatelessWidget {
  const _PhaseTimer({required this.circuit, required this.onSkip});

  final LiveCircuit circuit;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final secondsLeft = circuit.timeLeft.inSeconds;
    final mm = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (secondsLeft % 60).toString().padLeft(2, '0');
    final total = circuit.phaseTotal;
    final (accent, bright, wash, icon) = switch (circuit.phase) {
      CircuitPhase.prep => (
        AppColor.iceDeep,
        AppColor.ice,
        AppColor.greenWash,
        Icons.hourglass_top,
      ),
      CircuitPhase.rest => (
        AppColor.teal,
        AppColor.tealBright,
        AppColor.tealWash,
        Icons.timer_outlined,
      ),
      CircuitPhase.work => (
        AppColor.green,
        AppColor.greenBright,
        AppColor.greenWash,
        Icons.bolt,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: wash,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: accent.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: bright),
          const SizedBox(width: 10),
          Text('$mm:$ss', style: AppText.bodyStrong.copyWith(color: bright)),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: total > 0 ? 1 - (secondsLeft / total) : 0,
                minHeight: 3,
                backgroundColor: Colors.white.withValues(alpha: .08),
                valueColor: AlwaysStoppedAnimation(accent),
              ),
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onSkip,
            child: Text(
              'Overslaan',
              style: AppText.caption.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColor.inkMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Een herhalingen-stap in een lopend circuit: geen klok, je tikt "Klaar"
/// als je ze gedaan hebt.
class _RepStepBox extends StatelessWidget {
  const _RepStepBox({
    required this.target,
    required this.onDone,
    this.burn = false,
  });

  final String target;
  final bool burn;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: AppColor.greenWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColor.green.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          Icon(
            burn ? Icons.local_fire_department_outlined : Icons.repeat,
            size: 16,
            color: burn ? AppColor.amber : AppColor.greenBright,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              target,
              style: AppText.cardTitle.copyWith(color: AppColor.greenBright),
            ),
          ),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: AppColor.green,
              foregroundColor: AppColor.greenInk,
              minimumSize: const Size(88, 40),
            ),
            child: const Text('Klaar'),
          ),
        ],
      ),
    );
  }
}
