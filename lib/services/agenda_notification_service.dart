// agenda_notification_service.dart — meldingen uit de Agenda:
//   • geplande training: één melding op het ingestelde aantal minuten vóór
//     de start;
//   • wedstrijd: elke dag op het gekozen tijdstip een aftel-melding met
//     motivatie (zie core/competition_plan.dart), tot en met de wedstrijddag.
//
// Bij elke wijziging wordt alles opnieuw ingepland ([sync]): eerst alle
// agenda-meldingen weg, dan opnieuw. Zo blijft er nooit een melding staan
// van een verwijderde of verplaatste training. Eigen id-bereik
// (40000–69999), los van de andere meldingen in de app.

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_router.dart';
import 'notification_style.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/bolus_calculator.dart' show minutesOfDay;
import '../core/competition_plan.dart';
import '../models/agenda.dart';

class AgendaNotificationService {
  AgendaNotificationService._();
  static final AgendaNotificationService instance =
      AgendaNotificationService._();

  static const _trainingChannelId = 'kinetic_planned_training';
  static const _competitionChannelId = 'kinetic_competition_countdown';
  static const _firstTrainingId = 40000;
  static const _firstStartId = 45000;
  static const _firstCompetitionId = 50000;
  static const _lastId = 69999;

  /// Android staat maximaal ~500 geplande alarmen per app toe; ruim daaronder
  /// blijven (de rest van de app plant er ook een paar).
  ///
  /// Drie weken vooruit is genoeg: bij elke keer dat je de app opent schuift
  /// het venster mee. Minder meldingen = minder werk voor de plugin (die bij
  /// elke geplande melding zijn hele lijst opnieuw wegschrijft).
  static const maxDailyPerCompetition = 21;
  static const maxCompetitions = 3;
  static const maxTrainings = 200;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<void> _ensureInit() async {
    if (_initialized) return;
    _initialized = true;
    tz_data.initializeTimeZones();
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_notification'),
        ),
        onDidReceiveNotificationResponse: NotificationRouter.handle,
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _trainingChannelId,
          'Geplande trainingen',
          description: 'Herinnering vóór een geplande training.',
          importance: Importance.high,
        ),
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _competitionChannelId,
          'Wedstrijd-aftelling',
          description:
              'Dagelijks: hoeveel dagen nog tot je wedstrijd, met motivatie.',
          importance: Importance.defaultImportance,
        ),
      );
      await _android?.requestNotificationsPermission();
    } catch (_) {
      // Geen meldingen beschikbaar (bv. in tests of op desktop) — de agenda
      // zelf blijft gewoon werken.
    }
  }

  /// Plant alle agenda-meldingen opnieuw in op basis van de actuele lijsten.
  Future<void> sync({
    required List<PlannedTraining> trainings,
    required List<Competition> competitions,
    DateTime? now,
  }) async {
    final current = now ?? DateTime.now();
    final plan = planAgendaNotifications(
      trainings: trainings,
      competitions: competitions,
      now: current,
    );
    // Niets veranderd sinds de vorige keer? Dan niets opnieuw inplannen —
    // Vandaag en Agenda roepen dit bij elk laden aan, en alles wissen en
    // opnieuw plannen kost Android merkbaar tijd (de app hapert dan).
    final signature = [
      for (final p in plan)
        '${p.id}|${p.at.millisecondsSinceEpoch}|${p.title}|${p.body}|${p.payload}',
    ].join('|#|');
    if (signature == _lastSignature) return;
    await _ensureInit();
    try {
      final pending = await _plugin.pendingNotificationRequests();
      for (final p in pending) {
        if (p.id >= _firstTrainingId && p.id <= _lastId) {
          await _plugin.cancel(id: p.id);
        }
      }
    } catch (_) {
      return;
    }

    for (final s in plan) {
      await _schedule(s);
    }
    _lastSignature = signature;
  }

  /// Wat de vorige [sync] heeft ingepland (in deze app-sessie).
  String? _lastSignature;

  Future<void> _schedule(ScheduledAgendaNotification s) async {
    final isTraining = s.id < _firstCompetitionId;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        color: kNotificationColor,
        isTraining ? _trainingChannelId : _competitionChannelId,
        isTraining ? 'Geplande trainingen' : 'Wedstrijd-aftelling',
        importance: isTraining ? Importance.high : Importance.defaultImportance,
        priority: isTraining ? Priority.high : Priority.defaultPriority,
        styleInformation: BigTextStyleInformation(s.body),
        actions: s.startAction
            ? const [
                AndroidNotificationAction(
                  kStartTrainingActionId,
                  'Start training',
                  showsUserInterface: true,
                  cancelNotification: true,
                ),
              ]
            : null,
      ),
    );
    Future<void> plan(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: s.id,
      title: s.title,
      body: s.body,
      scheduledDate: tz.TZDateTime.from(s.at, tz.UTC),
      notificationDetails: details,
      androidScheduleMode: mode,
      payload: s.payload,
    );
    try {
      // Trainingen precies op tijd; lukt dat niet (geen toestemming voor
      // exacte alarmen), dan inexact — de dagelijkse aftelling is altijd
      // inexact, een paar minuten speling maakt daar niet uit.
      await plan(
        isTraining
            ? AndroidScheduleMode.exactAllowWhileIdle
            : AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {
      try {
        await plan(AndroidScheduleMode.inexactAllowWhileIdle);
      } catch (_) {
        // Niet blokkerend.
      }
    }
  }

  /// Vraagt toestemming voor exacte alarmen (Android 12-13), alleen op het
  /// moment dat je zelf een trainingsmelding instelt.
  Future<void> requestExactAlarmPermissionIfNeeded() async {
    await _ensureInit();
    try {
      await _android?.requestExactAlarmsPermission();
    } catch (_) {}
  }
}

