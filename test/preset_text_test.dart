import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/preset_text.dart';
import 'package:kinetic/models/food_preset.dart';

void main() {
  const appel = FoodPreset(singular: 'Appel', plural: 'Appels', carbs: 16, unitAmount: 135, unitLabel: 'g');
  const banaan = FoodPreset(singular: 'Banaan', plural: 'Bananen', carbs: 23);

  PresetChange tap(String text, Map<String, int> counts, FoodPreset p, int d) =>
      applyPresetChange(text: text, counts: counts, preset: p, delta: d);

  test('plus voegt "1 Appel" toe en telt koolhydraten', () {
    final r = tap('', {}, appel, 1);
    expect(r.text, '1 Appel');
    expect(r.counts, {'Appel': 1});
    expect(r.carbsDelta, 16);
  });

  test('tweede plus wordt meervoud', () {
    final r = tap('1 Appel', {'Appel': 1}, appel, 1);
    expect(r.text, '2 Appels');
    expect(r.carbsDelta, 16);
  });

  test('meerdere presets met komma ertussen', () {
    final r = tap('2 Appels', {'Appel': 2}, banaan, 1);
    expect(r.text, '2 Appels, 1 Banaan');
  });

  test('eigen woord blijft vooraan staan', () {
    final r = tap('Yoghurt', {}, appel, 1);
    expect(r.text, 'Yoghurt, 1 Appel');
  });

  test('min naar nul haalt de preset uit de tekst', () {
    var r = tap('Yoghurt, 1 Appel, 1 Banaan', {'Appel': 1, 'Banaan': 1}, appel, -1);
    expect(r.text, 'Yoghurt, 1 Banaan');
    expect(r.counts, {'Banaan': 1});
    expect(r.carbsDelta, -16);
    r = tap(r.text, r.counts, banaan, -1);
    expect(r.text, 'Yoghurt');
  });

  test('min op nul doet niets', () {
    final r = tap('Yoghurt', {}, appel, -1);
    expect(r.text, 'Yoghurt');
    expect(r.carbsDelta, 0);
  });

  test('hoeveelheid schaalt mee', () {
    expect(appel.amountLabel(2), '270 g');
  });

  test('veelgebruikte presets: minstens 2x, meest gebruikt eerst', () {
    final usage = presetUsage([
      {'Appel': 1},
      {'Appel': 2, 'Banaan': 1},
      {'Banaan': 1},
      {'Appel': 1},
    ]);
    expect(frequentPresets([banaan, appel], usage).map((p) => p.singular), ['Appel', 'Banaan']);
  });
}
