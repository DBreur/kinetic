// live_session_screen.dart: Live Sparring & Mat-Modus ("Actieve ronde-timer").
// Handschoenvriendelijk: de rondeklok is minstens 88px en leesbaar vanaf een
// paar meter, alle mat-bediening is minstens 64px. Loopt een ronde af (of tik
// je op VOLGENDE), dan gaat het scherm vanzelf naar /ronde-rust; na de
// laatste ronde volgt de opslaan/verwerpen-flow.

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
    final paused = t.isPaused;
    final hypo = liveHypo(store);
    final r = store.reading;
    return Scaffold(
      body: Column(
        children: [
          SessionTopBar(
            title: 'Actieve ronde-timer',
            status: paused ? 'GEPAUZEERD' : 'ACTIEVE SPARRING • LIVE',
            statusTone: paused ? KTone.warning : KTone.danger,
            live: !paused,
          ),
          Expanded(
            // SingleChildScrollView: alles wordt gebouwd, zodat tellers en
            // knoppen altijd vindbaar zijn. De onderste ruimte voor de
            // systeemknoppen zit in de BottomActionBar hieronder.
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
                    )
                  else ...[
                    const _GlucoseStrip(),
                    const SizedBox(height: 12),
                  ],
                  _TimerCard(timer: t),
                  const SizedBox(height: 12),
                  const TelemetryRow(),
                  const SizedBox(height: 12),
                  const TechniqueFocusCard(),
                  const SizedBox(height: 12),
                  const _FastCarbCard(),
                ],
              ),
            ),
          ),
          BottomActionBar(
            child: Row(
              children: [
                Expanded(
                  child: MatControlButton(
                    label: paused ? 'Hervat' : 'Pauze',
                    icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                    onPressed: store.toggleSparringTimer,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: MatControlButton(
                    label: t.isLastRound ? 'Afronden' : 'Volgende',
                    icon: t.isLastRound ? Icons.flag_rounded : Icons.skip_next_rounded,
                    style: KButtonStyle.secondary,
                    onPressed: store.advanceToRestPhase,
                  ),
                ),
                const SizedBox(width: 8),
                const Expanded(child: VoiceMemoButton(compact: true)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- top bar

/// Top bar van de mat-schermen: minimaliseren, logo, titel met live-status
/// en een stopknop (afronden met opslaan/verwerpen).
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
              tooltip: 'Minimaliseren (sessie loopt door)',
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
              message: 'Sessie afronden',
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

// ------------------------------------------------------------- glucose strip

/// "Stabiel • 6.8 mmol/L ↗ / Optimale sparringzone" met snelle carbs-knop.
class _GlucoseStrip extends StatelessWidget {
  const _GlucoseStrip();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final r = store.reading;
    final c = store.clearanceForNextRound();
    final tone = clearanceTone(c.level);
    final (bg, fg) = toneColors(k, tone);
    final word = switch (c.level) {
      ClearanceLevel.safe => 'Stabiel',
      ClearanceLevel.caution => 'Let op',
      ClearanceLevel.danger => 'Hypo',
      ClearanceLevel.unknown => 'Onzeker',
    };
    final sub = switch (c.level) {
      ClearanceLevel.safe => 'Optimale sparringzone',
      ClearanceLevel.danger => 'Stop: neem snelle koolhydraten',
      _ => c.title,
    };
    final icon = switch (c.level) {
      ClearanceLevel.safe => Icons.monitor_heart,
      ClearanceLevel.caution => Icons.warning_amber_rounded,
      ClearanceLevel.danger => Icons.dangerous,
      ClearanceLevel.unknown => Icons.sensors_off,
    };
    return KCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: fg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        r == null ? 'Geen glucosewaarde' : '$word • ${r.mmol.toStringAsFixed(1)} mmol/L',
                        style: t.bodyStrong,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (r != null) ...[
                      const SizedBox(width: 6),
                      Icon(trendIcon(r.trend), size: 18, color: toneSolid(k, tone)),
                    ],
                  ],
                ),
                Text(sub, style: t.caption.copyWith(color: fg), maxLines: 1, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Semantics(
            button: true,
            label: '${store.fastCarbGrams} gram snelle koolhydraten loggen',
            excludeSemantics: true,
            child: Material(
              color: k.well,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(KRadius.md),
                side: BorderSide(color: k.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  logMatIntervention(context, dextrose: true);
                },
                child: SizedBox(
                  height: 48,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: [
                        Icon(Icons.bolt, size: 18, color: k.accent),
                        const SizedBox(width: 4),
                        Text('+${store.fastCarbGrams}g', style: t.bodyStrong.copyWith(color: k.accent)),
                      ],
                    ),
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

// ------------------------------------------------------------- timer

String _disciplineLabel(String title) {
  final t = title.trim();
  return (t.toLowerCase().contains('sparring') ? t : '$t sparring').toUpperCase();
}

String _restLabel(int seconds) => '${seconds ~/ 60}:${two(seconds % 60)}';

class _TimerCard extends StatelessWidget {
  const _TimerCard({required this.timer});
  final SparringTimer timer;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final paused = timer.isPaused;
    final remaining = store.roundSecondsRemaining;
    final total = timer.config.rounds;
    final last = timer.isLastRound;
    final timeColor = paused
        ? k.textMuted
        : remaining <= 10
        ? k.warningInk
        : k.text;
    return KCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        children: [
          // Discipline + live/gepauzeerd.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: paused ? k.warningTint : k.primaryTint,
              borderRadius: BorderRadius.circular(KRadius.full),
            ),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (paused)
                    Icon(Icons.pause_rounded, size: 14, color: k.warningInk)
                  else
                    LiveDot(color: k.accent, size: 7),
                  const SizedBox(width: 8),
                  Text(
                    paused ? '${_disciplineLabel(store.sessionTitle)} • GEPAUZEERD' : _disciplineLabel(store.sessionTitle),
                    style: t.label.copyWith(color: paused ? k.warningInk : k.accent, fontWeight: FontWeight.w700, letterSpacing: 0.9),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Ronde ', style: t.title.copyWith(color: k.textSecondary)),
                TextSpan(text: '${timer.round}', style: t.headline.copyWith(fontSize: 26, fontWeight: FontWeight.w800)),
                TextSpan(text: ' / $total', style: t.title.copyWith(color: k.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          RoundSegments(
            total: total,
            done: timer.round - 1,
            currentProgress: timer.phaseProgress(store.now()),
          ),
          const SizedBox(height: 8),
          // De klok: tik = pauze/hervat.
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
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: paused ? k.warningTint : k.well,
              borderRadius: BorderRadius.circular(KRadius.full),
              border: Border.all(color: paused ? k.warningTint : k.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  paused ? Icons.touch_app : (last ? Icons.flag_rounded : Icons.timelapse),
                  size: 16,
                  color: paused ? k.warningInk : k.accent,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    paused
                        ? 'Gepauzeerd • tik de tijd om te hervatten'
                        : last
                        ? 'Laatste ronde • daarna afronden'
                        : 'Rust: ${_restLabel(timer.config.restSeconds)} min hierna',
                    style: t.bodyStrong.copyWith(fontSize: 13, color: paused ? k.warningInk : k.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          PhaseBar(value: timer.phaseProgress(store.now())),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RoundCircle(
                icon: Icons.stop_rounded,
                label: 'Stop',
                semantics: 'Sessie stoppen',
                iconColor: k.dangerInk,
                onTap: () => finishSessionFlow(context, natural: false),
              ),
              const SizedBox(width: 24),
              _RoundCircle(
                icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                label: paused ? 'Hervat' : 'Pauze',
                semantics: paused ? 'Timer hervatten' : 'Timer pauzeren',
                size: 88,
                filled: true,
                onTap: store.toggleSparringTimer,
              ),
              const SizedBox(width: 24),
              _RoundCircle(
                icon: last ? Icons.flag_rounded : Icons.skip_next_rounded,
                label: last ? 'Afronden' : 'Volgende',
                semantics: last ? 'Laatste ronde afronden' : 'Naar de rust',
                onTap: store.advanceToRestPhase,
              ),
            ],
          ),
        ],
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
  const RoundSegments({super.key, required this.total, required this.done, this.currentProgress = 0, this.nextHighlighted = false});

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

class _RoundCircle extends StatelessWidget {
  const _RoundCircle({
    required this.icon,
    required this.label,
    required this.semantics,
    required this.onTap,
    this.size = 64,
    this.filled = false,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final String semantics;
  final VoidCallback onTap;
  final double size;
  final bool filled;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      label: semantics,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 88,
            child: Center(
              child: Material(
                color: filled ? k.primary : k.well,
                shape: CircleBorder(side: filled ? BorderSide.none : BorderSide(color: k.border)),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onTap();
                  },
                  child: SizedBox(
                    width: size,
                    height: size,
                    child: Icon(icon, size: size * 0.45, color: filled ? k.onPrimary : (iconColor ?? k.text)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: context.t.caption.copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- techniek focus

/// "TECHNIEK FOCUS DEZE SESSIE": per techniek drie grote mat-tellers.
/// Tik = +1, lang indrukken = −1. Ook bruikbaar in de rust.
class TechniqueFocusCard extends StatelessWidget {
  const TechniqueFocusCard({super.key});

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final store = KineticScope.of(context);
    final list = store.sessionTechniques;
    final timer = store.sparring;
    final total = timer?.config.rounds ?? 0;
    // Tijdens de ronde en in de rust: wisselen geldt vanaf de volgende ronde.
    final nextRound = (timer?.round ?? 0) + 1;
    final upcoming = timer == null || nextRound > total
        ? null
        : nextRound == total
        ? 'Voor R$total'
        : 'Voor R$nextRound–R$total';
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: Icons.track_changes, size: 36, filled: true),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TECHNIEK FOCUS DEZE SESSIE',
                      style: t.label.copyWith(color: k.accent, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text('Direct aantikken vanaf de mat of in rust', style: t.caption, maxLines: 2),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              KPill('${list.length} actief', tone: KTone.primary),
            ],
          ),
          const SizedBox(height: 14),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                'Nog geen focus-technieken voor deze sessie. Kies hieronder wat je wilt tellen.',
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
          if (list.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Tik = +1 • lang indrukken = −1',
              textAlign: TextAlign.center,
              style: t.caption.copyWith(color: k.textMuted),
            ),
            const SizedBox(height: 12),
          ],
          KWell(
            onTap: () => showSessionTechniquePicker(context),
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz, color: k.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Focus wisselen of toevoegen', style: t.bodyStrong),
                        if (upcoming != null) Text(upcoming, style: t.caption),
                      ],
                    ),
                  ),
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
    final sub = [technique.learningGoal, technique.transition].map((s) => s.trim()).firstWhere(
      (s) => s.isNotEmpty,
      orElse: () => technique.group.description,
    );
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
                  Text(technique.name, style: t.title.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(sub, style: t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 8),
            KPill(technique.group.label, tone: striking ? KTone.primary : KTone.purple, dense: true),
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
                        Text(label, style: t.caption.copyWith(color: labelColor, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text('${count}x', style: t.metricMd.copyWith(fontWeight: FontWeight.w800, color: valueColor)),
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
            KWell(child: Text('Voeg eerst technieken toe in de Technieken Vault.', style: t.body.copyWith(color: k.textSecondary))),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Eyebrow(g.label),
            ),
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

// ------------------------------------------------------------- snelle carbs

class _FastCarbCard extends StatelessWidget {
  const _FastCarbCard();

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = context.t;
    final g = KineticScope.of(context).fastCarbGrams;
    return Semantics(
      button: true,
      label: '$g gram snelle koolhydraten loggen',
      excludeSemantics: true,
      child: Material(
        color: k.primary,
        borderRadius: BorderRadius.circular(KRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.mediumImpact();
            logMatIntervention(context, dextrose: true);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: k.onPrimary.withValues(alpha: 0.14), shape: BoxShape.circle),
                    child: Icon(Icons.medication_liquid, color: k.onPrimary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('+${g}g Snelle Koolhydraten', style: t.title.copyWith(color: k.onPrimary, fontWeight: FontWeight.w700)),
                        Text(
                          '1 tik: dextrose gel direct loggen',
                          style: t.caption.copyWith(color: k.onPrimary.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.add_circle, color: k.onPrimary, size: 28),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- mat-knoppen

/// Grote bedieningsknop voor de mat (icoon boven een kort label in
/// hoofdletters), minstens 64px hoog.
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

// ------------------------------------------------------------- spraakmemo

/// "Snelle Spraaknotitie Coach (REC)". Met [compact] als mat-knop
/// ("FOCUS NOTITIE") voor de onderbalk.
class VoiceMemoButton extends StatefulWidget {
  const VoiceMemoButton({super.key, this.compact = false});
  final bool compact;

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
    final k = context.k;
    final store = KineticScope.of(context);
    final rec = _recorder.isRecording;
    final secs = rec ? DateTime.now().difference(_recorder.startedAt!).inSeconds : 0;
    final n = store.voiceMemos.length;
    if (widget.compact) {
      return MatControlButton(
        label: rec ? 'REC ${mmss(secs)}' : (n == 0 ? 'Focus notitie' : 'Notitie • $n'),
        icon: rec ? Icons.stop_circle : Icons.mic_rounded,
        style: rec ? KButtonStyle.critical : KButtonStyle.secondary,
        onPressed: _toggle,
      );
    }
    return BigButton(
      label: rec ? 'REC ${mmss(secs)} • tik om te stoppen' : 'Snelle Spraaknotitie Coach (REC)${n == 0 ? '' : ' • $n'}',
      icon: rec ? Icons.stop_circle : Icons.mic,
      height: 64,
      style: rec ? KButtonStyle.critical : KButtonStyle.secondary,
      color: rec ? null : k.danger,
      outlined: !rec,
      foreground: rec ? null : k.text,
      onPressed: _toggle,
    );
  }
}

// ------------------------------------------------------------- acties

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
    builder: (ctx) {
      final k = ctx.k;
      final tt = ctx.t;
      return AlertDialog(
        title: Text(natural ? 'Sessie voltooid 🥋' : 'Sessie afronden?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${t.round} van ${t.config.rounds} rondes • ${durationLabel(minutes)}', style: tt.body),
            if (totals.$2 > 0) Text('${totals.$1} geslaagd van ${totals.$2} acties', style: tt.body),
            if (glucose.isNotEmpty)
              Text(
                'Glucose ${glucose.first.mmol.toStringAsFixed(1)} → ${glucose.last.mmol.toStringAsFixed(1)} mmol/L',
                style: tt.bodyStrong.copyWith(color: toneColors(k, glucoseZoneTone(glucose.last.mmol)).$2),
              ),
            if (store.voiceMemos.isNotEmpty) Text('${store.voiceMemos.length} spraakmemo(s) op dit toestel', style: tt.caption),
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
        title: const Text('Sessie verwerpen?'),
        content: const Text('Tellers en glucoseverloop van deze sessie worden niet opgeslagen.'),
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
