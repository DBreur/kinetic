// meal_impact.dart: de context-chips van het maaltijdformulier en de
// "Verwachte Glucose Impact"-voorspeller. De factoren zijn een bewust
// eenvoudige vuistregel (mmol/L stijging per gram koolhydraat, afhankelijk
// van of je spieren de suiker direct verbruiken), geen medisch model.

enum MealContext {
  preTraining('pre_training', '⚡ Vóór Training / Sparring (~30m)', '#pre-sparring'),
  postTraining('post_training', '🔄 Direct Na Training', '#post-training'),
  acute('acute', '🛡️ Acute Mat-Interventie', '#mat-interventie'),
  recovery('recovery', '🥗 Regulier Herstel', '#herstel');

  const MealContext(this.dbName, this.label, this.tag);
  final String dbName;
  final String label;

  /// Tag voor de Dexcom-annotatie in de tijdlijn.
  final String tag;

  String get shortLabel => switch (this) {
    MealContext.preTraining => 'Vóór training',
    MealContext.postTraining => 'Na training',
    MealContext.acute => 'Mat-interventie',
    MealContext.recovery => 'Herstel',
  };

  static MealContext? fromName(String? name) {
    for (final c in MealContext.values) {
      if (c.dbName == name) return c;
    }
    return null;
  }
}

class ImpactRange {
  final double low;
  final double high;
  const ImpactRange(this.low, this.high);

  bool get isNeutral => high.abs() < 0.3 && low.abs() < 0.3;

  String format() {
    String s(double v) => '${v >= 0 ? '+' : ''}${v.toStringAsFixed(1)}';
    if (isNeutral) return '≈ neutraal';
    return '${s(low)} tot ${s(high)} mmol/L';
  }
}

/// mmol/L per gram koolhydraten (laag, hoog) per context.
/// Vóór/na training verbruiken de spieren een deel direct; een acute
/// interventie is meestal snelle dextrose (regel van 15: 15g ≈ +1 tot +2).
const _factors = {
  MealContext.preTraining: (0.04, 0.06),
  MealContext.postTraining: (0.06, 0.09),
  MealContext.acute: (0.07, 0.12),
  MealContext.recovery: (0.10, 0.15),
};

/// Verwachte stijging in de komende ~60-90 minuten. Insuline die je erbij
/// spuit gaat eraf via je correctiefactor (mmol/L per eenheid, uit je profiel).
ImpactRange predictGlucoseImpact({
  required double carbs,
  required MealContext context,
  double insulinUnits = 0,
  double correctionFactor = 2.0,
}) {
  final (lo, hi) = _factors[context]!;
  final insulinDrop = insulinUnits * correctionFactor;
  return ImpactRange(carbs * lo - insulinDrop, carbs * hi - insulinDrop);
}
