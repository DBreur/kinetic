// competitions_screen.dart: Fight Prep & Gewicht (kinetic_wedstrijden_gewicht):
// de komende wedstrijd met de veilige afvalcorridor, de interactieve
// ochtendinweging (±0.1 kg) naar `weigh_ins`, de gewichtscurve, de
// wedstrijdagenda met resultaten en het T1D-weegprotocol.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../core/weight_plan.dart';
import '../models/competition.dart';
import '../models/weigh_in.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/charts.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/sheets.dart';

class CompetitionsScreen extends StatelessWidget {
  const CompetitionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final comp = store.nextCompetition;
    final now = store.now();
    final current = store.currentWeightKg;
    final target = store.targetWeightKg;
    final plan = (comp != null && current != null && target != null)
        ? WeightPlan(currentKg: current, targetKg: target, now: now, weighDay: comp.startsAt)
        : null;
    return KineticPage(
      subtitle: 'Wedstrijden & Gewicht',
      body: RefreshIndicator(
        color: k.primary,
        backgroundColor: k.surface,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: pagePadding(context, top: 16),
          children: [
            _Header(comp: comp, now: now),
            const SizedBox(height: 16),
            _CompetitionCard(comp: comp, plan: plan, now: now),
            const SizedBox(height: 12),
            const _WeighInCard(),
            const SizedBox(height: 12),
            _TrajectoryCard(comp: comp, plan: plan, now: now),
            const SizedBox(height: 24),
            const _Agenda(),
            const SizedBox(height: 24),
            const _Protocol(),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- helpers

/// +88 kg-klasse zonder eigen doel: je moet er bóven zitten.
bool _isMinimumClass(Competition? c) => c?.weightLimitType == WeightLimitType.over && c?.targetWeightKg == null;

/// De eerste weging van het kamp (hooguit 8 weken terug).
WeighIn? _campStart(List<WeighIn> weighIns, DateTime now) {
  final from = now.subtract(const Duration(days: 56));
  WeighIn? first;
  for (final w in weighIns) {
    if (w.measuredAt.isBefore(from)) continue;
    if (first == null || w.measuredAt.isBefore(first.measuredAt)) first = w;
  }
  return first;
}

String _signedKg(double v, {int digits = 1}) {
  final s = v.abs().toStringAsFixed(digits);
  if (double.parse(s) == 0) return '0.${'0' * digits} kg';
  return '${v < 0 ? '−' : '+'}$s kg';
}

String _dayLabel(DateTime t, DateTime now) {
  final d = dayStart(now).difference(dayStart(t)).inDays;
  return switch (d) {
    0 => 'vandaag',
    1 => 'gisteren',
    _ => shortDate(t),
  };
}

Future<void> _editTarget(BuildContext context) async {
  final store = KineticScope.read(context);
  final comp = store.nextCompetition;
  if (comp == null) return;
  final ctrl = TextEditingController(text: comp.targetWeightKg == null ? '' : dec1(comp.targetWeightKg!));
  final v = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Doelgewicht op de weegdag'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        style: ctx.t.body,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(labelText: 'kg (leeg = klassegrens)', suffixText: 'kg'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Annuleren')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Opslaan')),
      ],
    ),
  );
  ctrl.dispose();
  if (v == null) return;
  final kg = parseNum(v);
  if (v.trim().isNotEmpty && (kg == null || kg < 20 || kg > 300)) {
    if (context.mounted) showToast(context, 'Vul een gewicht tussen 20 en 300 kg in', error: true);
    return;
  }
  final ok = await store.setTargetWeight(kg);
  if (context.mounted && !ok) showToast(context, 'Doelgewicht opslaan mislukt', error: true);
}

// --------------------------------------------------------------- header

