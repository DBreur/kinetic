// competitions_screen.dart: Wedstrijden & Gewicht (Fight Prep): aftelling,
// interactieve ochtendinweging (±0.1 kg) naar `weigh_ins`, gewichtscurve met
// veilige corridor en het T1D-weegprotocol.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/weight_plan.dart';
import '../models/competition.dart';
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
    final comp = store.nextCompetition;
    final now = store.now();
    final current = store.currentWeightKg;
    final target = store.targetWeightKg;
    final plan = (comp != null && current != null && target != null)
        ? WeightPlan(currentKg: current, targetKg: target, now: now, weighDay: comp.startsAt)
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Wedstrijden & Gewicht')),
      body: RefreshIndicator(
        color: KColor.teal,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            _Countdown(comp: comp, now: now),
            const SizedBox(height: 12),
            const _WeighInCalculator(),
            const SizedBox(height: 12),
            KCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Eyebrow('Target curve', color: KColor.tealLight, icon: Icons.show_chart),
                  const SizedBox(height: 4),
                  Text(
                    'Veilige afvalcorridor ${dec1(safeLossPerWeekMin)} - ${dec1(safeLossPerWeekMax)} kg/week${comp == null ? '' : ' t.o.v. de weegdag (${longDate(comp.startsAt)})'}',
                    style: KText.caption,
                  ),
                  const SizedBox(height: 12),
                  WeightCurve(weighIns: store.weighIns, plan: plan, now: now),
                  if (plan != null) ...[
                    const SizedBox(height: 10),
                    _PlanVerdict(plan: plan, comp: comp!),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            const _Protocol(),
          ],
        ),
      ),
    );
  }
}

