// live_session_screen.dart: de lopende training. Een training is niet
// hetzelfde als sparren: bovenaan staan altijd glucose en Polar H10 (met de
// Voeding-knop), daaronder de trainingsklok (die pas loopt vanaf de
// begintijd), en tijdens de training voeg je blokken toe: warming-up,
// sparren (rondes met eigen duur en doelen), technieken (reps/tijd +
// notitie) en combinaties. Alleen tijdens het sparren zijn er de
// Geslaagd/Poging/Gecounterd-tellers en de grote mat-knoppen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/meal_impact.dart';
import '../core/sparring_timer.dart';
import '../models/live_training.dart';
import '../models/technique.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/start_training_sheet.dart';
import '../widgets/telemetry_widgets.dart' show glucoseZoneTone, liveHypo, toneSolid, trendIcon;
import '../widgets/training_sheets.dart';

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  late final KineticStore _store = KineticScope.read(context);
  bool _leaving = false;

  /// Tijdens het sparren: spar-weergave (true) of de gewone trainingspagina.
  bool _showSparring = true;
  String? _lastBlockId;

  @override
  void initState() {
    super.initState();
    _store.sparringEvents.addListener(_onEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) => _onEvent());
  }

  @override
  void dispose() {
    _store.sparringEvents.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() {
    if (!mounted || _leaving) return;
    final t = _store.sparring;
    if (t != null && t.phase == SparringPhase.rest) {
      _leaving = true;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushReplacementNamed('/ronde-rust');
    } else if (_store.sparringEvents.value == SparringEvent.finished) {
      HapticFeedback.heavyImpact();
      _store.sparringEvents.value = null;
      showToast(context, 'Sparren afgerond');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final tr = store.training;
    if (tr == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final now = store.now();
    final t = store.sparring;
    final sparring = t != null && !t.isDone;
    // Nieuw sparblok gestart: meteen naar de spar-weergave.
    final blockId = tr.activeSparring?.id;
    if (blockId != null && blockId != _lastBlockId) _showSparring = true;
    _lastBlockId = blockId;
    final sparView = sparring && _showSparring;
    final hypo = liveHypo(store);
    final r = store.reading;
    final status = sparring
        ? (t.isPaused ? 'SPARREN • GEPAUZEERD' : 'SPARREN • RONDE ${t.round}/${t.config.rounds}')
        : !tr.hasStarted(now)
        ? 'START OM ${hhmm(tr.startsAt)}'
        : tr.isOver(now)
        ? 'EINDTIJD BEREIKT'
        : 'TRAINING • LIVE';
    return Scaffold(
      body: Column(
        children: [
          SessionTopBar(
            title: tr.displayTitle,
            status: status,
            statusTone: sparring ? (t.isPaused ? KTone.warning : KTone.danger) : KTone.primary,
            live: sparring ? !t.isPaused : tr.hasStarted(now),
          ),
          Expanded(
            child: SingleChildScrollView(
              // Zonder onderbalk zelf ruimte houden voor de systeemknoppen.
              padding: EdgeInsets.fromLTRB(16, 12, 16, 24 + (sparView ? 0 : MediaQuery.viewPaddingOf(context).bottom)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hypo && r != null)
                    HypoBanner(
                      reading: r,
                      grams: store.fastCarbGrams,
                      onDextrose: () => logMatIntervention(context, dextrose: true),
                    ),
                  const _VitalsBar(),
                  const SizedBox(height: 12),
                  if (sparring) ...[
                    KSegmented<bool>(
                      options: const [(true, 'Sparren'), (false, 'Training')],
                      value: _showSparring,
                      onChanged: (v) => setState(() => _showSparring = v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (sparring && !_showSparring) ...[
                    _SparringMiniBar(timer: t, onTap: () => setState(() => _showSparring = true)),
                    const SizedBox(height: 12),
                  ],
                  if (sparView) ...[
                    _SparringPanel(timer: t),
                    const SizedBox(height: 12),
                    const TechniqueFocusCard(),
                  ] else ...[
                    _TrainingClock(training: tr),
                    const SizedBox(height: 12),
                    const _ActionGrid(),
                    const SizedBox(height: 12),
                    const _TechniqueList(),
                  ],
                  const SizedBox(height: 12),
                  _Timeline(training: tr),
                ],
              ),
            ),
          ),
          if (sparView)
            BottomActionBar(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: MatControlButton(
                      label: t.isPaused ? 'Hervat' : 'Pauze',
                      icon: t.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      onPressed: store.toggleSparringTimer,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MatControlButton(
                      label: t.isLastRound ? 'Klaar' : 'Volgende',
                      icon: t.isLastRound ? Icons.flag_rounded : Icons.skip_next_rounded,
                      style: KButtonStyle.secondary,
                      onPressed: store.advanceToRestPhase,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MatControlButton(
                      label: 'Stop',
                      icon: Icons.stop_rounded,
                      style: KButtonStyle.secondary,
                      onPressed: () => confirmStopSparring(context),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Techniek uit de training halen, met "Ongedaan" (log en notitie komen terug).
void removeTechniqueWithUndo(BuildContext context, Technique technique) {
  final store = KineticScope.read(context);
  final backup = store.removeSessionTechnique(technique.id);
  showToast(
    context,
    '${technique.name} uit de training gehaald',
    actionLabel: 'Ongedaan',
    onAction: () => store.restoreSessionTechnique(technique.id, backup),
  );
}

/// Compacte sparbalk op de trainingspagina: ronde, tijd en terug naar sparren.
class _SparringMiniBar extends StatelessWidget {
  const _SparringMiniBar({required this.timer, required this.onTap});
  final SparringTimer timer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final store = KineticScope.of(context);
    final color = timer.isPaused ? k.warning : k.danger;
    return Semantics(
      button: true,
      label: 'Terug naar sparren',
      child: KWell(
        onTap: onTap,
        color: color.withValues(alpha: 0.12),
        borderColor: color.withValues(alpha: 0.6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            LiveDot(color: color, active: !timer.isPaused),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Sparren • ronde ${timer.round}/${timer.config.rounds}${timer.isPaused ? ' • gepauzeerd' : ''}',
                style: context.t.bodyStrong,
              ),
            ),
            Text(
              mmss(store.roundSecondsRemaining),
              style: context.t.subtitle.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: k.textSecondary),
          ],
        ),
      ),
    );
  }
}

/// Sparblok stoppen (de training loopt door).
Future<void> confirmStopSparring(BuildContext context) async {
  final store = KineticScope.read(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Sparren stoppen?'),
      content: const Text('De rondes tot nu toe en de tellers blijven bewaard. De training loopt door.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Doorgaan')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop sparren')),
      ],
    ),
  );
  if (ok == true) store.finishSparringBlock();
}

// ------------------------------------------------------------ vitals

/// Altijd bovenaan: glucose (met trend en clearance) en Polar H10, plus de
/// Voeding-knop.
class _VitalsBar extends StatelessWidget {
  const _VitalsBar();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final r = store.reading;
    final fresh = r != null && !r.isStaleAt(store.now());
    final c = store.clearanceForNextRound();
    final tone = clearanceTone(c.level);
    final ink = toneColors(k, tone).$2;
    final zone = store.currentHeartRateZone;
    return KCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              label: fresh ? 'Glucose ${r.mmol.toStringAsFixed(1)} mmol/L, ${c.title}' : 'Geen actuele glucose',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DEXCOM G7', style: t.labelSm.copyWith(color: k.textMuted)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        fresh ? r.mmol.toStringAsFixed(1) : '--',
                        style: t.metricMd.copyWith(
                          fontWeight: FontWeight.w800,
                          color: fresh ? zoneInk(k, r.mmol) : k.textMuted,
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (fresh) Icon(trendIcon(r.trend), size: 18, color: ink),
                    ],
                  ),
                  Text(
                    fresh ? clearanceShort(c.level) : 'Geen data',
                    style: t.caption.copyWith(color: ink, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          if (store.showHeartRate) ...[
            Container(width: 1, height: 48, color: k.border),
            const SizedBox(width: 12),
            Expanded(
              child: Semantics(
                label: 'Hartslag ${store.heartRateBpm} BPM, ${zone.label}',
                excludeSemantics: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('POLAR H10', style: t.labelSm.copyWith(color: k.textMuted)),
                        const SizedBox(width: 4),
                        Icon(Icons.favorite, size: 12, color: k.danger),
                      ],
                    ),
                    Text('${store.heartRateBpm}', style: t.metricMd.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      zone.label,
                      style: t.caption.copyWith(color: k.dangerInk, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: 'Voeding loggen',
            excludeSemantics: true,
            child: Material(
              color: k.primaryTint,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KRadius.md),
                side: BorderSide(color: k.primary.withValues(alpha: 0.5)),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  showNutritionSheet(context);
                },
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.restaurant, color: k.accent),
                      const SizedBox(height: 4),
                      Text(
                        'Voeding',
                        style: t.caption.copyWith(color: k.accent, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ trainingsklok

String _hms(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

class _TrainingClock extends StatelessWidget {
  const _TrainingClock({required this.training});
  final LiveTraining training;

  Future<void> _editTimes(BuildContext context) async {
    final store = KineticScope.read(context);
    final tr = training;
    final start = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(tr.startsAt),
      helpText: 'Begintijd',
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(tr.endsAt),
      helpText: 'Eindtijd',
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (end == null) return;
    final s = DateTime(tr.startsAt.year, tr.startsAt.month, tr.startsAt.day, start.hour, start.minute);
    var e = DateTime(s.year, s.month, s.day, end.hour, end.minute);
    if (!e.isAfter(s)) e = e.add(const Duration(days: 1));
    store.setTrainingTimes(startsAt: s, endsAt: e);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final now = store.now();
    final tr = training;
    final started = tr.hasStarted(now);
    final over = tr.isOver(now);
    final total = tr.plannedMinutes * 60;
    final progress = total <= 0 ? 0.0 : tr.elapsedSeconds(now) / total;
    return KCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(started ? Icons.timer_outlined : Icons.hourglass_top, size: 18, color: k.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  started ? (over ? 'EINDTIJD BEREIKT' : 'TRAININGSTIJD') : 'BEGINT OVER',
                  style: t.label.copyWith(color: k.accent, fontWeight: FontWeight.w700),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editTimes(context),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text('${hhmm(tr.startsAt)} – ${hhmm(tr.endsAt)}'),
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _hms(started ? tr.elapsedSeconds(now) : tr.secondsUntilStart(now)),
                style: t.timer.copyWith(fontSize: 72, color: started ? k.text : k.textSecondary),
              ),
            ),
          ),
          const SizedBox(height: 6),
          PhaseBar(value: progress, color: over ? k.warning : null),
          const SizedBox(height: 8),
          Text(
            !started
                ? 'De klok begint om ${hhmm(tr.startsAt)}. Je kunt alvast loggen.'
                : over
                ? 'Gepland tot ${hhmm(tr.endsAt)}. Rond af met Stop als je klaar bent.'
                : 'Nog ${durationLabel(tr.remainingSeconds(now) ~/ 60)} tot ${hhmm(tr.endsAt)}',
            textAlign: TextAlign.center,
            style: t.caption.copyWith(color: over ? k.warningInk : null),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ acties

class _ActionGrid extends StatelessWidget {
  const _ActionGrid();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget tile(String label, IconData icon, Color color, VoidCallback onTap) => Expanded(
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: k.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(KRadius.lg),
            side: BorderSide(color: k.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: SizedBox(
              height: 76,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: color, size: 26),
                  const SizedBox(height: 6),
                  Text(label, style: context.t.bodyStrong),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return Column(
      children: [
        Row(
          children: [
            tile('Warming-up', Icons.directions_run, k.warning, () => showWarmupSheet(context)),
            const SizedBox(width: 8),
            tile('Sparren', Icons.sports_mma, k.danger, () => showSparringSetupSheet(context)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            tile('Techniek', Icons.sports_kabaddi, k.accent, () => addTechniquesToTraining(context)),
            const SizedBox(width: 8),
            tile('Combinatie', Icons.alt_route, k.purple, () => showComboSheet(context)),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------ technieken

/// Technieken van deze training: reps of tijd + notitie. Focus-technieken
/// krijgen een uitroepteken en een accentrand.
class _TechniqueList extends StatelessWidget {
  const _TechniqueList();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final list = [...store.sessionTechniques]
      ..sort((a, b) {
        if (a.isInFocus != b.isInFocus) return a.isInFocus ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Technieken', style: t.title)),
              TextButton.icon(
                onPressed: () => addTechniquesToTraining(context),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Toevoegen'),
              ),
            ],
          ),
          if (list.isEmpty)
            Text('Nog geen technieken. Voeg er een toe om reps, tijd of notities te loggen.', style: t.caption),
          for (final tech in list) ...[
            const SizedBox(height: 8),
            _TechniqueRow(technique: tech, log: store.techniqueLog(tech.id)),
          ],
          if (list.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Tik × (of veeg naar links) om een techniek uit de training te halen.', style: t.caption),
          ],
          if (list.any((x) => x.isInFocus)) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.priority_high, size: 14, color: k.warningInk),
                const SizedBox(width: 4),
                Expanded(child: Text('= focus-techniek', style: t.caption)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _TechniqueRow extends StatelessWidget {
  const _TechniqueRow({required this.technique, required this.log});
  final Technique technique;
  final TechniqueLog log;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.read(context);
    final focus = technique.isInFocus;
    final reps = log.measure == TechniqueMeasure.reps;
    final value = reps ? '${log.reps} reps' : durationLabel(log.seconds ~/ 60);
    return Dismissible(
      key: ValueKey('tech-${technique.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(color: k.dangerTint, borderRadius: BorderRadius.circular(KRadius.md)),
        child: Icon(Icons.delete_outline, color: k.dangerInk),
      ),
      onDismissed: (_) => removeTechniqueWithUndo(context, technique),
      child: _row(context, k, t, store, focus, reps, value),
    );
  }

  Widget _row(
    BuildContext context,
    KineticColors k,
    KineticTypography t,
    KineticStore store,
    bool focus,
    bool reps,
    String value,
  ) {
    return KWell(
      onTap: () => showTrainingTechniqueDetails(context, technique),
      borderColor: focus ? k.warning.withValues(alpha: 0.7) : null,
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      child: Row(
        children: [
          if (focus) ...[
            Tooltip(
              message: 'Focus-techniek',
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(color: k.warningTint, shape: BoxShape.circle),
                child: Icon(Icons.priority_high, size: 15, color: k.warningInk),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(technique.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(
                  log.note.trim().isEmpty
                      ? '${technique.group.label} • ${reps ? 'reps' : 'tijd'}'
                      : '📝 ${log.note.trim()}',
                  style: t.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          ValueStepper(
            value: reps ? '${log.reps}' : durationLabel(log.seconds ~/ 60),
            width: reps ? 40 : 56,
            semanticsLabel: '${technique.name} $value',
            onMinus: (reps ? log.reps : log.seconds) > 0
                ? () => store.setTechniqueLog(
                    technique.id,
                    reps ? log.copyWith(reps: log.reps - 1) : log.copyWith(seconds: (log.seconds - 60).clamp(0, 36000)),
                  )
                : null,
            onPlus: () => store.setTechniqueLog(
              technique.id,
              reps ? log.copyWith(reps: log.reps + 1) : log.copyWith(seconds: log.seconds + 60),
            ),
          ),
          IconButton(
            tooltip: '${technique.name} uit de training halen',
            visualDensity: VisualDensity.compact,
            onPressed: () => removeTechniqueWithUndo(context, technique),
            icon: Icon(Icons.close, size: 20, color: k.textMuted),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ sparpaneel

/// Rondeklok van het lopende sparblok met het doel van deze ronde en het
/// doel voor het hele sparren (beide af te vinken).
class _SparringPanel extends StatelessWidget {
  const _SparringPanel({required this.timer});
  final SparringTimer timer;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final block = store.training?.activeSparring;
    final paused = timer.isPaused;
    final remaining = store.roundSecondsRemaining;
    final total = timer.config.rounds;
    final roundIndex = timer.round - 1;
    final round = block != null && roundIndex < block.rounds.length ? block.rounds[roundIndex] : null;
    final timeColor = paused ? k.textMuted : (remaining <= 10 ? k.warningInk : k.accent);
    return KCard(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Ronde ',
                        style: t.headline.copyWith(fontSize: 26, color: k.accent),
                      ),
                      TextSpan(
                        text: '${timer.round}',
                        style: t.headline.copyWith(fontSize: 26, fontWeight: FontWeight.w800, color: k.accent),
                      ),
                      TextSpan(
                        text: ' / $total',
                        style: t.title.copyWith(color: k.textSecondary),
                      ),
                    ],
                  ),
                ),
              ),
              Icon(Icons.sports_kabaddi, size: 18, color: k.accent),
              const SizedBox(width: 6),
              Text('SPARRING', style: t.labelSm.copyWith(color: k.accent, letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 10),
          RoundSegments(total: total, done: timer.round - 1, currentProgress: timer.phaseProgress(store.now())),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.hourglass_bottom, size: 16, color: k.textSecondary),
              const SizedBox(width: 6),
              Text('RESTEREND IN RONDE', style: t.labelSm.copyWith(letterSpacing: 0.8)),
            ],
          ),
          Semantics(
            button: true,
            label: 'Resterende tijd ${mmss(remaining)}, tik om te ${paused ? 'hervatten' : 'pauzeren'}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.mediumImpact();
                store.toggleSparringTimer();
              },
              child: SizedBox(
                width: double.infinity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(mmss(remaining), style: t.timer.copyWith(fontSize: 100, color: timeColor)),
                ),
              ),
            ),
          ),
          PhaseBar(value: timer.phaseProgress(store.now())),
          if (block != null)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showSparringSetupSheet(context, existing: block),
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Rondes aanpassen'),
              ),
            ),
          if (paused) ...[
            const SizedBox(height: 8),
            Text(
              'Gepauzeerd • tik de tijd om te hervatten',
              textAlign: TextAlign.center,
              style: t.caption.copyWith(color: k.warningInk),
            ),
          ],
          if (block != null && round != null && round.goal.isNotEmpty) ...[
            const SizedBox(height: 14),
            GoalCheck(
              label: 'Doel ronde ${timer.round}',
              goal: round.goal,
              done: round.goalDone,
              onTap: () => store.toggleRoundGoal(block.id, roundIndex),
            ),
          ],
          if (block != null && block.goal.isNotEmpty) ...[
            const SizedBox(height: 8),
            GoalCheck(
              label: 'Doel sparren',
              goal: block.goal,
              done: block.goalDone,
              onTap: () => store.toggleSparringGoal(block.id),
            ),
          ],
        ],
      ),
    );
  }
}

/// Afvinkbaar doel (ronde of hele sparblok).
class GoalCheck extends StatelessWidget {
  const GoalCheck({super.key, required this.label, required this.goal, required this.done, required this.onTap});
  final String label;
  final String goal;
  final bool done;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    return Semantics(
      checked: done,
      button: true,
      label: '$label: $goal',
      excludeSemantics: true,
      child: KWell(
        onTap: () {
          HapticFeedback.mediumImpact();
          onTap();
        },
        color: done ? k.successTint : null,
        borderColor: done ? k.success : k.border,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              done ? Icons.check_circle : Icons.radio_button_unchecked,
              color: done ? k.success : k.textMuted,
              size: 28,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label.toUpperCase(), style: t.labelSm.copyWith(color: done ? k.successInk : k.textMuted)),
                  Text(
                    goal,
                    style: t.bodyStrong.copyWith(
                      decoration: done ? TextDecoration.lineThrough : null,
                      color: done ? k.textSecondary : k.text,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ tijdlijn

/// Alles wat je deze training hebt gelogd, in volgorde, aanpasbaar.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.training});
  final LiveTraining training;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final tr = training;
    final finished = tr.sparrings.where((b) => b.isFinished).toList();
    final empty = tr.warmups.isEmpty && finished.isEmpty && tr.nutrition.isEmpty && tr.combos.isEmpty;
    if (empty) return const SizedBox.shrink();
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Gelogd', style: t.title),
          const SizedBox(height: 8),
          for (final w in tr.warmups)
            _TimelineRow(
              icon: Icons.directions_run,
              color: k.warning,
              title: 'Warming-up • ${w.minutes} min',
              sub: hhmm(w.at),
              onTap: () => showWarmupSheet(context, existing: w),
            ),
          for (final b in finished) _SparringSummary(block: b),
          for (final c in tr.combos)
            _TimelineRow(
              icon: Icons.alt_route,
              color: k.purple,
              title: '${c.label} • ${c.count}×',
              sub: hhmm(c.at),
              onTap: () => showComboSheet(context),
            ),
          if (tr.nutrition.isNotEmpty) ...[
            const SizedBox(height: 4),
            FormLabel('Voeding', trailing: '${grams(tr.nutritionCarbs)} g koolh.', trailingColor: k.accent),
            NutritionLogList(
              items: tr.nutrition,
              onCount: (n, c) => store.updateNutrition(n.id, count: c),
              onTime: (n, at) => store.updateNutrition(n.id, at: at),
              onDelete: (n) => store.deleteNutrition(n.id),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.icon, required this.color, required this.title, required this.sub, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KWell(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Text(title, style: context.t.bodyStrong)),
            Text(sub, style: context.t.caption),
            if (onTap != null) Icon(Icons.chevron_right, color: context.k.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SparringSummary extends StatelessWidget {
  const _SparringSummary({required this.block});
  final SparringBlock block;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final store = KineticScope.read(context);
    final b = block;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: KWell(
        onTap: () => showSparringSetupSheet(context, existing: b),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.sports_mma, color: k.danger, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Sparren • ${b.roundsDone}/${b.rounds.length} rondes', style: context.t.bodyStrong),
                ),
                Text(b.startedAt == null ? '' : hhmm(b.startedAt!), style: context.t.caption),
                const SizedBox(width: 4),
                Icon(Icons.edit_outlined, size: 18, color: k.textMuted),
              ],
            ),
            if (b.goal.isNotEmpty) ...[
              const SizedBox(height: 8),
              GoalCheck(
                label: 'Doel sparren',
                goal: b.goal,
                done: b.goalDone,
                onTap: () => store.toggleSparringGoal(b.id),
              ),
            ],
            for (var i = 0; i < b.rounds.length; i++)
              if (b.rounds[i].goal.isNotEmpty) ...[
                const SizedBox(height: 6),
                GoalCheck(
                  label: 'Ronde ${i + 1}',
                  goal: b.rounds[i].goal,
                  done: b.rounds[i].goalDone,
                  onTap: () => store.toggleRoundGoal(b.id, i),
                ),
              ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ topbalk
class SessionTopBar extends StatelessWidget {
  const SessionTopBar({
    super.key,
    required this.title,
    required this.status,
    this.statusTone = KTone.danger,
    this.live = true,
    this.statusIcon,
  });

  final String title;
  final String status;
  final KTone statusTone;
  final bool live;
  final IconData? statusIcon;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final fg = toneColors(k, statusTone).$2;
    return Container(
      decoration: BoxDecoration(
        color: k.canvas,
        border: Border(bottom: BorderSide(color: k.border)),
      ),
      padding: EdgeInsets.only(top: MediaQuery.viewPaddingOf(context).top),
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Minimaliseren (training loopt door)',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: Icon(Icons.arrow_back, color: k.text),
            ),
            const KineticLogo(size: 32),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: t.subtitle.copyWith(height: 1.15), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (statusIcon != null)
                        Icon(statusIcon, size: 12, color: fg)
                      else
                        LiveDot(color: toneSolid(k, statusTone), active: live, size: 7),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          status,
                          style: t.labelSm.copyWith(color: fg, fontWeight: FontWeight.w700),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: 'Training afronden',
              child: Material(
                color: k.well,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(KRadius.md),
                  side: BorderSide(color: k.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => finishSessionFlow(context, natural: false),
                  child: SizedBox(
                    height: 48,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        children: [
                          Icon(Icons.stop_rounded, size: 20, color: k.dangerInk),
                          const SizedBox(width: 4),
                          Text('Stop', style: t.bodyStrong.copyWith(color: k.text)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Voortgang van de huidige fase, links uitgelijnd (KProgressBar centreert
/// zijn vulling).
class PhaseBar extends StatelessWidget {
  const PhaseBar({super.key, required this.value, this.color, this.height = 8});
  final double value;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final v = value.isNaN ? 0.0 : value.clamp(0.0, 1.0);
    return Container(
      height: height,
      decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.full)),
      alignment: Alignment.centerLeft,
      child: FractionallySizedBox(
        widthFactor: v,
        heightFactor: 1,
        child: DecoratedBox(
          decoration: BoxDecoration(color: color ?? k.primary, borderRadius: BorderRadius.circular(KRadius.full)),
        ),
      ),
    );
  }
}

/// Rondevoortgang als segmenten: klaar = vol, huidige ronde = deels gevuld.
class RoundSegments extends StatelessWidget {
  const RoundSegments({
    super.key,
    required this.total,
    required this.done,
    this.currentProgress = 0,
    this.nextHighlighted = false,
  });

  final int total;

  /// Aantal volledig afgeronde rondes.
  final int done;

  /// Voortgang (0..1) van de ronde na [done], als die loopt.
  final double currentProgress;

  /// In de rust: de volgende ronde krijgt een rand.
  final bool nextHighlighted;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Row(
      children: [
        for (var i = 1; i <= total; i++) ...[
          if (i > 1) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: i <= done ? k.primary : k.well,
                borderRadius: BorderRadius.circular(KRadius.full),
                border: nextHighlighted && i == done + 1 ? Border.all(color: k.primary) : null,
              ),
              child: i == done + 1 && !nextHighlighted && currentProgress > 0
                  ? FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: currentProgress.clamp(0.0, 1.0),
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: k.accent, borderRadius: BorderRadius.circular(KRadius.full)),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ],
    );
  }
}

class _TechniqueBlock extends StatelessWidget {
  const _TechniqueBlock({required this.technique});
  final Technique technique;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final striking = technique.group.isStriking;
    final counts = store.sessionCounts[technique.id] ?? const TechniqueCounts();
    final sub = [
      technique.learningGoal,
      technique.transition,
    ].map((s) => s.trim()).firstWhere((s) => s.isNotEmpty, orElse: () => technique.group.description);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(striking ? Icons.sports_mma : Icons.sports_kabaddi, size: 24, color: k.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    technique.name,
                    style: t.title.copyWith(fontWeight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(sub, style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            KPill(technique.group.label, tone: striking ? KTone.primary : KTone.purple, dense: true),
            IconButton(
              tooltip: '${technique.name} weghalen',
              visualDensity: VisualDensity.compact,
              onPressed: () => store.toggleSessionTechnique(technique.id),
              icon: Icon(Icons.close, size: 20, color: k.textMuted),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final stat in TechniqueStat.values) ...[
              if (stat != TechniqueStat.success) const SizedBox(width: 8),
              Expanded(
                child: _CounterTile(
                  stat: stat,
                  label: statLabel(stat, striking: striking),
                  count: counts[stat],
                  onTap: () => store.incrementTechniqueStat(technique.id, stat),
                  onLongPress: () => store.incrementTechniqueStat(technique.id, stat, delta: -1),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CounterTile extends StatelessWidget {
  const _CounterTile({
    required this.stat,
    required this.label,
    required this.count,
    required this.onTap,
    required this.onLongPress,
  });

  final TechniqueStat stat;
  final String label;
  final int count;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final (icon, labelColor, valueColor) = switch (stat) {
      TechniqueStat.success => (Icons.check_circle_outline, k.successInk, k.text),
      TechniqueStat.attempt => (Icons.history, k.textSecondary, k.text),
      TechniqueStat.countered => (Icons.cancel_outlined, k.dangerInk, k.dangerInk),
    };
    return Semantics(
      button: true,
      label: '$label, $count keer. Tik plus één, lang indrukken min één.',
      excludeSemantics: true,
      child: Material(
        color: k.well,
        borderRadius: BorderRadius.circular(KRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          onLongPress: () {
            HapticFeedback.heavyImpact();
            onLongPress();
          },
          child: SizedBox(
            height: 84,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: labelColor),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: t.caption.copyWith(color: labelColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${count}x',
                    style: t.metricMd.copyWith(fontWeight: FontWeight.w800, color: valueColor),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sheet om technieken aan de mat-tellers toe te voegen of weg te halen.
/// Tellers van een weggehaalde techniek blijven bewaard.
Future<void> showSessionTechniquePicker(BuildContext context) {
  return showKineticSheet<void>(
    context,
    builder: (ctx) {
      final k = ctx.k;
      final t = ctx.t;
      final s = KineticScope.of(ctx);
      final groups = [
        for (final g in TechniqueGroup.values)
          if (s.techniques.any((x) => x.group == g)) g,
      ];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Focus wisselen of toevoegen', style: t.headline),
          const SizedBox(height: 4),
          Text(
            'Tik een techniek om hem aan de mat-tellers toe te voegen of weg te halen. Tellers blijven bewaard.',
            style: t.body.copyWith(color: k.textSecondary),
          ),
          const SizedBox(height: 16),
          if (s.techniques.isEmpty)
            KWell(
              child: Text(
                'Voeg eerst technieken toe in de Technieken Vault.',
                style: t.body.copyWith(color: k.textSecondary),
              ),
            ),
          for (final g in groups) ...[
            Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Eyebrow(g.label)),
            for (final tech in s.techniques.where((x) => x.group == g)) ...[
              _PickRow(
                technique: tech,
                selected: s.sessionTechniqueIds.contains(tech.id),
                counts: s.sessionCounts[tech.id],
                onTap: () {
                  HapticFeedback.selectionClick();
                  s.toggleSessionTechnique(tech.id);
                },
              ),
              const SizedBox(height: 8),
            ],
          ],
          const SizedBox(height: 8),
          BigButton(label: 'Klaar', onPressed: () => Navigator.of(ctx).pop()),
        ],
      );
    },
  );
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.technique, required this.selected, required this.counts, required this.onTap});
  final Technique technique;
  final bool selected;
  final TechniqueCounts? counts;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final c = counts;
    final striking = technique.group.isStriking;
    final summary = c == null || c.total == 0
        ? null
        : '${c.success} ${statLabel(TechniqueStat.success, striking: striking).toLowerCase()} • ${c.total} totaal';
    return Semantics(
      selected: selected,
      child: KWell(
        onTap: onTap,
        color: selected ? k.primaryTint : null,
        borderColor: selected ? k.primary : k.border,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.radio_button_unchecked,
                color: selected ? k.primary : k.textMuted,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(technique.name, style: t.bodyStrong, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      summary ?? (selected ? 'Actief op de mat' : 'Tik om toe te voegen'),
                      style: t.caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class MatControlButton extends StatelessWidget {
  const MatControlButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.style = KButtonStyle.primary,
    this.height = 72,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final KButtonStyle style;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final (bg, fg, iconColor, side) = switch (style) {
      KButtonStyle.primary => (k.primary, k.onPrimary, k.onPrimary, BorderSide.none),
      KButtonStyle.secondary => (k.well, k.text, k.accent, BorderSide(color: k.border)),
      KButtonStyle.critical => (k.danger, Colors.white, Colors.white, BorderSide.none),
      KButtonStyle.ghost => (const Color(0x00000000), k.accent, k.accent, BorderSide(color: k.border)),
    };
    return Semantics(
      button: true,
      child: SizedBox(
        height: height,
        child: Material(
          color: bg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md), side: side),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onPressed!();
                  },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 28, color: iconColor),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label.toUpperCase(),
                      maxLines: 1,
                      style: context.t.label.copyWith(color: fg, fontWeight: FontWeight.w800, letterSpacing: 0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Acute mat-interventie: snelle koolhydraten (dextrose, grootte uit de
/// instellingen, standaard 15g) of +200ml isotone drank (14g koolh.).
Future<void> logMatIntervention(BuildContext context, {required bool dextrose}) async {
  final store = KineticScope.read(context);
  final g = store.fastCarbGrams;
  final e = await store.logFood(
    description: dextrose ? 'Dextrose gel (mat-interventie)' : 'Isotone drank 200ml (mat-interventie)',
    carbs: dextrose ? g.toDouble() : 14,
    context: MealContext.acute,
  );
  if (!dextrose) await store.addWater(200);
  if (!context.mounted) return;
  if (e == null) {
    showToast(context, 'Opslaan mislukt', error: true);
    return;
  }
  showToast(
    context,
    dextrose ? '+${g}g dextrose gelogd' : '+200ml isotoon (14g koolh.) gelogd',
    actionLabel: 'Ongedaan',
    onAction: () {
      store.deleteFood(e);
      if (!dextrose) store.addWater(-200);
    },
  );
}

// ------------------------------------------------------------- spartellers

/// Tijdens het sparren: per techniek Geslaagd/Poging/Gecounterd (striking:
/// Clean Hit/Geblokt/Tegenstoot). Tik = +1, lang indrukken = −1. Ook in de
/// rust beschikbaar.
class TechniqueFocusCard extends StatelessWidget {
  const TechniqueFocusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final list = [...store.sessionTechniques]..sort((a, b) => a.isInFocus == b.isInFocus ? 0 : (a.isInFocus ? -1 : 1));
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const IconTile(icon: Icons.track_changes, size: 36, filled: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TECHNIEKEN TIJDENS HET SPARREN',
                      style: t.label.copyWith(color: k.accent, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('Tik = +1 • lang indrukken = −1', style: t.caption),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Nog geen technieken. Voeg er hieronder een toe om te tellen.',
                style: t.body.copyWith(color: k.textSecondary),
              ),
            ),
          for (var i = 0; i < list.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(height: 1, color: k.border),
              ),
            _TechniqueBlock(technique: list[i]),
          ],
          const SizedBox(height: 12),
          KWell(
            onTap: () => showSessionTechniquePicker(context),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                children: [
                  Icon(Icons.add, color: k.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Techniek toevoegen of weghalen', style: t.bodyStrong)),
                  Icon(Icons.chevron_right, color: k.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Training afronden: vraagt opslaan/verwerpen en gaat terug naar de tabs.
Future<void> finishSessionFlow(BuildContext context, {required bool natural}) async {
  final store = KineticScope.read(context);
  final tr = store.training;
  if (tr == null) return;
  final now = store.now();
  final minutes = tr.hasStarted(now) ? now.difference(tr.startsAt).inMinutes : 0;
  final rounds = tr.sparrings.fold<int>(0, (a, b) => a + b.roundsDone) + (store.sparring?.round ?? 0);
  final goals = [
    for (final b in tr.sparrings) ...[
      if (b.goal.isNotEmpty) b.goalDone,
      for (final r in b.rounds)
        if (r.goal.isNotEmpty) r.goalDone,
    ],
  ];
  final glucose = store.sessionGlucose;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: !natural,
    builder: (ctx) {
      final k = ctx.k;
      final tt = ctx.t;
      return AlertDialog(
        title: Text(natural ? 'Training voltooid 🥋' : 'Training afronden?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${tr.displayTitle} • ${durationLabel(minutes)}', style: tt.body),
            if (tr.warmups.isNotEmpty)
              Text('Warming-up ${tr.warmups.fold<int>(0, (a, w) => a + w.minutes)} min', style: tt.body),
            if (rounds > 0) Text('$rounds sparrondes', style: tt.body),
            if (goals.isNotEmpty)
              Text('${goals.where((g) => g).length} van ${goals.length} doelen gehaald', style: tt.body),
            if (tr.nutrition.isNotEmpty) Text('Voeding: ${grams(tr.nutritionCarbs)} g koolh.', style: tt.body),
            if (glucose.isNotEmpty)
              Text(
                'Glucose ${glucose.first.mmol.toStringAsFixed(1)} → ${glucose.last.mmol.toStringAsFixed(1)} mmol/L',
                style: tt.bodyStrong.copyWith(color: toneColors(k, glucoseZoneTone(glucose.last.mmol)).$2),
              ),
          ],
        ),
        actions: [
          if (!natural) TextButton(onPressed: () => Navigator.pop(ctx, 'continue'), child: const Text('Doorgaan')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            style: TextButton.styleFrom(foregroundColor: k.dangerInk),
            child: const Text('Verwerpen'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Opslaan')),
        ],
      );
    },
  );
  if (choice == null || choice == 'continue' || !context.mounted) return;
  if (choice == 'discard') {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Training verwerpen?'),
        content: const Text(
          'Warming-up, sparren, technieken, voeding en glucoseverloop van deze training worden niet opgeslagen.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Terug')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: ctx.k.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwerpen'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
  }
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final saved = await store.finishTraining(save: choice == 'save');
  navigator.popUntil((r) => r.isFirst);
  if (choice == 'save') {
    showToastOn(
      messenger,
      saved == null ? 'Opslaan mislukt' : 'Training opgeslagen in je historie',
      error: saved == null,
    );
  }
}
