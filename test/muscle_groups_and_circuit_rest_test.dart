import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/exercise_library.dart';
import 'package:kinetic/models/exercise.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/state/strength_session_controller.dart';
import 'package:kinetic/widgets/muscle_figure.dart';

void main() {
  group('Oefeningenlijst', () {
    const custom = [
      Exercise(id: '1', name: 'zercher squat', muscleGroups: ['Quadriceps']),
      Exercise(id: '2', name: 'Plank', muscleGroups: ['Buik', 'Schouders']),
      Exercise(id: '3', name: 'Deadlift', muscleGroups: ['Onderrug']),
      Exercise(id: '4', name: 'Bulgarian split squat', muscleGroups: [
        'Quadriceps',
        'Billen',
      ]),
    ];

    test('alleen eigen oefeningen (geen vaste lijst meer), A–Z', () {
      expect(kExerciseLibrary, isEmpty);
      final names = allExercises(custom).map((e) => e.name).toList();
      expect(names, [
        'Bulgarian split squat',
        'Deadlift',
        'Plank',
        'zercher squat',
      ]);
    });

    test('filteren op spiergroepen (een van) en Z–A', () {
      final result = filterExercises(
        allExercises(custom),
        groups: {'Quadriceps', 'Onderrug'},
        ascending: false,
      );
      expect(result.map((e) => e.name), [
        'zercher squat',
        'Deadlift',
        'Bulgarian split squat',
      ]);
      expect(
        filterExercises(allExercises(custom), query: 'SQUAT').map((e) => e.name),
        ['Bulgarian split squat', 'zercher squat'],
      );
    });

    test('spiergroepen gaan mee in JSON', () {
      const e = Exercise(id: 'x', name: 'Curl', muscleGroups: ['Biceps']);
      expect(e.toInsertJson('u')['muscle_groups'], ['Biceps']);
      final back = Exercise.fromJson({
        'id': 'x',
        'name': 'Curl',
        'muscle_groups': ['Biceps'],
      });
      expect(back.muscleGroups, ['Biceps']);
      expect(Exercise.fromJson({'id': 'y', 'name': 'Oud'}).muscleGroups, []);
    });

    testWidgets('spierfiguurtje tekent als man en als vrouw', (tester) async {
      for (final female in [false, true]) {
        MuscleFigure.female.value = female;
        await tester.pumpWidget(
          const MaterialApp(
            home: Center(child: MuscleFigure(groups: ['Borst', 'Lats'])),
          ),
        );
        expect(tester.takeException(), isNull);
      }
      MuscleFigure.female.value = false;
    });
  });

  group('Circuitstappen', () {
    test('verzuring met reps erna en eigen rust via JSON', () {
      const step = CircuitStep(
        name: 'Push-up',
        toBurn: true,
        extraTarget: '5–10',
        restSeconds: 0,
      );
      expect(step.toJson(), {
        'name': 'Push-up',
        'to_burn': true,
        'extra_target': '5–10',
        'rest': 0,
      });
      final back = CircuitStep.fromJson(step.toJson());
      expect(back.kind, StepKind.burn);
      expect(back.isTimed, isFalse);
      expect(back.restSeconds, 0);
      expect(back.targetLabel, 'verzuring +5–10');
      expect(
        const CircuitStep(name: 'x', toBurn: true).targetLabel,
        'verzuring',
      );
    });

    test('rust per stap, anders de standaard', () {
      const c = Circuit(
        id: 'c',
        name: 'c',
        restSeconds: 20,
        steps: [
          CircuitStep(name: 'a', reps: 10, restSeconds: 0),
          CircuitStep(name: 'b', seconds: 60),
        ],
      );
      expect(c.restAfter(0), 0);
      expect(c.restAfter(1), 20);
      expect(c.summary, contains('rust per oefening'));
    });

    test('live: geen rust na een stap met rust 0, wel na de rest', () {
      final lc =
          LiveCircuit(
              const Circuit(
                id: 'c',
                name: 'c',
                rounds: 2,
                restSeconds: 15,
                steps: [
                  CircuitStep(name: 'Push-up', toBurn: true, restSeconds: 0),
                  CircuitStep(name: 'Squat', reps: 10),
                ],
              ),
            )
            ..isRunning = true
            ..startWork();
      expect(lc.waitingForTap, isTrue);
      lc.advance();
      expect(lc.phase, CircuitPhase.work);
      expect(lc.currentExerciseName, 'Squat');
      lc.advance();
      expect(lc.phase, CircuitPhase.rest);
      expect(lc.restTotal, 15);
    });
  });
}
