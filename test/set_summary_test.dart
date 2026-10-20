// set_summary_test.dart — een set wordt beschreven zoals hij gedaan is:
// verzuring en tijd, niet "× reps" (ook al staat er een reps-getal in).

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/training_session.dart';

void main() {
  test('verzuring: geen reps in de omschrijving', () {
    const s = ExerciseSet(kg: 12.5, reps: 20, toBurn: true);
    expect(s.summary, '12,5 kg · verzuring');
  });

  test('tijd: seconden in plaats van reps', () {
    const s = ExerciseSet(kg: 0, reps: 8, seconds: 20);
    expect(s.summary, '20s');
  });

  test('gewone set: kg × reps', () {
    const s = ExerciseSet(kg: 17.5, reps: 8);
    expect(s.summary, '17,5 kg · × 8');
  });
}
