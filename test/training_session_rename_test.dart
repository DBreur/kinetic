import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/training_session.dart';

void main() {
  test('copyWith kan de titel van een training aanpassen', () {
    final session = TrainingSession(
      id: 's1',
      kind: SessionKind.kracht,
      title: 'Krachttraining',
      startedAt: DateTime(2026, 1, 1),
      durationMinutes: 45,
      note: 'Voelde goed',
    );

    final renamed = session.copyWith(title: 'Push day');

    expect(renamed.title, 'Push day');
    // Alle andere velden blijven onveranderd.
    expect(renamed.id, session.id);
    expect(renamed.note, session.note);
    expect(renamed.startedAt, session.startedAt);
    expect(renamed.durationMinutes, session.durationMinutes);
  });

  test('copyWith zonder titel laat de bestaande titel staan', () {
    final session = TrainingSession(
      id: 's1',
      kind: SessionKind.sambo,
      title: 'Combat sambo',
      startedAt: DateTime(2026, 1, 1),
      durationMinutes: 60,
    );

    final updated = session.copyWith(note: 'Nieuwe notitie');

    expect(updated.title, 'Combat sambo');
    expect(updated.note, 'Nieuwe notitie');
  });

  test('copyWith kan de duur van een training aanpassen', () {
    final session = TrainingSession(
      id: 's1',
      kind: SessionKind.kracht,
      title: 'Krachttraining',
      startedAt: DateTime(2026, 1, 1),
      durationMinutes: 45,
    );

    final updated = session.copyWith(durationMinutes: 70);

    expect(updated.durationMinutes, 70);
    expect(updated.title, session.title);
  });

  test('copyWith zonder duur laat de bestaande duur staan', () {
    final session = TrainingSession(
      id: 's1',
      kind: SessionKind.kracht,
      title: 'Krachttraining',
      startedAt: DateTime(2026, 1, 1),
      durationMinutes: 45,
    );

    final updated = session.copyWith(title: 'Andere naam');

    expect(updated.durationMinutes, 45);
  });
}
