// training_insights.dart — pure aggregatielogica voor het Inzicht-scherm.
//
// Combineert data die al wordt opgeslagen (trainingssessies met hun
// glucose-curve, en het eetlogboek) tot beschrijvende statistieken over hoe
// sport en glucose samenhangen. Puur berekenend, geen UI — en bewust geen
// enkel advies of aanbeveling: alleen cijfers/feiten (zie CLAUDE-regels).

import '../models/food_log_entry.dart';
import '../models/training_session.dart';

enum InsightPeriod {
  week,
  month,
  all;

  String get label => switch (this) {
    InsightPeriod.week => 'Week',
    InsightPeriod.month => 'Maand',
    InsightPeriod.all => 'Alles',
  };

  /// Null betekent "geen ondergrens" (alle sessies).
  DateTime? since(DateTime now) => switch (this) {
    InsightPeriod.week => now.subtract(const Duration(days: 7)),
    InsightPeriod.month => now.subtract(const Duration(days: 30)),
    InsightPeriod.all => null,
  };
}

/// Statistieken voor één type training (sambo of kracht) binnen de gekozen
/// periode.
class SessionKindStats {
  final int count;
  final double? avgMmol;
  final double? lowestMmol;
  final int dipCount;

  /// Gemiddelde verandering (laatste − eerste meting) per sessie, over de
  /// sessies met minstens twee metingen. Null als er geen zijn.
  final double? avgDeltaMmol;

  const SessionKindStats({
    required this.count,
    required this.avgMmol,
    required this.lowestMmol,
    required this.dipCount,
    this.avgDeltaMmol,
  });

  double? get dipPercent => count == 0 ? null : dipCount / count * 100;
}

/// Vergelijkt sessies met weinig koolhydraten vlak vooraf tegen sessies met
/// meer koolhydraten vlak vooraf — puur een beschrijvende vergelijking,
/// geen aanbeveling.
class CarbsBeforeTrainingComparison {
  final int lowCarbSessions;
  final int lowCarbDips;
  final int higherCarbSessions;
  final int higherCarbDips;

  const CarbsBeforeTrainingComparison({
    required this.lowCarbSessions,
    required this.lowCarbDips,
    required this.higherCarbSessions,
    required this.higherCarbDips,
  });

  double? get lowCarbDipPercent =>
      lowCarbSessions == 0 ? null : lowCarbDips / lowCarbSessions * 100;

  double? get higherCarbDipPercent => higherCarbSessions == 0
      ? null
      : higherCarbDips / higherCarbSessions * 100;

  /// Bij te weinig sessies in een van beide groepen zegt een percentage
  /// niets zinnigs — dan liever niet tonen dan een vals gevoel van zekerheid.
  bool get hasEnoughData => lowCarbSessions >= 3 && higherCarbSessions >= 3;
}

class TrainingInsights {
  final InsightPeriod period;
  final int totalSessions;
  final int totalMinutes;
  final double? overallInRangePercent;

  /// Aandeel metingen onder [lowMmol] / boven [highMmol] — samen met
  /// [overallInRangePercent] telt dit op tot 100.
  final double? overallLowPercent;
  final double? overallHighPercent;
  final Map<SessionKind, SessionKindStats> byKind;
  final CarbsBeforeTrainingComparison carbsBeforeTraining;

  const TrainingInsights({
    required this.period,
    required this.totalSessions,
    required this.totalMinutes,
    required this.overallInRangePercent,
    this.overallLowPercent,
    this.overallHighPercent,
    required this.byKind,
    required this.carbsBeforeTraining,
  });

  static const lowMmol = 3.9;
  static const highMmol = 10.0;

  /// Grens en terugkijkvenster voor de koolhydraten-vergelijking: minder dan
  /// dit aantal gram binnen dit venster vóór de start telt als "weinig".
  static const carbThresholdGrams = 15.0;
  static const carbLookback = Duration(minutes: 90);

  factory TrainingInsights.compute({
    required List<TrainingSession> sessions,
    required List<FoodLogEntry> foodLogEntries,
    required InsightPeriod period,
    DateTime? now,
  }) {
    final since = period.since(now ?? DateTime.now());
    final scoped = since == null
        ? sessions
        : sessions.where((s) => s.startedAt.isAfter(since)).toList();

    final totalMinutes = scoped.fold<int>(0, (n, s) => n + s.durationMinutes);
    final allPoints = scoped.expand((s) => s.glucoseSeries).toList();
    final inRange = allPoints.isEmpty
        ? null
        : allPoints
                  .where((g) => g.mmol >= lowMmol && g.mmol <= highMmol)
                  .length /
              allPoints.length *
              100;
    double? share(bool Function(double) test) => allPoints.isEmpty
        ? null
        : allPoints.where((g) => test(g.mmol)).length / allPoints.length * 100;

    final byKind = <SessionKind, SessionKindStats>{
      for (final kind in SessionKind.values)
        kind: _statsFor(scoped.where((s) => s.kind == kind).toList()),
    };

    return TrainingInsights(
      period: period,
      totalSessions: scoped.length,
      totalMinutes: totalMinutes,
      overallInRangePercent: inRange,
      overallLowPercent: share((v) => v < lowMmol),
      overallHighPercent: share((v) => v > highMmol),
      byKind: byKind,
      carbsBeforeTraining: _carbsBeforeTraining(scoped, foodLogEntries),
    );
  }

  static SessionKindStats _statsFor(List<TrainingSession> sessions) {
    final points = sessions.expand((s) => s.glucoseSeries).toList();
    final avg = points.isEmpty
        ? null
        : points.map((g) => g.mmol).reduce((a, b) => a + b) / points.length;
    final lowest = points.isEmpty
        ? null
        : points.map((g) => g.mmol).reduce((a, b) => a < b ? a : b);
    final deltas = [
      for (final s in sessions)
        if (s.glucoseSeries.length >= 2)
          s.glucoseSeries.last.mmol - s.glucoseSeries.first.mmol,
    ];
    return SessionKindStats(
      count: sessions.length,
      avgMmol: avg,
      lowestMmol: lowest,
      dipCount: sessions.where((s) => s.hadDip).length,
      avgDeltaMmol: deltas.isEmpty
          ? null
          : deltas.reduce((a, b) => a + b) / deltas.length,
    );
  }

  static CarbsBeforeTrainingComparison _carbsBeforeTraining(
    List<TrainingSession> sessions,
    List<FoodLogEntry> foodLogEntries,
  ) {
    var lowCount = 0, lowDips = 0, highCount = 0, highDips = 0;
    for (final s in sessions) {
      final windowStart = s.startedAt.subtract(carbLookback);
      final carbsBefore = foodLogEntries
          .where((e) => e.at.isAfter(windowStart) && e.at.isBefore(s.startedAt))
          .fold<double>(0, (n, e) => n + (e.carbs ?? 0));
      if (carbsBefore < carbThresholdGrams) {
        lowCount++;
        if (s.hadDip) lowDips++;
      } else {
        highCount++;
        if (s.hadDip) highDips++;
      }
    }
    return CarbsBeforeTrainingComparison(
      lowCarbSessions: lowCount,
      lowCarbDips: lowDips,
      higherCarbSessions: highCount,
      higherCarbDips: highDips,
    );
  }
}