class _Countdown extends StatelessWidget {
  const _Countdown({required this.comp, required this.now});
  final Competition? comp;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final c = comp;
    if (c == null) {
      return KCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Eyebrow('Toernooi', color: KColor.purple, icon: Icons.emoji_events_outlined),
            const SizedBox(height: 8),
            Text('Geen wedstrijd gepland', style: KText.title),
            const SizedBox(height: 4),
            Text('Wedstrijden komen uit je bestaande competitions-tabel. Je kunt hier wel gewoon inwegen.', style: KText.caption),
          ],
        ),
      );
    }
    final diff = c.startsAt.difference(now);
    final days = diff.inDays;
    final hours = diff.inHours % 24;
    return KCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [KColor.purple.withValues(alpha: 0.25), KColor.surfaceContainer],
      ),
      borderColor: KColor.purple.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Eyebrow('${c.disciplineLabel} • ${c.weightClass.isEmpty ? 'open klasse' : c.weightClass}', color: KColor.purple, icon: Icons.emoji_events_outlined),
          const SizedBox(height: 8),
          Text(c.name, style: KText.display.copyWith(fontSize: 24)),
          const SizedBox(height: 4),
          Text(
            '${shortDate(c.startsAt)} • ${hhmm(c.startsAt)}${c.location.isEmpty ? '' : ' • ${c.location}'}',
            style: KText.caption.copyWith(color: KColor.text),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _CountBox(value: diff.isNegative ? 0 : days, label: 'DAGEN'),
              const SizedBox(width: 10),
              _CountBox(value: diff.isNegative ? 0 : hours, label: 'UUR'),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  diff.isNegative ? 'Wedstrijd is vandaag begonnen. Succes! 🥋' : 'tot de weegdag',
                  style: KText.caption,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBox extends StatelessWidget {
  const _CountBox({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: KColor.bg.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(KRadius.md)),
      child: Column(
        children: [
          Text(two(value), style: KText.metric),
          const SizedBox(height: 2),
          Text(label, style: KText.eyebrow.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}

class _WeighInCalculator extends StatelessWidget {
  const _WeighInCalculator();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final comp = store.nextCompetition;
    final draft = store.draftWeightKg;
    final target = store.targetWeightKg;
    final last = store.weighIns.isEmpty ? null : store.weighIns.first;
    String deltaText;
    Color deltaColor;
    if (target == null) {
      deltaText = 'Geen doelgewicht ingesteld';
      deltaColor = KColor.textMuted;
    } else {
      final d = double.parse((target - draft).toStringAsFixed(1));
      final minimum = comp?.weightLimitType == WeightLimitType.over && comp?.targetWeightKg == null;
      if (minimum) {
        // +88 kg-klasse: je moet er bóven zitten.
        final ok = comp!.isWithinLimit(draft);
        deltaText = ok ? 'Boven de klassegrens (${dec1(target)} kg) ✓' : 'Nog aan te komen: +${dec1((target - draft) + 0.1)} kg (min. > ${dec1(target)} kg)';
        deltaColor = ok ? KColor.success : KColor.warning;
      } else if (d.abs() < 0.05) {
        deltaText = 'Op doelgewicht ✓';
        deltaColor = KColor.success;
      } else if (d < 0) {
        deltaText = 'Nog af te vallen: ${dec1(d)} kg naar doel';
        deltaColor = KColor.warning;
      } else {
        deltaText = 'Onder doel: +${dec1(d)} kg marge';
        deltaColor = KColor.success;
      }
    }
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Ochtendinweging', color: KColor.blue, icon: Icons.monitor_weight_outlined)),
              TextButton.icon(
                onPressed: comp == null ? null : () => _editTarget(context, store),
                icon: const Icon(Icons.flag_outlined, size: 16),
                label: Text(target == null ? 'Doel instellen' : 'Doel ${dec1(target)} kg', style: KText.caption.copyWith(color: KColor.tealLight)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WeightStep(icon: Icons.remove, onTap: () => store.adjustWeight(-0.1)),
              Expanded(
                child: Column(
                  children: [
                    Text.rich(
                      TextSpan(children: [
                        TextSpan(text: dec1(draft), style: KText.metric.copyWith(fontSize: 48)),
                        TextSpan(text: ' kg', style: KText.subtitle.copyWith(color: KColor.textSecondary)),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    Text(deltaText, textAlign: TextAlign.center, style: KText.caption.copyWith(color: deltaColor, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              _WeightStep(icon: Icons.add, onTap: () => store.adjustWeight(0.1)),
            ],
          ),
          const SizedBox(height: 14),
          BigButton(
            label: 'Gewicht Registreren',
            icon: Icons.save_alt,
            onPressed: () async {
              final kg = store.draftWeightKg;
              final ok = await store.registerWeight();
              if (!context.mounted) return;
              showToast(context, ok ? '${dec1(kg)} kg opgeslagen in je gewichtscurve' : 'Opslaan mislukt', error: !ok);
            },
          ),
          if (last != null) ...[
            const SizedBox(height: 8),
            Center(
              child: Text(
                'Laatst gewogen: ${dec1(last.weightKg)} kg op ${shortDate(last.measuredAt)} ${hhmm(last.measuredAt)}',
                style: KText.caption,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _editTarget(BuildContext context, KineticStore store) async {
    final ctrl = TextEditingController(text: store.nextCompetition?.targetWeightKg == null ? '' : dec1(store.nextCompetition!.targetWeightKg!));
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Doelgewicht op de weegdag'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'kg (leeg = klassegrens)'),
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
    if (v.trim().isNotEmpty && (kg == null || kg < 20 || kg > 300)) return;
    await store.setTargetWeight(kg);
  }
}

class _WeightStep extends StatelessWidget {
  const _WeightStep({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Material(
        color: KColor.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.lg)),
        child: InkWell(
          borderRadius: BorderRadius.circular(KRadius.lg),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Icon(icon, size: 30, color: KColor.text),
        ),
      ),
    );
  }
}

class _PlanVerdict extends StatelessWidget {
  const _PlanVerdict({required this.plan, required this.comp});
  final WeightPlan plan;
  final Competition comp;

  @override
  Widget build(BuildContext context) {
    final rate = plan.requiredKgPerWeek;
    final (icon, color, text) = switch (plan.direction) {
      WeightDirection.onTarget => (Icons.check_circle, KColor.success, 'Je zit op je doelgewicht. Houd het stabiel en blijf hydrateren.'),
      WeightDirection.gain => (
          Icons.trending_up,
          KColor.blue,
          'Je moet ${dec1(plan.deltaKg)} kg aankomen. Geen cut nodig: eet en drink normaal richting de weging.',
        ),
      WeightDirection.lose => plan.isSafe
          ? (
              Icons.verified,
              KColor.success,
              'Nodig: ${rate == null ? '-' : dec1(rate)} kg/week. Binnen de veilige corridor (+ max ${dec1(plan.maxWaterCutKg)} kg water cut).',
            )
          : (
              Icons.warning_amber_rounded,
              KColor.danger,
              'Nodig: ${rate == null ? '-' : dec1(rate)} kg/week. Te snel voor T1D (risico op uitdroging/DKA). Overweeg een hogere klasse.',
            ),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: KText.caption.copyWith(color: KColor.text))),
      ],
    );
  }
}

class _Protocol extends StatelessWidget {
  const _Protocol();

  static const _items = [
    (
      'hydration',
      'Geen Extreme Uitdroging (Water Cut < 2.5%)',
      'Dehydratie verhoogt de kans op DKA en maakt CGM-waarden onbetrouwbaar.',
    ),
    (
      'glycogen',
      'Glycogeen Restoratie Post-Weeging',
      'Hypertoon elektrolyt + insulineverlaging 30-40% bij het bijtanken.',
    ),
    (
      'calibration',
      'Sensor Calibratie bij Vochtverschuivingen',
      'Controleer de G7 met een vingerprik na de weging en na het rehydrateren.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final done = store.checklistCount;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('T1D weegprotocol & rehydratatie', color: KColor.warning, icon: Icons.health_and_safety_outlined)),
              KBadge('$done / ${weighInChecklistKeys.length} Voldaan', color: done == weighInChecklistKeys.length ? KColor.success : KColor.warning, dot: false),
            ],
          ),
          const SizedBox(height: 8),
          for (final (i, (key, title, sub)) in _items.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(KRadius.md),
              onTap: () {
                HapticFeedback.selectionClick();
                store.toggleChecklist(key);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Transform.scale(
                      scale: 1.25,
                      child: Checkbox(value: store.checklistDone(key), onChanged: (_) => store.toggleChecklist(key)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${i + 1}. $title', style: KText.body.copyWith(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(sub, style: KText.caption),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (store.nextCompetition != null) ...[
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: () => showFingerstickSheet(context),
              icon: const Icon(Icons.water_drop_outlined),
              label: const Text('Vingerprik vergelijken met G7'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
        ],
      ),
    );
  }
}
