// live_session_screen.dart: Live Sparring & Mat-Modus. Handschoenvriendelijk:
// alle bedieningsknoppen zijn minstens 64px hoog, alles in hoog contrast.
// Loopt een ronde af (of tik je op VOLGENDE), dan gaat het scherm vanzelf
// naar /ronde-rust.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/meal_impact.dart';
import '../core/sparring_timer.dart';
import '../models/technique.dart';
import '../services/voice_memo_service.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/telemetry_widgets.dart';

class LiveSessionScreen extends StatefulWidget {
  const LiveSessionScreen({super.key});

  @override
  State<LiveSessionScreen> createState() => _LiveSessionScreenState();
}

class _LiveSessionScreenState extends State<LiveSessionScreen> {
  late final KineticStore _store = KineticScope.read(context);
  bool _leaving = false;

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
    if (t == null) return;
    if (t.phase == SparringPhase.rest) {
      _leaving = true;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushReplacementNamed('/ronde-rust');
    } else if (t.isDone) {
      _leaving = true;
      HapticFeedback.heavyImpact();
      finishSessionFlow(context, natural: true).then((_) => _leaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final t = store.sparring;
    if (t == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final r = store.reading;
    final paused = t.isPaused;
    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: KColor.bg,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(paused: paused),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  children: [
                    if (store.hypoAlert && r != null)
                      HypoBanner(reading: r, onDextrose: () => logMatIntervention(context, dextrose: true)),
                    _RoundHeader(timer: t),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: store.toggleSparringTimer,
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            mmss(store.roundSecondsRemaining),
                            style: KText.timer.copyWith(
                              color: paused ? KColor.textMuted : (store.roundSecondsRemaining <= 10 ? KColor.warning : KColor.text),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Center(
                      child: Text(
                        '${mmss(t.config.workSeconds)} werk / ${mmss(t.config.restSeconds)} rust${paused ? ' • GEPAUZEERD' : ''}',
                        style: KText.caption,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: DexcomLiveCard()),
                          SizedBox(width: 10),
                          Expanded(child: PolarLiveCard()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    const _TechniqueCounters(),
                    const SizedBox(height: 12),
                    const VoiceMemoButton(),
                  ],
                ),
              ),
              _BottomControls(paused: paused),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.paused});
  final bool paused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Minimaliseren',
            iconSize: 30,
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.keyboard_arrow_down, color: KColor.textSecondary),
          ),
          Expanded(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (paused ? KColor.warning : KColor.danger).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(KRadius.full),
                  border: Border.all(color: paused ? KColor.warning : KColor.danger),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiveDot(color: paused ? KColor.warning : KColor.danger, active: !paused),
                    const SizedBox(width: 8),
                    Text(
                      paused ? 'GEPAUZEERD' : 'ACTIEVE SPARRING • LIVE',
                      style: KText.eyebrow.copyWith(color: paused ? KColor.warning : KColor.danger, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Sessie afronden',
            iconSize: 28,
            onPressed: () => finishSessionFlow(context, natural: false),
            icon: const Icon(Icons.stop_circle_outlined, color: KColor.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RoundHeader extends StatelessWidget {
  const _RoundHeader({required this.timer});
  final SparringTimer timer;

  @override
  Widget build(BuildContext context) {
    final total = timer.config.rounds;
    return Column(
      children: [
        Text('Ronde ${timer.round} / $total', style: KText.title.copyWith(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 10),
        Row(
          children: [
            for (var i = 1; i <= total; i++) ...[
              if (i > 1) const SizedBox(width: 6),
              Expanded(
                child: Container(
                  height: 8,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(KRadius.full),
                    color: i < timer.round
                        ? KColor.teal
                        : i == timer.round
                        ? KColor.tealLight
                        : KColor.surfaceHigh,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _TechniqueCounters extends StatelessWidget {
  const _TechniqueCounters();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final list = store.sessionTechniques;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(child: Eyebrow('Techniek focus • mat-tap', color: KColor.tealLight, icon: Icons.touch_app)),
            TextButton.icon(
              onPressed: () => _pickTechniques(context),
              icon: const Icon(Icons.edit, size: 16, color: KColor.textSecondary),
              label: Text('Kiezen', style: KText.caption),
            ),
          ],
        ),
        if (list.isEmpty)
          KCard(
            onTap: () => _pickTechniques(context),
            child: Text('Nog geen focus-technieken. Tik om technieken voor deze sessie te kiezen.', style: KText.body.copyWith(color: KColor.textSecondary)),
          ),
        for (final t in list) ...[
          _CounterCard(technique: t),
          const SizedBox(height: 10),
        ],
        if (list.isNotEmpty)
          Text('Tik = +1 • lang indrukken = -1', textAlign: TextAlign.center, style: KText.caption.copyWith(color: KColor.textMuted)),
      ],
    );
  }

  Future<void> _pickTechniques(BuildContext context) {
    final store = KineticScope.read(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => KineticScope(
        store: store,
        child: Builder(
          builder: (ctx) {
            final s = KineticScope.of(ctx);
            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.7,
              builder: (_, scroll) => ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  Text('Technieken voor deze sessie', style: KText.title),
                  const SizedBox(height: 12),
                  for (final t in s.techniques)
                    CheckboxListTile(
                      value: s.sessionTechniqueIds.contains(t.id),
                      onChanged: (_) => s.toggleSessionTechnique(t.id),
                      title: Text(t.name, style: KText.body),
                      subtitle: Text(t.group.label, style: KText.caption),
                      contentPadding: EdgeInsets.zero,
                    ),
                  if (s.techniques.isEmpty) Text('Voeg eerst technieken toe in de Technieken Vault.', style: KText.caption),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  const _CounterCard({required this.technique});
  final Technique technique;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final striking = technique.group.isStriking;
    final counts = store.sessionCounts[technique.id] ?? const TechniqueCounts();
    final colors = {
      TechniqueStat.success: KColor.success,
      TechniqueStat.attempt: KColor.blue,
      TechniqueStat.countered: KColor.danger,
    };
    return KCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(technique.name, style: KText.subtitle.copyWith(fontSize: 17))),
              KBadge(striking ? 'Striking' : 'Grappling', color: striking ? KColor.danger : KColor.purple, dot: false),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (final stat in TechniqueStat.values) ...[
                if (stat != TechniqueStat.success) const SizedBox(width: 8),
                Expanded(
                  child: _TapCounter(
                    label: statLabel(stat, striking: striking),
                    count: counts[stat],
                    color: colors[stat]!,
                    onTap: () => store.incrementTechniqueStat(technique.id, stat),
                    onLongPress: () => store.incrementTechniqueStat(technique.id, stat, delta: -1),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _TapCounter extends StatelessWidget {
  const _TapCounter({required this.label, required this.count, required this.color, required this.onTap, required this.onLongPress});
  final String label;
  final int count;
  final Color color;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(KRadius.md);
    return Semantics(
      button: true,
      label: '$label, $count',
      child: Material(
        color: color.withValues(alpha: 0.14),
        shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: color.withValues(alpha: 0.55), width: 1.5)),
        child: InkWell(
          borderRadius: radius,
          onTap: () {
            HapticFeedback.mediumImpact();
            onTap();
          },
          onLongPress: () {
            HapticFeedback.heavyImpact();
            onLongPress();
          },
          child: SizedBox(
            height: 78,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('$count', style: KText.metric.copyWith(color: color, fontSize: 30)),
                const SizedBox(height: 4),
                Text(label, style: KText.caption.copyWith(color: KColor.text, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Snelle Spraaknotitie Coach (REC)".
class VoiceMemoButton extends StatefulWidget {
  const VoiceMemoButton({super.key});

  @override
  State<VoiceMemoButton> createState() => _VoiceMemoButtonState();
}

class _VoiceMemoButtonState extends State<VoiceMemoButton> {
  final _recorder = VoiceMemoRecorder();
  late final KineticStore _store = KineticScope.read(context);
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    if (_recorder.isRecording) {
      // Scherm wisselt (bv. naar de rust): opname netjes afsluiten.
      _recorder.stop().then((p) {
        if (p != null) _store.addVoiceMemo(p);
      }).whenComplete(_recorder.dispose);
    } else {
      _recorder.dispose();
    }
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_recorder.isRecording) {
      final path = await _recorder.stop();
      _tick?.cancel();
      if (path != null) _store.addVoiceMemo(path);
      if (mounted) {
        setState(() {});
        showToast(context, 'Spraakmemo opgeslagen (${_store.voiceMemos.length})');
      }
      return;
    }
    bool ok;
    try {
      ok = await _recorder.start(round: _store.sparring?.round ?? 0);
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (!ok) {
      showToast(context, 'Geen toegang tot de microfoon', error: true);
      return;
    }
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final rec = _recorder.isRecording;
    final secs = rec ? DateTime.now().difference(_recorder.startedAt!).inSeconds : 0;
    return BigButton(
      label: rec
          ? 'REC ${mmss(secs)} • tik om te stoppen'
          : 'Snelle Spraaknotitie Coach (REC)${store.voiceMemos.isEmpty ? '' : ' • ${store.voiceMemos.length}'}',
      icon: rec ? Icons.stop_circle : Icons.mic,
      color: KColor.danger,
      outlined: !rec,
      foreground: KColor.text,
      onPressed: _toggle,
    );
  }
}

class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.paused});
  final bool paused;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.read(context);
    final last = store.sparring?.isLastRound ?? false;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: const BoxDecoration(
        color: KColor.surface,
        border: Border(top: BorderSide(color: KColor.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: BigButton(
              height: 72,
              label: paused ? 'HERVAT' : 'PAUZE',
              icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: paused ? KColor.teal : KColor.surfaceElevated,
              foreground: paused ? KColor.bg : KColor.text,
              onPressed: store.toggleSparringTimer,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: BigButton(
              height: 72,
              label: last ? 'AFRONDEN' : 'VOLGENDE',
              icon: last ? Icons.flag_rounded : Icons.skip_next_rounded,
              onPressed: store.advanceToRestPhase,
            ),
          ),
        ],
      ),
    );
  }
}

/// Acute mat-interventie: +15g dextrose of +200ml isotone drank (14g koolh.).
Future<void> logMatIntervention(BuildContext context, {required bool dextrose}) async {
  final store = KineticScope.read(context);
  final e = await store.logFood(
    description: dextrose ? 'Dextrose gel (mat-interventie)' : 'Isotone drank 200ml (mat-interventie)',
    carbs: dextrose ? 15 : 14,
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
    dextrose ? '+15g dextrose gelogd' : '+200ml isotoon (14g koolh.) gelogd',
    actionLabel: 'Ongedaan',
    onAction: () {
      store.deleteFood(e);
      if (!dextrose) store.addWater(-200);
    },
  );
}

/// Afronden: vraagt opslaan/verwerpen en gaat terug naar de tabs.
Future<void> finishSessionFlow(BuildContext context, {required bool natural}) async {
  final store = KineticScope.read(context);
  final t = store.sparring;
  if (t == null) return;
  final minutes = store.now().difference(t.startedAt).inMinutes;
  final totals = store.sessionCounts.values.fold<(int, int)>(
    (0, 0),
    (acc, c) => (acc.$1 + c.success, acc.$2 + c.total),
  );
  final glucose = store.sessionGlucose;
  final choice = await showDialog<String>(
    context: context,
    barrierDismissible: !natural,
    builder: (ctx) => AlertDialog(
      title: Text(natural ? 'Sessie voltooid 🥋' : 'Sessie afronden?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${t.round} van ${t.config.rounds} rondes • ${durationLabel(minutes)}', style: KText.body),
          if (totals.$2 > 0) Text('${totals.$1} geslaagd van ${totals.$2} acties', style: KText.body),
          if (glucose.isNotEmpty)
            Text(
              'Glucose ${glucose.first.mmol.toStringAsFixed(1)} ➔ ${glucose.last.mmol.toStringAsFixed(1)} mmol/L',
              style: KText.body.copyWith(color: glucoseColor(glucose.last.mmol)),
            ),
          if (store.voiceMemos.isNotEmpty) Text('${store.voiceMemos.length} spraakmemo(s) op dit toestel', style: KText.caption),
        ],
      ),
      actions: [
        if (!natural) TextButton(onPressed: () => Navigator.pop(ctx, 'continue'), child: const Text('Doorgaan')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'discard'),
          child: const Text('Verwerpen', style: TextStyle(color: KColor.danger)),
        ),
        FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('Opslaan')),
      ],
    ),
  );
  if (choice == null || choice == 'continue' || !context.mounted) return;
  if (choice == 'discard') {
    final sure = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sessie verwerpen?'),
        content: const Text('Tellers en glucoseverloop van deze sessie worden niet opgeslagen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Terug')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: KColor.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Verwerpen'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) {
      if (natural && context.mounted) return finishSessionFlow(context, natural: true);
      return;
    }
  }
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final saved = await store.finishSparring(save: choice == 'save');
  navigator.popUntil((r) => r.isFirst);
  if (choice == 'save') {
    showToastOn(messenger, saved == null ? 'Opslaan mislukt' : 'Sessie opgeslagen in je trainingshistorie', error: saved == null);
  }
}
