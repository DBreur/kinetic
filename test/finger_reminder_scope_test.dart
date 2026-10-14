import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/app_profile.dart';

void main() {
  group('FingerReminderScope.matches', () {
    test('fingerOnly matcht alleen vingerprik', () {
      expect(
        FingerReminderScope.fingerOnly.matches(GlucoseSource.finger),
        isTrue,
      );
      expect(
        FingerReminderScope.fingerOnly.matches(GlucoseSource.nightscout),
        isFalse,
      );
    });

    test('sensorOnly matcht elke niet-vingerprik-bron', () {
      expect(
        FingerReminderScope.sensorOnly.matches(GlucoseSource.nightscout),
        isTrue,
      );
      expect(
        FingerReminderScope.sensorOnly.matches(GlucoseSource.dexcomShare),
        isTrue,
      );
      expect(
        FingerReminderScope.sensorOnly.matches(GlucoseSource.finger),
        isFalse,
      );
    });

    test('both matcht altijd', () {
      expect(
        FingerReminderScope.both.matches(GlucoseSource.nightscout),
        isTrue,
      );
      expect(FingerReminderScope.both.matches(GlucoseSource.finger), isTrue);
    });
  });

  group('FingerReminderScope.fromName', () {
    test('herkent bekende namen', () {
      expect(
        FingerReminderScope.fromName('sensorOnly'),
        FingerReminderScope.sensorOnly,
      );
      expect(FingerReminderScope.fromName('both'), FingerReminderScope.both);
    });

    test('valt terug op fingerOnly voor onbekende/lege waarde', () {
      expect(
        FingerReminderScope.fromName(null),
        FingerReminderScope.fingerOnly,
      );
      expect(
        FingerReminderScope.fromName('iets_onbekends'),
        FingerReminderScope.fingerOnly,
      );
    });
  });
}
