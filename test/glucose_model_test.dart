// glucose_model_test.dart — trendmapping en "oude data"-herkenning
// (isStale), los van alles wat een BuildContext of platformkanaal nodig
// heeft.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/glucose.dart';

void main() {
  group('trendFromDelta', () {
    test('duidelijk stijgend', () {
      expect(trendFromDelta(0.5), Trend.up);
    });
    test('licht stijgend', () {
      expect(trendFromDelta(0.15), Trend.slightUp);
    });
    test('stabiel', () {
      expect(trendFromDelta(0.05), Trend.flat);
      expect(trendFromDelta(-0.05), Trend.flat);
    });
    test('licht dalend', () {
      expect(trendFromDelta(-0.15), Trend.slightDown);
    });
    test('duidelijk dalend', () {
      expect(trendFromDelta(-0.3), Trend.down);
    });
    test('snel dalend', () {
      expect(trendFromDelta(-0.8), Trend.fastDown);
    });
  });

  group('GlucoseReading.isStale', () {
    test('een meting van 5 minuten oud is niet oud', () {
      final r = GlucoseReading(
        6.0,
        Trend.flat,
        DateTime.now().subtract(const Duration(minutes: 5)),
      );
      expect(r.isStale, isFalse);
    });

    test('een meting van 16 minuten oud is oud', () {
      final r = GlucoseReading(
        6.0,
        Trend.flat,
        DateTime.now().subtract(const Duration(minutes: 16)),
      );
      expect(r.isStale, isTrue);
    });
  });

  group('GlucoseSnapshot.isStale', () {
    test('geen meting: niet oud (er is gewoon niets om oud te noemen)', () {
      const snapshot = GlucoseSnapshot(reading: null, history: []);
      expect(snapshot.isStale, isFalse);
    });

    test('volgt de meting eronder', () {
      final fresh = GlucoseSnapshot(
        reading: GlucoseReading(6.0, Trend.flat, DateTime.now()),
        history: const [],
      );
      final stale = GlucoseSnapshot(
        reading: GlucoseReading(
          6.0,
          Trend.flat,
          DateTime.now().subtract(const Duration(minutes: 20)),
        ),
        history: const [],
      );
      expect(fresh.isStale, isFalse);
      expect(stale.isStale, isTrue);
    });
  });
}
