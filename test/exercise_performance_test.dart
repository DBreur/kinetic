import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/training_session.dart';

void main() {
  group('ExercisePerformance.heaviest', () {
    test('geeft het zwaarste gewicht terug, ongeacht het aantal reps', () {
      final performance = ExercisePerformance(
        date: DateTime(2026, 1, 1),
        sets: const [
          ExerciseSet(kg: 60, reps: 10),
          ExerciseSet(kg: 80, reps: 3),
          ExerciseSet(kg: 70, reps: 6),
        ],
      );

      expect(performance.heaviest, 80);
    });

    test('geeft 0 terug als er geen sets zijn', () {
      final performance = ExercisePerformance(
        date: DateTime(2026, 1, 1),
        sets: const [],
      );
      expect(performance.heaviest, 0);
    });
  });

  group('persoonlijk record over meerdere sessies', () {
    test('is het maximum van heaviest over alle sessies', () {
      final history = [
        ExercisePerformance(
          date: DateTime(2026, 1, 1),
          sets: const [ExerciseSet(kg: 60, reps: 8)],
        ),
        ExercisePerformance(
          date: DateTime(2026, 1, 8),
          sets: const [ExerciseSet(kg: 85, reps: 2)],
        ),
        ExercisePerformance(
          date: DateTime(2026, 1, 15),
          sets: const [ExerciseSet(kg: 70, reps: 5)],
        ),
      ];

      final pr = history.map((p) => p.heaviest).reduce((a, b) => a > b ? a : b);
      expect(pr, 85);
    });

    test('is null als de geschiedenis leeg is', () {
      final history = <ExercisePerformance>[];
      final pr = history.isEmpty
          ? null
          : history.map((p) => p.heaviest).reduce((a, b) => a > b ? a : b);
      expect(pr, isNull);
    });
  });
}
