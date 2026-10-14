// strength_session_controller_test.dart — een afgevinkte set die het
// bestaande record van een oefening verslaat werkt personalRecord bij en
// toont een korte melding (zie StrengthSessionController._checkNewRecord).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

  testWidgets(
    'eerste afgevinkte set met gewicht wordt meteen het record, met melding',
    (tester) async {
      final ctx = await pumpHost(tester);
      final controller = StrengthSessionController(
        title: 'Test',
        appController: AppController(),
        contextOf: () => ctx,
      );
      await controller.pickExercise('Squat');
      expect(controller.exercises.single.personalRecord, isNull);

      controller.updateSet(
        0,
        0,
        (s) => s
          ..kg = 60
          ..done = true,
      );
      await tester.pump();

      expect(controller.exercises.single.personalRecord, 60);
      expect(find.text('Nieuw record: Squat — 60kg!'), findsOneWidget);

      controller.dispose();
    },
  );

  testWidgets('een lichtere afgevinkte set verslaat het record niet', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    final controller = StrengthSessionController(
      title: 'Test',
      appController: AppController(),
      contextOf: () => ctx,
    );
    await controller.pickExercise('Squat');
    controller.updateSet(
      0,
      0,
      (s) => s
        ..kg = 60
        ..done = true,
    );
    await tester.pump();
    controller.addSet(0);
    controller.updateSet(
      0,
      1,
      (s) => s
        ..kg = 40
        ..done = true,
    );
    await tester.pump();

    expect(controller.exercises.single.personalRecord, 60);

    controller.dispose();
  });

  testWidgets('een nog zwaardere afgevinkte set verhoogt het record opnieuw', (
    tester,
  ) async {
    final ctx = await pumpHost(tester);
    final controller = StrengthSessionController(
      title: 'Test',
      appController: AppController(),
      contextOf: () => ctx,
    );
    await controller.pickExercise('Squat');
    controller.updateSet(
      0,
      0,
      (s) => s
        ..kg = 60
        ..done = true,
    );
    await tester.pump();
    // Ruim de eerste melding op zodat de tweede zichtbaar wordt — SnackBars
    // stapelen niet, ze wachten op elkaar.
    ScaffoldMessenger.of(ctx).removeCurrentSnackBar();
    await tester.pump();
    controller.addSet(0);
    controller.updateSet(
      0,
      1,
      (s) => s
        ..kg = 80
        ..done = true,
    );
    await tester.pump();

    expect(controller.exercises.single.personalRecord, 80);
    expect(find.text('Nieuw record: Squat — 80kg!'), findsOneWidget);

    controller.dispose();
  });

  testWidgets(
    'een sessie gestart vanuit een trainingsschema vult oefeningen en sets voor',
    (tester) async {
      final ctx = await pumpHost(tester);
      final controller = StrengthSessionController(
        title: 'Test',
        appController: AppController(),
        contextOf: () => ctx,
        planned: const [
          ExerciseEntry(
            name: 'Deadlift',
            sets: [ExerciseSet(kg: 80, reps: 5), ExerciseSet(kg: 80, reps: 5)],
          ),
          ExerciseEntry(
            name: 'Bankdrukken',
            sets: [ExerciseSet(kg: 60, reps: 8)],
          ),
        ],
      );
      await tester.pump();

      expect(controller.exercises, hasLength(2));
      expect(controller.exercises[0].name, 'Deadlift');
      expect(controller.exercises[0].sets, hasLength(2));
      expect(controller.exercises[0].sets[0].kg, 80);
      expect(controller.exercises[0].sets[0].reps, 5);
      expect(controller.exercises[0].sets[0].done, isFalse);
      expect(controller.exercises[1].name, 'Bankdrukken');
      expect(controller.exercises[1].sets.single.kg, 60);

      controller.dispose();
    },
  );

  testWidgets(
    'elapsed loopt door op basis van de kloktijd (geen Stopwatch die kan '
    'pauzeren als het scherm uit gaat) en pause/resume werkt nog correct',
    (tester) async {
      final ctx = await pumpHost(tester);
      final controller = StrengthSessionController(
        title: 'Test',
        appController: AppController(),
        contextOf: () => ctx,
      );

      // Timer.periodic/Future.delayed lopen in testWidgets in een
      // fake-tijd-zone — runAsync breekt daaruit zodat echte wall-clock
      // vertragingen (nodig om elapsed te testen) daadwerkelijk verstrijken.
      await tester.runAsync(() async {
        await Future.delayed(const Duration(milliseconds: 300));
        expect(controller.elapsed.inMilliseconds, greaterThanOrEqualTo(250));

        controller.pause();
        final atPause = controller.elapsed;
        await Future.delayed(const Duration(milliseconds: 300));
        // Gepauzeerd: elapsed staat stil, loopt niet door.
        expect(
          controller.elapsed.inMilliseconds,
          closeTo(atPause.inMilliseconds, 30),
        );

        controller.resume();
        await Future.delayed(const Duration(milliseconds: 300));
        expect(controller.elapsed, greaterThan(atPause));
      });

      controller.dispose();
    },
  );

  testWidgets(
    'tijd-gebaseerde set wordt automatisch afgevinkt zodra de klok afloopt',
    (tester) async {
      final ctx = await pumpHost(tester);
      late StrengthSessionController controller;

      // De controller's eigen 1s-ticker (_tick, een Timer.periodic) moet een
      // echte timer zijn om in deze test daadwerkelijk te kunnen afgaan —
      // daarom wordt de controller zelf ook binnen runAsync aangemaakt.
      await tester.runAsync(() async {
        controller = StrengthSessionController(
          title: 'Test',
          appController: AppController(),
          contextOf: () => ctx,
        );
        await controller.pickExercise('Plank');
        controller.updateSet(0, 0, (s) => s..seconds = 1);
        expect(controller.exercises.single.sets.single.done, isFalse);

        controller.startSetTimer(0, 0);
        // Ruim genoeg wachten voor minstens twee ticks van de 1s-ticker.
        await Future.delayed(const Duration(milliseconds: 2200));
      });

      expect(controller.exercises.single.sets.single.done, isTrue);

      controller.dispose();
    },
  );

  testWidgets(
    'circuit schakelt automatisch door werk/rust/oefeningen/rondes tot '
    'isDone',
    (tester) async {
      final ctx = await pumpHost(tester);
      late StrengthSessionController controller;

      await tester.runAsync(() async {
        controller = StrengthSessionController(
          title: 'Test',
          appController: AppController(),
          contextOf: () => ctx,
          plannedCircuits: const [
            Circuit(
              id: 'c1',
              name: 'Test-circuit',
              exerciseNames: ['A', 'B'],
              rounds: 2,
              workSeconds: 1,
              restSeconds: 1,
            ),
          ],
        );

        controller.startCircuit(0);
        expect(controller.circuits.single.phase, CircuitPhase.work);
        expect(controller.circuits.single.currentExerciseName, 'A');
        expect(controller.circuits.single.isRunning, isTrue);

        // Poll tot het circuit klaar is (2 rondes × 2 oefeningen × werk+rust
        // ≈ 7s), met een ruime marge voor tick-jitter.
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!controller.circuits.single.isDone &&
            DateTime.now().isBefore(deadline)) {
          await Future.delayed(const Duration(milliseconds: 200));
        }
      });

      expect(controller.circuits.single.isDone, isTrue);
      expect(controller.circuits.single.isRunning, isFalse);
      expect(controller.circuits.single.round, 1); // laatste ronde (0-based)

      controller.dispose();
    },
  );
}
