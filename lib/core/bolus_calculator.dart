// bolus_calculator.dart — berekent een voorstel voor de insulinedosis bij
// het loggen van eten: voedingsinsuline (koolhydraten / ratio van het
// actieve tijdvak) en correctie-insuline (verschil met de streefwaarde /
// correctiefactor, nooit negatief). Zuivere, makkelijk te testen functies —
// geen UI- of profielafhankelijkheden.

import '../models/bolus_period.dart';

/// Rondt een insulinedosis af op de dichtstbijzijnde halve eenheid — spuiten
/// gaat nu eenmaal in stappen van 0,5 E.
double roundToHalfUnit(double units) => (units * 2).round() / 2;

/// Minuten sinds middernacht voor een "HH:mm"-string.
int minutesOfDay(String hhmm) {
  final parts = hhmm.split(':');
  final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return h * 60 + m;
}

/// Het tijdvak dat geldt op [at] — het laatst gestarte tijdvak vóór of op dat
/// tijdstip, met wrap-around: ligt [at] vóór het vroegste tijdvak van de dag,
/// dan geldt het laatste tijdvak (dat "doorloopt" vanaf de vorige dag).
BolusPeriod? activePeriod(List<BolusPeriod> periods, DateTime at) {
  if (periods.isEmpty) return null;
  final sorted = [...periods]
    ..sort((a, b) => a.startMinutes.compareTo(b.startMinutes));
  final nowMinutes = at.hour * 60 + at.minute;
  BolusPeriod? active;
  for (final p in sorted) {
    if (p.startMinutes <= nowMinutes) active = p;
  }
  return active ?? sorted.last;
}

/// Of [at] in het nachtvenster valt ([nightStart]–[nightEnd], beide
/// "HH:mm") — met correcte afhandeling als dat venster middernacht
/// overschrijdt (bv. 19:00–05:00).
bool isNight(DateTime at, String nightStart, String nightEnd) {
  final start = minutesOfDay(nightStart);
  final end = minutesOfDay(nightEnd);
  if (start == end) return false;
  final nowMinutes = at.hour * 60 + at.minute;
  if (start < end) return nowMinutes >= start && nowMinutes < end;
  return nowMinutes >= start || nowMinutes < end;
}

class BolusSuggestion {
  final double? foodDose;
  final double? correctionDose;
  final double? total;
  final BolusPeriod? period;

  const BolusSuggestion({
    this.foodDose,
    this.correctionDose,
    this.total,
    this.period,
  });
}

/// Berekent het voorstel voor voedings- en correctie-insuline op [at].
/// Geeft `null`-onderdelen terug als er te weinig gegevens zijn (geen
/// koolhydraten, geen tijdvak, een ratio van 0) — nooit een deling door
/// nul, nooit een negatieve correctiedosis.
BolusSuggestion calculateBolus({
  required List<BolusPeriod> periods,
  double? carbs,
  double? currentMmol,
  required double correctionFactor,
  required double correctionTargetDay,
  required double correctionTargetNight,
  required String nightStart,
  required String nightEnd,
  required DateTime at,
}) {
  final period = activePeriod(periods, at);
  final foodDose =
      (carbs != null && carbs > 0 && period != null && period.carbRatio > 0)
      ? roundToHalfUnit(carbs / period.carbRatio)
      : null;

  double? correctionDose;
  if (currentMmol != null && correctionFactor > 0) {
    final target = isNight(at, nightStart, nightEnd)
        ? correctionTargetNight
        : correctionTargetDay;
    correctionDose = currentMmol > target
        ? roundToHalfUnit((currentMmol - target) / correctionFactor)
        : 0.0;
  }

  final total = (foodDose != null || correctionDose != null)
      ? (foodDose ?? 0) + (correctionDose ?? 0)
      : null;

  return BolusSuggestion(
    foodDose: foodDose,
    correctionDose: correctionDose,
    total: total,
    period: period,
  );
}
