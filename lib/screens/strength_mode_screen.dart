// strength_mode_screen.dart — live krachttraining
//
// Zelfde opzet als mat_mode_screen.dart: dit scherm is een "view" over
// StrengthSessionController: alle data (oefeningen, glucose, timers) leeft in
// de controller, niet hier. Zo blijft de sessie gewoon doorlopen (klok,
// Nightscout-polling, alarm) als je dit scherm verlaat om naar een ander
// tabblad te gaan — zie ShellScreen voor de permanente balk die de actieve
// sessie laat zien en heropent.

import 'package:flutter/material.dart';
import '../core/exercise_library.dart';
import '../models/exercise.dart';
import '../models/training_session.dart';
import '../repositories/circuit_repository.dart';
import '../state/strength_session_controller.dart';
import '../services/system_bars.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';
import '../widgets/block_widgets.dart' show AddBlockButton;
import '../widgets/manual_glucose.dart' show FingerHistoryStrip;
import '../widgets/nutrition_log.dart';
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
                          '${c.exerciseNames.length} oefeningen · '
                          '${c.rounds} rondes · ${c.workSeconds}s/'
                          '${c.restSeconds}s',
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
      builder: (context, _) => Scaffold(
        backgroundColor: AppColor.bg,
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
                  if (_c.restLeft > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: _RestBanner(
                        secondsLeft: _c.restLeft,
                        total: restSeconds,
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
                        12 + MediaQuery.of(context).padding.bottom,
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
                                Padding(
                                  key: ValueKey(_c.exercises[ei]),
                                  padding: EdgeInsets.zero,
                                  child: _ExerciseCard(
                                    exercise: _c.exercises[ei],
                                    onOpenHistory: () =>
                                        _openHistory(_c.exercises[ei].name),
                                    onRemove: () => _c.removeExercise(ei),
                                    onAddSet: () => _c.addSet(ei),
                                    onSetChanged: (si, patch) =>
                                        _c.updateSet(ei, si, patch),
                                    onStartSetTimer: (si) =>
                                        _c.startSetTimer(ei, si),
                                    onToggleSetMode: (si, timeBased) => _c
                                        .setSetMode(ei, si, timeBased: timeBased),
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
                        if (_c.adding)
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
                              onStart: () => _c.startCircuit(ci),
                              onSkip: () => _c.skipCircuitPhase(ci),
                              onStop: () => _c.stopCircuit(ci),
                              onRemove: () => _c.removeCircuit(ci),
                            ),
                          ),
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
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final LiveExercise exercise;
  final VoidCallback onRemove;
  final VoidCallback onAddSet;
  final VoidCallback onOpenHistory;
  final void Function(int setIndex, LiveSet Function(LiveSet)) onSetChanged;
  final void Function(int setIndex) onStartSetTimer;
  final void Function(int setIndex, bool timeBased) onToggleSetMode;
  final Widget? dragHandle;
  const _ExerciseCard({
    required this.exercise,
    required this.onRemove,
    required this.onAddSet,
    required this.onOpenHistory,
    required this.onSetChanged,
    required this.onStartSetTimer,
    required this.onToggleSetMode,
    this.dragHandle,
  });

  void _showDescription(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        backgroundColor: AppColor.surface,
        title: Text(exercise.name, style: AppText.cardTitle),
        content: Text(
          exercise.description,
          style: AppText.body.copyWith(color: AppColor.inkMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Sluiten'),
          ),
        ],
      ),
    );
  }

  String _fmtKg(double kg) =>
      kg % 1 == 0 ? kg.toInt().toString() : kg.toString();

  String _formatLastPerformance(List<ExerciseSet> sets) =>
      sets.map((s) => '${_fmtKg(s.kg)}kg × ${s.reps}').join(', ');

  @override
  Widget build(BuildContext context) {
    final done = exercise.sets.where((s) => s.done).length;
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
              if (exercise.description.isNotEmpty)
                InkWell(
                  onTap: () => _showDescription(context),
                  borderRadius: BorderRadius.circular(99),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColor.inkFaint,
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
              const SizedBox(width: 8),
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
                onChanged: (patch) => onSetChanged(si, patch),
                onStartTimer: () => onStartSetTimer(si),
                onToggleMode: (timeBased) => onToggleSetMode(si, timeBased),
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
      ),
    );
  }
}

