// notification_router.dart — één plek die reageert op een tik op een
// melding (of op de knop "Start training"). Alle services initialiseren
// dezelfde plugin-instantie; elke initialize() vervangt de callback, dus ze
// geven allemaal [NotificationRouter.handle] mee — anders zou de laatste
// service de afhandeling van de andere wissen.
//
// De shell luistert naar [NotificationRouter.pendingStart] en start dan de
// geplande training (of opent Vandaag).

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/agenda.dart';

/// Id van de actieknop in de startmelding.
const kStartTrainingActionId = 'start_training';

/// Id van de knop "Sluimeren" in de glucose-alarmmelding.
const kSnoozeAlarmActionId = 'snooze_alarm';

/// Verzoek om het glucose-alarm te sluimeren, uit de alarmmelding.
class AlarmSnoozeRequest {
  final bool isHigh;
  final double mmol;
  const AlarmSnoozeRequest({required this.isHigh, required this.mmol});

  /// Payload voor in de alarmmelding.
  static String payloadFor({required bool isHigh, required double mmol}) =>
      jsonEncode({'type': 'glucose_alarm', 'high': isHigh, 'mmol': mmol});

  /// Null als de payload niet van een alarmmelding is.
  static AlarmSnoozeRequest? tryParse(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final map = jsonDecode(payload);
      if (map is! Map || map['type'] != 'glucose_alarm') return null;
      return AlarmSnoozeRequest(
        isHigh: map['high'] == true,
        mmol: (map['mmol'] as num?)?.toDouble() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Verzoek om een geplande training te starten, uit een melding.
class PlannedStartRequest {
  final String trainingId;
  final TrainingKind kind;
  final String title;

  /// Waar = de knop "Start training" (meteen starten); onwaar = gewoon op
  /// de melding getikt (Vandaag openen, waar de startkaart staat).
  final bool startNow;

  const PlannedStartRequest({
    required this.trainingId,
    required this.kind,
    required this.title,
    this.startNow = false,
  });

  /// Payload voor in de melding.
  static String payloadFor(PlannedTraining t) => jsonEncode({
    'type': 'start_training',
    'id': t.id,
    'kind': t.kind.dbName,
    'title': t.displayTitle,
  });

  /// Null als de payload niet van een startmelding is.
  static PlannedStartRequest? tryParse(
    String? payload, {
    bool startNow = false,
  }) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final map = jsonDecode(payload);
      if (map is! Map || map['type'] != 'start_training') return null;
      return PlannedStartRequest(
        trainingId: (map['id'] as String?) ?? '',
        kind: TrainingKind.fromName(map['kind'] as String?),
        title: (map['title'] as String?) ?? '',
        startNow: startNow,
      );
    } catch (_) {
      return null;
    }
  }
}

class NotificationRouter {
  NotificationRouter._();

  /// Het laatste startverzoek; de shell zet hem na afhandeling op null.
  static final ValueNotifier<PlannedStartRequest?> pendingStart = ValueNotifier(
    null,
  );

  /// Het laatste sluimerverzoek; AppController zet hem na afhandeling op
  /// null.
  static final ValueNotifier<AlarmSnoozeRequest?> pendingSnooze = ValueNotifier(
    null,
  );

  /// Doorgeven als `onDidReceiveNotificationResponse` bij élke initialize().
  static void handle(NotificationResponse response) {
    if (response.actionId == kSnoozeAlarmActionId) {
      final snooze = AlarmSnoozeRequest.tryParse(response.payload);
      if (snooze != null) pendingSnooze.value = snooze;
      return;
    }
    final request = PlannedStartRequest.tryParse(
      response.payload,
      startNow: response.actionId == kStartTrainingActionId,
    );
    if (request != null) pendingStart.value = request;
  }

  /// Was de app dicht en is hij geopend via een melding? Dan dat verzoek
  /// alsnog afhandelen (de callback hierboven komt dan niet).
  static Future<void> checkLaunchDetails() async {
    try {
      final details = await FlutterLocalNotificationsPlugin()
          .getNotificationAppLaunchDetails();
      final response = details?.notificationResponse;
      if (details?.didNotificationLaunchApp == true && response != null) {
        handle(response);
      }
    } catch (_) {
      // Geen meldingen-plugin beschikbaar (tests/desktop).
    }
  }
}
