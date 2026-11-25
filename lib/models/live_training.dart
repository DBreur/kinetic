// live_training.dart: een lopende training. Een training is niet hetzelfde
// als sparren: je kiest een discipline en een begin- en eindtijd, en tijdens
// de training voeg je blokken toe: warming-up, sparren (met eigen rondes en
// doelen), technieken (reps/tijd + notitie), combinaties en voeding.
// Wordt als JSON lokaal bewaard zodat een herstart van de app niets kost, en
// bij afronden omgezet naar `training_sessions.blocks` en `.nutrition`.

import 'glucose.dart';
import 'technique.dart';

DateTime _date(Object? v) => DateTime.parse(v as String).toLocal();
String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Voeding tijdens (of na) een training: tijdstip, wat, hoeveel.
/// Formaat is compatibel met de oude `nutrition`-kolom ({label, at, mmol}).
class NutritionLog {
  const NutritionLog({
    required this.id,
    required this.at,
    required this.label,
    this.count = 1,
    this.carbs = 0,
    this.preset,
    this.mmol,
  });

  final String id;
  final DateTime at;

  /// Weergavetekst, bv. "4 Dextro's".
  final String label;
  final int count;

  /// Koolhydraten totaal (voor [count] stuks).
  final double carbs;

  /// Enkelvoud van de preset waar dit uit komt (null bij vrije invoer).
  final String? preset;
  final double? mmol;

  factory NutritionLog.fromJson(Map<String, dynamic> j) => NutritionLog(
    id: (j['id'] as String?) ?? '${j['at']}-${j['label']}',
    at: _date(j['at']),
    label: (j['label'] as String?) ?? '',
    count: (j['count'] as num?)?.toInt() ?? 1,
    carbs: (j['carbs'] as num?)?.toDouble() ?? 0,
    preset: j['preset'] as String?,
    mmol: (j['mmol'] as num?)?.toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'at': _iso(at),
    'count': count,
    'carbs': carbs,
    'preset': ?preset,
    'mmol': ?mmol,
  };

  NutritionLog copyWith({DateTime? at, String? label, int? count, double? carbs}) => NutritionLog(
    id: id,
    at: at ?? this.at,
    label: label ?? this.label,
    count: count ?? this.count,
    carbs: carbs ?? this.carbs,
    preset: preset,
    mmol: mmol,
  );
}

class WarmupLog {
  const WarmupLog({required this.id, required this.at, this.minutes = 15});
  final String id;
  final DateTime at;
  final int minutes;

  factory WarmupLog.fromJson(Map<String, dynamic> j) =>
      WarmupLog(id: j['id'] as String, at: _date(j['at']), minutes: (j['minutes'] as num?)?.toInt() ?? 15);

  Map<String, dynamic> toJson() => {'id': id, 'at': _iso(at), 'minutes': minutes};

  WarmupLog copyWith({int? minutes}) => WarmupLog(id: id, at: at, minutes: minutes ?? this.minutes);
}

/// Eén sparronde met eigen duur en (optioneel) eigen doel.
class SparRound {
  const SparRound({this.workSeconds = 300, this.restSeconds = 60, this.goal = '', this.goalDone = false});
  final int workSeconds;
  final int restSeconds;
  final String goal;
  final bool goalDone;

