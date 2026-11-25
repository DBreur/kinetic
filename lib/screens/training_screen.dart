// training_screen.dart: Sessie Historie (kinetic_training_historie_
// interactief_dark_mode): training starten of loggen, periode- en
// disciplinefilters, de volumekaart (mat-tijd, glucose safe-zone, sessies,
// rondes) met intensiteitsgrafiek, trainingspresets en de voltooide sessies.

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

    final sparSessions = sessions.where((s) => s.sparringRounds > 0).length;

    return RefreshIndicator(
      color: k.primary,
      backgroundColor: k.surface,
      onRefresh: store.refreshAll,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pagePadding(context, top: 8),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('LOGBOEK TELEMETRIE', style: context.t.labelSm.copyWith(color: k.accent, letterSpacing: 0.8)),
                    const SizedBox(height: 2),
                    Text('Sessie Historie', style: context.t.headline, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  backgroundColor: k.well,
                  foregroundColor: k.text,
                  side: BorderSide.none,
                  textStyle: context.t.bodyStrong,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(KRadius.sm)),
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
              label: 'Start Nieuwe Trainingssessie',
              icon: Icons.play_circle_outline,
              height: 56,
              fitLabel: true,
              color: k.accent,
              foreground: k.onPrimary,
              onPressed: () => showStartTrainingSheet(context),
            ),
          const SizedBox(height: 16),
          KSegmented<TrainingPeriod>(
            options: [for (final p in TrainingPeriod.values) (p, p == TrainingPeriod.camp ? 'Camp (8w)' : p.label)],
            value: _period,
            onChanged: (p) => setState(() => _period = p),
          ),
          if (disciplines.length > 1) ...[
            const SizedBox(height: 10),
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
          ],
          const SizedBox(height: 16),
          KCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                              Container(width: 8, height: 8, decoration: BoxDecoration(color: k.accent, shape: BoxShape.circle)),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  overviewTitle.toUpperCase(),
                                  style: context.t.labelSm.copyWith(color: k.textSecondary, letterSpacing: 0.6),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              durationLabel(minutes),
                              style: context.t.metric.copyWith(color: k.accent, fontSize: 48),
                            ),
                          ),
                          if (deltaLabel != null)
                            Row(
                              children: [
                                Icon(
                                  prevMinutes != null && minutes < prevMinutes ? Icons.trending_down : Icons.trending_up,
                                  size: 16,
                                  color: prevMinutes != null && minutes < prevMinutes ? k.warningInk : k.successInk,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    deltaLabel,
                                    style: context.t.caption.copyWith(
                                      color: prevMinutes != null && minutes < prevMinutes ? k.warningInk : k.successInk,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Glucose safe-zone', style: context.t.caption),
                        const SizedBox(height: 2),
                        Text(
                          tir == null ? '—' : '${(tir * 100).round()}%',
                          style: context.t.metricSm.copyWith(
                            color: tir == null ? k.textMuted : (tir >= 0.7 ? k.successInk : k.warningInk),
                          ),
                        ),
                        if (avg != null) ...[
                          const SizedBox(height: 2),
                          Text('gem. ${dec1(avg)} mmol/L', style: context.t.caption),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _VolumeTile(
                          icon: Icons.sports_mma,
                          label: 'Sessies',
                          value: '${sessions.length} ${sessions.length == 1 ? 'sessie' : 'sessies'}',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _VolumeTile(
                          icon: Icons.sports_kabaddi,
                          label: 'Sparring',
                          value: rounds > 0 ? '$rounds rondes' : '$sparSessions sessies',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(child: Text('Dagen & intensiteit (minuten)', style: context.t.caption.copyWith(fontWeight: FontWeight.w600))),
                    Text(
                      'Doel ${dec1(targetLow)}–${dec1(targetHigh)}',
                      style: context.t.caption.copyWith(color: k.accent, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
                  decoration: BoxDecoration(
                    color: k.isDark ? KineticColors.sunken : k.well,
                    borderRadius: BorderRadius.circular(KRadius.md),
                  ),
                  child: IntensityBars(values: bars, labels: labels),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const PresetManagerCard(training: true),
          const SizedBox(height: 24),
          SectionTitle(
            'Voltooide Trainingssessies',
            trailing: Text(
              '${sessions.length} getoond',
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

/// Well-tegel in de volumekaart ("Sparring • 4 sessies").
class _VolumeTile extends StatelessWidget {
  const _VolumeTile({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KWell(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: k.isDark ? KineticColors.sunken : k.surface,
              borderRadius: BorderRadius.circular(KRadius.sm),
            ),
            child: Icon(icon, size: 20, color: k.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: context.t.caption),
                Text(value, style: context.t.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
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

/// Rechthoekige tag ("MMA", "BJJ Gi") linksboven op een sessiekaart.
class _TagPill extends StatelessWidget {
  const _TagPill(this.text, {required this.tone});
  final String text;
  final KTone tone;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = toneColors(context.k, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(
        text,
        style: context.t.caption.copyWith(color: fg, fontWeight: FontWeight.w700),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// Statistiekcel in een sessiekaart: label boven, waarde eronder.
class _StatCell extends StatelessWidget {
  const _StatCell({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
      decoration: BoxDecoration(color: k.well, borderRadius: BorderRadius.circular(KRadius.sm)),
      child: Column(
        children: [
          Text(label, style: context.t.caption, maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: context.t.bodyStrong.copyWith(color: color ?? k.text, fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
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
    final subtitle = [
      if (s.sparringRounds > 0) '${s.sparringRounds} rondes',
      if (rpe != null) 'RPE $rpe/5',
      if (techniques.isNotEmpty) techniques.take(3).join(', ') + (techniques.length > 3 ? ' +${techniques.length - 3}' : ''),
    ].join(' • ');
    Color? glucoseInk(double v) => zoneInk(k, v);
    return KCard(
      onTap: () => _showDetails(context, s, now),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: _TagPill(s.title, tone: _disciplineTone(s)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _sessionDate(s.startedAt, now),
                  style: context.t.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.check_circle_outline, size: 16, color: k.successInk, semanticLabel: 'Voltooid'),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right, size: 20, color: k.textSecondary),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            focus.isEmpty ? s.title : '${s.title} • $focus',
            style: context.t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(subtitle, style: context.t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _StatCell(label: 'Duur', value: '${s.durationMinutes} min')),
              const SizedBox(width: 8),
              Expanded(child: _StatCell(label: 'Verbrand', value: '$kcal kcal', color: k.accent)),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCell(
                  label: 'Glucose',
                  value: traj == null ? '—' : '${dec1(traj.start)}→${dec1(traj.end)}',
                  color: traj == null ? k.textMuted : glucoseInk(traj.end),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ratio != null
                    ? _StatCell(
                        label: 'Geslaagd',
                        value: '${(ratio * 100).round()}%',
                        color: ratio >= 0.5 ? k.successInk : k.warningInk,
                      )
                    : _StatCell(
                        label: traj == null ? 'Rondes' : traj.middleLabel,
                        value: traj == null ? '${s.sparringRounds}' : dec1(traj.middle),
                        color: traj == null ? null : glucoseInk(traj.middle),
                      ),
              ),
            ],
          ),
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
