import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/combination_sort.dart';
import 'package:kinetic/models/combination.dart';

void main() {
  const combos = [
    Combination(id: '1', name: 'uchi mata → klem', type: ComboType.takedowns),
    Combination(
      id: '2',
      name: 'Armklem vanuit mount',
      favorite: true,
      techniques: ['Mount', 'Armklem'],
    ),
    Combination(id: '3', name: 'Jab-cross', type: ComboType.strikes),
    Combination(
      id: '4',
      name: 'Beenschaar',
      favorite: true,
      type: ComboType.takedowns,
    ),
  ];

  List<String> names(List<Combination> l) => [for (final c in l) c.name];

  test('standaard A–Z, hoofdletterongevoelig', () {
    expect(names(sortAndFilterCombos(combos)), [
      'Armklem vanuit mount',
      'Beenschaar',
      'Jab-cross',
      'uchi mata → klem',
    ]);
  });

  test('Z–A draait de volgorde om', () {
    expect(
      names(sortAndFilterCombos(combos, sort: ComboSort.za)).first,
      'uchi mata → klem',
    );
  });

  test('alleen favorieten', () {
    expect(names(sortAndFilterCombos(combos, onlyFavorites: true)), [
      'Armklem vanuit mount',
      'Beenschaar',
    ]);
  });

  test('type en favoriet combineren', () {
    expect(
      names(
        sortAndFilterCombos(
          combos,
          onlyFavorites: true,
          type: ComboType.takedowns,
        ),
      ),
      ['Beenschaar'],
    );
  });

  test('zoeken vindt ook op techniek binnen de combinatie', () {
    expect(names(sortAndFilterCombos(combos, query: 'MOUNT')), [
      'Armklem vanuit mount',
    ]);
    expect(names(sortAndFilterCombos(combos, query: 'armklem')), [
      'Armklem vanuit mount',
    ]);
  });

  test('favoriet overleeft fromJson/toInsertJson', () {
    final json = {
      ...combos[1].toInsertJson('u1'),
      'id': '2',
    };
    expect(Combination.fromJson(json).favorite, isTrue);
    expect(
      Combination.fromJson({'id': 'x', 'name': 'oud'}).favorite,
      isFalse,
    );
  });
}
