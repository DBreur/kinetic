// vandaag_screen.dart: "Vandaag's protocol" (kinetic_today_1/2): fight-prep-
// banner, Dexcom G7-kaart, glucosetrend met tijdvenster, de eerstvolgende
// training met pre-training check, pre-sparring advies, snelle 1-tik-knoppen
// en de dagelijkse output.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/meal_impact.dart';
import '../core/sparring_timer.dart';
import '../models/glucose.dart';
import '../models/kinetic_profile.dart';
import '../models/planned_training.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/glucose_timeline.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/sheets.dart';
import '../widgets/start_training_sheet.dart';

class VandaagScreen extends StatelessWidget {
  const VandaagScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final r = store.reading;
    return RefreshIndicator(
      color: k.primary,
      backgroundColor: k.surface,
      onRefresh: store.refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pagePadding(context, top: 16),
        children: [
          const _Header(),
          const SizedBox(height: 16),
          if (store.hypoAlert && r != null)
            HypoBanner(
              reading: r,
              grams: store.fastCarbGrams,
              onDextrose: () => _logFastCarbs(context),
            ),
          const _FightPrepBanner(),
          const SizedBox(height: 16),
          const _DexcomCard(),
          const SizedBox(height: 16),
          const _TrendCard(),
          const SizedBox(height: 16),
          const _TrainingCard(),
          const SizedBox(height: 16),
          const _AdviceCard(),
          const SizedBox(height: 16),
          const _QuickButtons(),
          const SizedBox(height: 16),
          const _DailyOutput(),
        ],
      ),
    );
  }

  static Future<void> _logFastCarbs(BuildContext context) async {
    final store = KineticScope.read(context);
    final g = store.fastCarbGrams;
    final e = await store.logFood(description: 'Dextrose (hypo)', carbs: g.toDouble(), context: MealContext.acute);
    if (!context.mounted) return;
    showToast(
      context,
      e == null ? 'Opslaan mislukt' : '+${g}g dextrose gelogd. Meet over 15 min opnieuw.',
      error: e == null,
    );
  }
}

// ------------------------------------------------------------------ header

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final h = store.now().hour;
    final greeting = h < 6
        ? 'Goedenacht'
        : h < 12
        ? 'Goedemorgen'
        : h < 18
        ? 'Goedemiddag'
        : 'Goedenavond';
    final name = store.displayName;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow("Vandaag's protocol"),
              const SizedBox(height: 4),
              Text(
                name.isEmpty ? greeting : '$greeting, $name',
                style: context.t.headline,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        const KPill('T1D • Sambo', tone: KTone.primary, dot: true),
      ],
    );
  }
}

// --------------------------------------------------------------- fight prep

class _FightPrepBanner extends StatelessWidget {
  const _FightPrepBanner();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final comp = store.nextCompetition;
    final weight = store.currentWeightKg;
    final target = store.targetWeightKg;
    final days = comp == null ? null : daysUntil(comp.startsAt, now: store.now());
    final title = comp == null
        ? 'Geen wedstrijd gepland'
        : '${comp.name} • ${days == 0 ? 'Vandaag!' : 'Nog $days ${days == 1 ? 'dag' : 'dagen'}'}';
    String? delta;
    if (weight != null && target != null) {
      final d = target - weight;
      delta = d.abs() < 0.05 ? ' (op gewicht)' : ' (${d > 0 ? '+' : ''}${dec1(d)} kg target)';
    }
    void open() => Navigator.of(context).pushNamed('/competitions');
    return KCard(
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: Icons.emoji_events_outlined, color: k.purple, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(comp == null ? 'Fight prep' : '${comp.disciplineLabel} • fight prep'),
                    const SizedBox(height: 2),
                    Text(title, style: context.t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: weight == null ? 'Nog geen weging' : '${dec1(weight)} kg',
                            style: context.t.bodyStrong,
                          ),
                          if (delta != null) TextSpan(text: delta, style: context.t.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: k.textMuted),
            ],
          ),
          const SizedBox(height: 12),
          BigButton(
            label: 'Inwegen & Prep ⚖️',
            style: KButtonStyle.secondary,
            height: 48,
            onPressed: open,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ dexcom

class _DexcomCard extends StatelessWidget {
  const _DexcomCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final r = store.reading;
    final now = store.now();
    final finger = store.profile?.glucoseSource == GlucoseSource.finger;
    final age = r == null ? null : now.difference(r.at).inMinutes;
    // Bij vingerprik is een oude meting normaal (je meet niet elke 15 min).
    final stale = !finger && age != null && age >= 15;
    final message = store.glucose?.message;
    return KCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconTile(icon: finger ? Icons.water_drop_outlined : Icons.sensors, size: 32, color: k.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(finger ? 'Vingerprik' : 'Dexcom G7 Actief', style: context.t.bodyStrong),
              ),
              if (age != null)
                Text(
                  age <= 0 ? 'Zojuist bijgewerkt' : '$age min geleden',
                  style: context.t.caption.copyWith(color: stale ? k.warningInk : null),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: GlucoseReadout(reading: r, size: 48, showArrow: false),
                    ),
                    const SizedBox(height: 4),
                    Text('IOB ${store.iob.toStringAsFixed(1)} E actief', style: context.t.caption),
                  ],
                ),
              ),
              if (r != null) ...[
                const SizedBox(width: 12),
                KWell(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        trendArrow(r.trend),
                        style: context.t.title.copyWith(color: isFalling(r.trend) ? k.warningInk : k.accent, height: 1),
                      ),
                      const SizedBox(width: 8),
                      Text(trendLabel(r.trend), style: context.t.bodyStrong),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),
          if (r != null)
            _RangeWell(reading: r, stale: stale)
          else ...[
            Text(
              message ?? 'Nog geen glucosewaarde.',
              style: context.t.caption.copyWith(color: k.warningInk),
            ),
            const SizedBox(height: 10),
            BigButton(
              label: 'Vingerprik invoeren',
              icon: Icons.water_drop_outlined,
              style: KButtonStyle.secondary,
              height: 48,
              onPressed: () => showFingerstickSheet(context),
            ),
          ],
        ],
      ),
    );
  }
}

