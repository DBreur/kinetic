// training_screen.dart: Training Historie: periodefilters, mat-volume,
// glucose safe-zone, intensiteitsgrafiek en sessiekaarten uit
// `training_sessions`.

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../models/training_session.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/charts.dart';
import '../widgets/kinetic_widgets.dart';

enum TrainingPeriod {
  week('Deze Week'),
  month('Maand'),
  camp('Fight Camp (8w)'),
  all('Alle');

  const TrainingPeriod(this.label);
  final String label;
}

/// Begin van de periode (null = alles).
DateTime? periodStart(TrainingPeriod p, DateTime now) {
  final today = dayStart(now);
  return switch (p) {
    TrainingPeriod.week => today.subtract(Duration(days: today.weekday - 1)),
    TrainingPeriod.month => today.subtract(const Duration(days: 29)),
    TrainingPeriod.camp => today.subtract(Duration(days: today.weekday - 1 + 7 * 7)),
    TrainingPeriod.all => null,
  };
}

/// Minuten per staafje + labels voor de intensiteitsgrafiek.
(List<int>, List<String>) intensitySeries(TrainingPeriod p, List<TrainingSession> sessions, DateTime now) {
  final today = dayStart(now);
  int minutesBetween(DateTime from, DateTime to) => sessions
      .where((s) => !s.startedAt.isBefore(from) && s.startedAt.isBefore(to))
      .fold(0, (sum, s) => sum + s.durationMinutes);
  switch (p) {
    case TrainingPeriod.week:
      final monday = today.subtract(Duration(days: today.weekday - 1));
      const names = ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'];
      return (
        [for (var i = 0; i < 7; i++) minutesBetween(monday.add(Duration(days: i)), monday.add(Duration(days: i + 1)))],
        names,
      );
    case TrainingPeriod.month:
    case TrainingPeriod.camp:
      final weeks = p == TrainingPeriod.month ? 5 : 8;
      final monday = today.subtract(Duration(days: today.weekday - 1));
      final values = <int>[];
      final labels = <String>[];
      for (var i = weeks - 1; i >= 0; i--) {
        final from = monday.subtract(Duration(days: 7 * i));
        values.add(minutesBetween(from, from.add(const Duration(days: 7))));
        labels.add(i == 0 ? 'nu' : '${from.day}/${from.month}');
      }
      return (values, labels);
    case TrainingPeriod.all:
      final values = <int>[];
      final labels = <String>[];
      for (var i = 11; i >= 0; i--) {
        final from = DateTime(today.year, today.month - i, 1);
        final to = DateTime(today.year, today.month - i + 1, 1);
        values.add(minutesBetween(from, to));
        labels.add(monthShort(from.month));
      }
      return (values, labels);
  }
}

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  TrainingPeriod _period = TrainingPeriod.week;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final now = store.now();
    final start = periodStart(_period, now);
    final sessions = store.sessions.where((s) => start == null || !s.startedAt.isBefore(start)).toList();
    final minutes = sessions.fold(0, (sum, s) => sum + s.durationMinutes);
    final safe = timeInRange(sessions.expand((s) => s.glucoseSeries.map((g) => g.mmol)));
    final (bars, labels) = intensitySeries(_period, store.sessions, now);
    final rounds = sessions.fold(0, (sum, s) => sum + s.sparringRounds);
    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: KColor.teal,
        onRefresh: store.refreshAll,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            const Eyebrow('Trainingsvolume & mat-tijd'),
            const SizedBox(height: 4),
            Text('Training Historie', style: KText.display),
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final p in TrainingPeriod.values) ...[
                    KChip(label: p.label, selected: _period == p, onTap: () => setState(() => _period = p)),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            KCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Eyebrow(_period == TrainingPeriod.week ? 'Weekoverzicht' : _period.label, color: KColor.tealLight, icon: Icons.bar_chart),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _Big(label: 'Mat volume', value: durationLabel(minutes))),
                      Expanded(
                        child: _Big(
                          label: 'Glucose safe-zone',
                          value: safe == null ? '—' : '${(safe * 100).round()}%',
                          color: safe == null ? KColor.textMuted : (safe >= 0.7 ? KColor.success : KColor.warning),
                        ),
                      ),
                      Expanded(child: _Big(label: 'Sessies', value: '${sessions.length}')),
                    ],
                  ),
                  const SizedBox(height: 18),
                  IntensityBars(values: bars, labels: labels),
                  const SizedBox(height: 8),
                  Text(
                    'Minuten op de mat${rounds > 0 ? ' • $rounds sparringrondes' : ''} • safe-zone = ${targetLow.toStringAsFixed(1)}-${targetHigh.toStringAsFixed(1)} mmol/L',
                    style: KText.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SectionTitle('Voltooide sessies', trailing: Text('${sessions.length}', style: KText.caption)),
            if (sessions.isEmpty)
              KCard(child: Text('Geen sessies in deze periode.', style: KText.caption)),
            for (final s in sessions) ...[
              _SessionCard(session: s, weightKg: store.currentWeightKg ?? 75),
              const SizedBox(height: 10),
            ],
          ],
        ),
      ),
    );
  }
}

