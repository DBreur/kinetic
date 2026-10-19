// session_times.dart — van/tot-tijden en duur van een training op één lijn
// houden. Puur en los te testen.
//
// • Van wijzigen: de training schuift, de duur blijft.
// • Tot wijzigen: de duur wordt tot − van (eindigt hij "eerder" dan hij
//   begint, dan loopt hij over middernacht door).
// • Duur wijzigen: de tot-tijd schuift mee.

/// Duur in minuten tussen [start] en een eindtijd op klokuren
/// ([endHour]:[endMinute]) — over middernacht telt als de volgende dag.
int durationUntil(DateTime start, int endHour, int endMinute) {
  final startMin = start.hour * 60 + start.minute;
  var endMin = endHour * 60 + endMinute;
  if (endMin < startMin) endMin += 24 * 60;
  return endMin - startMin;
}

/// Eindtijd bij een start en duur.
DateTime endFor(DateTime start, int durationMinutes) =>
    start.add(Duration(minutes: durationMinutes));

/// Zelfde dag, ander tijdstip (voor "van" aanpassen).
DateTime withTime(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

/// "19:00–20:30".
String timeRangeLabel(DateTime start, int? durationMinutes) {
  String hm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (durationMinutes == null) return hm(start);
  return '${hm(start)}–${hm(endFor(start, durationMinutes))}';
}
