// circuit_blocks_prep_pause_test.dart — blokken binnen een circuit (elk met
// eigen rondes), voorbereiden vóór elke oefening, pauzeren, en het aparte
// alarm tijdens trainingen.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/interval_timer.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/strength_session_controller.dart';

/// Blok A (squat + press) 2 rondes, dan blok B (row) 1 ronde. Geen rust,
/// zodat elke advance() precies één stap verder gaat.
const _circuit = Circuit(
  id: 'c',
  name: 'Training 1',
  restSeconds: 0,
  steps: [
    CircuitStep(name: 'Squat', reps: 15, block: 1, blockRounds: 2),
    CircuitStep(name: 'Press', reps: 15, block: 1, blockRounds: 2),
    CircuitStep(name: 'Row', reps: 12, block: 2, blockRounds: 1),
  ],
);

void main() {
  test('segments: elk blok met eigen rondes', () {
    final segs = _circuit.segments;
    expect(segs.length, 2);
    expect((segs[0].start, segs[0].end, segs[0].rounds), (0, 2, 2));
    expect((segs[1].start, segs[1].end, segs[1].rounds), (2, 3, 1));
    expect(_circuit.summary, contains('2 blokken'));
  });

  test('zonder blokken: één deel met de rondes van het circuit', () {
    const plain = Circuit(
      id: 'p',
      name: 'P',
      rounds: 3,
      steps: [
        CircuitStep(name: 'A', seconds: 30),
        CircuitStep(name: 'B', seconds: 30),
      ],
    );
    expect(plain.segments.single.rounds, 3);
    expect(plain.hasBlocks, isFalse);
  });

  test('blok en rondes overleven JSON en bewerken', () {
    final step = CircuitStep.fromJson(_circuit.steps.first.toJson());
    expect(step.block, 1);
    expect(step.blockRounds, 2);
    expect(step.copyWith(name: 'X').block, 1);
    expect(step.copyWith(clearBlock: true).block, isNull);
  });

  test('volgorde: blok A twee rondes, dan blok B', () {
    final lc = LiveCircuit(_circuit)..start();
    final order = <String>[lc.currentExerciseName];
    while (!lc.advance()) {
      order.add(lc.currentExerciseName);
    }
    expect(order, ['Squat', 'Press', 'Squat', 'Press', 'Row']);
    expect(lc.isDone, isTrue);
  });

  test('voorbereiden vóór elke oefening', () {
    final lc = LiveCircuit(_circuit)
      ..prepSeconds = 10
      ..start();
    expect(lc.phase, CircuitPhase.prep);
    expect(lc.timer.isRunning, isTrue);
    lc.advance();
    expect(lc.phase, CircuitPhase.work);
    expect(lc.currentExerciseName, 'Squat');
    lc.advance();
    expect(lc.phase, CircuitPhase.prep);
    expect(lc.currentExerciseName, 'Press');
  });

  test('pauzeren houdt de resterende tijd vast', () {
    final lc = LiveCircuit(_circuit)
      ..prepSeconds = 30
      ..start();
    lc.pause();
    expect(lc.isPaused, isTrue);
    expect(lc.timer.isPaused, isTrue);
    expect(lc.timeLeft.inSeconds, greaterThan(25));
    lc.resume();
    expect(lc.isPaused, isFalse);
    expect(lc.timer.isRunning, isTrue);
  });

  test('alarm tijdens training: eigen stand, anders die van dagelijks', () {
    final c = AppController()
      ..profile = AppProfile(
        id: 'u1',
        glucoseSource: GlucoseSource.nightscout,
        trainingLimit: 5.0,
        onboardingCompleted: true,
        alarmMode: AlarmMode.sound,
        trainingAlarmMode: AlarmMode.silent,
      );
    expect(c.alarmDecisionOutsideSession().withSound, isTrue);
    c.setSessionActive(true);
    expect(c.alarmDecision().enabled, isTrue);
    expect(c.alarmDecision().withSound, isFalse);

    c.profile = c.profile!.copyWith(trainingAlarmMode: AlarmMode.off);
    expect(c.alarmDecision().enabled, isFalse);
    expect(c.alarmDecisionOutsideSession().enabled, isTrue);

    c.profile = c.profile!.copyWith(clearTrainingAlarmMode: true);
    expect(c.alarmDecision().withSound, isTrue);
  });

  test('nieuwe instellingen heen en terug', () {
    final p = AppProfile.fromJson(const {
      'id': 'x',
      'spotify_button': 'strength',
      'training_alarm_mode': 'off',
      'circuit_prep_seconds': 20,
    });
    expect(p.spotifyButton, SpotifyButtonPlacement.strength);
    expect(p.spotifyButton.onMat, isFalse);
    expect(p.trainingAlarmMode, AlarmMode.off);
    expect(p.circuitPrepSeconds, 20);
    final back = AppProfile.fromJson({...p.toJson(), 'id': 'x'});
    expect(back.spotifyButton, SpotifyButtonPlacement.strength);
    expect(back.trainingAlarmMode, AlarmMode.off);

    final defaults = AppProfile.fromJson(const {'id': 'x'});
    expect(defaults.spotifyButton, SpotifyButtonPlacement.both);
    expect(defaults.trainingAlarmMode, isNull);
    expect(defaults.circuitPrepSeconds, 10);
  });

  test('rondes over het hele circuit: blokken zijn dan alleen groepering', () {
    final whole = _circuit.copyWith(roundsPerBlock: false, rounds: 2);
    expect(whole.segments.single.rounds, 2);
    final lc = LiveCircuit(whole)..start();
    final order = <String>[lc.currentExerciseName];
    while (!lc.advance()) {
      order.add(lc.currentExerciseName);
    }
    expect(order, ['Squat', 'Press', 'Row', 'Squat', 'Press', 'Row']);
    expect(
      Circuit.fromJson({...whole.toJson(), 'id': 'c'}).roundsPerBlock,
      isFalse,
    );
  });

  test('IntervalTimer: pauze bevriest de resterende tijd', () {
    final t = IntervalTimer()..start(const Duration(seconds: 30));
    t.pause();
    expect(t.isPaused, isTrue);
    expect(t.isRunning, isTrue, reason: 'gepauzeerd telt niet als afgelopen');
    final frozen = t.remaining;
    expect(t.remaining, frozen);
    t.resume();
    expect(t.isPaused, isFalse);
    expect(t.remaining.inSeconds, greaterThan(25));
  });

  testWidgets('sessiepauze zet rust, tijd-set en circuit stil', (tester) async {
    final c = StrengthSessionController(
      title: 'T',
      appController: AppController(),
      contextOf: () => throw UnimplementedError(),
      planned: const [
        ExerciseEntry(
          name: 'Plank',
          sets: [
            ExerciseSet(kg: 0, reps: 0, seconds: 40),
            ExerciseSet(kg: 0, reps: 0, seconds: 40),
          ],
        ),
      ],
      plannedCircuits: const [_circuit],
    );
    c.startSetTimer(0, 0);
    expect(
      c.activeTimedSet?.preparing,
      isFalse,
      reason: 'zonder profiel geen voorbereiding',
    );
    c.startCircuit(0);
    c.pause();
    expect(c.circuits.single.isPaused, isTrue);
    final left = c.activeTimedSet!.left;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 1200)),
    );
    expect(c.activeTimedSet!.left, left, reason: 'klok staat stil');
    c.resume();
    expect(c.circuits.single.isPaused, isFalse);
    c.stopSetTimer();
    expect(c.activeTimedSet, isNull);
    c.dispose();
  });

  testWidgets('tijd-set na afloop uitvinken blijft uitgevinkt', (tester) async {
    late StrengthSessionController c;
    await tester.runAsync(() async {
      c = StrengthSessionController(
        title: 'T',
        appController: AppController(),
        contextOf: () => throw UnimplementedError(),
        planned: const [
          ExerciseEntry(
            name: 'Plank',
            sets: [ExerciseSet(kg: 0, reps: 0, seconds: 1)],
          ),
        ],
      );
      c.startSetTimer(0, 0);
      await Future<void>.delayed(const Duration(milliseconds: 2500));
      expect(c.exercises[0].sets[0].done, isTrue, reason: 'klok vinkte af');

      c.updateSet(0, 0, (s) => s..done = false);
      await Future<void>.delayed(const Duration(milliseconds: 1500));
    });
    expect(c.exercises[0].sets[0].done, isFalse);
    expect(c.activeTimedSet, isNull);
    c.dispose();
  });
}
