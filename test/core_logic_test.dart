import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/formatters.dart';
import 'package:kinetic/core/glucose_rules.dart';
import 'package:kinetic/core/iob.dart';
import 'package:kinetic/core/meal_impact.dart';
import 'package:kinetic/core/sparring_timer.dart';
import 'package:kinetic/core/weight_plan.dart';
import 'package:kinetic/models/glucose.dart';
import 'package:kinetic/models/technique.dart';

void main() {
  final now = DateTime(2026, 11, 24, 18, 0);

  group('matClearance', () {
    GlucoseReading r(double mmol, [Trend t = Trend.flat, int minAgo = 2]) =>
        GlucoseReading(mmol, t, now.subtract(Duration(minutes: minAgo)));

    test('hypo blokkeert de volgende ronde', () {
      final c = matClearance(reading: r(3.6), roundLabel: 'R4', now: now);
      expect(c.level, ClearanceLevel.danger);
      expect(c.blocksNextRound, isTrue);
    });

    test('hypo blokkeert ook bij een oude meting', () {
      final c = matClearance(reading: r(3.2, Trend.flat, 30), roundLabel: 'R4', now: now);
      expect(c.level, ClearanceLevel.danger);
    });

    test('stabiel in doelbereik is veilig', () {
      final c = matClearance(reading: r(6.7, Trend.slightUp), roundLabel: 'R4', now: now);
      expect(c.level, ClearanceLevel.safe);
      expect(c.title, 'Veilig voor R4');
    });

    test('onder de eigen trainingsgrens geeft een waarschuwing', () {
      final c = matClearance(reading: r(5.5), roundLabel: 'R2', trainingLimit: 6.0, now: now);
      expect(c.level, ClearanceLevel.caution);
    });

    test('dalende trend onder 7 geeft een waarschuwing', () {
      final c = matClearance(reading: r(6.2, Trend.down), roundLabel: 'R2', now: now);
      expect(c.level, ClearanceLevel.caution);
      expect(c.title, 'Dalende trend');
    });

    test('hoog: ketonen checken', () {
      final c = matClearance(reading: r(14.5), roundLabel: 'R2', now: now);
      expect(c.title, contains('ketonen'));
    });

    test('oude of ontbrekende meting is onbekend, niet veilig', () {
      expect(matClearance(reading: null, roundLabel: 'R2', now: now).level, ClearanceLevel.unknown);
      expect(matClearance(reading: r(6.0, Trend.flat, 20), roundLabel: 'R2', now: now).level, ClearanceLevel.unknown);
    });

    test('time in range', () {
      expect(timeInRange([5.0, 6.0, 10.0, 3.5]), 0.5);
      expect(timeInRange([]), isNull);
    });
  });

  group('IOB (oref0-curve)', () {
    test('vol bij t=0, leeg na 5 uur, monotoon dalend', () {
      expect(iobFraction(Duration.zero), 1);
      expect(iobFraction(const Duration(hours: 5)), 0);
      var last = 1.0;
      for (var m = 10; m < 300; m += 10) {
        final f = iobFraction(Duration(minutes: m));
        expect(f, lessThanOrEqualTo(last));
        last = f;
      }
    });

    test('na 2 uur is grofweg de helft nog actief', () {
      final f = iobFraction(const Duration(hours: 2));
      expect(f, inInclusiveRange(0.4, 0.65));
    });

    test('telt doses op en negeert oude', () {
      final iob = insulinOnBoard([
        InsulinDose(now, 4),
        InsulinDose(now.subtract(const Duration(hours: 6)), 10),
      ], now: now);
      expect(iob, closeTo(4, 1e-9));
    });
  });

  group('maaltijd-impact', () {
    test('spec-voorbeeld: 30g vóór sparring ≈ +1.2 tot +1.8', () {
      final r = predictGlucoseImpact(carbs: 30, context: MealContext.preTraining);
      expect(r.low, closeTo(1.2, 1e-9));
      expect(r.high, closeTo(1.8, 1e-9));
      expect(r.format(), '+1.2 tot +1.8 mmol/L');
    });

    test('insuline trekt de stijging omlaag', () {
      final r = predictGlucoseImpact(carbs: 60, context: MealContext.recovery, insulinUnits: 3, correctionFactor: 2);
      expect(r.low, closeTo(0, 1e-9));
    });

    test('context round-trip naar de database-waarde', () {
      for (final c in MealContext.values) {
        expect(MealContext.fromName(c.dbName), c);
      }
      expect(MealContext.fromName(null), isNull);
    });
  });

  group('gewichtsplan', () {
    test('veilig afvallen binnen de corridor', () {
      final p = WeightPlan(currentKg: 78.4, targetKg: 77.0, now: now, weighDay: now.add(const Duration(days: 18)));
      expect(p.direction, WeightDirection.lose);
      expect(p.deltaKg, -1.4);
      expect(p.isSafe, isTrue);
    });

    test('te snel afvallen is onveilig', () {
      final p = WeightPlan(currentKg: 82, targetKg: 77, now: now, weighDay: now.add(const Duration(days: 14)));
      expect(p.isSafe, isFalse);
    });

    test('+88 klasse onder de grens = aankomen', () {
      final p = WeightPlan(currentKg: 86.7, targetKg: 88, now: now, weighDay: now.add(const Duration(days: 4)));
      expect(p.direction, WeightDirection.gain);
    });
  });

  group('sparring-timer', () {
    const config = SparringConfig(rounds: 3, workSeconds: 300, restSeconds: 60);

    test('telt af op wandklok en gaat vanzelf naar rust', () {
      final t = SparringTimer(config: config, now: now);
      expect(t.remaining(now), 300);
      expect(t.remaining(now.add(const Duration(seconds: 102))), 198);
      expect(mmss(t.remaining(now.add(const Duration(seconds: 102)))), '03:18');
      expect(t.tick(now.add(const Duration(seconds: 300))), SparringEvent.restStarted);
      expect(t.phase, SparringPhase.rest);
    });

    test('pauze bevriest de tijd', () {
      final t = SparringTimer(config: config, now: now);
      t.pause(now.add(const Duration(seconds: 10)));
      expect(t.remaining(now.add(const Duration(minutes: 30))), 290);
      t.resume(now.add(const Duration(minutes: 30)));
      expect(t.remaining(now.add(const Duration(minutes: 30, seconds: 90))), 200);
    });

    test('rust loopt af naar de volgende ronde, tenzij tegengehouden', () {
      final t = SparringTimer(config: config, now: now)..toRest(now);
      final end = now.add(const Duration(seconds: 60));
      expect(t.tick(end, holdRest: true), SparringEvent.restHeld);
      expect(t.restHeld, isTrue);
      expect(t.tick(end.add(const Duration(seconds: 5))), isNull);
      t.startNextRound(end);
      expect(t.round, 2);
      expect(t.phase, SparringPhase.work);
    });

    test('+30s rust, ook na het aflopen', () {
      final t = SparringTimer(config: config, now: now)..toRest(now);
      t.addRest(30, now);
      expect(t.remaining(now), 90);
      final later = now.add(const Duration(seconds: 200));
      t.addRest(30, later);
      expect(t.remaining(later), 30);
    });

    test('laatste ronde → klaar', () {
      final t = SparringTimer(config: const SparringConfig(rounds: 1), now: now);
      expect(t.tick(now.add(const Duration(minutes: 5))), SparringEvent.finished);
      expect(t.isDone, isTrue);
    });

    test('json round-trip (herstel na app-kill)', () {
      final t = SparringTimer(config: config, now: now)
        ..toRest(now)
        ..pause(now.add(const Duration(seconds: 20)));
      final r = SparringTimer.fromJson(t.toJson());
      expect(r.phase, SparringPhase.rest);
      expect(r.isPaused, isTrue);
      expect(r.remaining(now.add(const Duration(hours: 1))), 40);
      expect(r.config.rounds, 3);
    });
  });

  group('technieken', () {
    test('categorie → groep', () {
      expect(TechniqueGroup.fromCategory('Takedown'), TechniqueGroup.throws);
      expect(TechniqueGroup.fromCategory('Submission'), TechniqueGroup.submissions);
      expect(TechniqueGroup.fromCategory('Low calf kick'), TechniqueGroup.striking);
      expect(TechniqueGroup.fromCategory('Sprawl verdediging'), TechniqueGroup.defense);
      expect(TechniqueGroup.fromCategory('Overig'), TechniqueGroup.other);
    });

    test('mastery en bag volume uit de updates-historie', () {
      final t = Technique.fromJson({
        'id': 'a',
        'name': 'Harai Goshi',
        'category': 'Takedown',
        'focus_mode': 'none',
        'practice_next': true,
        'updates': [
          {'at': '2026-11-01T10:00:00Z', 'rating': 4, 'positions': [{'reps': 20}]},
          {'at': '2026-11-02T10:00:00Z', 'rating': 5, 'positions': [{'reps': 30}]},
          {'at': '2026-11-03T10:00:00Z', 'rating': 0, 'note': 'alleen notitie'},
        ],
      });
      expect(t.masteryPercent, 90);
      expect(t.loggedReps, 50);
      expect(t.isInFocus, isTrue, reason: 'oude practice_next telt als focus');
    });

    test('tellers kunnen niet onder nul', () {
      const c = TechniqueCounts();
      expect(c.add(TechniqueStat.success, -1).success, 0);
      expect(c.add(TechniqueStat.attempt, 1).add(TechniqueStat.attempt, 1).attempts, 2);
    });
  });

  test('formatters', () {
    expect(durationLabel(525), '8u 45m');
    expect(thousands(2450), '2.450');
    expect(grams(15), '15');
    expect(grams(12.5), '12.5');
    expect(daysUntil(DateTime(2026, 11, 28, 9), now: now), 4);
  });
}