class ScheduledAgendaNotification {
  final int id;
  final DateTime at;
  final String title;
  final String body;

  /// Meegegeven aan de melding (zie NotificationRouter).
  final String? payload;

  /// Toont de knop "Start training".
  final bool startAction;

  const ScheduledAgendaNotification(
    this.id,
    this.at,
    this.title,
    this.body, {
    this.payload,
    this.startAction = false,
  });
}

/// Welke meldingen er ingepland moeten worden — puur, zodat de planning
/// zonder plugin te testen is. Alleen momenten in de toekomst.
List<ScheduledAgendaNotification> planAgendaNotifications({
  required List<PlannedTraining> trainings,
  required List<Competition> competitions,
  required DateTime now,
}) {
  final result = <ScheduledAgendaNotification>[];

  final upcomingTrainings =
      trainings.where((t) => t.remindAt?.isAfter(now) ?? false).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  for (var i = 0;
      i < upcomingTrainings.length &&
          i < AgendaNotificationService.maxTrainings;
      i++) {
    final t = upcomingTrainings[i];
    final hh = t.startsAt.hour.toString().padLeft(2, '0');
    final mm = t.startsAt.minute.toString().padLeft(2, '0');
    result.add(
      ScheduledAgendaNotification(
        AgendaNotificationService._firstTrainingId + i,
        t.remindAt!,
        '${t.displayTitle} om $hh:$mm',
        [
          if (t.location.trim().isNotEmpty) t.location.trim(),
          if (t.note.trim().isNotEmpty) t.note.trim(),
          if (t.location.trim().isEmpty && t.note.trim().isEmpty)
            'Tijd om je spullen te pakken.',
        ].join(' · '),
      ),
    );
  }

  // Op het starttijdstip: melding met "Start training" (sambo en kracht).
  final toStart =
      trainings
          .where(
            (t) =>
                t.startsAt.isAfter(now) &&
                (t.kind.isSambo || t.kind == TrainingKind.kracht),
          )
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  for (var i = 0;
      i < toStart.length && i < AgendaNotificationService.maxTrainings;
      i++) {
    final t = toStart[i];
    result.add(
      ScheduledAgendaNotification(
        AgendaNotificationService._firstStartId + i,
        t.startsAt,
        '${t.displayTitle} begint',
        'Tik op "Start training" om je sessie meteen te starten.',
        payload: PlannedStartRequest.payloadFor(t),
        startAction: true,
      ),
    );
  }

  final upcomingComps =
      competitions
          .where((c) => c.dailyReminder && daysUntil(c.startsAt, now) >= 0)
          .toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
  for (var c = 0;
      c < upcomingComps.length && c < AgendaNotificationService.maxCompetitions;
      c++) {
    final comp = upcomingComps[c];
    final minutes = minutesOfDay(comp.reminderTime);
    final today = DateTime(now.year, now.month, now.day);
    final totalDays = daysUntil(comp.startsAt, now);
    var slot = 0;
    for (var d = 0;
        d <= totalDays && slot < AgendaNotificationService.maxDailyPerCompetition;
        d++) {
      final day = DateTime(today.year, today.month, today.day + d);
      final at = DateTime(
        day.year,
        day.month,
        day.day,
        minutes ~/ 60,
        minutes % 60,
      );
      if (!at.isAfter(now)) continue;
      final msg = dailyMessage(comp, day);
      result.add(
        ScheduledAgendaNotification(
          AgendaNotificationService._firstCompetitionId + c * 100 + slot,
          at,
          msg.title,
          msg.body,
        ),
      );
      slot++;
    }
  }
  return result;
}
