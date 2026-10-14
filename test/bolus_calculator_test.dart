import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/bolus_calculator.dart';
import 'package:kinetic/models/bolus_period.dart';

void main() {
  final periods = [
    const BolusPeriod(label: 'Ochtend', startTime: '00:00', carbRatio: 10),
    const BolusPeriod(label: 'Middag', startTime: '11:00', carbRatio: 8),
    const BolusPeriod(label: 'Avond', startTime: '16:00', carbRatio: 12),
  ];

  group('activePeriod', () {
    test('kiest het tijdvak waarvan de starttijd het dichtst ervoor ligt', () {
      expect(
        activePeriod(periods, DateTime(2026, 1, 1, 9, 30))!.label,
        'Ochtend',
      );
      expect(
        activePeriod(periods, DateTime(2026, 1, 1, 11, 0))!.label,
        'Middag',
      );
      expect(
        activePeriod(periods, DateTime(2026, 1, 1, 20, 0))!.label,
        'Avond',
      );
    });

    test(
      'laat het laatste tijdvak doorlopen tot het vroegste tijdvak de dag '
      'erna begint (geen gat vóór 00:00)',
      () {
        final nightOnly = [
          const BolusPeriod(label: 'Ochtend', startTime: '06:00', carbRatio: 10),
          const BolusPeriod(label: 'Avond', startTime: '18:00', carbRatio: 12),
        ];
        expect(
          activePeriod(nightOnly, DateTime(2026, 1, 1, 2, 0))!.label,
          'Avond',
        );
      },
    );

    test('geeft null bij een lege tijdvakkenlijst', () {
      expect(activePeriod(const [], DateTime(2026, 1, 1, 9, 0)), isNull);
    });
  });

  group('isNight', () {
    test('herkent een nachtvenster dat middernacht overschrijdt', () {
      expect(isNight(DateTime(2026, 1, 1, 20, 0), '19:00', '05:00'), isTrue);
      expect(isNight(DateTime(2026, 1, 1, 2, 0), '19:00', '05:00'), isTrue);
      expect(isNight(DateTime(2026, 1, 1, 12, 0), '19:00', '05:00'), isFalse);
      expect(isNight(DateTime(2026, 1, 1, 5, 0), '19:00', '05:00'), isFalse);
    });

    test('werkt ook voor een venster binnen dezelfde dag', () {
      expect(isNight(DateTime(2026, 1, 1, 13, 0), '12:00', '14:00'), isTrue);
      expect(isNight(DateTime(2026, 1, 1, 15, 0), '12:00', '14:00'), isFalse);
    });
  });

  group('calculateBolus', () {
    test('berekent voedingsdosis uit koolhydraten en de ratio van het tijdvak', () {
      final result = calculateBolus(
        periods: periods,
        carbs: 80,
        currentMmol: null,
        correctionFactor: 2,
        correctionTargetDay: 8,
        correctionTargetNight: 10,
        nightStart: '19:00',
        nightEnd: '05:00',
        at: DateTime(2026, 1, 1, 9, 0), // Ochtend, ratio 10
      );
      expect(result.foodDose, 8);
      expect(result.correctionDose, isNull);
      expect(result.total, 8);
      expect(result.period!.label, 'Ochtend');
    });

    test('correctiedosis is 0 op of onder de streefwaarde, nooit negatief', () {
      final atTarget = calculateBolus(
        periods: periods,
        carbs: null,
        currentMmol: 8,
        correctionFactor: 2,
        correctionTargetDay: 8,
        correctionTargetNight: 10,
        nightStart: '19:00',
        nightEnd: '05:00',
        at: DateTime(2026, 1, 1, 9, 0),
      );
      expect(atTarget.correctionDose, 0);

      final belowTarget = calculateBolus(
        periods: periods,
        carbs: null,
        currentMmol: 4,
        correctionFactor: 2,
        correctionTargetDay: 8,
        correctionTargetNight: 10,
        nightStart: '19:00',
        nightEnd: '05:00',
        at: DateTime(2026, 1, 1, 9, 0),
      );
      expect(belowTarget.correctionDose, 0);
    });

    test('gebruikt de nacht-streefwaarde binnen het nachtvenster', () {
      final result = calculateBolus(
        periods: periods,
        carbs: null,
        currentMmol: 14,
        correctionFactor: 2,
        correctionTargetDay: 8,
        correctionTargetNight: 10,
        nightStart: '19:00',
        nightEnd: '05:00',
        at: DateTime(2026, 1, 1, 22, 0), // nacht, streef 10
      );
      // (14 - 10) / 2 = 2
      expect(result.correctionDose, 2);
    });

    test('telt voeding en correctie op tot het totaal', () {
      final result = calculateBolus(
        periods: periods,
        carbs: 80,
        currentMmol: 14,
        correctionFactor: 2,
        correctionTargetDay: 8,
        correctionTargetNight: 10,
        nightStart: '19:00',
        nightEnd: '05:00',
        at: DateTime(2026, 1, 1, 9, 0), // dag, ratio 10, streef 8
      );
      // voeding 80/10 = 8, correctie (14-8)/2 = 3, totaal 11
      expect(result.foodDose, 8);
      expect(result.correctionDose, 3);
      expect(result.total, 11);
    });

    test(
      'geen deling door nul: lege tijdvakken of een ratio/factor van 0 '
      'geeft null/0 i.p.v. een fout',
      () {
        final noPeriods = calculateBolus(
          periods: const [],
          carbs: 50,
          currentMmol: null,
          correctionFactor: 2,
          correctionTargetDay: 8,
          correctionTargetNight: 10,
          nightStart: '19:00',
          nightEnd: '05:00',
          at: DateTime(2026, 1, 1, 9, 0),
        );
        expect(noPeriods.foodDose, isNull);
        expect(noPeriods.total, isNull);

        final zeroFactor = calculateBolus(
          periods: periods,
          carbs: null,
          currentMmol: 14,
          correctionFactor: 0,
          correctionTargetDay: 8,
          correctionTargetNight: 10,
          nightStart: '19:00',
          nightEnd: '05:00',
          at: DateTime(2026, 1, 1, 9, 0),
        );
        expect(zeroFactor.correctionDose, isNull);
      },
    );
  });
}
