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

enum StepKind { time, reps, burn }

/// Eén stap in een circuit: een tijd ([seconds]), herhalingen ([reps]) of
/// tot verzuring ([toBurn], eventueel nog [extraTarget] herhalingen erna,
/// bv. "5–10"). [restSeconds] is de rust ná deze stap; null = de standaard
/// rust van het circuit, 0 = meteen door.
class CircuitStep {
  final String name;
  final int? seconds;
  final int? reps;
  final bool toBurn;
  final String extraTarget;
  final int? restSeconds;

  /// Video's bij deze stap (links). Leeg = die van de oefening met dezelfde
  /// naam in je oefeningen, als die er zijn.
  final List<String> videoUrls;

  /// Blok binnen het circuit: opeenvolgende stappen met hetzelfde nummer
  /// doe je samen een eigen aantal rondes ([blockRounds]) voordat je naar
  /// het volgende deel gaat. Null = geen blok. Zie [Circuit.segments].
  final int? block;

  /// Rondes van het blok — staat op elke stap van het blok, de eerste telt.
  final int? blockRounds;

  const CircuitStep({
    required this.name,
    this.seconds,
    this.reps,
    this.toBurn = false,
    this.extraTarget = '',
    this.restSeconds,
    this.videoUrls = const [],
    this.block,
    this.blockRounds,
  });

  StepKind get kind => toBurn
      ? StepKind.burn
      : reps != null
      ? StepKind.reps
      : StepKind.time;

  /// Telt af; herhalingen en verzuring wachten op "Klaar".
  bool get isTimed => kind == StepKind.time;

  /// "1 min", "45 s", "10×" of "verzuring +5–10".
  String get targetLabel => switch (kind) {
    StepKind.reps => '$reps×',
    StepKind.burn =>
      extraTarget.isEmpty ? 'verzuring' : 'verzuring +$extraTarget',
    StepKind.time => _timeLabel(seconds ?? 0),
  };

  static String _timeLabel(int s) =>
      s >= 60 && s % 60 == 0 ? '${s ~/ 60} min' : '$s s';

  factory CircuitStep.fromJson(dynamic json) {
    final map = json as Map<String, dynamic>;
    final toBurn = (map['to_burn'] as bool?) ?? false;
    final reps = toBurn ? null : (map['reps'] as num?)?.toInt();
    return CircuitStep(
      name: (map['name'] as String?) ?? '',
      reps: reps,
      seconds: toBurn || reps != null
          ? null
          : ((map['seconds'] as num?)?.toInt() ?? 40),
      toBurn: toBurn,
      extraTarget: (map['extra_target'] as String?) ?? '',
      restSeconds: (map['rest'] as num?)?.toInt(),
      videoUrls: ((map['videos'] as List?) ?? const [])
          .map((e) => e as String)
          .toList(),
      block: (map['block'] as num?)?.toInt(),
      blockRounds: (map['block_rounds'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    ...switch (kind) {
      StepKind.burn => {
        'to_burn': true,
        if (extraTarget.isNotEmpty) 'extra_target': extraTarget,
      },
      StepKind.reps => {'reps': reps},
      StepKind.time => {'seconds': seconds ?? 40},
    },
    'rest': ?restSeconds,
    if (videoUrls.isNotEmpty) 'videos': videoUrls,
    'block': ?block,
    'block_rounds': ?blockRounds,
  };

  CircuitStep copyWith({
    String? name,
    List<String>? videoUrls,
    int? block,
    bool clearBlock = false,
    int? blockRounds,
  }) => CircuitStep(
    name: name ?? this.name,
    seconds: seconds,
    reps: reps,
    toBurn: toBurn,
    extraTarget: extraTarget,
    restSeconds: restSeconds,
    videoUrls: videoUrls ?? this.videoUrls,
    block: clearBlock ? null : (block ?? this.block),
    blockRounds: clearBlock ? null : (blockRounds ?? this.blockRounds),
  );
}

/// Een deel van een circuit dat je een aantal rondes herhaalt: een blok
/// (stappen [start] tot [end]) of, zonder blokken, het hele circuit.
class CircuitSegment {
  final int start;
  final int end;
  final int rounds;

  /// Bloknummer, of null voor stappen buiten een blok.
  final int? block;
  const CircuitSegment({
    required this.start,
    required this.end,
    required this.rounds,
    this.block,
  });

  int get length => end - start;
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

  /// Met blokken: true = elk blok zijn eigen rondes na elkaar (A A A, B B
  /// B); false = het hele circuit telkens één keer door ([rounds] keer),
  /// blokken zijn dan alleen een groepering.
  final bool roundsPerBlock;

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
    this.roundsPerBlock = true,
  });

  /// De stappen zoals ze gedaan worden: de eigen stappen, of (bij oudere
  /// circuits) elke oefening even lang als [workSeconds].
  List<CircuitStep> get effectiveSteps => steps.isNotEmpty
      ? steps
      : [
          for (final n in exerciseNames)
            CircuitStep(name: n, seconds: workSeconds),
        ];

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
    roundsPerBlock: (json['rounds_per_block'] as bool?) ?? true,
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
    final blocks = roundsPerBlock
        ? segments.where((g) => g.block != null).length
        : 0;
    return [
      '${st.length} oefening${st.length == 1 ? '' : 'en'}',
      if (blocks > 0)
        '$blocks blok${blocks == 1 ? '' : 'ken'}'
      else
        '$rounds ronde${rounds == 1 ? '' : 's'}',
      if (targets.length == 1) '${targets.first} per oefening',
      _restLabel,
    ].join(' · ');
  }

