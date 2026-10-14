import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/training_insights.dart';
import 'package:kinetic/models/food_log_entry.dart';
import 'package:kinetic/models/training_session.dart';

TrainingSession _session({
  required SessionKind kind,
  required DateTime startedAt,
  required List<double> mmolPoints,
  int durationMinutes = 30,
}) {
  return TrainingSession(
    id: 's-${startedAt.toIso8601String()}-${kind.name}',
    kind: kind,
    title: kind.name,
    startedAt: startedAt,
    durationMinutes: durationMinutes,
    glucoseSeries: [
      for (var i = 0; i < mmolPoints.length; i++)
        GlucosePoint(startedAt.add(Duration(minutes: i)), mmolPoints[i]),
    ],
  );
}

FoodLogEntry _food({required DateTime at, required double carbs}) =>
    FoodLogEntry(
      id: 'f-${at.toIso8601String()}',
      at: at,
      description: 'test',
      carbs: carbs,
    );

void main() {
  final now = DateTime(2026, 6, 15, 18, 0);

  group('TrainingInsights.compute — periode-filter', () {
    test('sessies buiten de gekozen week vallen weg', () {
      final inWeek = _session(
        kind: SessionKind.kracht,
        startedAt: now.subtract(const Duration(days: 2)),
        mmolPoints: [6.0, 6.5],
      );
      final outsideWeek = _session(
        kind: SessionKind.kracht,
        startedAt: now.subtract(const Duration(days: 20)),
        mmolPoints: [6.0],
      );

      final insights = TrainingInsights.compute(
        sessions: [inWeek, outsideWeek],
        foodLogEntries: const [],
        period: InsightPeriod.week,
        now: now,
      );

      expect(insights.totalSessions, 1);
    });

    test('InsightPeriod.all negeert de datumgrens volledig', () {
      final old = _session(
        kind: SessionKind.sambo,
        startedAt: DateTime(2020, 1, 1),
        mmolPoints: [6.0],
      );
      final insights = TrainingInsights.compute(
        sessions: [old],
        foodLogEntries: const [],
        period: InsightPeriod.all,
        now: now,
      );
      expect(insights.totalSessions, 1);
    });
  });

  group('TrainingInsights.compute — per-soort statistieken', () {
    test('gemiddelde en laagste glucose worden apart per kind berekend', () {
      final sambo = _session(
        kind: SessionKind.sambo,
        startedAt: now.subtract(const Duration(hours: 2)),
        mmolPoints: [8.0, 4.0], // gemiddeld 6.0, laagste 4.0 → dip (<5.0)
      );
      final kracht = _session(
        kind: SessionKind.kracht,
        startedAt: now.subtract(const Duration(hours: 1)),
        mmolPoints: [7.0, 7.0], // gemiddeld 7.0, geen dip
      );

      final insights = TrainingInsights.compute(
        sessions: [sambo, kracht],
        foodLogEntries: const [],
        period: InsightPeriod.all,
        now: now,
      );

      final samboStats = insights.byKind[SessionKind.sambo]!;
      final krachtStats = insights.byKind[SessionKind.kracht]!;

      expect(samboStats.count, 1);
      expect(samboStats.avgMmol, 6.0);
      expect(samboStats.lowestMmol, 4.0);
      expect(samboStats.dipCount, 1);
      expect(samboStats.dipPercent, 100.0);

      expect(krachtStats.count, 1);
      expect(krachtStats.avgMmol, 7.0);
      expect(krachtStats.dipCount, 0);
      expect(krachtStats.dipPercent, 0.0);
    });

    test('lege selectie geeft null-statistieken, geen crash', () {
      final insights = TrainingInsights.compute(
        sessions: const [],
        foodLogEntries: const [],
        period: InsightPeriod.all,
        now: now,
      );
      expect(insights.totalSessions, 0);
      expect(insights.overallInRangePercent, isNull);
      expect(insights.byKind[SessionKind.sambo]!.avgMmol, isNull);
      expect(insights.byKind[SessionKind.sambo]!.dipPercent, isNull);
    });
  });

  group('TrainingInsights.compute — koolhydraten vóór training', () {
    test(
      'koolhydraten binnen het venster vóór start tellen mee als "hoger"',
      () {
        final start = now;
        final session = _session(
          kind: SessionKind.kracht,
          startedAt: start,
          mmolPoints: [4.0], // dip
        );
        final carbsJustBefore = _food(
          at: start.subtract(const Duration(minutes: 30)),
          carbs: 20,
        );

        final insights = TrainingInsights.compute(
          sessions: [session],
          foodLogEntries: [carbsJustBefore],
          period: InsightPeriod.all,
          now: now,
        );

        expect(insights.carbsBeforeTraining.higherCarbSessions, 1);
        expect(insights.carbsBeforeTraining.higherCarbDips, 1);
        expect(insights.carbsBeforeTraining.lowCarbSessions, 0);
      },
    );

    test('koolhydraten buiten het venster (te vroeg) tellen niet mee', () {
      final start = now;
      final session = _session(
        kind: SessionKind.kracht,
        startedAt: start,
        mmolPoints: [7.0],
      );
      final tooEarly = _food(
        at: start.subtract(const Duration(hours: 3)),
        carbs: 40,
      );

      final insights = TrainingInsights.compute(
        sessions: [session],
        foodLogEntries: [tooEarly],
        period: InsightPeriod.all,
        now: now,
      );

      // Geen koolhydraten binnen het venster gevonden → telt als "weinig".
      expect(insights.carbsBeforeTraining.lowCarbSessions, 1);
      expect(insights.carbsBeforeTraining.higherCarbSessions, 0);
    });

    test('hasEnoughData is pas waar vanaf 3 sessies in beide groepen', () {
      const comparison = CarbsBeforeTrainingComparison(
        lowCarbSessions: 2,
        lowCarbDips: 0,
        higherCarbSessions: 5,
        higherCarbDips: 1,
      );
      expect(comparison.hasEnoughData, isFalse);

      const enough = CarbsBeforeTrainingComparison(
        lowCarbSessions: 3,
        lowCarbDips: 1,
        higherCarbSessions: 3,
        higherCarbDips: 0,
      );
      expect(enough.hasEnoughData, isTrue);
      expect(enough.lowCarbDipPercent, closeTo(33.33, 0.1));
      expect(enough.higherCarbDipPercent, 0.0);
    });
  });

  group('TrainingInsights.compute — verdeling & verandering', () {
    test('onder/in/boven bereik tellen op tot 100%', () {
      final s = _session(
        kind: SessionKind.sambo,
        startedAt: now.subtract(const Duration(days: 1)),
        mmolPoints: [3.5, 6.0, 7.0, 11.0],
      );
      final i = TrainingInsights.compute(
        sessions: [s],
        foodLogEntries: const [],
        period: InsightPeriod.week,
        now: now,
      );
      expect(i.overallLowPercent, 25);
      expect(i.overallInRangePercent, 50);
      expect(i.overallHighPercent, 25);
    });

    test('gemiddelde verandering per kind negeert sessies met één meting', () {
      final sessions = [
        _session(
          kind: SessionKind.sambo,
          startedAt: now.subtract(const Duration(days: 1)),
          mmolPoints: [6.0, 8.0],
        ),
        _session(
          kind: SessionKind.sambo,
          startedAt: now.subtract(const Duration(days: 2)),
          mmolPoints: [7.0, 8.0],
        ),
        _session(
          kind: SessionKind.sambo,
          startedAt: now.subtract(const Duration(days: 3)),
          mmolPoints: [9.0],
        ),
        _session(
          kind: SessionKind.kracht,
          startedAt: now.subtract(const Duration(days: 1)),
          mmolPoints: [8.0, 6.0],
        ),
      ];
      final i = TrainingInsights.compute(
        sessions: sessions,
        foodLogEntries: const [],
        period: InsightPeriod.week,
        now: now,
      );
      expect(i.byKind[SessionKind.sambo]!.avgDeltaMmol, closeTo(1.5, 1e-9));
      expect(i.byKind[SessionKind.kracht]!.avgDeltaMmol, closeTo(-2.0, 1e-9));
    });

    test('zonder metingen zijn verdeling en verandering null', () {
      final i = TrainingInsights.compute(
        sessions: const [],
        foodLogEntries: const [],
        period: InsightPeriod.all,
        now: now,
      );
      expect(i.overallLowPercent, isNull);
      expect(i.overallHighPercent, isNull);
      expect(i.byKind[SessionKind.sambo]!.avgDeltaMmol, isNull);
    });
  });
}