/// "✓ In bereik  •  Doel: 4.2 – 9.0 mmol/L", per zone.
class _RangeWell extends StatelessWidget {
  const _RangeWell({required this.reading, required this.stale});
  final GlucoseReading reading;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final range = '${dec1(targetLow)} – ${dec1(targetHigh)} mmol/L';
    final (IconData icon, String label, KTone tone, String detail) = stale
        ? (Icons.schedule, 'Meting is oud', KTone.warning, 'Controleer de sensor')
        : switch (zoneFor(reading.mmol)) {
            GlucoseZone.inTarget => (Icons.check, 'In bereik', KTone.success, 'Doel: $range'),
            GlucoseZone.hypo => (Icons.priority_high, 'Hypo', KTone.danger, 'Onder ${dec1(hypoBelow)} mmol/L'),
            GlucoseZone.low => (Icons.south, 'Laag', KTone.warning, 'Doel: $range'),
            GlucoseZone.high => (Icons.north, 'Hoog', KTone.warning, 'Doel: $range'),
          };
    final (_, fg) = toneColors(k, tone);
    final solid = switch (tone) {
      KTone.success => k.success,
      KTone.danger => k.danger,
      _ => k.warning,
    };
    return KWell(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: solid, shape: BoxShape.circle),
            child: Icon(icon, size: 16, color: k.surface),
          ),
          const SizedBox(width: 10),
          Text(label, style: context.t.bodyStrong.copyWith(color: fg)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              detail,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.t.caption,
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------- trend

class _TrendCard extends StatefulWidget {
  const _TrendCard();

  @override
  State<_TrendCard> createState() => _TrendCardState();
}

class _TrendCardState extends State<_TrendCard> {
  int _hours = 6;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final now = store.now();
    final from = now.subtract(Duration(hours: _hours));
    final window = store.glucoseHistory.where((g) => g.at.isAfter(from)).map((g) => g.mmol).toList();
    final avg = window.isEmpty ? null : window.reduce((a, b) => a + b) / window.length;
    final tir = timeInRange(window);
    return KCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.ssid_chart, color: k.accent, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text('Glucosetrend', style: context.t.title)),
              if (avg != null) ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: zoneInk(k, avg), shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
                Text('Gem. ${dec1(avg)} mmol/L', style: context.t.caption),
              ],
            ],
          ),
          const SizedBox(height: 14),
          KSegmented<int>(
            options: const [(3, '3u'), (6, '6u'), (12, '12u'), (24, '24u')],
            value: _hours,
            onChanged: (h) => setState(() => _hours = h),
          ),
          const SizedBox(height: 12),
          GlucoseTimeline(
            points: store.glucoseHistory,
            meals: store.foodEntries,
            now: now,
            windowHours: _hours,
            height: 190,
          ),
          if (tir != null) ...[
            const SizedBox(height: 8),
            Text(
              '${(tir * 100).round()}% in doelbereik (laatste $_hours uur) • tik op de lijn voor details',
              style: context.t.caption,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- training

class _TrainingCard extends StatefulWidget {
  const _TrainingCard();

  @override
  State<_TrainingCard> createState() => _TrainingCardState();
}

class _TrainingCardState extends State<_TrainingCard> {
  bool? _expanded;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final p = store.nextPlannedTraining;
    final active = store.isSparringActive;
    final cfg = store.sparringConfig;
    final clearance = store.clearanceForNextRound();
    final expanded = _expanded ?? clearance.level != ClearanceLevel.safe;
    final (_, toneFg) = toneColors(k, clearanceTone(clearance.level));
    final t = store.sparring;

    final header = p == null
        ? Row(
            children: [
              IconTile(icon: Icons.sports_kabaddi, size: 56, color: k.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Geen training gepland', style: context.t.title),
                    const SizedBox(height: 2),
                    Text('Start een vrije training of plan er een in je agenda.', style: context.t.caption),
                  ],
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon: _kindIcon(p.kind), size: 56, color: k.primary, filled: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        KPill(p.kind.label, tone: KTone.neutral, dense: true, uppercase: true),
                        if (p.durationMinutes != null) Text('${p.durationMinutes} min', style: context.t.caption),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(p.displayTitle, style: context.t.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (p.location.trim().isNotEmpty)
                      Text(p.location.trim(), style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              KPill(_timeLabel(p.startsAt, store.now()), tone: KTone.primary),
            ],
          );

    return KCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          header,
          const SizedBox(height: 16),
          KWell(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                Icon(active ? Icons.sports_mma : Icons.timer_outlined, color: k.accent, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    active && t != null
                        ? '${store.sessionTitle} • ${t.phase == SparringPhase.rest ? 'Rust' : 'Ronde'} ${t.round}/${t.config.rounds}'
                        : '${configShort(cfg)} Live Sparring',
                    style: context.t.body.copyWith(color: k.text),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  active ? mmss(store.roundSecondsRemaining) : '${restClock(cfg)} rust',
                  style: context.t.caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Pre-Training Check: status meteen zichtbaar, uitleg uitklapbaar.
          Material(
            color: k.primaryTint,
            borderRadius: BorderRadius.circular(KRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !expanded);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Pre-Training Check', style: context.t.bodyStrong.copyWith(color: k.accent)),
                          ),
                          KPill(
                            clearanceShort(clearance.level),
                            tone: clearanceTone(clearance.level),
                            icon: clearanceIcon(clearance.level),
                            dense: true,
                          ),
                          const SizedBox(width: 6),
                          Icon(expanded ? Icons.expand_less : Icons.expand_more, color: k.accent),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: expanded
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8, right: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(clearance.title, style: context.t.bodyStrong.copyWith(color: toneFg)),
                                  const SizedBox(height: 2),
                                  Text(clearance.detail, style: context.t.caption.copyWith(color: k.text)),
                                ],
                              ),
                            )
                          : const SizedBox(width: double.infinity),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (active)
            BigButton(
              label: 'Terug naar de mat',
              icon: Icons.sports_mma,
              height: 56,
              onPressed: () {
                HapticFeedback.heavyImpact();
                openLiveSession(context);
              },
            )
          else
            BigButton(
              label: 'Training starten',
              icon: Icons.play_arrow_rounded,
              height: 56,
              onPressed: () => showStartTrainingSheet(context, planned: p),
            ),
        ],
      ),
    );
  }

  static IconData _kindIcon(TrainingKind kind) => switch (kind) {
    TrainingKind.kracht => Icons.fitness_center,
    TrainingKind.overig => Icons.sports_martial_arts,
    _ => Icons.sports_kabaddi,
  };

  /// "18:30", of "morgen 18:30" / "do 18:30" als het niet vandaag is.
  static String _timeLabel(DateTime at, DateTime now) {
    final days = daysUntil(at, now: now);
    if (days == 0) return hhmm(at);
    if (days == 1) return 'morgen ${hhmm(at)}';
    return '${shortDate(at).split(' ').first} ${hhmm(at)}';
  }
}

