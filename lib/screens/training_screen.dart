// training_screen.dart: Training Historie (kinetic_training_dark/light):
// training starten of loggen, filters per discipline en periode, het
// weekoverzicht (mat-tijd, sessies, gemiddelde glucose) met
// intensiteitsgrafiek en de recente sessies met hun glucoseverloop.

import 'package:material_ui/material_ui.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../models/training_session.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/charts.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/food_preset_widgets.dart';
import '../widgets/sheets.dart';
import '../widgets/start_training_sheet.dart';
import '../widgets/training_sheets.dart';
import '../widgets/video_widgets.dart';
import 'log_training_screen.dart';

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

/// Vergelijkbare vorige periode, voor "+45m t.o.v. vorige" (null bij Alle).
(DateTime, DateTime)? _previousWindow(TrainingPeriod p, DateTime now) {
  final start = periodStart(p, now);
  if (start == null) return null;
  return switch (p) {
    TrainingPeriod.week => (start.subtract(const Duration(days: 7)), now.subtract(const Duration(days: 7))),
    TrainingPeriod.month => (start.subtract(const Duration(days: 30)), start),
    TrainingPeriod.camp => (start.subtract(const Duration(days: 56)), start),
    TrainingPeriod.all => null,
  };
}

/// ISO-8601 weeknummer.
int _isoWeek(DateTime d) {
  final date = DateTime.utc(d.year, d.month, d.day);
  final thursday = date.add(Duration(days: 4 - date.weekday));
  return thursday.difference(DateTime.utc(thursday.year, 1, 1)).inDays ~/ 7 + 1;
}

const _weekdays = ['Maandag', 'Dinsdag', 'Woensdag', 'Donderdag', 'Vrijdag', 'Zaterdag', 'Zondag'];

/// "Vandaag, 18:00", "Gisteren, 18:00", "Donderdag 07:30" of "ma 3 nov".
String _sessionDate(DateTime at, DateTime now) {
  final days = dayStart(now).difference(dayStart(at)).inDays;
  if (days == 0) return 'Vandaag, ${hhmm(at)}';
  if (days == 1) return 'Gisteren, ${hhmm(at)}';
  if (days > 1 && days < 7) return '${_weekdays[at.weekday - 1]} ${hhmm(at)}';
  return '${shortDate(at)} • ${hhmm(at)}';
}

/// Toon per discipline (tag-kleur van de sessiekaart).
KTone _disciplineTone(TrainingSession s) {
  final t = s.title.toLowerCase();
  if (s.isStrength || t.contains('kracht')) return KTone.info;
  if (t.contains('bjj') || t.contains('judo')) return KTone.purple;
  if (t.contains('sambo')) return KTone.primary;
  return KTone.neutral;
}

/// Focus uit de notitie ("Focus: Sparring • RPE 4/5") of afgeleid uit de blokken.
String _sessionFocus(TrainingSession s) {
  final m = RegExp(r'Focus: ([^•\n]+)').firstMatch(s.note);
  if (m != null) return m.group(1)!.trim();
  if (s.sparringRounds > 0) return 'Sparring';
  if (s.isStrength) return 'Kracht';
  if (s.coveredTechniques.isNotEmpty) return 'Techniek';
  return '';
}

int? _sessionRpe(TrainingSession s) {
  final m = RegExp(r'RPE (\d)/5').firstMatch(s.note);
  return m == null ? null : int.parse(m.group(1)!);
}

