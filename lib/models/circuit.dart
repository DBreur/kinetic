// circuit.dart — een opgeslagen circuit voor krachttraining: een naam plus
// stappen die je in rondes doorloopt, met rust ertussen (bv. "3 rondes:
// 1 min schaduwboksen, 10× push-up, 1 min bearcrawl"). Elke stap is óf een
// tijd (telt af) óf een aantal herhalingen (je tikt "Klaar"). Ook
// warming-ups zijn gewoon een circuit. Herbruikbaar: te selecteren tijdens
// een live training of op te nemen in een trainingsschema.
//
// Oudere circuits hebben alleen [exerciseNames] met één vaste [workSeconds]
// voor elke oefening — [effectiveSteps] vertaalt dat naar stappen, en bij
// opslaan worden de namen en werktijd gewoon meegeschreven (voor Uchivo).

/// Eén stap in een circuit: een tijd ([seconds]) of herhalingen ([reps]).
class CircuitStep {
  final String name;
  final int? seconds;
  final int? reps;

  const CircuitStep({required this.name, this.seconds, this.reps});

  bool get isTimed => reps == null;

  /// "1 min", "45 s" of "10×".
  String get targetLabel {
    if (!isTimed) return '$reps×';
    final s = seconds ?? 0;
    if (s >= 60 && s % 60 == 0) return '${s ~/ 60} min';
    return '$s s';
  }

  factory CircuitStep.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    final reps = (map['reps'] as num?)?.toInt();
    return CircuitStep(
      name: (map['name'] as String?) ?? '',
      reps: reps,
      seconds: reps == null ? ((map['seconds'] as num?)?.toInt() ?? 40) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (reps != null) 'reps': reps else 'seconds': seconds ?? 40,
  };

  CircuitStep copyWith({String? name, int? seconds, int? reps, bool timed = true}) =>
      timed
      ? CircuitStep(name: name ?? this.name, seconds: seconds ?? this.seconds ?? 40)
      : CircuitStep(name: name ?? this.name, reps: reps ?? this.reps ?? 10);
}

class Circuit {
  final String id;
  final String name;
  final List<String> exerciseNames;
  final int rounds;
  final int workSeconds;
  final int restSeconds;
  final String description;
  final List<String> videoUrls;

  /// Stappen met eigen tijd of herhalingen. Leeg bij oudere circuits — gebruik
  /// [effectiveSteps].
  final List<CircuitStep> steps;

  const Circuit({
    required this.id,
    required this.name,
    this.exerciseNames = const [],
    this.rounds = 3,
    this.workSeconds = 40,
    this.restSeconds = 20,
    this.description = '',
    this.videoUrls = const [],
    this.steps = const [],
  });

  /// De stappen zoals ze gedaan worden: de eigen stappen, of (bij oudere
  /// circuits) elke oefening even lang als [workSeconds].
  List<CircuitStep> get effectiveSteps => steps.isNotEmpty
      ? steps
      : [for (final n in exerciseNames) CircuitStep(name: n, seconds: workSeconds)];

  factory Circuit.fromJson(Map<String, dynamic> json) => Circuit(
    id: (json['id'] as String?) ?? '',
    name: json['name'] as String,
    exerciseNames: ((json['exercise_names'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    rounds: (json['rounds'] as num?)?.toInt() ?? 3,
    workSeconds: (json['work_seconds'] as num?)?.toInt() ?? 40,
    restSeconds: (json['rest_seconds'] as num?)?.toInt() ?? 20,
    description: (json['description'] as String?) ?? '',
    videoUrls: ((json['video_urls'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    steps: ((json['steps'] as List?) ?? []).map(CircuitStep.fromJson).toList(),
  );

  /// Namen en een werktijd voor Uchivo (dat alleen die velden kent): de
  /// namen van de stappen, en de tijd van de eerste getimede stap.
  List<String> get _compatNames =>
      steps.isNotEmpty ? [for (final s in steps) s.name] : exerciseNames;
  int get _compatWorkSeconds {
    for (final s in steps) {
      if (s.isTimed && s.seconds != null) return s.seconds!;
    }
    return workSeconds;
  }

  /// "3 oefeningen · 3 rondes · 1 min per oefening · 20s rust" — bij
  /// gemengde stappen zonder de tijd per oefening.
  String get summary {
    final st = effectiveSteps;
    final targets = {for (final s in st) s.targetLabel};
    return [
      '${st.length} oefening${st.length == 1 ? '' : 'en'}',
      '$rounds ronde${rounds == 1 ? '' : 's'}',
      if (targets.length == 1) '${targets.first} per oefening',
      restSeconds > 0 ? '${restSeconds}s rust' : 'geen rust',
    ].join(' · ');
  }

  /// "1 min Schaduwboksen, 10× Push-up, …"
  String get stepsLabel => [
    for (final s in effectiveSteps) '${s.targetLabel} ${s.name}',
  ].join(', ');

  Map<String, dynamic> _fields() => {
    'name': name,
    'exercise_names': _compatNames,
    'rounds': rounds,
    'work_seconds': _compatWorkSeconds,
    'rest_seconds': restSeconds,
    'description': description,
    'video_urls': videoUrls,
    'steps': steps.map((s) => s.toJson()).toList(),
  };

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    ..._fields(),
  };

  /// Voor updates en voor embedding in een WorkoutTemplate.
  Map<String, dynamic> toJson() => {'id': id, ..._fields()};

  Map<String, dynamic> toUpdateJson() => _fields();

  Circuit copyWith({
    String? name,
    List<String>? exerciseNames,
    int? rounds,
    int? workSeconds,
    int? restSeconds,
    String? description,
    List<String>? videoUrls,
    List<CircuitStep>? steps,
  }) => Circuit(
    id: id,
    name: name ?? this.name,
    exerciseNames: exerciseNames ?? this.exerciseNames,
    rounds: rounds ?? this.rounds,
    workSeconds: workSeconds ?? this.workSeconds,
    restSeconds: restSeconds ?? this.restSeconds,
    description: description ?? this.description,
    videoUrls: videoUrls ?? this.videoUrls,
    steps: steps ?? this.steps,
  );
}