class _SetRow extends StatelessWidget {
  final int num;
  final LiveSet liveSet;
  final void Function(LiveSet Function(LiveSet)) onChanged;
  final VoidCallback onStartTimer;
  final ValueChanged<bool> onToggleMode;
  const _SetRow({
    required this.num,
    required this.liveSet,
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
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _StepButton(label: '−', onTap: onDown),
            SizedBox(
              width: 40,
              child: Text(
                value,
                textAlign: TextAlign.center,
                style: AppText.cardTitle,
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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: liveSet.done
            ? AppColor.greenWash
            : AppColor.surfaceRaised,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            child: Text(
              '$num',
              textAlign: TextAlign.center,
              style: AppText.caption,
            ),
          ),
          Expanded(
            child: _stepper(
              value: liveSet.kg % 1 == 0
                  ? liveSet.kg.toInt().toString()
                  : liveSet.kg.toString(),
              unit: 'kg',
              onDown: () =>
                  onChanged((s) => s..kg = (s.kg - 2.5).clamp(0, 500)),
              onUp: () => onChanged((s) => s..kg = (s.kg + 2.5).clamp(0, 500)),
            ),
          ),
          Expanded(
            child: liveSet.seconds != null
                ? _timeControl()
                : _stepper(
                    value: '${liveSet.reps}',
                    unit: 'reps',
                    onDown: () =>
                        onChanged((s) => s..reps = (s.reps - 1).clamp(1, 100)),
                    onUp: () =>
                        onChanged((s) => s..reps = (s.reps + 1).clamp(1, 100)),
                  ),
          ),
          InkWell(
            onTap: () => onToggleMode(liveSet.seconds == null),
            borderRadius: BorderRadius.circular(99),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Icon(
                liveSet.seconds != null ? Icons.repeat : Icons.timer_outlined,
                size: 16,
                color: AppColor.inkFaint,
              ),
            ),
          ),
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
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.bgDeep,
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
              fillColor: Colors.white.withValues(alpha: .06),
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
              final descriptions = {
                for (final e in customExercises) e.name: e.description,
              };
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
                            color: Colors.white.withValues(alpha: .04),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: AppText.bodyStrong),
                              if ((descriptions[name] ?? '').isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    descriptions[name]!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppText.caption.copyWith(
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                            ],
                          ),
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

/// Rustteller die verschijnt zodra je een set afvinkt — net als in Lyfta.
class _RestBanner extends StatelessWidget {
  final int secondsLeft;
  final int total;
  final VoidCallback onSkip;
  const _RestBanner({
    required this.secondsLeft,
    required this.total,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final mm = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (secondsLeft % 60).toString().padLeft(2, '0');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColor.tealWash,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColor.teal.withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.timer_outlined,
            size: 16,
            color: AppColor.tealBright,
          ),
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
                value: 1 - (secondsLeft / total),
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
      ),
    );
  }
}

/// Toont een circuit: niet gestart (Start-knop), lopend (huidige
/// oefening/rust + aftelklok + voortgangsbalk, schakelt zelf automatisch
/// door) of voltooid.
class _CircuitCard extends StatelessWidget {
  final LiveCircuit liveCircuit;
  final VoidCallback onStart;
  final VoidCallback onSkip;
  final VoidCallback onStop;
  final VoidCallback onRemove;
  const _CircuitCard({
    required this.liveCircuit,
    required this.onStart,
    required this.onSkip,
    required this.onStop,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final c = liveCircuit.circuit;
    final secondsLeft = liveCircuit.timeLeft.inSeconds;
    final mm = (secondsLeft ~/ 60).toString().padLeft(2, '0');
    final ss = (secondsLeft % 60).toString().padLeft(2, '0');
    final isResting = liveCircuit.phase == CircuitPhase.rest;
    final total = isResting ? c.restSeconds : c.workSeconds;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: liveCircuit.isDone ? AppColor.greenWash : AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(c.name, style: AppText.cardTitle)),
              if (!liveCircuit.isRunning)
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
          const SizedBox(height: 4),
          Text(
            '${c.exerciseNames.length} oefeningen · ${c.rounds} rondes · '
            '${c.workSeconds}s/${c.restSeconds}s',
            style: AppText.caption.copyWith(fontSize: 11),
          ),
          const SizedBox(height: 10),
          if (liveCircuit.isDone)
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
          else if (liveCircuit.isRunning)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ronde ${liveCircuit.round + 1} van ${c.rounds} · '
                  '${isResting ? "Rust" : liveCircuit.currentExerciseName}',
                  style: AppText.bodyStrong.copyWith(
                    color: isResting ? AppColor.tealBright : AppColor.ink,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: isResting ? AppColor.tealWash : AppColor.greenWash,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: (isResting ? AppColor.teal : AppColor.green)
                          .withValues(alpha: .35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isResting ? Icons.timer_outlined : Icons.bolt,
                        size: 16,
                        color: isResting
                            ? AppColor.tealBright
                            : AppColor.greenBright,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '$mm:$ss',
                        style: AppText.bodyStrong.copyWith(
                          color: isResting
                              ? AppColor.tealBright
                              : AppColor.greenBright,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: total > 0 ? 1 - (secondsLeft / total) : 0,
                            minHeight: 3,
                            backgroundColor: Colors.white.withValues(
                              alpha: .08,
                            ),
                            valueColor: AlwaysStoppedAnimation(
                              isResting ? AppColor.teal : AppColor.green,
                            ),
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
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onStop,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(40),
                  ),
                  child: const Text('Stop'),
                ),
              ],
            )
          else
            FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: AppColor.green,
                foregroundColor: AppColor.greenInk,
                minimumSize: const Size.fromHeight(44),
              ),
              child: const Text('Start circuit'),
            ),
        ],
      ),
    );
  }
}