class _Header extends StatelessWidget {
  const _Header({required this.comp, required this.now});
  final Competition? comp;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = comp;
    final days = c == null ? null : daysUntil(c.startsAt, now: now);
    final pill = switch (days) {
      null => null,
      0 => 'Weegdag',
      final d when d > 0 => 'Kampdag −$d',
      _ => null,
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Eyebrow('Metabool vechtersdashboard'),
              const SizedBox(height: 4),
              Text('Fight Prep & Gewicht', style: context.t.headline),
            ],
          ),
        ),
        if (pill != null) ...[
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: KPill(pill, tone: KTone.primary, dot: true),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------ wedstrijd

class _CompetitionCard extends StatelessWidget {
  const _CompetitionCard({required this.comp, required this.plan, required this.now});
  final Competition? comp;
  final WeightPlan? plan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final c = comp;
    if (c == null) {
      return KCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTile(icon: Icons.emoji_events_outlined, size: 40, color: k.textSecondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Geen wedstrijd gepland', style: context.t.title),
                  const SizedBox(height: 4),
                  Text(
                    'Wedstrijden komen uit je bestaande competitions-tabel. Je kunt hier wel gewoon inwegen.',
                    style: context.t.caption,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final days = daysUntil(c.startsAt, now: now);
    final countdown = switch (days) {
      0 => 'Vandaag officiële weging',
      1 => 'Morgen officiële weging',
      final d when d > 1 => 'Nog $d dagen tot officiële weging',
      _ => 'Wedstrijd is begonnen. Succes!',
    };
    final limit = c.weightLimitKg;
    final limitTag = limit == null
        ? null
        : switch (c.weightLimitType) {
            WeightLimitType.under => '−${dec1(limit)} kg limiet',
            WeightLimitType.over => '+${dec1(limit)} kg minimum',
            WeightLimitType.none => null,
          };
    final current = store.currentWeightKg;
    final target = store.targetWeightKg;
    final minimum = _isMinimumClass(c);
    final start = _campStart(store.weighIns, now)?.weightKg ?? current;

    // Delta-pill: hoeveel er nog af (of bij) moet.
    Widget? deltaPill;
    if (current != null && target != null) {
      final d = double.parse((target - current).toStringAsFixed(1));
      if (minimum) {
        deltaPill = c.isWithinLimit(current)
            ? const KPill('Boven grens', tone: KTone.success, icon: Icons.check, dense: true)
            : KPill('+${dec1(target - current + 0.1)} kg aankomen', tone: KTone.warning, dense: true);
      } else if (d.abs() < 0.05) {
        deltaPill = const KPill('Op doel', tone: KTone.success, icon: Icons.check, dense: true);
      } else if (d < 0) {
        deltaPill = KPill('${dec1(d)} kg naar doel', tone: KTone.warning, dense: true);
      } else if (c.weightLimitType == WeightLimitType.under) {
        deltaPill = KPill('+${dec1(d)} kg marge', tone: KTone.success, dense: true);
      } else {
        deltaPill = KPill('+${dec1(d)} kg aankomen', tone: KTone.info, dense: true);
      }
    }

    // Voortgang van het kampbegin naar het doel.
    var progress = 0.0;
    if (current != null && target != null && start != null) {
      if ((start - target).abs() < 0.05) {
        progress = (current - target).abs() < 0.05 ? 1 : 0;
      } else {
        progress = ((start - current) / (start - target)).clamp(0.0, 1.0);
      }
    }

    final (statusIcon, statusColor, statusText) = _corridorStatus(k, c, plan, current);

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Eyebrow(
                  '${c.disciplineLabel} • ${c.weightClass.isEmpty ? 'open klasse' : c.weightClass}',
                  icon: Icons.sports_martial_arts,
                  color: k.accent,
                ),
              ),
              if (limitTag != null) ...[
                const SizedBox(width: 8),
                KPill(limitTag, tone: KTone.primary, dense: true),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(c.name, style: context.t.headline),
          const SizedBox(height: 4),
          Text('${longDate(c.startsAt)} ${c.startsAt.year} • $countdown', style: context.t.body.copyWith(color: k.textSecondary)),
          if (c.location.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('${c.location} • ${hhmm(c.startsAt)}', style: context.t.caption.copyWith(color: k.textMuted)),
          ],
          const SizedBox(height: 14),
          KWell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: 'Huidig: ', style: context.t.caption),
                            TextSpan(text: current == null ? '--' : dec1(current), style: context.t.subtitle),
                            TextSpan(text: ' kg', style: context.t.caption),
                          ],
                        ),
                      ),
                    ),
                    ?deltaPill,
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Semantics(
                          button: true,
                          label: 'Doelgewicht aanpassen',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(KRadius.sm),
                            onTap: () => _editTarget(context),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 48),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text.rich(
                                      TextSpan(
                                        children: [
                                          TextSpan(text: 'Doel: ', style: context.t.caption),
                                          TextSpan(text: target == null ? '--' : dec1(target), style: context.t.subtitle),
                                          TextSpan(text: ' kg', style: context.t.caption),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.edit_outlined, size: 16, color: k.accent),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                KProgressBar(value: progress, height: 10),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      start == null ? 'Start kamp' : 'Start kamp (${dec1(start)} kg)',
                      style: context.t.labelSm.copyWith(color: k.textMuted),
                    ),
                    const Spacer(),
                    Text('Doelweging', style: context.t.labelSm.copyWith(color: k.textMuted)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(statusText, style: context.t.caption.copyWith(color: statusColor, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Korte status van de afvalcorridor (icoon, kleur, tekst).
(IconData, Color, String) _corridorStatus(KineticColors k, Competition c, WeightPlan? plan, double? current) {
  if (_isMinimumClass(c) && current != null && c.weightLimitKg != null) {
    final limit = c.weightLimitKg!;
    return c.isWithinLimit(current)
        ? (Icons.check_circle, k.successInk, 'Boven de klassegrens (> ${dec1(limit)} kg)')
        : (Icons.trending_up, k.warningInk, 'Nog +${dec1(limit - current + 0.1)} kg aankomen voor de +${dec1(limit)} kg-klasse');
  }
  final p = plan;
  if (p == null) return (Icons.info_outline, k.textSecondary, 'Registreer een weging om je corridor te berekenen');
  final rate = p.requiredKgPerWeek;
  return switch (p.direction) {
    WeightDirection.onTarget => (Icons.check_circle, k.successInk, 'Op doelgewicht: houd het stabiel'),
    WeightDirection.gain => (Icons.trending_up, k.blue, 'Aankomen: ${_signedKg(p.deltaKg)}, geen cut nodig'),
    WeightDirection.lose when !p.isSafe => (
      Icons.warning_amber_rounded,
      k.dangerInk,
      'Te snel: ${rate == null ? '-' : rate.toStringAsFixed(2)} kg/wk nodig (max ${dec1(safeLossPerWeekMax)})',
    ),
    WeightDirection.lose when rate != null && rate > safeLossPerWeekMax => (
      Icons.warning_amber_rounded,
      k.warningInk,
      'Krap: ${rate.toStringAsFixed(2)} kg/wk + max ${dec1(p.maxWaterCutKg)} kg water cut',
    ),
    WeightDirection.lose => (
      Icons.verified,
      k.successInk,
      'Binnen veilige afvalcorridor (${rate == null ? '-' : rate.toStringAsFixed(2)} kg/wk)',
    ),
  };
}

// -------------------------------------------------------------- inweging

class _WeighInCard extends StatelessWidget {
  const _WeighInCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final now = store.now();
    final comp = store.nextCompetition;
    final draft = store.draftWeightKg;
    final target = store.targetWeightKg;
    final last = store.weighIns.isEmpty ? null : store.weighIns.first;
    final minimum = _isMinimumClass(comp);
    final wantGain = minimum || (target != null && store.currentWeightKg != null && target > store.currentWeightKg!);

    // Afstand tot het doel, live met de stepper mee.
    String deltaText;
    Color deltaColor;
    IconData deltaIcon;
    if (target == null) {
      deltaText = 'Geen doelgewicht ingesteld';
      deltaColor = k.textMuted;
      deltaIcon = Icons.flag_outlined;
    } else {
      final d = double.parse((target - draft).toStringAsFixed(1));
      if (minimum) {
        final ok = comp!.isWithinLimit(draft);
        deltaText = ok
            ? 'Boven de klassegrens (${dec1(target)} kg)'
            : 'Nog aan te komen: +${dec1((target - draft) + 0.1)} kg (min. > ${dec1(target)} kg)';
        deltaColor = ok ? k.successInk : k.warningInk;
        deltaIcon = ok ? Icons.check_circle : Icons.trending_up;
      } else if (d.abs() < 0.05) {
        deltaText = 'Op doelgewicht';
        deltaColor = k.successInk;
        deltaIcon = Icons.check_circle;
      } else if (d < 0) {
        deltaText = 'Nog af te vallen: ${dec1(d)} kg naar doel';
        deltaColor = k.warningInk;
        deltaIcon = Icons.flag_outlined;
      } else {
        deltaText = 'Onder doel: +${dec1(d)} kg marge';
        deltaColor = k.successInk;
        deltaIcon = Icons.check_circle;
      }
    }

    // Trend t.o.v. de vorige weging (van vóór vandaag).
    final today = dayStart(now);
    WeighIn? prev;
    for (final w in store.weighIns) {
      if (w.measuredAt.isBefore(today) && (prev == null || w.measuredAt.isAfter(prev.measuredAt))) prev = w;
    }
    Widget trend;
    if (prev == null) {
      trend = Text('Eerste weging', style: context.t.caption);
    } else {
      final diff = double.parse((draft - prev.weightKg).toStringAsFixed(1));
      final good = wantGain ? diff > 0 : diff < 0;
      final color = diff.abs() < 0.05 ? k.textSecondary : (good ? k.successInk : k.warningInk);
      final icon = diff.abs() < 0.05 ? Icons.trending_flat : (diff < 0 ? Icons.trending_down : Icons.trending_up);
      trend = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              diff.abs() < 0.05
                  ? 'Gelijk aan ${_dayLabel(prev.measuredAt, now)}'
                  : '${_signedKg(diff)} t.o.v. ${_dayLabel(prev.measuredAt, now)}',
              style: context.t.caption.copyWith(color: color, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );
    }

    // Glucose bij het wegen ("nuchter" als het ochtend is).
    final r = store.reading;
    final fasting = now.hour < 11;
    String glucoseSub;
    Color glucoseColor;
    if (r == null) {
      glucoseSub = store.glucose?.message ?? 'Geen meting';
      glucoseColor = k.textMuted;
    } else if (now.difference(r.at).inMinutes >= 15) {
      glucoseSub = 'Meting ${now.difference(r.at).inMinutes} min oud';
      glucoseColor = k.textMuted;
    } else {
      (glucoseSub, glucoseColor) = switch (zoneFor(r.mmol)) {
        GlucoseZone.hypo => ('Hypo: eerst eten', k.dangerInk),
        GlucoseZone.low => ('Laag (${trendLabel(r.trend).toLowerCase()})', k.warningInk),
        GlucoseZone.high => (r.mmol > ketoneCheckAbove ? 'Hoog: check ketonen' : 'Boven doelbereik', k.warningInk),
        GlucoseZone.inTarget => ('${trendLabel(r.trend)} (laag risico)', k.successInk),
      };
    }

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.monitor_weight_outlined, size: 22, color: k.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('Ochtend Inweging', style: context.t.title)),
              Text('${fasting ? 'Nuchter' : 'Vandaag'} • ${hhmm(now)}', style: context.t.caption),
            ],
          ),
          const SizedBox(height: 12),
          KWell(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                StepButton(icon: Icons.remove, size: 64, onTap: () => store.adjustWeight(-0.1)),
                Expanded(
                  child: Column(
                    children: [
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: dec1(draft), style: context.t.metric),
                            TextSpan(text: ' kg', style: context.t.subtitle.copyWith(color: k.textSecondary)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 2),
                      trend,
                    ],
                  ),
                ),
                StepButton(icon: Icons.add, size: 64, onTap: () => store.adjustWeight(0.1)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(deltaIcon, size: 16, color: deltaColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(deltaText, style: context.t.caption.copyWith(color: deltaColor, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  inWell: true,
                  icon: Icons.history,
                  label: 'Laatste weging',
                  value: last == null ? '--' : '${dec1(last.weightKg)} kg',
                  sub: last == null ? 'Nog geen weging' : '${_dayLabel(last.measuredAt, now)} ${hhmm(last.measuredAt)}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  inWell: true,
                  icon: Icons.bloodtype_outlined,
                  label: fasting ? 'Nuchtere glucose' : 'Glucose nu',
                  value: r == null ? '--' : '${dec1(r.mmol)} mmol/L',
                  sub: glucoseSub,
                  subColor: glucoseColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          BigButton(
            label: 'Gewicht Registreren',
            icon: Icons.save_outlined,
            height: 56,
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final kg = store.draftWeightKg;
              final ok = await store.registerWeight();
              showToastOn(messenger, ok ? '${dec1(kg)} kg opgeslagen in je gewichtscurve' : 'Opslaan mislukt', error: !ok);
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ traject

class _TrajectoryCard extends StatelessWidget {
  const _TrajectoryCard({required this.comp, required this.plan, required this.now});
  final Competition? comp;
  final WeightPlan? plan;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final p = plan;
    final c = comp;
    final current = store.currentWeightKg;
    final start = _campStart(store.weighIns, now);
    final minimum = _isMinimumClass(c);
    final wantGain = minimum || p?.direction == WeightDirection.gain;

    final pill = switch (p) {
      null => null,
      _ when minimum && current != null => c!.isWithinLimit(current)
          ? const KPill('Boven grens', tone: KTone.success, icon: Icons.verified, dense: true)
          : const KPill('Aankomen', tone: KTone.warning, icon: Icons.trending_up, dense: true),
      final p when p.direction == WeightDirection.onTarget => const KPill('Op gewicht', tone: KTone.success, icon: Icons.verified, dense: true),
      final p when p.direction == WeightDirection.gain => const KPill('Aankomen', tone: KTone.info, icon: Icons.trending_up, dense: true),
      final p when p.isSafe => const KPill('Op schema', tone: KTone.success, icon: Icons.verified, dense: true),
      _ => const KPill('Te snel', tone: KTone.danger, icon: Icons.warning_amber_rounded, dense: true),
    };

    // Kampstatistiek: totaal, tempo per week, restant.
    final total = (start == null || current == null) ? null : current - start.weightKg;
    final weeks = start == null ? 0.0 : now.difference(start.measuredAt).inHours / (24 * 7);
    final perWeek = (total == null || weeks < 0.5) ? null : total / weeks;
    Color? good(double? v) {
      if (v == null || v.abs() < 0.05) return null;
      return (wantGain ? v > 0 : v < 0) ? k.successInk : k.warningInk;
    }

    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Gewichtstraject & Target Curve', style: context.t.title),
                    const SizedBox(height: 2),
                    Text(
                      c == null
                          ? 'Je laatste wegingen'
                          : 'Corridor ${dec1(safeLossPerWeekMin)} - ${dec1(safeLossPerWeekMax)} kg/week naar de weging (${longDate(c.startsAt)})',
                      style: context.t.caption,
                    ),
                  ],
                ),
              ),
              if (pill != null) ...[const SizedBox(width: 8), pill],
            ],
          ),
          const SizedBox(height: 14),
          WeightCurve(weighIns: store.weighIns, plan: p, now: now),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  inWell: true,
                  label: wantGain ? 'Totaal verschil' : 'Totaal verlies',
                  value: total == null ? '--' : _signedKg(total),
                  valueColor: good(total),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  inWell: true,
                  label: 'Snelheid / wk',
                  value: perWeek == null ? '--' : _signedKg(perWeek, digits: 2),
                  valueColor: good(perWeek),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  inWell: true,
                  label: 'Restant',
                  value: p == null ? '--' : '${dec1(p.deltaKg.abs())} kg',
                  valueColor: k.accent,
                ),
              ),
            ],
          ),
          if (p != null && c != null && !minimum) ...[
            const SizedBox(height: 12),
            _PlanVerdict(plan: p),
          ],
        ],
      ),
    );
  }
}