/// Vrije notities (zonder de "Focus: ..."-regel).
String _sessionNotes(TrainingSession s) =>
    s.note.split('\n').where((l) => !l.startsWith('Focus: ') && l.trim().isNotEmpty).join('\n');

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key});

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  TrainingPeriod _period = TrainingPeriod.week;

  /// Discipline-filter (kleine letters), null = alle.
  String? _discipline;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final now = store.now();

    // Disciplines uit de historie (eerste schrijfwijze wint).
    final disciplines = <String, String>{};
    for (final s in store.sessions) {
      final key = s.title.trim().toLowerCase();
      if (key.isNotEmpty) disciplines.putIfAbsent(key, () => s.title.trim());
    }
    final discipline = disciplines.containsKey(_discipline) ? _discipline : null;
    final ofDiscipline = store.sessions
        .where((s) => discipline == null || s.title.trim().toLowerCase() == discipline)
        .toList();

    final start = periodStart(_period, now);
    final sessions = ofDiscipline.where((s) => start == null || !s.startedAt.isBefore(start)).toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    final minutes = sessions.fold(0, (sum, s) => sum + s.durationMinutes);
    final prev = _previousWindow(_period, now);
    final prevMinutes = prev == null
        ? null
        : ofDiscipline
              .where((s) => !s.startedAt.isBefore(prev.$1) && s.startedAt.isBefore(prev.$2))
              .fold(0, (sum, s) => sum + s.durationMinutes);
    final glucose = sessions.expand((s) => s.glucoseSeries.map((g) => g.mmol)).toList();
    final avg = glucose.isEmpty ? null : glucose.reduce((a, b) => a + b) / glucose.length;
    final tir = timeInRange(glucose);
    final rounds = sessions.fold(0, (sum, s) => sum + s.sparringRounds);
    final (bars, labels) = intensitySeries(_period, ofDiscipline, now);

    final overviewTitle = switch (_period) {
      TrainingPeriod.week => 'Weekoverzicht • W${_isoWeek(now)}',
      TrainingPeriod.month => 'Maandoverzicht • 30 dagen',
      TrainingPeriod.camp => 'Fight camp • 8 weken',
      TrainingPeriod.all => 'Alle trainingen',
    };
    String? deltaLabel;
    if (prevMinutes != null) {
      final d = minutes - prevMinutes;
      deltaLabel = d == 0
          ? 'Gelijk aan vorige'
          : '${d > 0 ? '+' : '−'}${d.abs() >= 60 ? durationLabel(d.abs()) : '${d.abs()}m'} t.o.v. vorige';
    }

    return RefreshIndicator(
      color: k.primary,
      backgroundColor: k.surface,
      onRefresh: store.refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pagePadding(context, top: 16),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Training Historie', style: context.t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('Belasting & glycemie', style: context.t.caption),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: k.surface,
                  foregroundColor: k.text,
                  side: BorderSide(color: k.border),
                  textStyle: context.t.bodyStrong,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const LogTrainingScreen()),
                ),
                icon: Icon(Icons.edit_note, size: 20, color: k.accent),
                label: const Text('Loggen'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (store.isTrainingActive)
            BigButton(
              label: 'Terug naar de training',
              icon: Icons.sports_mma,
              height: 56,
              onPressed: () => openLiveSession(context),
            )
          else
            BigButton(
              label: 'Training starten',
              icon: Icons.play_arrow_rounded,
              height: 56,
              onPressed: () => showStartTrainingSheet(context),
            ),
          const SizedBox(height: 12),
          const PresetManagerCard(training: true),
          const SizedBox(height: 16),
          _ChipRow(
            children: [
              KChip(
                label: 'Alle sporten',
                selected: discipline == null,
                onTap: () => setState(() => _discipline = null),
              ),
              for (final e in disciplines.entries)
                KChip(
                  label: e.value,
                  selected: discipline == e.key,
                  onTap: () => setState(() => _discipline = e.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _ChipRow(
            children: [
              for (final p in TrainingPeriod.values)
                KChip(
                  label: p.label,
                  icon: p == _period ? Icons.calendar_today_outlined : null,
                  selected: _period == p,
                  color: _period == p ? k.text : null,
                  onTap: () => setState(() => _period = p),
                ),
            ],
          ),
          const SizedBox(height: 16),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.insert_chart_outlined, size: 20, color: k.accent),
                    const SizedBox(width: 8),
                    Expanded(child: Eyebrow(overviewTitle)),
                    if (tir != null)
                      KPill(
                        tir >= 0.7 ? 'In veilige zone' : 'Let op glucose',
                        tone: tir >= 0.7 ? KTone.success : KTone.warning,
                        dot: true,
                        dense: true,
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: MetricTile(
                          inWell: true,
                          label: 'Mat tijd',
                          value: durationLabel(minutes),
                          sub: deltaLabel ?? '${sessions.length} sessies',
                          subColor: prevMinutes == null || minutes == prevMinutes
                              ? null
                              : (minutes > prevMinutes ? k.successInk : k.warningInk),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricTile(
                          inWell: true,
                          label: 'Sessies',
                          value: '${sessions.length}',
                          sub: rounds > 0 ? '$rounds rondes' : _period.label,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: MetricTile(
                          inWell: true,
                          label: 'Glucose',
                          value: avg == null ? '—' : dec1(avg),
                          valueColor: avg == null ? k.textMuted : zoneInk(k, avg),
                          sub: tir == null ? 'Geen CGM-data' : '${(tir * 100).round()}% in bereik',
                          subColor: tir == null ? k.textMuted : (tir >= 0.7 ? k.successInk : k.warningInk),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                IntensityBars(values: bars, labels: labels),
                const SizedBox(height: 8),
                Text(
                  'Minuten op de mat • doelbereik ${dec1(targetLow)}–${dec1(targetHigh)} mmol/L',
                  style: context.t.caption,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SectionTitle(
            'Recente sessies',
            trailing: Text(
              '${_period == TrainingPeriod.all ? 'Alle' : _period.label} • ${sessions.length}',
              style: context.t.caption,
            ),
          ),
          if (sessions.isEmpty)
            KCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Geen sessies in deze periode', style: context.t.bodyStrong),
                  const SizedBox(height: 4),
                  Text(
                    'Start een training met de rondeklok of log er achteraf een.',
                    style: context.t.caption,
                  ),
                ],
              ),
            ),
          for (final s in sessions) ...[
            _SessionCard(session: s, now: now, weightKg: store.currentWeightKg ?? 75),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }
}

class _ChipRow extends StatelessWidget {
  const _ChipRow({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ sessiekaart

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.session, required this.now, required this.weightKg});
  final TrainingSession session;
  final DateTime now;
  final double weightKg;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final k = context.k;
    final focus = _sessionFocus(s);
    final rpe = _sessionRpe(s);
    final kcal = estimateKcal(minutes: s.durationMinutes, weightKg: weightKg, strength: s.isStrength);
    final ratio = s.successRatio;
    final techniques = s.coveredTechniques;
    final traj = GlucoseTrajectory.of(s.glucoseSeries);
    return KCard(
      onTap: () => _showDetails(context, s, now),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Flexible(child: KPill(s.title, tone: _disciplineTone(s))),
              if (focus.isNotEmpty) ...[
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '• $focus',
                    style: context.t.subtitle.copyWith(color: k.textSecondary, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const Spacer(),
              Text('Details', style: context.t.caption),
              Icon(Icons.chevron_right, size: 18, color: k.textSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.timer_outlined, size: 20, color: k.text),
              const SizedBox(width: 6),
              Text('${s.durationMinutes} min', style: context.t.subtitle.copyWith(fontWeight: FontWeight.w700)),
              if (rpe != null) ...[
                const SizedBox(width: 10),
                KPill('RPE $rpe/5', dense: true),
              ],
              if (s.sparringRounds > 0) ...[
                const SizedBox(width: 6),
                KPill('${s.sparringRounds} rondes', dense: true),
              ],
              const Spacer(),
              Text(_sessionDate(s.startedAt, now), style: context.t.caption),
            ],
          ),
          const SizedBox(height: 4),
          Text('~$kcal kcal (schatting)', style: context.t.caption.copyWith(color: k.textMuted)),
          const SizedBox(height: 12),
          _GlucoseWell(trajectory: traj),
          if (techniques.isNotEmpty || ratio != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Geregistreerd:', style: context.t.caption),
                for (final t in techniques.take(5)) KPill(t, dense: true),
                if (techniques.length > 5) KPill('+${techniques.length - 5}', dense: true),
                if (ratio != null)
                  KPill(
                    '${(ratio * 100).round()}% geslaagd',
                    tone: ratio >= 0.5 ? KTone.success : KTone.warning,
                    icon: Icons.track_changes,
                    dense: true,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static Future<void> _showDetails(BuildContext context, TrainingSession s, DateTime now) {
    return showKineticSheet<void>(
      context,
      builder: (ctx) {
        final k = ctx.k;
        // Live uit de store, zodat aanpassingen aan de voeding meteen zichtbaar zijn.
        final store = KineticScope.of(ctx);
        final cur = store.sessions.where((x) => x.id == s.id).firstOrNull ?? s;
        final notes = _sessionNotes(s);
        final warmups = s.blocks.where((b) => b['kind'] == 'warmup').toList();
        final spars = s.blocks.where((b) => b['kind'] == 'sparring' && (b['goal'] != null || b['round_goals'] != null)).toList();
        final techLogs = s.blocks
            .where((b) => b['kind'] == 'technique' && (((b['reps'] as num?) ?? 0) > 0 || ((b['seconds'] as num?) ?? 0) > 0 || b['measure'] != null))
            .toList();
        final combos = s.blocks.where((b) => b['kind'] == 'combination').toList();
        final results = s.techniqueResults;
        final rpe = _sessionRpe(s);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.title, style: ctx.t.headline),
            const SizedBox(height: 4),
            Text(
              [
                _sessionDate(s.startedAt, now),
                durationLabel(s.durationMinutes),
                if (_sessionFocus(s).isNotEmpty) _sessionFocus(s),
                if (rpe != null) 'RPE $rpe/5',
              ].join(' • '),
              style: ctx.t.caption,
            ),
            const SizedBox(height: 16),
            _GlucoseWell(trajectory: GlucoseTrajectory.of(s.glucoseSeries), height: 64),
            if (results.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Technieken op de mat'),
              for (final r in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KWell(
                    child: Row(
                      children: [
                        Expanded(child: Text(r.name, style: ctx.t.bodyStrong)),
                        Text(
                          '${r.counts.success} ${r.striking ? 'clean' : 'geslaagd'} • ${r.counts.attempts} pogingen • ${r.counts.countered} ${r.striking ? 'tegen' : 'gecounterd'}',
                          style: ctx.t.caption,
                        ),
                      ],
                    ),
                  ),
                ),
            ] else if (s.coveredTechniques.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Technieken'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final t in s.coveredTechniques) KPill(t)],
              ),
            ],
            if (warmups.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Warming-up'),
              for (final w in warmups)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KWell(child: Text('${w['minutes'] ?? '?'} min', style: ctx.t.bodyStrong)),
                ),
            ],
            if (spars.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Sparren & doelen'),
              for (final b in spars)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KWell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${b['rounds'] ?? 0} rondes', style: ctx.t.bodyStrong),
                        if ((b['goal'] as String? ?? '').isNotEmpty)
                          _GoalLine(text: 'Doel: ${b['goal']}', done: b['goal_done'] == true),
                        for (final g in (b['round_goals'] as List? ?? const []))
                          if (g is Map) _GoalLine(text: '${g['goal']}', done: g['done'] == true),
                      ],
                    ),
                  ),
                ),
            ],
            if (techLogs.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Technieken gelogd'),
              for (final b in techLogs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: KWell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('${b['name']}', style: ctx.t.bodyStrong)),
                            Text(
                              b['measure'] == 'time'
                                  ? durationLabel((((b['seconds'] as num?) ?? 0) ~/ 60).toInt())
                                  : '${b['reps'] ?? 0} reps',
                              style: ctx.t.caption,
                            ),
                          ],
                        ),
                        if ((b['note'] as String? ?? '').trim().isNotEmpty)
                          Text('${b['note']}', style: ctx.t.caption.copyWith(color: k.text)),
                        if (store.techniques.where((t) => t.id == b['technique_id']).firstOrNull case final tech?
                            when tech.videoUrls.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          VideoList(urls: tech.videoUrls, dense: true),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
            if (combos.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Combinaties'),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final c in combos) KPill('${c['name']} • ${c['reps'] ?? 1}×')],
              ),
            ],
            if (cur.nutrition.isNotEmpty) ...[
              const SizedBox(height: 20),
              FormLabel(
                'Voeding tijdens de training',
                trailing: '${grams(cur.nutrition.fold<double>(0, (a, n) => a + n.carbs))} g koolh.',
                trailingColor: k.accent,
              ),
              NutritionLogList(
                items: cur.nutrition,
                onCount: (n, c) => store.updateSessionNutrition(s.id, id: n.id, count: c),
                onTime: (n, at) => store.updateSessionNutrition(s.id, id: n.id, at: at),
                onDelete: (n) => store.updateSessionNutrition(s.id, id: n.id, delete: true),
              ),
            ],
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 20),
              const FormLabel('Notities'),
              KWell(child: Text(notes, style: ctx.t.body.copyWith(color: k.text))),
            ],
          ],
        );
      },
    );
  }
}

