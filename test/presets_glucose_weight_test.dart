import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/competition_plan.dart';
import 'package:kinetic/core/food_preset_usage.dart';
import 'package:kinetic/core/glucose_prefill.dart';
import 'package:kinetic/models/agenda.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/food_log_entry.dart';
import 'package:kinetic/models/food_preset.dart';
import 'package:kinetic/models/glucose.dart';

void main() {
  final now = DateTime(2026, 10, 14, 12);

  const presets = [
    FoodPreset(singular: 'Appel', plural: 'Appels', carbs: 16),
    FoodPreset(singular: 'Volkoren boterham', plural: 'Volkoren boterhammen', carbs: 15),
    FoodPreset(singular: 'Banaan', plural: 'Bananen', carbs: 27),
    FoodPreset(singular: 'Melk', plural: 'Melk', carbs: 12),
    FoodPreset(singular: '7up', plural: '7up', carbs: 10),
  ];

  FoodLogEntry entry(int daysAgo, Map<String, int> counts) => FoodLogEntry(
    id: '$daysAgo$counts',
    at: now.subtract(Duration(days: daysAgo)),
    description: '',
    presetCounts: counts,
  );

  group('presetgebruik', () {
    test('telt eetmomenten binnen het venster, niet stuks', () {
      final usage = presetUsage([
        entry(1, {'Appel': 3}),
        entry(2, {'Appel': 1, 'Banaan': 1}),
        entry(200, {'Melk': 1}), // buiten 90 dagen
      ], now: now);
      expect(usage, {'Appel': 2, 'Banaan': 1});
    });

    test('vaak gebruikt: meest gebruikt eerst, ongebruikt niet', () {
      final top = frequentPresets(presets, {'Banaan': 1, 'Appel': 4});
      expect([for (final p in top) p.singular], ['Appel', 'Banaan']);
    });
  });

  group('zoeken', () {
    test('begint-met eerst, dan woordbegin, dan bevat', () {
      final hits = searchPresets(presets, 'bo');
      // "boterham" begint een woord in "Volkoren boterham".
      expect(hits.first.singular, 'Volkoren boterham');
      expect(searchPresets(presets, 'an').map((p) => p.singular), ['Banaan']);
    });

    test('vindt ook op meervoud, hoofdletterongevoelig', () {
      expect(searchPresets(presets, 'BANANEN').single.singular, 'Banaan');
    });

    test('bij gelijke rang wint vaker gebruikt', () {
      const two = [
        FoodPreset(singular: 'Rijst', plural: 'Rijst', carbs: 30),
        FoodPreset(singular: 'Rijstwafel', plural: 'Rijstwafels', carbs: 7),
      ];
      expect(
        searchPresets(two, 'rijst', usage: {'Rijstwafel': 5}).first.singular,
        'Rijstwafel',
      );
    });
  });

  test('groeperen per letter, cijfers achteraan onder #', () {
    final groups = groupByLetter(presets);
    expect([for (final (l, _) in groups) l], ['A', 'B', 'M', 'V', '#']);
    expect(groups.last.$2.single.singular, '7up');
  });

  group('glucose voorvullen', () {
    GlucoseReading at(int minutesAgo) =>
        GlucoseReading(6.4, Trend.flat, now.subtract(Duration(minutes: minutesAgo)));

    test('sensor: tot 15 minuten oud', () {
      expect(isPrefillableReading(at(10), true, now: now), isTrue);
      expect(isPrefillableReading(at(16), true, now: now), isFalse);
    });

    test('vingerprik: tot 30 minuten oud', () {
      expect(isPrefillableReading(at(25), false, now: now), isTrue);
      expect(isPrefillableReading(at(31), false, now: now), isFalse);
    });
  });

  group('gewicht richting wedstrijd', () {
    Competition c({
      WeightLimit limit = WeightLimit.under,
      double? limitKg = 79,
      double? target,
    }) => Competition(
      id: 'c',
      name: 'NK',
      startsAt: now.add(const Duration(days: 20)),
      weightLimit: limit,
      weightLimitKg: limitKg,
      targetWeightKg: target,
    );

    test('onder de grens: nog afvallen richting doel', () {
      final s = weightStatus(c(target: 78.5), 80.2)!;
      expect(s.limitLabel, 'Onder 79,0 kg');
      expect(s.goalKg, 78.5);
      expect(s.toGoKg, closeTo(1.7, 1e-9));
      expect(s.withinLimit, isFalse);
    });

    test('zonder doel telt de grens zelf', () {
      final s = weightStatus(c(), 78)!;
      expect(s.goalKg, 79);
      expect(s.toGoKg, closeTo(-1, 1e-9));
      expect(s.withinLimit, isTrue);
    });

    test('boven de grens: nog aankomen', () {
      final s = weightStatus(c(limit: WeightLimit.over, limitKg: 90), 88)!;
      expect(s.limitLabel, 'Boven 90,0 kg');
      expect(s.toGoKg, closeTo(2, 1e-9));
      expect(s.withinLimit, isFalse);
    });

    test('alleen een doel, of helemaal niets', () {
      final s = weightStatus(c(limit: WeightLimit.none, target: 75), null)!;
      expect(s.limitLabel, 'Doel 75,0 kg');
      expect(s.toGoKg, isNull);
      expect(weightStatus(c(limit: WeightLimit.none, limitKg: null), 80), isNull);
    });

    test('gewichtsvelden overleven toJson/fromJson', () {
      final back = Competition.fromJson({
        ...c(target: 78.5).toJson(),
        'id': 'c',
      });
      expect(back.weightLimit, WeightLimit.under);
      expect(back.weightLimitKg, 79);
      expect(back.targetWeightKg, 78.5);
    });
  });

  test('profiel: lichaamsgegevens opslaan en weer wissen', () {
    final p = AppProfile.defaults('u').copyWith(
      weightKg: 80.4,
      heightCm: 182,
      sex: 'male',
    );
    final back = AppProfile.fromJson(p.toJson());
    expect(back.weightKg, 80.4);
    expect(back.heightCm, 182);
    expect(back.sex, 'male');
    final cleared = back.copyWith(clearWeight: true, clearHeight: true);
    expect(cleared.weightKg, isNull);
    expect(cleared.heightCm, isNull);
    expect(cleared.sex, 'male');
  });
}
