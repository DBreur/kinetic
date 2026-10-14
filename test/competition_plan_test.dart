import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/core/competition_plan.dart';
import 'package:kinetic/models/agenda.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kinetic/services/agenda_notification_service.dart';
import 'package:kinetic/services/notification_router.dart';

void main() {
  final now = DateTime(2026, 10, 14, 9, 30);

  Competition comp({
    required DateTime at,
    Discipline discipline = Discipline.sport,
    bool daily = true,
    String time = '08:00',
    String name = 'NK Sport Sambo',
  }) => Competition(
    id: name,
    name: name,
    startsAt: at,
    discipline: discipline,
    dailyReminder: daily,
    reminderTime: time,
  );

  group('daysUntil', () {
    test('telt kalenderdagen, tijdstip doet er niet toe', () {
      expect(daysUntil(DateTime(2026, 10, 14, 23, 59), now), 0);
      expect(daysUntil(DateTime(2026, 10, 15, 0, 1), now), 1);
      expect(daysUntil(DateTime(2026, 10, 13, 20), now), -1);
    });

    test('over de wintertijdwissel heen (25 okt) geen dag verschil', () {
      expect(daysUntil(DateTime(2026, 10, 28, 10), now), 14);
    });
  });

  test('fases volgen de aftelling', () {
    expect(phaseFor(-1), CompetitionPhase.done);
    expect(phaseFor(0), CompetitionPhase.competitionDay);
    expect(phaseFor(3), CompetitionPhase.competitionWeek);
    expect(phaseFor(4), CompetitionPhase.taper);
    expect(phaseFor(14), CompetitionPhase.taper);
    expect(phaseFor(15), CompetitionPhase.preparation);
    expect(phaseFor(56), CompetitionPhase.preparation);
    expect(phaseFor(57), CompetitionPhase.buildUp);
  });

  test('volgende wedstrijd: vandaag telt mee, voorbije niet', () {
    final past = comp(at: DateTime(2026, 10, 1), name: 'Oud');
    final today = comp(at: DateTime(2026, 10, 14, 18), name: 'Vandaag');
    final later = comp(at: DateTime(2026, 12, 1), name: 'Later');
    expect(nextCompetition([later, past, today], now)!.name, 'Vandaag');
    expect(nextCompetition([past], now), isNull);
  });

  group('disciplineregel', () {
    final sport = comp(at: DateTime(2026, 11, 1));
    test('sport sambo: combat-training ervoor is een conflict', () {
      expect(
        conflictsWithCompetition(
          TrainingKind.combatSambo,
          DateTime(2026, 10, 20),
          sport,
        ),
        isTrue,
      );
      expect(
        conflictsWithCompetition(
          TrainingKind.sportSambo,
          DateTime(2026, 10, 20),
          sport,
        ),
        isFalse,
      );
      expect(
        conflictsWithCompetition(
          TrainingKind.kracht,
          DateTime(2026, 10, 20),
          sport,
        ),
        isFalse,
      );
    });

    test('na de wedstrijd geen conflict meer', () {
      expect(
        conflictsWithCompetition(
          TrainingKind.combatSambo,
          DateTime(2026, 11, 2),
          sport,
        ),
        isFalse,
      );
    });

    test('beide disciplines: geen beperking', () {
      expect(disciplineReminder(Discipline.both), isNull);
      expect(
        conflictsWithCompetition(
          TrainingKind.combatSambo,
          DateTime(2026, 10, 20),
          comp(at: DateTime(2026, 11, 1), discipline: Discipline.both),
        ),
        isFalse,
      );
    });
  });

  test('dagelijkse melding: titel per aftelling, regel bij sport sambo', () {
    final c = comp(at: DateTime(2026, 10, 26, 10));
    final msg = dailyMessage(c, DateTime(2026, 10, 14));
    expect(msg.title, 'Nog 12 dagen tot NK Sport Sambo');
    expect(msg.body, contains('Toespitsen'));
    expect(msg.body, contains('Alleen sport sambo trainen.'));
    expect(dailyMessage(c, DateTime(2026, 10, 25)).title, 'Morgen: NK Sport Sambo');
    expect(dailyMessage(c, DateTime(2026, 10, 26)).title, 'Vandaag: NK Sport Sambo');
  });

  test('motivatie is per dag vast en wisselt tussen dagen', () {
    final a = motivationFor(DateTime(2026, 10, 14));
    expect(motivationFor(DateTime(2026, 10, 14, 23)), a);
    final week = {
      for (var d = 0; d < 7; d++) motivationFor(DateTime(2026, 10, 14 + d)),
    };
    expect(week.length, greaterThan(1));
  });

  group('planAgendaNotifications', () {
    test('training: melding op x minuten vooraf, alleen toekomst', () {
      final plan = planAgendaNotifications(
        now: now,
        competitions: const [],
        trainings: [
          PlannedTraining(
            id: 'a',
            startsAt: DateTime(2026, 10, 15, 19),
            remindMinutesBefore: 60,
            location: 'Dynamo',
          ),
          PlannedTraining(
            id: 'b',
            startsAt: DateTime(2026, 10, 14, 10),
            remindMinutesBefore: 60, // 9:00 — al voorbij
          ),
          PlannedTraining(id: 'c', startsAt: DateTime(2026, 10, 16, 19)),
        ],
      );
      final reminders = plan.where((p) => !p.startAction).toList();
      expect(reminders.length, 1);
      expect(reminders.single.at, DateTime(2026, 10, 15, 18));
      expect(reminders.single.title, 'Sport sambo om 19:00');
      expect(reminders.single.body, 'Dynamo');
    });

    test('wedstrijd: elke dag een melding tot en met de wedstrijddag', () {
      final plan = planAgendaNotifications(
        now: now, // 9:30, dus vandaag 08:00 is al voorbij
        trainings: const [],
        competitions: [comp(at: DateTime(2026, 10, 18, 10))],
      );
      expect(plan.map((p) => p.at.day).toList(), [15, 16, 17, 18]);
      expect(plan.map((p) => p.id).toSet().length, plan.length);
      expect(plan.last.title, 'Vandaag: NK Sport Sambo');
    });

    test('wedstrijd zonder dagelijkse melding of ver weg is begrensd', () {
      expect(
        planAgendaNotifications(
          now: now,
          trainings: const [],
          competitions: [comp(at: DateTime(2026, 10, 18), daily: false)],
        ),
        isEmpty,
      );
      final far = planAgendaNotifications(
        now: now,
        trainings: const [],
        competitions: [comp(at: DateTime(2027, 6, 1))],
      );
      expect(far.length, AgendaNotificationService.maxDailyPerCompetition);
    });
  });

  test('modellen overleven toJson/fromJson', () {
    final t = PlannedTraining(
      id: 'x',
      startsAt: DateTime(2026, 10, 15, 19),
      kind: TrainingKind.combatSambo,
      title: 'Sparren',
      remindMinutesBefore: 30,
    );
    final t2 = PlannedTraining.fromJson({...t.toJson(), 'id': 'x'});
    expect(t2.kind, TrainingKind.combatSambo);
    expect(t2.remindMinutesBefore, 30);
    expect(t2.startsAt, t.startsAt);

    final c = Competition(
      id: 'c',
      name: 'Open',
      startsAt: DateTime(2026, 11, 1, 10),
      discipline: Discipline.combat,
      resultPlace: 2,
      resultWins: 3,
      resultLosses: 1,
    );
    final c2 = Competition.fromJson({...c.toJson(), 'id': 'c'});
    expect(c2.discipline, Discipline.combat);
    expect(c2.hasResult, isTrue);
    expect(c2.resultWins, 3);
  });

  group('geplande training starten', () {
    PlannedTraining t(String id, DateTime at, [TrainingKind k = TrainingKind.sportSambo]) =>
        PlannedTraining(id: id, startsAt: at, kind: k, title: 'Training $id');

    test('startmelding met knop op het begin, alleen sambo/kracht in de toekomst', () {
      final plan = planAgendaNotifications(
        now: now,
        competitions: const [],
        trainings: [
          t('a', DateTime(2026, 10, 15, 19)),
          t('b', DateTime(2026, 10, 15, 20), TrainingKind.overig),
          t('c', DateTime(2026, 10, 14, 9)), // voorbij
          t('d', DateTime(2026, 10, 16, 7), TrainingKind.kracht),
        ],
      ).where((p) => p.startAction).toList();
      expect(plan.map((p) => p.at), [
        DateTime(2026, 10, 15, 19),
        DateTime(2026, 10, 16, 7),
      ]);
      expect(plan.first.title, 'Training a begint');
      final req = PlannedStartRequest.tryParse(plan.last.payload, startNow: true)!;
      expect(req.trainingId, 'd');
      expect(req.kind, TrainingKind.kracht);
      expect(req.title, 'Training d');
      expect(req.startNow, isTrue);
    });

    test('startvenster: 15 min ervoor tot 60 min erna, dichtstbijzijnde wint', () {
      final list = [
        t('vroeg', DateTime(2026, 10, 14, 9, 0)),
        t('later', DateTime(2026, 10, 14, 9, 40)),
      ];
      expect(plannedToStartNow(list, DateTime(2026, 10, 14, 8, 40)), isNull);
      expect(plannedToStartNow(list, DateTime(2026, 10, 14, 8, 50))!.id, 'vroeg');
      expect(plannedToStartNow(list, DateTime(2026, 10, 14, 9, 30))!.id, 'later');
      expect(
        plannedToStartNow(list, DateTime(2026, 10, 14, 9, 30), alreadyStarted: {'later'})!.id,
        'vroeg',
      );
      expect(plannedToStartNow(list, DateTime(2026, 10, 14, 10, 50)), isNull);
      expect(
        plannedToStartNow([t('x', DateTime(2026, 10, 14, 9), TrainingKind.overig)],
            DateTime(2026, 10, 14, 9)),
        isNull,
      );
    });

    test('router: knop = meteen starten, tik op melding = Vandaag openen', () {
      final payload = PlannedStartRequest.payloadFor(t('a', DateTime(2026, 10, 15, 19)));
      NotificationRouter.handle(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotificationAction,
        actionId: kStartTrainingActionId,
        payload: payload,
      ));
      expect(NotificationRouter.pendingStart.value!.startNow, isTrue);
      NotificationRouter.handle(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: payload,
      ));
      expect(NotificationRouter.pendingStart.value!.startNow, isFalse);
      NotificationRouter.pendingStart.value = null;
      NotificationRouter.handle(NotificationResponse(
        notificationResponseType: NotificationResponseType.selectedNotification,
        payload: 'iets anders',
      ));
      expect(NotificationRouter.pendingStart.value, isNull);
    });
  });
}
