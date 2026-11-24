// glucose_rules.dart: doelbereik, kleuren, trendpijlen en de "mag ik de mat
// op?"-check. Pure functies, zodat de veiligheidslogica los te testen is.

import 'package:material_ui/material_ui.dart';

import '../models/glucose.dart';
import '../theme/kinetic_theme.dart';

/// Doelbereik uit de spec (4.2 - 9.0 mmol/L) en de hypogrens (< 4.0).
const double targetLow = 4.2;
const double targetHigh = 9.0;
const double hypoBelow = 4.0;

/// Boven deze waarde adviseren de ADA/ISPAD-richtlijnen ketonen te meten
/// voordat je (verder) traint.
const double ketoneCheckAbove = 13.9;

enum GlucoseZone { hypo, low, inTarget, high }

GlucoseZone zoneFor(double mmol) {
  if (mmol < hypoBelow) return GlucoseZone.hypo;
  if (mmol < targetLow) return GlucoseZone.low;
  if (mmol <= targetHigh) return GlucoseZone.inTarget;
  return GlucoseZone.high;
}

Color glucoseColor(double mmol) => switch (zoneFor(mmol)) {
  GlucoseZone.hypo => KColor.danger,
  GlucoseZone.low => KColor.warning,
  GlucoseZone.inTarget => KColor.success,
  GlucoseZone.high => KColor.warning,
};

String trendArrow(Trend t) => switch (t) {
  Trend.up => '↑',
  Trend.slightUp => '↗',
  Trend.flat => '→',
  Trend.slightDown => '↘',
  Trend.down => '↓',
  Trend.fastDown => '⇊',
};

String trendLabel(Trend t) => switch (t) {
  Trend.up => 'Snel stijgend',
  Trend.slightUp => 'Licht stijgend',
  Trend.flat => 'Stabiel',
  Trend.slightDown => 'Licht dalend',
  Trend.down => 'Dalend',
  Trend.fastDown => 'Snel dalend',
};

bool isFalling(Trend t) =>
    t == Trend.slightDown || t == Trend.down || t == Trend.fastDown;

/// Fractie van de metingen binnen het doelbereik (0..1), of null zonder data.
double? timeInRange(Iterable<double> values) {
  var total = 0;
  var inRange = 0;
  for (final v in values) {
    total++;
    if (v >= targetLow && v <= targetHigh) inRange++;
  }
  return total == 0 ? null : inRange / total;
}

enum ClearanceLevel { safe, caution, danger, unknown }

class MatClearance {
  final ClearanceLevel level;
  final String title;
  final String detail;

  const MatClearance(this.level, this.title, this.detail);

  Color get color => switch (level) {
    ClearanceLevel.safe => KColor.success,
    ClearanceLevel.caution => KColor.warning,
    ClearanceLevel.danger => KColor.danger,
    ClearanceLevel.unknown => KColor.textSecondary,
  };

  /// Alleen bij echt gevaar houden we de volgende ronde tegen.
  bool get blocksNextRound => level == ClearanceLevel.danger;
}

/// Beoordeelt of de volgende ronde veilig kan starten. [trainingLimit] is de
/// eigen ondergrens uit het profiel (profiles.training_limit).
MatClearance matClearance({
  required GlucoseReading? reading,
  required String roundLabel,
  double trainingLimit = 5.0,
  DateTime? now,
}) {
  if (reading == null) {
    return MatClearance(
      ClearanceLevel.unknown,
      'Geen glucosewaarde',
      'Meet met een vingerprik vóór $roundLabel.',
    );
  }
  final age = (now ?? DateTime.now()).difference(reading.at).inMinutes;
  final mmol = reading.mmol;
  final v = mmol.toStringAsFixed(1);

  if (mmol < hypoBelow) {
    return MatClearance(
      ClearanceLevel.danger,
      'Hypo: niet starten',
      '$v mmol/L. Neem 15g snelle koolhydraten en meet na 15 minuten opnieuw.',
    );
  }
  if (age >= 15) {
    return MatClearance(
      ClearanceLevel.unknown,
      'Meting $age min oud',
      'Sensorverbinding kwijt? Meet met een vingerprik vóór $roundLabel.',
    );
  }
  if (mmol < trainingLimit) {
    return MatClearance(
      ClearanceLevel.caution,
      'Onder je trainingsgrens',
      '$v mmol/L (grens ${trainingLimit.toStringAsFixed(1)}). Overweeg +15g dextrose.',
    );
  }
  if (isFalling(reading.trend) && mmol < 7.0) {
    return MatClearance(
      ClearanceLevel.caution,
      'Dalende trend',
      '$v mmol/L ${trendArrow(reading.trend)}. Overweeg +15g dextrose vóór $roundLabel.',
    );
  }
  if (mmol > ketoneCheckAbove) {
    return MatClearance(
      ClearanceLevel.caution,
      'Hoog: check ketonen',
      '$v mmol/L. Boven ${ketoneCheckAbove.toStringAsFixed(1)} eerst ketonen meten.',
    );
  }
  return MatClearance(
    ClearanceLevel.safe,
    'Veilig voor $roundLabel',
    'Stabiel doelbereik ${targetLow.toStringAsFixed(1)} - ${targetHigh.toStringAsFixed(1)} mmol/L',
  );
}