class _Big extends StatelessWidget {
  const _Big({required this.label, required this.value, this.color = KColor.text});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: KText.eyebrow.copyWith(fontSize: 10)),
        const SizedBox(height: 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: KText.metricSmall.copyWith(color: color)),
        ),
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.weightKg});
  final TrainingSession session;
  final double weightKg;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final accent = s.isStrength ? KColor.blue : (s.isCombat ? KColor.danger : KColor.purple);
    final kcal = estimateKcal(minutes: s.durationMinutes, weightKg: weightKg, strength: s.isStrength);
    final safe = s.glucoseSafeZone;
    final ratio = s.successRatio;
    final techniques = s.coveredTechniques;
    return KCard(
      padding: EdgeInsets.zero,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(KRadius.lg)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(s.title, style: KText.subtitle)),
                        Text('${shortDate(s.startedAt)} • ${hhmm(s.startedAt)}', style: KText.caption),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 14,
                      runSpacing: 8,
                      children: [
                        _Fact(Icons.timer_outlined, durationLabel(s.durationMinutes)),
                        _Fact(Icons.local_fire_department_outlined, '~$kcal kcal'),
                        if (s.sparringRounds > 0) _Fact(Icons.sports_mma, '${s.sparringRounds} rondes'),
                        if (ratio != null) _Fact(Icons.track_changes, '${(ratio * 100).round()}% geslaagd'),
                      ],
                    ),
                    if (s.glucoseStart != null) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Text(s.glucoseStart!.toStringAsFixed(1), style: KText.body.copyWith(color: glucoseColor(s.glucoseStart!), fontWeight: FontWeight.w800)),
                          Text('  ➔  ', style: KText.caption),
                          Text(s.glucoseEnd!.toStringAsFixed(1), style: KText.body.copyWith(color: glucoseColor(s.glucoseEnd!), fontWeight: FontWeight.w800)),
                          Text('  mmol/L • laagste ${s.glucoseLowest!.toStringAsFixed(1)}', style: KText.caption),
                          const Spacer(),
                          if (safe != null)
                            KBadge('${(safe * 100).round()}% safe', color: safe >= 0.7 ? KColor.success : KColor.warning, dot: false),
                        ],
                      ),
                    ],
                    if (techniques.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final t in techniques.take(6)) KBadge(t, color: KColor.textSecondary, dot: false),
                          if (techniques.length > 6) KBadge('+${techniques.length - 6}', color: KColor.textMuted, dot: false),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: KColor.textSecondary),
        const SizedBox(width: 4),
        Text(text, style: KText.caption.copyWith(color: KColor.text)),
      ],
    );
  }
}
