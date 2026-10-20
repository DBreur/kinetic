// session_detail_screen.dart — bekijk een opgeslagen training
//
// Toont de glucosecurve van de sessie (tik op een punt voor tijd + waarde,
// tijdlabels om het half uur), de behandelde blokken/oefeningen en de
// notitie. Aanpassen (technieken toevoegen/wijzigen, notitie, verwijderen)
// gebeurt in session_edit_screen.dart, bereikbaar via "Aanpassen" hierboven.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../core/formatters.dart';
import '../models/training_session.dart';
import '../repositories/session_repository.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/nutrition_log.dart';
import 'session_edit_screen.dart';

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({
    super.key,
    required this.session,
    required this.repository,
    required this.controller,
  });

  final TrainingSession session;
  final SessionRepository repository;
  final AppController controller;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late TrainingSession _session;
  int? _pointIdx;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
  }

  Future<void> _openEdit() async {
    final result = await Navigator.push<SessionEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => SessionEditScreen(
          session: _session,
          repository: widget.repository,
          controller: widget.controller,
        ),
      ),
    );
    if (result == null) return;
    if (result.deleted) {
      if (mounted) Navigator.pop(context, true);
      return;
    }
    setState(() {
      _session = result.session!;
      _changed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _session;
    final low = s.lowestMmol;
    return PopScope(
      // canPop: false zodat ook het systeem-terugpijltje/-gebaar (dat via
      // maybePop loopt, niet via onPressed hieronder) het _changed-resultaat
      // meegeeft — anders ziet de lijst een hernoemde titel pas na handmatig
      // verversen.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        Navigator.pop(context, _changed);
      },
      child: Scaffold(
        backgroundColor: AppColor.bg,
        appBar: AppBar(
          backgroundColor: AppColor.bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          leading: BackButton(
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(
            s.title,
            style: AppText.bodyStrong.copyWith(fontSize: 14),
          ),
          actions: [
            TextButton(onPressed: _openEdit, child: const Text('Aanpassen')),
          ],
        ),
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            20,
            18,
            20,
            24 + MediaQuery.of(context).padding.bottom,
          ),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColor.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('GLUCOSEVERLOOP', style: AppText.overline),
                      const Spacer(),
                      Text(
                        dutchShortDate(s.startedAt),
                        style: AppText.caption.copyWith(fontSize: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (s.glucoseSeries.length < 2)
                    Text(
                      'Geen glucoseverloop vastgelegd voor deze training.',
                      style: AppText.caption,
                    )
                  else ...[
                    if (_pointIdx != null)
                      GestureDetector(
                        onTap: () => setState(() => _pointIdx = null),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                mmolText(s.glucoseSeries[_pointIdx!].mmol),
                                style: AppText.display.copyWith(
                                  fontSize: 26,
                                  color: glucoseColor(
                                    glucoseStateFor(
                                      s.glucoseSeries[_pointIdx!].mmol,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'mmol/L om ${DateFormat('HH:mm', 'nl_NL').format(s.glucoseSeries[_pointIdx!].at)}',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Tik op een punt voor tijd en waarde.',
                          style: AppText.caption,
                        ),
                      ),
                    SizedBox(
                      height: 132,
                      child: _SessionCurve(
                        series: s.glucoseSeries,
                        selected: _pointIdx,
                        onPick: (i) => setState(() => _pointIdx = i),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _Stat(
                          label: 'start',
                          value: mmolText(s.firstMmol ?? 0),
                        ),
                        const SizedBox(width: 18),
                        _Stat(
                          label: 'laagste',
                          value: mmolText(low ?? 0),
                          color: s.hadDip ? AppColor.amberBright : null,
                        ),
                        const SizedBox(width: 18),
                        _Stat(label: 'eind', value: mmolText(s.lastMmol ?? 0)),
                        const SizedBox(width: 18),
                        _Stat(label: 'duur', value: '${s.durationMinutes}′'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (s.kind == SessionKind.sambo && s.blocks.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('BEHANDELD', style: AppText.overline),
              const SizedBox(height: 10),
              for (final b in s.blocks) _BlockCard(block: b),
            ],
            if (s.kind == SessionKind.kracht && s.exercises.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('OEFENINGEN', style: AppText.overline),
              const SizedBox(height: 10),
              for (final e in s.exercises) _ExerciseSummary(entry: e),
            ],
            if (s.circuits.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('CIRCUITS', style: AppText.overline),
              const SizedBox(height: 10),
              for (final c in s.circuits) _CircuitSummary(circuit: c),
            ],
            if (s.nutrition.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('VOEDING TIJDENS TRAINING', style: AppText.overline),
              const SizedBox(height: 10),
              NutritionLogList(entries: s.nutrition),
            ],
            const SizedBox(height: 20),
            Text('NOTITIE OVER DE TRAINING', style: AppText.overline),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColor.surface,
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: Text(
                s.note.trim().isNotEmpty ? s.note : 'Nog geen notitie',
                style: AppText.body.copyWith(
                  color: s.note.trim().isNotEmpty
                      ? AppColor.ink.withValues(alpha: .85)
                      : AppColor.inkGhost,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.caption.copyWith(fontSize: 10)),
        Text(
          value,
          style: AppText.cardTitle.copyWith(fontSize: 14, color: color),
        ),
      ],
    );
  }
}

class _BlockCard extends StatelessWidget {
  const _BlockCard({required this.block});
  final SessionBlock block;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(block.name, style: AppText.bodyStrong)),
              if (block.rating > 0)
                Text(
                  '★' * block.rating,
                  style: AppText.caption.copyWith(color: AppColor.amberBright),
                ),
            ],
          ),
          if (_metaLine.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(_metaLine, style: AppText.caption),
          ],
          if (block.goals.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [for (final g in block.goals) _GoalPill(goal: g)],
            ),
          ],
          if (block.roundGoals.any((g) => g.isNotEmpty) ||
              block.roundRestrictions.any((r) => r.isNotEmpty)) ...[
            const SizedBox(height: 6),
            for (var i = 0; i < block.roundMinutes.length; i++)
              if (_roundItems(block.roundGoals, i).isNotEmpty ||
                  _roundItems(block.roundRestrictions, i).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ronde ${i + 1}',
                        style: AppText.caption.copyWith(fontSize: 10),
                      ),
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: [
                          for (final r in _roundItems(
                            block.roundRestrictions,
                            i,
                          ))
                            _RestrictionPill(restriction: r),
                          for (final g in _roundItems(block.roundGoals, i))
                            _GoalPill(goal: g),
                        ],
                      ),
                    ],
                  ),
                ),
          ],
          if (block.note.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              block.note,
              style: AppText.body.copyWith(
                color: AppColor.inkMuted,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String get _metaLine {
    if (block.kind == BlockKind.technique) {
      return block.minutes > 0
          ? (block.meta.isNotEmpty
                ? '${block.meta} · ${block.minutes} min'
                : '${block.minutes} min')
          : block.meta;
    }
    if (block.roundMinutes.isNotEmpty) {
      final total = block.roundMinutes.fold(0, (a, b) => a + b);
      var line = '$total min · ${block.roundMinutes.length} rondes';
      if (block.restSeconds.isNotEmpty &&
          block.restSeconds.toSet().length == 1) {
        line += ' · ${block.restSeconds.first}s rust';
      }
      return line;
    }
    return block.rounds > 0
        ? '${block.minutes} min · ${block.rounds} rondes'
        : '${block.minutes} min';
  }
}

/// Doel uit een opgeslagen sessie — alleen-lezen, met een vinkje als het
/// bereikt is.
List<SparGoal> _roundItems(List<List<SparGoal>> perRound, int i) =>
    i < perRound.length ? perRound[i] : const [];

/// Beperking van een ronde (startpositie of wat niet mocht).
class _RestrictionPill extends StatelessWidget {
  const _RestrictionPill({required this.restriction});

  final SparGoal restriction;

  @override
  Widget build(BuildContext context) {
    final isStart = restriction.text.toLowerCase().startsWith('start');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColor.surfaceHigh,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            restriction.achieved
                ? Icons.verified
                : (isStart ? Icons.flag_outlined : Icons.block),
            size: 12,
            color: restriction.achieved ? AppColor.ice : AppColor.coralSoft,
          ),
          const SizedBox(width: 4),
          Text(
            restriction.text,
            style: AppText.caption.copyWith(fontSize: 11, color: AppColor.ink),
          ),
        ],
      ),
    );
  }
}