  factory SparRound.fromJson(Map<String, dynamic> j) => SparRound(
    workSeconds: (j['work'] as num?)?.toInt() ?? 300,
    restSeconds: (j['rest'] as num?)?.toInt() ?? 60,
    goal: (j['goal'] as String?) ?? '',
    goalDone: (j['goal_done'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {'work': workSeconds, 'rest': restSeconds, 'goal': goal, 'goal_done': goalDone};

  SparRound copyWith({int? workSeconds, int? restSeconds, String? goal, bool? goalDone}) => SparRound(
    workSeconds: workSeconds ?? this.workSeconds,
    restSeconds: restSeconds ?? this.restSeconds,
    goal: goal ?? this.goal,
    goalDone: goalDone ?? this.goalDone,
  );
}

/// Een sparblok binnen de training: doel voor het geheel, rondes met eigen
/// doelen, en de tellers per techniek (alleen tijdens sparren).
class SparringBlock {
  const SparringBlock({
    required this.id,
    required this.rounds,
    this.goal = '',
    this.goalDone = false,
    this.startedAt,
    this.endedAt,
    this.roundsDone = 0,
    this.counts = const {},
  });

  final String id;
  final List<SparRound> rounds;
  final String goal;
  final bool goalDone;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final int roundsDone;

  /// Techniek-id → Geslaagd/Poging/Gecounterd.
  final Map<String, TechniqueCounts> counts;

  bool get isFinished => endedAt != null;

  factory SparringBlock.fromJson(Map<String, dynamic> j) => SparringBlock(
    id: j['id'] as String,
    rounds: [for (final r in (j['rounds'] as List?) ?? const []) SparRound.fromJson(r as Map<String, dynamic>)],
    goal: (j['goal'] as String?) ?? '',
    goalDone: (j['goal_done'] as bool?) ?? false,
    startedAt: j['started_at'] == null ? null : _date(j['started_at']),
    endedAt: j['ended_at'] == null ? null : _date(j['ended_at']),
    roundsDone: (j['rounds_done'] as num?)?.toInt() ?? 0,
    counts: ((j['counts'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, TechniqueCounts.fromJson(v as Map<String, dynamic>)),
    ),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'rounds': [for (final r in rounds) r.toJson()],
    'goal': goal,
    'goal_done': goalDone,
    if (startedAt != null) 'started_at': _iso(startedAt!),
    if (endedAt != null) 'ended_at': _iso(endedAt!),
    'rounds_done': roundsDone,
    'counts': counts.map((k, v) => MapEntry(k, v.toJson())),
  };

  SparringBlock copyWith({
    List<SparRound>? rounds,
    String? goal,
    bool? goalDone,
    DateTime? startedAt,
    DateTime? endedAt,
    int? roundsDone,
    Map<String, TechniqueCounts>? counts,
  }) => SparringBlock(
    id: id,
    rounds: rounds ?? this.rounds,
    goal: goal ?? this.goal,
    goalDone: goalDone ?? this.goalDone,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt ?? this.endedAt,
    roundsDone: roundsDone ?? this.roundsDone,
    counts: counts ?? this.counts,
  );
}

/// Hoe je een techniek buiten het sparren logt.
enum TechniqueMeasure { reps, time }

/// Techniek-log buiten het sparren: reps of tijd, plus een notitie.
class TechniqueLog {
  const TechniqueLog({this.measure = TechniqueMeasure.reps, this.reps = 0, this.seconds = 0, this.note = ''});
  final TechniqueMeasure measure;
  final int reps;
  final int seconds;
  final String note;

  bool get isEmpty => reps == 0 && seconds == 0 && note.trim().isEmpty;

  factory TechniqueLog.fromJson(Map<String, dynamic> j) => TechniqueLog(
    measure: j['measure'] == 'time' ? TechniqueMeasure.time : TechniqueMeasure.reps,
    reps: (j['reps'] as num?)?.toInt() ?? 0,
    seconds: (j['seconds'] as num?)?.toInt() ?? 0,
    note: (j['note'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {'measure': measure.name, 'reps': reps, 'seconds': seconds, 'note': note};

  TechniqueLog copyWith({TechniqueMeasure? measure, int? reps, int? seconds, String? note}) => TechniqueLog(
    measure: measure ?? this.measure,
    reps: reps ?? this.reps,
    seconds: seconds ?? this.seconds,
    note: note ?? this.note,
  );
}

/// Gelogde combinatie, bv. Harai Goshi → O-soto-gari.
class ComboLog {
  const ComboLog({required this.id, required this.steps, required this.at, this.count = 1, this.combinationId});
  final String id;

  /// Techniek-namen in volgorde.
  final List<String> steps;
  final DateTime at;
  final int count;
  final String? combinationId;

  String get label => steps.join(' → ');

  factory ComboLog.fromJson(Map<String, dynamic> j) => ComboLog(
    id: j['id'] as String,
    steps: [for (final s in (j['steps'] as List?) ?? const []) s as String],
    at: _date(j['at']),
    count: (j['count'] as num?)?.toInt() ?? 1,
    combinationId: j['combination_id'] as String?,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'steps': steps,
    'at': _iso(at),
    'count': count,
    'combination_id': ?combinationId,
  };

  ComboLog copyWith({int? count}) =>
      ComboLog(id: id, steps: steps, at: at, count: count ?? this.count, combinationId: combinationId);
}

class LiveTraining {
  const LiveTraining({
    required this.discipline,
    required this.startsAt,
    required this.endsAt,
    this.title = '',
    this.techniqueIds = const [],
    this.techniqueLogs = const {},
    this.nutrition = const [],
    this.warmups = const [],
    this.sparrings = const [],
    this.combos = const [],
    this.glucose = const [],
  });

  /// "Sport Sambo", "BJJ", "Kracht"...
  final String discipline;

  /// Vrije naam; leeg = de discipline.
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final List<String> techniqueIds;
  final Map<String, TechniqueLog> techniqueLogs;
  final List<NutritionLog> nutrition;
  final List<WarmupLog> warmups;
  final List<SparringBlock> sparrings;
  final List<ComboLog> combos;
  final List<GlucosePoint> glucose;

  String get displayTitle => title.trim().isEmpty ? discipline : title.trim();

  bool hasStarted(DateTime now) => !now.isBefore(startsAt);
  bool isOver(DateTime now) => !now.isBefore(endsAt);

  /// Seconden tot de start (0 als hij al loopt).
  int secondsUntilStart(DateTime now) => hasStarted(now) ? 0 : startsAt.difference(now).inSeconds + 1;
  int elapsedSeconds(DateTime now) => hasStarted(now) ? now.difference(startsAt).inSeconds : 0;
  int remainingSeconds(DateTime now) => isOver(now) ? 0 : endsAt.difference(hasStarted(now) ? now : startsAt).inSeconds;
  int get plannedMinutes => endsAt.difference(startsAt).inMinutes;

  /// Het sparblok dat nu loopt (gestart, nog niet afgerond).
  SparringBlock? get activeSparring {
    for (final s in sparrings) {
      if (s.startedAt != null && !s.isFinished) return s;
    }
    return null;
  }

  double get nutritionCarbs => nutrition.fold(0.0, (a, n) => a + n.carbs);

  factory LiveTraining.fromJson(Map<String, dynamic> j) => LiveTraining(
    discipline: (j['discipline'] as String?) ?? 'Training',
    title: (j['title'] as String?) ?? '',
    startsAt: _date(j['starts_at']),
    endsAt: _date(j['ends_at']),
    techniqueIds: [for (final s in (j['techniques'] as List?) ?? const []) s as String],
    techniqueLogs: ((j['technique_logs'] as Map?) ?? const {}).map(
      (k, v) => MapEntry(k as String, TechniqueLog.fromJson(v as Map<String, dynamic>)),
    ),
    nutrition: [for (final n in (j['nutrition'] as List?) ?? const []) NutritionLog.fromJson(n as Map<String, dynamic>)],
    warmups: [for (final w in (j['warmups'] as List?) ?? const []) WarmupLog.fromJson(w as Map<String, dynamic>)],
    sparrings: [for (final s in (j['sparrings'] as List?) ?? const []) SparringBlock.fromJson(s as Map<String, dynamic>)],
    combos: [for (final c in (j['combos'] as List?) ?? const []) ComboLog.fromJson(c as Map<String, dynamic>)],
    glucose: [for (final g in (j['glucose'] as List?) ?? const []) GlucosePoint.fromJson(g as Map<String, dynamic>)],
  );

  Map<String, dynamic> toJson() => {
    'discipline': discipline,
    'title': title,
    'starts_at': _iso(startsAt),
    'ends_at': _iso(endsAt),
    'techniques': techniqueIds,
    'technique_logs': techniqueLogs.map((k, v) => MapEntry(k, v.toJson())),
    'nutrition': [for (final n in nutrition) n.toJson()],
    'warmups': [for (final w in warmups) w.toJson()],
    'sparrings': [for (final s in sparrings) s.toJson()],
    'combos': [for (final c in combos) c.toJson()],
    'glucose': [for (final g in glucose) g.toJson()],
  };

  LiveTraining copyWith({
    String? discipline,
    String? title,
    DateTime? startsAt,
    DateTime? endsAt,
    List<String>? techniqueIds,
    Map<String, TechniqueLog>? techniqueLogs,
    List<NutritionLog>? nutrition,
    List<WarmupLog>? warmups,
    List<SparringBlock>? sparrings,
    List<ComboLog>? combos,
    List<GlucosePoint>? glucose,
  }) => LiveTraining(
    discipline: discipline ?? this.discipline,
    title: title ?? this.title,
    startsAt: startsAt ?? this.startsAt,
    endsAt: endsAt ?? this.endsAt,
    techniqueIds: techniqueIds ?? this.techniqueIds,
    techniqueLogs: techniqueLogs ?? this.techniqueLogs,
    nutrition: nutrition ?? this.nutrition,
    warmups: warmups ?? this.warmups,
    sparrings: sparrings ?? this.sparrings,
    combos: combos ?? this.combos,
    glucose: glucose ?? this.glucose,
  );
}
