// positions_focus_calculator_test.dart — per positie vastleggen bij een
// techniek, focus (eerstvolgende / aantal / tot datum) en wat er na een
// training mee gebeurt, "+ set" die alles overneemt, en het
// koolhydraten-rekenmachientje.

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/technique.dart';
import 'package:kinetic/models/training_session.dart';
import 'package:kinetic/state/app_controller.dart';
import 'package:kinetic/state/strength_session_controller.dart';
import 'package:kinetic/widgets/carb_calculator.dart';

void main() {
  group('positie per techniek', () {
    test('SessionBlock met aantal en posities: heen en terug', () {
      const block = SessionBlock(
        name: 'Armklem',
        reps: 8,
        positions: [
          PositionPractice(
            position: 'Mount',
            rating: 4,
            reps: 5,
            wentWell: 'snel',
            toImprove: 'heup laag',
          ),
          PositionPractice(position: 'Turtle', rating: 2),
        ],
      );
      final back = SessionBlock.fromJson(block.toJson());
      expect(back.reps, 8);
      expect(back.positions.length, 2);
      expect(back.positions.first.toImprove, 'heup laag');
      expect(back.positions.first.summary, contains('Mount · ★★★★ · 5×'));
      expect(back.positions.first.summary, contains('beter: heup laag'));
    });

    test('update van een techniek met posities: heen en terug', () {
      final u = TechniqueUpdate(
        at: DateTime.utc(2026, 10, 28),
        rating: 3,
        positions: const [
          PositionPractice(position: 'Turtle', rating: 2, toImprove: 'grip'),
        ],
      );
      final back = TechniqueUpdate.fromJson(u.toJson());
      expect(back.positions.single.position, 'Turtle');
      expect(back.positions.single.toImprove, 'grip');
      final old = TechniqueUpdate.fromJson(const {
        'at': '2026-01-01T00:00:00Z',
        'rating': 4,
      });
      expect(old.positions, isEmpty);
    });

    test('oude blokken zonder aantal of posities blijven werken', () {
      final old = SessionBlock.fromJson(const {'name': 'Heupworp'});
      expect(old.reps, 0);
      expect(old.positions, isEmpty);
      expect(old.toJson().containsKey('positions'), isFalse);
    });
  });

  group('focus', () {
    final now = DateTime(2026, 10, 28, 12);
    Technique t(FocusMode mode, {int? left, DateTime? until}) => Technique(
      id: 'x',
      name: 'Armklem',
      focusMode: mode,
      focusTrainingsLeft: left,
      focusUntil: until,
    );

    test('actief per soort', () {
      expect(t(FocusMode.none).isFocusActive(now), isFalse);
      expect(t(FocusMode.next).isFocusActive(now), isTrue);
      expect(t(FocusMode.count, left: 2).isFocusActive(now), isTrue);
      expect(t(FocusMode.count, left: 0).isFocusActive(now), isFalse);
      expect(
        t(FocusMode.until, until: DateTime(2026, 10, 28)).isFocusActive(now),
        isTrue,
        reason: 't/m vandaag',
      );
      expect(
        t(FocusMode.until, until: DateTime(2026, 10, 27)).isFocusActive(now),
        isFalse,
      );
    });

    test('na een training: eerstvolgende klaar, aantal één minder', () {
      expect(t(FocusMode.next).focusAfterTraining().mode, FocusMode.none);
      final three = t(FocusMode.count, left: 3).focusAfterTraining();
      expect((three.mode, three.left), (FocusMode.count, 2));
      final last = t(FocusMode.count, left: 1).focusAfterTraining();
      expect(last.mode, FocusMode.none);
      final until = t(
        FocusMode.until,
        until: DateTime(2026, 11, 7),
      ).focusAfterTraining();
      expect(until.mode, FocusMode.until, reason: 'loopt vanzelf af');
    });

    test('oude rijen: practice_next wordt "eerstvolgende"', () {
      final legacy = Technique.fromJson(const {
        'id': 'a',
        'name': 'Klem',
        'practice_next': true,
      });
      expect(legacy.focusMode, FocusMode.next);
      final fresh = Technique.fromJson(const {
        'id': 'b',
        'name': 'Worp',
        'focus_mode': 'count',
        'focus_trainings_left': 3,
      });
      expect(fresh.focusLabel, 'Nog 3 trainingen');
    });
  });

  testWidgets('"+ set" neemt ook het aantal na verzuring over', (tester) async {
    final c = StrengthSessionController(
      title: 'T',
      appController: AppController(),
      contextOf: () => throw UnimplementedError(),
      planned: const [
        ExerciseEntry(
          name: 'Goblet squat',
          sets: [
            ExerciseSet(
              kg: 12.5,
              reps: 20,
              toBurn: true,
              extraTarget: '5–10',
              extraReps: 7,
            ),
          ],
        ),
      ],
    );
    c.addSet(0);
    final added = c.exercises[0].sets[1];
    expect(added.kg, 12.5);
    expect(added.toBurn, isTrue);
    expect(added.extraTarget, '5–10');
    expect(added.extraReps, 7);
    expect(added.done, isFalse);
    c.dispose();
  });

  group('rekenmachientje', () {
    test('optellen en aftrekken, met komma', () {
      expect(evaluateCarbSum('45 + 12 − 8'), 49);
      expect(evaluateCarbSum('12,5 + 7,5'), 20);
      expect(evaluateCarbSum(''), 0);
    });

    test('nooit negatief, ongeldig = null', () {
      expect(evaluateCarbSum('10 − 30'), 0);
      expect(evaluateCarbSum('10 + + 3'), isNull);
      expect(evaluateCarbSum('abc'), isNull);
    });
  });
}
