// planned_training.dart: een geplande training uit `planned_trainings`
// (de agenda van de oude app). Kan vanuit Vandaag/Training gestart worden.

enum TrainingKind {
  sportSambo('sport_sambo', 'Sport Sambo'),
  combatSambo('combat_sambo', 'Combat Sambo'),
  kracht('kracht', 'Kracht'),
  overig('overig', 'Overig');

  const TrainingKind(this.dbName, this.label);
  final String dbName;
  final String label;

  static TrainingKind fromName(String? name) => TrainingKind.values.firstWhere(
    (k) => k.dbName == name,
    orElse: () => TrainingKind.overig,
  );
}

class PlannedTraining {
  final String id;
  final DateTime startsAt;
  final TrainingKind kind;
  final String title;
  final String location;
  final String note;
  final int? durationMinutes;
  final List<String> techniqueIds;

  const PlannedTraining({
    required this.id,
    required this.startsAt,
    this.kind = TrainingKind.overig,
    this.title = '',
    this.location = '',
    this.note = '',
    this.durationMinutes,
    this.techniqueIds = const [],
  });

  factory PlannedTraining.fromJson(Map<String, dynamic> j) => PlannedTraining(
    id: j['id'] as String,
    startsAt: DateTime.parse(j['starts_at'] as String).toLocal(),
    kind: TrainingKind.fromName(j['kind'] as String?),
    title: (j['title'] as String?) ?? '',
    location: (j['location'] as String?) ?? '',
    note: (j['note'] as String?) ?? '',
    durationMinutes: (j['duration_minutes'] as num?)?.toInt(),
    techniqueIds: [
      for (final x in (j['technique_ids'] as List?) ?? const [])
        if (x is String) x,
    ],
  );

  String get displayTitle => title.trim().isEmpty ? kind.label : title.trim();
}
