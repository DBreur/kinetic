// glucose_entry.dart — een handmatig ingevoerde (vingerprik) glucosewaarde.

import 'glucose.dart';

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

/// Glucosestand op basis van vingerprikken (nieuwste eerst): de laatste
/// meting, met een trend t.o.v. de vorige.
GlucoseSnapshot snapshotFromFingerEntries(List<ManualGlucoseEntry> entries) {
  if (entries.isEmpty) {
    return const GlucoseSnapshot(
      reading: null,
      history: [],
      message: 'Voer je eerste vingerprik in.',
    );
  }
  final latest = entries.first;
  final trend = entries.length > 1
      ? trendFromDelta(latest.mmol - entries[1].mmol)
      : Trend.flat;
  return GlucoseSnapshot(
    reading: GlucoseReading(latest.mmol, trend, latest.at),
    history: entries.reversed.map((e) => GlucosePoint(e.at, e.mmol)).toList(),
  );
}
