// weigh_in_and_step_videos_test.dart — volgende weegdatum en het moment
// van de herinnering, video's per circuitstap in de JSON, en de nieuwe
// profielinstellingen (sluimertijd, standaardrust, weeginterval).

import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/weigh_in_plan.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/circuit.dart';
import 'package:kinetic/models/weigh_in.dart';

void main() {
  group('nextWeighIn', () {
    final now = DateTime(2026, 10, 20, 12);

    test('geen interval: geen volgende weging', () {
      expect(
        nextWeighIn(
          last: DateTime(2026, 10, 18),
          intervalDays: 0,
          reminderTime: '08:00',
          now: now,
        ),
        isNull,
      );
    });

    test('nog nooit gewogen: vandaag op het tijdstip', () {
      expect(
        nextWeighIn(
          last: null,
          intervalDays: 7,
          reminderTime: '08:00',
          now: now,
        ),
        DateTime(2026, 10, 20, 8),
      );
    });

    test('laatste weging + interval, op het tijdstip', () {
      expect(
        nextWeighIn(
          last: DateTime(2026, 10, 18, 21, 15),
          intervalDays: 7,
          reminderTime: '07:30',
          now: now,
        ),
        DateTime(2026, 10, 25, 7, 30),
      );
    });

    test('over de wintertijd heen blijft het uur gelijk', () {
      // 25 oktober 2026 gaat de klok in Europa een uur terug.
      final next = nextWeighIn(
        last: DateTime(2026, 10, 20, 9),
        intervalDays: 7,
        reminderTime: '08:00',
        now: now,
      )!;
      expect(next.hour, 8);
      expect(next.day, 27);
    });
  });

  group('weighInReminderAt', () {
    final now = DateTime(2026, 10, 20, 12);

    test('in de toekomst: precies dan', () {
      final next = DateTime(2026, 10, 25, 8);
      expect(
        weighInReminderAt(next: next, reminderTime: '08:00', now: now),
        next,
      );
    });

    test('te laat en het tijdstip vandaag is al voorbij: morgen', () {
      expect(
        weighInReminderAt(
          next: DateTime(2026, 10, 18, 8),
          reminderTime: '08:00',
          now: now,
        ),
        DateTime(2026, 10, 21, 8),
      );
    });

    test('te laat maar het tijdstip komt vandaag nog: vandaag', () {
      expect(
        weighInReminderAt(
          next: DateTime(2026, 10, 18, 18),
          reminderTime: '18:00',
          now: now,
        ),
        DateTime(2026, 10, 20, 18),
      );
    });
  });

  test('WeighIn JSON rondt af op één decimaal', () {
    final json = WeighIn(
      id: '',
      measuredAt: DateTime.utc(2026, 10, 20, 7),
      weightKg: 81.26,
    ).toInsertJson('u1');
    expect(json['weight_kg'], 81.3);
    expect(json['user_id'], 'u1');
  });

  test("video's per circuitstap: heen en terug, en weg als ze leeg zijn", () {
    const step = CircuitStep(
      name: 'Goblet squat',
      reps: 15,
      videoUrls: ['https://youtu.be/abc'],
    );
    final back = CircuitStep.fromJson(step.toJson());
    expect(back.videoUrls, ['https://youtu.be/abc']);
    expect(back.copyWith(name: 'X').videoUrls, ['https://youtu.be/abc']);
    expect(
      const CircuitStep(name: 'Plank', seconds: 30).toJson().containsKey(
        'videos',
      ),
      isFalse,
    );
  });

  test('nieuwe profielinstellingen: standaardwaarden en heen en terug', () {
    final defaults = AppProfile.fromJson(const {'id': 'x'});
    expect(defaults.alarmSnoozeMinutes, 15);
    expect(defaults.defaultRestSeconds, 90);
    expect(defaults.weighInIntervalDays, 7);
    expect(defaults.weighInReminderTime, '08:00');

    final changed = defaults.copyWith(
      alarmSnoozeMinutes: 30,
      defaultRestSeconds: 120,
      weighInIntervalDays: 3,
      weighInReminderTime: '07:15',
    );
    final back = AppProfile.fromJson({...changed.toJson(), 'id': 'x'});
    expect(back.alarmSnoozeMinutes, 30);
    expect(back.defaultRestSeconds, 120);
    expect(back.weighInIntervalDays, 3);
    expect(back.weighInReminderTime, '07:15');
  });
}
