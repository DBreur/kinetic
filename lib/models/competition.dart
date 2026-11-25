// competition.dart: een wedstrijd uit de bestaande tabel `competitions`.

enum WeightLimitType {
  none(''),
  under('under'), // maximaal gewicht (bv. -82 kg)
  over('over'); // minimaal gewicht (bv. +88 kg)

  const WeightLimitType(this.dbName);
  final String dbName;

  static WeightLimitType fromName(String? name) => WeightLimitType.values
      .firstWhere((w) => w.dbName == name, orElse: () => WeightLimitType.none);
}

class Competition {
  final String id;
  final String name;
  final DateTime startsAt;
  final String discipline;
  final String location;
  final String weightClass;
  final WeightLimitType weightLimitType;
  final double? weightLimitKg;
  final double? targetWeightKg;

  /// Eigen doel voor de wedstrijd (kolom `goal`).
  final String goal;

  /// Resultaat na afloop (bestaande kolommen result_*).
  final int? resultPlace;
  final int? resultWins;
  final int? resultLosses;
  final String resultNote;

  const Competition({
    required this.id,
    required this.name,
    required this.startsAt,
    this.discipline = 'sport',
    this.location = '',
    this.weightClass = '',
    this.weightLimitType = WeightLimitType.none,
    this.weightLimitKg,
    this.targetWeightKg,
    this.goal = '',
    this.resultPlace,
    this.resultWins,
    this.resultLosses,
    this.resultNote = '',
  });

  factory Competition.fromJson(Map<String, dynamic> j) => Competition(
    id: j['id'] as String,
    name: j['name'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    discipline: (j['discipline'] as String?) ?? 'sport',
    location: (j['location'] as String?) ?? '',
    weightClass: (j['weight_class'] as String?) ?? '',
    weightLimitType: WeightLimitType.fromName(j['weight_limit_type'] as String?),
    weightLimitKg: (j['weight_limit_kg'] as num?)?.toDouble(),
    targetWeightKg: (j['target_weight_kg'] as num?)?.toDouble(),
    goal: (j['goal'] as String?) ?? '',
    resultPlace: (j['result_place'] as num?)?.toInt(),
    resultWins: (j['result_wins'] as num?)?.toInt(),
    resultLosses: (j['result_losses'] as num?)?.toInt(),
    resultNote: (j['result_note'] as String?) ?? '',
  );

  /// Kolommen voor insert/update (de app beheert deze velden).
  Map<String, dynamic> toJson() => {
    'name': name,
    'starts_at': startsAt.toUtc().toIso8601String(),
    'discipline': discipline,
    'location': location,
    'weight_class': weightClass,
    'weight_limit_type': weightLimitType.dbName,
    'weight_limit_kg': weightLimitKg,
    'target_weight_kg': targetWeightKg,
    'goal': goal,
    'result_place': resultPlace,
    'result_wins': resultWins,
    'result_losses': resultLosses,
    'result_note': resultNote,
  };

  Competition copyWith({
    String? id,
    String? name,
    DateTime? startsAt,
    String? discipline,
    String? location,
    String? weightClass,
    WeightLimitType? weightLimitType,
    double? weightLimitKg,
    bool clearWeightLimit = false,
    double? targetWeightKg,
    bool clearTarget = false,
    String? goal,
    int? resultPlace,
    int? resultWins,
    int? resultLosses,
    bool clearResult = false,
    String? resultNote,
  }) => Competition(
    id: id ?? this.id,
    name: name ?? this.name,
    startsAt: startsAt ?? this.startsAt,
    discipline: discipline ?? this.discipline,
    location: location ?? this.location,
    weightClass: weightClass ?? this.weightClass,
    weightLimitType: weightLimitType ?? this.weightLimitType,
    weightLimitKg: clearWeightLimit ? null : (weightLimitKg ?? this.weightLimitKg),
    targetWeightKg: clearTarget ? null : (targetWeightKg ?? this.targetWeightKg),
    goal: goal ?? this.goal,
    resultPlace: clearResult ? null : (resultPlace ?? this.resultPlace),
    resultWins: clearResult ? null : (resultWins ?? this.resultWins),
    resultLosses: clearResult ? null : (resultLosses ?? this.resultLosses),
    resultNote: resultNote ?? this.resultNote,
  );

  bool get hasResult => resultPlace != null || resultWins != null || resultNote.trim().isNotEmpty;

  /// "Goud / 1e plaats", "3e plaats", of null zonder plaats.
  String? get placeLabel => switch (resultPlace) {
    null => null,
    1 => 'Goud / 1e plaats',
    2 => 'Zilver / 2e plaats',
    3 => 'Brons / 3e plaats',
    final p => '${p}e plaats',
  };

  String get disciplineLabel => switch (discipline) {
    'combat' => 'Combat Sambo',
    'both' => 'Sport + Combat Sambo',
    _ => 'Sport Sambo',
  };

  /// Het gewicht waar je naartoe werkt: een expliciet doel, anders de
  /// klassegrens zelf.
  double? get effectiveTargetKg => targetWeightKg ?? weightLimitKg;

  /// Minimumklasse ("+88 kg"): je moet er strikt boven zitten, dus de
  /// kleinste geldige weging is grens + 0.1 kg.
  bool get isMinimumClass => weightLimitType == WeightLimitType.over && targetWeightKg == null && weightLimitKg != null;

  /// Hoeveel kg er nog bij moet voor een minimumklasse (0 als je erboven zit),
  /// of null als dit geen minimumklasse is. Eén bron voor alle schermen.
  double? gainNeededKg(double kg) {
    if (!isMinimumClass) return null;
    final need = weightLimitKg! + 0.1 - kg;
    return need <= 0.04 ? 0 : double.parse(need.toStringAsFixed(1));
  }

  /// Mag het gewicht op de weegdag niet boven/onder de grens komen?
  bool isWithinLimit(double kg) => switch (weightLimitType) {
    WeightLimitType.under => weightLimitKg == null || kg <= weightLimitKg!,
    WeightLimitType.over => weightLimitKg == null || kg > weightLimitKg!,
    WeightLimitType.none => true,
  };
}
