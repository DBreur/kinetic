// weigh_in.dart — één weging: gewicht met het moment waarop je woog. Het
// actuele gewicht staat daarnaast nog in profiles.weight_kg (voor de
// gewichtsklasse bij wedstrijden); de lijst wegingen geeft "laatst gewogen"
// en het verloop.

class WeighIn {
  final String id;
  final DateTime measuredAt;
  final double weightKg;

  const WeighIn({
    required this.id,
    required this.measuredAt,
    required this.weightKg,
  });

  factory WeighIn.fromJson(Map<String, dynamic> json) => WeighIn(
    id: json['id'] as String,
    measuredAt: DateTime.parse(json['measured_at'] as String).toLocal(),
    weightKg: (json['weight_kg'] as num).toDouble(),
  );

  Map<String, dynamic> toInsertJson(String userId) => {
    'user_id': userId,
    'measured_at': measuredAt.toUtc().toIso8601String(),
    'weight_kg': double.parse(weightKg.toStringAsFixed(1)),
  };
}
