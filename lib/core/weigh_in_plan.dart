// weigh_in_plan.dart — wanneer je weer moet wegen: de laatste weging plus
// het ingestelde aantal dagen, op het ingestelde tijdstip.

/// "HH:mm" → minuten sinds middernacht (ongeldig → 08:00).
int _minutesOf(String time) {
  final parts = time.split(':');
  final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
  final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
  if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
    return 8 * 60;
  }
  return h * 60 + m;
}

/// [day] op [time] — via de velden, niet door minuten op te tellen, zodat
/// de zomer-/wintertijd het uur niet verschuift.
DateTime _at(DateTime day, String time, {int plusDays = 0}) {
  final minutes = _minutesOf(time);
  return DateTime(
    day.year,
    day.month,
    day.day + plusDays,
    minutes ~/ 60,
    minutes % 60,
  );
}

/// De geplande volgende weging, of null als er geen interval is ingesteld.
/// Nog nooit gewogen: vandaag. Kan in het verleden liggen (dan ben je te
/// laat) — zie [weighInReminderAt] voor het moment van de melding.
DateTime? nextWeighIn({
  required DateTime? last,
  required int intervalDays,
  required String reminderTime,
  required DateTime now,
}) {
  if (intervalDays <= 0) return null;
  if (last == null) return _at(now, reminderTime);
  return _at(last, reminderTime, plusDays: intervalDays);
}

/// Wanneer de herinnering afgaat: op [next], of — als dat moment al voorbij
/// is — de eerstvolgende keer dat het [reminderTime] is (vandaag of
/// morgen). Null als er geen weging gepland is.
DateTime? weighInReminderAt({
  required DateTime? next,
  required String reminderTime,
  required DateTime now,
}) {
  if (next == null) return null;
  if (next.isAfter(now)) return next;
  final today = _at(now, reminderTime);
  return today.isAfter(now)
      ? today
      : _at(now, reminderTime, plusDays: 1);
}
