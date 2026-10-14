import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/exercise.dart';

void main() {
  test('fromJson/toInsertJson round-trip', () {
    final exercise = Exercise(
      id: 'e1',
      name: 'Deadlift',
      description: 'Rug recht, heupen naar achteren.',
    );

    final inserted = exercise.toInsertJson('user-1');
    expect(inserted['user_id'], 'user-1');
    expect(inserted['name'], 'Deadlift');
    expect(inserted['description'], 'Rug recht, heupen naar achteren.');

    // Simuleer wat er terugkomt uit Supabase (inclusief de gegenereerde id).
    final row = {'id': 'e1', ...inserted};
    final restored = Exercise.fromJson(row);

    expect(restored.id, 'e1');
    expect(restored.name, 'Deadlift');
    expect(restored.description, 'Rug recht, heupen naar achteren.');
  });

  test('description is optioneel en valt terug op een lege string', () {
    final exercise = Exercise.fromJson({'id': 'e2', 'name': 'Squat'});
    expect(exercise.description, '');
  });

  test('copyWith past alleen de opgegeven velden aan', () {
    const exercise = Exercise(id: 'e3', name: 'Bankdrukken');
    final updated = exercise.copyWith(description: 'Schouderbladen samen.');

    expect(updated.id, 'e3');
    expect(updated.name, 'Bankdrukken');
    expect(updated.description, 'Schouderbladen samen.');
  });
}
