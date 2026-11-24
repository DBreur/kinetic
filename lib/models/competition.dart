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
    resultPlace: (j['result_place'] as num?)?.toInt(),
    resultWins: (j['result_wins'] as num?)?.toInt(),
    resultLosses: (j['result_losses'] as num?)?.toInt(),
    resultNote: (j['result_note'] as String?) ?? '',
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

  /// Mag het gewicht op de weegdag niet boven/onder de grens komen?
  bool isWithinLimit(double kg) => switch (weightLimitType) {
    WeightLimitType.under => weightLimitKg == null || kg <= weightLimitKg!,
    WeightLimitType.over => weightLimitKg == null || kg > weightLimitKg!,
    WeightLimitType.none => true,
  };
}
