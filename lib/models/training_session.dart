import 'circuit.dart';
import 'glucose.dart' show GlucosePoint;

export 'circuit.dart';
export 'glucose.dart' show GlucosePoint;

enum SessionKind { sambo, kracht }

enum BlockKind { technique, warmup, sparring }

BlockKind blockKindFromName(String? name) => switch (name) {
  'warmup' => BlockKind.warmup,
  'sparring' => BlockKind.sparring,
  _ => BlockKind.technique,
};

/// Eén doel voor het sparren — zelf ingevoerd, en tijdens (of na) de sessie
/// af te vinken als bereikt of niet.
class SparGoal {
  final String text;
  final bool achieved;
  const SparGoal({required this.text, this.achieved = false});

  /// Accepteert ook een kale string, voor doelen die zijn opgeslagen voordat
  /// het bereikt-vinkje bestond.
  factory SparGoal.fromJson(dynamic json) {
    if (json is String) return SparGoal(text: json);
    final map = json as Map<String, dynamic>;
    return SparGoal(
      text: map['text'] as String,
      achieved: (map['achieved'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {'text': text, 'achieved': achieved};

  SparGoal copyWith({String? text, bool? achieved}) =>
      SparGoal(text: text ?? this.text, achieved: achieved ?? this.achieved);
}

/// Eén onderdeel van een sambo-sessie: een techniek, de warming-up, of het
/// sparren. Techniek krijgt een sterbeoordeling; warming-up/sparren krijgen
/// een duur (en sparren ook rondes) in plaats daarvan.
class SessionBlock {
  final BlockKind kind;
  final String name;
  final String meta;
  final String note;

  /// Positiewisseling, bv. "Staand -> Grond" — alleen voor technique.
  final String transition;
  final int rating; // 0 = niet beoordeeld — alleen zinvol voor technique
  final bool covered;
  final int minutes; // alleen warmup/sparring
  final int rounds; // alleen sparring

  /// Duur per ronde — alleen sparring. Elke ronde is apart aanpasbaar en
  /// verwijderbaar, in plaats van één totaal aantal rondes.
  final List<int> roundMinutes;

  /// Algemene doelen voor het sparren, zelf ingevoerd — alleen sparring.
  final List<SparGoal> goals;

  /// Doelen per ronde (index-gelijk aan [roundMinutes]) — alleen sparring.
  final List<List<SparGoal>> roundGoals;

  /// Beperkingen per ronde (index-gelijk aan [roundMinutes]) — bv. een
  /// startpositie of iets wat niet mag ("Start: grond onder", "Geen
  /// klemmen"). Alleen sparring; [SparGoal.achieved] = je hield je eraan.
  final List<List<SparGoal>> roundRestrictions;

  /// Rust in seconden na elke ronde (index-gelijk aan [roundMinutes]) —
  /// alleen sparring.
  final List<int> restSeconds;

  /// Wanneer dit blok tijdens de training is gedaan (gezet zodra het als
  /// behandeld wordt afgevinkt, later nog aan te passen).
  final DateTime? loggedAt;

  /// True zodra deze techniek gekoppeld is aan een bestaande catalogus-
  /// techniek. Voorkomt een dubbele catalogus-aanmaak als de naam later
  /// wordt aangepast.
  final bool catalogLinked;

  const SessionBlock({
    this.kind = BlockKind.technique,
    required this.name,
    this.meta = '',
    this.note = '',
    this.transition = '',
    this.rating = 0,
    this.covered = false,
    this.minutes = 0,
    this.rounds = 0,
    this.roundMinutes = const [],
    this.goals = const [],
    this.roundGoals = const [],
    this.roundRestrictions = const [],
    this.restSeconds = const [],
    this.loggedAt,
    this.catalogLinked = false,
  });

  factory SessionBlock.fromJson(Map<String, dynamic> json) => SessionBlock(
    kind: blockKindFromName(json['kind'] as String?),
    name: json['name'] as String,
    meta: (json['meta'] as String?) ?? '',
    note: (json['note'] as String?) ?? '',
    transition: (json['transition'] as String?) ?? '',
    rating: (json['rating'] as num?)?.toInt() ?? 0,
    covered: (json['covered'] as bool?) ?? false,
    minutes: (json['minutes'] as num?)?.toInt() ?? 0,
    rounds: (json['rounds'] as num?)?.toInt() ?? 0,
    roundMinutes: ((json['round_minutes'] as List?) ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
    goals: ((json['goals'] as List?) ?? [])
        .map((e) => SparGoal.fromJson(e))
        .toList(),
    roundGoals: ((json['round_goals'] as List?) ?? [])
        .map((e) => ((e as List?) ?? []).map(SparGoal.fromJson).toList())
        .toList(),
    roundRestrictions: ((json['round_restrictions'] as List?) ?? [])
        .map((e) => ((e as List?) ?? []).map(SparGoal.fromJson).toList())
        .toList(),
    restSeconds: ((json['rest_seconds'] as List?) ?? [])
        .map((e) => (e as num).toInt())
        .toList(),
    loggedAt: json['logged_at'] != null
        ? DateTime.parse(json['logged_at'] as String).toLocal()
        : null,
    catalogLinked: (json['catalog_linked'] as bool?) ?? false,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.name,
    'name': name,
    'meta': meta,
    'note': note,
    'transition': transition,
    'rating': rating,
    'covered': covered,
    'minutes': minutes,
    'rounds': rounds,
    'round_minutes': roundMinutes,
    'goals': goals.map((g) => g.toJson()).toList(),
    'round_goals': roundGoals
        .map((list) => list.map((g) => g.toJson()).toList())
        .toList(),
    'round_restrictions': roundRestrictions
        .map((list) => list.map((g) => g.toJson()).toList())
        .toList(),
    'rest_seconds': restSeconds,
    'logged_at': loggedAt?.toUtc().toIso8601String(),
    'catalog_linked': catalogLinked,
  };

  SessionBlock copyWith({
    BlockKind? kind,
    String? name,
    String? meta,
    String? note,
    String? transition,
    int? rating,
    bool? covered,
    int? minutes,
    int? rounds,
    List<int>? roundMinutes,
    List<SparGoal>? goals,
    List<List<SparGoal>>? roundGoals,
    List<List<SparGoal>>? roundRestrictions,
    List<int>? restSeconds,
    DateTime? loggedAt,
    bool? catalogLinked,
  }) => SessionBlock(
    kind: kind ?? this.kind,
    name: name ?? this.name,
    meta: meta ?? this.meta,
    note: note ?? this.note,
    transition: transition ?? this.transition,
    rating: rating ?? this.rating,
    covered: covered ?? this.covered,
    minutes: minutes ?? this.minutes,
    rounds: rounds ?? this.rounds,
    roundMinutes: roundMinutes ?? this.roundMinutes,
    goals: goals ?? this.goals,
    roundGoals: roundGoals ?? this.roundGoals,
    roundRestrictions: roundRestrictions ?? this.roundRestrictions,
    restSeconds: restSeconds ?? this.restSeconds,
    loggedAt: loggedAt ?? this.loggedAt,
    catalogLinked: catalogLinked ?? this.catalogLinked,
  );
}

class ExerciseSet {
  final double kg;
  final int reps;
  final bool done;

  /// Tijd-gebaseerde set (bv. een plank van 45s) i.p.v. reps — `null`
  /// betekent gewoon een reps-gebaseerde set zoals voorheen.
  final int? seconds;

  /// "Tot verzuring": door tot je verzuring voelt, en dan nog [extraTarget]
  /// herhalingen (bv. "5–10"). [extraReps] = hoeveel het er na de
  /// verzuring echt werden.
  final bool toBurn;
  final String extraTarget;
  final int? extraReps;

  /// Gelukt (true) / niet gelukt (false) / niet aangegeven (null), met
  /// optioneel waarom.
  final bool? completed;
  final String note;

  const ExerciseSet({
    required this.kg,
    required this.reps,
    this.done = false,
    this.seconds,
    this.toBurn = false,
    this.extraTarget = '',
    this.extraReps,
    this.completed,
    this.note = '',
  });

  factory ExerciseSet.fromJson(Map<String, dynamic> json) => ExerciseSet(
    kg: (json['kg'] as num?)?.toDouble() ?? 0,
    reps: (json['reps'] as num?)?.toInt() ?? 0,
    done: (json['done'] as bool?) ?? false,
    seconds: (json['seconds'] as num?)?.toInt(),
    toBurn: (json['to_burn'] as bool?) ?? false,
    extraTarget: (json['extra_target'] as String?) ?? '',
    extraReps: (json['extra_reps'] as num?)?.toInt(),
    completed: json['completed'] as bool?,
    note: (json['note'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'kg': kg,
    'reps': reps,
    'done': done,
    if (seconds != null) 'seconds': seconds,
    if (toBurn) 'to_burn': true,
    if (extraTarget.isNotEmpty) 'extra_target': extraTarget,
    if (extraReps != null) 'extra_reps': extraReps,
    if (completed != null) 'completed': completed,
    if (note.isNotEmpty) 'note': note,
  };

  ExerciseSet copyWith({
    double? kg,
    int? reps,
    bool? done,
    int? seconds,
    bool clearSeconds = false,
    bool? toBurn,
    String? extraTarget,
    int? extraReps,
    bool clearExtraReps = false,
    bool? completed,
    bool clearCompleted = false,
    String? note,
  }) => ExerciseSet(
    kg: kg ?? this.kg,
    reps: reps ?? this.reps,
    done: done ?? this.done,
    seconds: clearSeconds ? null : (seconds ?? this.seconds),
    toBurn: toBurn ?? this.toBurn,
    extraTarget: extraTarget ?? this.extraTarget,
    extraReps: clearExtraReps ? null : (extraReps ?? this.extraReps),
    completed: clearCompleted ? null : (completed ?? this.completed),
    note: note ?? this.note,
  );

  /// Korte omschrijving voor overzichten: "20 kg × 8", "45 s",
  /// "verzuring +7".
  String get summary {
    final weight = kg > 0 ? '${_num(kg)} kg · ' : '';
    if (seconds != null) return '$weight${seconds}s';
    if (toBurn) {
      return '${weight}verzuring'
          '${extraReps != null ? ' +$extraReps' : (extraTarget.isNotEmpty ? ' (+$extraTarget)' : '')}';
    }
    return '$weight× $reps';
  }

  static String _num(double v) =>
      v % 1 == 0 ? v.toInt().toString() : v.toString().replaceAll('.', ',');
}

/// Eén keer dat een oefening werd gedaan, met de sets van die dag — voor het
/// voortgangsscherm en het persoonlijk record.
class ExercisePerformance {
  final DateTime date;
  final List<ExerciseSet> sets;

  const ExercisePerformance({required this.date, required this.sets});

  /// Zwaarste gewicht in deze sets, ongeacht het aantal reps.
  double get heaviest =>
      sets.fold<double>(0, (max, s) => s.kg > max ? s.kg : max);
}

/// Voeding gelogd tijdens een training: welk preset, wanneer, en hoe hoog de
/// glucose op dat moment was.
class NutritionEntry {
  final String label;
  final DateTime at;
  final double mmol;

  const NutritionEntry({
    required this.label,
    required this.at,
    required this.mmol,
  });

  factory NutritionEntry.fromJson(Map<String, dynamic> json) => NutritionEntry(
    label: json['label'] as String,
    at: DateTime.parse(json['at'] as String).toLocal(),
    mmol: (json['mmol'] as num).toDouble(),
  );

  Map<String, dynamic> toJson() => {
    'label': label,
    'at': at.toUtc().toIso8601String(),
    'mmol': mmol,
  };
}

class ExerciseEntry {
  final String name;
  final List<ExerciseSet> sets;

  /// Blok (superset): opeenvolgende oefeningen met hetzelfde nummer doe je
  /// per ronde achter elkaar, met pas daarna rust. Null = losse oefening.
  /// Zie core/rest_blocks.dart.
  final int? block;

  /// Rust in seconden na een set (los) of na een ronde (blok). Null = de
  /// standaard uit de instellingen.
  final int? restSeconds;

  const ExerciseEntry({
    required this.name,
    required this.sets,
    this.block,
    this.restSeconds,
  });

  factory ExerciseEntry.fromJson(Map<String, dynamic> json) => ExerciseEntry(
    name: json['name'] as String,
    sets: (json['sets'] as List)
        .map((e) => ExerciseSet.fromJson(e as Map<String, dynamic>))
        .toList(),
    block: (json['block'] as num?)?.toInt(),
    restSeconds: (json['rest'] as num?)?.toInt(),
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'sets': sets.map((s) => s.toJson()).toList(),
    if (block != null) 'block': block,
    if (restSeconds != null) 'rest': restSeconds,
  };
}

class TrainingSession {
  final String id;
  final SessionKind kind;
  final String title;
  final DateTime startedAt;
  final int durationMinutes;
  final String note;
  final List<GlucosePoint> glucoseSeries;
  final List<SessionBlock> blocks;
  final List<ExerciseEntry> exercises;
  final List<NutritionEntry> nutrition;

  /// Circuits die daadwerkelijk tijdens deze training zijn uitgevoerd — een
  /// snapshot-kopie, los van wat eventueel nog in Instellingen staat.
  final List<Circuit> circuits;

  const TrainingSession({
    required this.id,
    required this.kind,
    required this.title,
    required this.startedAt,
    required this.durationMinutes,
    this.note = '',
    this.glucoseSeries = const [],
    this.blocks = const [],
    this.exercises = const [],
    this.nutrition = const [],
    this.circuits = const [],
  });

  factory TrainingSession.fromJson(Map<String, dynamic> json) =>
      TrainingSession(
        id: json['id'] as String,
        kind: (json['kind'] as String) == 'kracht'
            ? SessionKind.kracht
            : SessionKind.sambo,
        title: json['title'] as String,
        startedAt: DateTime.parse(json['started_at'] as String).toLocal(),
        durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 0,
        note: (json['note'] as String?) ?? '',
        glucoseSeries: ((json['glucose_series'] as List?) ?? [])
            .map((e) => GlucosePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        blocks: ((json['blocks'] as List?) ?? [])
            .map((e) => SessionBlock.fromJson(e as Map<String, dynamic>))
            .toList(),
        exercises: ((json['exercises'] as List?) ?? [])
            .map((e) => ExerciseEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        nutrition: ((json['nutrition'] as List?) ?? [])
            .map((e) => NutritionEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        circuits: ((json['circuits'] as List?) ?? [])
            .map((e) => Circuit.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'kind': kind.name,
    'title': title,
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_minutes': durationMinutes,
    'note': note,
    'glucose_series': glucoseSeries.map((g) => g.toJson()).toList(),
    'blocks': blocks.map((b) => b.toJson()).toList(),
    'exercises': exercises.map((e) => e.toJson()).toList(),
    'nutrition': nutrition.map((n) => n.toJson()).toList(),
    'circuits': circuits.map((c) => c.toJson()).toList(),
  };

  TrainingSession copyWith({
    DateTime? startedAt,
    String? title,
    String? note,
    int? durationMinutes,
    List<SessionBlock>? blocks,
    List<ExerciseEntry>? exercises,
    List<NutritionEntry>? nutrition,
    List<Circuit>? circuits,
  }) => TrainingSession(
    id: id,
    kind: kind,
    title: title ?? this.title,
    startedAt: startedAt ?? this.startedAt,
    durationMinutes: durationMinutes ?? this.durationMinutes,
    note: note ?? this.note,
    glucoseSeries: glucoseSeries,
    blocks: blocks ?? this.blocks,
    exercises: exercises ?? this.exercises,
    nutrition: nutrition ?? this.nutrition,
    circuits: circuits ?? this.circuits,
  );

  double? get lowestMmol => glucoseSeries.isEmpty
      ? null
      : glucoseSeries.map((g) => g.mmol).reduce((a, b) => a < b ? a : b);

  double? get firstMmol =>
      glucoseSeries.isEmpty ? null : glucoseSeries.first.mmol;
  double? get lastMmol =>
      glucoseSeries.isEmpty ? null : glucoseSeries.last.mmol;
  bool get hadDip => (lowestMmol ?? 99) < 5.0;
}
