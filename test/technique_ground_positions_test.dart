// technique_ground_positions_test.dart — groundPositions is een optioneel,
// vrij veld (leeg is een geldige, bewuste waarde) dat meerdere posities mag
// bevatten — eenzelfde afwerking lukt vaak vanuit meer dan één positie. De
// regel "alleen bewaren als naar == Submission" zit in de UI
// (technique_edit_screen.dart); dit test alleen het model zelf.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/positions.dart';
import 'package:kinetic/models/technique.dart';

void main() {
  test('groundPositions is standaard leeg', () {
    const t = Technique(id: 't1', name: 'Test');
    expect(t.groundPositions, isEmpty);
  });

  test('fromJson/toInsertJson rondje met meerdere gekozen posities', () {
    const t = Technique(
      id: 't1',
      name: 'Kimura',
      transition: 'Grond boven -> Submission',
      groundPositions: ['Half guard', 'Mount'],
    );
    final json = t.toInsertJson('u1');
    expect(json['ground_positions'], ['Half guard', 'Mount']);

    final restored = Technique.fromJson({...json, 'id': 't1'});
    expect(restored.groundPositions, ['Half guard', 'Mount']);
  });

  test('fromJson valt terug op een lege lijst als het veld ontbreekt', () {
    final t = Technique.fromJson({'id': 't1', 'name': 'Test'});
    expect(t.groundPositions, isEmpty);
  });

  test('copyWith past alleen groundPositions aan, de rest blijft gelijk', () {
    const t = Technique(id: 't1', name: 'Kimura');
    final next = t.copyWith(groundPositions: ['Mount']);
    expect(next.groundPositions, ['Mount']);
    expect(next.name, 'Kimura');
  });

  test('kGroundPositions bevat de door de gebruiker genoemde voorbeelden', () {
    expect(kGroundPositions, contains('Mount'));
    expect(kGroundPositions, contains('Half guard'));
    expect(kGroundPositions, contains('Guard'));
    expect(kGroundPositions, contains('North-South'));
  });
}
