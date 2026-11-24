// iob.dart: Insulin On Board, geschat uit de insuline die je in het
// eetlogboek noteert. Gebruikt de exponentiële snelwerkende-insulinecurve
// van OpenAPS/oref0 (piek 75 min, werkingsduur 5 uur). Het blijft een
// schatting: een pomp of pen met dosislog weet het beter.

import 'dart:math' as math;

const Duration insulinActionDuration = Duration(hours: 5);
const Duration insulinPeak = Duration(minutes: 75);

/// Fractie (0..1) van een bolus die na [elapsed] nog actief is.
double iobFraction(Duration elapsed) {
  final t = elapsed.inSeconds / 60.0;
  final td = insulinActionDuration.inMinutes.toDouble();
  final tp = insulinPeak.inMinutes.toDouble();
  if (t <= 0) return 1;
  if (t >= td) return 0;
  final tau = tp * (1 - tp / td) / (1 - 2 * tp / td);
  final a = 2 * tau / td;
  final s = 1 / (1 - a + (1 + a) * math.exp(-td / tau));
  final fraction =
      1 -
      s *
          (1 - a) *
          ((t * t / (tau * td * (1 - a)) - t / tau - 1) * math.exp(-t / tau) +
              1);
  return fraction.clamp(0.0, 1.0);
}

class InsulinDose {
  final DateTime at;
  final double units;
  const InsulinDose(this.at, this.units);
}

/// Totale actieve insuline (E) op [now].
double insulinOnBoard(Iterable<InsulinDose> doses, {DateTime? now}) {
  final t = now ?? DateTime.now();
  var total = 0.0;
  for (final d in doses) {
    if (d.units <= 0) continue;
    total += d.units * iobFraction(t.difference(d.at));
  }
  return total;
}
