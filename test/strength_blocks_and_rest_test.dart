// strength_blocks_and_rest_test.dart — blokken (supersets) en rust bij
// krachttraining: rust pas na een hele ronde van het blok, eigen rust per
// oefening/blok, sets verwijderen tijdens de training, en dat blok en rust
// het opslaan en herstellen overleven.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/rest_blocks.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/strength_session_controller.dart';

void main() {
  Future<BuildContext> pumpHost(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pump();
    return ctx;
  }

  List<ExerciseSet> threeSets() =>
      List.generate(3, (_) => const ExerciseSet(kg: 10, reps: 15));

  StrengthSessionController coachDayOne(BuildContext ctx) =>
      StrengthSessionController(
        title: 'Training 1',
        appController: AppController(),
        contextOf: () => ctx,
        planned: [
          ExerciseEntry(
            name: 'Goblet squat',
            sets: threeSets(),
            block: 1,
            restSeconds: 120,
          ),
          ExerciseEntry(
            name: 'Shoulder press',
            sets: threeSets(),
            block: 1,
            restSeconds: 120,
          ),
          ExerciseEntry(name: 'Push-ups', sets: threeSets()),
        ],
      );

  group('pure blok-logica', () {
    test('blockRange en normalizeBlocks', () {
      final blocks = [1, 1, null, 2, 2, 2, 3];
      expect(blockRange(blocks, 1), (start: 0, end: 2));
      expect(blockRange(blocks, 2), (start: 2, end: 3));
      expect(blockRange(blocks, 4), (start: 3, end: 6));
      // Een blok van één is geen blok.
      expect(normalizeBlocks(blocks), [1, 1, null, 2, 2, 2, null]);
    });

    test('formatRest', () {
      expect(formatRest(45), '45 s');
      expect(formatRest(90), '1:30 min');
      expect(formatRest(120), '2 min');
    });
  });

  testWidgets('rust pas als set n van álle oefeningen in het blok af is', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    final c = coachDayOne(ctx);

    c.updateSet(0, 0, (s) => s..done = true);
    expect(c.restLeft, 0, reason: 'blok nog niet rond');

    c.updateSet(1, 0, (s) => s..done = true);
    expect(c.restLeft, greaterThan(100));
    expect(c.restTotal, 120);
    expect(c.restNext, 'Ronde 2 · Goblet squat');

    c.dispose();
  });

  testWidgets('losse oefening: rust na elke set, standaard uit profiel', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    final c = coachDayOne(ctx);

    c.updateSet(2, 0, (s) => s..done = true);
    expect(c.restTotal, defaultRestFallback);
    expect(c.restNext, 'Set 2 · Push-ups');

    c.setRest(2, 45);
    c.updateSet(2, 1, (s) => s..done = true);
    expect(c.restTotal, 45);

    c.dispose();
  });

  testWidgets('koppelen, losmaken en rust van het hele blok', (tester) async {
    final ctx = await pumpHost(tester);
    final c = coachDayOne(ctx);

    c.linkWithPrevious(2);
    expect(c.blockOf(2), (start: 0, end: 3));
    expect(c.restAfter(2), 120, reason: 'neemt de rust van het blok over');

    c.setRest(0, 60);
    expect([for (final e in c.exercises) e.restSeconds], [60, 60, 60]);

    c.unlink(1);
    // Midden uit het blok: erboven en eronder blijven elk één oefening over,
    // dus geen blok meer.
    expect([for (final e in c.exercises) e.block], [null, null, null]);

    c.dispose();
  });

  testWidgets('set verwijderen tijdens de training', (tester) async {
    final ctx = await pumpHost(tester);
    final c = coachDayOne(ctx);

    c.removeSet(0, 1);
    expect(c.exercises[0].sets.length, 2);
    c.removeSet(0, 5); // buiten bereik: niets
    expect(c.exercises[0].sets.length, 2);

    c.dispose();
  });

  testWidgets('blok en rust overleven snapshot en herstel', (tester) async {
    final ctx = await pumpHost(tester);
    final c = coachDayOne(ctx);
    final snapshot = c.toSnapshot();
    c.dispose();

    final restored = StrengthSessionController.restore(
      snapshot,
      appController: AppController(),
      contextOf: () => ctx,
    );
    expect([for (final e in restored.exercises) e.block], [1, 1, null]);
    expect(restored.restAfter(0), 120);
    restored.dispose();

    final entry = ExerciseEntry.fromJson(
      ExerciseEntry(
        name: 'X',
        sets: const [],
        block: 2,
        restSeconds: 90,
      ).toJson(),
    );
    expect(entry.block, 2);
    expect(entry.restSeconds, 90);
    // Zonder blok/rust: geen extra sleutels in de JSON.
    expect(
      const ExerciseEntry(name: 'Y', sets: []).toJson().keys,
      ['name', 'sets'],
    );
  });
}
