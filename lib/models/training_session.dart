// training_session.dart: een voltooide training uit de bestaande tabel
// `training_sessions`. Live sessies van Kinetic 2.0 schrijven blokken in
// hetzelfde formaat als de oude app (kind/name/meta/note/minutes/rounds...),
// zodat alle historie leesbaar blijft. Extra tellers staan in extra keys.

import '../core/glucose_rules.dart';
import 'glucose.dart';
import 'technique.dart';

class SessionTechniqueResult {
  final String name;
  final bool striking;
  final TechniqueCounts counts;
  const SessionTechniqueResult(this.name, this.striking, this.counts);
}

class TrainingSession {
  final String id;
  final String kind; // 'sambo' | 'kracht'
  final String title;
  final DateTime startedAt;
  final int durationMinutes;
  final String note;
  final List<GlucosePoint> glucoseSeries;
  final List<Map<String, dynamic>> blocks;

  const TrainingSession({
    required this.id,
    required this.kind,
    required this.title,
    required this.startedAt,
    required this.durationMinutes,
    this.note = '',
    this.glucoseSeries = const [],
    this.blocks = const [],
  });

  factory TrainingSession.fromJson(Map<String, dynamic> j) => TrainingSession(
    id: j['id'] as String,
    kind: (j['kind'] as String?) ?? 'sambo',
    title: (j['title'] as String?) ?? 'Training',
    startedAt: DateTime.parse(j['started_at'] as String).toLocal(),
    durationMinutes: (j['duration_minutes'] as num?)?.toInt() ?? 0,
    note: (j['note'] as String?) ?? '',
    glucoseSeries: [
      for (final g in (j['glucose_series'] as List?) ?? const [])
        if (g is Map<String, dynamic>) GlucosePoint.fromJson(g),
    ],
    blocks: [
      for (final b in (j['blocks'] as List?) ?? const [])
        if (b is Map<String, dynamic>) b,
    ],
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'kind': kind,
    'title': title,
    'started_at': startedAt.toUtc().toIso8601String(),
    'duration_minutes': durationMinutes,
    'note': note,
    'glucose_series': glucoseSeries.map((g) => g.toJson()).toList(),
    'blocks': blocks,
  };

  /// Kleur/discipline voor de sessiekaart.
  bool get isStrength => kind == 'kracht';

  bool get isCombat => title.toLowerCase().contains('combat');

  int get sparringRounds => blocks
      .where((b) => b['kind'] == 'sparring')
      .fold(0, (sum, b) => sum + ((b['rounds'] as num?)?.toInt() ?? 0));

  int get sparringMinutes => blocks
      .where((b) => b['kind'] == 'sparring')
      .fold(0, (sum, b) => sum + ((b['minutes'] as num?)?.toInt() ?? 0));

  List<String> get coveredTechniques => [
    for (final b in blocks)
      if (b['kind'] == 'technique' && (b['covered'] as bool? ?? true))
        (b['name'] as String?) ?? '',
  ].where((n) => n.isNotEmpty).toList();

  /// Tellers uit live sessies (alleen sessies van 2.0 hebben deze).
  List<SessionTechniqueResult> get techniqueResults => [
    for (final b in blocks)
      if (b['kind'] == 'technique' && b['counts'] is Map<String, dynamic>)
        SessionTechniqueResult(
          (b['name'] as String?) ?? '',
          (b['striking'] as bool?) ?? false,
          TechniqueCounts.fromJson(b['counts'] as Map<String, dynamic>),
        ),
  ];

  /// Succesratio (geslaagd / alle acties) over alle getelde technieken.
  double? get successRatio {
    var success = 0;
    var total = 0;
    for (final r in techniqueResults) {
      success += r.counts.success;
      total += r.counts.total;
    }
    return total == 0 ? null : success / total;
  }

  double? get glucoseSafeZone => timeInRange(glucoseSeries.map((g) => g.mmol));

  double? get glucoseStart =>
      glucoseSeries.isEmpty ? null : glucoseSeries.first.mmol;
  double? get glucoseEnd =>
      glucoseSeries.isEmpty ? null : glucoseSeries.last.mmol;
  double? get glucoseLowest => glucoseSeries.isEmpty
      ? null
      : glucoseSeries.map((g) => g.mmol).reduce((a, b) => a < b ? a : b);
}

/// Grove kcal-schatting: MET × kg × uur. Vechtsport-sparring ≈ MET 10,
/// krachttraining ≈ MET 5.
int estimateKcal({
  required int minutes,
  required double weightKg,
  bool strength = false,
}) {
  final met = strength ? 5.0 : 10.0;
  return (met * weightKg * minutes / 60).round();
}
