import 'package:flutter_test/flutter_test.dart';
import 'package:kinetic/core/session_times.dart';
import 'package:kinetic/models/agenda.dart';
import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/models/technique.dart';
import 'package:kinetic/services/agenda_notification_service.dart';

void main() {
  group('van/tot en duur', () {
    final start = DateTime(2026, 10, 20, 19, 0);

    test('tot bepaalt de duur, ook over middernacht', () {
      expect(durationUntil(start, 20, 30), 90);
      expect(durationUntil(start, 19, 0), 0);
      expect(durationUntil(DateTime(2026, 10, 20, 23, 30), 0, 15), 45);
    });

    test('duur schuift de tot-tijd, van verschuift de start', () {
      expect(endFor(start, 105), DateTime(2026, 10, 20, 20, 45));
      expect(withTime(start, 18, 15), DateTime(2026, 10, 20, 18, 15));
      expect(timeRangeLabel(start, 90), '19:00–20:30');
      expect(timeRangeLabel(start, null), '19:00');
    });
  });

  group('PlannedTraining', () {
    test('duur, technieken en herinneringen via JSON', () {
      final t = PlannedTraining(
        id: 'p1',
        startsAt: DateTime(2026, 10, 20, 19),
        durationMinutes: 90,
        techniqueIds: const ['t1', 't2'],
        techniqueReminders: const [0, 60, 60, -5],
      );
      final json = t.toJson();
      expect(json['duration_minutes'], 90);
      expect(json['technique_ids'], ['t1', 't2']);
      // Geen dubbele, vroegste eerst; negatief = tijdens de training.
      expect(json['technique_reminders'], [60, 0, -5]);
      final back = PlannedTraining.fromJson({
        'id': 'p1',
        ...json,
        'starts_at': t.startsAt.toUtc().toIso8601String(),
      });
      expect(back.endsAt, DateTime(2026, 10, 20, 20, 30));
      expect(back.techniqueReminders, [60, 0, -5]);
      expect(normalizeReminders([-30, -99999]), [-30]);
    });

    test('oude rijen zonder de nieuwe kolommen', () {
      final t = PlannedTraining.fromJson({
        'id': 'p',
        'starts_at': '2026-10-20T17:00:00Z',
      });
      expect(t.durationMinutes, isNull);
      expect(t.endsAt, isNull);
      expect(t.techniqueIds, isEmpty);
    });

    test('labels', () {
      expect(reminderLabel(0), 'bij de start');
      expect(reminderLabel(15), '15 min vooraf');
      expect(reminderLabel(60), '1 uur vooraf');
      expect(reminderLabel(90), '1 uur 30 min vooraf');
      expect(reminderLabel(1440), '1 dag vooraf');
      expect(reminderLabel(-15), '15 min na de start');
      expect(reminderLabel(-60), '1 uur na de start');
    });
  });

  group('techniek-herinneringen', () {
    final now = DateTime(2026, 10, 20, 12);
    final sambo = PlannedTraining(
      id: 'a',
      startsAt: DateTime(2026, 10, 20, 19),
      title: 'Sparren',
      techniqueIds: const ['t1'],
      techniqueReminders: const [60, 0],
    );
    final kracht = PlannedTraining(
      id: 'b',
      startsAt: DateTime(2026, 10, 21, 18),
      kind: TrainingKind.kracht,
    );
    const names = {'t1': 'Uchi mata', 't2': 'Armklem'};

    List<ScheduledAgendaNotification> plan(
      TechniqueReminderInput input, {
      List<PlannedTraining>? trainings,
    }) => planAgendaNotifications(
      trainings: trainings ?? [sambo, kracht],
      competitions: const [],
      now: now,
      techniques: input,
    ).where((n) => n.techniqueSound != null).toList();

    test('per herinnering een melding, met geluid naar keuze', () {
      final result = plan(
        const TechniqueReminderInput(names: names, withSound: true),
      );
      expect(result.map((n) => n.at), [
        DateTime(2026, 10, 20, 18),
        DateTime(2026, 10, 20, 19),
      ]);
      expect(result.map((n) => n.id), [46000, 46001]);
      expect(result.first.body, 'Uchi mata');
      expect(result.last.title, 'Nu oefenen: Uchi mata');
      expect(result.every((n) => n.techniqueSound == true), isTrue);
      expect(result.every((n) => !n.at.isAfter(sambo.startsAt)), isTrue);
    });

    test('eerstvolgende training: bij de eerste sambo-training, met standaardmomenten', () {
      final result = plan(
        const TechniqueReminderInput(
          names: names,
          practiceNextIds: ['t2'],
          defaultReminders: [30],
        ),
        trainings: [
          kracht,
          sambo.copyWith(techniqueIds: const [], techniqueReminders: const []),
        ],
      );
      expect(result, hasLength(1));
      expect(result.single.at, DateTime(2026, 10, 20, 18, 30));
      expect(result.single.body, 'Armklem');
      expect(result.single.techniqueSound, isFalse);
    });

    test('tijdens de training, maar nooit na de eindtijd', () {
      final result = plan(
        const TechniqueReminderInput(names: names),
        trainings: [
          sambo.copyWith(
            durationMinutes: 60,
            techniqueReminders: const [0, -15, -45, -90],
          ),
        ],
      );
      expect(result.map((n) => n.at), [
        DateTime(2026, 10, 20, 19),
        DateTime(2026, 10, 20, 19, 15),
        DateTime(2026, 10, 20, 19, 45),
      ]);
      expect(result[1].title, 'Nu oefenen: Uchi mata');
      expect(result[1].body, 'Sparren is 15 min bezig.');
    });

    test('uit = geen techniek-meldingen; voorbije momenten vallen weg', () {
      expect(
        plan(const TechniqueReminderInput(names: names, enabled: false)),
        isEmpty,
      );
      final late = planAgendaNotifications(
        trainings: [sambo],
        competitions: const [],
        now: DateTime(2026, 10, 20, 18, 30),
        techniques: const TechniqueReminderInput(names: names),
      ).where((n) => n.techniqueSound != null);
      expect(late.map((n) => n.at), [DateTime(2026, 10, 20, 19)]);
    });
  });

  test('profiel en techniek: nieuwe velden', () {
    final p = AppProfile.fromJson({
      ...AppProfile.defaults('u').toJson(),
      'technique_reminder_defaults': [0, 120, 0],
      'technique_reminder_sound': true,
    });
    expect(p.techniqueReminderDefaults, [120, 0]);
    expect(p.techniqueReminderSound, isTrue);
    expect(p.techniqueRemindersEnabled, isTrue);
    final t = Technique.fromJson({
      'id': 'x',
      'name': 'Uchi mata',
      'practice_next': true,
    });
    expect(t.practiceNext, isTrue);
    expect(t.copyWith(practiceNext: false).practiceNext, isFalse);
  });
}
