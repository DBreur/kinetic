// live_session_restore_test.dart — een lopende training moet terugkomen als
// de app sluit, en de glucosecurve moet nieuwe/gemiste metingen netjes
// aanvullen (zonder dubbelen).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/session_glucose.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/mat_session_controller.dart';
import 'package:kinetic/state/strength_session_controller.dart';
import 'package:kinetic/widgets/block_widgets.dart';

void main() {
  group('glucose in een live sessie', () {
    final start = DateTime(2026, 10, 14, 19);
    GlucosePoint p(int min, double v) =>
        GlucosePoint(start.add(Duration(minutes: min)), v);

    test('alleen nieuwe punten, gemiste metingen aangevuld, gesorteerd', () {
      final series = [p(0, 6.0), p(5, 6.2)];
      final fresh = newSessionPoints(series, [
        p(5, 6.2), // al bekend
        p(20, 7.0),
        p(10, 6.5), // gemist terwijl de app stillag
        p(15, 6.8),
        p(20, 7.0), // dubbel in de levering
      ], sessionStart: start);
      expect(fresh.map((e) => e.mmol), [6.5, 6.8, 7.0]);
    });

    test('metingen van vóór de training tellen niet', () {
      final fresh = newSessionPoints(const [], [
        p(-30, 5.0),
        p(0, 6.0),
      ], sessionStart: start);
      expect(fresh.single.mmol, 6.0);
    });

    test('dezelfde meting opnieuw opgehaald → niets nieuws', () {
      expect(
        newSessionPoints([p(0, 6.0)], [p(0, 6.0)], sessionStart: start),
        isEmpty,
      );
    });

    test('aantal op te vragen metingen volgt het gat', () {
      final now = start.add(const Duration(minutes: 60));
      expect(countToFill(start.add(const Duration(minutes: 55)), now), 3);
      expect(countToFill(start, now), 14);
      expect(countToFill(null, now), 12);
      expect(
        countToFill(start.subtract(const Duration(days: 3)), now),
        288,
      );
    });
  });

  group('training herstellen na sluiten van de app', () {
    Future<BuildContext> host(WidgetTester tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      return ctx;
    }

    testWidgets('sambo: blokken, curve, voeding en pauze komen terug', (
      tester,
    ) async {
      final ctx = await host(tester);
      final app = AppController();
      final started = DateTime.now().subtract(const Duration(minutes: 40));
      final original = MatSessionController(
        title: 'Wedstrijdsparren',
        appController: app,
        contextOf: () => ctx,
        planned: [
          TechniqueEntry(name: 'Harai goshi', covered: true, rating: 4),
          TechniqueEntry(name: 'Knieklem'),
        ],
        startedAt: started,
        restoredSeries: [
          GlucosePoint(started, 6.1),
          GlucosePoint(started.add(const Duration(minutes: 20)), 7.3),
        ],
      );
      original.logNutrition('AA drink');
      original.pause();

      // Via JSON, zoals in de echte opslag.
      final json =
          jsonDecode(jsonEncode(original.toSnapshot()))
              as Map<String, dynamic>;
      original.dispose();

      final back = MatSessionController.restore(
        json,
        appController: app,
        contextOf: () => ctx,
      );
      expect(back.title, 'Wedstrijdsparren');
      expect(back.blocks.map((b) => b.name), ['Harai goshi', 'Knieklem']);
      expect(back.blocks.first.covered, isTrue);
      expect(back.blocks.first.rating, 4);
      expect(back.series.map((g) => g.mmol), [6.1, 7.3]);
      expect(back.glucoseMmol, 7.3);
      expect(back.nutrition.single.label, 'AA drink');
      expect(back.isPaused, isTrue);
      // De tijd liep door tijdens het "sluiten": ~40 minuten, niet 0.
      expect(back.elapsed.inMinutes, greaterThanOrEqualTo(39));
      back.dispose();
    });

    testWidgets('kracht: oefeningen met afgevinkte sets komen terug', (
      tester,
    ) async {
      final ctx = await host(tester);
      final app = AppController();
      final original = StrengthSessionController(
        title: 'Posterior chain',
        appController: app,
        contextOf: () => ctx,
        planned: const [
          ExerciseEntry(
            name: 'Deadlift',
            sets: [
              ExerciseSet(kg: 100, reps: 5, done: true),
              ExerciseSet(kg: 110, reps: 3),
            ],
          ),
        ],
      );
      final json =
          jsonDecode(jsonEncode(original.toSnapshot()))
              as Map<String, dynamic>;
      original.dispose();

      final back = StrengthSessionController.restore(
        json,
        appController: app,
        contextOf: () => ctx,
      );
      expect(back.title, 'Posterior chain');
      expect(back.exercises.single.name, 'Deadlift');
      expect(back.exercises.single.sets.map((s) => s.done), [true, false]);
      expect(back.exercises.single.sets.last.kg, 110);
      back.dispose();
    });
  });
}
