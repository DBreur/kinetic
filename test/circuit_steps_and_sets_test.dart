import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/models/exercise.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/state/strength_session_controller.dart';

void main() {
  group('CircuitStep', () {
    test('tijd- en herhalingen-stappen gaan heen en terug via JSON', () {
      const timed = CircuitStep(name: 'Schaduwboksen', seconds: 60);
      const reps = CircuitStep(name: 'Push-up', reps: 10);
      expect(timed.toJson(), {'name': 'Schaduwboksen', 'seconds': 60});
      expect(reps.toJson(), {'name': 'Push-up', 'reps': 10});
      final back = CircuitStep.fromJson(reps.toJson());
      expect(back.isTimed, isFalse);
      expect(back.reps, 10);
      expect(CircuitStep.fromJson(timed.toJson()).seconds, 60);
    });

    test('labels', () {
      expect(const CircuitStep(name: 'a', seconds: 60).targetLabel, '1 min');
      expect(const CircuitStep(name: 'a', seconds: 45).targetLabel, '45 s');
      expect(const CircuitStep(name: 'a', reps: 10).targetLabel, '10×');
    });
  });

  group('Circuit', () {
    test('oude circuits zonder stappen krijgen stappen met de werktijd', () {
      final c = Circuit.fromJson({
        'id': 'x',
        'name': 'Oud',
        'exercise_names': ['Burpee', 'Squat'],
        'rounds': 2,
        'work_seconds': 30,
        'rest_seconds': 10,
      });
      expect(c.effectiveSteps.map((s) => s.targetLabel), ['30 s', '30 s']);
      expect(c.summary, '2 oefeningen · 2 rondes · 30 s per oefening · 10s rust');
    });

    test('schrijft namen en werktijd mee voor Uchivo', () {
      const c = Circuit(
        id: 'x',
        name: 'Training 2',
        rounds: 1,
        restSeconds: 0,
        description: 'Tempo hoog',
        videoUrls: ['https://youtu.be/abc'],
        steps: [
          CircuitStep(name: 'Push-up', reps: 10),
          CircuitStep(name: 'Schaduwboksen', seconds: 60),
        ],
      );
      final json = c.toUpdateJson();
      expect(json['exercise_names'], ['Push-up', 'Schaduwboksen']);
      expect(json['work_seconds'], 60);
      expect(json['description'], 'Tempo hoog');
      expect(json['video_urls'], ['https://youtu.be/abc']);
      final back = Circuit.fromJson({'id': 'x', ...json});
      expect(back.steps.first.reps, 10);
      expect(back.summary, '2 oefeningen · 1 ronde · geen rust');
      expect(back.stepsLabel, '10× Push-up, 1 min Schaduwboksen');
    });
  });

  group('LiveCircuit', () {
    LiveCircuit running(Circuit c) => LiveCircuit(c)
      ..isRunning = true
      ..startWork();

    test('herhalingen-stap wacht op Klaar, tijd-stap telt af', () {
      final lc = running(
        const Circuit(
          id: 'x',
          name: 'c',
          rounds: 1,
          restSeconds: 0,
          steps: [
            CircuitStep(name: 'Push-up', reps: 10),
            CircuitStep(name: 'Plank', seconds: 30),
          ],
        ),
      );
      expect(lc.waitingForTap, isTrue);
      expect(lc.timer.isRunning, isFalse);
      expect(lc.advance(), isFalse);
      expect(lc.currentExerciseName, 'Plank');
      expect(lc.waitingForTap, isFalse);
      expect(lc.timer.isRunning, isTrue);
      expect(lc.advance(), isTrue);
      expect(lc.isDone, isTrue);
    });

    test('rust tussen stappen en door naar de volgende ronde', () {
      final lc = running(
        const Circuit(
          id: 'x',
          name: 'c',
          rounds: 2,
          restSeconds: 15,
          steps: [CircuitStep(name: 'Squat', reps: 12)],
        ),
      );
      lc.advance();
      expect(lc.phase, CircuitPhase.rest);
      expect(lc.waitingForTap, isFalse);
      lc.advance();
      expect(lc.round, 1);
      expect(lc.phase, CircuitPhase.work);
      expect(lc.waitingForTap, isTrue);
      expect(lc.advance(), isTrue);
    });
  });

  group('ExerciseSet', () {
    test('verzuring en gelukt/reden gaan heen en terug via JSON', () {
      const set = ExerciseSet(
        kg: 20,
        reps: 0,
        done: true,
        toBurn: true,
        extraTarget: '5–10',
        extraReps: 7,
        completed: false,
        note: 'Schouder deed pijn',
      );
      final back = ExerciseSet.fromJson(set.toJson());
      expect(back.toBurn, isTrue);
      expect(back.extraTarget, '5–10');
      expect(back.extraReps, 7);
      expect(back.completed, isFalse);
      expect(back.note, 'Schouder deed pijn');
      expect(back.summary, '20 kg · verzuring +7');
    });

    test('oude sets zonder de nieuwe velden', () {
      final s = ExerciseSet.fromJson({'kg': 50, 'reps': 5, 'done': true});
      expect(s.toBurn, isFalse);
      expect(s.completed, isNull);
      expect(s.summary, '50 kg · × 5');
    });
  });

  group('LiveSet', () {
    test('like() neemt de opzet over maar niet de uitkomst', () {
      const planned = ExerciseSet(
        kg: 10,
        reps: 0,
        done: true,
        toBurn: true,
        extraTarget: '5–10',
        extraReps: 6,
        completed: true,
        note: 'top',
      );
      final like = LiveSet.like(planned);
      expect(like.mode, SetMode.burn);
      expect(like.extraTarget, '5–10');
      expect(like.extraReps, isNull);
      expect(like.completed, isNull);
      expect(like.done, isFalse);
      final full = LiveSet.from(planned);
      expect(full.toExerciseSet().note, 'top');
      expect(full.done, isTrue);
    });

    test('een niet-gelukte set met reden wordt ook bewaard', () {
      expect(LiveSet().worthSaving, isFalse);
      expect((LiveSet()..completed = false).worthSaving, isTrue);
      expect((LiveSet()..note = 'te zwaar').worthSaving, isTrue);
      expect((LiveSet()..done = true).worthSaving, isTrue);
    });
  });

  test('Exercise schrijft video_urls mee', () {
    const e = Exercise(id: '', name: 'Squat', videoUrls: ['https://x.y']);
    expect(e.toInsertJson('u')['video_urls'], ['https://x.y']);
  });
}
