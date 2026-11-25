// training_blocks.dart: een afgeronde LiveTraining omzetten naar de blokken
// van `training_sessions.blocks`, in hetzelfde formaat als de historie
// (kind/name/meta/note/minutes/rounds...). Extra velden (doelen, reps, tijd,
// combinaties) staan in extra keys, zodat oude schermen blijven werken.

import '../models/live_training.dart';
import '../models/technique.dart';

List<Map<String, dynamic>> trainingBlocks(LiveTraining tr, List<Technique> techniques, DateTime end) {
  final stamp = end.toUtc().toIso8601String();
  final byId = {for (final t in techniques) t.id: t};

  // Sparteller per techniek, opgeteld over alle sparblokken.
  final sparCounts = <String, TechniqueCounts>{};
  for (final b in tr.sparrings) {
    for (final e in b.counts.entries) {
      final sum = sparCounts[e.key] ?? const TechniqueCounts();
      sparCounts[e.key] = TechniqueCounts(
        success: sum.success + e.value.success,
        attempts: sum.attempts + e.value.attempts,
        countered: sum.countered + e.value.countered,
      );
    }
  }

  final ids = {...tr.techniqueIds, ...tr.techniqueLogs.keys, ...sparCounts.keys};
  return [
    for (final w in tr.warmups)
      {
        'kind': 'warmup',
        'name': 'Warming-up',
        'meta': '${w.minutes} min',
        'note': '',
        'minutes': w.minutes,
        'covered': true,
        'logged_at': w.at.toUtc().toIso8601String(),
      },
    for (final b in tr.sparrings)
      if (b.roundsDone > 0 || b.goal.isNotEmpty || b.rounds.any((r) => r.goalDone))
        {
          'kind': 'sparring',
          'name': 'Sparren',
          'meta': '${b.rounds.length} rondes',
          'note': b.goal,
          'goal': b.goal,
          'goal_done': b.goalDone,
          'rounds': b.roundsDone,
          'minutes': (b.rounds.take(b.roundsDone).fold<int>(0, (a, r) => a + r.workSeconds) / 60).round(),
          'round_minutes': [for (final r in b.rounds.take(b.roundsDone)) (r.workSeconds / 60).round()],
          'rest_seconds': [
            for (var i = 0; i < b.roundsDone - 1 && i < b.rounds.length; i++) b.rounds[i].restSeconds,
          ],
          'round_goals': [
            for (final r in b.rounds)
              if (r.goal.isNotEmpty) {'goal': r.goal, 'done': r.goalDone},
          ],
          'covered': true,
          'logged_at': (b.endedAt ?? end).toUtc().toIso8601String(),
        },
    for (final id in ids)
      if (byId[id] case final t?)
        if (_hasData(tr.techniqueLogs[id], sparCounts[id]) || tr.techniqueIds.contains(id))
          _techniqueBlock(t, tr.techniqueLogs[id] ?? const TechniqueLog(), sparCounts[id], stamp),
    for (final c in tr.combos)
      {
        'kind': 'combination',
        'name': c.label,
        'meta': 'Combinatie',
        'note': '',
        'steps': c.steps,
        'reps': c.count,
        'covered': true,
        'combination_id': ?c.combinationId,
        'logged_at': c.at.toUtc().toIso8601String(),
      },
  ];
}

bool _hasData(TechniqueLog? log, TechniqueCounts? counts) =>
    (log != null && !log.isEmpty) || (counts != null && counts.total > 0);

Map<String, dynamic> _techniqueBlock(Technique t, TechniqueLog log, TechniqueCounts? counts, String stamp) {
  final c = counts ?? const TechniqueCounts();
  final striking = t.group.isStriking;
  final countNote = c.total == 0
      ? ''
      : [for (final s in TechniqueStat.values) '${statLabel(s, striking: striking)} ${c[s]}'].join(' · ');
  return {
    'kind': 'technique',
    'name': t.name,
    'meta': t.category,
    'technique_id': t.id,
    'note': [if (log.note.trim().isNotEmpty) log.note.trim(), if (countNote.isNotEmpty) countNote].join('\n'),
    'covered': true,
    'measure': log.measure.name,
    'reps': log.measure == TechniqueMeasure.reps ? log.reps : 0,
    'seconds': log.measure == TechniqueMeasure.time ? log.seconds : 0,
    if (c.total > 0) 'counts': c.toJson(),
    'striking': striking,
    'logged_at': stamp,
  };
}
