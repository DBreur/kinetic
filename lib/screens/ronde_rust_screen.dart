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
    if (t == null) return;
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
        builder: (ctx) => AlertDialog(
          title: Text(c.title, style: KText.title.copyWith(color: KColor.danger)),
          content: Text('${c.detail}\n\nWeet je zeker dat je de volgende ronde wilt starten?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nee, wachten')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: KColor.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Toch starten'),
            ),
          ],
        ),
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
    final clearance = store.clearanceForNextRound();
    final remaining = store.roundSecondsRemaining;
    final held = t.restHeld;
    final r = store.reading;
    return Scaffold(
      backgroundColor: KColor.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
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
                      child: Text(
                        'RONDE RUST • R${t.round} VOLTOOID',
                        style: KText.eyebrow.copyWith(color: KColor.tealLight, fontSize: 12),
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
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  if (store.hypoAlert && r != null)
                    HypoBanner(reading: r, onDextrose: () => logMatIntervention(context, dextrose: true)),
                  Center(
                    child: CountdownRing(
                      progress: t.phaseProgress(store.now()),
                      color: held ? KColor.danger : clearance.color == KColor.textSecondary ? KColor.teal : clearance.color,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            held ? 'WACHT' : mmss(remaining),
                            style: KText.timer.copyWith(fontSize: held ? 48 : 64, color: held ? KColor.danger : KColor.text),
                          ),
                          const SizedBox(height: 4),
                          Text(held ? 'GLUCOSE EERST' : 'HERSTELTIJD', style: KText.eyebrow.copyWith(color: held ? KColor.danger : KColor.textSecondary)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton(
                      onPressed: _startNext,
                      style: TextButton.styleFrom(minimumSize: const Size(0, 52)),
                      child: Text('⏩ Sla rust over • Start R$next direct', style: KText.body.copyWith(color: KColor.tealLight, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _ClearanceCard(clearance: clearance),
                  const SizedBox(height: 10),
                  const IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: DexcomLiveCard(showClearance: true)),
                        SizedBox(width: 10),
                        Expanded(child: PolarLiveCard(showRecovery: true)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  const _BreathingGuide(),
                  const SizedBox(height: 16),
                  const Eyebrow('Acute mat-interventies', color: KColor.warning, icon: Icons.medical_services_outlined),
                  const SizedBox(height: 8),
                  BigButton(
                    label: '+15g Dextrose (Snelwerkende Gel)',
                    icon: Icons.bolt,
                    color: KColor.warning,
                    onPressed: () => logMatIntervention(context, dextrose: true),
                  ),
                  const SizedBox(height: 8),
                  BigButton(
                    label: '+200ml Isotone Drank (14g Koolh.)',
                    icon: Icons.local_drink,
                    color: KColor.blue,
                    outlined: true,
                    onPressed: () => logMatIntervention(context, dextrose: false),
                  ),
                  const SizedBox(height: 16),
                  _CoachFocus(round: next),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: KColor.surface,
                border: Border(top: BorderSide(color: KColor.border)),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: BigButton(
                      height: 72,
                      label: '+30s Rust',
                      icon: Icons.more_time,
                      color: KColor.surfaceElevated,
                      foreground: KColor.text,
                      onPressed: () => store.addRestSeconds(30),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: BigButton(
                      height: 72,
                      label: '🥋 KLAAR VOOR RONDE $next',
                      color: clearance.blocksNextRound ? KColor.danger : KColor.teal,
                      foreground: clearance.blocksNextRound ? KColor.text : KColor.bg,
                      onPressed: _startNext,
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

class _ClearanceCard extends StatelessWidget {
  const _ClearanceCard({required this.clearance});
  final MatClearance clearance;

  @override
  Widget build(BuildContext context) {
    final icon = switch (clearance.level) {
      ClearanceLevel.safe => Icons.verified,
      ClearanceLevel.caution => Icons.warning_amber_rounded,
      ClearanceLevel.danger => Icons.dangerous,
      ClearanceLevel.unknown => Icons.help_outline,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: clearance.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(KRadius.lg),
        border: Border.all(color: clearance.color.withValues(alpha: 0.6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: clearance.color, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(clearance.title, style: KText.subtitle.copyWith(color: clearance.color, fontWeight: FontWeight.w900)),
                const SizedBox(height: 2),
                Text(clearance.detail, style: KText.caption.copyWith(color: KColor.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    return KCard(
      padding: const EdgeInsets.all(14),
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value * 10; // seconden in de cyclus
          final inhale = t < 4;
          final scale = inhale ? 0.55 + 0.45 * (t / 4) : 1.0 - 0.45 * ((t - 4) / 6);
          final secsLeft = inhale ? (4 - t).ceil() : (10 - t).ceil();
          return Row(
            children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: Container(
                    width: 64 * scale,
                    height: 64 * scale,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: KColor.blue.withValues(alpha: 0.25),
                      border: Border.all(color: KColor.blue, width: 2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('Vagale ademhaling', color: KColor.blue),
                    const SizedBox(height: 4),
                    Text(inhale ? 'Inademen • $secsLeft' : 'Uitademen • $secsLeft', style: KText.title),
                    Text('Inademen 4s / Uitademen 6s', style: KText.caption),
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

class _CoachFocus extends StatelessWidget {
  const _CoachFocus({required this.round});
  final int round;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final text = store.coachFocusFor(round);
    return KCard(
      borderColor: KColor.purple.withValues(alpha: 0.5),
      onTap: () => _edit(context, store, text),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Eyebrow('Coach focus • ronde $round', color: KColor.purple, icon: Icons.record_voice_over)),
              const Icon(Icons.edit, size: 16, color: KColor.textMuted),
            ],
          ),
          const SizedBox(height: 8),
          Text(text, style: KText.title.copyWith(fontSize: 20)),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, KineticStore store, String current) async {
    final ctrl = TextEditingController(text: store.coachFocus[round] ?? '');
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Instructie ronde $round'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: current),
          onSubmitted: (s) => Navigator.pop(ctx, s),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Opslaan')),
        ],
      ),
    );
    ctrl.dispose();
    if (v != null) store.setCoachFocus(round, v.trim());
  }
}
