import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/workout_template.dart';

void main() {
  test('fromJson/toInsertJson round-trip met oefeningen en sets', () {
    final template = WorkoutTemplate(
      id: 't1',
      name: 'Dag 1',
      exercises: const [
        ExerciseEntry(
          name: 'Deadlift',
          sets: [ExerciseSet(kg: 80, reps: 5), ExerciseSet(kg: 80, reps: 5)],
        ),
      ],
    );

    final inserted = template.toInsertJson('user-1');
    expect(inserted['user_id'], 'user-1');
    expect(inserted['name'], 'Dag 1');

    final row = {'id': 't1', ...inserted};
    final restored = WorkoutTemplate.fromJson(row);

    expect(restored.id, 't1');
    expect(restored.name, 'Dag 1');
    expect(restored.exercises.single.name, 'Deadlift');
    expect(restored.exercises.single.sets, hasLength(2));
    expect(restored.exercises.single.sets.first.kg, 80);
    expect(restored.exercises.single.sets.first.reps, 5);
  });

  test('exercises is optioneel en valt terug op een lege lijst', () {
    final template = WorkoutTemplate.fromJson({'id': 't2', 'name': 'Leeg'});
    expect(template.exercises, isEmpty);
  });

  test('copyWith past alleen de opgegeven velden aan', () {
    const template = WorkoutTemplate(id: 't3', name: 'Push');
    final updated = template.copyWith(
      exercises: const [
        ExerciseEntry(
          name: 'Bankdrukken',
          sets: [ExerciseSet(kg: 60, reps: 8)],
        ),
      ],
    );

    expect(updated.id, 't3');
    expect(updated.name, 'Push');
    expect(updated.exercises.single.name, 'Bankdrukken');
  });
}
