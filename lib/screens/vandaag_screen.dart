// vandaag_screen.dart: dashboard: fight-prep-banner, Dexcom G7-tijdlijn,
// Start Live Sparring, snelle 1-tik-knoppen en de dagelijkse output.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/meal_impact.dart';
import '../core/sparring_timer.dart';
import '../models/kinetic_profile.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/glucose_timeline.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/sheets.dart';

class VandaagScreen extends StatelessWidget {
  const VandaagScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final now = store.now();
    final r = store.reading;
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: KColor.teal,
        backgroundColor: KColor.surfaceContainer,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _Header(now: now),
            const SizedBox(height: 16),
            if (store.hypoAlert && r != null)
              HypoBanner(
                reading: r,
                onDextrose: () => _logDextrose(context),
              ),
            const _FightPrepBanner(),
            const SizedBox(height: 12),
            const _DexcomCard(),
            const SizedBox(height: 12),
            const _SparringCta(),
            const SizedBox(height: 12),
            const _QuickButtons(),
            const SizedBox(height: 20),
            const SectionTitle('Dagelijkse output'),
            const _DailyOutput(),
          ],
        ),
      ),
    );
  }

  static Future<void> _logDextrose(BuildContext context) async {
    final store = KineticScope.read(context);
    final e = await store.logFood(description: 'Dextrose (hypo)', carbs: 15, context: MealContext.acute);
    if (!context.mounted) return;
    showToast(context, e == null ? 'Opslaan mislukt' : '+15g dextrose gelogd. Meet over 15 min opnieuw.', error: e == null);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now});
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final h = now.hour;
    final greeting = h < 6 ? 'Goedenacht' : h < 12 ? 'Goedemorgen' : h < 18 ? 'Goedemiddag' : 'Goedenavond';
    final name = (store.profile?.username.trim().isNotEmpty ?? false)
        ? store.profile!.username.trim()
        : (store.email ?? '').split('@').first;
    final synced = store.syncError == null;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Eyebrow(shortDate(now)),
              const SizedBox(height: 4),
              Text(name.isEmpty ? greeting : '$greeting, $name', style: KText.display, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        IconButton.filledTonal(
          tooltip: 'Instellingen & data export',
          style: IconButton.styleFrom(backgroundColor: KColor.surfaceContainer, minimumSize: const Size(48, 48)),
          onPressed: () => Navigator.of(context).pushNamed('/telemetrie-export'),
          icon: Badge(
            backgroundColor: synced ? KColor.success : KColor.warning,
            smallSize: 8,
            child: const Icon(Icons.tune, color: KColor.text),
          ),
        ),
      ],
    );
  }
}

class _FightPrepBanner extends StatelessWidget {
  const _FightPrepBanner();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final comp = store.nextCompetition;
    final weight = store.currentWeightKg;
    final target = store.targetWeightKg;
    final days = comp == null ? null : daysUntil(comp.startsAt, now: store.now());
    String weightLine;
    if (weight == null) {
      weightLine = 'Nog geen weging';
    } else if (target == null) {
      weightLine = '${dec1(weight)} kg';
    } else {
      final d = target - weight;
      final sign = d > 0 ? '+' : '';
      weightLine = d.abs() < 0.05 ? '${dec1(weight)} kg (op gewicht)' : '${dec1(weight)} kg ($sign${dec1(d)} kg target)';
    }
    final title = comp == null
        ? 'Geen wedstrijd gepland'
        : '${comp.name} • ${days == 0 ? 'Vandaag!' : 'Nog $days ${days == 1 ? 'dag' : 'dagen'}'}';
    return KCard(
      onTap: () => Navigator.of(context).pushNamed('/competitions'),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [KColor.purple.withValues(alpha: 0.22), KColor.surfaceContainer],
      ),
      borderColor: KColor.purple.withValues(alpha: 0.35),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(comp == null ? 'Fight prep' : '${comp.disciplineLabel} • fight prep', color: KColor.purple, icon: Icons.emoji_events_outlined),
                const SizedBox(height: 8),
                Text(title, style: KText.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(weightLine, style: KText.caption.copyWith(color: KColor.text)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: KColor.purple,
              foregroundColor: KColor.text,
              minimumSize: const Size(0, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.md)),
            ),
            onPressed: () => Navigator.of(context).pushNamed('/competitions'),
            child: const Text('Inwegen & Prep ⚖️', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _DexcomCard extends StatelessWidget {
  const _DexcomCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final r = store.reading;
    final now = store.now();
    final source = store.profile?.glucoseSource ?? GlucoseSource.dexcomShare;
    final age = r == null ? null : now.difference(r.at).inMinutes;
    final message = store.glucose?.message;
    return KCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Eyebrow(
                  source == GlucoseSource.finger ? 'Glucose • vingerprik' : 'Dexcom G7 • 12u telemetrie',
                  color: KColor.tealLight,
                  icon: Icons.sensors,
                ),
              ),
              if (age != null)
                Text(age <= 0 ? 'zojuist' : '$age min geleden', style: KText.caption.copyWith(color: r!.isStale ? KColor.warning : KColor.textMuted)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: GlucoseReadout(reading: r, size: 40)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('IOB', style: KText.eyebrow),
                  const SizedBox(height: 2),
                  Text('${store.iob.toStringAsFixed(1)} E', style: KText.metricSmall.copyWith(color: KColor.blue)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (r != null)
            KBadge(
              r.isStale
                  ? 'Meting is oud: sensorverbinding controleren'
                  : '${trendLabel(r.trend)} • ${_zoneText(r.mmol)}',
              color: r.isStale ? KColor.warning : glucoseColor(r.mmol),
            )
          else if (message != null)
            Text(message, style: KText.caption.copyWith(color: KColor.warning)),
          const SizedBox(height: 10),
          GlucoseTimeline(points: store.glucoseHistory, meals: store.foodEntries, now: now),
        ],
      ),
    );
  }

  static String _zoneText(double mmol) => switch (zoneFor(mmol)) {
    GlucoseZone.hypo => 'Hypo < ${hypoBelow.toStringAsFixed(1)}',
    GlucoseZone.low => 'Laag',
    GlucoseZone.inTarget => 'In doelbereik ${targetLow.toStringAsFixed(1)} - ${targetHigh.toStringAsFixed(1)}',
    GlucoseZone.high => 'Boven doelbereik',
  };
}

