// glucose_prefill.dart — mag een bekende glucosewaarde automatisch worden
// ingevuld bij een nieuw eetmoment? Alleen als hij recent is: een sensor
// meet elke ~5 minuten, dus ouder dan 15 minuten is verdacht; een
// vingerprik mag iets ouder zijn (30 minuten), je prikt niet continu.

import '../models/glucose.dart';

bool isPrefillableReading(
  GlucoseReading reading,
  bool fromSensor, {
  DateTime? now,
}) {
  final age = (now ?? DateTime.now()).difference(reading.at);
  if (age.isNegative) return true;
  return age <= Duration(minutes: fromSensor ? 15 : 30);
}