// ------------------------------------------------------------------ advies

class _AdviceCard extends StatelessWidget {
  const _AdviceCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final (title, text, tone) = _advice(store.clearanceForNextRound(), store.reading, store.iob, store.fastCarbGrams);
    final (_, fg) = toneColors(k, tone);
    return KCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconTile(icon: tone == KTone.primary ? Icons.bolt : Icons.warning_amber_rounded, size: 44, color: fg),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.bodyStrong),
                const SizedBox(height: 4),
                Text(text, style: context.t.body.copyWith(color: k.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Tip vóór de mat, afgeleid uit de clearance, de trend en de IOB.
  static (String, String, KTone) _advice(MatClearance c, GlucoseReading? r, double iob, int fastCarbs) {
    switch (c.level) {
      case ClearanceLevel.danger:
        return ('Pre-sparring alarm', 'Niet de mat op. ${c.detail}', KTone.danger);
      case ClearanceLevel.unknown:
        return ('Pre-sparring check', '${c.title}. ${c.detail}', KTone.warning);
      case ClearanceLevel.caution:
        return ('Pre-sparring let op', '${c.title}: ${c.detail}', KTone.warning);
      case ClearanceLevel.safe:
        break;
    }
    if (r != null && isFalling(r.trend)) {
      return (
        'Pre-sparring advies',
        'Je glucose daalt (${trendLabel(r.trend).toLowerCase()}). Neem ${fastCarbs}g snelle koolhydraten 15-30 min vóór de eerste ronde.',
        KTone.warning,
      );
    }
    if (iob >= 1.0) {
      return (
        'Pre-sparring advies',
        'Nog ${iob.toStringAsFixed(1)} E insuline actief: grotere kans op een dip tijdens het sparren. Houd dextrose binnen handbereik.',
        KTone.warning,
      );
    }
    if (r != null && (r.trend == Trend.up || r.trend == Trend.slightUp)) {
      return (
        'Pre-sparring advies',
        'Stijgende trend. Combat-rondes geven adrenaline en laten je glucose eerst verder stijgen: corrigeer vóór de training voorzichtig.',
        KTone.primary,
      );
    }
    return (
      'Pre-sparring advies',
      'Combat-rondes verhogen de adrenaline. Verwacht eerst een stijging door glucose uit de lever en daarna een snelle daling rond ronde 4.',
      KTone.primary,
    );
  }
}

// ------------------------------------------------------------ snelle knoppen

class _QuickButtons extends StatelessWidget {
  const _QuickButtons();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
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
                  'Vocht ${(before / 1000).toStringAsFixed(2)}L → ${(store.waterMlToday / 1000).toStringAsFixed(2)}L',
                  actionLabel: 'Ongedaan',
                  onAction: () => store.addWater(-250),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconTile(icon: Icons.water_drop_outlined, size: 32, color: k.blue),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Vocht', style: context.t.bodyStrong)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${liters.toStringAsFixed(store.waterMlToday % 100 == 0 ? 1 : 2)}L',
                    style: context.t.metricMd,
                  ),
                  const SizedBox(height: 4),
                  Text('Tik voor +250ml', style: context.t.caption.copyWith(color: k.blue, fontWeight: FontWeight.w600)),
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
                  Row(
                    children: [
                      IconTile(icon: Icons.restaurant_outlined, size: 32, color: k.warningInk),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Eten & carbs', style: context.t.bodyStrong)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: grams(store.carbsToday), style: context.t.metricMd),
                        TextSpan(text: ' / ${grams(store.carbsTarget)}g', style: context.t.unit),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Maaltijd toevoegen',
                    style: context.t.caption.copyWith(color: k.warningInk, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------- dagelijkse output

class _DailyOutput extends StatelessWidget {
  const _DailyOutput();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final mat = store.matMinutesToday;
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: a), const SizedBox(width: 8), Expanded(child: b)],
      ),
    );
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Dagelijkse output', style: context.t.title)),
              Text(shortDate(store.now()), style: context.t.caption),
            ],
          ),
          const SizedBox(height: 12),
          pair(
            MetricTile(
              inWell: true,
              label: 'Verbranding',
              value: '${store.kcalToday} kcal',
              sub: 'Schatting uit mat-tijd',
              icon: Icons.local_fire_department_outlined,
              accent: k.warningInk,
            ),
            MetricTile(
              inWell: true,
              label: 'Tijd op mat',
              value: '$mat min',
              sub: store.isSparringActive ? 'Sessie loopt' : 'Vandaag',
              icon: Icons.timer_outlined,
            ),
          ),
          const SizedBox(height: 8),
          pair(
            MetricTile(
              inWell: true,
              label: 'HRV herstel',
              value: '—',
              sub: 'Koppel Polar H10',
              icon: Icons.monitor_heart_outlined,
              accent: k.blue,
              subColor: k.textMuted,
            ),
            MetricTile(
              inWell: true,
              label: 'Slaap',
              value: '—',
              sub: 'Geen slaapbron',
              icon: Icons.bedtime_outlined,
              accent: k.purple,
              subColor: k.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
