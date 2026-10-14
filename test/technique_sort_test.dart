// technique_sort_test.dart — sorteerregels voor de technieklijst, los van de
// UI getest. Favorieten moeten altijd bovenaan blijven, ongeacht welke
// sortering gekozen is; daarbinnen moet elke sorteeroptie het juiste veld in
// de juiste richting gebruiken.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/technique_sort.dart';
import 'package:kinetic/models/technique.dart';

class _Item implements TechniqueSortable {
  const _Item({
    required this.name,
    this.favorite = false,
    this.createdAt,
    this.lastDate,
    this.learningStatus = LearningStatus.none,
  });

  @override
  final String name;
  @override
  final bool favorite;
  @override
  final DateTime? createdAt;
  @override
  final DateTime? lastDate;
  @override
  final LearningStatus learningStatus;
}

void main() {
  group('sortTechniques — naam', () {
    test('Naam (A-Z) sorteert alfabetisch, hoofdletterongevoelig', () {
      final items = [
        const _Item(name: 'banaan'),
        const _Item(name: 'Appel'),
        const _Item(name: 'citroen'),
      ];
      sortTechniques(items, TechniqueSort.nameAsc);
      expect(items.map((i) => i.name).toList(), ['Appel', 'banaan', 'citroen']);
    });

    test('Naam (Z-A) is het omgekeerde', () {
      final items = [
        const _Item(name: 'banaan'),
        const _Item(name: 'Appel'),
        const _Item(name: 'citroen'),
      ];
      sortTechniques(items, TechniqueSort.nameDesc);
      expect(items.map((i) => i.name).toList(), ['citroen', 'banaan', 'Appel']);
    });
  });

  group('sortTechniques — favorieten', () {
    test('favorieten staan altijd bovenaan, ongeacht de gekozen sortering', () {
      final items = [
        const _Item(name: 'Z-techniek', favorite: false),
        const _Item(name: 'A-techniek', favorite: true),
      ];
      sortTechniques(items, TechniqueSort.nameAsc);
      // Zonder de favorieten-regel zou 'A-techniek' toch al eerst komen —
      // test met een sortering die dat NIET vanzelf zou doen.
      sortTechniques(items, TechniqueSort.nameDesc);
      expect(items.first.name, 'A-techniek');
    });
  });

  group('sortTechniques — datum toegevoegd', () {
    test('nieuwste eerst', () {
      final items = [
        _Item(name: 'oud', createdAt: DateTime(2026, 1, 1)),
        _Item(name: 'nieuw', createdAt: DateTime(2026, 6, 1)),
      ];
      sortTechniques(items, TechniqueSort.dateAddedNewest);
      expect(items.map((i) => i.name).toList(), ['nieuw', 'oud']);
    });

    test('oudste eerst', () {
      final items = [
        _Item(name: 'oud', createdAt: DateTime(2026, 1, 1)),
        _Item(name: 'nieuw', createdAt: DateTime(2026, 6, 1)),
      ];
      sortTechniques(items, TechniqueSort.dateAddedOldest);
      expect(items.map((i) => i.name).toList(), ['oud', 'nieuw']);
    });
  });

  group('sortTechniques — laatst beoefend', () {
    test('nieuwste eerst, technieken zonder datum komen laatst', () {
      final items = [
        _Item(name: 'nooit', lastDate: null),
        _Item(name: 'lang geleden', lastDate: DateTime(2026, 1, 1)),
        _Item(name: 'recent', lastDate: DateTime(2026, 9, 1)),
      ];
      sortTechniques(items, TechniqueSort.lastPracticedNewest);
      expect(items.map((i) => i.name).toList(), [
        'recent',
        'lang geleden',
        'nooit',
      ]);
    });
  });

  group('sortTechniques — leerstatus', () {
    test('bezig > gepland > geen > beheerst, en alfabetisch binnen elke status', () {
      final items = [
        const _Item(name: 'B-beheerst', learningStatus: LearningStatus.mastered),
        const _Item(name: 'A-bezig', learningStatus: LearningStatus.learning),
        const _Item(name: 'C-geen', learningStatus: LearningStatus.none),
        const _Item(name: 'D-gepland', learningStatus: LearningStatus.planned),
        const _Item(name: 'A-geen', learningStatus: LearningStatus.none),
      ];
      sortTechniques(items, TechniqueSort.learningStatus);
      expect(items.map((i) => i.name).toList(), [
        'A-bezig',
        'D-gepland',
        'A-geen',
        'C-geen',
        'B-beheerst',
      ]);
    });
  });
}
