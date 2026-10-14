// glucose_entry.dart — een handmatig ingevoerde (vingerprik) glucosewaarde.

class ManualGlucoseEntry {
  final String id;
  final double mmol;
  final DateTime at;

  const ManualGlucoseEntry({
    required this.id,
    required this.mmol,
    required this.at,
  });

  factory ManualGlucoseEntry.fromJson(Map<String, dynamic> json) =>
      ManualGlucoseEntry(
        id: json['id'] as String,
        mmol: (json['mmol'] as num).toDouble(),
        at: DateTime.parse(json['at'] as String).toLocal(),
      );
}
