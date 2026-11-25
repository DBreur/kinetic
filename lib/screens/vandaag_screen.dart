// vandaag_screen.dart: Vandaag (kinetic_vandaag_interactief_dark_mode):
// fight-prep-banner, continu telemetrie (glucose, IOB en trend in één
// kaart), de mat-modus-kaart om een training te starten, snelle tegels
// (eten, vocht), de geplande training met pre-training check, advies en de
// dagelijkse output.

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
        padding: pagePadding(context, top: 8),
        children: [
          if (store.hypoAlert && r != null)
            HypoBanner(
              reading: r,
              grams: store.fastCarbGrams,
              onDextrose: () => _logFastCarbs(context),
            ),
          const _FightPrepBanner(),
          const SizedBox(height: 16),
          const _TelemetryCard(),
          const SizedBox(height: 16),
          const _MatModeCard(),
          const SizedBox(height: 12),
          const _QuickButtons(),
          const SizedBox(height: 16),
          const _TrainingCard(),
          const SizedBox(height: 16),
          const _AdviceCard(),
          const SizedBox(height: 24),
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
    String? delta;
    var deltaColor = k.successInk;
    if (weight != null && target != null) {
      // Minimumklasse: strikt boven de grens, dus dezelfde +0.1 als op Wedstrijden.
      final d = comp?.gainNeededKg(weight) ?? (target - weight);
      if (d.abs() < 0.05) {
        delta = 'op gewicht';
      } else {
        delta = '${d > 0 ? '+' : ''}${dec1(d)} kg target';
        if (d.abs() > 3) deltaColor = k.warningInk;
      }
    }
    void open() => Navigator.of(context).pushNamed('/competitions');
    return KCard(
      onTap: open,
      color: k.isDark ? k.well : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 9, height: 9, decoration: BoxDecoration(color: k.accent, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (comp?.name ?? 'Fight prep').toUpperCase(),
                  style: context.t.labelSm.copyWith(color: k.accent, letterSpacing: 0.8),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (days != null) ...[
                const SizedBox(width: 8),
                DarkPill(days == 0 ? 'Vandaag!' : 'Nog $days ${days == 1 ? 'dag' : 'dagen'}'),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(comp == null ? 'Geen wedstrijd gepland' : 'Huidig gewicht', style: context.t.caption),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: weight == null ? '--' : dec1(weight),
                              style: context.t.metricMd.copyWith(fontSize: 30),
                            ),
                            TextSpan(text: ' kg', style: context.t.unit),
                            if (delta != null)
                              TextSpan(
                                text: '   $delta',
                                style: context.t.caption.copyWith(color: deltaColor, fontWeight: FontWeight.w700),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: open,
                style: OutlinedButton.styleFrom(
                  foregroundColor: k.accent,
                  backgroundColor: k.isDark ? k.surface : null,
                  side: BorderSide(color: k.accent.withValues(alpha: 0.35)),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  textStyle: context.t.bodyStrong,
                ),
                icon: const Icon(Icons.monitor_weight_outlined, size: 18),
                label: Text(comp == null ? 'Plannen' : 'Inwegen & Prep'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- telemetrie

/// "Continu Telemetrie": waarde + trend + IOB, de laatste meting en de
/// glucosetrend (3/6/12/24 uur) in één kaart.
class _TelemetryCard extends StatefulWidget {
  const _TelemetryCard();

  @override
  State<_TelemetryCard> createState() => _TelemetryCardState();
}

class _TelemetryCardState extends State<_TelemetryCard> {
  int _hours = 3;

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
    final from = now.subtract(Duration(hours: _hours));
    final window = store.glucoseHistory.where((g) => g.at.isAfter(from)).map((g) => g.mmol).toList();
    final tir = timeInRange(window);

    final (String zoneLabel, KTone zoneTone) = r == null
        ? ('Geen meting', KTone.neutral)
        : stale
        ? ('Meting is oud', KTone.warning)
        : switch (zoneFor(r.mmol)) {
            GlucoseZone.inTarget => ('Binnen range', KTone.success),
            GlucoseZone.hypo => ('Hypo', KTone.danger),
            GlucoseZone.low => ('Laag', KTone.warning),
            GlucoseZone.high => ('Hoog', KTone.warning),
          };
    final trendColor = r == null ? k.textMuted : (isFalling(r.trend) ? k.warningInk : k.accent);

    return KCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(finger ? Icons.water_drop_outlined : Icons.ssid_chart, color: k.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  finger ? 'Glucose (vingerprik)' : 'Continu Telemetrie',
                  style: context.t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              KPill(zoneLabel, tone: zoneTone, dot: true, dense: true),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      GlucoseReadout(reading: r, size: 52, showArrow: false),
                      if (r != null) ...[
                        const SizedBox(width: 12),
                        Text(trendArrow(r.trend), style: context.t.metricMd.copyWith(color: trendColor)),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('IOB (insuline actief)', style: context.t.caption),
                  const SizedBox(height: 2),
                  Text(
                    '${store.iob.toStringAsFixed(1)} E',
                    style: context.t.subtitle.copyWith(color: k.accent, fontFeatures: const [FontFeature.tabularFigures()]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (r != null)
            KWell(
              color: k.isDark ? KineticColors.sunken : null,
              borderColor: k.border,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.schedule, size: 16, color: stale ? k.warningInk : k.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    hhmm(r.at),
                    style: context.t.caption.copyWith(color: stale ? k.warningInk : k.text, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      age == null || age <= 0 ? '• zojuist' : '• $age min',
                      style: context.t.caption.copyWith(color: stale ? k.warningInk : null),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    trendLabel(r.trend),
                    style: context.t.caption.copyWith(color: trendColor, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            )
          else ...[
            Text(
              store.glucose?.message ?? 'Nog geen glucosewaarde.',
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
          const SizedBox(height: 14),
          GlucoseTimeline(
            points: store.glucoseHistory,
            meals: store.foodEntries,
            now: now,
            windowHours: _hours,
            height: 180,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  tir == null ? 'Houd een punt ingedrukt voor details' : '${(tir * 100).round()}% in doelbereik',
                  style: context.t.caption,
                  maxLines: 2,
                ),
              ),
              const SizedBox(width: 8),
              for (final h in const [3, 6, 12, 24])
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _HourChip(hours: h, selected: _hours == h, onTap: () => setState(() => _hours = h)),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HourChip extends StatelessWidget {
  const _HourChip({required this.hours, required this.selected, required this.onTap});
  final int hours;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      selected: selected,
      button: true,
      label: 'Laatste $hours uur',
      excludeSemantics: true,
      child: Material(
        color: selected ? k.primaryTint : k.well,
        borderRadius: BorderRadius.circular(KRadius.sm),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            constraints: const BoxConstraints(minWidth: 40, minHeight: 36),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text('${hours}u', style: context.t.labelSm.copyWith(color: selected ? k.accent : k.textSecondary)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- mat-modus

/// De grote teal kaart: training starten, of terug naar de lopende training.
class _MatModeCard extends StatelessWidget {
  const _MatModeCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final tr = store.isTrainingActive ? store.training : null;
    final t = store.sparring;
    final String eyebrow;
    final String title;
    final String sub;
    if (tr != null) {
      eyebrow = t != null ? 'Mat-modus • sparren' : 'Mat-modus • live';
      title = 'Terug naar de training';
      sub = t != null
          ? 'Ronde ${t.round}/${t.config.rounds} • ${t.phase == SparringPhase.rest ? 'rust' : 'nog'} ${mmss(store.roundSecondsRemaining)}'
          : '${tr.displayTitle} • tot ${hhmm(tr.endsAt)}';
    } else {
      eyebrow = 'Mat-modus • stand-by';
      title = 'Training starten';
      sub = 'Discipline, tijden en sensor-check';
    }
    final fg = k.isDark ? k.onPrimary : Colors.white;
    return Semantics(
      button: true,
      label: title,
      excludeSemantics: true,
      child: Material(
        color: k.primary,
        borderRadius: BorderRadius.circular(KRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            HapticFeedback.heavyImpact();
            if (tr != null) {
              openLiveSession(context);
            } else {
              showStartTrainingSheet(context, planned: store.nextPlannedTraining);
            }
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 16, 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(tr != null ? Icons.sensors : Icons.sports_mma, size: 16, color: fg.withValues(alpha: 0.8)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              eyebrow.toUpperCase(),
                              style: context.t.labelSm.copyWith(color: fg.withValues(alpha: 0.8)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(title, style: context.t.headline.copyWith(color: fg)),
                      const SizedBox(height: 2),
                      Text(
                        sub,
                        style: context.t.caption.copyWith(color: fg.withValues(alpha: 0.85)),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: fg.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(tr != null ? Icons.open_in_full : Icons.play_arrow_rounded, color: fg, size: 30),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- training

/// "Geplande Mat-Tijd": de eerstvolgende training met de pre-training check.
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
    final clearance = store.clearanceForNextRound();
    final expanded = _expanded ?? clearance.level != ClearanceLevel.safe;
    final (_, toneFg) = toneColors(k, clearanceTone(clearance.level));

    return KCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('Geplande Mat-Tijd', style: context.t.title)),
              if (p != null) KPill(_timeLabel(p.startsAt, store.now(), p.durationMinutes), tone: KTone.primary, dense: true),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.md)),
                child: Icon(p == null ? Icons.event_available_outlined : _kindIcon(p.kind), color: k.accent, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p?.displayTitle ?? 'Geen training gepland',
                      style: context.t.subtitle.copyWith(fontSize: 17),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      p == null
                          ? 'Start een vrije training met de mat-modus-kaart.'
                          : [
                              p.kind.label,
                              if (p.durationMinutes != null) '${p.durationMinutes} min',
                              if (p.location.trim().isNotEmpty) p.location.trim(),
                            ].join(' • '),
                      style: context.t.caption,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Pre-Training Check: status meteen zichtbaar, uitleg uitklapbaar.
          Material(
            color: k.isDark ? KineticColors.sunken : k.well,
            borderRadius: BorderRadius.circular(KRadius.md),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() => _expanded = !expanded);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 32),
                      child: Row(
                        children: [
                          Icon(clearanceIcon(clearance.level), size: 20, color: toneFg),
                          const SizedBox(width: 8),
                          Expanded(child: Text('Pre-Training Check', style: context.t.bodyStrong)),
                          KPill(clearanceShort(clearance.level), tone: clearanceTone(clearance.level), dense: true),
                          const SizedBox(width: 4),
                          Icon(expanded ? Icons.expand_less : Icons.expand_more, color: k.textSecondary),
                        ],
                      ),
                    ),
                    AnimatedSize(
                      duration: const Duration(milliseconds: 180),
                      alignment: Alignment.topCenter,
                      child: expanded
                          ? Padding(
                              padding: const EdgeInsets.only(top: 8, right: 4, left: 28),
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
        ],
      ),
    );
  }

  static IconData _kindIcon(TrainingKind kind) => switch (kind) {
    TrainingKind.kracht => Icons.fitness_center,
    TrainingKind.overig => Icons.sports_martial_arts,
    _ => Icons.sports_kabaddi,
  };

  /// "18:30 - 20:00", met "morgen" / "do" ervoor als het niet vandaag is.
  static String _timeLabel(DateTime at, DateTime now, int? minutes) {
    final days = daysUntil(at, now: now);
    final range = minutes == null ? hhmm(at) : '${hhmm(at)} - ${hhmm(at.add(Duration(minutes: minutes)))}';
    if (days == 0) return range;
    if (days == 1) return 'morgen $range';
    return '${shortDate(at).split(' ').first} $range';
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
    // Inzicht-kaart uit de mocks: accentstreep links.
    return ClipRRect(
      borderRadius: BorderRadius.circular(KRadius.lg),
      child: Container(
        decoration: BoxDecoration(
          color: k.surface,
          border: Border(left: BorderSide(color: fg, width: 4)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(tone == KTone.primary ? Icons.lightbulb_outline : Icons.warning_amber_rounded, color: fg, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(title, style: context.t.subtitle)),
              ],
            ),
            const SizedBox(height: 6),
            Text(text, style: context.t.body.copyWith(color: k.textSecondary)),
          ],
        ),
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
    final liters = store.waterMlToday / 1000;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _QuickTile(
              icon: Icons.restaurant,
              title: 'Eten & Carbs',
              value: store.nutritionGoalsEnabled
                  ? '${grams(store.carbsToday)}/${grams(store.carbsTarget)}g'
                  : '${grams(store.carbsToday)}g',
              sub: 'Maaltijd toevoegen',
              onTap: store.requestMealSheet,
            ),
          ),
          if (store.waterEnabled) ...[
            const SizedBox(width: 12),
            Expanded(
              child: _QuickTile(
                icon: Icons.water_drop_outlined,
                title: 'Vocht',
                value: '${liters.toStringAsFixed(store.waterMlToday % 100 == 0 ? 1 : 2)} L',
                sub: 'Tik voor +250ml',
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
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Tegel met icoonvlak linksboven, waarde rechtsboven, titel en subregel.
class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.icon, required this.title, required this.value, required this.sub, required this.onTap});
  final IconData icon;
  final String title;
  final String value;
  final String sub;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.sm)),
                child: Icon(icon, color: k.accent, size: 22),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Align(
                  alignment: Alignment.topRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: context.t.bodyStrong.copyWith(color: k.accent, fontFeatures: const [FontFeature.tabularFigures()]),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(title, style: context.t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(sub, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
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
    final mat = store.matMinutesToday;
    Widget pair(Widget a, Widget b) => IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Row(
            children: [
              const Expanded(child: Eyebrow('Dagelijkse output')),
              Text(shortDate(store.now()), style: context.t.caption),
            ],
          ),
        ),
        pair(
          OutputTile(
            label: 'Verbranding',
            value: '${store.kcalToday}',
            unit: 'kcal',
            sub: 'Schatting uit mat-tijd',
            icon: Icons.local_fire_department_outlined,
          ),
          OutputTile(
            label: 'Tijd op Mat',
            value: '$mat',
            unit: 'min',
            sub: store.isTrainingActive ? 'Sessie loopt' : 'Vandaag',
            icon: Icons.timer_outlined,
          ),
        ),
        const SizedBox(height: 12),
        pair(
          const OutputTile(
            label: 'HRV Herstel',
            value: '—',
            sub: 'Koppel Polar H10',
            icon: Icons.favorite_border,
            muted: true,
          ),
          const OutputTile(
            label: 'Slaap Herstel',
            value: '—',
            sub: 'Geen slaapbron',
            icon: Icons.bedtime_outlined,
            muted: true,
          ),
        ),
      ],
    );
  }
}