class _GoalPill extends StatelessWidget {
  const _GoalPill({required this.goal});
  final SparGoal goal;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .05),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            goal.achieved ? Icons.check_circle : Icons.circle_outlined,
            size: 12,
            color: goal.achieved ? AppColor.greenBright : AppColor.inkFaint,
          ),
          const SizedBox(width: 5),
          Text(
            goal.text,
            style: AppText.caption.copyWith(
              fontSize: 10,
              color: goal.achieved ? AppColor.inkFaint : null,
              decoration: goal.achieved ? TextDecoration.lineThrough : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseSummary extends StatelessWidget {
  const _ExerciseSummary({required this.entry});
  final ExerciseEntry entry;

  /// Sets met meer dan kg × reps (tijd, verzuring, gelukt/reden) krijgen
  /// elk een eigen regel; anders blijft het één compacte regel.
  bool get _detailed => entry.sets.any(
    (s) =>
        s.seconds != null ||
        s.toBurn ||
        s.completed != null ||
        s.note.isNotEmpty,
  );

  @override
  Widget build(BuildContext context) {
    final summary = entry.sets.isEmpty
        ? '—'
        // Hier alleen gewone reps-sets (tijd/verzuring krijgen hieronder
        // een eigen regel per set, zie _detailed).
        : '${entry.sets.length} × ${entry.sets.map((s) => s.reps).join('/')}'
              '${entry.sets.first.kg > 0 ? ' · ${mmolText(entry.sets.first.kg)} kg' : ''}';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: !_detailed
          ? Row(
              children: [
                Expanded(child: Text(entry.name, style: AppText.bodyStrong)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    summary,
                    style: AppText.caption,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.name, style: AppText.bodyStrong),
                const SizedBox(height: 6),
                for (var i = 0; i < entry.sets.length; i++)
                  _SetLine(index: i, set: entry.sets[i]),
              ],
            ),
    );
  }
}

class _SetLine extends StatelessWidget {
  const _SetLine({required this.index, required this.set});
  final int index;
  final ExerciseSet set;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                child: Text('${index + 1}', style: AppText.caption),
              ),
              if (set.toBurn)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(
                    Icons.local_fire_department_outlined,
                    size: 14,
                    color: AppColor.amber,
                  ),
                ),
              Expanded(
                child: Text(
                  set.summary,
                  style: AppText.caption.copyWith(color: AppColor.ink),
                ),
              ),
              if (set.completed != null)
                Text(
                  set.completed! ? 'gelukt' : 'niet gelukt',
                  style: AppText.caption.copyWith(
                    color: set.completed!
                        ? AppColor.greenBright
                        : AppColor.redBright,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          if (set.note.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 20, top: 1),
              child: Text(
                set.note,
                style: AppText.caption.copyWith(fontStyle: FontStyle.italic),
              ),
            ),
        ],
      ),
    );
  }
}