  /// De delen die je na elkaar doet. Zonder blokken: één deel (alle
  /// stappen, [rounds] rondes). Met blokken: elk blok met zijn eigen
  /// rondes; stappen ertussen zonder blok vormen samen een deel met
  /// [rounds] rondes.
  List<CircuitSegment> get segments {
    final st = effectiveSteps;
    if (!roundsPerBlock || !hasBlocks) {
      return [CircuitSegment(start: 0, end: st.length, rounds: rounds)];
    }
    final result = <CircuitSegment>[];
    var i = 0;
    while (i < st.length) {
      final block = st[i].block;
      var end = i + 1;
      while (end < st.length && st[end].block == block) {
        end++;
      }
      result.add(
        CircuitSegment(
          start: i,
          end: end,
          rounds: block == null ? rounds : (st[i].blockRounds ?? rounds),
          block: block,
        ),
      );
      i = end;
    }
    return result;
  }

  bool get hasBlocks => effectiveSteps.any((s) => s.block != null);

  /// Rust ná stap [i]: de eigen rust van die stap, anders de standaard.
  int restAfter(int i) {
    final st = effectiveSteps;
    return (i >= 0 && i < st.length ? st[i].restSeconds : null) ?? restSeconds;
  }

  String get _restLabel {
    final rests = {
      for (var i = 0; i < effectiveSteps.length; i++) restAfter(i),
    };
    if (rests.length > 1) return 'rust per oefening';
    final r = rests.isEmpty ? restSeconds : rests.first;
    return r > 0 ? '${r}s rust' : 'geen rust';
  }

  /// "1 min Schaduwboksen, 10× Push-up, …"
  String get stepsLabel =>
      [for (final s in effectiveSteps) '${s.targetLabel} ${s.name}'].join(', ');

  Map<String, dynamic> _fields() => {
    'name': name,
    'exercise_names': _compatNames,
    'rounds': rounds,
    'work_seconds': _compatWorkSeconds,
    'rest_seconds': restSeconds,
    'description': description,
    'video_urls': videoUrls,
    'steps': steps.map((s) => s.toJson()).toList(),
    'rounds_per_block': roundsPerBlock,
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
    bool? roundsPerBlock,
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
    roundsPerBlock: roundsPerBlock ?? this.roundsPerBlock,
  );
}
