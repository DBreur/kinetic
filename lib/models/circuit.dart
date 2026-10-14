// circuit.dart — een opgeslagen circuit voor krachttraining: een naam plus
// een lijst oefeningnamen die je in rondes doorloopt, elk voor dezelfde
// werktijd met dezelfde rust ertussen (bv. "3 rondes van 40s werk / 20s
// rust: sprawls, sit-outs, lunge jumps, bear crawls, hollow hold"). Ook
// warming-ups zijn gewoon een circuit — geen apart concept. Herbruikbaar:
// te selecteren tijdens een live training of op te nemen in een
// trainingsschema (zie WorkoutTemplate.circuits).

class Circuit {
  final String id;
  final String name;
  final List<String> exerciseNames;
  final int rounds;
  final int workSeconds;
  final int restSeconds;

  const Circuit({
    required this.id,
    required this.name,
    this.exerciseNames = const [],
    this.rounds = 3,
    this.workSeconds = 40,
    this.restSeconds = 20,
  });

  factory Circuit.fromJson(Map<String, dynamic> json) => Circuit(
    id: json['id'] as String,
    name: json['name'] as String,
    exerciseNames: ((json['exercise_names'] as List?) ?? [])
        .map((e) => e as String)
        .toList(),
    rounds: (json['rounds'] as num?)?.toInt() ?? 3,
    workSeconds: (json['work_seconds'] as num?)?.toInt() ?? 40,
    restSeconds: (json['rest_seconds'] as num?)?.toInt() ?? 20,
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'name': name,
    'exercise_names': exerciseNames,
    'rounds': rounds,
    'work_seconds': workSeconds,
    'rest_seconds': restSeconds,
  };

  /// Voor embedding in een WorkoutTemplate — geen eigen rij, dus geen
  /// user_id nodig.
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'exercise_names': exerciseNames,
    'rounds': rounds,
    'work_seconds': workSeconds,
    'rest_seconds': restSeconds,
  };

  Circuit copyWith({
    String? name,
    List<String>? exerciseNames,
    int? rounds,
    int? workSeconds,
    int? restSeconds,
  }) => Circuit(
    id: id,
    name: name ?? this.name,
    exerciseNames: exerciseNames ?? this.exerciseNames,
    rounds: rounds ?? this.rounds,
    workSeconds: workSeconds ?? this.workSeconds,
    restSeconds: restSeconds ?? this.restSeconds,
  );
}
