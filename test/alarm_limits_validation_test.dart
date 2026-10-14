import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/app_profile.dart';

void main() {
  test('trainingsgrens gelijk aan dagelijkse grens is geldig', () {
    expect(isValidAlarmLimits(trainingLimit: 5.0, dailyLowBelow: 5.0), isTrue);
  });

  test('trainingsgrens boven de dagelijkse grens is geldig', () {
    expect(isValidAlarmLimits(trainingLimit: 5.0, dailyLowBelow: 3.9), isTrue);
  });

  test('trainingsgrens onder de dagelijkse grens is ongeldig', () {
    expect(isValidAlarmLimits(trainingLimit: 3.5, dailyLowBelow: 3.9), isFalse);
  });
}
