// alarm_decision_test.dart — AppController.alarmDecision() is de enige plek
// die bepaalt of, en hoe, het hypo-alarm mag afgaan. Deze tests dekken de
// vijf regels uit de opdracht, in volgorde.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/state/app_controller.dart';

AppProfile _profile({
  GlucoseSource glucoseSource = GlucoseSource.nightscout,
  AlarmMode alarmMode = AlarmMode.sound,
  double trainingLimit = 5.0,
  double dailyLowBelow = 3.9,
  bool dailyLowEnabled = true,
}) => AppProfile(
  id: 'u1',
  glucoseSource: glucoseSource,
  trainingLimit: trainingLimit,
  onboardingCompleted: true,
  alarmMode: alarmMode,
  dailyLowBelow: dailyLowBelow,
  dailyLowEnabled: dailyLowEnabled,
);

void main() {
  test('vingerprik: nooit een alarm, ook niet met modus sound', () {
    final c = AppController()
      ..profile = _profile(
        glucoseSource: GlucoseSource.finger,
        alarmMode: AlarmMode.sound,
      );
    final decision = c.alarmDecision();
    expect(decision.enabled, isFalse);
    // Ook een duidelijke hypowaarde van 2,5 mag geen alarm opleveren — de
    // enabled-vlag alleen al voorkomt dat, ongeacht lowBelow.
    expect(decision.enabled && 2.5 <= decision.lowBelow, isFalse);
  });

  test('modus off: nooit een alarm', () {
    final c = AppController()..profile = _profile(alarmMode: AlarmMode.off);
    final decision = c.alarmDecision();
    expect(decision.enabled, isFalse);
    expect(decision.withSound, isFalse);
  });

  test('modus silent: wel alarm, zonder geluid', () {
    final c = AppController()..profile = _profile(alarmMode: AlarmMode.silent);
    final decision = c.alarmDecision();
    expect(decision.enabled, isTrue);
    expect(decision.withSound, isFalse);
  });

  test('geen sessie, waarde 4,5, dagelijkse grens 3,9, trainingsgrens 5,0: '
      'geen alarm', () {
    final c = AppController()
      ..profile = _profile(dailyLowBelow: 3.9, trainingLimit: 5.0);
    // Geen sessie actief (c.setSessionActive is nooit aangeroepen).
    final decision = c.alarmDecision();
    expect(decision.isTrainingLimit, isFalse);
    expect(decision.lowBelow, 3.9);
    const value = 4.5;
    expect(decision.enabled && value <= decision.lowBelow, isFalse);
  });

  test(
    'wel een sessie, dezelfde waarde 4,5: wel alarm, met de trainingsgrens',
    () {
      final c = AppController()
        ..profile = _profile(dailyLowBelow: 3.9, trainingLimit: 5.0);
      c.setSessionActive(true);
      final decision = c.alarmDecision();
      expect(decision.isTrainingLimit, isTrue);
      expect(decision.lowBelow, 5.0);
      const value = 4.5;
      expect(decision.enabled && value <= decision.lowBelow, isTrue);
    },
  );

  test('geen sessie en dagelijkse grens uitgeschakeld: geen alarm', () {
    final c = AppController()..profile = _profile(dailyLowEnabled: false);
    final decision = c.alarmDecision();
    expect(decision.enabled, isFalse);
  });

  test(
    'tijdens een sessie is de dagelijkse grens irrelevant — de trainingsgrens '
    'geldt altijd, ook als de dagelijkse grens uit staat',
    () {
      final c = AppController()
        ..profile = _profile(dailyLowEnabled: false, trainingLimit: 5.0);
      c.setSessionActive(true);
      final decision = c.alarmDecision();
      expect(decision.enabled, isTrue);
      expect(decision.isTrainingLimit, isTrue);
      expect(decision.lowBelow, 5.0);
    },
  );

  test('geen profiel geladen: geen alarm', () {
    final c = AppController();
    final decision = c.alarmDecision();
    expect(decision.enabled, isFalse);
  });

  test('alarmDecisionOutsideSession geeft altijd de dagelijkse grens, ongeacht '
      'of er toevallig een sessie loopt', () {
    final c = AppController()
      ..profile = _profile(dailyLowBelow: 3.9, trainingLimit: 5.0);
    c.setSessionActive(true);
    final outside = c.alarmDecisionOutsideSession();
    expect(outside.isTrainingLimit, isFalse);
    expect(outside.lowBelow, 3.9);
  });
}
