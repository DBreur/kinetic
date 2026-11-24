// weight_plan.dart: rekent de veilige gewichtscorridor voor een T1D-vechter
// uit. Maximaal 0.5 - 0.8 kg per week afvallen (spec); sneller verhoogt het
// risico op uitdroging en DKA.

const double safeLossPerWeekMin = 0.5;
const double safeLossPerWeekMax = 0.8;

/// Maximale water cut vlak voor de weging (als fractie van lichaamsgewicht).
const double maxWaterCutFraction = 0.025;

enum WeightDirection { lose, gain, onTarget }

class WeightPlan {
  final double currentKg;
  final double targetKg;
  final DateTime now;
  final DateTime weighDay;

  const WeightPlan({
    required this.currentKg,
    required this.targetKg,
    required this.now,
    required this.weighDay,
  });

  /// Negatief = afvallen, positief = aankomen.
  double get deltaKg => double.parse((targetKg - currentKg).toStringAsFixed(1));

  WeightDirection get direction {
    if (deltaKg.abs() < 0.05) return WeightDirection.onTarget;
    return deltaKg < 0 ? WeightDirection.lose : WeightDirection.gain;
  }

  double get weeksLeft {
    final days = weighDay.difference(now).inHours / 24.0;
    return days <= 0 ? 0 : days / 7.0;
  }

  /// Benodigd tempo in kg/week (positief getal), of null als er geen tijd is.
  double? get requiredKgPerWeek {
    if (weeksLeft <= 0) return null;
    return deltaKg.abs() / weeksLeft;
  }

  /// Wat je met een veilige water cut op de dag zelf nog mag overbruggen.
  double get maxWaterCutKg => currentKg * maxWaterCutFraction;

  /// Haalbaar binnen de corridor (plus hooguit een kleine water cut)?
  bool get isSafe {
    if (direction != WeightDirection.lose) return true;
    final reachable = weeksLeft * safeLossPerWeekMax + maxWaterCutKg;
    return deltaKg.abs() <= reachable + 1e-9;
  }

  /// Ondergrens/bovengrens van de corridor op [at] (lineair vanaf nu).
  (double fast, double slow) corridorAt(DateTime at) {
    final weeks = at.difference(now).inHours / (24.0 * 7.0);
    if (weeks <= 0) return (currentKg, currentKg);
    return (
      currentKg - weeks * safeLossPerWeekMax,
      currentKg - weeks * safeLossPerWeekMin,
    );
  }
}
