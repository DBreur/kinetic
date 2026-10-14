import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/training_streak.dart';

void main() {
  final now = DateTime(2026, 6, 15, 20, 0); // maandag

  group('TrainingStreak.compute — consecutiveDays', () {
    test('drie opeenvolgende dagen tot en met vandaag', () {
      final streak = TrainingStreak.compute([
        now,
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 2)),
      ], now: now);
      expect(streak.consecutiveDays, 3);
      expect(streak.label, '3 dagen op rij getraind');
    });

    test('streak telt door als je gisteren trainde maar vandaag nog niet', () {
      final streak = TrainingStreak.compute([
        now.subtract(const Duration(days: 1)),
        now.subtract(const Duration(days: 2)),
      ], now: now);
      expect(streak.consecutiveDays, 2);
    });

    test('een gat van een dag stopt de streak', () {
      final streak = TrainingStreak.compute([
        now,
        now.subtract(const Duration(days: 2)), // gisteren ontbreekt
      ], now: now);
      expect(streak.consecutiveDays, 1);
    });

    test('meerdere sessies op dezelfde dag tellen als één dag', () {
      final streak = TrainingStreak.compute([
        now,
        now.subtract(const Duration(hours: 2)),
      ], now: now);
      expect(streak.consecutiveDays, 1);
    });

    test('geen sessies geeft streak 0 en geen label', () {
      final streak = TrainingStreak.compute(const [], now: now);
      expect(streak.consecutiveDays, 0);
      expect(streak.daysInLastWeek, 0);
      expect(streak.label, isNull);
    });
  });

  group('TrainingStreak.compute — daysInLastWeek', () {
    test('telt losse dagen binnen de laatste 7 dagen (inclusief vandaag)', () {
      final streak = TrainingStreak.compute([
        now,
        now.subtract(const Duration(days: 3)),
        now.subtract(const Duration(days: 6)),
        now.subtract(const Duration(days: 10)), // buiten het venster
      ], now: now);
      expect(streak.daysInLastWeek, 3);
    });
  });

  group('TrainingStreak.label', () {
    test('valt terug op het weekoverzicht als er geen streak van 2+ is', () {
      final streak = TrainingStreak.compute([
        now.subtract(const Duration(days: 3)),
      ], now: now);
      expect(streak.consecutiveDays, 0);
      expect(streak.label, '1 van de 7 dagen deze week getraind');
    });
  });
}
