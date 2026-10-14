import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/circuit.dart';

void main() {
  test('fromJson/toInsertJson round-trip met oefeningen en timing', () {
    const circuit = Circuit(
      id: 'c1',
      name: 'Explosieve onderlichaam',
      exerciseNames: ['Sprawls', 'Sit-outs', 'Lunge jumps'],
      rounds: 3,
      workSeconds: 40,
      restSeconds: 20,
    );

    final inserted = circuit.toInsertJson('user-1');
    expect(inserted['user_id'], 'user-1');
    expect(inserted['name'], 'Explosieve onderlichaam');

    final row = {'id': 'c1', ...inserted};
    final restored = Circuit.fromJson(row);

    expect(restored.id, 'c1');
    expect(restored.name, 'Explosieve onderlichaam');
    expect(restored.exerciseNames, ['Sprawls', 'Sit-outs', 'Lunge jumps']);
    expect(restored.rounds, 3);
    expect(restored.workSeconds, 40);
    expect(restored.restSeconds, 20);
  });

  test('ontbrekende velden vallen terug op standaardwaarden', () {
    final circuit = Circuit.fromJson({'id': 'c2', 'name': 'Leeg'});
    expect(circuit.exerciseNames, isEmpty);
    expect(circuit.rounds, 3);
    expect(circuit.workSeconds, 40);
    expect(circuit.restSeconds, 20);
  });

  test('toJson/fromJson round-trip (embedding in een WorkoutTemplate)', () {
    const circuit = Circuit(
      id: 'c3',
      name: 'Warming-up mobiliteit',
      exerciseNames: ['Heupcirkels', 'Shrimping'],
      rounds: 1,
      workSeconds: 30,
      restSeconds: 10,
    );

    final restored = Circuit.fromJson(circuit.toJson());

    expect(restored.id, 'c3');
    expect(restored.name, 'Warming-up mobiliteit');
    expect(restored.exerciseNames, ['Heupcirkels', 'Shrimping']);
    expect(restored.rounds, 1);
  });

  test('copyWith past alleen de opgegeven velden aan', () {
    const circuit = Circuit(id: 'c4', name: 'Core');
    final updated = circuit.copyWith(rounds: 5, workSeconds: 60);

    expect(updated.id, 'c4');
    expect(updated.name, 'Core');
    expect(updated.rounds, 5);
    expect(updated.workSeconds, 60);
    expect(updated.restSeconds, circuit.restSeconds);
  });
}