class _PlanVerdict extends StatelessWidget {
  const _PlanVerdict({required this.plan});
  final WeightPlan plan;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final rate = plan.requiredKgPerWeek;
    final (icon, color, text) = switch (plan.direction) {
      WeightDirection.onTarget => (Icons.check_circle, k.successInk, 'Je zit op je doelgewicht. Houd het stabiel en blijf hydrateren.'),
      WeightDirection.gain => (
        Icons.trending_up,
        k.blue,
        'Je moet ${dec1(plan.deltaKg)} kg aankomen. Geen cut nodig: eet en drink normaal richting de weging.',
      ),
      WeightDirection.lose =>
        plan.isSafe
            ? (
                Icons.verified,
                k.successInk,
                'Nodig: ${rate == null ? '-' : dec1(rate)} kg/week. Binnen de veilige corridor (+ max ${dec1(plan.maxWaterCutKg)} kg water cut).',
              )
            : (
                Icons.warning_amber_rounded,
                k.dangerInk,
                'Nodig: ${rate == null ? '-' : dec1(rate)} kg/week. Te snel voor T1D (risico op uitdroging/DKA). Overweeg een hogere klasse.',
              ),
    };
    return KWell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: context.t.caption.copyWith(color: k.text))),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- agenda

class _Agenda extends StatelessWidget {
  const _Agenda();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final now = store.now();
    final today = dayStart(now);
    final all = store.allCompetitions;
    final upcoming = all.where((c) => !c.startsAt.isBefore(today)).toList()..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final past = all.where((c) => c.startsAt.isBefore(today)).toList()..sort((a, b) => b.startsAt.compareTo(a.startsAt));
    final nextId = store.nextCompetition?.id ?? (upcoming.isEmpty ? null : upcoming.first.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Wedstrijd & Weeg Agenda',
          trailing: Text('${all.length} ${all.length == 1 ? 'toernooi' : 'toernooien'}', style: context.t.caption),
        ),
        if (all.isEmpty)
          KCard(child: Text('Nog geen wedstrijden in je agenda. Ze komen uit je bestaande competitions-tabel.', style: context.t.caption)),
        for (final c in upcoming) ...[
          _UpcomingItem(comp: c, isNext: c.id == nextId, now: now, currentKg: store.currentWeightKg),
          const SizedBox(height: 8),
        ],
        for (final c in past) ...[
          _PastItem(comp: c),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _UpcomingItem extends StatelessWidget {
  const _UpcomingItem({required this.comp, required this.isNext, required this.now, required this.currentKg});
  final Competition comp;
  final bool isNext;
  final DateTime now;
  final double? currentKg;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = comp;
    final days = daysUntil(c.startsAt, now: now);
    final color = isNext ? k.accent : k.textSecondary;
    final status = isNext
        ? (days == 0 ? 'Weegdag vandaag' : 'In voorbereiding ($days ${days == 1 ? 'dag' : 'dagen'})')
        : 'Gepland • over $days dagen';
    final target = c.effectiveTargetKg;
    final limit = c.weightLimitKg;
    String right;
    Color rightColor = k.accent;
    if (isNext && target != null) {
      right = 'Doel: ${dec1(target)} kg';
    } else if (limit != null && currentKg != null && c.weightLimitType == WeightLimitType.under) {
      final room = limit - currentKg!;
      right = room >= 0 ? '+${dec1(room)} kg speelruimte' : '${dec1(room.abs())} kg te zwaar';
      rightColor = room >= 0 ? k.successInk : k.warningInk;
    } else if (limit != null && currentKg != null && c.weightLimitType == WeightLimitType.over) {
      final ok = c.isWithinLimit(currentKg!);
      right = ok ? 'Boven grens' : 'Nog +${dec1(limit - currentKg! + 0.1)} kg';
      rightColor = ok ? k.successInk : k.warningInk;
    } else {
      right = c.weightClass.isEmpty ? 'Open klasse' : c.weightClass;
    }
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Flexible(child: Text(status.toUpperCase(), style: context.t.labelSm.copyWith(color: color))),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(c.name, style: context.t.subtitle),
                    const SizedBox(height: 2),
                    Text(
                      [
                        '${shortDate(c.startsAt)} ${c.startsAt.year}',
                        c.weightClass.isEmpty ? 'open klasse' : c.weightClass,
                        c.disciplineLabel,
                      ].join(' • '),
                      style: context.t.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(isNext ? Icons.flag_outlined : Icons.event_outlined, color: color, size: 22),
            ],
          ),
          const SizedBox(height: 10),
          KWell(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Weging ${shortDate(c.startsAt)} • ${hhmm(c.startsAt)}${c.location.isEmpty ? '' : ' • ${c.location}'}',
                    style: context.t.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(right, style: context.t.caption.copyWith(color: rightColor, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PastItem extends StatelessWidget {
  const _PastItem({required this.comp});
  final Competition comp;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final c = comp;
    final place = c.placeLabel;
    final color = place == null ? k.textMuted : (c.resultPlace == 1 ? k.warningInk : k.accent);
    final record = (c.resultWins != null || c.resultLosses != null) ? '${c.resultWins ?? 0}W • ${c.resultLosses ?? 0}V' : null;
    return KCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(place == null ? Icons.history : Icons.military_tech, size: 16, color: color),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text((place ?? 'Afgelopen • geen resultaat').toUpperCase(), style: context.t.labelSm.copyWith(color: color)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(c.name, style: context.t.subtitle),
                const SizedBox(height: 2),
                Text(
                  'Afgelopen • ${shortDate(c.startsAt)} ${c.startsAt.year}${c.weightClass.isEmpty ? '' : ' • ${c.weightClass} klasse'}',
                  style: context.t.caption,
                ),
                if (c.resultNote.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(c.resultNote.trim(), style: context.t.caption.copyWith(color: k.textMuted)),
                ],
              ],
            ),
          ),
          if (record != null) ...[
            const SizedBox(width: 8),
            KPill(record, dense: true),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ protocol

class _Protocol extends StatelessWidget {
  const _Protocol();

  static const _items = [
    (
      'hydration',
      Icons.water_drop_outlined,
      'Geen Extreme Uitdroging (Water Cut < 2.5%)',
      'Ernstige dehydratatie vertraagt de opname van insuline onder de huid en vergroot het risico op (euglykemische) ketoacidose (DKA).',
    ),
    (
      'glycogen',
      Icons.restaurant_outlined,
      'Glycogeen Restoratie Post-Weeging',
      'Start ~20 min na de officiële weging met hypertone elektrolyten + snelle koolhydraten. Verlaag de bolus 30-40% door de verhoogde insulinegevoeligheid.',
    ),
    (
      'calibration',
      Icons.monitor_heart_outlined,
      'Sensor Calibratie bij Vochtverschuivingen',
      'Controleer de G7 met een vingerprik op de weegochtend en na het rehydrateren: vochtverschuivingen geven CGM-afwijkingen tot 1.5 mmol/L.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final done = store.checklistCount;
    final all = done == weighInChecklistKeys.length;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.health_and_safety_outlined, color: k.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text('T1D Weegprotocol & Rehydratatie', style: context.t.title)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Kritieke metabole richtlijnen voor vechters met type 1 diabetes in de laatste week van de gewichtsafname.',
            style: context.t.caption,
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: KPill(
              '$done / ${weighInChecklistKeys.length} Voldaan',
              tone: all ? KTone.success : KTone.warning,
              icon: all ? Icons.check_circle : Icons.pending_outlined,
              dense: true,
            ),
          ),
          const SizedBox(height: 12),
          for (final (key, icon, title, sub) in _items) ...[
            KWell(
              padding: const EdgeInsets.fromLTRB(4, 8, 12, 12),
              borderColor: store.checklistDone(key) ? k.primary.withValues(alpha: 0.5) : null,
              onTap: () {
                HapticFeedback.selectionClick();
                store.toggleChecklist(key);
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(value: store.checklistDone(key), onChanged: (_) => store.toggleChecklist(key)),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(top: 1),
                                child: Icon(icon, size: 16, color: k.accent),
                              ),
                              const SizedBox(width: 6),
                              Expanded(child: Text(title, style: context.t.bodyStrong)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(sub, style: context.t.caption),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 4),
          BigButton(
            label: 'Vingerprik vergelijken met G7',
            icon: Icons.water_drop_outlined,
            style: KButtonStyle.secondary,
            onPressed: () => showFingerstickSheet(context),
          ),
        ],
      ),
    );
  }
}