class _CircuitSummary extends StatelessWidget {
  const _CircuitSummary({required this.circuit});
  final Circuit circuit;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(circuit.name, style: AppText.bodyStrong),
          const SizedBox(height: 2),
          Text(
            '${circuit.stepsLabel} · ${circuit.rounds} '
            'ronde${circuit.rounds == 1 ? '' : 's'}'
            '${circuit.restSeconds > 0 ? ' · ${circuit.restSeconds}s rust' : ''}',
            style: AppText.caption,
          ),
        ],
      ),
    );
  }
}

class _SessionCurve extends StatelessWidget {
  const _SessionCurve({
    required this.series,
    required this.selected,
    required this.onPick,
  });

  final List<GlucosePoint> series;
  final int? selected;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final w = constraints.maxWidth;
            final dx = series.length > 1 ? w / (series.length - 1) : 0.0;
            if (dx == 0) return;
            final idx = (details.localPosition.dx / dx).round().clamp(
              0,
              series.length - 1,
            );
            onPick(idx);
          },
          child: CustomPaint(
            size: Size(constraints.maxWidth, constraints.maxHeight),
            painter: _CurvePainter(series, selected),
          ),
        );
      },
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter(this.series, this.selected);
  final List<GlucosePoint> series;
  final int? selected;

  static const _min = 2.0, _max = 14.0, _lo = 3.9, _hi = 10.0;

  double _y(double v, double h) =>
      h - ((v.clamp(_min, _max) - _min) / (_max - _min)) * h;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.length < 2) return;
    final h = size.height - 18;

    canvas.drawRect(
      Rect.fromLTRB(0, _y(_hi, h), size.width, _y(_lo, h)),
      Paint()..color = AppColor.green.withValues(alpha: .10),
    );

    final dx = size.width / (series.length - 1);
    final path = Path()..moveTo(0, _y(series.first.mmol, h));
    for (var i = 1; i < series.length; i++) {
      path.lineTo(dx * i, _y(series[i].mmol, h));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColor.green
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    if (selected != null) {
      final sx = dx * selected!;
      canvas.drawLine(
        Offset(sx, 0),
        Offset(sx, h),
        Paint()
          ..color = AppColor.greenBright.withValues(alpha: .55)
          ..strokeWidth = 1.5,
      );
    }

    for (var i = 0; i < series.length; i++) {
      final isSel = i == selected;
      canvas.drawCircle(
        Offset(dx * i, _y(series[i].mmol, h)),
        isSel ? 5 : 2.5,
        Paint()..color = isSel ? AppColor.greenBright : AppColor.green,
      );
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final i in _tickIndices()) {
      tp.text = TextSpan(
        text: DateFormat('HH:mm', 'nl_NL').format(series[i].at),
        style: AppText.caption.copyWith(fontSize: 9),
      );
      tp.layout();
      final x = (dx * i).clamp(tp.width / 2, size.width - tp.width / 2);
      tp.paint(canvas, Offset(x - tp.width / 2, size.height - 14));
    }
  }

  /// Kiest tijdstippen om het half uur (of vaker bij een korte sessie) en
  /// zoekt daar de dichtstbijzijnde meting bij, in plaats van gewoon om de
  /// zoveel metingen — die komen niet altijd op een vaste interval binnen.
  List<int> _tickIndices() {
    final start = series.first.at;
    final end = series.last.at;
    final totalMinutes = end.difference(start).inMinutes;
    final stepMinutes = totalMinutes <= 40
        ? 10
        : (totalMinutes <= 90 ? 15 : 30);

    final indices = <int>[];
    var cursor = 0;
    for (var mark = 0; mark <= totalMinutes; mark += stepMinutes) {
      final target = start.add(Duration(minutes: mark));
      while (cursor < series.length - 1 &&
          series[cursor + 1].at.difference(target).abs() <=
              series[cursor].at.difference(target).abs()) {
        cursor++;
      }
      if (indices.isEmpty || indices.last != cursor) indices.add(cursor);
    }
    if (indices.last != series.length - 1) indices.add(series.length - 1);
    return indices;
  }

  @override
  bool shouldRepaint(_CurvePainter old) =>
      old.series != series || old.selected != selected;
}