class _SparringCta extends StatelessWidget {
  const _SparringCta();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final active = store.isSparringActive;
    final t = store.sparring;
    final focus = store.focusTechniques.length;
    final clearance = store.clearanceForNextRound();
    return KCard(
      glow: true,
      onTap: () {
        HapticFeedback.heavyImpact();
        openLiveSession(context);
      },
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [KColor.teal, Color(0xFF0F766E)],
      ),
      borderColor: KColor.tealLight.withValues(alpha: 0.5),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: KColor.bg.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(KRadius.lg),
            ),
            child: Icon(active ? Icons.play_circle_fill : Icons.sports_mma, color: KColor.text, size: 32),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active ? 'Terug naar de mat' : 'Start Live Sparring',
                  style: KText.title.copyWith(color: KColor.text, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  active
                      ? '${t!.phase == SparringPhase.rest ? 'Rust' : 'Ronde'} ${t.round}/${t.config.rounds} • ${mmss(store.roundSecondsRemaining)}'
                      : '${store.sparringConfig.summary} • $focus focus-${focus == 1 ? 'techniek' : 'technieken'}',
                  style: KText.caption.copyWith(color: KColor.text.withValues(alpha: 0.85)),
                ),
                if (!active && clearance.level != ClearanceLevel.safe) ...[
                  const SizedBox(height: 6),
                  Text('⚠ ${clearance.title}', style: KText.caption.copyWith(color: KColor.bg, fontWeight: FontWeight.w800)),
                ],
              ],
            ),
          ),
          if (!active)
            IconButton(
              tooltip: 'Rondes instellen',
              onPressed: () => showSparringConfigSheet(context),
              icon: const Icon(Icons.tune, color: KColor.text),
            ),
        ],
      ),
    );
  }
}

class _QuickButtons extends StatelessWidget {
  const _QuickButtons();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final liters = store.waterMlToday / 1000;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: KCard(
              onTap: () async {
                HapticFeedback.mediumImpact();
                final before = store.waterMlToday;
                await store.addWater(250);
                if (!context.mounted) return;
                showToast(
                  context,
                  'Vocht ${(before / 1000).toStringAsFixed(2)}L ➔ ${(store.waterMlToday / 1000).toStringAsFixed(2)}L',
                  actionLabel: 'Ongedaan',
                  onAction: () => store.addWater(-250),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Vocht', color: KColor.blue, icon: Icons.water_drop),
                  const SizedBox(height: 10),
                  Text('${liters.toStringAsFixed(liters * 100 % 10 == 0 ? 1 : 2)}L', style: KText.metric),
                  const SizedBox(height: 6),
                  Text('Tik voor +250ml', style: KText.caption.copyWith(color: KColor.blue, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: KCard(
              onTap: store.requestMealSheet,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Eten & carbs', color: KColor.warning, icon: Icons.restaurant),
                  const SizedBox(height: 10),
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(text: grams(store.carbsToday), style: KText.metric),
                      TextSpan(text: ' / ${grams(store.carbsTarget)}g', style: KText.caption),
                    ]),
                  ),
                  const SizedBox(height: 6),
                  Text('Maaltijd toevoegen', style: KText.caption.copyWith(color: KColor.warning, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyOutput extends StatelessWidget {
  const _DailyOutput();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final mat = store.matMinutesToday;
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.55,
      children: [
        MetricTile(
          label: 'Verbranding',
          value: mat == 0 ? '0 kcal' : '${store.kcalToday} kcal',
          sub: 'schatting uit mat-tijd',
          icon: Icons.local_fire_department,
          accent: KColor.warning,
        ),
        MetricTile(
          label: 'Tijd op mat',
          value: '$mat min',
          sub: store.isSparringActive ? 'sessie loopt' : 'vandaag',
          icon: Icons.timer_outlined,
        ),
        const MetricTile(
          label: 'HRV herstel',
          value: '—',
          sub: 'Koppel Polar H10',
          icon: Icons.monitor_heart_outlined,
          accent: KColor.blue,
          subColor: KColor.textMuted,
        ),
        const MetricTile(
          label: 'Slaap',
          value: '—',
          sub: 'Geen slaapbron gekoppeld',
          icon: Icons.bedtime_outlined,
          accent: KColor.purple,
          subColor: KColor.textMuted,
        ),
      ],
    );
  }
}
