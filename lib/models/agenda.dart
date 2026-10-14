// agenda.dart — geplande trainingen en wedstrijden (tabellen
// planned_trainings en competitions, zie migratie 202610150001).

/// Soort geplande training.
enum TrainingKind {
  sportSambo('sport_sambo', 'Sport sambo'),
  combatSambo('combat_sambo', 'Combat sambo'),
  kracht('kracht', 'Kracht'),
  overig('overig', 'Overig');

  const TrainingKind(this.dbName, this.label);
  final String dbName;
  final String label;

  static TrainingKind fromName(String? name) => TrainingKind.values
      .firstWhere((k) => k.dbName == name, orElse: () => TrainingKind.overig);

  bool get isSambo =>
      this == TrainingKind.sportSambo || this == TrainingKind.combatSambo;
}

class PlannedTraining {
  final String id;
  final DateTime startsAt;
  final TrainingKind kind;
  final String title;
  final String location;
  final String note;

  /// Minuten vóór de start voor een melding; null = geen melding.
  final int? remindMinutesBefore;

  const PlannedTraining({
    required this.id,
    required this.startsAt,
    this.kind = TrainingKind.sportSambo,
    this.title = '',
    this.location = '',
    this.note = '',
    this.remindMinutesBefore,
  });

  /// Titel om te tonen — zelf ingevuld, anders de soort.
  String get displayTitle => title.trim().isEmpty ? kind.label : title.trim();

  DateTime? get remindAt => remindMinutesBefore == null
      ? null
      : startsAt.subtract(Duration(minutes: remindMinutesBefore!));

  factory PlannedTraining.fromJson(Map<String, dynamic> json) =>
      PlannedTraining(
        id: json['id'] as String,
        startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
        kind: TrainingKind.fromName(json['kind'] as String?),
        title: (json['title'] as String?) ?? '',
        location: (json['location'] as String?) ?? '',
        note: (json['note'] as String?) ?? '',
        remindMinutesBefore: (json['remind_minutes_before'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
    'starts_at': startsAt.toUtc().toIso8601String(),
    'kind': kind.dbName,
    'title': title.trim(),
    'location': location.trim(),
    'note': note.trim(),
    'remind_minutes_before': remindMinutesBefore,
  };

  PlannedTraining copyWith({
    DateTime? startsAt,
    TrainingKind? kind,
    String? title,
    String? location,
    String? note,
    int? remindMinutesBefore,
    bool clearReminder = false,
  }) => PlannedTraining(
    id: id,
    startsAt: startsAt ?? this.startsAt,
    kind: kind ?? this.kind,
    title: title ?? this.title,
    location: location ?? this.location,
    note: note ?? this.note,
    remindMinutesBefore: clearReminder
        ? null
        : (remindMinutesBefore ?? this.remindMinutesBefore),
  );
}

/// Vecht je onder of boven een gewichtsgrens (of geen klasse)?
enum WeightLimit {
  none('', 'Geen'),
  under('under', 'Onder'),
  over('over', 'Boven');

  const WeightLimit(this.dbName, this.label);
  final String dbName;
  final String label;

  static WeightLimit fromName(String? name) => WeightLimit.values.firstWhere(
    (w) => w.dbName == name,
    orElse: () => WeightLimit.none,
  );
}

/// Discipline van een wedstrijd.
enum Discipline {
  sport('sport', 'Sport sambo'),
  combat('combat', 'Combat sambo'),
  both('both', 'Sport + combat');

  const Discipline(this.dbName, this.label);
  final String dbName;
  final String label;

  static Discipline fromName(String? name) => Discipline.values.firstWhere(
    (d) => d.dbName == name,
    orElse: () => Discipline.sport,
  );
}

class Competition {
  final String id;
  final String name;
  final DateTime startsAt;
  final Discipline discipline;
  final String location;
  final String weightClass;
  final String goal;
  final bool dailyReminder;

  /// Tijdstip van de dagelijkse aftel-melding, "HH:mm".
  final String reminderTime;
  final int? resultPlace;
  final int? resultWins;
  final int? resultLosses;
  final String resultNote;

  /// Gewichtsklasse: grens en of je eronder of erboven vecht.
  final WeightLimit weightLimit;
  final double? weightLimitKg;

  /// Verwacht / gewenst gewicht op de weging.
  final double? targetWeightKg;

  /// Links naar het reglement en de toernooiwebsite (leeg = geen).
  final String rulesUrl;
  final String websiteUrl;

  const Competition({
    required this.id,
    required this.name,
    required this.startsAt,
    this.discipline = Discipline.sport,
    this.location = '',
    this.weightClass = '',
    this.goal = '',
    this.dailyReminder = true,
    this.reminderTime = '08:00',
    this.resultPlace,
    this.resultWins,
    this.resultLosses,
    this.resultNote = '',
    this.weightLimit = WeightLimit.none,
    this.weightLimitKg,
    this.targetWeightKg,
    this.rulesUrl = '',
    this.websiteUrl = '',
  });

  bool get hasResult =>
      resultPlace != null || resultWins != null || resultLosses != null;

  factory Competition.fromJson(Map<String, dynamic> json) => Competition(
    id: json['id'] as String,
    name: json['name'] as String,
    startsAt: DateTime.parse(json['starts_at'] as String).toLocal(),
    discipline: Discipline.fromName(json['discipline'] as String?),
    location: (json['location'] as String?) ?? '',
    weightClass: (json['weight_class'] as String?) ?? '',
    goal: (json['goal'] as String?) ?? '',
    dailyReminder: (json['daily_reminder'] as bool?) ?? true,
    reminderTime: (json['reminder_time'] as String?) ?? '08:00',
    resultPlace: (json['result_place'] as num?)?.toInt(),
    resultWins: (json['result_wins'] as num?)?.toInt(),
    resultLosses: (json['result_losses'] as num?)?.toInt(),
    resultNote: (json['result_note'] as String?) ?? '',
    weightLimit: WeightLimit.fromName(json['weight_limit_type'] as String?),
    weightLimitKg: (json['weight_limit_kg'] as num?)?.toDouble(),
    targetWeightKg: (json['target_weight_kg'] as num?)?.toDouble(),
    rulesUrl: (json['rules_url'] as String?) ?? '',
    websiteUrl: (json['website_url'] as String?) ?? '',
  );

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'starts_at': startsAt.toUtc().toIso8601String(),
    'discipline': discipline.dbName,
    'location': location.trim(),
    'weight_class': weightClass.trim(),
    'goal': goal.trim(),
    'daily_reminder': dailyReminder,
    'reminder_time': reminderTime,
    'result_place': resultPlace,
    'result_wins': resultWins,
    'result_losses': resultLosses,
    'result_note': resultNote.trim(),
    'weight_limit_type': weightLimitKg == null ? '' : weightLimit.dbName,
    'weight_limit_kg': weightLimit == WeightLimit.none ? null : weightLimitKg,
    'target_weight_kg': targetWeightKg,
    'rules_url': normalizeUrl(rulesUrl),
    'website_url': normalizeUrl(websiteUrl),
  };
}

/// Maakt van wat je intypt een bruikbare link: spaties weg, en "https://"
/// ervoor als je dat zelf weglaat ("sambo.nl/regels" → "https://…"). Leeg
/// blijft leeg.
String normalizeUrl(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(t)) return t;
  return 'https://$t';
}
