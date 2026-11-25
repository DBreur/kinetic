// ronde_rust_screen.dart: Ronde Rust: hersteltimer, acute glucose-check,
// Polar H10-herstel met vagale ademhaling, mat-interventies en de coach-
// instructie voor de volgende ronde. Bij een hypo start de volgende ronde
// niet vanzelf: dan moet je bewust bevestigen.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/sparring_timer.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/charts.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/telemetry_widgets.dart';
import '../widgets/training_sheets.dart';
import 'live_session_screen.dart';

class RondeRustScreen extends StatefulWidget {
  const RondeRustScreen({super.key});

  @override
  State<RondeRustScreen> createState() => _RondeRustScreenState();
}

class _RondeRustScreenState extends State<RondeRustScreen> {
  late final KineticStore _store = KineticScope.read(context);
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _store.sparringEvents.addListener(_onEvent);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onEvent();
      // Direct bij binnenkomst een verse glucosewaarde ophalen.
      _store.refreshGlucose();
    });
  }

  @override
  void dispose() {
    _store.sparringEvents.removeListener(_onEvent);
    super.dispose();
  }

  void _onEvent() {
    if (!mounted || _leaving) return;
    final t = _store.sparring;
    if (t == null) {
      // Sparblok gestopt of afgerond: terug naar de training.
      _leaving = true;
      if (_store.isTrainingActive) {
        Navigator.of(context).pushReplacementNamed('/live-session');
      } else {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (t.phase == SparringPhase.work) {
      _leaving = true;
      HapticFeedback.heavyImpact();
      Navigator.of(context).pushReplacementNamed('/live-session');
    } else if (_store.sparringEvents.value == SparringEvent.restHeld) {
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _startNext() async {
    final c = _store.clearanceForNextRound();
    if (c.blocksNextRound) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) {
          final k = ctx.k;
          return AlertDialog(
            icon: Icon(Icons.dangerous, color: k.danger, size: 32),
            title: Text(c.title, style: ctx.t.title.copyWith(color: k.dangerInk, fontWeight: FontWeight.w700)),
            content: Text('${c.detail}\n\nWeet je zeker dat je de volgende ronde wilt starten?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nee, wachten')),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: k.danger, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Toch starten'),
              ),
            ],
          );
        },
      );
      if (go != true) return;
    }
    _store.startNextRound();
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final t = store.sparring;
    if (t == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final next = t.round + 1;
    final noTimer = !store.restTimerEnabled;
    final clearance = store.clearanceForNextRound();
    final r = store.reading;
    final hypo = liveHypo(store);
    return Scaffold(
      body: Column(
        children: [
          SessionTopBar(
            title: 'Ronde rust',
            status: t.restHeld && !noTimer ? 'WACHT OP GLUCOSE' : 'HERSTEL • R${t.round} VOLTOOID',
            statusTone: t.restHeld && !noTimer ? KTone.danger : KTone.info,
            live: !t.restHeld,
          ),
          Expanded(
            // De ruimte voor de systeemknoppen zit in de BottomActionBar.
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (hypo && r != null)
                    HypoBanner(
                      reading: r,
                      grams: store.fastCarbGrams,
                      onDextrose: () => logMatIntervention(context, dextrose: true),
                    ),
                  _RestTimerCard(timer: t, clearance: clearance, onSkip: _startNext),
                  const SizedBox(height: 12),
                  _ClearanceCard(clearance: clearance),
                  const SizedBox(height: 12),
                  const TelemetryRow(rest: true),
                  const SizedBox(height: 12),
                  const _BreathingGuide(),
                  const SizedBox(height: 20),
                  BigButton(
                    height: 64,
                    label: 'Voeding loggen',
                    icon: Icons.restaurant,
                    style: clearance.level == ClearanceLevel.danger ? KButtonStyle.critical : KButtonStyle.secondary,
                    onPressed: () => showNutritionSheet(context),
                  ),
                  const SizedBox(height: 20),
                  _NextRoundGoals(round: next),
                  const SizedBox(height: 12),
                  const TechniqueFocusCard(),
                ],
              ),
            ),
          ),
          BottomActionBar(
            child: Row(
              children: [
                if (!noTimer) ...[
                  Expanded(
                    child: BigButton(
                      height: 72,
                      vertical: true,
                      label: '+30s Rust',
                      icon: Icons.more_time,
                      style: KButtonStyle.secondary,
                      onPressed: () => store.addRestSeconds(30),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: BigButton(
                    height: 72,
                    label: '🥋 KLAAR VOOR RONDE $next',
                    style: clearance.blocksNextRound ? KButtonStyle.critical : KButtonStyle.primary,
                    onPressed: _startNext,
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

// ------------------------------------------------------------- timer

class _RestTimerCard extends StatelessWidget {
  const _RestTimerCard({required this.timer, required this.clearance, required this.onSkip});
  final SparringTimer timer;
  final MatClearance clearance;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final noTimer = !store.restTimerEnabled;
    // Zonder rusttimer is "vastgehouden" normaal: geen rood WACHT-scherm.
    final held = timer.restHeld && !noTimer;
    final next = timer.round + 1;
    final restElapsed = store.now().difference(timer.phaseStartedAt).inSeconds;
    final total = timer.config.rounds;
    final remaining = store.roundSecondsRemaining;
    final ringColor = held
        ? k.danger
        : switch (clearance.level) {
            ClearanceLevel.safe || ClearanceLevel.unknown => k.primary,
            ClearanceLevel.caution => k.warning,
            ClearanceLevel.danger => k.danger,
          };
    return KCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        children: [
          KPill('Ronde ${timer.round} voltooid', tone: KTone.success, icon: Icons.check_circle, uppercase: true),
          const SizedBox(height: 12),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Rust voor ronde ', style: t.title.copyWith(color: k.textSecondary)),
                TextSpan(text: '$next', style: t.headline.copyWith(fontSize: 26, fontWeight: FontWeight.w800)),
                TextSpan(text: ' / $total', style: t.title.copyWith(color: k.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          RoundSegments(total: total, done: timer.round, nextHighlighted: true),
          const SizedBox(height: 20),
          Semantics(
            label: held ? 'Rust vastgehouden: eerst glucose herstellen' : 'Hersteltijd ${mmss(remaining)}',
            excludeSemantics: true,
            child: CountdownRing(
              size: 228,
              stroke: 12,
              // Vastgehouden: volle rode ring.
              progress: held || noTimer ? 0 : timer.phaseProgress(store.now()),
              color: ringColor,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (held) ...[
                    Icon(Icons.pan_tool_rounded, color: k.dangerInk, size: 28),
                    const SizedBox(height: 4),
                  ],
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      held ? 'WACHT' : mmss(noTimer ? restElapsed : remaining),
                      style: t.timer.copyWith(fontSize: held ? 48 : 60, color: held ? k.dangerInk : k.text),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    held ? 'GLUCOSE EERST' : (noTimer ? 'RUST • GEEN TIMER' : 'HERSTELTIJD'),
                    style: t.label.copyWith(color: held ? k.dangerInk : k.textSecondary, fontWeight: FontWeight.w700, letterSpacing: 1.2),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onSkip,
            style: TextButton.styleFrom(minimumSize: const Size(0, 52), foregroundColor: k.accent),
            icon: const Icon(Icons.fast_forward_rounded, size: 22),
            label: Text(noTimer ? 'Start R$next' : 'Sla rust over • Start R$next direct', style: t.bodyStrong.copyWith(color: k.accent)),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- clearance

class _ClearanceCard extends StatelessWidget {
  const _ClearanceCard({required this.clearance});
  final MatClearance clearance;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final tone = clearanceTone(clearance.level);
    final (bg, ink) = toneColors(k, tone);
    final solid = toneSolid(k, tone);
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: clearance.level == ClearanceLevel.unknown ? k.surface : bg,
          borderRadius: BorderRadius.circular(KRadius.lg),
          border: Border.all(color: clearance.level == ClearanceLevel.unknown ? k.borderStrong : solid),
        ),
        child: Row(
          children: [
            Icon(clearanceIcon(clearance.level), color: solid, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(clearance.title, style: t.title.copyWith(color: ink, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(clearance.detail, style: t.body.copyWith(color: k.text)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- ademhaling

/// Vagale ademhaling: 4s in, 6s uit.
class _BreathingGuide extends StatefulWidget {
  const _BreathingGuide();

  @override
  State<_BreathingGuide> createState() => _BreathingGuideState();
}

class _BreathingGuideState extends State<_BreathingGuide> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    return KCard(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final s = _c.value * 10; // seconden in de cyclus
          final inhale = s < 4;
          final scale = inhale ? 0.5 + 0.5 * (s / 4) : 1.0 - 0.5 * ((s - 4) / 6);
          final secsLeft = inhale ? (4 - s).ceil() : (10 - s).ceil();
          return Row(
            children: [
              SizedBox(
                width: 72,
                height: 72,
                child: Center(
                  child: Container(
                    width: 72 * scale,
                    height: 72 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: k.blue.withValues(alpha: k.isDark ? 0.2 : 0.12),
                      border: Border.all(color: k.blue, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow('Vagale ademhaling', color: k.blue, icon: Icons.air),
                    const SizedBox(height: 4),
                    Text(inhale ? 'Inademen • $secsLeft' : 'Uitademen • $secsLeft', style: t.headline),
                    Text('Inademen 4s / Uitademen 6s', style: t.caption),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ------------------------------------------------------------- doelen

/// Doel van de volgende ronde en van het hele sparren (afvinkbaar; tik op
/// de kaart om het rondedoel aan te passen).
class _NextRoundGoals extends StatelessWidget {
  const _NextRoundGoals({required this.round});
  final int round;

  Future<void> _edit(BuildContext context, KineticStore store, String blockId, int index, String current) async {
    final ctrl = TextEditingController(text: current);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Doel ronde ${index + 1}'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Zet Harai Goshi in'),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Opslaan')),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) store.setRoundGoal(blockId, index, v);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final store = KineticScope.of(context);
    final block = store.training?.activeSparring;
    if (block == null) return const SizedBox.shrink();
    final prevIndex = round - 2;
    final index = round - 1;
    final prev = prevIndex >= 0 && prevIndex < block.rounds.length ? block.rounds[prevIndex] : null;
    final next = index < block.rounds.length ? block.rounds[index] : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prev != null && prev.goal.isNotEmpty) ...[
          GoalCheck(
            label: 'Doel ronde ${round - 1} gehaald?',
            goal: prev.goal,
            done: prev.goalDone,
            onTap: () => store.toggleRoundGoal(block.id, prevIndex),
          ),
          const SizedBox(height: 8),
        ],
        if (next != null)
          KCard(
            onTap: () => _edit(context, store, block.id, index, next.goal),
            child: Row(
              children: [
                IconTile(icon: Icons.flag_outlined, color: k.purple, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Eyebrow('Doel ronde $round', color: k.purple),
                      const SizedBox(height: 4),
                      Text(
                        next.goal.isEmpty ? 'Tik om een doel te zetten' : next.goal,
                        style: next.goal.isEmpty
                            ? context.t.body.copyWith(color: k.textSecondary)
                            : context.t.title.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.edit_outlined, size: 20, color: k.textSecondary),
              ],
            ),
          ),
        if (block.goal.isNotEmpty) ...[
          const SizedBox(height: 8),
          GoalCheck(label: 'Doel sparren', goal: block.goal, done: block.goalDone, onTap: () => store.toggleSparringGoal(block.id)),
        ],
      ],
    );
  }
}
