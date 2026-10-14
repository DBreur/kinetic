import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/food_preset.dart';

void main() {
  test('sortedPresets sorteert case-insensitief op naam', () {
    const presets = [
      FoodPreset(singular: 'Pizza (groot)', plural: 'Pizza (groot)'),
      FoodPreset(singular: 'appel', plural: 'appels'),
      FoodPreset(singular: 'boterham', plural: 'boterhammen'),
      FoodPreset(singular: 'Ei', plural: 'Eieren'),
    ];

    final sorted = sortedPresets(presets).map((p) => p.singular).toList();

    expect(sorted, ['appel', 'boterham', 'Ei', 'Pizza (groot)']);
  });

  test('sortedPresets laat de oorspronkelijke lijst ongemoeid', () {
    const presets = [
      FoodPreset(singular: 'boterham', plural: 'boterhammen'),
      FoodPreset(singular: 'appel', plural: 'appels'),
    ];

    sortedPresets(presets);

    expect(presets.first.singular, 'boterham');
  });
}
