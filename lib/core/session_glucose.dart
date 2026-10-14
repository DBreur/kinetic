// session_glucose.dart — nieuwe sensorwaarden bij de glucosecurve van een
// live sessie voegen. De sessie haalt elke minuut op; een sensor meet maar
// elke ~5 minuten, en als Android de app even stillegt (scherm uit,
// gepauzeerd en weggelegd) worden er metingen gemist. Deze functie vult die
// achteraf aan, zonder dubbele punten.

import '../models/glucose.dart';

/// Punten uit [incoming] die nieuw zijn voor [series]: na het laatste punt
/// van de curve (en niet vóór [sessionStart]), oplopend gesorteerd, zonder
/// dubbelen (zelfde moment binnen [sameWithin]).
List<GlucosePoint> newSessionPoints(
  List<GlucosePoint> series,
  Iterable<GlucosePoint> incoming, {
  required DateTime sessionStart,
  Duration sameWithin = const Duration(seconds: 30),
}) {
  final last = series.isEmpty ? null : series.last.at;
  final sorted = incoming.toList()..sort((a, b) => a.at.compareTo(b.at));
  final result = <GlucosePoint>[];
  for (final p in sorted) {
    if (p.at.isBefore(sessionStart.subtract(sameWithin))) continue;
    final prev = result.isNotEmpty ? result.last.at : last;
    if (prev != null && !p.at.isAfter(prev.add(sameWithin))) continue;
    result.add(p);
  }
  return result;
}

/// Hoeveel metingen je moet opvragen om het gat sinds [lastPoint] te
/// dichten (sensor: 1 per 5 min), minimaal 2 en hoogstens een dag.
int countToFill(DateTime? lastPoint, DateTime now) {
  if (lastPoint == null) return 12;
  final minutes = now.difference(lastPoint).inMinutes;
  return ((minutes / 5).ceil() + 2).clamp(2, 288);
}