class _GoalLine extends StatelessWidget {
  const _GoalLine({required this.text, required this.done});
  final String text;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? k.success : k.textMuted),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: context.t.caption.copyWith(color: k.text))),
        ],
      ),
    );
  }
}

/// "Glucoseverloop": start / piek of dip / eind, sparkline en status.
class _GlucoseWell extends StatelessWidget {
  const _GlucoseWell({required this.trajectory, this.height = 40});
  final GlucoseTrajectory? trajectory;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final t = trajectory;
    if (t == null) {
      return KWell(
        child: Row(
          children: [
            Icon(Icons.show_chart, size: 18, color: k.textMuted),
            const SizedBox(width: 8),
            Expanded(child: Text('Geen glucosedata voor deze sessie', style: context.t.caption)),
          ],
        ),
      );
    }
    final (status, tone) = t.status;
    final (_, statusFg) = toneColors(k, tone);
    final tir = t.inRange;
    Widget value(String label, double mmol, CrossAxisAlignment align, {String? arrow}) => Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: context.t.caption),
        const SizedBox(height: 2),
        Text(
          '${dec1(mmol)}${arrow == null ? '' : ' $arrow'}',
          style: context.t.metricSm.copyWith(color: zoneFor(mmol) == GlucoseZone.inTarget ? k.text : zoneInk(k, mmol)),
        ),
      ],
    );
    return KWell(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, size: 16, color: k.textSecondary),
              const SizedBox(width: 6),
              Text('Glucoseverloop', style: context.t.caption),
              const Spacer(),
              Container(width: 7, height: 7, decoration: BoxDecoration(color: statusFg, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(status, style: context.t.caption.copyWith(color: statusFg, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: value('Start', t.start, CrossAxisAlignment.start)),
              Expanded(
                child: value(
                  t.middleLabel,
                  t.middle,
                  CrossAxisAlignment.center,
                  arrow: t.dipDominant ? '↘' : (t.high - t.start >= 0.3 ? '↗' : null),
                ),
              ),
              Expanded(child: value('Eind', t.end, CrossAxisAlignment.end)),
            ],
          ),
          const SizedBox(height: 10),
          GlucoseSparkline(points: t.points, height: height),
          if (tir != null) ...[
            const SizedBox(height: 6),
            Text(
              '${(tir * 100).round()}% in doelbereik • Δ ${t.delta >= 0 ? '+' : '−'}${dec1(t.delta.abs())} mmol/L',
              style: context.t.caption.copyWith(color: k.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
