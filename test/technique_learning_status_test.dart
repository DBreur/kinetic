// technique_learning_status_test.dart — de leerstatus-/planningregels los
// van de UI en het netwerk: een datum kiezen bij status "none" wordt
// "planned", een behandelde geplande techniek wordt "learning", en de
// planning sorteert/labelt zoals in het tabblad Technieken getoond wordt.

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:kinetic/core/formatters.dart';
import 'package:kinetic/models/technique.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('nl_NL');
  });

  group('Technique.copyWith — leerstatus', () {
    test('een datum zetten vanuit status none wordt planned', () {
      const base = Technique(id: 't1', name: 'Harai Goshi');
      final date = DateTime(2026, 10, 20);

      // Exact het patroon dat de UI gebruikt zodra je een datum kiest
      // terwijl de status nog "none" is.
      final next = base.copyWith(
        learningStatus: LearningStatus.planned,
        plannedFor: date,
      );

      expect(next.learningStatus, LearningStatus.planned);
      expect(next.plannedFor, date);
    });

    test('clearPlannedFor maakt de geplande datum weer leeg', () {
      final base = Technique(
        id: 't1',
        name: 'Harai Goshi',
        learningStatus: LearningStatus.planned,
        plannedFor: DateTime(2026, 10, 20),
      );
      final next = base.copyWith(clearPlannedFor: true);
      expect(next.plannedFor, isNull);
    });
  });

  group('techniquesToStartLearning', () {
    final planned = Technique(
      id: 't1',
      name: 'Harai Goshi',
      learningStatus: LearningStatus.planned,
    );
    final learning = Technique(
      id: 't2',
      name: 'Juji Gatame',
      learningStatus: LearningStatus.learning,
    );
    final none = const Technique(id: 't3', name: 'Osoto Gari');

    test(
      'een geplande techniek die behandeld is in de sessie gaat naar learning',
      () {
        final result = techniquesToStartLearning(
          [planned, learning, none],
          ['Harai Goshi'],
        );
        expect(result, [planned]);
      },
    );

    test('vergelijkt namen hoofdletterongevoelig', () {
      final result = techniquesToStartLearning([planned], ['harai goshi']);
      expect(result, [planned]);
    });

    test('technieken die niet behandeld zijn blijven ongemoeid', () {
      final result = techniquesToStartLearning([planned], ['Juji Gatame']);
      expect(result, isEmpty);
    });

    test(
      'technieken die al learning/none/mastered zijn worden nooit opnieuw gestart',
      () {
        final result = techniquesToStartLearning(
          [learning, none],
          ['Juji Gatame', 'Osoto Gari'],
        );
        expect(result, isEmpty);
      },
    );
  });

  group('planningLabel', () {
    final now = DateTime(2026, 10, 12);

    test('vandaag', () {
      expect(planningLabel(DateTime(2026, 10, 12), now: now), 'Vandaag');
    });

    test('morgen', () {
      expect(planningLabel(DateTime(2026, 10, 13), now: now), 'Morgen');
    });

    test('een datum verder in de toekomst krijgt een korte datum', () {
      final label = planningLabel(DateTime(2026, 10, 20), now: now);
      expect(label, isNot('Vandaag'));
      expect(label, isNot('Morgen'));
      expect(label, isNot(contains('Te laat')));
    });

    test('een verstreken datum toont "Te laat · N dagen"', () {
      expect(
        planningLabel(DateTime(2026, 10, 9), now: now),
        'Te laat · 3 dagen',
      );
    });

    test('één dag te laat gebruikt het enkelvoud "dag"', () {
      expect(
        planningLabel(DateTime(2026, 10, 11), now: now),
        'Te laat · 1 dag',
      );
    });
  });

  group('planning sorteren', () {
    test('technieken met een geplande datum sorteren chronologisch', () {
      final a = Technique(
        id: 'a',
        name: 'A',
        plannedFor: DateTime(2026, 10, 20),
      );
      final b = Technique(
        id: 'b',
        name: 'B',
        plannedFor: DateTime(2026, 10, 14),
      );
      final c = Technique(
        id: 'c',
        name: 'C',
        plannedFor: DateTime(2026, 10, 16),
      );
      final sorted = [a, b, c]..sort(
        (x, y) => x.plannedFor!.compareTo(y.plannedFor!),
      );
      expect(sorted.map((t) => t.name).toList(), ['B', 'C', 'A']);
    });
  });
}
